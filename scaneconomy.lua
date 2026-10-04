-- Developer: Nathan
-- scaneconomy.lua - Read-only economy scan.
-- Pasang di Lua Scripts, reload, lalu ketik /scaneconomy sebagai founder.
-- HANYA READ-ONLY: tidak mengambil, memindahkan, atau mengubah item.
--
-- BATAS API: ini scan parsial, BUKAN total ekonomi seluruh server.
-- Terbaca: player online (inventory + Extra Backpack), world loaded
-- (drop, lock terpasang, stok vending, dan WL hasil penjualan vending).
-- Tidak terbaca: player offline, world unloaded, storage box, vault,
-- donation box, serta isi container lain yang tidak diekspos oleh API.
-- Scan bertahap, bukan snapshot atomik: perpindahan item selama scan
-- bisa membuat item terlewat atau terhitung dua kali.
--
-- Lock standar dikenali lewat ID. Lock lain yang TERAMATI dikenali
-- melalui nama berakhiran kata "Lock"/"Locks" (heuristik, bukan registry).
-- Tambahkan override untuk custom lock yang namanya berbeda, atau false
-- untuk mengecualikan item yang keliru dikenali. Tidak menebak kurs custom.
local LOCK_OVERRIDES = {
    [242] = "World Lock (WL)",
    [1796] = "Diamond Lock (DL)",
    [7188] = "Blue Gem Lock (BGL)",
    [8470] = "Golden Gem Lock (GGL)",
    -- [13200] = "Rayman Lock",
    -- [12345] = false,
}

local FOUNDER_ROLE = 1000
local WORK_PER_TICK = 600
local ROWS_PER_PAGE = 4
local COOLDOWN_SECONDS = 30
local DIALOG = "scaneconomy_result"
local active = nil
local reports = {}
local lastStarted = nil

local function isFounder(player)
    -- Pemeriksaan role persis: owner 999 juga ditolak.
    return player and player:isOnline() and player:getRole() == FOUNDER_ROLE
end

local function clean(value)
    return tostring(value or ""):gsub("`.", ""):gsub("[|\r\n]", " ")
end

local function number(value)
    local s = string.format("%.0f", value)
    local reversed = s:reverse():gsub("(%d%d%d)", "%1.")
    return reversed:reverse():gsub("^%.", "")
end

local function message(player, text)
    player:onConsoleMessage("`6[ScanEconomy] ``" .. text)
end

local function lockInfo(job, id)
    if not id or id <= 0 then return nil end
    local cached = job.catalog[id]
    if cached ~= nil then return cached or nil end
    local override = LOCK_OVERRIDES[id]
    local info = false
    if type(override) == "string" then
        info = { name = clean(override):sub(1, 80), automatic = false }
    elseif override ~= false then
        local item = getItem(id)
        if item then
            local name = clean(item:getName())
            local lower = name:lower():gsub("%s+$", "")
            if lower == "lock" or lower == "locks"
                or lower:match("%slocks?$") then
                info = { name = name:sub(1, 80), automatic = true }
            end
        end
    end
    job.catalog[id] = info
    return info or nil
end

local function rowFor(job, id, info)
    local row = job.rows[id]
    if not row then
        row = { id = id, name = info.name, automatic = info.automatic,
            inventory = 0, extra = 0, drops = 0, placed = 0,
            vending = 0, earnings = 0, total = 0 }
        job.rows[id] = row
    end
    return row
end

local function add(job, id, count, source)
    count = tonumber(count)
    if not count or count <= 0 then return end
    local info = lockInfo(job, id)
    if not info then return end
    local row = rowFor(job, id, info)
    row[source] = row[source] + count
    row.total = row.total + count
end

