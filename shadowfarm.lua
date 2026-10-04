-- Developer: Nathan
-- /shadowfarm: online owner-linked BFG, through an engine extension.
-- ShadowfarmNative is an integration contract, NOT an API in docslua...txt.
-- Without that extension, show unavailable; do not create a cosmetic worker,
-- fabricate MAG stock, transfer NPC loot, multiply gems, or elevate NPC roles.
local VERSION, DB_FILE = "v1-native-control", "shadowfarm_v1.db"
local MAX_AMOUNT, MAX_SAFE, SESSION_SECONDS = 2000000000, 9007199254740991, 120
local CAPABILITIES = {"npcMirror","ownerLinkedBfg","ownerRewards","onlineOnly","worldLease","nativeMultipliers","playerHandoff","cleanupOnReload"}
local CHEATS = {"autofarm","autocollect","autofish","antibounce","fastdrop","fastpull","fasttrash","speed","jump","double_jump","heat_resist","strong_punch","long_punch","long_build"}
local db, ready, generation, initError, initializedAdapter
local Runtime, UI = {version=1}, {}
local sessions, workers, busy, pendingStarts, serial = {}, {}, {}, {}, 0

local function integer(n,low,high)
    return type(n)=="number" and n==n and n>=low and n<=high and n==math.floor(n) and n or nil
end
local function number(n) return string.format("%.0f",n) end
local function fmt(n) return number(n):reverse():gsub("(%d%d%d)","%1."):reverse():gsub("^%.","") end
local function clean(v,max) return tostring(v or ""):gsub("`.",""):gsub("[|%c]"," "):sub(1,max or 180) end
local function uid(p) return assert(integer(p:getUserID(),1,MAX_SAFE),"ID akun tidak valid.") end
local function realPlayer(p) return p and p:isOnline() and p:getType()==0 end
local function tell(p,s) p:onConsoleMessage("`3[ShadowFarm]`` " .. s) end
local function notify(p,s) pcall(function() if realPlayer(p) then tell(p,s) end end) end
local function query(s) return assert(db:query(s),"Database sesi ShadowFarm tidak dapat diakses.") end
local function token(v)
    return type(v)=="string" and #v>0 and #v<=96 and v:match("^[%w_:%-%.]+$") and v or nil
end
local function worldName(v)
    return type(v)=="string" and #v>0 and #v<=24 and v:match("^[%w]+$") and v or nil
end
local function native()
    local api=rawget(_G,"ShadowfarmNative")
    if type(api)~="table" or api.apiVersion~=1 or type(api.capabilities)~="table" then return nil end
    for _,name in ipairs(CAPABILITIES) do if api.capabilities[name]~=true then return nil end end
    for _,name in ipairs({"beginGeneration","start","status","stop"}) do if type(api[name])~="function" then return nil end end
    if initializedAdapter~=api then
        assert(api.beginGeneration(generation)==true,"Engine belum berhasil membersihkan sesi ShadowFarm sebelumnya.")
        initializedAdapter=api
    end
    return api
