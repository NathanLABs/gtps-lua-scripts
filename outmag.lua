-- Developer: Nathan
-- Per-MAG DROP ALL ITEM button, Lua 5.1+.
-- Extraction is NOT operational without OutmagNative API version 2.
-- See outmag-README.md. No undocumented MAG fields are read or written here.
local busy, pending, sessions, sending = {}, {}, {}, {}
local MAG_IDS = {[5638]=true, [5930]=true, [9850]=true, [10266]=true, [21220]=true}
local PREFIX, serial = "outmag_drop_", 0
local messages = {
    blocked = "Cannot drop items: the tile in front of you is blocked.",
    bounds = "Cannot drop items: the tile in front of you is outside the world.",
    denied = "You do not have permission to empty this MAG.",
    protected = "Cannot empty this MAG: the machine is protected.",
    empty = "There are no stored items in this MAG.",
    capacity = "Cannot drop items: the world drop limit would be exceeded.",
    unavailable = "Cannot empty this MAG: this server needs the OutmagNative engine extension.",
    changed = "This MAG has changed. Please wrench it again.",
    distance = "Please stand closer to this MAG and wrench it again.",
    failed = "Cannot empty this MAG: the operation failed. Please check the server log.",
}

local function tell(player, message)
    player:onConsoleMessage("`6[OutMag] ``" .. message)
end

local function formatNumber(n)
    local s = string.format("%.0f", n)
    repeat
        local count
        s, count = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        if count == 0 then return s end
    until false
end

local function positiveInteger(n)
    return type(n) == "number" and n > 0 and n <= 9007199254740991 and n == math.floor(n)
end

local function run(world, player, target)
    if not player or not player:isOnline() or player:getType() ~= 0 then return end
    world = world or player:getWorld()
    if not world or world:getName() ~= player:getWorldName() then
        tell(player, "Cannot empty this MAG: please enter a world first.")
        return
    end
    local name = world:getName()
    if not target or target.world ~= name then tell(player, messages.changed); return end
    local current
    for _, tile in ipairs(world:getTiles()) do
        if tile:getPosX() == target.x and tile:getPosY() == target.y then current = tile; break end
    end
    if not current or current:getTileForeground() ~= target.item then tell(player, messages.changed); return end
    if busy[name] then
        tell(player, "Please wait: another MAG operation is in progress.")
        return
    end
    -- A custom extension contract, NOT an existing API in docslua...txt.
    local native = rawget(_G, "OutmagNative")
    if type(native) ~= "table" or native.apiVersion ~= 2 or type(native.drainMagInFront) ~= "function" then
        tell(player, messages.unavailable)
        return
    end
    busy[name] = true
    local ok, result = pcall(native.drainMagInFront, world, player, target.x, target.y, target.item)
    busy[name] = nil
    if not ok then
        print("[outmag] ENGINE ERROR: " .. tostring(result))
        tell(player, messages.failed)
        return
    end
    if type(result) ~= "table" or type(result.ok) ~= "boolean" then
        print("[outmag] Invalid engine result; no automatic retry performed.")
        tell(player, messages.failed)
    elseif result.ok then
        if not positiveInteger(result.items) then
            print("[outmag] Invalid engine receipt; no automatic retry performed.")
            tell(player, messages.failed)
            return
        end
        tell(player, "`2Dropped " .. formatNumber(result.items) .. " items from this MAG one tile in front of you.")
    else
        tell(player, messages[result.code] or messages.failed)
    end
end

local function command(world, player, full)
    if type(full) ~= "string" then return false end
    local name, args = full:match("^%s*/?(%S+)%s*(.-)%s*$")
    if not name or name:lower() ~= "outmag" then return false end
    if args ~= "" then tell(player, "Usage: /outmag"); return true end
    tell(player, "Wrench a MAG, then press DROP ALL ITEM to empty that machine.")
    return true
end

local function wrench(world, player, tile)
    local uid = player:getUserID()
    pending[uid], sessions[uid] = nil, nil
    local item = tile:getTileForeground()
    if not MAG_IDS[item] then return end
    pending[uid] = {world=world:getName(), x=tile:getPosX(), y=tile:getPosY(), item=item, expires=os.time()+2}
end

