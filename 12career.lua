-- Developer: Nathan
-- Standalone GTPS Lua 5.1+. /career (/12career) and Founder /setcareer.
-- Native activity callbacks only; unsupported activities require a trusted
-- server integration through Career12.connect/complete. No client XP grants.
local VERSION, DB_FILE = "v1-careers", "career12_v1.db"
local MAX_LEVEL, BASE_XP, MAX_AMOUNT = 10, 100, 2000000000
local MAX_ID, SESSION_SECONDS = 9007199254740991, 120
local db, ready, generation, initError
local sessions, busy, serial = {}, {}, 0
local UI, API, sources, byID = {}, {version=1}, {}, {}
local unpack = unpack or table.unpack
local CAREERS = {
    {id="hero",name="Hero",defaultXP=25,summary="Selesaikan misi Hero dan hadapi penjahat untuk mengembangkan karirmu.",guide={
        "Selesaikan satu misi Hero yang berhasil. XP diberikan setelah keberhasilan dikonfirmasi server.",
        "Satu misi selesai dihitung satu aktivitas. Misi gagal dan percobaan belum memberi XP.",
        "Jika status Menunggu, aktivitas Hero belum tersambung di server ini."}},
    {id="mystic",name="Mystic",defaultXP=20,summary="Kembangkan karir Mystic melalui ritual dan misi yang berhasil.",guide={
        "Selesaikan satu aktivitas Mystic yang berhasil dan dikonfirmasi server.",
        "Satu ritual atau misi selesai dihitung satu aktivitas. Percobaan gagal tidak memberi XP.",
        "Jika status Menunggu, aktivitas Mystic belum tersambung di server ini."}},
    {id="surgeon",name="Surgeon",defaultXP=20,summary="Bantu pasien melalui operasi yang berhasil.",guide={
        "Selesaikan operasi hingga server memberikan hadiah keberhasilan kepada surgeon.",
        "Satu operasi berhasil dihitung satu aktivitas, berapa pun jumlah item hadiahnya.",
        "Operasi gagal dan hadiah level karir tidak menambah XP Surgeon."}},
    {id="angler",name="Angler",icon=3000,defaultXP=10,summary="Tangkap ikan dan bangun karir pemancingmu.",guide={
        "Pancing sampai ikan berhasil ditangkap dan hasil tangkapan diberikan server.",
        "Satu tangkapan dihitung satu aktivitas. Berat ikan tidak menggandakan XP.",
        "Melempar pancing, ikan lepas, dan menjual ikan belum memberi XP Angler."}},
    {id="trainer",name="Trainer",defaultXP=10,summary="Kelola ikan di Fish Tank untuk mengembangkan karir Trainer.",guide={
        "Masukkan ikan ke Fish Tank sampai server mengonfirmasi ikan sudah berada di tank.",
        "Satu pemasukan ikan dihitung satu aktivitas, mengikuti fitur training di server ini.",
        "XP Trainer di sini berasal dari Fish Tank; kemenangan pertarungan ikan belum dihitung."}},
    {id="startopia",name="Startopia",defaultXP=25,summary="Selesaikan perjalanan dan misi luar angkasa.",guide={
        "Selesaikan satu misi Startopia yang berhasil dan dikonfirmasi server.",
        "Satu misi selesai dihitung satu aktivitas. Misi gagal tidak memberi XP.",
        "Jika status Menunggu, aktivitas Startopia belum tersambung di server ini."}},
    {id="cooking",name="Cooking",defaultXP=20,summary="Masak hidangan dengan hasil yang memenuhi resep.",guide={
        "Selesaikan masakan di oven dan capai akurasi minimum resep hidangan tersebut.",
        "Satu masakan berhasil dihitung satu aktivitas. Jumlah hidangan tidak menggandakan XP.",
        "Masakan RUINED dan item pengganti dari kegagalan tidak dihitung.",
        "Jika beberapa resep menghasilkan item yang sama, akurasi minimum tertinggi digunakan."}},
    {id="ghost",name="Ghost Hunter",icon=21264,defaultXP=10,summary="Tangkap ghost sampai hasil tangkapan masuk ke inventory.",guide={
        "Tangkap ghost hingga server memberikan jar hasil tangkapan.",
        "Satu penangkapan berhasil dihitung satu aktivitas, berapa pun jumlah jar.",
        "Memunculkan ghost, memakai mode /ghost, dan membeli jar belum memberi XP."}},
    {id="farmer",name="Farmer",defaultXP=2,summary="Panen pohon dan kembangkan karir pertanianmu.",guide={
        "Panen pohon yang sudah matang hingga server mengonfirmasi hasil panen.",
        "Satu pohon dipanen dihitung satu aktivitas. Jumlah buah tidak menggandakan XP.",
        "Menanam, mengambil drop, dan menghancurkan block biasa belum memberi XP Farmer."}},
    {id="firefighter",name="Firefighter",defaultXP=10,summary="Padamkan api untuk membantu menjaga world.",guide={
        "Padamkan api hingga server mengonfirmasi api berhasil dipadamkan.",
        "Satu api padam dihitung satu aktivitas.",
        "Percobaan yang gagal dan tile tanpa api belum memberi XP Firefighter."}},
    {id="provider",name="Provider",icon=3044,defaultXP=5,summary="Dapatkan hasil dari siklus provider milikmu.",guide={
        "Tunggu provider menyelesaikan satu siklus dan membayarkan hasilnya.",
        "Satu pembayaran siklus dihitung satu aktivitas; jumlah item tidak menggandakan XP.",
        "XP diberikan ke pemilik provider yang dilaporkan server, bukan pengambil drop."}},
    {id="gladiator",name="Gladiator",defaultXP=25,summary="Raih kemenangan dalam pertarungan yang dikonfirmasi server.",guide={
        "Menangkan satu pertarungan Gladiator yang divalidasi oleh sistem pertarungan server.",
        "Satu kemenangan dihitung satu aktivitas. Memukul player saja tidak memberi XP.",
        "Jika status Menunggu, aktivitas Gladiator belum tersambung di server ini."}},
}
for _,meta in ipairs(CAREERS) do
    byID[meta.id]=meta
    sources[meta.id]={ready=false,mode="bridge",label="Perlu integrasi sukses " .. meta.name .. " melalui Career12."}
end

local function integer(n,low,high)
    return type(n)=="number" and n==n and n>=low and n<=high and n==math.floor(n) and n or nil
