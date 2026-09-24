require "import"
import "android.app.AlertDialog"
import "android.content.Context"
import "android.content.DialogInterface"
import "android.content.ClipData"
import "android.content.ClipboardManager"
import "android.widget.*"
import "android.view.View"
import "android.view.WindowManager"
import "android.view.Gravity"
import "android.os.Handler"
import "android.os.Looper"
import "java.lang.Thread"
import "java.lang.Runnable"
import "java.lang.String"
import "java.net.URL"
import "java.net.URLEncoder"
import "java.net.HttpURLConnection"
import "java.io.BufferedReader"
import "java.io.InputStreamReader"
import "org.json.JSONObject"
import "org.json.JSONArray"

local konteks = this or service
local CURRENT_VERSION = "v3.0"
local UPDATE_URL = "https://raw.githubusercontent.com/novanblind/Google-Terjemahan-multi-mesin/main/Terjemahan.lua"

-- Nama SharedPreferences unik khusus script ini
local PREF_NAME = "novan_google_terjemahan_multimesin_prefs_2026"
local PREF_KEY_ENGINE = "pref_engine"
local PREF_KEY_GROQ_KEY = "pref_groq_key"
local PREF_KEY_GEMINI_KEY = "pref_gemini_key"
local PREF_KEY_SRC = "pref_src_lang"
local PREF_KEY_TGT = "pref_tgt_lang"

-- 3 Model Groq Teks Terbaik
local GROQ_MODELS = {
    "qwen/qwen3.8-27b",
    "openai/gpt-oss-20b",
    "openai/gpt-oss-120b"
}

-- Model Gemini Khusus Varian Flash-Lite
local GEMINI_MODELS = {
    "gemini-2.5-flash-lite",
    "gemini-flash-lite-latest",
    "gemini-3.1-flash-lite",
    "gemini-3.1-flash-lite-preview",
    "gemini-3.5-flash-lite"
}

-- Daftar Pilihan Bahasa
local LANGUAGE_LIST = {
    {name = "Deteksi Otomatis", code = "auto"},
    {name = "Indonesia", code = "id"},
    {name = "Inggris", code = "en"},
    {name = "Jawa", code = "jw"},
    {name = "Sunda", code = "su"},
    {name = "Arab", code = "ar"},
    {name = "Jepang", code = "ja"},
    {name = "Korea", code = "ko"},
    {name = "Mandarin", code = "zh-CN"},
    {name = "Spanyol", code = "es"},
    {name = "Prancis", code = "fr"},
    {name = "Jerman", code = "de"},
    {name = "Rusia", code = "ru"},
    {name = "Belanda", code = "nl"},
    {name = "Turki", code = "tr"}
}

----------------------------------------------------------------
-- Pengelolaan SharedPreferences
----------------------------------------------------------------
local function getPrefString(key, defaultVal)
    local val = defaultVal
    pcall(function()
        local sp = konteks.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        val = sp.getString(key, defaultVal)
    end)
    return val or defaultVal
end

local function setPrefString(key, val)
    pcall(function()
        local sp = konteks.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        local editor = sp.edit()
        editor.putString(key, tostring(val))
        editor.apply()
    end)
end

----------------------------------------------------------------
-- Utilitas Aksesibilitas (TTS, Toast, Window Overlay, Jaringan)
----------------------------------------------------------------
local function speakText(txt)
    if not txt or txt == "" then return end
    pcall(function()
        if service and service.speak then
            service.speak(txt)
        elseif this and this.speak then
            this.speak(txt)
        end
    end)
end

local function showToast(msg)
    local handler = Handler(Looper.getMainLooper())
    handler.post(Runnable({
        run = function()
            Toast.makeText(konteks, tostring(msg), Toast.LENGTH_SHORT).show()
        end
    }))
end

local function isConnected()
    local cm = konteks.getSystemService(Context.CONNECTIVITY_SERVICE)
    local activeNetwork = cm and cm.getActiveNetworkInfo()
    return activeNetwork ~= nil and activeNetwork.isConnected()
end

