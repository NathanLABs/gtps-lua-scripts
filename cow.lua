-- Developer: Nathan
-- /setcow: server Owner (999) and Founder (1000).
-- Replaces Cow 866's provider payout, before native Milk/MAG drops.
-- Ground rewards use a durable per-cycle journal; uncertain spawns never replay.
local VERSION, DB_FILE, COW_ID = "v1-cow-lock", "cow_v1.db", 866
local MAX_AMOUNT, MAX_SAFE, PAGE_SIZE, SESSION_SECONDS = 2000000000, 9007199254740991, 8, 120
local DEFAULT_LOCKS = {242,1796,7188,8470}
local db, ready, initError, generation, current, providerOK
local sessions, busy, serial = {}, {}, 0
local Runtime = {version=1}

local function integer(n,low,high)
    return type(n)=="number" and n==n and n>=low and n<=high and n==math.floor(n) and n or nil
end
local function number(n) return string.format("%.0f",n) end
local function fmt(n) return number(n):reverse():gsub("(%d%d%d)","%1."):reverse():gsub("^%.","") end
local function clean(v,limit) return tostring(v or ""):gsub("`.",""):gsub("[|%c]"," "):sub(1,limit or 160) end
local function sql(v) return "'" .. tostring(v):gsub("%z",""):gsub("'","''") .. "'" end
local function uid(p) return assert(integer(p:getUserID(),1,MAX_SAFE),"ID akun tidak valid.") end
local function realPlayer(p) return p and p:isOnline() and p:getType()==0 end
local function admin(p) return realPlayer(p) and (p:getRole()==999 or p:getRole()==1000) end
local function tell(p,s) p:onConsoleMessage("`3[Cow]`` " .. s) end
local function notifyOwner(p,s)
    pcall(function() if realPlayer(p) then tell(p,s) end end)
end
local function query(s) return assert(db:query(s),"Database Cow tidak dapat diakses.") end
local function tx(fn)
    query("BEGIN IMMEDIATE")
    local ok,value=pcall(fn)
    if ok then ok,value=pcall(function() query("COMMIT"); return value end) end
    if not ok then pcall(function() query("ROLLBACK") end); error(value) end
    return value
end
local function config()
    local row=assert(query("SELECT * FROM cow_settings WHERE id=1")[1],"Pengaturan Cow belum tersedia.")
    row.enabled=assert(integer(tonumber(row.enabled),0,1),"Status Cow tidak valid.")
    row.item=assert(integer(tonumber(row.item),1,MAX_AMOUNT),"ID lock tidak valid.")
    row.amount=assert(integer(tonumber(row.amount),1,MAX_AMOUNT),"Amount Cow tidak valid.")
    row.revision=assert(integer(tonumber(row.revision),0,MAX_SAFE-1),"Versi pengaturan tidak valid.")
    return row
end
local function parse(value,low,high)
    if type(value)~="string" or #value>16 then return nil end
    local digits=value:match("^%s*(%d+)%s*$")
    return digits and integer(tonumber(digits),low,high) or nil
end
local function itemName(id)
    local item=getItem(id)
    return item and clean(item:getName(),30) or ("Item #" .. id .. " (tidak tersedia)")
end
local function audit(p,event,detail)
    query("INSERT INTO cow_log(actor,event,detail,at) VALUES(" .. number(uid(p)) .. "," .. sql(event) .. "," .. sql(clean(detail,200)) .. "," .. os.time() .. ")")
end
local function revision(p,state)
    assert(admin(p),"Pengaturan Cow khusus Owner server atau Founder.")
    local row=config()
    assert(row.revision==state.revision,"Pengaturan berubah. Buka ulang /setcow sebelum menyimpan.")
    assert(row.revision<MAX_SAFE-1,"Versi pengaturan mencapai batas.")
    return row
end
local function groundTotal(world,item)
    local total=0
    local drops=world:getDroppedItems()
    assert(type(drops)=="table","Isi drop world tidak dapat diperiksa.")
    for _,drop in ipairs(drops) do
        if drop:getItemID()==item then
            local count=assert(integer(drop:getItemCount(),0,MAX_AMOUNT),"Jumlah drop tidak valid.")
            assert(total<=MAX_SAFE-count,"Jumlah drop world melebihi batas pemeriksaan.")
            total=total+count
        end
    end
    return total