end
local function number(n) return string.format("%.0f",n) end
local function fmt(n) return number(n):reverse():gsub("(%d%d%d)","%1."):reverse():gsub("^%.","") end
local function clean(v,limit) return tostring(v or ""):gsub("`.",""):gsub("[|%c]"," "):sub(1,limit or 200) end
local function sql(v) return "'" .. tostring(v):gsub("%z",""):gsub("'","''") .. "'" end
local function uid(p) return assert(integer(p:getUserID(),1,MAX_ID),"ID akun tidak valid.") end
local function realPlayer(p) return p and p:isOnline() and p:getType()==0 end
local function founder(p) return realPlayer(p) and p:getRole()==1000 end
local function tell(p,s) p:onConsoleMessage("`3[12 Careers]`` " .. s) end
local function query(s) return assert(db:query(s),"Database karir tidak dapat diakses.") end
local function tx(callback)
    query("BEGIN IMMEDIATE")
    local ok,value=pcall(callback)
    if ok then ok,value=pcall(function() query("COMMIT"); return value end) end
    if not ok then pcall(function() query("ROLLBACK") end); error(value) end
    return value
end
local function threshold(n) return BASE_XP*n*(n+1)/2 end
local function level(xp)
    local n=0
    while n<MAX_LEVEL and xp>=threshold(n+1) do n=n+1 end
    return n
end
local function settings(id)
    assert(byID[id],"Karir tidak ditemukan.")
    local row=assert(query("SELECT * FROM c12_careers WHERE id=" .. sql(id))[1],"Pengaturan karir tidak tersedia.")
    row.enabled=assert(integer(tonumber(row.enabled),0,1),"Status karir tidak valid.")
    row.xp_per_event=assert(integer(tonumber(row.xp_per_event),1,1000000),"XP per aktivitas tidak valid.")
    row.revision=assert(integer(tonumber(row.revision),0,MAX_ID-1),"Versi pengaturan tidak valid.")
    return row
end
local function progress(id,career)
    local row=query("SELECT xp,activities FROM c12_progress WHERE uid=" .. number(id) .. " AND career=" .. sql(career))[1]
    if not row then return {xp=0,activities=0} end
    row.xp=assert(integer(tonumber(row.xp),0,MAX_AMOUNT),"XP tersimpan tidak valid.")
    row.activities=assert(integer(tonumber(row.activities),0,MAX_AMOUNT),"Jumlah aktivitas tidak valid.")
    return row
end
local function pending(id)
    return query("SELECT id FROM c12_claims WHERE uid=" .. number(id) .. " AND state='pending' LIMIT 1")[1]
end
local function rewardConfig(id,n)
    local row=query("SELECT item,amount FROM c12_rewards WHERE career=" .. sql(id) .. " AND level=" .. n)[1]
    if row then
        row.item=assert(integer(tonumber(row.item),1,MAX_AMOUNT),"ID reward tersimpan tidak valid.")
        row.amount=assert(integer(tonumber(row.amount),1,MAX_AMOUNT),"Jumlah reward tersimpan tidak valid.")
    end
    return row
end
local function careerData(p,id)
    local row=progress(uid(p),id)
    return {meta=assert(byID[id],"Karir tidak ditemukan."),config=settings(id),xp=row.xp,level=level(row.xp),
        source=sources[id],held=pending(uid(p))~=nil}
end
local function tierRows(p,id)
    local data=careerData(p,id)
    local claims={}
    for _,row in ipairs(query("SELECT level,item,amount,state FROM c12_claims WHERE uid=" .. number(uid(p)) .. " AND career=" .. sql(id))) do
        claims[tonumber(row.level)]=row
    end
    local rows={}
    for n=1,MAX_LEVEL do
        local reward,receipt=rewardConfig(id,n),claims[n]
        local status
        if receipt and receipt.state=="claimed" then status="claimed"
        elseif receipt and receipt.state=="pending" then status="pending"
        elseif not reward then status="empty"
        elseif not getItem(reward.item) then status="missing"
        elseif data.level<n then status="locked"
        elseif data.config.enabled~=1 then status="paused"
        elseif not data.source.ready then status="waiting"
        elseif data.held then status="held"
        else status="ready" end
        local display=reward
        if receipt and (receipt.state=="claimed" or receipt.state=="pending") then
            display={item=tonumber(receipt.item),amount=tonumber(receipt.amount)}
        end
        rows[n]={level=n,status=status,display=display}
    end
    return rows
end
local function log(actor,event,career,detail)
    query("INSERT INTO c12_log(actor,event,career,detail,at) VALUES(" .. number(actor) .. "," .. sql(event) .. ","
        .. sql(career or "") .. "," .. sql(clean(detail,240)) .. "," .. os.time() .. ")")
end
local function snapshot(p,item)
    return {inventory=assert(integer(p:getItemAmount(item),0,MAX_AMOUNT),"Jumlah item tidak valid."),
        extra=assert(integer(p:getExtraBackpackAmount(item),0,MAX_AMOUNT),"Jumlah Extra Backpack tidak valid.")}
end
local function parse(value,low,high)
    if type(value)~="string" or #value>16 then return nil end
    local digits=value:match("^%s*(%d+)%s*$")
    return digits and integer(tonumber(digits),low,high) or nil
end
local function guard(p,callback)
    if not realPlayer(p) then return end
    local id=uid(p)
    if busy[id] then return end
    busy[id]=true
    local ok,err=pcall(function()
        assert(ready,"Sistem karir belum tersedia. Periksa log [12career] di server.")
        callback()
    end)
    busy[id]=nil
    if not ok then
        sessions[id]=nil
        print("[12career] ERROR uid=" .. number(id) .. " / " .. tostring(err))
        local checked,row=false,nil
        if ready then checked,row=pcall(pending,id) end
        tell(p,"`o" .. (checked and row and ("Reward #" .. number(row.id) .. " perlu diperiksa Founder sebelum klaim lagi.")
            or clean(err,220):gsub("^.-:%d+:%s*","")) .. "``")
    end
end

