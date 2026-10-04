-- Developer: Nathan
-- One KitPass season, three Basic/Premium reward levels. Lua 5.1+.
-- Uses documented engine APIs; premium grants are account-UID based.
local VERSION, DB_FILE = "v2-pass-ui", "kitpass_v1.db"
local LEVELS, MAX_AMOUNT = 3, 2000000000
local db, ready, initError, generation
local sessions, busy, serial = {}, {}, 0
local UI = {}
local function int(v, low, high)
    local n = tonumber(v)
    if type(v)=="string" and not v:match("^%d+$") then return nil end
    return n and n==n and n>=low and n<=high and n==math.floor(n) and n or nil
end
local function clean(v, limit) return tostring(v or ""):gsub("`.", ""):gsub("[|%c]", " "):sub(1, limit or 40) end
local function sql(v) return "'" .. tostring(v):gsub("%z", ""):gsub("'", "''") .. "'" end
local function number(v) return string.format("%.0f", v) end
local function fmt(v) return number(v):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") end
local function q(s) return assert(db:query(s), "Database KitPass gagal diakses.") end
local function tx(callback)
    q("BEGIN IMMEDIATE")
    local ok, result = pcall(callback)
    if ok then ok, result = pcall(function() q("COMMIT"); return result end) end
    if not ok then pcall(function() q("ROLLBACK") end); error(result) end
    return result
end
local function uid(p) return assert(int(p:getUserID(), 1, MAX_AMOUNT), "ID akun tidak valid.") end
local function activePlayer(p) return p and p:isOnline() and p:getType()==0 end
local function founder(p) return activePlayer(p) and p:getRole()==1000 end
local function tell(p, text) if p then p:onConsoleMessage("`6[KitPass] ``" .. text) end end
local function config(key) return assert(q("SELECT value FROM kp_config WHERE key=" .. sql(key))[1], "Konfigurasi tidak ditemukan.").value end
local function bump() q("UPDATE kp_config SET value=value+1 WHERE key='revision'") end
local function season() return q("SELECT * FROM kp_seasons WHERE id=" .. config("season"))[1] end
local function running(s) return s and os.time()>=s.starts_at and os.time()<s.ends_at end
local function member(s, id) return s and q("SELECT * FROM kp_members WHERE season=" .. s.id .. " AND uid=" .. id)[1] end
local function premium(s, id) local m=member(s,id); return m and m.premium==1 or false end
local function points(s, id)
    local row=s and q("SELECT xp FROM kp_progress WHERE season=" .. s.id .. " AND uid=" .. id)[1]
    return row and row.xp or 0
end
local function level(s, id)
    return math.min(LEVELS, math.floor(points(s,id)/config("xp_per_level")))
end
local function period(kind)
    local day=math.floor((os.time()+25200)/86400)
    -- 1970-01-01 was Thursday, so day + 3 makes Monday the week boundary.
    return kind=="daily" and day or math.floor((day+3)/7)
end
local log
local function mission(s, id, kind)
    local key=period(kind)
    local row=q("SELECT * FROM kp_missions WHERE season=" .. s.id .. " AND uid=" .. id .. " AND kind=" .. sql(kind) .. " AND period=" .. key)[1]
    if row then return row end
    local rule=assert(q("SELECT * FROM kp_mission_rules WHERE kind=" .. sql(kind))[1])
    q("INSERT OR IGNORE INTO kp_missions(season,uid,kind,period,action,goal,reward_xp,progress,completed) VALUES("
        .. s.id .. "," .. id .. "," .. sql(kind) .. "," .. key .. "," .. sql(rule.action) .. "," .. rule.goal .. "," .. rule.reward_xp .. ",0,0)")
    return assert(q("SELECT * FROM kp_missions WHERE season=" .. s.id .. " AND uid=" .. id .. " AND kind=" .. sql(kind) .. " AND period=" .. key)[1])
