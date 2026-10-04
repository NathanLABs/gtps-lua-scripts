-- Developer: Nathan
-- World-owner drop cleaner. Preview and confirmation use a one-use snapshot.
local PREFIX, COOLDOWN_SECONDS, MAX_ITEM_TYPES, SESSION_SECONDS = "cleardrop2_", 3, 20, 120
local previous = rawget(_G, "ClearDrop2Runtime")
local generation = type(previous)=="table" and tonumber(previous.generation) or 0
if not generation or generation<0 or generation>=9007199254740990 then generation=0 end
local runtime = {generation=math.floor(generation)+1}
_G.ClearDrop2Runtime = runtime
local sessions, lastUsed, lastCleared, serial = {}, {}, {}, 0

local function msg(player, text)
    player:onConsoleMessage("`6[ClearDrop2] ``" .. text)
end
local function integer(value)
    return type(value)=="number" and value>=1 and value<=9007199254740991
        and value==math.floor(value) and value or nil
end
local function dropUID(value)
    -- The native UID range does not exclude zero (unlike account/item IDs).
    return value==0 and 0 or integer(value)
end
local function clean(value)
    return tostring(value or ""):gsub("`.", ""):gsub("[|%c]", " ")
end
local function number(value)
    return string.format("%.0f", value):reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
end

-- Display names are mutable (/nick). Resolve the native owner account instead.
-- Account lookup and native access must agree, otherwise deny without mutation.
local function ownerID(world, player)
    local ok, result = pcall(function()
        if not world or not player or not player:isOnline() or player:getType()~=0 then return nil end
        local id = integer(player:getUserID())
        local current = player:getWorld()
        local name = world:getName()
        if not id or type(name)~="string" or name=="" or not current
            or current:getName()~=name or player:getWorldName()~=name then return nil end
        local owner = world:getOwner()
        if type(owner)~="string" or owner=="" or type(getPlayerByName)~="function" then return nil end
        local account = getPlayerByName(owner)
        if not account or not account:isOnline() or account:getType()~=0
            or integer(account:getUserID())~=id or world:hasAccess(player)~=true then return nil end
        return id
    end)
    return ok and result or nil
end