-- Activity and external success receipts commit together. Native callbacks have
-- no event ID: count one documented successful event, never fruit/item/weight.
local function award(p,id,receipt)
    if not ready or not realPlayer(p) then return false,"unavailable" end
    assert(byID[id],"Karir tidak ditemukan.")
    if not sources[id].ready then return false,"disconnected" end
    local account=uid(p)
    if busy[account] then return false,"busy" end
    busy[account]=true
    local ok,result=pcall(function()
        local result=tx(function()
            local cfg=settings(id)
            if cfg.enabled~=1 then return {reason="paused"} end
            if receipt and query("SELECT receipt FROM c12_receipts WHERE uid=" .. number(account) .. " AND career=" .. sql(id) .. " AND receipt=" .. sql(receipt))[1] then
                return {reason="duplicate"}
            end
            local before=progress(account,id)
            local after=math.min(MAX_AMOUNT,before.xp+cfg.xp_per_event)
            query("INSERT OR IGNORE INTO c12_progress(uid,career,xp,activities,updated_at) VALUES(" .. number(account) .. "," .. sql(id) .. ",0,0," .. os.time() .. ")")
            query("UPDATE c12_progress SET xp=" .. number(after) .. ",activities=MIN(2000000000,activities+1),updated_at=" .. os.time()
                .. " WHERE uid=" .. number(account) .. " AND career=" .. sql(id))
            if receipt then query("INSERT INTO c12_receipts(uid,career,receipt,at) VALUES(" .. number(account) .. "," .. sql(id) .. "," .. sql(receipt) .. "," .. os.time() .. ")") end
            local beforeLevel,afterLevel=level(before.xp),level(after)
            if afterLevel>beforeLevel then log(account,"level_up",id,"Level " .. afterLevel .. ", XP " .. number(after)) end
            return {awarded=true,beforeLevel=beforeLevel,afterLevel=afterLevel}
        end)
        if result.awarded and result.afterLevel>result.beforeLevel then
            tell(p,"`3LEVEL UP!`` " .. byID[id].name .. " Level " .. result.afterLevel .. ". Buka /career untuk melihat reward.")
        end
        return result
    end)
    busy[account]=nil
    if not ok then print("[12career] XP ERROR " .. id .. " uid=" .. number(account) .. " / " .. tostring(result)); return false,"database_error" end
    return result.awarded==true,result.awarded and "awarded" or result.reason
end
local function claim(p,id,n,state)
    assert(integer(n,1,MAX_LEVEL),"Level reward tidak valid.")
    local account=uid(p)
    local key=tx(function()
        local cfg=settings(id)
        assert(cfg.revision==state.revision,"Pengaturan berubah. Buka ulang reward untuk melihat yang terbaru.")
        assert(cfg.enabled==1 and sources[id].ready,"Karir belum aktif.")
        assert(level(progress(account,id).xp)>=n,"Level reward belum terbuka.")
        assert(not pending(account),"Ada reward pending. Hubungi Founder.")
        local previous=query("SELECT state FROM c12_claims WHERE uid=" .. number(account) .. " AND career=" .. sql(id) .. " AND level=" .. n)[1]
        assert(not previous or previous.state=="cancelled","Reward sudah diklaim atau masih pending.")
        local reward=assert(rewardConfig(id,n),"Reward belum diatur Founder.")
        assert(getItem(reward.item),"Item reward belum tersedia di server.")
        local before=snapshot(p,reward.item)
        assert(before.inventory+before.extra+reward.amount<=MAX_AMOUNT,"Jumlah item akan melebihi batas penyimpanan.")
        query("INSERT OR REPLACE INTO c12_claims(uid,career,level,item,amount,state,before_inv,before_extra,at) VALUES("
            .. number(account) .. "," .. sql(id) .. "," .. n .. "," .. reward.item .. "," .. number(reward.amount)
            .. ",'pending'," .. number(before.inventory) .. "," .. number(before.extra) .. "," .. os.time() .. ")")
        return assert(integer(tonumber(query("SELECT last_insert_rowid() AS id")[1].id),1,MAX_ID),"Jurnal reward tidak valid.")
    end)
    local receipt=assert(query("SELECT * FROM c12_claims WHERE id=" .. number(key))[1],"Jurnal reward tidak ditemukan.")
    local giveOK,given=pcall(p.giveItem,p,receipt.item,receipt.amount)
    local readOK,after=pcall(snapshot,p,receipt.item)
    local unchanged=readOK and after.inventory==receipt.before_inv and after.extra==receipt.before_extra
    if giveOK and given==false and unchanged then
        tx(function()
            query("UPDATE c12_claims SET state='cancelled',after_inv=" .. number(after.inventory) .. ",after_extra=" .. number(after.extra)
                .. ",finished_at=" .. os.time() .. ",note='Grant refused without item changes' WHERE id=" .. number(key) .. " AND state='pending'")
            log(account,"claim_refused",id,"Reward #" .. number(key))
        end)
        tell(p,"Pengiriman reward ditolak server. Item tidak berubah; kamu bisa mencoba lagi.")
        UI.rewards(p,id,state.page); return
    end
    if not (giveOK and given==true and readOK and after.inventory>=receipt.before_inv and after.extra>=receipt.before_extra
        and after.inventory-receipt.before_inv+after.extra-receipt.before_extra==receipt.amount) then
        local note="api_ok=" .. tostring(giveOK) .. " result=" .. tostring(given) .. " read_ok=" .. tostring(readOK)
        if readOK then note=note .. " inventory=" .. number(after.inventory) .. " extra=" .. number(after.extra) end
        pcall(function() query("UPDATE c12_claims SET note=" .. sql(note) .. " WHERE id=" .. number(key)) end)
        print("[12career] NEEDS REVIEW #" .. number(key) .. " " .. note)
        error("Reward #" .. number(key) .. " perlu diperiksa Founder. Pengiriman tidak akan diulang otomatis.")
    end
    tx(function()
        assert(query("SELECT state FROM c12_claims WHERE id=" .. number(key))[1].state=="pending","Status reward berubah.")
        query("UPDATE c12_claims SET state='claimed',after_inv=" .. number(after.inventory) .. ",after_extra=" .. number(after.extra)
            .. ",finished_at=" .. os.time() .. ",note='Exact item delivery verified' WHERE id=" .. number(key) .. " AND state='pending'")
        log(account,"claimed",id,"Level " .. n .. ", item " .. receipt.item .. " x" .. number(receipt.amount) .. ", reward #" .. number(key))
    end)
    tell(p,"`2Reward " .. byID[id].name .. " Level " .. n .. " diterima!``"
        .. (after.extra>receipt.before_extra and (" Extra Backpack: +" .. fmt(after.extra-receipt.before_extra) .. " item.") or ""))
    UI.rewards(p,id,state.page)
end
local function revise(p,id,state)
    assert(founder(p),"Panel ini khusus Founder.")
    local cfg=settings(id)
    assert(cfg.revision==state.revision,"Pengaturan telah berubah. Buka kembali panel sebelum menyimpan.")
    assert(cfg.revision<MAX_ID-1,"Versi pengaturan mencapai batas.")
    return cfg