end
local function cycleKey(world,tile)
    local name=world:getName()
    assert(type(name)=="string" and #name>0 and #name<=64,"Nama world tidak valid.")
    local x=assert(integer(tile:getPosX(),0,MAX_AMOUNT),"Posisi Cow tidak valid.")
    local y=assert(integer(tile:getPosY(),0,MAX_AMOUNT),"Posisi Cow tidak valid.")
    local cycle=assert(integer(tile:getTileData(1),0,MAX_SAFE),"Timestamp siklus Cow tidak tersedia; reward tidak dikirim.")
    return {world=name,x=x,y=y,cycle=cycle}
end
local function cycleWhere(key)
    return "world=" .. sql(key.world) .. " AND x=" .. number(key.x) .. " AND y=" .. number(key.y) .. " AND cycle_start=" .. number(key.cycle)
end
local function sourceOwner(p)
    local ok,id=pcall(function() return uid(p) end)
    return ok and id or 0
end
local function payout(world,p,tile)
    local key=cycleKey(world,tile)
    local receipt=tx(function()
        if query("SELECT id FROM cow_payouts WHERE " .. cycleWhere(key))[1] then return {duplicate=true} end
        local cfg=config()
        if cfg.enabled~=1 then return nil end
        assert(query("SELECT item FROM cow_locks WHERE item=" .. cfg.item)[1],"Lock Cow tidak terdaftar.")
        assert(getItem(cfg.item),"Item lock Cow tidak tersedia di server.")
        local before=groundTotal(world,cfg.item)
        assert(before<=MAX_SAFE-cfg.amount,"Jumlah drop world akan melewati batas pemeriksaan.")
        query("INSERT INTO cow_payouts(world,x,y,cycle_start,actor,item,amount,state,before_total,created_at) VALUES("
            .. sql(key.world) .. "," .. number(key.x) .. "," .. number(key.y) .. "," .. number(key.cycle) .. "," .. number(sourceOwner(p))
            .. "," .. cfg.item .. "," .. number(cfg.amount) .. ",'pending'," .. number(before) .. "," .. os.time() .. ")")
        return {id=assert(integer(tonumber(query("SELECT last_insert_rowid() AS id")[1].id),1,MAX_SAFE),"Jurnal Cow tidak valid."),
            item=cfg.item,amount=cfg.amount,before=before,key=key}
    end)
    if not receipt then return false end
    if receipt.duplicate then return true end
    -- Once an intent commits, use that snapshot even if another setting changes.
    local spawnOK,spawned=pcall(world.spawnItem,world,key.x,key.y,receipt.item,receipt.amount)
    local readOK,after=pcall(groundTotal,world,receipt.item)
    local state,note="pending",""
    if spawnOK and spawned==true and readOK and after-receipt.before==receipt.amount then
        state,note="done","Exact ground drop verified"
    elseif spawnOK and spawned==false and readOK and after==receipt.before then
        state,note="refused","Native spawn refused without drop changes"
    else
        note="api_ok=" .. tostring(spawnOK) .. " result=" .. tostring(spawned) .. " read_ok=" .. tostring(readOK)
    end
    if state~="pending" then
        tx(function()
            assert(query("SELECT state FROM cow_payouts WHERE id=" .. number(receipt.id))[1].state=="pending","Status reward Cow berubah.")
            query("UPDATE cow_payouts SET state=" .. sql(state) .. ",after_total=" .. number(after) .. ",finished_at=" .. os.time()
                .. ",note=" .. sql(note) .. " WHERE id=" .. number(receipt.id) .. " AND state='pending'")
        end)
    else
        pcall(function() query("UPDATE cow_payouts SET " .. (readOK and ("after_total=" .. number(after) .. ",") or "")
            .. "note=" .. sql(note) .. " WHERE id=" .. number(receipt.id)) end)
    end
    if state~="done" then
        print("[cow] NEEDS REVIEW #" .. number(receipt.id) .. " " .. key.world .. " (" .. key.x .. "," .. key.y .. ") " .. state .. " | " .. note)
        notifyOwner(p,"`oReward Cow #" .. number(receipt.id) .. " belum terkonfirmasi. Hubungi Owner/Founder.``")
    end
    return true
end
local function providerDrop(world,p,tile,_,_)
    if _G.CowDrops~=Runtime then return false end
    local identified,item=pcall(function() return tile:getTileID() end)
    if not identified or item~=COW_ID then return false end
    if not ready then return false end
    -- Errors must still return true: engine swallows callback errors and would
    -- otherwise continue the Milk drop after a partial/uncertain lock spawn.
    local ok,result=pcall(function()
        -- Read committed configuration, including after a post-save UI failure.
        -- A cached disabled setting must never restore Milk for an active setup.
        local cfg=config()
        if cfg.enabled~=1 then
            -- A converted cycle stays consumed after disabling, even on reload.
            local valid,key=pcall(cycleKey,world,tile)
            if not valid then return false end
            return query("SELECT id FROM cow_payouts WHERE " .. cycleWhere(key))[1]~=nil
        end
        return payout(world,p,tile)
    end)
    if not ok then
        print("[cow] PAYOUT ERROR: " .. tostring(result))
        notifyOwner(p,"`oReward Cow gagal diproses. Periksa log [cow] di console server.``")
        return true
    end
    return result
end

local function panel(p,state,notice)
    assert(admin(p),"Pengaturan Cow khusus Owner server atau Founder.")
    local cfg=config()
    state=state or {item=cfg.item,amount=cfg.amount,page=1}
    local rows={}
    for _,row in ipairs(query("SELECT item FROM cow_locks ORDER BY custom,item")) do
        local item=tonumber(row.item)
        if getItem(item) then rows[#rows+1]=item end
    end
    local pages=math.max(1,math.ceil(#rows/PAGE_SIZE))
    local page=math.max(1,math.min(state.page or 1,pages))
    local L={"set_default_color|`w\nset_bg_color|20,24,31,230|\nset_border_color|92,104,122,255|\n"
        .. "add_label_with_icon|big|`wCOW REWARD``|left|" .. COW_ID .. "|\nadd_spacer|small|\n"}
    local function text(s) L[#L+1]="add_smalltext|" .. s .. "|\n" end
    local function button(key,label) L[#L+1]="add_button|" .. key .. "|" .. label .. "|noflags|0|0|\n" end
    text("`oPilih lock, isi Amount, lalu Save. Berlaku untuk semua Cow.``")
    text(cfg.enabled==1 and ("Saat ini: `3" .. fmt(cfg.amount) .. " " .. itemName(cfg.item) .. "`` per Cow.")
        or "Saat ini: `oSusu bawaan``. Lock aktif setelah Save.")
    if not providerOK then text("`oEvent Cow tidak tersedia di engine ini; setting belum dapat diaktifkan.``") end
    if notice then text("`o" .. clean(notice,180) .. "``") end
    L[#L+1]="add_spacer|small|\nadd_label|small|`wPILIH LOCK``|left|\n"
    local buttons={}
    for n=(page-1)*PAGE_SIZE+1,math.min(page*PAGE_SIZE,#rows) do
        local item=rows[n]
        local chosen=state.item==item
        local key="lock_" .. item
        L[#L+1]="add_button_with_icon|" .. key .. "|" .. (chosen and "`3" or "`w") .. itemName(item) .. "``|"
            .. (chosen and "staticYellowFrame" or "staticBlueFrame") .. "|" .. item .. "||\n"
        buttons[key]=true
    end
    L[#L+1]="add_button_with_icon||END_LIST|noflags|0||\nadd_spacer|small|\n"
    if pages>1 then
        text("Halaman " .. page .. "/" .. pages)
        if page>1 then button("previous","Previous") end
        if page<pages then button("next","Next") end
    end
    L[#L+1]="add_label_with_icon|small|`wDipilih: " .. itemName(state.item) .. "``|left|" .. state.item .. "|\n"
    L[#L+1]="add_text_input|amount|Amount :|" .. number(state.amount) .. "|10|\n"
    text("1 Cow = `3" .. fmt(state.amount) .. " " .. itemName(state.item) .. "``. Susu diganti.")
    if providerOK then button("save","`3Save Reward``") end
    if cfg.enabled==1 then button("milk","Gunakan Susu Bawaan") end
    L[#L+1]="add_spacer|small|\nadd_text_input|custom_item|Custom Lock ItemID :||10|\n"
    button("add","Tambah Custom Lock")
    serial=serial+1
    local nextState={name="cow_" .. number(generation) .. "_" .. number(serial),item=state.item,amount=state.amount,page=page,
        revision=cfg.revision,expires=os.time()+SESSION_SECONDS,buttons=buttons}
    for _,line in ipairs(L) do local key=line:match("^add_button|([^|]+)|"); if key then buttons[key]=true end end
    L[#L+1]="add_spacer|small|\nadd_smalltext|`9© Dibuat Oleh : Nathan``|\n"
    L[#L+1]="end_dialog|" .. nextState.name .. "|Tutup||\n"
    local markup=table.concat(L)
    assert(#markup<=4096,"Dialog Cow terlalu panjang.")
    sessions[uid(p)]=nextState
    local ok,result=pcall(p.onDialogRequest,p,markup)
    if not ok or result==false then sessions[uid(p)]=nil; error("Menu Cow tidak dapat dibuka.") end
end
local function save(p,state,raw)
    local amount=assert(parse(raw,1,MAX_AMOUNT),"Amount harus angka bulat 1-2.000.000.000, tanpa titik atau koma.")
    assert(providerOK,"Event Cow tidak tersedia di engine ini.")
    tx(function()
        revision(p,state)
        assert(query("SELECT item FROM cow_locks WHERE item=" .. state.item)[1] and getItem(state.item),"Lock yang dipilih tidak tersedia.")
        query("UPDATE cow_settings SET enabled=1,item=" .. state.item .. ",amount=" .. number(amount) .. ",revision=revision+1 WHERE id=1")
        audit(p,"save","item=" .. state.item .. " amount=" .. number(amount))
    end)
    current=config()
    panel(p,nil,"Disimpan. 1 Cow = " .. fmt(amount) .. " " .. itemName(current.item) .. ".")
end
local function milk(p,state)
    tx(function()
        revision(p,state)
        query("UPDATE cow_settings SET enabled=0,revision=revision+1 WHERE id=1")
        audit(p,"milk","Native Milk restored")
    end)
    current=config(); panel(p)
end
local function addLock(p,state,raw)
    local item=assert(parse(raw,1,MAX_AMOUNT),"Custom Lock ItemID harus angka bulat positif.")
    assert(getItem(item),"ItemID tidak tersedia di server.")
    local added=tx(function()
        revision(p,state)
        if query("SELECT item FROM cow_locks WHERE item=" .. item)[1] then return false end
        assert(tonumber(query("SELECT COUNT(*) AS n FROM cow_locks")[1].n)<100,"Maksimal 100 pilihan lock.")
        query("INSERT INTO cow_locks(item,custom) VALUES(" .. item .. ",1)")
        query("UPDATE cow_settings SET revision=revision+1 WHERE id=1")
        audit(p,"add_lock","item=" .. item)
        return true
    end)
    current=config()
    -- A new selection is only a draft; existing active payouts change on Save.
    panel(p,{item=item,amount=state.amount,page=state.page},added and "Custom lock ditambahkan. Tekan Save untuk memakainya." or "Lock ini sudah tersedia. Tekan Save untuk memakainya.")
end
local function guard(p,fn)
    if not realPlayer(p) then return end
    local account=uid(p)
    if busy[account] then return end
    busy[account]=true
    local ok,err=pcall(function()
        assert(ready,"Setting Cow belum tersedia. Periksa log [cow] di console server.")
        assert(admin(p),"Perintah /setcow khusus Owner server atau Founder.")
        fn()
    end)
    busy[account]=nil
    if not ok then
        sessions[account]=nil
        print("[cow] ERROR uid=" .. number(account) .. " / " .. tostring(err))
        tell(p,"`o" .. clean(err,220):gsub("^.-:%d+:%s*","") .. "``")
    end
end
local function command(_,p,full)
    if _G.CowDrops~=Runtime or type(full)~="string" then return false end
    local name=full:match("^%s*/?(%S+)")
    if not name or name:lower()~="setcow" then return false end
    guard(p,function() panel(p) end)
    return true
end
local function dialog(_,p,data)
    if _G.CowDrops~=Runtime or type(data)~="table" or type(data.dialog_name)~="string" or not data.dialog_name:match("^cow_") then return false end
    guard(p,function()
        local account=uid(p)
        local state=sessions[account]
        local matches=state and state.name==data.dialog_name
        local clicked=data.buttonClicked
        if data.quit=="1" or data.quit==1 or clicked==nil or clicked=="" or clicked=="cancel" or clicked=="Tutup" then
            if matches then sessions[account]=nil end
            return
        end
        if state and not matches then tell(p,"`oGunakan menu Cow yang terbaru.``"); return end
        if not matches or os.time()>=state.expires then sessions[account]=nil; panel(p); return end
        if not state.buttons[clicked] then return end
        sessions[account]=nil
        if config().revision~=state.revision then panel(p,nil,"Pengaturan berubah. Periksa menu terbaru sebelum melanjutkan."); return end
        local item=tonumber(clicked:match("^lock_(%d+)$"))
        if item then
            assert(query("SELECT item FROM cow_locks WHERE item=" .. number(item))[1] and getItem(item),"Lock tidak tersedia.")
            panel(p,{item=item,amount=parse(data.amount,1,MAX_AMOUNT) or state.amount,page=state.page})
        elseif clicked=="save" then save(p,state,data.amount)
        elseif clicked=="milk" then milk(p,state)
        elseif clicked=="add" then
            state.amount=parse(data.amount,1,MAX_AMOUNT) or state.amount
            addLock(p,state,data.custom_item)
        elseif clicked=="previous" or clicked=="next" then
            panel(p,{item=state.item,amount=parse(data.amount,1,MAX_AMOUNT) or state.amount,page=state.page+(clicked=="next" and 1 or -1)})
        end
    end)
    return true
end
local function install(label,fn,arg)
    if type(fn)~="function" then print("[cow] Missing API: " .. label); return false end
    local ok,result=pcall(fn,arg)
    if not ok or result==false then print("[cow] Registration failed: " .. label .. " / " .. tostring(result)); return false end
    return true
end

print("[cow] BOOT " .. VERSION .. " | " .. tostring(_VERSION))
local commandOK=install("command",onPlayerCommandCallback,command)
local dialogOK=install("dialog",onPlayerDialogCallback,dialog)
local registered=install("/setcow",registerLuaCommand,{command="setcow",roleRequired=999,description="Owner/Founder: ganti hasil Cow menjadi lock.",
    callback=function(p,args) return command(nil,p,"setcow " .. (args or "")) end})
providerOK=install("onProviderDropCallback",onProviderDropCallback,providerDrop)
install("disconnect",onPlayerDisconnectCallback,function(p) if _G.CowDrops==Runtime and p then sessions[uid(p)]=nil end end)
ready,initError=pcall(function()
    assert((registered or commandOK) and dialogOK,"API command/dialog tidak tersedia.")
    assert(type(getItem)=="function","API item tidak tersedia.")
    assert(type(sqlite)=="table" and type(sqlite.open)=="function","SQLite tidak tersedia.")
    db=assert(sqlite.open(DB_FILE),"Database Cow tidak dapat dibuka.")
    query("PRAGMA synchronous=FULL")
    query("CREATE TABLE IF NOT EXISTS cow_settings(id INTEGER PRIMARY KEY CHECK(id=1),enabled INTEGER NOT NULL CHECK(enabled IN (0,1)),item INTEGER NOT NULL CHECK(item>0),amount INTEGER NOT NULL CHECK(amount BETWEEN 1 AND 2000000000),revision INTEGER NOT NULL CHECK(revision>=0))")
    query("CREATE TABLE IF NOT EXISTS cow_locks(item INTEGER PRIMARY KEY,custom INTEGER NOT NULL CHECK(custom IN (0,1)))")
    query("CREATE TABLE IF NOT EXISTS cow_runtime(id INTEGER PRIMARY KEY CHECK(id=1),generation INTEGER NOT NULL)")
    query("CREATE TABLE IF NOT EXISTS cow_payouts(id INTEGER PRIMARY KEY AUTOINCREMENT,world TEXT NOT NULL,x INTEGER NOT NULL,y INTEGER NOT NULL,cycle_start INTEGER NOT NULL,actor INTEGER NOT NULL,item INTEGER NOT NULL,amount INTEGER NOT NULL,state TEXT NOT NULL CHECK(state IN ('pending','done','refused')),before_total INTEGER NOT NULL,after_total INTEGER,created_at INTEGER NOT NULL,finished_at INTEGER,note TEXT NOT NULL DEFAULT '',UNIQUE(world,x,y,cycle_start))")
    query("CREATE TABLE IF NOT EXISTS cow_log(id INTEGER PRIMARY KEY AUTOINCREMENT,actor INTEGER NOT NULL,event TEXT NOT NULL,detail TEXT NOT NULL,at INTEGER NOT NULL)")
    generation=tx(function()
        query("INSERT OR IGNORE INTO cow_settings(id,enabled,item,amount,revision) VALUES(1,0,7188,1,0)")
        for _,item in ipairs(DEFAULT_LOCKS) do query("INSERT OR IGNORE INTO cow_locks(item,custom) VALUES(" .. item .. ",0)") end
        query("INSERT OR IGNORE INTO cow_runtime(id,generation) VALUES(1,0)")
        query("UPDATE cow_runtime SET generation=generation+1 WHERE id=1")
        return assert(integer(tonumber(query("SELECT generation FROM cow_runtime WHERE id=1")[1].generation),1,MAX_SAFE),"Generasi dialog tidak valid.")
    end)
    current=config()
end)
_G.CowDrops=Runtime
print("[cow] ROUTES registered=" .. tostring(registered) .. " command=" .. tostring(commandOK) .. " dialog=" .. tostring(dialogOK) .. " provider=" .. tostring(providerOK))
print(ready and ("[cow] Loaded /setcow | Cow 866 | " .. (current.enabled==1 and ("item " .. current.item .. " x" .. number(current.amount)) or "Milk until Save"))
    or ("[cow] INIT FAILED: " .. tostring(initError)))
return Runtime