local function copyToClipboard(txt)
    pcall(function()
        local cm = konteks.getSystemService(Context.CLIPBOARD_SERVICE)
        local clip = ClipData.newPlainText("Terjemahan", txt)
        cm.setPrimaryClip(clip)
        showToast("Teks disalin ke papan klip")
        speakText("Teks terjemahan telah disalin ke papan klip")
    end)
end

local function showSafeDialog(dlg)
    pcall(function()
        local win = dlg.getWindow()
        if win then
            local overlayType = 2032
            if WindowManager and WindowManager.LayoutParams and WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY then
                overlayType = WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
            end
            win.setType(overlayType)
        end
    end)
    dlg.show()
end

----------------------------------------------------------------
-- Fitur Periksa Versi Baru
----------------------------------------------------------------
local function checkUpdate()
    if not isConnected() then
        showToast("Butuh koneksi internet untuk memeriksa versi")
        speakText("Butuh koneksi internet untuk memeriksa versi baru")
        return
    end

    showToast("Memeriksa versi baru...")
    speakText("Memeriksa versi baru")

    Thread(Runnable({
        run = function()
            local success = false
            local remoteCode = nil

            pcall(function()
                local url = URL(UPDATE_URL)
                local conn = url.openConnection()
                conn.setRequestMethod("GET")
                conn.setConnectTimeout(8000)
                conn.setReadTimeout(12000)
                conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
                conn.setRequestProperty("Cache-Control", "no-cache")

                if conn.getResponseCode() == 200 then
                    local reader = BufferedReader(InputStreamReader(conn.getInputStream(), "UTF-8"))
                    local lines = {}
                    local line = reader.readLine()
                    while line ~= nil do
                        table.insert(lines, line)
                        line = reader.readLine()
                    end
                    reader.close()
                    remoteCode = table.concat(lines, "\n")
                    success = true
                end
                conn.disconnect()
            end)

            local handler = Handler(Looper.getMainLooper())
            handler.post(Runnable({
                run = function()
                    if success and remoteCode and #remoteCode > 0 then
                        local remoteVer = remoteCode:match('CURRENT_VERSION%s*=%s*["\']([^"\']+)["\']')
                        if not remoteVer then
                            remoteVer = remoteCode:match('[Vv]ersi%s*([%d%.]+)') or remoteCode:match('v([%d%.]+)')
                        end

                        local hasUpdate = false
                        if remoteVer then
                            if remoteVer ~= CURRENT_VERSION then
                                hasUpdate = true
                            end
                        else
                            remoteVer = "Tersedia di Server"
                            hasUpdate = true
                        end

                        local builder = AlertDialog.Builder(konteks)
                        if hasUpdate then
                            builder.setTitle("Pembaruan Ditemukan!")
                            builder.setMessage("Versi saat ini: " .. CURRENT_VERSION .. "\nVersi baru: " .. tostring(remoteVer) .. "\n\nApakah Anda ingin memperbarui script ini sekarang?")
                            speakText("Pembaruan tersedia versi " .. tostring(remoteVer) .. ". Apakah Anda ingin memperbarui sekarang?")

                            builder.setPositiveButton("Perbarui Sekarang", DialogInterface.OnClickListener({
                                onClick = function(dialog, which)
                                    local scriptPath = nil
                                    pcall(function()
                                        local info = debug.getinfo(1, "S")
                                        if info and info.source and info.source:sub(1, 1) == "@" then
                                            scriptPath = info.source:sub(2)
                                        end
                                    end)

                                    local fileSaved = false
                                    if scriptPath then
                                        pcall(function()
                                            local f = io.open(scriptPath, "w")
                                            if f then
                                                f:write(remoteCode)
                                                f:close()
                                                fileSaved = true
                                            end
                                        end)
                                    end

                                    pcall(function()
                                        local cm = konteks.getSystemService(Context.CLIPBOARD_SERVICE)
                                        local cd = ClipData.newPlainText("Script Update", remoteCode)
                                        cm.setPrimaryClip(cd)
                                    end)

                                    if fileSaved then
                                        showToast("Script berhasil diperbarui ke " .. tostring(remoteVer))
                                        speakText("Script berhasil diperbarui ke versi " .. tostring(remoteVer))
                                    else
                                        showToast("Script baru telah disalin ke papan klip")
                                        speakText("Script baru telah disalin ke papan klip")
                                    end
                                end
                            }))

                            builder.setNegativeButton("Batal", DialogInterface.OnClickListener({
                                onClick = function(dialog, which)
                                    dialog.dismiss()
                                end
                            }))
                        else
                            builder.setTitle("Versi Terbaru")
                            builder.setMessage("Script Anda sudah menggunakan versi paling baru (" .. CURRENT_VERSION .. "). Tidak ada pembaruan.")
                            speakText("Script Anda sudah menggunakan versi paling baru " .. CURRENT_VERSION)
                            builder.setPositiveButton("OK", DialogInterface.OnClickListener({
                                onClick = function(dialog, which)
                                    dialog.dismiss()
                                end
                            }))
                        end
                        showSafeDialog(builder.create())
                    else
                        showToast("Gagal memeriksa versi baru dari server")
                        speakText("Gagal memeriksa versi baru dari server")
                    end
                end
            }))
        end
    })).start()
