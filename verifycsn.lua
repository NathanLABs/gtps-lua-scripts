-- Developer: Nathan
-- Verified CSN world directory. Documented GTPS Lua APIs, Lua 5.1+.
local VERSION, KEY = "v4-remove", "verifycsn_worlds_v1"
local ICON, PAGE_SIZE, MAX_WORLDS = 758, 18, 1000 -- Roulette Wheel
local records, membership, sessions = {}, {}, {}
local ready, initError, serial = false, nil, 0
local UI = {}
local DIRECTORY_INTRO = "This is a list of all verified casino worlds, and you can see their worlds here, you can also report any issues with them, warp to worlds at any time, the world based on player count and ratings and top rated would be displayed up here."
local WELCOME_INTRO = "This casino is officially verified by GTPS. Please follow the rules to ensure a fair experience."
local RULES = {
    "- Hosters and players must use donation boxes to avoid drop scams.",
    "- Admins in this world must have a guarantee and assist with refund issues.",
    "- Gambling using items is strictly prohibited, only required locks (wl, dl, bgl, goldena) are allowed.",
    "- All players and hosters must be above level 10. Violators will be banned.",
    "- This world is monitored. Any scamming or rule breaking will result in a penalty, nuke, and bans for all involved.",
    "- Server staff only receive reports and do not provide direct refunds.",
}

local function clean(value, maxLength)
    return tostring(value or ""):gsub("`.", ""):gsub("[%c|`\\]", ""):sub(1, maxLength or 32)
end

local function worldName(value)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$"):upper()
    if #value < 1 or #value > 24 or not value:match("^[A-Z0-9]+$") then return nil end
    return value
end

