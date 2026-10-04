-- Developer: Nathan
-- autosb.lua - Auto Super Broadcast. Command: /autosb
-- /autosb -> Start | Stop | Configure
-- Configure: teks dan durasi berjalan (menit).
-- Durasi 0 = sampai Stop. Start setelah Stop memulai durasi baru.
-- Konfigurasi tersimpan per akun. Disconnect/reload menghentikan Auto SB;
-- player perlu menekan Start lagi. Tidak menyimpan status berjalan.
-- Pengiriman melalui /sb asli: izin, biaya, dan cooldown tetap milik engine.
-- Docs engine belum menyediakan getter cooldown /sb. Isi konstanta berikut
-- sesuai cooldown /sb server; nil menolak Start sampai nilainya tersedia.
-- Jika setting cooldown server berubah, perbarui konstanta ini juga.
-- Nilai true dari sendPlayerMessage berarti command diproses, bukan bukti
-- broadcast diterima. Script tidak menebak biaya atau keberhasilan /sb.

local SERVER_SB_COOLDOWN_SECONDS = nil
local MAX_DURATION_MINUTES = 1440
local MAX_TEXT_BYTES = 300
local MENU_DIALOG = "autosb_menu"
local CONFIG_DIALOG = "autosb_config"
local STORE_PREFIX = "autosb_config_v1_"
-- Optional existing storage prefix: configure server KV before updating.
-- The default is used by new installs; see PUBLISHING.md for existing data.
local STORE_PREFIX_KEY = "autosb_storage_prefix_v1"
local storeReady, storeError = pcall(function()
    if type(loadStringFromServer) ~= "function" then return end
    local configuredPrefix = loadStringFromServer(STORE_PREFIX_KEY)
    if configuredPrefix ~= nil then
        assert(type(configuredPrefix) == "string" and #configuredPrefix > 0 and #configuredPrefix <= 128
            and configuredPrefix:match("^[%w_%-]+$"), "Invalid Auto SB storage prefix.")
        STORE_PREFIX = configuredPrefix
    end
end)
local sessions = {}

local function notify(player, text)
    player:onConsoleMessage("`6[Auto SB]`` " .. text)
end

local function trim(text)
    return text:match("^%s*(.-)%s*$")
end

local function integer(value, minimum, maximum)
    if type(value) ~= "number" and type(value) ~= "string" then return nil end
    local parsed = tonumber(value)
    if not parsed or parsed ~= parsed or parsed < minimum or parsed > maximum
        or parsed ~= math.floor(parsed) then return nil end
    return parsed
end

local function validText(value)
    -- Menolak pemisah dialog/packet; kode warna Growtopia tetap diizinkan.
    if type(value) ~= "string" or #value > MAX_TEXT_BYTES
        or value:find("[|%c]") then return nil end
    value = trim(value)
    if value == "" or trim(value:gsub("`.", "")) == "" then return nil end
    return value
end

local function getSession(player)
    assert(storeReady, "Auto SB storage configuration failed: " .. tostring(storeError))
    local id = player:getUserID()
    if sessions[id] then return sessions[id] end
    local state = { text = "", duration = 0 }
    local ok, saved = pcall(loadDataFromServer, STORE_PREFIX .. id)
    if ok and type(saved) == "table" then
        state.text = validText(saved.text) or ""
        state.duration = integer(saved.duration, 0, MAX_DURATION_MINUTES) or 0
    elseif not ok then
        print("[autosb] Failed to load config for " .. id .. ": " .. tostring(saved))
    end
    sessions[id] = state
    return state
end

local function stop(state)
    if state.timer then timer.clearInterval(state.timer) end
    state.timer = nil
    state.nextSend = nil
    state.expiresAt = nil
end