end

----------------------------------------------------------------
-- Jalur Terjemahan 1: Google Translate (Metode POST Ramah Teks Panjang)
----------------------------------------------------------------
local function translateWithGoogle(text, srcLang, tgtLang, callback)
    Thread(Runnable({
        run = function()
            local resultText = nil
            pcall(function()
                local postDataStr = "client=gtx&sl=" .. srcLang .. "&tl=" .. tgtLang .. "&dt=t&q=" .. URLEncoder.encode(text, "UTF-8")
                local postData = String(postDataStr).getBytes("UTF-8")
                local url = URL("https://translate.googleapis.com/translate_a/single")
                local conn = url.openConnection()
                conn.setRequestMethod("POST")
                conn.setConnectTimeout(10000)
                conn.setReadTimeout(15000)
                conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
                conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8")
                conn.setDoOutput(true)

                local os = conn.getOutputStream()
                os.write(postData)
                os.flush()
                os.close()

                if conn.getResponseCode() == 200 then
                    local reader = BufferedReader(InputStreamReader(conn.getInputStream(), "UTF-8"))
                    local lines = {}
                    local line = reader.readLine()
                    while line ~= nil do
                        table.insert(lines, line)
                        line = reader.readLine()
                    end
                    reader.close()

                    local jsonArray = JSONArray(table.concat(lines, "\n"))
                    local sentences = jsonArray.getJSONArray(0)
                    local out = ""
                    for i = 0, sentences.length() - 1 do
                        local item = sentences.getJSONArray(i)
                        if not item.isNull(0) then
                            out = out .. item.getString(0)
                        end
                    end
                    if out ~= "" then resultText = out end
                end
                conn.disconnect()
            end)

            local handler = Handler(Looper.getMainLooper())
            handler.post(Runnable({
                run = function()
                    callback(resultText ~= nil, resultText or "Gagal memproses terjemahan Google")
                end
            }))
        end
    })).start()
end