end
local function progress(p, action)
    if not ready or not activePlayer(p) then return end
    local s=season(); if not running(s) then return end
    local id=uid(p)
    if busy[id] then return end
    local beforeLevel=level(s,id)
    local completed={}
    tx(function()
        for _,kind in ipairs({"daily","weekly"}) do
            local m=mission(s,id,kind)
            if m.action==action and m.completed==0 then
                local count=math.min(m.goal,m.progress+1)
                local done=count>=m.goal and 1 or 0
                q("UPDATE kp_missions SET progress=" .. count .. ",completed=" .. done .. " WHERE season=" .. s.id .. " AND uid=" .. id .. " AND kind=" .. sql(kind) .. " AND period=" .. m.period .. " AND completed=0")
                if done==1 then
                    q("INSERT OR IGNORE INTO kp_progress(season,uid,xp) VALUES(" .. s.id .. "," .. id .. ",0)")
                    q("UPDATE kp_progress SET xp=MIN(2000000000,xp+" .. m.reward_xp .. ") WHERE season=" .. s.id .. " AND uid=" .. id)
                    log(id,"mission_completed",s.id,kind .. " +" .. m.reward_xp .. " XP")
                    completed[#completed+1]={kind=kind,xp=m.reward_xp}
                end
            end
        end
    end)
    for _,m in ipairs(completed) do tell(p,"`2Misi " .. (m.kind=="daily" and "harian" or "mingguan") .. " selesai! +" .. fmt(m.xp) .. " XP.``") end
    if #completed>0 then
        local afterLevel=level(s,id)
        if afterLevel>beforeLevel then tell(p,"`3LEVEL UP!`` KitPass Level " .. afterLevel .. " terbuka. Lihat reward di /kitpass.") end
    end
end
log=function(actor, event, target, detail)
    q("INSERT INTO kp_log(actor,event,target,detail,at) VALUES(" .. actor .. "," .. sql(event) .. "," .. (target or 0) .. "," .. sql(clean(detail,180)) .. "," .. os.time() .. ")")
end
local function held(id) return q("SELECT id FROM kp_claims WHERE uid=" .. id .. " AND state='pending' LIMIT 1")[1] end
local function guard(p, callback)
    if not activePlayer(p) then return end
    local id=uid(p)
    if busy[id] then tell(p, "`oTunggu transaksi sebelumnya selesai."); return end
    busy[id]=true
    local ok, err=pcall(function()
        assert(ready, "KitPass belum tersedia. Periksa log server [kitpass].")
        callback()
    end)
    busy[id]=nil
    if not ok then print("[kitpass] ERROR uid=" .. id .. " / " .. tostring(err)); tell(p,"`4" .. clean(err,220)) end
end
local function initialize()
    assert(type(sqlite)=="table" and type(sqlite.open)=="function", "SQLite tidak tersedia.")
    db=assert(sqlite.open(DB_FILE), "Database KitPass tidak dapat dibuka.")
    q("PRAGMA synchronous=FULL")
    q("CREATE TABLE IF NOT EXISTS kp_config(key TEXT PRIMARY KEY,value INTEGER NOT NULL)")
    q("CREATE TABLE IF NOT EXISTS kp_seasons(id INTEGER PRIMARY KEY AUTOINCREMENT,starts_at INTEGER NOT NULL,ends_at INTEGER NOT NULL,duration INTEGER NOT NULL)")
    q("CREATE TABLE IF NOT EXISTS kp_rewards(track TEXT NOT NULL CHECK(track IN ('basic','premium')),level INTEGER NOT NULL CHECK(level BETWEEN 1 AND 3),item INTEGER NOT NULL,amount INTEGER NOT NULL CHECK(amount>0),PRIMARY KEY(track,level))")
    q("CREATE TABLE IF NOT EXISTS kp_members(season INTEGER NOT NULL,uid INTEGER NOT NULL,premium INTEGER NOT NULL DEFAULT 0,granted_by INTEGER NOT NULL DEFAULT 0,granted_at INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(season,uid))")
    q("CREATE TABLE IF NOT EXISTS kp_progress(season INTEGER NOT NULL,uid INTEGER NOT NULL,xp INTEGER NOT NULL CHECK(xp>=0),PRIMARY KEY(season,uid))")
    q("CREATE TABLE IF NOT EXISTS kp_mission_rules(kind TEXT PRIMARY KEY CHECK(kind IN ('daily','weekly')),action TEXT NOT NULL CHECK(action IN ('break','harvest')),goal INTEGER NOT NULL CHECK(goal>0),reward_xp INTEGER NOT NULL CHECK(reward_xp>0))")
    q("CREATE TABLE IF NOT EXISTS kp_missions(season INTEGER NOT NULL,uid INTEGER NOT NULL,kind TEXT NOT NULL,period INTEGER NOT NULL,action TEXT NOT NULL,goal INTEGER NOT NULL,reward_xp INTEGER NOT NULL,progress INTEGER NOT NULL DEFAULT 0,completed INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(season,uid,kind,period))")
    q("CREATE TABLE IF NOT EXISTS kp_claims(id INTEGER PRIMARY KEY AUTOINCREMENT,season INTEGER NOT NULL,uid INTEGER NOT NULL,track TEXT NOT NULL,level INTEGER NOT NULL,item INTEGER NOT NULL,amount INTEGER NOT NULL,state TEXT NOT NULL CHECK(state IN ('pending','claimed','cancelled')),before_inv INTEGER NOT NULL,before_extra INTEGER NOT NULL,after_inv INTEGER,after_extra INTEGER,at INTEGER NOT NULL,UNIQUE(season,uid,track,level))")
    q("CREATE TABLE IF NOT EXISTS kp_log(id INTEGER PRIMARY KEY AUTOINCREMENT,actor INTEGER NOT NULL,event TEXT NOT NULL,target INTEGER NOT NULL,detail TEXT NOT NULL,at INTEGER NOT NULL)")
    q("CREATE INDEX IF NOT EXISTS kp_pending ON kp_claims(uid,state)")
    tx(function()
        q("INSERT OR IGNORE INTO kp_config(key,value) VALUES('season',0)")
        q("INSERT OR IGNORE INTO kp_config(key,value) VALUES('revision',0)")
        q("INSERT OR IGNORE INTO kp_config(key,value) VALUES('generation',0)")
        q("INSERT OR IGNORE INTO kp_config(key,value) VALUES('xp_per_level',100)")
        q("INSERT OR IGNORE INTO kp_mission_rules(kind,action,goal,reward_xp) VALUES('daily','break',100,100)")
        q("INSERT OR IGNORE INTO kp_mission_rules(kind,action,goal,reward_xp) VALUES('weekly','harvest',500,300)")
        q("UPDATE kp_config SET value=value+1 WHERE key='generation'")
        generation=config("generation")
    end)
end
local function grant(p, raw)
    assert(founder(p), "Perintah ini khusus Founder.")
    local name=tostring(raw or ""):match("^%s*(.-)%s*$")
    assert(#name>=1 and #name<=32 and name:match("^[%w_]+$"), "Gunakan /givepremiumkit GROWID.")
    local target=assert(getPlayerByName(name), "Player harus online agar GrowID dapat ditemukan engine.")
    assert(activePlayer(target), "Player harus online.")
    local id=uid(target)
    local result=tx(function()
        assert(founder(p), "Perintah ini khusus Founder.")
        local s=season(); assert(running(s), "KitPass belum aktif atau durasinya sudah habis.")
        if premium(s,id) then return false end
        q("INSERT OR IGNORE INTO kp_members(season,uid,premium) VALUES(" .. s.id .. "," .. id .. ",0)")
        q("UPDATE kp_members SET premium=1,granted_by=" .. uid(p) .. ",granted_at=" .. os.time() .. " WHERE season=" .. s.id .. " AND uid=" .. id)
        log(uid(p),"premium_granted",id,"Musim #" .. s.id)
        return true
    end)
    tell(p, result and ("`2Premium KitPass diberikan ke " .. clean(name,32) .. ".") or "Player tersebut sudah memiliki Premium KitPass pada musim ini.")
    if result then sessions[id]=nil; tell(target,"`2Founder memberikan Premium KitPass. Buka /kitpass > Premium.") end
end
local function setDuration(p, raw, state)
    assert(founder(p), "Panel ini khusus Founder.")
    local days=assert(int(raw,1,365), "Duration harus 1-365 hari.")
    tx(function()
        assert(config("revision")==state.revision and config("season")==state.season,"Pengaturan berubah. Buka /setkitpass lagi.")
        local s=season()
        assert(state.restart and not running(s) or not state.restart and running(s),"Status musim berubah. Buka Set Duration lagi.")
        if not state.restart then
            local ends=s.starts_at+days*86400
            assert(ends>os.time(), "Duration terlalu pendek: waktu berakhir sudah lewat.")
            q("UPDATE kp_seasons SET duration=" .. days .. ",ends_at=" .. ends .. " WHERE id=" .. s.id)
            log(uid(p),"duration_changed",s.id,days .. " hari")
        else
            q("INSERT INTO kp_seasons(starts_at,ends_at,duration) VALUES(" .. os.time() .. "," .. (os.time()+days*86400) .. "," .. days .. ")")
            local id=q("SELECT last_insert_rowid() AS id")[1].id
            q("UPDATE kp_config SET value=" .. id .. " WHERE key='season'")
            log(uid(p),"season_started",id,days .. " hari")
        end
        bump()
    end)
end
local function saveRewards(p, track, data, state)
    assert(founder(p), "Panel ini khusus Founder.")
    assert(track=="basic" or track=="premium", "Jenis reward tidak valid.")
    local rewards={}
    for n=1,LEVELS do
        local item=assert(int(data["item_"..n],0,MAX_AMOUNT), "ItemID Level " .. n .. " tidak valid.")
        local amount=assert(int(data["amount_"..n],0,MAX_AMOUNT), "Amount Level " .. n .. " tidak valid.")
        assert((item==0)==(amount==0), "Gunakan ItemID 0 dan Amount 0 untuk mengosongkan Level " .. n .. ".")
        if item>0 then assert(getItem(item), "ItemID Level " .. n .. " tidak tersedia di server."); rewards[#rewards+1]={level=n,item=item,amount=amount} end
    end
    tx(function()
        assert(config("revision")==state.revision and config("season")==state.season,"Pengaturan berubah. Buka form terbaru.")
        q("DELETE FROM kp_rewards WHERE track=" .. sql(track))
        for _,r in ipairs(rewards) do q("INSERT INTO kp_rewards(track,level,item,amount) VALUES(" .. sql(track) .. "," .. r.level .. "," .. r.item .. "," .. r.amount .. ")") end
        bump(); log(uid(p),"rewards_changed",0,track)
    end)
end
local function saveMissions(p, data, state)
    assert(founder(p),"Panel ini khusus Founder.")
    local step=assert(int(data.xp_per_level,1,1000000),"XP per Level harus 1-1,000,000.")
    local rules={}
    for _,kind in ipairs({"daily","weekly"}) do
        local action=tostring(data[kind.."_action"] or ""):lower()
        assert(action=="break" or action=="harvest","Action harus break atau harvest.")
        rules[#rules+1]={kind=kind,action=action,goal=assert(int(data[kind.."_goal"],1,1000000),"Target misi harus 1-1,000,000."),xp=assert(int(data[kind.."_xp"],1,1000000),"XP misi harus 1-1,000,000.")}
    end
    tx(function()
        assert(config("revision")==state.revision and config("season")==state.season,"Pengaturan berubah. Buka form terbaru.")
        local s=season()
        assert(not running(s) or step==config("xp_per_level"),"XP per Level hanya bisa diganti sebelum mulai atau setelah musim selesai.")
        q("UPDATE kp_config SET value=" .. step .. " WHERE key='xp_per_level'")
        for _,r in ipairs(rules) do q("UPDATE kp_mission_rules SET action=" .. sql(r.action) .. ",goal=" .. r.goal .. ",reward_xp=" .. r.xp .. " WHERE kind=" .. sql(r.kind)) end
        bump(); log(uid(p),"missions_changed",0,"Aturan misi diperbarui.")
    end)
end
-- Inventory and SQLite cannot share an atomic commit. Persist intent first;
-- ambiguous grants stay pending and are never automatically replayed.
local function claim(p, track, n, state)
    local id=uid(p)
    assert(not held(id), "Klaim sebelumnya belum pasti. Hubungi Founder untuk memeriksa jurnal.")
    local reward, key
    key=tx(function()
        assert(config("revision")==state.revision and config("season")==state.season,"Pengaturan berubah. Buka /kitpass lagi.")
        local s=season(); assert(running(s), "KitPass belum aktif atau durasinya sudah habis.")
        assert(n<=level(s,id), "Level tersebut belum terbuka.")
        assert(track=="basic" or (track=="premium" and premium(s,id)), "Premium hanya diberikan oleh Founder.")
        assert(not held(id), "Ada klaim pending. Hubungi Founder.")
        reward=assert(q("SELECT * FROM kp_rewards WHERE track=" .. sql(track) .. " AND level=" .. n)[1], "Reward belum diatur Founder.")
        assert(getItem(reward.item), "Item reward tidak tersedia di server.")
        local previous=q("SELECT * FROM kp_claims WHERE season=" .. s.id .. " AND uid=" .. id .. " AND track=" .. sql(track) .. " AND level=" .. n)[1]
        assert(not previous or previous.state=="cancelled", "Reward sudah diklaim atau masih pending.")
        local inv=assert(int(p:getItemAmount(reward.item),0,MAX_AMOUNT), "Inventory tidak valid.")
        local extra=assert(int(p:getExtraBackpackAmount(reward.item),0,MAX_AMOUNT), "Extra Backpack tidak valid.")
        assert(inv+extra+reward.amount<=MAX_AMOUNT, "Jumlah item inventory/Extra Backpack melebihi batas.")
        q("INSERT OR REPLACE INTO kp_claims(season,uid,track,level,item,amount,state,before_inv,before_extra,at) VALUES("
            .. s.id .. "," .. id .. "," .. sql(track) .. "," .. n .. "," .. reward.item .. "," .. reward.amount .. ",'pending'," .. inv .. "," .. extra .. "," .. os.time() .. ")")
        return q("SELECT last_insert_rowid() AS id")[1].id
    end)
    local receipt=assert(q("SELECT * FROM kp_claims WHERE id=" .. key)[1])
    local result=p:giveItem(reward.item,reward.amount)
    local afterInv=assert(int(p:getItemAmount(reward.item),0,MAX_AMOUNT), "Inventory setelah klaim tidak valid.")
    local afterExtra=assert(int(p:getExtraBackpackAmount(reward.item),0,MAX_AMOUNT), "Extra Backpack setelah klaim tidak valid.")
    q("UPDATE kp_claims SET after_inv=" .. afterInv .. ",after_extra=" .. afterExtra .. " WHERE id=" .. key)
    if result==false and afterInv==receipt.before_inv and afterExtra==receipt.before_extra then
        q("UPDATE kp_claims SET state='cancelled' WHERE id=" .. key)
        error("Engine menolak klaim dan inventory tidak berubah. Buka /kitpass untuk mencoba kembali.")
    end
    assert(result==true and afterInv+afterExtra==receipt.before_inv+receipt.before_extra+reward.amount,
        "Klaim #" .. key .. " belum pasti. Hubungi Founder; item tidak diberikan ulang.")
    tx(function()
        assert(q("SELECT state FROM kp_claims WHERE id=" .. key)[1].state=="pending", "Status klaim berubah.")
        q("UPDATE kp_claims SET state='claimed' WHERE id=" .. key)
        log(id,"reward_claimed",key,track .. " Level " .. n)
    end)
    tell(p,"`2Reward " .. (track=="basic" and "Basic" or "Premium") .. " Level " .. n .. " berhasil diklaim.")
end
local function line(L, s) L[#L+1]=s .. "\n" end
local function button(L, key, text) line(L,"add_button|" .. key .. "|" .. text .. "|noflags|0|0|") end
local function text(L, s) line(L,"add_smalltext|" .. s .. "|") end
local function begin(title)
    return {"set_default_color|`w\nset_bg_color|20,24,31,230|\nset_border_color|92,104,122,255|\nadd_label|big|`w" .. title .. "``|left|\nadd_spacer|small|\n"}
end
local function show(p, L, state)
    serial=serial+1; state.name="kitpass_" .. generation .. "_" .. serial
    state.expires=os.time()+180; state.revision=config("revision"); state.season=config("season"); state.buttons={}
    for _,s in ipairs(L) do local key=s:match("^add_button|([^|]+)|"); if key then state.buttons[key]=true end end
    line(L,"add_spacer|small|\nadd_smalltext|`9© Dibuat Oleh : Nathan``|")
    line(L,"end_dialog|" .. state.name .. "|Close||")
    local markup=table.concat(L); assert(#markup<=4096,"Dialog KitPass terlalu panjang.")
    sessions[uid(p)]=state
    local result=p:onDialogRequest(markup)
    if result==false then sessions[uid(p)]=nil; error("Tidak dapat membuka dialog KitPass.") end
end
function UI.section(L, title)
    line(L,"add_spacer|small|\nadd_label|small|`w" .. title .. "``|left|")
end
function UI.countdown(seconds)
    seconds=math.max(0,seconds)
    if seconds<60 then return "Kurang dari 1 menit" end
    local days=math.floor(seconds/86400); local hours=math.floor(seconds%86400/3600); local minutes=math.floor(seconds%3600/60)
    return (days>0 and (days .. " hari ") or "") .. (hours>0 and (hours .. " jam ") or "") .. minutes .. " menit"
end
local function remaining(s)
    if not s then return "Belum dimulai" end
    if not running(s) then return "Selesai" end
    return UI.countdown(s.ends_at-os.time())
end
function UI.bar(L, key, label, current, maximum, color)
    current=math.max(0,math.min(current,maximum))
    -- Native progress element; numeric captions also remain visible independently.
    line(L,"add_progress_bar|" .. key .. "|big|" .. label .. "|" .. number(current) .. "|" .. number(maximum) .. "|" .. (color or "blue") .. "|")
end
function UI.summary(L, s, p)
    local id=uid(p); local earned=points(s,id); local step=config("xp_per_level"); local cap=LEVELS*step
    text(L,s and ("`oSEASON " .. s.id .. "  /  " .. (running(s) and "BERLANGSUNG" or "SELESAI") .. "``") or "`oBelum dimulai. Founder sedang menyiapkan KitPass.``")
    text(L,"Sisa waktu: `w" .. remaining(s) .. "``")
    if s then text(L,"`oBerakhir: " .. os.date("!%d/%m/%Y %H:%M",s.ends_at+25200) .. " WIB``") end
    UI.section(L,"PROGRESS KITPASS")
    text(L,"Level KitPass: `w" .. level(s,id) .. " / " .. LEVELS .. "``  /  " .. fmt(math.min(earned,cap)) .. " / " .. fmt(cap) .. " XP")
    UI.bar(L,"kitpass_xp","KITPASS XP",earned,cap,"blue")
    if level(s,id)>=LEVELS then text(L,"`3LEVEL MAKSIMAL`` - semua level telah terbuka.")
    else text(L,"`o" .. fmt((level(s,id)+1)*step-earned) .. " XP lagi menuju Level " .. (level(s,id)+1) .. ".``") end
    if earned>cap then text(L,"`oTotal XP musim: " .. fmt(earned) .. "``") end
end
function UI.tiers(s, id, track)
    local rewards, claims, result={}, {}, {}
    for _,r in ipairs(q("SELECT * FROM kp_rewards WHERE track=" .. sql(track))) do rewards[r.level]=r end
    if s then for _,c in ipairs(q("SELECT * FROM kp_claims WHERE season=" .. s.id .. " AND uid=" .. id .. " AND track=" .. sql(track))) do claims[c.level]=c end end
    local hold=held(id); local allowed=track=="basic" or premium(s,id); local currentLevel=level(s,id)
    for n=1,LEVELS do
        local r,c=rewards[n],claims[n]
        local status
        if c and c.state=="claimed" then status="claimed"
        elseif c and c.state=="pending" then status="pending"
        elseif not r then status="empty"
        elseif not getItem(r.item) then status="missing"
        elseif not running(s) then status="inactive"
        elseif n>currentLevel then status="locked"
        elseif not allowed then status="premium"
        elseif hold then status="held"
        else status="ready" end
        result[n]={level=n,track=track,reward=r,receipt=c,status=status,display=(c and (c.state=="claimed" or c.state=="pending")) and c or r}
    end
    return result
end
function UI.readyRewards(s, id, track)
    local available={}
    for _,t in ipairs(track and {track} or {"basic","premium"}) do
        for _,row in ipairs(UI.tiers(s,id,t)) do if row.status=="ready" then available[#available+1]=row end end
    end
    return available
end
function UI.card(L, row, step, compact)
    local r=row.display
    local accent=row.track=="premium" and "`6" or "`3"
    if r then
        local item=getItem(r.item); local name=item and clean(item:getName(),32) or ("Item #" .. r.item)
        line(L,"add_label_with_icon|" .. (compact and "small" or "big") .. "|" .. accent .. "Level " .. row.level .. "`` - " .. name .. "|left|" .. r.item .. "|")
        text(L,"`o" .. (row.track=="basic" and "BASIC" or "PREMIUM") .. "  /  x" .. fmt(r.amount) .. "  /  " .. fmt(row.level*step) .. " XP``")
    else line(L,"add_label|small|" .. accent .. "Level " .. row.level .. "``|left|"); text(L,"`oReward belum diatur Founder.``") end
    local captions={claimed="`2SUDAH DIKLAIM``",pending="`4PENDING - perlu diperiksa Founder.``",missing="`oItem belum tersedia. Hubungi Founder.``",inactive="`oKlaim ditutup - KitPass belum aktif atau selesai.``",locked="`oTERKUNCI - selesaikan misi untuk naik level.``",premium="`oPREMIUM TERKUNCI - akses diberikan Founder.``",held="`oKlaim menunggu pemeriksaan Founder.``",ready="`3SIAP DIKLAIM``"}
    if captions[row.status] then text(L,captions[row.status]) end
end
function UI.home(p)
    local s=season(); local id=uid(p); local L=begin("KITPASS")
    text(L,"`oSelesaikan misi. Naik level. Kumpulkan reward musim ini.``")
    UI.summary(L,s,p)
    local basic=UI.tiers(s,id,"basic"); local prem=UI.tiers(s,id,"premium")
    local counts={basic=0,premium=0,claimed=0}
    for _,rows in ipairs({basic,prem}) do for _,r in ipairs(rows) do
        if r.status=="ready" then counts[r.track]=counts[r.track]+1 elseif r.status=="claimed" then counts.claimed=counts.claimed+1 end
    end end
    UI.section(L,"REWARD TRACKS")
    text(L,"`3BASIC`` - untuk semua player.")
    local access=premium(s,id)
    text(L,"`6PREMIUM`` - " .. (access and running(s) and "AKTIF" or (access and "Musim selesai" or "akses diberikan Founder")) .. ".")
    text(L,"Reward siap klaim: `wBasic " .. counts.basic .. " / Premium " .. counts.premium .. "``  /  Diklaim: " .. counts.claimed)
    if held(id) then text(L,"`oAda klaim yang perlu diperiksa Founder sebelum mengambil hadiah lain.``") end
    button(L,"basic","`3BASIC REWARDS`` (" .. counts.basic .. " siap)")
    button(L,"premium","`6PREMIUM REWARDS`` (" .. counts.premium .. " siap)")
    if counts.basic+counts.premium>=2 then button(L,"claim_all","Claim All Available Rewards") end
    UI.section(L,"MISSIONS & REWARDS")
    button(L,"missions","Daily & Weekly Missions"); button(L,"preview","Preview All Rewards")
    button(L,"refresh","Refresh"); button(L,"help","How to Play")
    show(p,L,{view="home"})
end
function UI.track(p, track)
    local s=season(); local id=uid(p); local L=begin(track=="basic" and "KITPASS BASIC" or "KITPASS PREMIUM")
    text(L,track=="basic" and "`oReward gratis untuk semua player.``" or "`oReward tambahan untuk pemilik Premium dari Founder.``")
    UI.summary(L,s,p)
    local rows=UI.tiers(s,id,track); local available=0
    for _,row in ipairs(rows) do
        line(L,"add_spacer|small|"); UI.card(L,row,config("xp_per_level"))
        if row.status=="ready" then available=available+1; button(L,"claim_"..row.level,"Claim Level " .. row.level) end
    end
    line(L,"add_spacer|small|")
    if available>=2 then button(L,"claim_all","Claim All " .. (track=="basic" and "Basic" or "Premium") .. " Rewards") end
    button(L,"missions","Missions"); button(L,"refresh","Refresh"); button(L,"back","Back")
    show(p,L,{view="track",track=track})
end
function UI.preview(p)
    local s=season(); local L=begin("REWARD PREVIEW")
    text(L,"`oTiga level. Dua track. Progress XP yang sama.``")
    for _,track in ipairs({"basic","premium"}) do
        UI.section(L,track=="basic" and "BASIC - untuk semua player" or "PREMIUM - diberikan Founder")
        for _,row in ipairs(UI.tiers(s,uid(p),track)) do UI.card(L,row,config("xp_per_level"),true) end
    end
    button(L,"back","Back"); show(p,L,{view="preview"})
end
function UI.help(p)
    local L=begin("HOW TO PLAY")
    for _,entry in ipairs({
        {"1. Selesaikan misi","Misi harian dan mingguan memberi XP otomatis setelah target selesai."},
        {"2. Buka level","Setiap " .. fmt(config("xp_per_level")) .. " XP membuka satu level. Maksimal Level " .. LEVELS .. "."},
        {"3. Klaim reward","Basic terbuka untuk semua player. Premium hanya aktif setelah diberikan Founder."},
        {"4. Ikuti musim","Hadiah harus diambil sebelum durasi selesai. Setiap reward hanya dapat diklaim sekali per musim."},
        {"Reset misi","Harian: 00.00 WIB. Mingguan: Senin 00.00 WIB. Reset misi tidak menghapus XP musim."},
    }) do UI.section(L,entry[1]); line(L,"add_textbox|`o" .. entry[2] .. "``|left|") end
    button(L,"back","Back"); show(p,L,{view="help"})
end
function UI.confirmAll(p, track, previous)
    assert(config("revision")==previous.revision and config("season")==previous.season,"Pengaturan berubah. Buka /kitpass lagi.")
    local rewards=UI.readyRewards(season(),uid(p),track)
    assert(#rewards>=2,"Tidak ada cukup reward siap klaim. Muat ulang menu.")
    local L=begin("CONFIRM CLAIM ALL")
    text(L,"Klaim " .. #rewards .. " reward yang sudah terbuka?")
    for _,r in ipairs(rewards) do
        line(L,"add_spacer|small|"); UI.card(L,r,config("xp_per_level"),true)
    end
    button(L,"confirm_all","Confirm Claim All"); button(L,"back","Back")
    local snapshot={}
    for _,r in ipairs(rewards) do snapshot[#snapshot+1]={track=r.track,level=r.level,item=r.reward.item,amount=r.reward.amount} end
    show(p,L,{view="claim_all",track=track,rewards=snapshot})
end
local function claimAll(p, state)
    assert(config("revision")==state.revision and config("season")==state.season,"Pengaturan berubah. Buka /kitpass lagi.")
    assert(running(season()),"KitPass sudah selesai.")
    local totals={}
    for _,r in ipairs(state.rewards) do
        assert(r.track=="basic" or premium(season(),uid(p)),"Premium hanya diberikan oleh Founder.")
        assert(getItem(r.item),"Item reward tidak tersedia.")
        totals[r.item]=(totals[r.item] or 0)+r.amount
    end
    for item,amount in pairs(totals) do assert(p:getItemAmount(item)+p:getExtraBackpackAmount(item)+amount<=MAX_AMOUNT,"Jumlah item inventory/Extra Backpack melebihi batas.") end
    local done=0
    for _,r in ipairs(state.rewards) do
        local ok,err=pcall(claim,p,r.track,r.level,state)
        if not ok then tell(p,"`o" .. done .. " reward berhasil diklaim. Klaim berikutnya dihentikan: " .. clean(err,170)); return end
        done=done+1
    end
    tell(p,"`3CLAIM ALL SELESAI`` - " .. done .. " reward berhasil diambil.")
end
function UI.admin(p)
    assert(founder(p),"Panel ini khusus Founder.")
    local s=season(); local L=begin("KITPASS SETTINGS")
    text(L,"`oFOUNDER PANEL  /  Satu KitPass  /  3 Level``")
    text(L,"Sisa waktu: " .. remaining(s))
    if s then text(L,"Berakhir: " .. os.date("!%d/%m/%Y %H:%M",s.ends_at+25200) .. " WIB") end
    text(L,s and ("Duration saat ini: " .. s.duration .. " hari") or "Atur Duration untuk memulai KitPass.")
    local basic=q("SELECT COUNT(*) AS n FROM kp_rewards WHERE track='basic'")[1].n
    local prem=q("SELECT COUNT(*) AS n FROM kp_rewards WHERE track='premium'")[1].n
    UI.section(L,"REWARD SETUP")
    text(L,"Basic: " .. basic .. " / " .. LEVELS .. " reward  /  Premium: " .. prem .. " / " .. LEVELS .. " reward")
    text(L,"`oPremium player: /givepremiumkit GROWID (target online).``")
    UI.section(L,"SETTINGS")
    button(L,"duration","Set Duration"); button(L,"rewards_basic","Set Reward"); button(L,"rewards_premium","Set Premium Reward"); button(L,"mission_rules","Set Mission")
    show(p,L,{view="admin"})
end
function UI.duration(p)
    local s=season(); local L=begin("SET DURATION")
    text(L,"Duration hanya bisa diatur Founder.")
    text(L,running(s) and "Waktu berakhir dihitung dari awal musim yang sedang berjalan." or "Menyimpan Duration memulai musim baru. Premium dan klaim berlaku per musim.")
    line(L,"add_text_input|days|Duration (Hari):|" .. (s and s.duration or "") .. "|3|")
    button(L,"save_duration","Save Duration"); button(L,"back_admin","Back"); show(p,L,{view="duration",restart=not running(s)})
end
function UI.confirmDuration(p, raw, previous)
    local days=assert(int(raw,1,365),"Duration harus 1-365 hari.")
    assert(config("revision")==previous.revision and config("season")==previous.season,"Pengaturan berubah. Buka /setkitpass lagi.")
    local L=begin("MULAI KITPASS")
    text(L,"Mulai musim baru selama " .. days .. " hari?")
    text(L,"XP dan akses Premium dimulai dari awal; reward yang diatur tetap digunakan.")
    button(L,"start","Start KitPass"); button(L,"back_admin","Back")
    show(p,L,{view="start",days=days,restart=true})
end
function UI.rewards(p, track)
    local L=begin(track=="basic" and "SET REWARD" or "SET PREMIUM REWARD")
    text(L,track=="basic" and "`3BASIC`` - reward untuk semua player." or "`6PREMIUM`` - reward tambahan untuk pemilik Premium.")
    text(L,"ItemID 0 dan Amount 0 untuk mengosongkan reward.")
    text(L,"Reward yang sudah diklaim tetap tercatat pada musim yang sama.")
    for n=1,LEVELS do
        local r=q("SELECT * FROM kp_rewards WHERE track=" .. sql(track) .. " AND level=" .. n)[1]
        line(L,"add_spacer|small|\nadd_label|small|Level " .. n .. "|left|")
        if r and getItem(r.item) then line(L,"add_label_with_icon|small|`o" .. clean(getItem(r.item):getName(),32) .. " x" .. fmt(r.amount) .. "``|left|" .. r.item .. "|") end
        line(L,"add_text_input|item_" .. n .. "|ItemID :|" .. (r and r.item or 0) .. "|10|")
        line(L,"add_text_input|amount_" .. n .. "|Amount :|" .. (r and r.amount or 0) .. "|10|")
    end
    button(L,"save_rewards","Save Reward"); button(L,"back_admin","Back"); show(p,L,{view="rewards",track=track})
end
local function missionLabel(action) return action=="break" and "Pecahkan blok" or "Panen pohon" end
function UI.missions(p)
    local s=season(); local L=begin("KITPASS MISSIONS")
    UI.summary(L,s,p)
    text(L,"`oXP diterima otomatis ketika target misi selesai.``")
    if running(s) then
        for _,kind in ipairs({"daily","weekly"}) do
            local m=mission(s,uid(p),kind)
            UI.section(L,kind=="daily" and "DAILY MISSION / MISI HARIAN" or "WEEKLY MISSION / MISI MINGGUAN")
            line(L,"add_label|small|`w" .. missionLabel(m.action) .. "``|left|")
            text(L,"Progress: " .. fmt(m.progress) .. " / " .. fmt(m.goal) .. "  /  " .. math.floor(m.progress/m.goal*100) .. "%")
            UI.bar(L,kind.."_progress","MISSION PROGRESS",m.progress,m.goal,"blue")
            text(L,"Reward: `w+" .. fmt(m.reward_xp) .. " XP``  /  " .. (m.completed==1 and "`2SELESAI``" or "`oDALAM PROGRESS``"))
            local reset=(kind=="daily" and (period(kind)+1)*86400 or ((period(kind)+1)*7-3)*86400)-25200
            text(L,"`oReset " .. (kind=="daily" and "00.00 WIB" or "Senin 00.00 WIB") .. " / " .. UI.countdown(reset-os.time()) .. " lagi``")
        end
    else text(L,"KitPass belum aktif atau durasinya sudah habis.") end
    line(L,"add_spacer|small|"); button(L,"refresh","Refresh Missions"); button(L,"back","Back"); show(p,L,{view="missions"})
end
function UI.missionRules(p)
    local L=begin("SET MISSION")
    text(L,"Action: break = pecahkan blok; harvest = panen pohon.")
    text(L,"Misi yang sudah dimulai tetap memakai aturan lama sampai reset berikutnya.")
    line(L,"add_text_input|xp_per_level|XP per Level :|" .. config("xp_per_level") .. "|7|")
    for _,kind in ipairs({"daily","weekly"}) do
        local r=q("SELECT * FROM kp_mission_rules WHERE kind=" .. sql(kind))[1]
        line(L,"add_spacer|small|\nadd_label|small|" .. (kind=="daily" and "Misi Harian" or "Misi Mingguan") .. "|left|")
        line(L,"add_text_input|" .. kind .. "_action|Action :|" .. r.action .. "|7|")
        line(L,"add_text_input|" .. kind .. "_goal|Target :|" .. r.goal .. "|7|")
        line(L,"add_text_input|" .. kind .. "_xp|Reward XP :|" .. r.reward_xp .. "|7|")
    end
    button(L,"save_missions","Save Mission"); button(L,"back_admin","Back"); show(p,L,{view="mission_rules"})
end
local function command(_, p, full)
    if type(full)~="string" then return false end
    local name,args=full:match("^%s*/?(%S+)%s*(.-)%s*$"); name=name and name:lower()
    if name~="kitpass" and name~="setkitpass" and name~="givepremiumkit" then return false end
    guard(p,function()
        if name=="givepremiumkit" then grant(p,args)
        elseif name=="setkitpass" then assert(args=="","Gunakan /setkitpass."); UI.admin(p)
        else assert(args=="","Gunakan /kitpass."); UI.home(p) end
    end)
    return true
end
local function dialog(_, p, data)
    if type(data)~="table" or type(data.dialog_name)~="string" or not data.dialog_name:match("^kitpass_") then return false end
    guard(p,function()
        local state=sessions[uid(p)]
        if not state or state.name~=data.dialog_name then tell(p,"`oMenu kedaluwarsa. Buka /kitpass atau /setkitpass lagi."); return end
        sessions[uid(p)]=nil
        local clicked=data.buttonClicked
        if clicked==nil or clicked=="" or clicked=="cancel" then return end
        assert(os.time()<=state.expires and state.buttons[clicked],"Menu kedaluwarsa. Buka menu terbaru.")
        if state.view=="admin" or state.view=="duration" or state.view=="start" or state.view=="rewards" or state.view=="mission_rules" then assert(founder(p),"Panel ini khusus Founder.") end
        if state.view=="home" then
            if clicked=="missions" then UI.missions(p)
            elseif clicked=="refresh" then UI.home(p)
            elseif clicked=="preview" then UI.preview(p)
            elseif clicked=="help" then UI.help(p)
            elseif clicked=="claim_all" then UI.confirmAll(p,nil,state)
            else UI.track(p,clicked) end
        elseif state.view=="missions" then if clicked=="refresh" then UI.missions(p) else UI.home(p) end
        elseif state.view=="preview" or state.view=="help" then UI.home(p)
        elseif state.view=="track" then
            if clicked=="back" then UI.home(p)
            elseif clicked=="refresh" then UI.track(p,state.track)
            elseif clicked=="missions" then UI.missions(p)
            elseif clicked=="claim_all" then UI.confirmAll(p,state.track,state)
            else local n=assert(int(clicked:match("^claim_(%d+)$"),1,LEVELS)); claim(p,state.track,n,state); UI.track(p,state.track) end
        elseif state.view=="claim_all" then
            if clicked=="confirm_all" then claimAll(p,state) end
            if state.track then UI.track(p,state.track) else UI.home(p) end
        elseif clicked=="back_admin" then UI.admin(p)
        elseif state.view=="admin" then
            if clicked=="duration" then UI.duration(p) elseif clicked=="mission_rules" then UI.missionRules(p) else UI.rewards(p,clicked=="rewards_basic" and "basic" or "premium") end
        elseif state.view=="duration" and clicked=="save_duration" then
            if state.restart then UI.confirmDuration(p,data.days,state) else setDuration(p,data.days,state); tell(p,"`2Duration tersimpan."); UI.admin(p) end
        elseif state.view=="start" and clicked=="start" then setDuration(p,state.days,state); tell(p,"`2KitPass dimulai."); UI.admin(p)
        elseif state.view=="rewards" and clicked=="save_rewards" then saveRewards(p,state.track,data,state); tell(p,"`2Reward tersimpan."); UI.admin(p)
        elseif state.view=="mission_rules" and clicked=="save_missions" then saveMissions(p,data,state); tell(p,"`2Misi tersimpan."); UI.admin(p) end
    end)
    return true
end
local function install(label, fn, argument)
    if type(fn)~="function" then print("[kitpass] Missing API: " .. label); return false end
    local ok,result=pcall(fn,argument)
    if not ok or result==false then print("[kitpass] Registration failed: " .. label .. " / " .. tostring(result)); return false end
    return true
end
print("[kitpass] BOOT " .. VERSION .. " | " .. tostring(_VERSION))
local dialogOK=install("dialog",onPlayerDialogCallback,dialog)
local commandOK=install("command",onPlayerCommandCallback,command)
local registered=true
for _,spec in ipairs({{"kitpass",0,"Basic dan Premium KitPass."},{"setkitpass",1000,"Founder: Duration dan Reward KitPass."},{"givepremiumkit",1000,"Founder: beri Premium KitPass ke GrowID online."}}) do
    local name=spec[1]
    local ok=install("/"..name,registerLuaCommand,{command=name,roleRequired=spec[2],exactRole=spec[2]==1000,description=spec[3],callback=function(p,args) return command(nil,p,name .. " " .. (args or "")) end})
    registered=ok and registered
end
install("disconnect",onPlayerDisconnectCallback,function(p) if p then sessions[uid(p)],busy[uid(p)]=nil,nil end end)
local breakOK=install("mission break",onTileBreakCallback,function(_,p,tile)
    if tile and tile:getTileForeground()>0 then
        local ok,err=pcall(progress,p,"break"); if not ok then print("[kitpass] MISSION ERROR: " .. tostring(err)) end
    end
end)
local harvestOK=install("mission harvest",onPlayerHarvestCallback,function(_,p)
    local ok,err=pcall(progress,p,"harvest"); if not ok then print("[kitpass] MISSION ERROR: " .. tostring(err)) end
end)
ready,initError=pcall(function()
    assert(dialogOK and (registered or commandOK),"API command/dialog tidak tersedia.")
    assert(type(getItem)=="function" and type(getPlayerByName)=="function","API item/player tidak tersedia.")
    assert(breakOK and harvestOK,"API misi break/harvest tidak tersedia.")
    initialize()
end)
print("[kitpass] ROUTES registered=" .. tostring(registered) .. " command=" .. tostring(commandOK) .. " dialog=" .. tostring(dialogOK))
print(ready and "[kitpass] Loaded /kitpass /setkitpass /givepremiumkit" or ("[kitpass] INIT FAILED: " .. tostring(initError)))