-- Bind to the server-side wrench selection and the matching native title icon.
-- Keep the original dialog name, embedded fields, and built-in buttons intact.
local function outgoing(player, packet)
    if type(packet) ~= "table" or packet[1] ~= "OnDialogRequest" or type(packet[2]) ~= "string" then return false end
    local uid = player:getUserID()
    if sending[uid] then return false end
    sessions[uid] = nil
    local target = pending[uid]
    pending[uid] = nil -- Only the first dialog after this wrench can be extended.
    if not target or os.time() > target.expires or player:getWorldName() ~= target.world then return false end
    local text = packet[2]
    local framed = "\n" .. text
    local icon = framed:match("\nadd_label_with_icon|[^|\r\n]*|[^|\r\n]*|[^|\r\n]*|(%d+)|")
    local dialogName = framed:match("\nend_dialog|([^|\r\n]+)|")
    if tonumber(icon) ~= target.item or not dialogName then return false end
    serial = serial + 1
    target.button = PREFIX .. tostring(serial)
    target.dialog = dialogName
    target.expires = os.time() + 120
    local extra = "add_spacer|small|\nadd_button|" .. target.button .. "|`2DROP ALL ITEM``|noflags|0|0|\n"
    local credit = "add_smalltext|`9© Dibuat Oleh : Nathan``|\n"
    if not framed:find("\n" .. credit, 1, true) then extra = extra .. "add_spacer|small|\n" .. credit end
    local replaced, count = framed:gsub("\nend_dialog|", function() return "\n" .. extra .. "end_dialog|" end, 1)
    replaced = replaced:sub(2)
    if count ~= 1 or #replaced > 4096 then return false end
    local copy = {}
    for i, value in ipairs(packet) do copy[i] = value end
    copy[2] = replaced
    sending[uid] = true
    local ok, result = pcall(player.sendVariant, player, copy)
    sending[uid] = nil
    if not ok or result == false then print("[outmag] Dialog injection failed: " .. tostring(result)); return false end
    sessions[uid] = target
    return true
end

local function dialog(world, player, data)
    if type(data) ~= "table" then return false end
    local uid = player:getUserID()
    local state = sessions[uid]
    local clicked = type(data.buttonClicked) == "string" and data.buttonClicked or ""
    if clicked:sub(1, #PREFIX) ~= PREFIX then
        if state and data.dialog_name == state.dialog then sessions[uid] = nil end
        return false -- Original MAG controls continue through the native handler.
    end
    sessions[uid] = nil -- Consume before native mutation; duplicate clicks cannot replay it.
    if not state or data.dialog_name ~= state.dialog or clicked ~= state.button or os.time() > state.expires then
        tell(player, "This MAG menu has expired. Please wrench the MAG again.")
        return true
    end
    local ok, err = pcall(run, world, player, state)
    if not ok then print("[outmag] DROP ERROR: " .. tostring(err)); tell(player, messages.failed) end
    return true
end

local function clear(player)
    local uid = player:getUserID()
    pending[uid], sessions[uid], sending[uid] = nil, nil, nil
end

local function install(label, callback, value)
    if type(callback) ~= "function" then print("[outmag] Missing API: " .. label); return false end
    local ok, result = pcall(callback, value)
    if not ok or result == false then print("[outmag] Cannot register " .. label .. ": " .. tostring(result)); return false end
    return true
end

print("[outmag] BOOT v2-per-mag | " .. tostring(_VERSION))
local wrenchOK = install("wrench hook", onTileWrenchCallback, wrench)
local sendOK = install("outgoing dialog hook", onPlayerSendRaw, outgoing)
local dialogOK = install("dialog hook", onPlayerDialogCallback, dialog)
install("disconnect cleanup", onPlayerDisconnectCallback, clear)
install("world cleanup", onPlayerEnterWorldCallback, function(_, player) clear(player) end)
local hooked = install("command hook", onPlayerCommandCallback, command)
local registered = install("/outmag", registerLuaCommand, {
    command = "outmag", roleRequired = 0, exactRole = false,
    description = "How to use the DROP ALL ITEM button on a MAG.",
    callback = function(player, args) return command(nil, player, "outmag " .. (args or "")) end,
})
print("[outmag] ROUTES registered=" .. tostring(registered) .. " command=" .. tostring(hooked))
print("[outmag] BUTTON wrench=" .. tostring(wrenchOK) .. " outgoing=" .. tostring(sendOK) .. " dialog=" .. tostring(dialogOK))
local native = rawget(_G, "OutmagNative")
if type(native) ~= "table" or native.apiVersion ~= 2 or type(native.drainMagInFront) ~= "function" then
    print("[outmag] NOT READY: MAG extraction/facing API missing. See outmag-README.md.")
end