----------------------------------------------------------------
-- Jalur Terjemahan 2: Groq AI (Fallback 3 Model & Max Tokens 4096)
----------------------------------------------------------------
local function tryGroqModel(modelIndex, text, tgtLang, apiKey, callback)
    if modelIndex > #GROQ_MODELS then
        callback(false, "Semua model Groq gagal merespons atau limit.")
        return
    end

    local model = GROQ_MODELS[modelIndex]
    local endpoint = "https://api.groq.com/openai/v1/chat/completions"
    local instruction = "You are a professional translator. Translate directly into " .. tgtLang .. ". Return ONLY the translated text without quotes or preamble."

    Thread(Runnable({
        run = function()
            local resultText = nil
            local isSuccess = false
            pcall(function()
                local payload = JSONObject()
                payload.put("model", model)
                payload.put("temperature", 0.2)
                payload.put("max_tokens", 4096)

                local msgs = JSONArray()
                local sObj = JSONObject()
                sObj.put("role", "system")
                sObj.put("content", instruction)
                msgs.put(sObj)

                local uObj = JSONObject()
                uObj.put("role", "user")
                uObj.put("content", text)
                msgs.put(uObj)

                payload.put("messages", msgs)
                local data = String(payload.toString()).getBytes("UTF-8")

                local url = URL(endpoint)
                local conn = url.openConnection()
                conn.setRequestMethod("POST")
                conn.setConnectTimeout(10000)
                conn.setReadTimeout(20000)
                conn.setRequestProperty("Content-Type", "application/json; charset=UTF-8")
                conn.setRequestProperty("Authorization", "Bearer " .. apiKey)
                conn.setDoOutput(true)

                local os = conn.getOutputStream()
                os.write(data)
                os.flush()
                os.close()

                if conn.getResponseCode() == 200 then
                    local reader = BufferedReader(InputStreamReader(conn.getInputStream(), "UTF-8"))
                    local lines = {}
                    local line = reader.readLine()
                    while line ~= nil do
                        table.insert(lines, line)
                        line = reader.readLine()
                    end
                    reader.close()

                    local resJson = JSONObject(table.concat(lines, "\n"))
                    local choices = resJson.optJSONArray("choices")
                    if choices and choices.length() > 0 then
                        local content = choices.getJSONObject(0).optJSONObject("message"):optString("content")
                        if content and content ~= "" then
                            resultText = content:gsub('^%s*"', ''):gsub('"%s*$', ''):gsub("^%s+", ""):gsub("%s+$", "")
                            isSuccess = true
                        end
                    end
                end
                conn.disconnect()
            end)

            local handler = Handler(Looper.getMainLooper())
            handler.post(Runnable({
                run = function()
                    if isSuccess and resultText then
                        callback(true, resultText)
                    else
                        tryGroqModel(modelIndex + 1, text, tgtLang, apiKey, callback)
                    end
                end
            }))
        end
    })).start()
end

----------------------------------------------------------------
-- Jalur Terjemahan 3: Gemini Flash-Lite (Fallback 5 Model & Max Output 8192)
----------------------------------------------------------------
local function tryGeminiModel(modelIndex, text, tgtLang, apiKey, callback)
    if modelIndex > #GEMINI_MODELS then
        callback(false, "Semua model Gemini Flash-Lite gagal merespons.")
        return
    end

    local model = GEMINI_MODELS[modelIndex]
    local endpoint = "https://generativelanguage.googleapis.com/v1beta/models/" .. model .. ":generateContent?key=" .. apiKey

    Thread(Runnable({
        run = function()
            local resultText = nil
            local isSuccess = false
            pcall(function()
                local payload = JSONObject()
                local contents = JSONArray()
                local cObj = JSONObject()
                local parts = JSONArray()
                local pObj = JSONObject()

                local prompt = "You are a professional translator. Translate directly into " .. tgtLang .. ". Return ONLY the translated text without explanations or quotes:\n\n" .. text
                pObj.put("text", prompt)
                parts.put(pObj)
                cObj.put("parts", parts)
                contents.put(cObj)
                payload.put("contents", contents)

                local genConfig = JSONObject()
                genConfig.put("temperature", 0.2)
                genConfig.put("maxOutputTokens", 8192)
                payload.put("generationConfig", genConfig)

                local data = String(payload.toString()).getBytes("UTF-8")
                local url = URL(endpoint)
                local conn = url.openConnection()
                conn.setRequestMethod("POST")
                conn.setConnectTimeout(10000)
                conn.setReadTimeout(20000)
                conn.setRequestProperty("Content-Type", "application/json; charset=UTF-8")
                conn.setDoOutput(true)

                local os = conn.getOutputStream()
                os.write(data)
                os.flush()
                os.close()

                if conn.getResponseCode() == 200 then
                    local reader = BufferedReader(InputStreamReader(conn.getInputStream(), "UTF-8"))
                    local lines = {}
                    local line = reader.readLine()
                    while line ~= nil do
                        table.insert(lines, line)
                        line = reader.readLine()
                    end
                    reader.close()

                    local resJson = JSONObject(table.concat(lines, "\n"))
                    local candidates = resJson.optJSONArray("candidates")
                    if candidates and candidates.length() > 0 then
                        local textOut = candidates.getJSONObject(0).optJSONObject("content").optJSONArray("parts").getJSONObject(0).optString("text")
                        if textOut and textOut ~= "" then
                            resultText = textOut:gsub('^%s*"', ''):gsub('"%s*$', ''):gsub("^%s+", ""):gsub("%s+$", "")
                            isSuccess = true
                        end
                    end
                end
                conn.disconnect()
            end)

            local handler = Handler(Looper.getMainLooper())
            handler.post(Runnable({
                run = function()
                    if isSuccess and resultText then
                        callback(true, resultText)
                    else
                        tryGeminiModel(modelIndex + 1, text, tgtLang, apiKey, callback)
                    end
                end
            }))
        end
    })).start()
