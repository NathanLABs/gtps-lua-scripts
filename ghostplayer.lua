-- Developer: Nathan
-- ghostplayer.lua - Gunakan command bawaan: /ghost
-- Player biasa: hanya owner world. Admin/access world tidak cukup.
-- Dev (4), SDev (5), dan role staf di atasnya tetap memakai izin staf engine.
-- Upload hanya file ini. Tidak memerlukan database atau script lain.

local DEV_ROLE = 4 -- ID role dari dokumentasi engine server ini.
local tracked, reported = {}, {}

local function notify(player, message)
    player:onConsoleMessage("`6[Ghost]`` " .. message)
end

local ready, initError = pcall(function()
    assert(setGhostModePolicy({
        worldOwner = true,
        worldAdmins = false,
        roles = { DEV_ROLE },
        -- Role editor tidak boleh memberi jalan pintas untuk player non-owner.
        rolePermission = false,
        obeyWorldSetting = true,
    }) == true, "Ghost policy rejected by engine")
end)
if not ready then print("[ghostplayer] INIT FAILED: " .. tostring(initError)) end

local function activePlayer(player)
    return player and player:isOnline() and player:getType() == 0
end

local function protect(player, fn)
    local ok, result = pcall(fn)
    if not ok then
        local id = player:getUserID()
        local message = tostring(result)
        if reported[id] ~= message then
            reported[id] = message
            print("[ghostplayer] uid=" .. tostring(id) .. " " .. message)
            notify(player, "`4Ghost tidak dapat diproses.`` Hubungi admin untuk memeriksa log server.")
        end
        return false
    end
    reported[player:getUserID()] = nil
    return true, result
end

local function disable(player, message)
    if player:isGhostMode() then
        assert(player:setGhostMode(false) == true and not player:isGhostMode(), "Failed to disable ghost mode")
        notify(player, message)
    end
    tracked[player:getUserID()] = nil
end

-- Tidak mendaftarkan ulang /ghost atau mengganti toggle bawaan.
-- nil = lanjutkan ke policy engine: engine memeriksa owner secara native.
-- Snapshot nama owner hanya untuk mendeteksi PERUBAHAN kepemilikan,
-- bukan untuk memberi izin berdasarkan nickname/nama tampilan player.
onPlayerGhostModeCallback(function(world, player, reason)
    if not activePlayer(player) then return false end
    local ok, decision = protect(player, function()
        local id = player:getUserID()
        if player:hasRole(DEV_ROLE) then tracked[id] = nil; return nil end
        if not ready then return false end
        if reason ~= "command" and reason ~= "enter" then return false end
        if not world then
            if reason == "command" then notify(player, "Masuk ke world milikmu untuk memakai /ghost.") end
            return false
        end
        local name, owner = world:getName(), world:getOwner()
        if type(name) ~= "string" or name == "" or type(owner) ~= "string" or owner == "" then
            if reason == "command" then notify(player, "`4/ghost hanya tersedia untuk owner world yang sudah dikunci.``") end
            return false
        end
        -- Jangan memperbarui bukti world saat ghost sudah aktif: command yang
        -- ditolak setelah world dijual tidak boleh mengesahkan owner baru.
        if not player:isGhostMode() then tracked[id] = { world = name, owner = owner } end
        return nil
    end)
    if not ok then return false end
    return decision
end)

onPlayerLeaveWorldCallback(function(world, player)
    if not activePlayer(player) then return end
    protect(player, function()
        if player:hasRole(DEV_ROLE) then tracked[player:getUserID()] = nil; return end
        disable(player, "Ghost dimatikan karena kamu keluar world. Gunakan /ghost lagi di world milikmu.")
    end)
end)

-- Tick menangani penjualan world, penghapusan lock, dan perubahan role saat
-- ghost masih aktif. Tidak menyimpan handle player/world di luar callback.
onPlayerTick(function(player)
    if not activePlayer(player) then return end
    protect(player, function()
        local id = player:getUserID()
        if player:hasRole(DEV_ROLE) or not player:isGhostMode() then tracked[id] = nil; return end
        local record = tracked[id]
        local world = player:getWorld()
        if not ready or not record or not world or world:getName() ~= record.world
            or world:getOwner() ~= record.owner then
            disable(player, "Ghost dimatikan karena world atau kepemilikannya berubah. Gunakan /ghost untuk memeriksa izin kembali.")
        end
    end)
end)

onPlayerDisconnectCallback(function(player)
    if not player then return end
    local id = player:getUserID()
    tracked[id], reported[id] = nil, nil
end)

print("[ghostplayer] " .. (ready and "Loaded: /ghost | world owner only for players; Dev/SDev use staff policy"
    or "Unavailable; check initialization errors"))