-- JSON storage may decode a Lua array as an object with string indices.
-- Normalize dense 0/1-based indices before using # or ipairs, without dropping rows.
local function storedWorlds(data)
    local indexed, indices, normalized = {}, {}, false
    for key, row in pairs(data) do
        local kind = type(key)
        assert(kind=="number" or (kind=="string" and (key=="0" or key:match("^[1-9]%d*$"))),
            "Indeks daftar world tersimpan tidak valid; data tidak ditimpa.")
        local index = tonumber(key)
        assert(index and index>=0 and index<=MAX_WORLDS and index==math.floor(index),
            "Indeks daftar world tersimpan di luar batas; data tidak ditimpa.")
        assert(indexed[index]==nil and type(row)=="table",
            "Indeks world duplikat atau record bukan tabel; data tidak ditimpa.")
        indexed[index] = row
        indices[#indices+1] = index
        assert(#indices<=MAX_WORLDS, "Daftar tersimpan melebihi batas world.")
        normalized = normalized or kind=="string"
    end
    if #indices==0 then return {}, false end
    table.sort(indices)
    local first = indices[1]
    assert(first==0 or first==1, "Daftar world harus dimulai pada indeks 0 atau 1; data tidak ditimpa.")
    local ordered = {}
    for position, index in ipairs(indices) do
        assert(index==first+position-1, "Indeks daftar world tersimpan berlubang; data tidak ditimpa.")
        ordered[position] = indexed[index]
    end
    return ordered, normalized or first==0
end

local function realPlayer(p)
    return p and p:isOnline() and p:getType() == 0
end

local function founder(p)
    return realPlayer(p) and p:getRole() == 1000
end

local function tell(p, text)
    if p then p:onConsoleMessage("`6[Verify CSN] ``" .. text) end
end

local function guard(p, callback)
    local ok, err = pcall(function()
        if not realPlayer(p) then return end
        assert(ready, "Daftar world belum tersedia. Periksa log [verifycsn] di console server.")
        callback()
    end)
    if not ok then
        print("[verifycsn] ERROR: " .. tostring(err))
        tell(p, "`4" .. clean(err, 220))
    end
end

local function stats(world, name)
    local count, owner = 0, "-"
    if world then
        owner = clean(world:getOwner(), 32)
        if owner == "" then owner = "-" end
        for _, p in ipairs(world:getPlayers()) do
            if realPlayer(p) then count = count + 1 end
        end
    end
    local record = membership[name] or {}
    local ratingCount = record.ratingCount or 0
    local rating = ratingCount > 0 and (record.ratingTotal or 0) / ratingCount or 0
    return {name=name, owner=owner, count=count, exists=world ~= nil, rating=rating, ratingCount=ratingCount}
end

local function sortedWorlds()
    local rows = {}
    for _, record in ipairs(records) do
        rows[#rows+1] = stats(getWorld(record.name), record.name)
    end
    table.sort(rows, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if a.rating ~= b.rating then return a.rating > b.rating end
        return a.name < b.name
    end)
    return rows
end

local function send(p, view, body, allowed, extra, cancelLabel)
    assert(#body < 3500, "Dialog terlalu panjang.")
    serial = serial + 1
    local token = tostring(os.time()) .. "_" .. tostring(serial)
    local state = {view=view, token=token, allowed=allowed, expires=os.time()+180, extra=extra}
    local markup = "set_default_color|`o\nset_bg_color|32,62,90,180|\nset_border_color|255,255,255,255|\n"
        .. body .. "add_spacer|small|\nadd_smalltext|`9© Dibuat Oleh : Nathan``|\n"
        .. "embed_data|verifycsn_token|" .. token .. "\nend_dialog|verifycsn|" .. (cancelLabel or "") .. "||\n"
    assert(#markup <= 4096, "Dialog terlalu panjang.")
    local uid = p:getUserID()
    sessions[uid] = state
    local ok, result = pcall(p.onDialogRequest, p, markup)
    if not ok or result == false then
        sessions[uid] = nil
        error("Tidak dapat membuka dialog Verify CSN: " .. tostring(result))
    end
end

function UI.list(p, page)
    local rows = sortedWorlds()
    local pages = math.max(1, math.ceil(#rows / PAGE_SIZE))
    page = math.max(1, math.min(math.floor(tonumber(page) or 1), pages))
    local body = "add_label_with_icon|big|`oVerified Casino Worlds|left|" .. ICON .. "|\n"
        .. "add_textbox|`o" .. DIRECTORY_INTRO .. "|left|\n"
        .. "add_spacer|big|\nadd_label|small|`oList of verified casino worlds:|left|\nadd_spacer|big|\n"
    local allowed = {}
    if #rows == 0 then
        body = body .. "add_textbox|`oNo verified casino worlds yet.|left|\n"
    else
        for rank = (page-1)*PAGE_SIZE+1, math.min(page*PAGE_SIZE, #rows) do
            local row = rows[rank]
            local button = "world_" .. row.name
            -- Pink rank, cream remainder, matching the supplied directory screenshot.
            local label = "`o[`##" .. rank .. "`o] " .. row.name .. " (" .. row.count .. " Players) - Rated: " .. string.format("%.1f", row.rating) .. " (" .. row.ratingCount .. "x)"
            body = body .. "add_button|" .. button .. "|" .. label .. "|bigBlueButton|0|0|\n"
            allowed[button] = row.name
        end
    end
    if page > 1 then body = body .. "add_button|previous|Previous|noflags|0|0|\n"; allowed.previous = true end
    if page < pages then body = body .. "add_button|next|Next|noflags|0|0|\n"; allowed.next = true end
    if pages > 1 then body = body .. "add_smalltext|`oPage " .. page .. " / " .. pages .. "|\n" end
    body = body .. "add_spacer|big|\nadd_button|close|`oClose Menu|noflags|0|0|\n"
    allowed.close = true
    send(p, "list", body, allowed, {page=page})
end

function UI.welcome(world, p)
    local name = worldName(world:getName())
    if not name or not membership[name] or worldName(p:getWorldName()) ~= name then return end
    local body = "add_label|big|`2Welcome to Verified Casino!|left|\n"
        .. "add_textbox|`w" .. WELCOME_INTRO .. "|left|\nadd_spacer|big|\n"
    for _, rule in ipairs(RULES) do body = body .. "add_textbox|`o" .. rule .. "|left|\n" end
    body = body .. "add_spacer|big|\n"
    -- Native footer renders the yellow Continue button shown in the reference.
    send(p, "welcome", body, {}, {world=name}, "Continue")
end

local function add(p, input)
    assert(founder(p), "Perintah /addverify khusus Founder.")
    local name = assert(worldName(input), "Gunakan /addverify NAMAWORLD (1-24 huruf atau angka).")
    if membership[name] then tell(p, "`o" .. name .. " sudah terverifikasi."); return end
    assert(#records < MAX_WORLDS, "Daftar sudah mencapai batas " .. MAX_WORLDS .. " world.")
    local world = assert(getWorld(name), "World " .. name .. " tidak ditemukan.")
    assert(worldName(world:getName()) == name, "Nama world dari engine tidak cocok.")
    local row = {name=name, addedBy=p:getUserID(), addedAt=os.time(), ratingTotal=0, ratingCount=0}
    local nextRecords = {}
    for i, record in ipairs(records) do nextRecords[i] = record end
    nextRecords[#nextRecords+1] = row
    -- Commit before publishing to runtime; a failed save never grants verification.
    assert(saveDataToServer(KEY, {version=1, worlds=nextRecords}) == true, "Gagal menyimpan verifikasi world. Tidak ada perubahan.")
    records, membership[name] = nextRecords, row
    tell(p, "`2" .. name .. " berhasil ditambahkan ke daftar Verify CSN.")
    print("[verifycsn] VERIFIED world=" .. name .. " founder_uid=" .. tostring(row.addedBy))
end

local function remove(p, input)
    assert(founder(p), "Perintah /removeverify khusus Founder.")
    local name = assert(worldName(input), "Gunakan /removeverify NAMAWORLD (1-24 huruf atau angka).")
    if not membership[name] then tell(p, "`o" .. name .. " belum terverifikasi."); return end
    local nextRecords = {}
    for _, record in ipairs(records) do
        if record.name~=name then nextRecords[#nextRecords+1] = record end
    end
    -- Revoke only after persistence succeeds; deleted worlds can also be removed.
    assert(saveDataToServer(KEY, {version=1, worlds=nextRecords}) == true,
        "Gagal menyimpan pencabutan verifikasi. Tidak ada perubahan.")
    records, membership[name] = nextRecords, nil
    tell(p, "`2Verifikasi world " .. name .. " berhasil dicabut.")
    print("[verifycsn] REMOVED world=" .. name .. " founder_uid=" .. tostring(p:getUserID()))
end

local function command(_, p, full)
    if type(full) ~= "string" then return false end
    local name, args = full:match("^%s*/?(%S+)%s*(.-)%s*$")
    if not name then return false end
    name = name:lower()
    if name ~= "addverify" and name ~= "removeverify" and name ~= "verifycsn" then return false end
    guard(p, function()
        if name == "addverify" then add(p, args)
        elseif name == "removeverify" then remove(p, args)
        else
            assert(args == "", "Gunakan /verifycsn tanpa tambahan teks.")
            UI.list(p, 1)
        end
    end)
    return true
end

local function dialog(_, p, data)
    if type(data) ~= "table" or data.dialog_name ~= "verifycsn" then return false end
    guard(p, function()
        local uid = p:getUserID()
        local state = sessions[uid]
        -- A stale dialog cannot consume a newer session.
        if not state or data.verifycsn_token ~= state.token then
            tell(p, "`oMenu telah kedaluwarsa. Ketik /verifycsn untuk membuka daftar terbaru.")
            return
        end
        sessions[uid] = nil
        local button = data.buttonClicked
        if button == nil or button == "" or button == "cancel" then return end
        if os.time() > state.expires or not state.allowed[button] then
            tell(p, "`oMenu telah kedaluwarsa. Ketik /verifycsn untuk membuka daftar terbaru.")
            return
        end
        if button == "close" then return
        elseif button == "next" then UI.list(p, state.extra.page+1)
        elseif button == "previous" then UI.list(p, state.extra.page-1)
        else
            local destination = state.allowed[button]
            assert(type(destination) == "string" and membership[destination], "World tidak lagi terverifikasi.")
            assert(getWorld(destination), "World tidak tersedia saat ini.")
            assert(p:enterWorld(destination) == true, "Tidak dapat masuk ke world tersebut. Periksa pembatasan akses world.")
        end
    end)
    return true
end

local function install(label, callback, value)
    if type(callback) ~= "function" then print("[verifycsn] Missing API: " .. label); return false end
    local ok, result = pcall(callback, value)
    if not ok or result == false then print("[verifycsn] Registration failed: " .. label .. " / " .. tostring(result)); return false end
    return true
end

print("[verifycsn] BOOT " .. VERSION .. " | " .. tostring(_VERSION))
local hooked = install("command", onPlayerCommandCallback, command)
local registered = true
for _, spec in ipairs({{name="addverify",role=1000,description="Founder: tambahkan world Verify CSN."},{name="removeverify",role=1000,description="Founder: cabut verifikasi world CSN."},{name="verifycsn",role=0,description="Daftar world CSN terverifikasi."}}) do
    local name = spec.name
    local ok = install("/" .. name, registerLuaCommand, {
        command=name, roleRequired=spec.role, exactRole=spec.role==1000, description=spec.description,
        callback=function(p, args) return command(nil, p, name .. " " .. (args or "")) end,
    })
    registered = ok and registered
end
local dialogOK = install("dialog", onPlayerDialogCallback, dialog)
local enterOK = install("world entry", onPlayerEnterWorldCallback, function(world, p)
    if p then sessions[p:getUserID()] = nil end
    if not ready or not world or not realPlayer(p) then return end
    guard(p, function() UI.welcome(world, p) end)
end)
install("disconnect", onPlayerDisconnectCallback, function(p) if p then sessions[p:getUserID()] = nil end end)
print("[verifycsn] ROUTES registered=" .. tostring(registered) .. " command=" .. tostring(hooked) .. " dialog=" .. tostring(dialogOK) .. " enter=" .. tostring(enterOK))
ready, initError = pcall(function()
    assert((registered or hooked) and dialogOK and enterOK, "API command/dialog/world entry tidak tersedia.")
    assert(type(getWorld)=="function" and type(loadDataFromServer)=="function" and type(saveDataToServer)=="function", "API world/storage tidak tersedia.")
    local saved = loadDataFromServer(KEY)
    if saved == nil then return end
    assert(type(saved)=="table" and saved.version==1 and type(saved.worlds)=="table", "Format data Verify CSN tidak valid; data tidak ditimpa.")
    local ordered, normalized = storedWorlds(saved.worlds)
    local nextRecords, nextMembership = {}, {}
    for index, row in ipairs(ordered) do
        local name = worldName(row.name)
        assert(name and name==row.name and not nextMembership[name], "Record world tidak valid pada posisi " .. index)
        local count = row.ratingCount==nil and 0 or row.ratingCount
        local total = row.ratingTotal==nil and 0 or row.ratingTotal
        assert(type(count)=="number" and count>=0 and count<=1000000 and count==math.floor(count)
            and type(total)=="number" and total>=0 and total<=5*count and total==math.floor(total), "Data rating world tidak valid pada posisi " .. index)
        nextRecords[#nextRecords+1], nextMembership[row.name] = row, row
    end
    records, membership = nextRecords, nextMembership
    if normalized then print("[verifycsn] STORAGE normalized " .. #records .. " world indices to Lua array") end
end)
print(ready and ("[verifycsn] Loaded " .. #records .. " verified worlds | /addverify /removeverify /verifycsn") or ("[verifycsn] INIT FAILED: " .. tostring(initError)))