end

----------------------------------------------------------------
-- Distributor Eksekusi Terjemahan
----------------------------------------------------------------
local function runTranslation(text, srcLang, tgtLang, callback)
    local engine = getPrefString(PREF_KEY_ENGINE, "Google")

    if engine == "Groq" then
        local key = getPrefString(PREF_KEY_GROQ_KEY, "")
        if key == "" then
            showToast("Kunci API Groq belum diisi. Menggunakan Google.")
            speakText("Kunci Groq kosong, beralih ke Google")
            translateWithGoogle(text, srcLang, tgtLang, callback)
            return
        end
        tryGroqModel(1, text, tgtLang, key, function(ok, res)
            if ok then
                callback(true, res)
            else
                speakText("Groq gagal, beralih ke Google Translate")
                translateWithGoogle(text, srcLang, tgtLang, callback)
            end
        end)
    elseif engine == "Gemini" then
        local key = getPrefString(PREF_KEY_GEMINI_KEY, "")
        if key == "" then
            showToast("Kunci API Gemini belum diisi. Menggunakan Google.")
            speakText("Kunci Gemini kosong, beralih ke Google")
            translateWithGoogle(text, srcLang, tgtLang, callback)
            return
        end
        tryGeminiModel(1, text, tgtLang, key, function(ok, res)
            if ok then
                callback(true, res)
            else
                speakText("Gemini gagal, beralih ke Google Translate")
                translateWithGoogle(text, srcLang, tgtLang, callback)
            end
        end)
    else
        translateWithGoogle(text, srcLang, tgtLang, callback)
    end
end

----------------------------------------------------------------
-- Dialog Pengaturan Mesin Terjemahan
----------------------------------------------------------------
local function showSettingsDialog(onSaveCallback)
    local builder = AlertDialog.Builder(konteks)
    builder.setTitle("Pengaturan Mesin Terjemahan")

    local layout = LinearLayout(konteks)
    layout.setOrientation(LinearLayout.VERTICAL)
    layout.setPadding(40, 20, 40, 20)

    local lblEngine = TextView(konteks)
    lblEngine.setText("Pilih Mesin Terjemahan Utama:")
    lblEngine.setTextSize(15)
    layout.addView(lblEngine)

    local radioGroup = RadioGroup(konteks)
    local engines = {"Google", "Groq", "Gemini"}
    local currentEngine = getPrefString(PREF_KEY_ENGINE, "Google")

    local radioButtons = {}
    for i, eng in ipairs(engines) do
        local rb = RadioButton(konteks)
        rb.setText(eng)
        rb.setId(i)
        rb.setContentDescription("Pilihan mesin: " .. eng)
        if eng == currentEngine then rb.setChecked(true) end
        radioGroup.addView(rb)
        radioButtons[i] = eng
    end
    layout.addView(radioGroup)

    local lblGroq = TextView(konteks)
    lblGroq.setText("\nKunci API Groq:")
    layout.addView(lblGroq)

    local inputGroq = EditText(konteks)
    inputGroq.setHint("Tempel kunci API Groq di sini...")
    inputGroq.setContentDescription("Kolom pengisian kunci API Groq")
    inputGroq.setText(getPrefString(PREF_KEY_GROQ_KEY, ""))
    layout.addView(inputGroq)

    local lblGemini = TextView(konteks)
    lblGemini.setText("\nKunci API Gemini:")
    layout.addView(lblGemini)

    local inputGemini = EditText(konteks)
    inputGemini.setHint("Tempel kunci API Gemini di sini...")
    inputGemini.setContentDescription("Kolom pengisian kunci API Gemini")
    inputGemini.setText(getPrefString(PREF_KEY_GEMINI_KEY, ""))
    layout.addView(inputGemini)

    -- Tombol Periksa Versi Baru di Dalam Pengaturan
    local lblVer = TextView(konteks)
    lblVer.setText("\nInformasi Versi:")
    layout.addView(lblVer)

    local btnCheckUpdate = Button(konteks)
    btnCheckUpdate.setText("Periksa versi baru")
    btnCheckUpdate.setContentDescription("Periksa versi baru")
    btnCheckUpdate.setOnClickListener(View.OnClickListener({
        onClick = function(v)
            checkUpdate()
        end
    }))
    layout.addView(btnCheckUpdate)

    local scroll = ScrollView(konteks)
    scroll.addView(layout)
    builder.setView(scroll)

    builder.setPositiveButton("Simpan Pengaturan", DialogInterface.OnClickListener({
        onClick = function(dialog, which)
            local selectedId = radioGroup.getCheckedRadioButtonId()
            local selectedEngine = radioButtons[selectedId] or "Google"
            setPrefString(PREF_KEY_ENGINE, selectedEngine)
            setPrefString(PREF_KEY_GROQ_KEY, tostring(inputGroq.getText()):gsub("%s+", ""))
            setPrefString(PREF_KEY_GEMINI_KEY, tostring(inputGemini.getText()):gsub("%s+", ""))

            showToast("Pengaturan disimpan. Mesin aktif: " .. selectedEngine)
            speakText("Pengaturan disimpan. Mesin terjemahan aktif sekarang adalah " .. selectedEngine)
            if onSaveCallback then onSaveCallback(selectedEngine) end
        end
    }))

    builder.setNegativeButton("Batal", nil)
    showSafeDialog(builder.create())