local function showDialog(world, player)
    local id = assert(ownerID(world, player), "Owner permission could not be verified.")
    local groups, order, seen = {}, {}, {}
    for _, drop in ipairs(world:getDroppedItems() or {}) do
        local item, count, dropID = integer(drop:getItemID()), integer(drop:getItemCount()), dropUID(drop:getUID())
        assert(item and count and dropID and not seen[dropID], "Invalid drop snapshot.")
        seen[dropID] = true
        if not groups[item] then
            groups[item] = {count=0, piles={}}
            order[#order+1] = item
        end
        local group = groups[item]
        assert(group.count+count<=9007199254740991, "Drop total exceeds the supported limit.")
        group.count = group.count+count
        group.piles[#group.piles+1] = {uid=dropID,item=item,count=count}
    end
    sessions[id] = nil
    if #order==0 then msg(player, "Tidak ada item yang terjatuh di world ini."); return end
    table.sort(order, function(a,b)
        if groups[a].count~=groups[b].count then return groups[a].count>groups[b].count end
        return a<b
    end)
    serial = serial+1
    local state = {name=PREFIX..runtime.generation.."_"..serial,world=world:getName(),owner=id,
        expires=os.time()+SESSION_SECONDS,offered={},drops={}}
    local lines = {
        "add_label|big|`wClear Drop Selektif``|left|\n",
        "add_smalltext|World: `w"..clean(state.world).."``|\n",
        "add_smalltext|Centang item yang ingin dibersihkan. Hanya tumpukan pada preview ini yang akan dihapus.|\n",
        "add_spacer|small|\n",
    }
    for i=1,math.min(#order,MAX_ITEM_TYPES) do
        local item, group = order[i], groups[order[i]]
        local catalog = getItem(item)
        local label = catalog and clean(catalog:getName()):sub(1,70) or ("Item #"..item)
        if label=="" then label="Item #"..item end
        lines[#lines+1] = "add_checkbox|item_"..item.."|"..label.."  `w["..number(group.count)
            .." item, "..#group.piles.." tumpukan]``|0|\n"
        state.offered[item] = true
        for _, pile in ipairs(group.piles) do state.drops[pile.uid] = pile end
    end
    if #order>MAX_ITEM_TYPES then
        lines[#lines+1] = "add_smalltext|`9"..(#order-MAX_ITEM_TYPES).." jenis item lain tidak ditampilkan dan tidak akan dihapus.``|\n"
    end
    lines[#lines+1] = "add_spacer|small|\nadd_checkbox|select_all|`2Pilih Semua Item di Atas``|0|\n"
    lines[#lines+1] = "add_button|clear|`4Bersihkan Item Terpilih``|noflags|0|0|\n"
    lines[#lines+1] = "add_spacer|small|\nadd_smalltext|`9© Dibuat Oleh : Nathan``|\n"
    lines[#lines+1] = "end_dialog|"..state.name.."|Batal||\n"
    local markup = table.concat(lines)
    assert(#markup<=4096, "Dialog preview is too long.")
    sessions[id] = state
    local ok, result = pcall(player.onDialogRequest, player, markup)
    if not ok or result==false then sessions[id]=nil; error("Cannot open drop preview.") end
end

local function processClear(world, player, state, data)
    assert(ownerID(world,player)==state.owner and world:getName()==state.world, "World ownership changed. Open a new preview.")
    assert(data.select_all==nil or data.select_all=="0" or data.select_all=="1", "Invalid checkbox value.")
    local selected = {}
    for key, value in pairs(data) do
        if type(key)=="string" and key:sub(1,5)=="item_" then
            local item = tonumber(key:match("^item_([1-9]%d*)$"))
            assert(item and state.offered[item] and (value=="0" or value=="1"), "Item was not offered in this preview.")
            if value=="1" then selected[item]=true end
        end
    end
    if data.select_all=="1" then for item in pairs(state.offered) do selected[item]=true end end
    if not next(selected) then msg(player, "Tidak ada item yang dipilih."); return end
    local current, removal = {}, {}
    for _, drop in ipairs(world:getDroppedItems() or {}) do
        local dropID = dropUID(drop:getUID())
        assert(dropID and not current[dropID], "Invalid current drop snapshot.")
        current[dropID] = {item=drop:getItemID(),count=drop:getItemCount()}
    end
    -- Validate every selected pile before the first delete; never add new drops.
    for dropID, snapshot in pairs(state.drops) do
        if selected[snapshot.item] then
            local pile = current[dropID]
            assert(pile and pile.item==snapshot.item and pile.count==snapshot.count,
                "Items changed since the preview. Open /cleardrop2 again.")
            removal[#removal+1] = snapshot
        end
    end
    local now = os.time()
    local previousClear = lastCleared[state.owner]
    assert(not previousClear or now-previousClear>=COOLDOWN_SECONDS, "Please wait before clearing items again.")
    assert(ownerID(world,player)==state.owner, "World ownership changed. No items were removed.")
    lastCleared[state.owner] = now
    local removed, count = 0, 0
    for _, pile in ipairs(removal) do
        -- Copy counts from the reviewed Lua snapshot; native handles can become
        -- invalid immediately after removeDroppedItem.
        if ownerID(world,player)~=state.owner then break end
        if world:removeDroppedItem(pile.uid)==true then
            removed, count = removed+1, count+pile.count
        end
    end
    msg(player, "`2Berhasil membersihkan "..number(count).." item ("..removed.." tumpukan).")
end

local function protect(player, fn)
    local ok, err = pcall(fn)
    if not ok then
        print("[cleardrop2] ERROR: "..tostring(err))
        if player then msg(player, "`4Item tidak dibersihkan atau hanya sebagian diproses. Buka preview baru; periksa log jika error berulang.") end
    end
end

registerLuaCommand {command="cleardrop2",roleRequired=0,description="World owner: bersihkan drop item tertentu di world kamu."}
onPlayerCommandCallback(function(world, player, fullCommand)
    if _G.ClearDrop2Runtime~=runtime then return false end
    local command = tostring(fullCommand):match("^%s*/?(%S+)")
    if not command or command:lower()~="cleardrop2" then return false end
    protect(player, function()
        local id = ownerID(world,player)
        if not id then msg(player,"`4Hanya world owner yang terverifikasi engine bisa menggunakan command ini."); return end
        local now = os.time()
        if lastUsed[id] and now-lastUsed[id]<COOLDOWN_SECONDS then msg(player,"Tunggu sebelum membuka preview lagi."); return end
        lastUsed[id] = now
        showDialog(world,player)
    end)
    return true
end)

onPlayerDialogCallback(function(world, player, data)
    if _G.ClearDrop2Runtime~=runtime or type(data)~="table" or type(data.dialog_name)~="string"
        or data.dialog_name:sub(1,#PREFIX)~=PREFIX then return false end
    protect(player, function()
        local id = player and integer(player:getUserID())
        local state = id and sessions[id]
        if not state or state.name~=data.dialog_name then msg(player,"`4Preview telah kedaluwarsa. Ketik /cleardrop2 lagi."); return end
        sessions[id] = nil -- Consume before cancel, validation, or native mutation.
        local clicked = data.buttonClicked
        if data.quit=="1" or data.quit==1 or clicked==nil or clicked=="" or clicked=="cancel" or clicked=="Batal" then return end
        assert(clicked=="clear" and os.time()<state.expires, "Preview expired or button was not offered.")
        processClear(world,player,state,data)
    end)
    return true
end)

local function clear(player)
    if _G.ClearDrop2Runtime~=runtime or not player then return end
    local id = player:getUserID()
    sessions[id],lastUsed[id],lastCleared[id] = nil,nil,nil
end
onPlayerDisconnectCallback(clear)
onPlayerEnterWorldCallback(function(_, player) clear(player) end)
onPlayerLeaveWorldCallback(function(_, player) clear(player) end)
print("[cleardrop2] Loaded. /cleardrop2: native owner authorization and one-use drop preview.")