local function showReport(player, report, page)
    if not isFounder(player) then return end
    local pages = math.max(1, math.ceil(#report.list / ROWS_PER_PAGE))
    page = math.max(1, math.min(pages, math.floor(tonumber(page) or 1)))
    local lines = {}
    local function label(text)
        lines[#lines + 1] = "add_smalltext|" .. text .. "|\n"
    end
    lines[#lines + 1] = "add_label|big|`wScan Economy - Founder``|left|\n"
    label("`4SCAN PARSIAL - bukan total seluruh server.``")
    label("Storage box / vault / container lain: TIDAK TERBACA.")
    label("Player offline / world unloaded: TIDAK TERBACA.")
    label("Item berpindah saat scan bisa terlewat / terhitung dua kali.")
    label("Player terbaca: " .. number(report.players) .. "/" .. number(report.playerCount)
        .. "; world: " .. number(report.worlds) .. "/" .. number(report.worldCount)
        .. "; dilewati: " .. number(report.skipped))
    label("Durasi: " .. number(report.elapsed) .. " detik; halaman " .. page .. "/" .. pages)
    label("*) Kandidat dari nama item; pastikan termasuk mata uang server.")
    label("Jumlah = unit item, bukan hasil konversi ke WL.")
    for i = (page - 1) * ROWS_PER_PAGE + 1, math.min(page * ROWS_PER_PAGE, #report.list) do
        local row = report.list[i]
        lines[#lines + 1] = "add_spacer|small|\n"
        label("`w" .. row.name .. (row.automatic and " *" or "") .. " [ID " .. row.id .. "]``")
        label("`2Total teramati: " .. number(row.total) .. "``")
        label("Backpack: " .. number(row.inventory) .. " / Extra Backpack: " .. number(row.extra))
        label("Drop world: " .. number(row.drops) .. " / Terpasang: " .. number(row.placed))
        label("Stok vending: " .. number(row.vending) .. " / Hasil vending (WL): " .. number(row.earnings))
    end
    if page > 1 then
        lines[#lines + 1] = "add_button|page_" .. (page - 1) .. "|Sebelumnya|noflags|0|0|\n"
    end
    if page < pages then
        lines[#lines + 1] = "add_button|page_" .. (page + 1) .. "|Berikutnya|noflags|0|0|\n"
    end
    lines[#lines + 1] = "add_spacer|small|\nadd_smalltext|`9© Dibuat Oleh : Nathan``|\n"
    lines[#lines + 1] = "end_dialog|" .. DIALOG .. "|Tutup||\n"
    player:onDialogRequest(table.concat(lines))
end

local function stop(job)
    if job.timer then timer.clearInterval(job.timer) end
    if active == job then active = nil end
end

local function finish(job, player)
    local list = {}
    for _, row in pairs(job.rows) do list[#list + 1] = row end
    table.sort(list, function(a, b) return a.id < b.id end)
    local report = { list = list, players = job.players, worlds = job.worlds,
        playerCount = #job.playerIDs, worldCount = #job.worldHandles,
        skipped = job.skipped, elapsed = os.time() - job.started }
    reports[job.requester] = report
    stop(job)
    message(player, "`2Scan selesai. ``Hasil parsial ditampilkan; storage/vault dan data offline tidak tercakup.")
    showReport(player, report, 1)
end

local function scanPlayer(job, player)
    -- Kedua inventory dibaca dalam callback yang sama, tanpa menahan player handle.
    for _, item in ipairs(player:getInventoryItems() or {}) do
        add(job, item:getItemID(), item:getItemCount(), "inventory")
    end
    for _, item in ipairs(player:getExtraBackpack() or {}) do
        add(job, item:getItemID(), item:getItemCount(), "extra")
    end
    job.players = job.players + 1
end

local function step(job, requester)
    if job.playerIndex <= #job.playerIDs then
        local player = getPlayer(job.playerIDs[job.playerIndex])
        job.playerIndex = job.playerIndex + 1
        if player and player:isOnline() and player:getType() == 0 then
            scanPlayer(job, player)
        else
            job.skipped = job.skipped + 1
        end
        return
    end

    if job.worldIndex > #job.worldHandles then
        finish(job, requester)
        return
    end
    local world = job.worldHandles[job.worldIndex]
    local sx = world:getSizeX()
    if not sx or sx <= 0 then
        job.skipped = job.skipped + 1
        job.worldIndex = job.worldIndex + 1
        job.worldState = nil
        return
    end
    if not job.worldState then
        local drops = world:getDroppedItems() or {}
        local tiles = world:getTiles() or {}
        job.worldState = { drops = drops, dropIndex = 1,
            tiles = tiles, tileIndex = 1 }
    end
    local state = job.worldState
    local budget = WORK_PER_TICK
    while budget > 0 and state.dropIndex <= #state.drops do
        local drop = state.drops[state.dropIndex]
        add(job, drop:getItemID(), drop:getItemCount(), "drops")
        state.dropIndex = state.dropIndex + 1
        budget = budget - 1
    end
    while budget > 0 and state.tileIndex <= #state.tiles do
        local tile = state.tiles[state.tileIndex]
        if tile then
            local fg = tile:getTileForeground()
            local bg = tile:getTileBackground()
            if fg then add(job, fg, 1, "placed") end
            if bg then add(job, bg, 1, "placed") end
            local vendOk, stockID = pcall(function() return tile:getVendingItem() end)
            if vendOk and stockID and stockID ~= 0 then
                local _, cnt = pcall(function() return tile:getVendingCount() end)
                local _, earn = pcall(function() return tile:getVendingEarnings() end)
                add(job, stockID, (type(cnt) == "number" and cnt) or 0, "vending")
                add(job, 242, (type(earn) == "number" and earn) or 0, "earnings")
            end
        else
            job.skipped = job.skipped + 1
        end
        state.tileIndex = state.tileIndex + 1
        budget = budget - 1
    end
    if state.dropIndex > #state.drops and state.tileIndex > #state.tiles then
        job.worlds = job.worlds + 1
        job.worldIndex = job.worldIndex + 1
        job.worldState = nil
    end
end

local function beginScan(player)
    if not isFounder(player) then
        message(player, "`4Command ini hanya untuk role Founder (1000).")
        return
    end
    if active then
        message(player, "Scan sedang berjalan: " .. active.players .. "/" .. #active.playerIDs
            .. " player, " .. active.worlds .. "/" .. #active.worldHandles .. " world selesai.")
        return
    end
    local now = os.time()
    if lastStarted and now - lastStarted < COOLDOWN_SECONDS then
        message(player, "Tunggu " .. (COOLDOWN_SECONDS - (now - lastStarted)) .. " detik sebelum scan ulang.")
        return
    end
    local job = { requester = player:getUserID(), started = now, catalog = {}, rows = {},
        playerIDs = {}, worldHandles = {}, playerIndex = 1, worldIndex = 1,
        players = 0, worlds = 0, skipped = 0 }
    -- Simpan ID saja: player handle hanya dijamin valid di callback penerima.
    local seenPlayers, seenWorlds = {}, {}
    for _, online in ipairs(getServerPlayers()) do
        local id = online:getUserID()
        if online:getType() == 0 and not seenPlayers[id] then
            job.playerIDs[#job.playerIDs + 1] = id
            seenPlayers[id] = true
        end
    end
    for _, world in ipairs(getWorlds()) do
        local name = world:getName()
        if not seenWorlds[name] then
            job.worldHandles[#job.worldHandles + 1] = world
            seenWorlds[name] = true
        end
    end
    -- Tampilkan denominasi yang dikonfigurasi meskipun jumlah teramatinya 0.
    for id, name in pairs(LOCK_OVERRIDES) do
        if type(name) == "string" then rowFor(job, id, lockInfo(job, id)) end
    end
    reports[job.requester] = nil
    active = job
    lastStarted = now
    message(player, "Scan parsial dimulai: " .. #job.playerIDs .. " player online, "
        .. #job.worldHandles .. " world loaded. Proses bertahap; ketik /scaneconomy untuk progres.")
    message(player, "`9Catatan: storage/vault, player offline, dan world unloaded tidak tercakup scan ini.")
    job.timer = timer.setInterval(1, function()
        -- Re-resolve peminta dan cek ulang role pada setiap tick.
        local requester = getPlayer(job.requester)
        if not isFounder(requester) then
            print("[scaneconomy] Stopped: requester offline or role changed.")
            stop(job)
            return
        end
        local ok, err = pcall(step, job, requester)
        if not ok then
            stop(job)
            reports[job.requester] = nil
            print("[scaneconomy] Scan aborted: " .. tostring(err))
            message(requester, "`4Scan gagal; hasil tidak diterbitkan. Periksa log Lua server.")
        end
    end)
end

registerLuaCommand {
    command = "scaneconomy",
    roleRequired = FOUNDER_ROLE,
    exactRole = true,
    description = "Founder: scan lock teramati (online/loaded; tanpa storage/vault).",
}

onPlayerCommandCallback(function(world, player, fullCommand)
    -- Docs mengatakan tanpa slash, beberapa contoh memakai slash: terima keduanya.
    local command, args = tostring(fullCommand):match("^%s*/?(%S+)%s*(.-)%s*$")
    if not command or command:lower() ~= "scaneconomy" then return false end
    if not isFounder(player) then
        message(player, "`4Command ini hanya untuk role Founder (1000).")
    elseif args ~= "" then
        message(player, "Cara pakai: /scaneconomy")
    else
        beginScan(player)
    end
    return true
end)

onPlayerDialogCallback(function(world, player, data)
    if data.dialog_name ~= DIALOG then return false end
    if not isFounder(player) then return true end
    local report = reports[player:getUserID()]
    local page = tostring(data.buttonClicked or ""):match("^page_(%d+)$")
    if report and page and #page <= 6 then showReport(player, report, tonumber(page)) end
    return true
end)

onPlayerDisconnectCallback(function(player)
    local id = player:getUserID()
    reports[id] = nil
    if active and active.requester == id then stop(active) end
end)

print("[scaneconomy] Loaded. /scaneconomy: founder only; partial online/loaded scan.")