end

----------------------------------------------------------------
-- Dialog Pemilih Bahasa Ramah Aksesibilitas
----------------------------------------------------------------
local function showLanguageSelector(title, isSource, onSelected)
    local builder = AlertDialog.Builder(konteks)
    builder.setTitle(title)

    local names = {}
    local filteredList = {}
    for _, item in ipairs(LANGUAGE_LIST) do
        if not (isSource == false and item.code == "auto") then
            table.insert(filteredList, item)
            table.insert(names, item.name)
        end
    end

    builder.setItems(names, DialogInterface.OnClickListener({
        onClick = function(dialog, which)
            local picked = filteredList[which + 1]
            onSelected(picked.name, picked.code)
        end
    }))
    builder.setNegativeButton("Batal", nil)
    showSafeDialog(builder.create())
end

----------------------------------------------------------------
-- Antarmuka Utama Terjemahan Ramah Tunanetra
----------------------------------------------------------------
local function openTranslatorApp()
    local builder = AlertDialog.Builder(konteks)
    builder.setTitle("Google Terjemahan Multi-Mesin (" .. CURRENT_VERSION .. ")")

    local root = LinearLayout(konteks)
    root.setOrientation(LinearLayout.VERTICAL)
    root.setPadding(35, 20, 35, 20)

    -- Status Mesin Aktif
    local curEngine = getPrefString(PREF_KEY_ENGINE, "Google")
    local tvEngineStatus = TextView(konteks)
    tvEngineStatus.setText("Mesin aktif: " .. curEngine)
    tvEngineStatus.setContentDescription("Mesin terjemahan yang aktif saat ini: " .. curEngine)
    tvEngineStatus.setTextSize(14)
    tvEngineStatus.setGravity(Gravity.RIGHT)
    tvEngineStatus.setPadding(0, 0, 0, 10)
    root.addView(tvEngineStatus)

    -- Baris Pemilihan Bahasa
    local curSrcCode = getPrefString(PREF_KEY_SRC, "auto")
    local curTgtCode = getPrefString(PREF_KEY_TGT, "en")
    local curSrcName = "Deteksi Otomatis"
    local curTgtName = "Inggris"

    for _, v in ipairs(LANGUAGE_LIST) do
        if v.code == curSrcCode then curSrcName = v.name end
        if v.code == curTgtCode then curTgtName = v.name end
    end

    -- 1. Tombol Bahasa Asal
    local btnSrc = Button(konteks)
    local function updateSrcButton()
        btnSrc.setText("Bahasa asal: " .. curSrcName)
        btnSrc.setContentDescription("Bahasa asal saat ini " .. curSrcName .. ". Ketuk dua kali untuk memilih bahasa asal.")
    end
    updateSrcButton()
    root.addView(btnSrc)

    -- 2. Tombol Tukar Bahasa
    local btnSwap = Button(konteks)
    btnSwap.setText("Tukar bahasa asal dan tujuan")
    btnSwap.setContentDescription("Tombol tukar posisi antara bahasa asal dan bahasa tujuan.")
    root.addView(btnSwap)

    -- 3. Tombol Bahasa Tujuan
    local btnTgt = Button(konteks)
    local function updateTgtButton()
        btnTgt.setText("Bahasa tujuan: " .. curTgtName)
        btnTgt.setContentDescription("Bahasa tujuan saat ini " .. curTgtName .. ". Ketuk dua kali untuk memilih bahasa tujuan.")
    end
    updateTgtButton()
    root.addView(btnTgt)

    -- Kolom Teks Asal
    local lblInput = TextView(konteks)
    lblInput.setText("\nKolom Teks Asal:")
    lblInput.setTextSize(14)
    root.addView(lblInput)

    local inputSource = EditText(konteks)
    inputSource.setHint("Ketik atau tempel teks yang ingin diterjemahkan di sini...")
    inputSource.setContentDescription("Kolom teks asal. Masukkan teks yang akan diterjemahkan.")
    inputSource.setMinLines(3)
    inputSource.setGravity(Gravity.TOP)
    root.addView(inputSource)

    -- Tombol Terjemahkan
    local btnTranslate = Button(konteks)
    btnTranslate.setText("Mulai Terjemahkan")
    btnTranslate.setContentDescription("Tombol mulai terjemahkan teks.")
    root.addView(btnTranslate)

    -- Kolom Hasil Terjemahan
    local lblResult = TextView(konteks)
    lblResult.setText("\nHasil Terjemahan:")
    lblResult.setTextSize(14)
    root.addView(lblResult)

    local outputResult = EditText(konteks)
    outputResult.setHint("Hasil terjemahan akan tampil di sini...")
    outputResult.setContentDescription("Kolom hasil terjemahan.")
    outputResult.setMinLines(3)
    outputResult.setGravity(Gravity.TOP)
    outputResult.setFocusable(true)
    root.addView(outputResult)

    -- Baris Tombol Aksi Hasil
    local actionRow = LinearLayout(konteks)
    actionRow.setOrientation(LinearLayout.HORIZONTAL)
    actionRow.setPadding(0, 15, 0, 10)

    local btnSpeak = Button(konteks)
    btnSpeak.setText("Bicara")
    btnSpeak.setContentDescription("Putar suara teks hasil terjemahan")
    local paramAct = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0)
    btnSpeak.setLayoutParams(paramAct)
    actionRow.addView(btnSpeak)

    local btnCopy = Button(konteks)
    btnCopy.setText("Salin")
    btnCopy.setContentDescription("Salin hasil terjemahan ke papan klip")
    btnCopy.setLayoutParams(paramAct)
    actionRow.addView(btnCopy)

    local btnClear = Button(konteks)
    btnClear.setText("Hapus Teks")
    btnClear.setContentDescription("Hapus isi kolom teks asal dan hasil terjemahan")
    btnClear.setLayoutParams(paramAct)
    actionRow.addView(btnClear)

    root.addView(actionRow)

    -- Interaksi Pilihan Bahasa Asal
    btnSrc.setOnClickListener(View.OnClickListener({
        onClick = function(v)
            showLanguageSelector("Pilih Bahasa Asal", true, function(name, code)
                curSrcName = name
                curSrcCode = code
                updateSrcButton()
                setPrefString(PREF_KEY_SRC, code)
                speakText("Bahasa asal diatur ke " .. name)
            end)
        end
    }))

    -- Interaksi Pilihan Bahasa Tujuan
    btnTgt.setOnClickListener(View.OnClickListener({
        onClick = function(v)
            showLanguageSelector("Pilih Bahasa Tujuan", false, function(name, code)
                curTgtName = name
                curTgtCode = code
                updateTgtButton()
                setPrefString(PREF_KEY_TGT, code)
                speakText("Bahasa tujuan diatur ke " .. name)
            end)
        end
    }))

    -- Interaksi Tukar Bahasa
    btnSwap.setOnClickListener(View.OnClickListener({
        onClick = function(v)
            if curSrcCode == "auto" then
                showToast("Tidak bisa menukar bahasa saat asal diatur Otomatis")
                speakText("Tidak bisa menukar bahasa saat bahasa asal masih Deteksi Otomatis")
                return
            end

            local tmpName = curSrcName
            local tmpCode = curSrcCode
            curSrcName = curTgtName
            curSrcCode = curTgtCode
            curTgtName = tmpName
            curTgtCode = tmpCode

            updateSrcButton()
            updateTgtButton()
            setPrefString(PREF_KEY_SRC, curSrcCode)
            setPrefString(PREF_KEY_TGT, curTgtCode)

            -- Tukar isi kotak teks jika sudah ada isinya
            local srcText = tostring(inputSource.getText())
            local resText = tostring(outputResult.getText())
            inputSource.setText(resText)
            outputResult.setText(srcText)

            speakText("Bahasa berhasil ditukar. Bahasa asal sekarang " .. curSrcName .. ", bahasa tujuan " .. curTgtName)
        end
    }))

    -- Eksekusi Terjemahan
    btnTranslate.setOnClickListener(View.OnClickListener({
        onClick = function(v)
            local txt = tostring(inputSource.getText()):gsub("^%s+", ""):gsub("%s+$", "")
            if txt == "" then
                showToast("Masukkan teks terlebih dahulu")
                speakText("Kolom teks masih kosong. Masukkan teks terlebih dahulu.")
                return
            end

            outputResult.setText("Sedang menerjemahkan...")
            speakText("Sedang menerjemahkan")
            runTranslation(txt, curSrcCode, curTgtCode, function(success, result)
                if success then
                    outputResult.setText(result)
                    if #result > 120 then
                        speakText("Terjemahan selesai. Ketuk tombol bicara jika ingin mendengarkan.")
                    else
                        speakText(result)
                    end
                else
                    outputResult.setText("Terjadi kesalahan: " .. tostring(result))
                    speakText("Gagal menerjemahkan teks")
                end
            end)
        end
    }))

    -- Aksi Tombol Putar Suara
    btnSpeak.setOnClickListener(View.OnClickListener({
        onClick = function(v)
            local res = tostring(outputResult.getText())
            if res and res ~= "" and res ~= "Sedang menerjemahkan..." then
                speakText(res)
            else
                speakText("Belum ada hasil terjemahan untuk dibacakan")
            end
        end
    }))

    -- Aksi Tombol Salin
    btnCopy.setOnClickListener(View.OnClickListener({
        onClick = function(v)
            local res = tostring(outputResult.getText())
            if res and res ~= "" and res ~= "Sedang menerjemahkan..." then
                copyToClipboard(res)
            else
                speakText("Belum ada teks yang bisa disalin")
            end
        end
    }))

    -- Aksi Tombol Hapus
    btnClear.setOnClickListener(View.OnClickListener({
        onClick = function(v)
            inputSource.setText("")
            outputResult.setText("")
            speakText("Semua teks telah dibersihkan")
        end
    }))

    local scroll = ScrollView(konteks)
    scroll.addView(root)
    builder.setView(scroll)

    -- Tombol Pengaturan di Dialog Utama
    builder.setNeutralButton("Pengaturan Mesin", DialogInterface.OnClickListener({
        onClick = function(dialog, which)
            showSettingsDialog(function(newEngine)
                tvEngineStatus.setText("Mesin aktif: " .. newEngine)
                tvEngineStatus.setContentDescription("Mesin terjemahan yang aktif saat ini: " .. newEngine)
            end)
        end
    }))

    builder.setNegativeButton("Tutup", nil)
    showSafeDialog(builder.create())
end

-- Jalankan Aplikasi Terjemahan
openTranslatorApp()
return true