end
local function toggle(p,id,state)
    tx(function()
        local cfg=revise(p,id,state)
        query("UPDATE c12_careers SET enabled=" .. (cfg.enabled==1 and 0 or 1) .. ",revision=revision+1 WHERE id=" .. sql(id))
        log(uid(p),"toggle",id,cfg.enabled==1 and "paused" or "enabled")
    end)
    UI.manage(p,id)
end
local function setXP(p,id,value,state)
    assert(founder(p),"Panel ini khusus Founder.")
    local xp=assert(parse(value,1,1000000),"XP harus angka bulat 1-1.000.000, tanpa titik atau koma.")
    tx(function()
        revise(p,id,state)
        query("UPDATE c12_careers SET xp_per_event=" .. xp .. ",revision=revision+1 WHERE id=" .. sql(id))
        log(uid(p),"set_xp",id,number(xp))
    end)
    tell(p,"XP " .. byID[id].name .. " disimpan: +" .. fmt(xp) .. " per aktivitas.")
    UI.manage(p,id)
end
local function setRewards(p,id,data,state)
    assert(founder(p),"Panel ini khusus Founder.")
    local rows={}
    local first=(state.page-1)*5+1
    for n=first,math.min(first+4,MAX_LEVEL) do
        local item=parse(data["item_" .. n],0,MAX_AMOUNT)
        local amount=parse(data["amount_" .. n],0,MAX_AMOUNT)
        assert(item and amount,"Level " .. n .. ": ItemID dan Amount harus angka bulat, tanpa pemisah.")
        assert((item==0 and amount==0) or (item>0 and amount>0),"Level " .. n .. ": isi ItemID dan Amount, atau keduanya 0.")
        assert(item==0 or getItem(item),"Level " .. n .. ": ItemID tidak tersedia di server.")
        rows[#rows+1]={level=n,item=item,amount=amount}
    end
    tx(function()
        revise(p,id,state)
        for _,row in ipairs(rows) do
            query("DELETE FROM c12_rewards WHERE career=" .. sql(id) .. " AND level=" .. row.level)
            if row.item>0 then query("INSERT INTO c12_rewards(career,level,item,amount) VALUES(" .. sql(id) .. "," .. row.level .. "," .. row.item .. "," .. number(row.amount) .. ")") end
        end
        query("UPDATE c12_careers SET revision=revision+1 WHERE id=" .. sql(id))
        log(uid(p),"set_rewards",id,"Level " .. first .. "-" .. (first+4))
    end)
    tell(p,"`2Reward " .. byID[id].name .. " Level " .. first .. "-" .. (first+4) .. " disimpan.``")
    UI.manage(p,id)
end

local function begin(title,icon)
    local L={"set_default_color|`w\nset_bg_color|20,24,31,230|\nset_border_color|92,104,122,255|\n"}
    if icon and getItem(icon) then L[#L+1]="add_label_with_icon|big|`w" .. clean(title,90) .. "``|left|" .. icon .. "|\n"
    else L[#L+1]="add_label|big|`w" .. clean(title,90) .. "``|left|\n" end
    L[#L+1]="add_spacer|small|\n"
    return L
end
local function text(L,s) L[#L+1]="add_smalltext|" .. s .. "|\n" end
local function button(L,key,caption) L[#L+1]="add_button|" .. key .. "|" .. caption .. "|noflags|0|0|\n" end
local function show(p,L,state)
    serial=serial+1
    state.name="career12_" .. number(generation) .. "_" .. number(serial)
    state.expires,state.buttons=os.time()+SESSION_SECONDS,{}
    if state.career and not state.revision then state.revision=settings(state.career).revision end
    for _,line in ipairs(L) do
        local key=line:match("^add_button|([^|]+)|")
        if key then state.buttons[key]=true end
    end
    L[#L+1]="add_spacer|small|\nadd_smalltext|`9© Dibuat Oleh : Nathan``|\n"
    L[#L+1]="end_dialog|" .. state.name .. "|Tutup||\n"
    local markup=table.concat(L)
    assert(#markup<=4096,"Dialog terlalu panjang.")
    sessions[uid(p)]=state
    local ok,result=pcall(p.onDialogRequest,p,markup)
    if not ok or result==false then sessions[uid(p)]=nil; error("Menu karir tidak dapat dibuka.") end
end

-- Calm, compact native Career12 dialogs. Numeric captions remain visible if a
-- particular client does not render the native progress-bar element.
function UI.line(L,s) L[#L+1]=s .. "\n" end
function UI.section(L,title)
    UI.line(L,"add_spacer|small|")
    UI.line(L,"add_label|small|`w" .. clean(title,90) .. "``|left|")
end
function UI.status(data)
    if data.config.enabled~=1 then return "DIJEDA" end
    return data.source.ready and "AKTIF" or "MENUNGGU"
end
function UI.bar(L,key,current,maximum)
    current=math.max(0,math.min(current,maximum))
    UI.line(L,"add_progress_bar|" .. key .. "|big|CAREER XP|" .. string.format("%.0f",current) .. "|" .. string.format("%.0f",maximum) .. "|blue|")
end
function UI.summary(L,data)
    text(L,"`o" .. UI.status(data) .. "  /  +" .. fmt(data.config.xp_per_event) .. " XP per aktivitas valid``")
    text(L,"Level: `w" .. data.level .. " / " .. MAX_LEVEL .. "``  /  Total XP: `w" .. fmt(data.xp) .. "``")
    local base=threshold(data.level)
    if data.level<MAX_LEVEL then
        local nextLevel=threshold(data.level+1)
        text(L,"Progress level: " .. fmt(data.xp-base) .. " / " .. fmt(nextLevel-base) .. " XP")
        UI.bar(L,"career_progress",data.xp-base,nextLevel-base)
        text(L,"`o" .. fmt(nextLevel-data.xp) .. " XP lagi menuju Level " .. (data.level+1) .. ".``")
    else
        UI.bar(L,"career_progress",1,1)
        text(L,"`3LEVEL MAKSIMAL`` - seluruh level telah terbuka.")
    end
    if data.config.enabled~=1 then text(L,"`oKarir sedang dijeda Founder. Progress kamu tetap tersimpan.``")
    elseif not data.source.ready then text(L,"`oBelum tersambung di server ini. Progress kamu tetap tersimpan.``") end
    if data.held then text(L,"`oAda reward yang perlu diperiksa Founder sebelum klaim berikutnya.``") end
end
function UI.home(p)
    local L=begin("12 CAREERS")
    text(L,"`oJalani aktivitas favoritmu. Kembangkan karir. Kumpulkan reward.``")
    local rows,mastered,active={},0,0
    -- Keep one data snapshot per career so captions cannot mix configurations.
    local totalLevel=0
    for _,meta in ipairs(CAREERS) do
        local data=careerData(p,meta.id)
        rows[#rows+1]=data; totalLevel=totalLevel+data.level
        if data.level>=MAX_LEVEL then mastered=mastered+1 end
        if data.config.enabled==1 and data.source.ready then active=active+1 end
    end
    text(L,"Total level: `w" .. totalLevel .. " / " .. (#CAREERS*MAX_LEVEL) .. "``  /  Karir maksimum: " .. mastered)
    text(L,"`o" .. #CAREERS .. " karir  /  " .. active .. " aktif  /  Maksimal Level " .. MAX_LEVEL .. " per karir``")
    UI.section(L,"PILIH KARIR")
    for _,data in ipairs(rows) do
        local caption="`3" .. clean(data.meta.name,26) .. "``  -  Level " .. data.level .. "/" .. MAX_LEVEL
        if data.config.enabled~=1 then caption=caption .. "  (`oDijeda``)"
        elseif not data.source.ready then caption=caption .. "  (`oMenunggu``)"
        elseif data.level>=MAX_LEVEL then caption=caption .. "  (`2MAX``)" end
        button(L,"open_" .. data.meta.id,caption)
    end
    UI.line(L,"add_spacer|small|")
    button(L,"help","Cara Bermain"); button(L,"refresh","Refresh")
    show(p,L,{view="home"})
end
function UI.career(p,id)
    local data=careerData(p,id)
    local L=begin(string.upper(data.meta.name),data.meta.icon)
    UI.line(L,"add_textbox|`o" .. clean(data.meta.summary,220) .. "``|left|")
    UI.summary(L,data)
    local available,claimed=0,0
    for _,row in ipairs(tierRows(p,id)) do
        if row.status=="ready" then available=available+1 elseif row.status=="claimed" then claimed=claimed+1 end
    end
    UI.section(L,"REWARD LEVELING")
    text(L,"Siap klaim: `w" .. available .. "``  /  Diklaim: " .. claimed .. " / " .. MAX_LEVEL)
    text(L,"`oSetiap hadiah diklaim satu kali. Inventory penuh memakai Extra Backpack.``")
    button(L,"rewards","Lihat Reward" .. (available>0 and (" (" .. available .. " siap)") or ""))
    button(L,"guide","Panduan " .. clean(data.meta.name,26))
    UI.line(L,"add_spacer|small|")
    button(L,"refresh","Refresh"); button(L,"back","Back")
    show(p,L,{view="career",career=id})
end
function UI.guide(p,id)
    local data=careerData(p,id)
    local L=begin("PANDUAN " .. string.upper(data.meta.name),data.meta.icon)
    UI.line(L,"add_textbox|`o" .. clean(data.meta.summary,220) .. "``|left|")
    UI.section(L,"CARA MENDAPATKAN XP")
    for n,entry in ipairs(data.meta.guide or {}) do
        if n<=4 then UI.line(L,"add_textbox|" .. n .. ". " .. clean(entry,240) .. "|left|") end
    end
    text(L,"Aktivitas valid memberi `w+" .. fmt(data.config.xp_per_event) .. " XP`` otomatis.")
    if data.config.enabled~=1 then text(L,"`oKarir sedang dijeda Founder; aktivitas belum memberi XP.``")
    elseif not data.source.ready then text(L,"`oBelum tersambung di server ini; aktivitas belum memberi XP.``") end
    UI.section(L,"LEVEL & REWARD")
    UI.line(L,"add_textbox|`oXP setiap karir terpisah dan tersimpan setelah restart. Level 1 terbuka pada " .. fmt(threshold(1)) .. " XP; Level " .. MAX_LEVEL .. " pada " .. fmt(threshold(MAX_LEVEL)) .. " XP.``|left|")
    UI.line(L,"add_textbox|`oHadiah yang sudah terbuka diambil lewat Lihat Reward. Setiap hadiah hanya dapat diklaim sekali. Jika inventory penuh, hadiah masuk Extra Backpack.``|left|")
    button(L,"back","Back")
    show(p,L,{view="guide",career=id})
end
function UI.card(L,row)
    UI.line(L,"add_spacer|small|")
    local reward=row.display
    if reward then
        local item=getItem(reward.item)
        local name=item and clean(item:getName(),34) or ("Item #" .. reward.item)
        UI.line(L,"add_label_with_icon|small|`wLevel " .. row.level .. "`` - " .. name .. "|left|" .. reward.item .. "|")
        text(L,"`oReward: x" .. fmt(reward.amount) .. "  /  " .. fmt(threshold(row.level)) .. " XP``")
    else
        UI.line(L,"add_label|small|`wLevel " .. row.level .. "``  /  " .. fmt(threshold(row.level)) .. " XP|left|")
    end
    local captions={
        claimed="`2SUDAH DIKLAIM``",
        pending="`4PENDING`` - perlu diperiksa Founder.",
        empty="`oReward belum disiapkan Founder.``",
        missing="`oItem tidak tersedia. Hubungi Founder.``",
        locked="`oTERKUNCI`` - selesaikan aktivitas untuk naik level.",
        paused="`oKarir sedang dijeda Founder.``",
        waiting="`oBelum tersambung di server ini.``",
        held="`oMenunggu pemeriksaan klaim sebelumnya.``",
        ready="`3SIAP DIKLAIM``",
    }
    text(L,captions[row.status] or "`oReward tidak tersedia.``")
end
function UI.rewards(p,id,page)
    page=page==2 and 2 or 1
    local data=careerData(p,id)
    local first=(page-1)*5+1; local last=math.min(page*5,MAX_LEVEL)
    local L=begin(string.upper(data.meta.name) .. " REWARDS",data.meta.icon)
    text(L,"Level " .. first .. "-" .. last .. "  /  Halaman " .. page .. "/2  /  Level kamu: `w" .. data.level .. "``")
    text(L,"`oKlaim satu kali per level. Hadiah penuh masuk Extra Backpack.``")
    local rows=tierRows(p,id)
    for n=first,last do
        UI.card(L,rows[n])
        if rows[n].status=="ready" then button(L,"claim_" .. n,"Claim Level " .. n) end
    end
    UI.line(L,"add_spacer|small|")
    if page>1 then button(L,"previous","Level 1-5") end
    if page<2 then button(L,"next","Level 6-10") end
    button(L,"back","Back")
    show(p,L,{view="rewards",career=id,page=page})
end
function UI.help(p)
    local L=begin("12 CAREERS - CARA BERMAIN")
    for _,entry in ipairs({
        {"1. PILIH AKTIVITAS","Ada 12 karir dengan XP terpisah. Pilih karir untuk melihat aktivitas yang dihitung dan panduan lengkapnya."},
        {"2. DAPATKAN XP","Aktivitas yang valid memberi XP otomatis. Jumlah XP per aktivitas mengikuti pengaturan Founder."},
        {"3. NAIK LEVEL","Level 1 membutuhkan " .. fmt(threshold(1)) .. " XP. Kebutuhan tiap level meningkat sampai Level " .. MAX_LEVEL .. " (" .. fmt(threshold(MAX_LEVEL)) .. " XP total)."},
        {"4. AMBIL HADIAH","Buka karir > Lihat Reward. Hadiah siap klaim hanya dapat diambil sekali. Inventory penuh memakai Extra Backpack."},
        {"5. PROGRESS TERSIMPAN","XP dan hadiah yang sudah diklaim tetap tersimpan setelah restart. Karir yang dijeda tetap menyimpan progress kamu."},
    }) do
        UI.section(L,entry[1]); UI.line(L,"add_textbox|`o" .. entry[2] .. "``|left|")
    end
    button(L,"back","Back"); show(p,L,{view="help"})
end
function UI.admin(p)
    assert(founder(p),"Panel ini khusus Founder.")
    local L=begin("12 CAREERS SETTINGS")
    text(L,"`oFOUNDER PANEL  /  Status, XP, dan reward tiap karir``")
    text(L,"Pilih karir untuk mengatur fitur dan hadiah Level 1-10.")
    UI.section(L,"PENGATURAN KARIR")
    for _,meta in ipairs(CAREERS) do
        local data=careerData(p,meta.id)
        button(L,"admin_" .. meta.id,clean(meta.name,26) .. "  -  " .. UI.status(data))
    end
    UI.line(L,"add_spacer|small|"); button(L,"refresh","Refresh")
    show(p,L,{view="admin"})
end
function UI.manage(p,id)
    assert(founder(p),"Panel ini khusus Founder.")
    local data=careerData(p,id)
    local L=begin("SET " .. string.upper(data.meta.name),data.meta.icon)
    text(L,"`oFOUNDER PANEL``")
    text(L,"Status: `w" .. UI.status(data) .. "``  /  XP per aktivitas: " .. fmt(data.config.xp_per_event))
    UI.line(L,"add_textbox|`oSumber aktivitas: " .. clean(data.source.label,220) .. "``|left|")
    local configured=0
    for n=1,MAX_LEVEL do if rewardConfig(id,n) then configured=configured+1 end end
    text(L,"Reward diatur: " .. configured .. " / " .. MAX_LEVEL)
    text(L,"`oMengubah pengaturan tidak menghapus XP atau hadiah yang sudah diklaim.``")
    UI.section(L,"KONTROL KARIR")
    button(L,"toggle",data.config.enabled==1 and "Pause Career" or "Enable Career")
    button(L,"xp","Set XP per Aktivitas")
    UI.section(L,"REWARD LEVELING")
    button(L,"rewards_1","Set Reward - Level 1-5")
    button(L,"rewards_2","Set Reward - Level 6-10")
    UI.line(L,"add_spacer|small|"); button(L,"back","Back")
    show(p,L,{view="manage",career=id,revision=data.config.revision})
end
function UI.xpForm(p,id)
    assert(founder(p),"Panel ini khusus Founder.")
    local data=careerData(p,id)
    local L=begin("SET XP - " .. string.upper(data.meta.name),data.meta.icon)
    text(L,"XP diberikan otomatis setiap satu aktivitas valid.")
    text(L,"`oMengubah XP tidak mengubah progress yang sudah tersimpan.``")
    UI.line(L,"add_text_input|xp_value|XP per Aktivitas :|" .. data.config.xp_per_event .. "|10|")
    UI.line(L,"add_spacer|small|"); button(L,"save","Save XP"); button(L,"back","Back")
    show(p,L,{view="xp",career=id,revision=data.config.revision})
end
function UI.rewardForm(p,id,page)
    assert(founder(p),"Panel ini khusus Founder.")
    page=page==2 and 2 or 1
    local data=careerData(p,id)
    local first=(page-1)*5+1; local last=math.min(page*5,MAX_LEVEL)
    local L=begin("SET REWARD - " .. string.upper(data.meta.name),data.meta.icon)
    text(L,"Level " .. first .. "-" .. last .. "  /  Halaman " .. page .. "/2")
    text(L,"`oItemID 0 dan Amount 0 untuk mengosongkan reward.``")
    text(L,"`oHadiah yang sudah diklaim tetap tercatat sesuai item saat klaim.``")
    for n=first,last do
        local reward=rewardConfig(id,n)
        UI.section(L,"LEVEL " .. n .. "  /  " .. fmt(threshold(n)) .. " XP")
        if reward then
            local item=getItem(reward.item)
            if item then UI.line(L,"add_label_with_icon|small|`o" .. clean(item:getName(),34) .. " x" .. fmt(reward.amount) .. "``|left|" .. reward.item .. "|") end
        end
        UI.line(L,"add_text_input|item_" .. n .. "|ItemID :|" .. (reward and reward.item or 0) .. "|10|")
        UI.line(L,"add_text_input|amount_" .. n .. "|Amount :|" .. (reward and reward.amount or 0) .. "|10|")
    end
    UI.line(L,"add_spacer|small|"); button(L,"save","Save Reward"); button(L,"back","Back")
    show(p,L,{view="reward_form",career=id,page=page,revision=data.config.revision})
end


local function command(_,p,full)
    if _G.Career12~=API then return false end
    if type(full)~="string" then return false end
    local name=full:match("^%s*/?(%S+)")
    name=name and name:lower()
    if name~="career" and name~="12career" and name~="setcareer" then return false end
    guard(p,function()
        if name=="setcareer" then assert(founder(p),"Perintah /setcareer khusus Founder."); UI.admin(p)
        else UI.home(p) end
    end)
    return true
end
local function dialog(_,p,data)
    if _G.Career12~=API then return false end
    if type(data)~="table" or type(data.dialog_name)~="string" or not data.dialog_name:match("^career12_") then return false end
    guard(p,function()
        local account=uid(p)
        local state=sessions[account]
        local matches=state and state.name==data.dialog_name
        local clicked=data.buttonClicked
        if data.quit=="1" or data.quit==1 or clicked==nil or clicked=="" or clicked=="cancel" or clicked=="Tutup" then
            if matches then sessions[account]=nil end
            return
        end
        if state and not matches then tell(p,"`oGunakan menu karir yang terbaru.``"); return end
        if not matches or os.time()>=state.expires then
            sessions[account]=nil; UI.home(p); return
        end
        if not state.buttons[clicked] then return end
        sessions[account]=nil -- Consume before any side effects; packets cannot replay.
        local view,id=state.view,state.career
        if view=="admin" or view=="manage" or view=="xp" or view=="reward_form" then
            assert(founder(p),"Panel ini khusus Founder.")
        end
        if id and settings(id).revision~=state.revision then
            tell(p,"`oPengaturan berubah. Menu diperbarui; periksa sebelum melanjutkan.``")
            if view=="manage" then UI.manage(p,id)
            elseif view=="xp" then UI.xpForm(p,id)
            elseif view=="reward_form" then UI.rewardForm(p,id,state.page)
            elseif view=="rewards" then UI.rewards(p,id,state.page)
            elseif view=="guide" then UI.guide(p,id)
            else UI.career(p,id) end
            return
        end
        if view=="home" then
            if clicked=="refresh" then UI.home(p)
            elseif clicked=="help" then UI.help(p)
            else local chosen=clicked:match("^open_(.+)$"); if byID[chosen] then UI.career(p,chosen) end end
        elseif view=="career" then
            if clicked=="back" then UI.home(p)
            elseif clicked=="refresh" then UI.career(p,id)
            elseif clicked=="guide" then UI.guide(p,id)
            elseif clicked=="rewards" then UI.rewards(p,id,1) end
        elseif (view=="guide" or view=="rewards") and clicked=="back" then UI.career(p,id)
        elseif view=="help" and clicked=="back" then UI.home(p)
        elseif view=="rewards" then
            if clicked=="next" then UI.rewards(p,id,2)
            elseif clicked=="previous" then UI.rewards(p,id,1)
            else local n=tonumber(clicked:match("^claim_(%d+)$")); if n then claim(p,id,n,state) end end
        elseif view=="admin" then
            if clicked=="refresh" then UI.admin(p)
            else local chosen=clicked:match("^admin_(.+)$"); if byID[chosen] then UI.manage(p,chosen) end end
        elseif view=="manage" then
            if clicked=="back" then UI.admin(p)
            elseif clicked=="toggle" then toggle(p,id,state)
            elseif clicked=="xp" then UI.xpForm(p,id)
            elseif clicked=="rewards_1" then UI.rewardForm(p,id,1)
            elseif clicked=="rewards_2" then UI.rewardForm(p,id,2) end
        elseif view=="xp" then
            if clicked=="back" then UI.manage(p,id) elseif clicked=="save" then setXP(p,id,data.xp_value,state) end
        elseif view=="reward_form" then
            if clicked=="back" then UI.manage(p,id) elseif clicked=="save" then setRewards(p,id,data,state) end
        end
    end)
    return true
end
local function install(label,fn,arg)
    if type(fn)~="function" then print("[12career] Missing API: " .. label); return false end
    local ok,result=pcall(fn,arg)
    if not ok or result==false then print("[12career] Registration failed: " .. label .. " / " .. tostring(result)); return false end
    return true
end
local function native(id,label,fn,validate,available)
    local source=sources[id]
    source.mode,source.label="native",label
    if available==false then source.label=label .. " (API pendukung tidak tersedia)"; return end
    source.ready=install(label,fn,function(_,p,...)
        if _G.Career12~=API then return end
        local args={...}
        local count=select("#",...)
        local ok,err=pcall(function()
            if validate(unpack(args,1,count)) then award(p,id) end
        end)
        if not ok then print("[12career] ACTIVITY ERROR " .. id .. " / " .. tostring(err)) end
        -- Advisory callback: never intercept or cancel the underlying activity.
    end)
    if not source.ready then source.label=label .. " (callback tidak tersedia)" end
end
local function itemResult(item,amount)
    return integer(item,1,MAX_AMOUNT) and integer(amount,1,MAX_AMOUNT) and getItem(item)~=nil
end
local function cooked(item,amount,accuracy)
    if not itemResult(item,amount) or type(accuracy)~="number" or accuracy~=accuracy or accuracy<0 or accuracy>100 then return false end
    local recipes=getCookingRecipes()
    if type(recipes)~="table" then return false end
    local minimum
    for _,recipe in pairs(recipes) do
        if type(recipe)=="table" and recipe.result==item then
            local required=recipe.minAccuracy
            if required==nil then required=25 end
            if type(required)~="number" or required~=required or required<0 or required>100 then return false end
            minimum=math.max(minimum or 0,required)
        end
    end
    return minimum~=nil and accuracy>=minimum
end

function API.connect(id,label)
    if _G.Career12~=API or not ready then return false,"unavailable" end
    if not byID[id] or sources[id].mode~="bridge" then return false,"unsupported_career" end
    if type(label)~="string" or label:match("^%s*$") or #label>120 then return false,"invalid_label" end
    sources[id].ready,sources[id].label=true,clean(label,120)
    print("[12career] CONNECTED " .. id .. " | " .. sources[id].label)
    return true,"connected"
end
function API.disconnect(id)
    if _G.Career12~=API or not ready then return false,"unavailable" end
    if not byID[id] or sources[id].mode~="bridge" then return false,"unsupported_career" end
    sources[id].ready=false
    sources[id].label="Perlu integrasi sukses " .. byID[id].name .. " melalui Career12."
    return true,"disconnected"
end
function API.complete(p,id,receipt)
    if _G.Career12~=API or not ready then return false,"unavailable" end
    if not byID[id] or sources[id].mode~="bridge" then return false,"unsupported_career" end
    if type(receipt)~="string" or #receipt<1 or #receipt>96 or not receipt:match("^[%w_:%-%.]+$") then return false,"invalid_receipt" end
    local ok,accepted,reason=pcall(award,p,id,receipt)
    if not ok then print("[12career] BRIDGE ERROR " .. id .. " / " .. tostring(accepted)); return false,"invalid_activity" end
    return accepted,reason
end
function API.getProgress(p,id)
    if _G.Career12~=API or not ready or not realPlayer(p) or not byID[id] then return nil end
    local row=progress(uid(p),id)
    return {xp=row.xp,activities=row.activities,level=level(row.xp),maxLevel=MAX_LEVEL,enabled=settings(id).enabled==1,connected=sources[id].ready}
end

print("[12career] BOOT " .. VERSION .. " | " .. tostring(_VERSION))
local commandOK=install("command",onPlayerCommandCallback,command)
local dialogOK=install("dialog",onPlayerDialogCallback,dialog)
local registered=true
for _,spec in ipairs({{name="career",role=0},{name="12career",role=0},{name="setcareer",role=1000}}) do
    local name=spec.name
    local ok=install("/" .. name,registerLuaCommand,{command=name,roleRequired=spec.role,exactRole=spec.role==1000,
        description=spec.role==1000 and "Founder: atur status, XP, dan reward 12 karir." or "Panduan, XP, dan reward 12 karir.",
        callback=function(p,args) return command(nil,p,name .. " " .. (args or "")) end})
    registered=ok and registered
end
install("disconnect",onPlayerDisconnectCallback,function(p) if _G.Career12==API and p then sessions[uid(p)]=nil end end)
ready,initError=pcall(function()
    assert((registered or commandOK) and dialogOK,"API command/dialog tidak tersedia.")
    assert(type(getItem)=="function","API item tidak tersedia.")
    assert(type(sqlite)=="table" and type(sqlite.open)=="function","SQLite tidak tersedia.")
    db=assert(sqlite.open(DB_FILE),"Database karir tidak dapat dibuka.")
    query("PRAGMA synchronous=FULL")
    query("CREATE TABLE IF NOT EXISTS c12_careers(id TEXT PRIMARY KEY,enabled INTEGER NOT NULL CHECK(enabled IN (0,1)),xp_per_event INTEGER NOT NULL CHECK(xp_per_event BETWEEN 1 AND 1000000),revision INTEGER NOT NULL CHECK(revision>=0))")
    query("CREATE TABLE IF NOT EXISTS c12_progress(uid INTEGER NOT NULL,career TEXT NOT NULL,xp INTEGER NOT NULL CHECK(xp BETWEEN 0 AND 2000000000),activities INTEGER NOT NULL CHECK(activities BETWEEN 0 AND 2000000000),updated_at INTEGER NOT NULL,PRIMARY KEY(uid,career))")
    query("CREATE TABLE IF NOT EXISTS c12_rewards(career TEXT NOT NULL,level INTEGER NOT NULL CHECK(level BETWEEN 1 AND 10),item INTEGER NOT NULL CHECK(item>0),amount INTEGER NOT NULL CHECK(amount BETWEEN 1 AND 2000000000),PRIMARY KEY(career,level))")
    query("CREATE TABLE IF NOT EXISTS c12_claims(id INTEGER PRIMARY KEY AUTOINCREMENT,uid INTEGER NOT NULL,career TEXT NOT NULL,level INTEGER NOT NULL CHECK(level BETWEEN 1 AND 10),item INTEGER NOT NULL,amount INTEGER NOT NULL,state TEXT NOT NULL CHECK(state IN ('pending','claimed','cancelled')),before_inv INTEGER NOT NULL,before_extra INTEGER NOT NULL,after_inv INTEGER,after_extra INTEGER,at INTEGER NOT NULL,finished_at INTEGER,note TEXT NOT NULL DEFAULT '',UNIQUE(uid,career,level))")
    query("CREATE UNIQUE INDEX IF NOT EXISTS c12_pending ON c12_claims(uid) WHERE state='pending'")
    query("CREATE TABLE IF NOT EXISTS c12_receipts(uid INTEGER NOT NULL,career TEXT NOT NULL,receipt TEXT NOT NULL,at INTEGER NOT NULL,PRIMARY KEY(uid,career,receipt))")
    query("CREATE TABLE IF NOT EXISTS c12_runtime(id INTEGER PRIMARY KEY CHECK(id=1),generation INTEGER NOT NULL)")
    query("CREATE TABLE IF NOT EXISTS c12_log(id INTEGER PRIMARY KEY AUTOINCREMENT,actor INTEGER NOT NULL,event TEXT NOT NULL,career TEXT NOT NULL,detail TEXT NOT NULL,at INTEGER NOT NULL)")
    generation=tx(function()
        for _,meta in ipairs(CAREERS) do
            query("INSERT OR IGNORE INTO c12_careers(id,enabled,xp_per_event,revision) VALUES(" .. sql(meta.id) .. ",1," .. meta.defaultXP .. ",0)")
            settings(meta.id)
        end
        query("INSERT OR IGNORE INTO c12_runtime(id,generation) VALUES(1,0)")
        query("UPDATE c12_runtime SET generation=generation+1 WHERE id=1")
        return assert(integer(tonumber(query("SELECT generation FROM c12_runtime WHERE id=1")[1].generation),1,MAX_ID),"Generasi dialog tidak valid.")
    end)
end)
_G.Career12=API
if ready then
    native("surgeon","onPlayerSurgeryCallback",onPlayerSurgeryCallback,itemResult)
    native("angler","onPlayerCatchFishCallback",onPlayerCatchFishCallback,function(item,weight)
        return integer(item,1,MAX_AMOUNT) and getItem(item)~=nil and type(weight)=="number" and weight==weight and weight>0 and weight<math.huge
    end)
    native("trainer","onPlayerTrainFishCallback (Fish Tank)",onPlayerTrainFishCallback,function() return true end)
    native("cooking","onPlayerCookingCallback + akurasi resep",onPlayerCookingCallback,cooked,type(getCookingRecipes)=="function")
    native("ghost","onPlayerCatchGhostCallback",onPlayerCatchGhostCallback,itemResult)
    native("farmer","onPlayerHarvestCallback (1 pohon)",onPlayerHarvestCallback,function(_,amount) return integer(amount,1,MAX_AMOUNT)~=nil end)
    native("firefighter","onPlayerPutOutFireCallback",onPlayerPutOutFireCallback,function() return true end)
    native("provider","onPlayerProviderCallback (pemilik)",onPlayerProviderCallback,function(_,item,amount) return itemResult(item,amount) end)
end
local active=0
for _,source in pairs(sources) do if source.ready then active=active+1 end end
print("[12career] ROUTES registered=" .. tostring(registered) .. " command=" .. tostring(commandOK) .. " dialog=" .. tostring(dialogOK))
print(ready and ("[12career] Loaded /career /12career /setcareer | " .. active .. "/12 sources connected | database " .. DB_FILE)
    or ("[12career] INIT FAILED: " .. tostring(initError)))
return API