local function showMenu(player)
    local state = getSession(player)
    local status = state.timer and "`2Berjalan``" or "`4Berhenti``"
    local duration = state.duration == 0 and "Sampai Stop" or (state.duration .. " menit")
    local preview = state.text ~= "" and state.text or "Belum diatur; pilih Configure."
    local lines = {
        "add_label|big|`wAuto Super Broadcast``|left|\n",
        "add_smalltext|Status: " .. status .. "|\n",
        "add_smalltext|Teks: " .. preview .. "``|\n",
        "add_smalltext|Cooldown SB: " .. (SERVER_SB_COOLDOWN_SECONDS
            and (SERVER_SB_COOLDOWN_SECONDS .. " detik") or "belum diatur") .. "|\n",
        "add_smalltext|Durasi: " .. duration .. "|\n",
    }
    if state.timer then
        lines[#lines + 1] = "add_smalltext|SB berikutnya dalam sekitar "
            .. math.max(0, state.nextSend - os.time()) .. " detik.|\n"
        if state.expiresAt then
            lines[#lines + 1] = "add_smalltext|Sisa durasi: "
                .. math.max(0, state.expiresAt - os.time()) .. " detik.|\n"
        end
    end
    lines[#lines + 1] = "add_smalltext|Izin, biaya, dan cooldown mengikuti /sb server.|\n"
    lines[#lines + 1] = "add_smalltext|Auto SB berhenti saat disconnect. Start untuk menjalankan lagi.|\n"
    lines[#lines + 1] = "add_spacer|small|\n"
    lines[#lines + 1] = "add_button|autosb_start|Start|noflags|0|0|\n"
    lines[#lines + 1] = "add_button|autosb_stop|Stop|noflags|0|0|\n"
    lines[#lines + 1] = "add_button|autosb_configure|Configure|noflags|0|0|\n"
    lines[#lines + 1] = "add_spacer|small|\nadd_smalltext|`9© Dibuat Oleh : Nathan``|\n"
    lines[#lines + 1] = "end_dialog|" .. MENU_DIALOG .. "|Tutup||\n"
    player:onDialogRequest(table.concat(lines))
end

local function showConfigure(player)
    local state = getSession(player)
    player:onDialogRequest(table.concat({
        "add_label|big|`wConfigure Auto SB``|left|\n",
        "add_smalltext|Isi teks saja; /sb ditambahkan otomatis.|\n",
        "add_text_input|autosb_text|Text|" .. state.text .. "|" .. MAX_TEXT_BYTES .. "|\n",
        "add_smalltext|Jeda SB menggunakan cooldown server; tidak diatur per player.|\n",
        "add_text_input|autosb_duration|Durasi (menit)|" .. state.duration .. "|4|\n",
        "add_smalltext|0 = sampai Stop; maksimal " .. MAX_DURATION_MINUTES .. " menit.|\n",
        "add_smalltext|Saat berjalan, teks baru dipakai pada SB berikutnya; durasi dihitung ulang.|\n",
        "add_button|autosb_save|Simpan|noflags|0|0|\n",
        "add_button|autosb_back|Kembali|noflags|0|0|\n",
        "add_spacer|small|\nadd_smalltext|`9© Dibuat Oleh : Nathan``|\n",
        "end_dialog|" .. CONFIG_DIALOG .. "|Tutup||\n",
    }))
end

local function tick(id, state)
    local player = getPlayer(id)
    if not player or not player:isOnline() then
        stop(state)
        sessions[id] = nil
        return
    end
    local now = os.time()
    if state.expiresAt and now >= state.expiresAt then
        stop(state)
        notify(player, "`2Durasi selesai.`` Tekan Start di /autosb untuk menjalankan lagi.")
        return
    end
    if now < state.nextSend then return end
    local world = player:getWorld()
    if not world then return end -- Tunggu player masuk world, tetap hitung durasi.
    -- Jadwalkan sebelum dispatch. Tidak mengejar broadcast yang terlewat
    -- dengan mengirim beruntun jika tick terlambat atau player pindah world.
    state.lastAttempt = now
    state.nextSend = now + SERVER_SB_COOLDOWN_SECONDS
    local dispatched = world:sendPlayerMessage(player, "/sb " .. state.text)
    if not dispatched then
        stop(state)
        notify(player, "`4Auto SB dihentikan: command /sb tidak dapat diproses.")
    end
end

local function start(player)
    local state = getSession(player)
    if state.timer then
        notify(player, "Auto SB sudah berjalan.")
        showMenu(player)
        return
    end
    if not integer(SERVER_SB_COOLDOWN_SECONDS, 1, 86400) then
        notify(player, "`4Cooldown /sb server belum diatur oleh pengelola script.")
        showMenu(player)
        return
    end
    if not validText(state.text) then
        notify(player, "Isi teks dan durasi melalui Configure terlebih dahulu.")
        showConfigure(player)
        return
    end
    if not player:getWorld() then
        notify(player, "Masuk ke world dahulu sebelum menekan Start.")
        showMenu(player)
        return
    end
    local now = os.time()
    local id = player:getUserID()
    local interval = SERVER_SB_COOLDOWN_SECONDS
    state.nextSend = math.max(now, (state.lastAttempt or (now - interval)) + interval)
    state.expiresAt = state.duration > 0 and (now + state.duration * 60) or nil
    -- Hanya menangkap user ID dan data Lua; player/world dibaca ulang tiap tick.
    state.timer = timer.setInterval(1, function()
        if sessions[id] ~= state or not state.timer then return end
        local ok, err = pcall(tick, id, state)
        if not ok then
            stop(state)
            print("[autosb] Stopped for " .. id .. ": " .. tostring(err))
            local current = getPlayer(id)
            if current and current:isOnline() then
                notify(current, "`4Auto SB berhenti karena error. Periksa log Lua server.")
            end
        end
    end)
    notify(player, "`2Auto SB dimulai.`` Cooldown SB " .. interval .. " detik. Gunakan Stop untuk menghentikan.")
    showMenu(player)
end

local function configure(player, data)
    if not storeReady then
        notify(player, "`4Auto SB storage configuration failed. Check the server log before saving.")
        return
    end
    local text = validText(data.autosb_text)
    if not text then
        notify(player, "`4Teks wajib diisi, maksimal " .. MAX_TEXT_BYTES .. " byte, tanpa baris baru atau karakter |.")
        showConfigure(player)
        return
    end
    local duration = integer(data.autosb_duration, 0, MAX_DURATION_MINUTES)
    if not duration then
        notify(player, "`4Durasi harus bilangan bulat 0-" .. MAX_DURATION_MINUTES .. " menit.")
        showConfigure(player)
        return
    end
    local saved = { text = text, duration = duration }
    local ok, result = pcall(saveDataToServer, STORE_PREFIX .. player:getUserID(), saved)
    if not ok or result ~= true then
        notify(player, "`4Konfigurasi gagal disimpan. Pengaturan sebelumnya tetap berlaku.")
        showConfigure(player)
        return
    end
    local state = getSession(player)
    state.text, state.duration = text, duration
    if state.timer then
        local now = os.time()
        state.expiresAt = duration > 0 and (now + duration * 60) or nil
    end
    notify(player, "`2Konfigurasi disimpan.`` "
        .. (state.timer and "Teks diperbarui dan durasi dimulai ulang." or "Tekan Start untuk memulai."))
    showMenu(player)
end

registerLuaCommand {
    command = "autosb",
    roleRequired = 0,
    description = "Atur Auto Super Broadcast: Start, Stop, Configure.",
}

onPlayerCommandCallback(function(world, player, fullCommand)
    local command = tostring(fullCommand):match("^%s*/?(%S+)")
    if not command or command:lower() ~= "autosb" then return false end
    if player and player:isOnline() then
        if storeReady then showMenu(player)
        else notify(player, "`4Auto SB storage configuration failed. Check the server log before using /autosb.") end
    end
    return true
end)

onPlayerDialogCallback(function(world, player, data)
    if data.dialog_name ~= MENU_DIALOG and data.dialog_name ~= CONFIG_DIALOG then return false end
    if not player or not player:isOnline() then return true end
    if not storeReady then
        notify(player, "`4Auto SB storage configuration failed. Check the server log before using /autosb.")
        return true
    end
    if data.dialog_name == MENU_DIALOG then
        if data.buttonClicked == "autosb_start" then
            start(player)
        elseif data.buttonClicked == "autosb_stop" then
            stop(getSession(player))
            notify(player, "Auto SB dihentikan. Konfigurasi tetap tersimpan; Start untuk menjalankan lagi.")
            showMenu(player)
        elseif data.buttonClicked == "autosb_configure" then
            showConfigure(player)
        end
    elseif data.buttonClicked == "autosb_save" then
        configure(player, data)
    elseif data.buttonClicked == "autosb_back" then
        showMenu(player)
    end
    return true
end)

onPlayerDisconnectCallback(function(player)
    local id = player:getUserID()
    local state = sessions[id]
    if state then stop(state) end
    sessions[id] = nil
end)

if not storeReady then print("[autosb] STORAGE ERROR: " .. tostring(storeError)) end
print("[autosb] Loaded. Use /autosb -> Start / Stop / Configure.")