end
local function status(api,id)
    local row=api.status(id)
    assert(type(row)=="table" and row.ownerID==id and type(row.active)=="boolean","Status ShadowFarm dari engine tidak valid.")
    if not row.active then return {ownerID=id,active=false,reason=clean(row.reason or "",120)} end
    local result={ownerID=id,active=true,sessionId=assert(token(row.sessionId),"ID sesi native tidak valid."),
        requestId=assert(token(row.requestId),"ID request native tidak valid."),
        generation=assert(integer(row.generation,1,MAX_SAFE),"Generasi sesi native tidak valid."),
        world=assert(worldName(row.world),"World farm native tidak valid."),
        npcName=assert(type(row.npcName)=="string" and #row.npcName>0 and #row.npcName<=30 and row.npcName,"Nama clone native tidak valid."),
        target=assert(integer(row.target,1,MAX_AMOUNT),"Target BFG native tidak valid."),
        slots=assert(integer(row.slots,1,MAX_AMOUNT),"Slot autofarm native tidak valid."),
        delayMs=assert(integer(row.delayMs,0,60000),"Delay autofarm native tidak valid."),
        startedAt=assert(integer(row.startedAt,0,MAX_SAFE),"Waktu mulai native tidak valid."),
        gemsEarned=assert(integer(row.gemsEarned or 0,0,MAX_SAFE),"Statistik gems native tidak valid."),
        blocksBroken=assert(integer(row.blocksBroken or 0,0,MAX_SAFE),"Statistik block native tidak valid.")}
    return result
end
local function snapshot(p)
    local world=assert(p:getWorld(),"Masuk ke world BFG terlebih dahulu.")
    local profile={ownerID=uid(p),ownerName=clean(p:getName(),30),world=assert(worldName(world:getName()),"Nama world BFG tidak valid."),
        role=assert(integer(p:getRole(),0,MAX_AMOUNT),"Role tidak valid."),clothes={},cheats={}}
    profile.x=p:getPosX(); profile.y=p:getPosY()
    assert(type(profile.x)=="number" and profile.x==profile.x and profile.x>=0 and profile.x<=MAX_AMOUNT
        and type(profile.y)=="number" and profile.y==profile.y and profile.y>=0 and profile.y<=MAX_AMOUNT,"Posisi karakter tidak valid.")
    for slot=0,9 do
        local item=assert(integer(p:getClothingItemID(slot),0,MAX_AMOUNT),"Pakaian karakter tidak valid.")
        assert(item==0 or getItem(item),"Item pakaian tidak tersedia di server.")
        profile.clothes[slot+1]=item
    end
    local r,g,b,a=p:getSkin()
    profile.skin={assert(integer(r,0,255),"Warna kulit tidak valid."),assert(integer(g,0,255),"Warna kulit tidak valid."),
        assert(integer(b,0,255),"Warna kulit tidak valid."),assert(integer(a,0,255),"Warna kulit tidak valid.")}
    for _,name in ipairs(CHEATS) do profile.cheats[name]=p:getCheat(name)==true end
    assert(profile.cheats.autofarm,"Aktifkan Autofarm lewat /cheats dan atur BFG terlebih dahulu.")
    local af=assert(p:getAutofarm(),"Setting autofarm tidak tersedia.")
    profile.target=assert(integer(af:getTargetBlockID(),1,MAX_AMOUNT),"Pilih target block BFG terlebih dahulu.")
    assert(getItem(profile.target),"Target block BFG tidak tersedia di server.")
    profile.slots=assert(integer(af:getSlots(),1,MAX_AMOUNT),"Jumlah slot autofarm belum diatur.")
    profile.delayMs=assert(integer(p:getCustomAutofarmDelay(),0,60000),"Delay autofarm tidak valid.")
    if type(getAutofarmMaxFar)=="function" then
        profile.serverMaxFar=assert(integer(getAutofarmMaxFar(),-1,99),"Batas autofarm server tidak valid.")
        assert(profile.serverMaxFar==-1 or profile.serverMaxFar>0,"Autofarm sedang dibatasi server.")
    end
    return profile
end
local function remember(id,row)
    if row.active then workers[id]={sessionId=row.sessionId,world=row.world}
    else workers[id]=nil end
end
local function cleanup(id,expected)
    local ok,result=pcall(function()
        local api=assert(native(),"Dukungan engine ShadowFarm tidak tersedia.")
        api.stop(id,expected)
        local row=status(api,id)
        -- A stale stop must not erase a replacement session.
        if row.active then
            remember(id,row)
            return expected and row.sessionId~=expected or false
        end
        workers[id]=nil
        return true
    end)
    if not ok or result~=true then
        local record=workers[id] or {}
        record.needsCleanup=true
        record.cleanupSession=expected
        workers[id]=record
        print("[shadowfarm] CLEANUP PENDING uid=" .. number(id) .. " / " .. tostring(result))
        return false
    end
    return true
end

local function begin(title)
    return {"set_default_color|`w\nset_bg_color|20,24,31,230|\nset_border_color|92,104,122,255|\nadd_label|big|`w" .. title .. "``|left|\nadd_spacer|small|\n"}
end
local function text(L,s) L[#L+1]="add_smalltext|" .. s .. "|\n" end
local function button(L,key,label) L[#L+1]="add_button|" .. key .. "|" .. label .. "|noflags|0|0|\n" end
local function show(p,L,state)
    serial=serial+1
    state.name="shadowfarm_" .. number(generation) .. "_" .. number(serial)
    state.expires,state.buttons=os.time()+SESSION_SECONDS,{}
    for _,line in ipairs(L) do local key=line:match("^add_button|([^|]+)|"); if key then state.buttons[key]=true end end
    L[#L+1]="add_spacer|small|\nadd_smalltext|`9© Dibuat Oleh : Nathan``|\n"
    L[#L+1]="end_dialog|" .. state.name .. "|Tutup||\n"
    local markup=table.concat(L)
    assert(#markup<=4096,"Dialog ShadowFarm terlalu panjang.")
    sessions[uid(p)]=state
    local ok,result=pcall(p.onDialogRequest,p,markup)
    if not ok or result==false then sessions[uid(p)]=nil; error("Menu ShadowFarm tidak dapat dibuka.") end
end
function UI.unavailable(p)
    local L=begin("SHADOW FARM")
    text(L,"`oFarm belum diaktifkan.``")
    L[#L+1]="add_textbox|Engine server belum menyediakan penghubung NPC ke BFG, MAG, dan hasil farm pemilik. Minta Owner server mengaktifkan dukungan ShadowFarm terlebih dahulu.|left|\n"
    text(L,"Setelah tersedia, clone memakai pakaian dan setting autofarm saat mulai.")
    button(L,"refresh","Periksa Lagi"); button(L,"help","Cara Pakai")
    show(p,L,{view="unavailable"})
end
function UI.help(p)
    local L=begin("SHADOW FARM - PANDUAN")
    for _,s in ipairs({"1. Masuk ke world BFG dan siapkan target block/slot lewat /cheats.",
        "2. Pakai set pakaianmu, termasuk item bonus gems yang ingin digunakan.",
        "3. Ketik /shadowfarm. Farm dimulai jika engine mendukung dan setting valid.",
        "4. Kamu boleh pindah world; clone tetap bekerja di world BFG asal.",
        "5. Kamu harus tetap online. Logout menghentikan clone dan farm.",
        "6. Gunakan /shadowfarm stop untuk berhenti. /shadowfarm status membuka informasi farm."}) do
        L[#L+1]="add_textbox|" .. s .. "|left|\n"
    end
    text(L,"Bonus pakaian, jumlah slot, stok, dan akses mengikuti aturan server.")
    button(L,"back","Back"); show(p,L,{view="help"})
end
function UI.status(p,row,notice)
    local L=begin("SHADOW FARM")
    if notice then text(L,"`o" .. clean(notice,160) .. "``") end
    if row.active then
        text(L,"Status: `3AKTIF``  /  Pemilik tetap harus online.")
        text(L,"World farm: `w" .. clean(row.world,24) .. "``  /  Clone: " .. clean(row.npcName,30))
        local item=getItem(row.target)
        if item then L[#L+1]="add_label_with_icon|small|`w" .. clean(item:getName(),32) .. "``|left|" .. row.target .. "|\n" end
        text(L,"Slot autofarm: `w" .. fmt(row.slots) .. "``  /  Delay: " .. (row.delayMs==0 and "Default server" or (fmt(row.delayMs) .. " ms")))
        text(L,"Durasi: " .. fmt(math.max(0,os.time()-row.startedAt)) .. " detik")
        text(L,"Block dihancurkan: " .. fmt(row.blocksBroken) .. "  /  Gems diperoleh: " .. fmt(row.gemsEarned))
        text(L,"`oKamu boleh pindah world. Pakaian clone mengikuti snapshot saat mulai.``")
        button(L,"stop","Stop ShadowFarm")
    else
        text(L,"Status: `oTIDAK AKTIF``")
        text(L,"Siapkan pakaian, target block, dan slot autofarm di world BFG.")
        if row.reason and row.reason~="" then text(L,"`o" .. row.reason .. "``") end
        button(L,"start","Start ShadowFarm")
    end
    button(L,"refresh","Refresh"); button(L,"help","Cara Pakai")
    show(p,L,{view="status",sessionId=row.active and row.sessionId or nil})
end
local function inspect(p,notice)
    local api=native()
    if not api then UI.unavailable(p); return end
    local id=uid(p)
    if workers[id] and workers[id].needsCleanup then
        assert(cleanup(id,workers[id].cleanupSession),"Sesi sebelumnya belum selesai dibersihkan. Hubungi Owner server.")
    end
    local row=status(api,id)
    assert(not row.active or row.generation==generation,"Engine masih menyimpan sesi ShadowFarm dari versi sebelumnya.")
    remember(id,row)
    UI.status(p,row,notice)
end
local function start(p)
    local api=native()
    if not api then UI.unavailable(p); return end
    local id=uid(p)
    local pending={cancelled=false}
    pendingStarts[id]=pending
    if workers[id] and workers[id].needsCleanup then
        assert(cleanup(id,workers[id].cleanupSession),"Sesi sebelumnya belum selesai dibersihkan. Hubungi Owner server.")
    end
    local before=status(api,id)
    if before.active then inspect(p); return end
    local profile=snapshot(p)
    if _G.ShadowfarmControl~=Runtime then return end
    assert(not pending.cancelled and realPlayer(p),"ShadowFarm dibatalkan karena koneksi pemain berakhir.")
    profile.generation=generation
    serial=serial+1
    local requestId="sf:" .. number(generation) .. ":" .. number(id) .. ":" .. number(serial)
    pending.requestId=requestId
    workers[id]={needsCleanup=true,world=profile.world}
    local ok,result=pcall(api.start,p,profile,requestId)
    local readOK,row=pcall(status,api,id)
    if pendingStarts[id]==pending then pendingStarts[id]=nil end
    -- Reload supersedes this controller. Only stop its own proven receipt;
    -- the new native generation must cancel older work even without a receipt.
    if _G.ShadowfarmControl~=Runtime then
        if ok and type(result)=="table" and token(result.sessionId) then pcall(api.stop,id,result.sessionId) end
        return
    end
    local playerOK,online=pcall(function() return realPlayer(p) and uid(p)==id end)
    if pending.cancelled or not playerOK or not online then
        cleanup(id,nil)
        error("ShadowFarm dibatalkan karena koneksi pemain berakhir.")
    end
    if ok and type(result)=="table" and result.ok==false and readOK and not row.active then
        workers[id]=nil
        UI.status(p,row,clean(result.reason or "Engine menolak setting ShadowFarm.",160)); return
    end
    local valid=ok and type(result)=="table" and result.ok==true and readOK and row.active
        and token(result.sessionId) and row.sessionId==result.sessionId and row.ownerID==id and row.requestId==requestId
        and row.generation==generation and row.world==profile.world and row.target==profile.target and row.delayMs==profile.delayMs and row.slots<=profile.slots
        and (not profile.serverMaxFar or profile.serverMaxFar==-1 or row.slots<=profile.serverMaxFar)
    if not valid then
        cleanup(id,nil)
        print("[shadowfarm] START NOT VERIFIED uid=" .. number(id) .. " api_ok=" .. tostring(ok) .. " read_ok=" .. tostring(readOK))
        error("ShadowFarm belum terkonfirmasi. Sesi tidak akan dimulai ulang otomatis; periksa log server.")
    end
    remember(id,row)
    notify(p,"`3ShadowFarm aktif di " .. clean(row.world,24) .. ".`` Kamu boleh pindah world selama tetap online.")
    UI.status(p,row)
end
local function stop(p,expected)
    local api=native()
    if not api then UI.unavailable(p); return end
    local id=uid(p)
    local row=status(api,id)
    if expected and (not row.active or row.sessionId~=expected) then inspect(p,"Sesi farm berubah. Periksa informasi terbaru."); return end
    assert(cleanup(id,row.active and row.sessionId or nil),"Engine belum mengonfirmasi penghentian ShadowFarm. Hubungi Owner server.")
    inspect(p,"ShadowFarm dihentikan.")
end
local function guard(p,fn)
    local valid,id=pcall(function() if realPlayer(p) then return uid(p) end end)
    if not valid then print("[shadowfarm] INVALID PLAYER: " .. tostring(id)); return end
    if not id then return end
    if busy[id] then return end
    busy[id]=true
    local ok,err=pcall(function() assert(ready,"ShadowFarm belum tersedia. Periksa log [shadowfarm] di server."); fn() end)
    pendingStarts[id]=nil
    busy[id]=nil
    if not ok then
        sessions[id]=nil
        print("[shadowfarm] ERROR uid=" .. number(id) .. " / " .. tostring(err))
        notify(p,"`o" .. clean(err,220):gsub("^.-:%d+:%s*","") .. "``")
    end
end
local function command(_,p,full)
    if _G.ShadowfarmControl~=Runtime or type(full)~="string" then return false end
    local name,args=full:match("^%s*/?(%S+)%s*(.-)%s*$")
    if not name or name:lower()~="shadowfarm" then return false end
    args=args:lower()
    guard(p,function()
        if args=="" or args=="start" then start(p)
        elseif args=="status" then inspect(p)
        elseif args=="stop" then stop(p)
        elseif args=="help" then UI.help(p)
        else tell(p,"Gunakan /shadowfarm, /shadowfarm status, /shadowfarm stop, atau /shadowfarm help.") end
    end)
    return true
end
local function dialog(_,p,data)
    if _G.ShadowfarmControl~=Runtime or type(data)~="table" or type(data.dialog_name)~="string" or not data.dialog_name:match("^shadowfarm_") then return false end
    guard(p,function()
        local id=uid(p)
        local state=sessions[id]
        local matches=state and state.name==data.dialog_name
        local clicked=data.buttonClicked
        if data.quit=="1" or data.quit==1 or clicked==nil or clicked=="" or clicked=="cancel" or clicked=="Tutup" then
            if matches then sessions[id]=nil end
            return
        end
        if state and not matches then tell(p,"`oGunakan menu ShadowFarm yang terbaru.``"); return end
        if not matches or os.time()>=state.expires then sessions[id]=nil; inspect(p); return end
        if not state.buttons[clicked] then return end
        sessions[id]=nil
        if clicked=="help" then UI.help(p)
        elseif clicked=="start" then start(p)
        elseif clicked=="stop" then stop(p,state.sessionId)
        elseif clicked=="refresh" or clicked=="back" then inspect(p) end
    end)
    return true
end
local function tick()
    if _G.ShadowfarmControl~=Runtime or not ready then return end
    for id,record in pairs(workers) do
        if not busy[id] then
            busy[id]=true
            local ok,err=pcall(function()
                local p=getPlayer(id)
                if not realPlayer(p) then cleanup(id,nil); return end
                if record.needsCleanup then cleanup(id,record.cleanupSession); return end
                local api=assert(native(),"Adapter engine tidak tersedia.")
                local row=status(api,id)
                assert(not row.active or row.generation==generation,"Generasi sesi engine berubah.")
                if not row.active then workers[id]=nil; sessions[id]=nil; notify(p,"`oShadowFarm selesai/dihentikan engine.``"); return end
                remember(id,row)
            end)
            busy[id]=nil
            if not ok then
                print("[shadowfarm] MONITOR ERROR uid=" .. number(id) .. " / " .. tostring(err))
                cleanup(id,record.sessionId)
            end
        end
    end
end
local function disconnect(p)
    if _G.ShadowfarmControl~=Runtime or not p then return end
    local valid,id=pcall(uid,p)
    if not valid then print("[shadowfarm] DISCONNECT ID ERROR: " .. tostring(id)); return end
    sessions[id]=nil
    if not workers[id] and not pendingStarts[id] then return end
    if pendingStarts[id] then pendingStarts[id].cancelled=true end
    -- Disconnect callbacks may still report isOnline=true; stop unconditionally.
    cleanup(id,nil)
end
local function install(label,fn,arg)
    if type(fn)~="function" then print("[shadowfarm] Missing API: " .. label); return false end
    local ok,result=pcall(fn,arg)
    if not ok or result==false then print("[shadowfarm] Registration failed: " .. label .. " / " .. tostring(result)); return false end
    return true
end

print("[shadowfarm] BOOT " .. VERSION .. " | " .. tostring(_VERSION))
local commandOK=install("command",onPlayerCommandCallback,command)
local dialogOK=install("dialog",onPlayerDialogCallback,dialog)
local registered=install("/shadowfarm",registerLuaCommand,{command="shadowfarm",roleRequired=0,description="Clone farm online dari setting BFG aktif (memerlukan dukungan engine).",
    callback=function(p,args) return command(nil,p,"shadowfarm " .. (args or "")) end})
local tickOK=install("online monitor",onTick,tick)
local disconnectOK=install("disconnect",onPlayerDisconnectCallback,disconnect)
ready,initError=pcall(function()
    assert((registered or commandOK) and dialogOK and tickOK and disconnectOK,"API command/dialog/lifecycle tidak tersedia.")
    assert(type(getPlayer)=="function" and type(getItem)=="function","API akun/item tidak tersedia.")
    assert(type(sqlite)=="table" and type(sqlite.open)=="function","SQLite tidak tersedia.")
    db=assert(sqlite.open(DB_FILE),"Database sesi ShadowFarm tidak dapat dibuka.")
    query("PRAGMA synchronous=FULL")
    query("CREATE TABLE IF NOT EXISTS sf_runtime(id INTEGER PRIMARY KEY CHECK(id=1),generation INTEGER NOT NULL)")
    query("BEGIN IMMEDIATE")
    local ok,result=pcall(function()
        query("INSERT OR IGNORE INTO sf_runtime(id,generation) VALUES(1,0)")
        query("UPDATE sf_runtime SET generation=generation+1 WHERE id=1")
        local n=assert(integer(tonumber(query("SELECT generation FROM sf_runtime WHERE id=1")[1].generation),1,MAX_SAFE),"Generasi sesi tidak valid.")
        query("COMMIT"); return n
    end)
    if not ok then pcall(function() query("ROLLBACK") end); error(result) end
    generation=result
end)
_G.ShadowfarmControl=Runtime
local connected=false
if ready then
    local checked,api=pcall(native)
    connected=checked and api~=nil
    if not checked then print("[shadowfarm] ADAPTER INIT ERROR: " .. tostring(api)) end
end
print("[shadowfarm] ROUTES registered=" .. tostring(registered) .. " command=" .. tostring(commandOK) .. " dialog=" .. tostring(dialogOK) .. " tick=" .. tostring(tickOK) .. " disconnect=" .. tostring(disconnectOK))
print(ready and ("[shadowfarm] Loaded /shadowfarm | native_bfg=" .. tostring(connected)
    .. (connected and "" or " | BFG unavailable: ShadowfarmNative extension is not installed/ready"))
    or ("[shadowfarm] INIT FAILED: " .. tostring(initError)))
return Runtime
