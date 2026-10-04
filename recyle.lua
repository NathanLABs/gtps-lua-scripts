-- Developer: Nathan
-- recyle.lua - Event lock recycling, persistent SQLite claims.
-- Upload this file only. No native mailbox API is assumed: claims live in /re.
local DB_FILE, VERSION = "recycle_lock_v1.db", "v1"
local MAX_AMOUNT, MAX_POINTS, PAGE_SIZE = 2000000000, 9000000000000, 5
local DEFAULT_LOCKS = {{242,1},{1796,100},{7188,10000},{8470,1000000}}
local db,ready,initError,generation
local serial,sessions,busy=0,{},{}
local UI={}
local function number(n) return string.format("%.0f",n) end
local function integer(v,lo,hi)
    if type(v)=="string" and not v:match("^%d+$") then return nil end
    local n=tonumber(v)
    return n and n==n and n>=lo and n<=hi and n==math.floor(n) and n or nil
end
local function clean(v,max) return tostring(v or ""):gsub("`.",""):gsub("[|%c]"," "):sub(1,max or 40) end
local function sql(v) return "'"..tostring(v):gsub("%z",""):gsub("'","''").."'" end
local function fmt(v) return number(v):reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","") end
local function quantity(raw,hi)
    local s=tostring(raw or ""):match("^%s*(.-)%s*$")
    if s:find(",",1,true) then
        local head,tail=s:match("^(%d%d?%d?),(.*)$")
        if not head then return nil end
        for part in (tail..","):gmatch("(.-),") do if not part:match("^%d%d%d$") then return nil end end
        s=head..tail:gsub(",","")
    end
    return integer(s,1,hi)
end
local function q(s) return assert(db:query(s),"Database recycle gagal diakses.") end
local function tx(fn)
    q("BEGIN IMMEDIATE")
    local ok,result=pcall(fn)
    if ok then ok,result=pcall(function() q("COMMIT"); return result end) end
    if not ok then pcall(function() q("ROLLBACK") end); error(result) end
    return result
end
local function uid(p) return assert(integer(p:getUserID(),1,MAX_AMOUNT),"ID akun tidak valid.") end
local function founder(p) return p and p:isOnline() and p:getRole()==1000 end
local function tell(p,s) p:onConsoleMessage("`6[Recycle Lock]`` "..s) end
local function itemName(item) local it=getItem(item); return it and clean(it:getName(),36) or ("Item #"..item) end
local function cfg(k) return assert(q("SELECT value FROM re_config WHERE key="..sql(k))[1],"Konfigurasi tidak ditemukan.").value end
local function bump() q("UPDATE re_config SET value=value+1 WHERE key='revision'") end
local function season() return assert(q("SELECT * FROM re_seasons WHERE id="..cfg("season"))[1],"Musim tidak ditemukan.") end
local function touch(p)
    local id=uid(p); local name=clean(p:getName(),32)
    q("INSERT OR IGNORE INTO re_players(uid,name) VALUES("..id..","..sql(name)..")")
    q("UPDATE re_players SET name="..sql(name).." WHERE uid="..id)
end
local function log(actor,event,ref,detail)
    q("INSERT INTO re_log(actor,event,ref,detail,at) VALUES("..actor..","..sql(event)..","..(ref or 0)..","..sql(clean(detail,220))..","..os.time()..")")
end
local function points(s,id)
    local row=q("SELECT points FROM re_scores WHERE season="..s.." AND uid="..id)[1]
    return row and row.points or 0
end
local function held(id) return q("SELECT id FROM re_moves WHERE uid="..id.." AND status='pending' LIMIT 1")[1] end
local function available(id) assert(not held(id),"Transaksi sebelumnya belum pasti. Hubungi Founder; jangan mengulang pemberian item.") end
local function standings(s)
    if s.awarded_at>0 then return q("SELECT uid,name,points FROM re_awards WHERE season="..s.id.." ORDER BY rank") end
    return q("SELECT a.uid,p.name,a.points FROM re_scores a JOIN re_players p ON p.uid=a.uid WHERE a.season="..s.id.." AND a.points>0 ORDER BY a.points DESC,a.last_move ASC,a.uid ASC LIMIT 10")
end
local function initialize()
    db=assert(sqlite.open(DB_FILE),"SQLite recycle tidak tersedia.")
    q("PRAGMA synchronous=FULL")
    q("CREATE TABLE IF NOT EXISTS re_config(key TEXT PRIMARY KEY,value INTEGER NOT NULL)")
    q("CREATE TABLE IF NOT EXISTS re_players(uid INTEGER PRIMARY KEY,name TEXT NOT NULL)")
    q("CREATE TABLE IF NOT EXISTS re_seasons(id INTEGER PRIMARY KEY AUTOINCREMENT,state TEXT NOT NULL,created_at INTEGER NOT NULL,awarded_at INTEGER NOT NULL DEFAULT 0,ended_at INTEGER NOT NULL DEFAULT 0)")
    q("CREATE TABLE IF NOT EXISTS re_locks(item INTEGER PRIMARY KEY,value INTEGER NOT NULL CHECK(value>0),enabled INTEGER NOT NULL)")
    q("CREATE TABLE IF NOT EXISTS re_rewards(rank INTEGER NOT NULL CHECK(rank BETWEEN 1 AND 10),item INTEGER NOT NULL,amount INTEGER NOT NULL CHECK(amount>0),PRIMARY KEY(rank,item))")
    q("CREATE TABLE IF NOT EXISTS re_scores(season INTEGER NOT NULL,uid INTEGER NOT NULL,points INTEGER NOT NULL CHECK(points>=0),last_move INTEGER NOT NULL,PRIMARY KEY(season,uid))")
    q("CREATE TABLE IF NOT EXISTS re_awards(season INTEGER NOT NULL,rank INTEGER NOT NULL,uid INTEGER NOT NULL,name TEXT NOT NULL,points INTEGER NOT NULL,PRIMARY KEY(season,rank),UNIQUE(season,uid))")
    q("CREATE TABLE IF NOT EXISTS re_claims(id INTEGER PRIMARY KEY AUTOINCREMENT,season INTEGER NOT NULL,rank INTEGER NOT NULL,uid INTEGER NOT NULL,item INTEGER NOT NULL,amount INTEGER NOT NULL,state TEXT NOT NULL,UNIQUE(season,rank,item))")
    q("CREATE TABLE IF NOT EXISTS re_moves(id INTEGER PRIMARY KEY AUTOINCREMENT,season INTEGER NOT NULL,uid INTEGER NOT NULL,kind TEXT NOT NULL,item INTEGER NOT NULL,amount INTEGER NOT NULL,points INTEGER NOT NULL,source TEXT NOT NULL,claim INTEGER NOT NULL DEFAULT 0,status TEXT NOT NULL,before_inv INTEGER NOT NULL,before_extra INTEGER NOT NULL,after_inv INTEGER,after_extra INTEGER,at INTEGER NOT NULL)")
    q("CREATE TABLE IF NOT EXISTS re_log(id INTEGER PRIMARY KEY AUTOINCREMENT,actor INTEGER NOT NULL,event TEXT NOT NULL,ref INTEGER NOT NULL,detail TEXT NOT NULL,at INTEGER NOT NULL)")
    q("CREATE INDEX IF NOT EXISTS re_top ON re_scores(season,points DESC,last_move,uid)")
    q("CREATE INDEX IF NOT EXISTS re_claim_owner ON re_claims(uid,state,id)")
    q("CREATE INDEX IF NOT EXISTS re_pending ON re_moves(uid,status)")
    q("CREATE INDEX IF NOT EXISTS re_season_moves ON re_moves(season,kind,status)")
    tx(function()
        q("INSERT OR IGNORE INTO re_config(key,value) VALUES('generation',0)")
        q("INSERT OR IGNORE INTO re_config(key,value) VALUES('revision',0)")
        if not q("SELECT value FROM re_config WHERE key='season'")[1] then
            q("INSERT INTO re_seasons(state,created_at) VALUES('open',"..os.time()..")")
            q("INSERT INTO re_config(key,value) VALUES('season',"..q("SELECT last_insert_rowid() AS id")[1].id..")")
        end
        for _,l in ipairs(DEFAULT_LOCKS) do
            if getItem(l[1]) then q("INSERT OR IGNORE INTO re_locks(item,value,enabled) VALUES("..l[1]..","..l[2]..",1)") end
        end
        q("UPDATE re_config SET value=value+1 WHERE key='generation'")
        generation=cfg("generation")
    end)
    season()
end
local function quote(p,item,raw,source)
    available(uid(p))
    local s=season(); assert(s.state=="open","Musim sudah selesai. Tunggu musim baru.")
    local l=assert(q("SELECT * FROM re_locks WHERE item="..item.." AND enabled=1")[1],"Lock tidak aktif.")
    assert(getItem(item),"Item lock tidak tersedia di server.")
    assert(source=="inventory" or source=="extra","Sumber lock tidak valid.")
    local stock=source=="extra" and p:getExtraBackpackAmount(item) or p:getItemAmount(item)
    local rawText=tostring(raw or ""):lower():match("^%s*(.-)%s*$")
    local count=assert(quantity((rawText=="all" or rawText=="max") and number(stock) or raw,MAX_AMOUNT),"Jumlah lock harus bulat positif, atau all/max.")
    assert(stock>=count,"Jumlah lock di sumber yang dipilih tidak cukup.")
    assert(count<=math.floor((MAX_POINTS-points(s.id,uid(p)))/l.value),"Total poin melewati batas event.")
    return {season=s.id,uid=uid(p),item=item,count=count,value=l.value,points=count*l.value,source=source,revision=cfg("revision")}
end
-- Inventory and SQLite do not share an atomic commit. Persist intent first;
-- ambiguous outcomes remain pending and are never retried automatically.
local function move(p,op)
    available(uid(p))
    local inv=assert(integer(p:getItemAmount(op.item),0,MAX_AMOUNT),"Inventory tidak valid.")
    local extra=assert(integer(p:getExtraBackpackAmount(op.item),0,MAX_AMOUNT),"Extra Backpack tidak valid.")
    local key=tx(function()
        available(uid(p))
        if op.kind=="claim" then
            assert(inv+extra+op.count<=MAX_AMOUNT,"Ruang inventory/Extra Backpack tidak cukup.")
            local c=assert(q("SELECT * FROM re_claims WHERE id="..op.claim.." AND uid="..uid(p).." AND state='ready'")[1],"Hadiah tidak tersedia.")
            assert(c.item==op.item and c.amount==op.count,"Hadiah berubah.")
            q("UPDATE re_claims SET state='pending' WHERE id="..op.claim)
        else
            assert(season().id==op.season and season().state=="open" and cfg("revision")==op.revision,"Musim/pengaturan berubah. Buka konfirmasi terbaru.")
            assert(points(op.season,uid(p))+op.points<=MAX_POINTS,"Batas poin tercapai.")
        end
        q("INSERT INTO re_moves(season,uid,kind,item,amount,points,source,claim,status,before_inv,before_extra,at) VALUES("
            ..op.season..","..uid(p)..","..sql(op.kind)..","..op.item..","..op.count..","..number(op.points or 0)..","..sql(op.source)..","..(op.claim or 0)..",'pending',"..inv..","..extra..","..os.time()..")")
        return q("SELECT last_insert_rowid() AS id")[1].id
    end)
    local result
    if op.kind=="claim" then result=p:giveItem(op.item,op.count)
    elseif op.source=="extra" then result=p:takeFromExtraBackpack(op.item,op.count)
    else result=p:changeItem(op.item,-op.count) end
    local afterInv,afterExtra=p:getItemAmount(op.item),p:getExtraBackpackAmount(op.item)
    q("UPDATE re_moves SET after_inv="..afterInv..",after_extra="..afterExtra.." WHERE id="..key)
    local rejected=(result==false or result==0) and afterInv==inv and afterExtra==extra
    if rejected then
        tx(function()
            q("UPDATE re_moves SET status='cancelled' WHERE id="..key)
            if op.kind=="claim" then q("UPDATE re_claims SET state='ready' WHERE id="..op.claim) end
        end)
        error("Engine menolak transaksi; inventory tidak berubah. Silakan coba lagi.")
    end
    local exact
    if op.kind=="claim" then exact=result==true and afterInv+afterExtra==inv+extra+op.count
    elseif op.source=="extra" then exact=result==op.count and afterInv==inv and afterExtra==extra-op.count
    else exact=result==true and afterInv==inv-op.count and afterExtra==extra end
    assert(exact,"Hasil transaksi #"..key.." belum pasti. Founder perlu memeriksa jurnal; item tidak diberikan ulang.")
    tx(function()
        assert(q("SELECT status FROM re_moves WHERE id="..key)[1].status=="pending","Transaksi sudah diproses.")
        if op.kind=="claim" then
            assert(q("SELECT state FROM re_claims WHERE id="..op.claim)[1].state=="pending","Status hadiah berubah.")
            q("UPDATE re_claims SET state='claimed' WHERE id="..op.claim)
        else
            assert(points(op.season,uid(p))+op.points<=MAX_POINTS,"Batas poin tercapai.")
            q("INSERT OR IGNORE INTO re_scores(season,uid,points,last_move) VALUES("..op.season..","..uid(p)..",0,0)")
            q("UPDATE re_scores SET points=points+"..number(op.points)..",last_move="..key.." WHERE season="..op.season.." AND uid="..uid(p))
        end
        q("UPDATE re_moves SET status='done' WHERE id="..key)
    end)
end
local function recycle(p,snapshot)
    assert(snapshot.uid==uid(p),"Akun tidak sesuai.")
    local current=quote(p,snapshot.item,number(snapshot.count),snapshot.source)
    assert(snapshot.season==current.season and snapshot.revision==current.revision and snapshot.value==current.value,"Poin/musim berubah. Buka konfirmasi terbaru.")
    current.kind="recycle"; move(p,current)
    tell(p,"`2Berhasil recycle "..fmt(current.count).." "..itemName(current.item)..". +"..fmt(current.points).." poin!")
end
local function claim(p,key)
    local c=assert(q("SELECT * FROM re_claims WHERE id="..key.." AND uid="..uid(p).." AND state='ready'")[1],"Hadiah bukan milikmu atau sudah diambil.")
    assert(getItem(c.item),"Item hadiah belum tersedia di server. Hubungi Founder.")
    move(p,{kind="claim",season=c.season,item=c.item,count=c.amount,claim=c.id,source="both"})
    tell(p,"`2Hadiah "..itemName(c.item).." x"..fmt(c.amount).." berhasil diambil.")
end
local function sendRewards(p)
    assert(founder(p),"Perintah khusus Founder.")
    return tx(function()
        local s=season()
        if s.awarded_at>0 then return {already=true,season=s.id} end
        assert(s.state=="open","Musim tidak aktif.")
        assert(not q("SELECT id FROM re_moves WHERE season="..s.id.." AND kind='recycle' AND status='pending' LIMIT 1")[1],"Ada recycle pending. Rekonsiliasi jurnal terlebih dahulu sebelum menentukan pemenang.")
        local winners=standings(s); assert(#winners>0,"Belum ada peserta dengan poin.")
        local total=0
        for rank,w in ipairs(winners) do
            local rewards=q("SELECT * FROM re_rewards WHERE rank="..rank.." ORDER BY item")
            assert(#rewards>0,"Hadiah rank #"..rank.." belum diatur di /setrecycle.")
            q("INSERT INTO re_awards(season,rank,uid,name,points) VALUES("..s.id..","..rank..","..w.uid..","..sql(w.name)..","..number(w.points)..")")
            for _,r in ipairs(rewards) do
                assert(getItem(r.item) and integer(r.amount,1,MAX_AMOUNT),"Hadiah rank #"..rank.." tidak valid.")
                q("INSERT INTO re_claims(season,rank,uid,item,amount,state) VALUES("..s.id..","..rank..","..w.uid..","..r.item..","..r.amount..",'ready')")
                total=total+1
            end
        end
        q("UPDATE re_seasons SET state='rewarded',awarded_at="..os.time().." WHERE id="..s.id)
        bump(); log(uid(p),"rewards_sent",s.id,#winners.." pemenang / "..total.." hadiah")
        return {season=s.id,winners=#winners,claims=total}
    end)
end
local function resetSeason(p,expected)
    assert(founder(p),"Perintah khusus Founder.")
    return tx(function()
        local s=season(); assert(s.id==expected,"Musim sudah berubah.")
        assert(not q("SELECT id FROM re_moves WHERE season="..s.id.." AND kind='recycle' AND status='pending' LIMIT 1")[1],"Masih ada recycle pending; selesaikan jurnal dahulu.")
        assert(s.awarded_at>0 or #standings(s)==0,"Bagikan hadiah dahulu melalui /sendrewardrecyclelock sebelum reset.")
        q("UPDATE re_seasons SET state='closed',ended_at="..os.time().." WHERE id="..s.id)
        q("INSERT INTO re_seasons(state,created_at) VALUES('open',"..os.time()..")")
        local nextID=q("SELECT last_insert_rowid() AS id")[1].id
        q("UPDATE re_config SET value="..nextID.." WHERE key='season'")
        bump(); log(uid(p),"season_reset",s.id,"Musim baru #"..nextID)
        return nextID
    end)
end

local function text(L,s) L[#L+1]="add_smalltext|"..s.."|\n" end
local function paragraph(L,s) L[#L+1]="add_textbox|"..s.."|left|\n" end
local function space(L) L[#L+1]="add_spacer|small|\n" end
local function button(L,key,s) L[#L+1]="add_button|"..key.."|"..s.."|noflags|0|0|\n" end
local function input(L,key,title,value,len) L[#L+1]="add_text_input|"..key.."|"..title.."|"..clean(value,40).."|"..(len or 20).."|\n" end
local function begin(title,item)
    return {"set_default_color|`w\nset_bg_color|26,34,51,230|\nadd_label_with_icon|big|`w"..title.."``|left|"..(item or 242).."|\nadd_spacer|small|\n"}
end
local function show(p,L,state)
    serial=serial+1; state.name="recycle_lock_"..generation.."_"..serial
    state.expires=os.time()+120; state.revision=cfg("revision"); state.buttons={}
    for _,line in ipairs(L) do local key=line:match("^add_button[^|]*|([^|]+)|"); if key then state.buttons[key]=true end end
    L[#L+1]="add_spacer|small|\nadd_smalltext|`9© Dibuat Oleh : Nathan``|\n"
    L[#L+1]="add_quick_exit|\nend_dialog|"..state.name.."|Close||"
    local packet=table.concat(L); assert(#packet<4096,"Dialog melebihi batas ukuran.")
    sessions[uid(p)]=state; p:onDialogRequest(packet)
end
local function rows(query,page,size)
    size=size or PAGE_SIZE
    local count=q("SELECT COUNT(*) AS n FROM ("..query..")")[1].n
    local pages=math.max(1,math.ceil(count/size)); page=math.max(1,math.min(page or 1,pages))
    return q(query.." LIMIT "..size.." OFFSET "..((page-1)*size)),page,pages
end
local function pages(L,page,max)
    if max>1 then text(L,"Halaman "..page.." / "..max) end
    if page>1 then button(L,"page_"..(page-1),"Sebelumnya") end
    if page<max then button(L,"page_"..(page+1),"Berikutnya") end
end
function UI.top(p)
    local s=season(); local L=begin("TOP 10 RECYCLE LOCK",7188)
    text(L,"Musim #"..s.id.." / "..(s.state=="open" and "`2BERLANGSUNG``" or "`9SELESAI``"))
    text(L,"TOTAL RECYCLE dihitung dalam poin setara WL.")
    local top=standings(s)
    if #top==0 then paragraph(L,"`9Belum ada peserta. Mulai recycle melalui /re.``") end
    for rank,r in ipairs(top) do
        space(L); L[#L+1]="add_label|big|"..(rank==1 and "`9" or "`w").."#"..rank.." "..clean(r.name,32).."``|left|\n"
        text(L,"TOTAL RECYCLE : `2"..fmt(r.points).." poin``")
    end
    show(p,L,{view="top"})
end
function UI.home(p,page)
    local s=season(); local L=begin("Recycle Lock Event",7188)
    text(L,"Musim #"..s.id.." / Poin kamu: `2"..fmt(points(s.id,uid(p))).."``")
    paragraph(L,"Daur ulang lock untuk mengikuti kompetisi Top 10. Lock yang sudah didaur ulang tidak dapat dikembalikan.")
    button(L,"top","`9TOP 10 LEADERBOARD``")
    local count=q("SELECT COUNT(*) AS n FROM re_claims WHERE uid="..uid(p).." AND state='ready'")[1].n
    button(L,"claims","`2Kotak Klaim ("..count..")``")
    if s.state~="open" then paragraph(L,"`9Hadiah musim ini sudah dibagikan. Tunggu musim baru untuk recycle lagi.``")
    else
        space(L); text(L,"`wPILIH LOCK``")
        local list,at,max=rows("SELECT * FROM re_locks WHERE enabled=1 ORDER BY value,item",page)
        if #list==0 then text(L,"Belum ada lock yang diaktifkan Founder.") end
        for _,l in ipairs(list) do
            L[#L+1]="add_label_with_icon|small|`w"..itemName(l.item).."``|left|"..l.item.."|\n"
            text(L,"1 lock = `2"..fmt(l.value).." poin`` / Inventory "..fmt(p:getItemAmount(l.item)).." / Extra "..fmt(p:getExtraBackpackAmount(l.item)))
            button(L,"lock_"..l.item,"Recycle "..itemName(l.item))
        end
        pages(L,at,max)
    end
    show(p,L,{view="home"})
end
function UI.recycleForm(p,item)
    local l=assert(q("SELECT * FROM re_locks WHERE item="..item.." AND enabled=1")[1],"Lock tidak aktif.")
    local L=begin("Recycle "..itemName(item),item)
    text(L,"1 lock = `2"..fmt(l.value).." poin``")
    text(L,"Inventory: "..fmt(p:getItemAmount(item)).." / Extra Backpack: "..fmt(p:getExtraBackpackAmount(item)))
    input(L,"amount","JUMLAH LOCK :","1")
    L[#L+1]="add_checkbox|extra|Ambil dari Extra Backpack|0|\n"
    text(L,"Isi angka bulat atau all/max. Poin dihitung sebelum konfirmasi.")
    button(L,"preview","`2HITUNG POIN``"); button(L,"home","Back")
    show(p,L,{view="recycle_form",item=item})
end
function UI.preview(p,op)
    local L=begin("Konfirmasi Recycle",op.item)
    paragraph(L,"Recycle `9"..fmt(op.count).." "..itemName(op.item).."`` dari "..(op.source=="extra" and "Extra Backpack" or "inventory")..".")
    text(L,"Poin diperoleh: `2"..fmt(op.points).."``")
    text(L,"Total poin setelah recycle: `2"..fmt(points(op.season,uid(p))+op.points).."``")
    paragraph(L,"`9Lock akan dihapus permanen setelah kamu menekan DAUR ULANG.``")
    button(L,"confirm","`2DAUR ULANG``"); button(L,"home","Batal")
    show(p,L,{view="recycle_confirm",quote=op})
end
function UI.claims(p,page)
    local L=begin("Kotak Klaim Recycle",7188)
    local list,at,max=rows("SELECT * FROM re_claims WHERE uid="..uid(p).." AND state IN ('ready','pending') ORDER BY id",page)
    if #list==0 then paragraph(L,"`9Belum ada hadiah yang perlu diambil.``") end
    for _,c in ipairs(list) do
        L[#L+1]="add_label_with_icon|small|`w"..itemName(c.item).." x"..fmt(c.amount).."``|left|"..c.item.."|\n"
        text(L,"Musim #"..c.season.." / Hadiah rank #"..c.rank)
        if c.state=="ready" then button(L,"claim_"..c.id,"`2Ambil Hadiah``") else text(L,"`9Menunggu pemeriksaan Founder.``") end
    end
    pages(L,at,max); button(L,"home","Back"); show(p,L,{view="claims",page=at})
end
function UI.admin(p)
    assert(founder(p),"Panel khusus Founder.")
    local s=season(); local L=begin("Recycle / Founder",7188)
    text(L,"Musim #"..s.id.." / "..s.state)
    button(L,"locks","Lock & Nilai Poin"); button(L,"rewards","Hadiah Rank 1 - 10")
    text(L,"Kirim hadiah: /sendrewardrecyclelock")
    text(L,"Mulai musim baru: /resetleaderboardre")
    show(p,L,{view="admin",admin=true})
end
function UI.locks(p,page)
    local L=begin("Lock & Nilai Poin")
    button(L,"new_lock","`2+ Tambah Custom Lock``")
    local list,at,max=rows("SELECT * FROM re_locks ORDER BY value,item",page)
    for _,l in ipairs(list) do
        text(L,itemName(l.item).." (#"..l.item..") / "..fmt(l.value).." poin / "..(l.enabled==1 and "ON" or "OFF"))
        button(L,"edit_"..l.item,"Edit Lock")
    end
    pages(L,at,max); button(L,"admin","Back"); show(p,L,{view="locks",admin=true})
end
function UI.lockForm(p,item)
    local l=item and assert(q("SELECT * FROM re_locks WHERE item="..item)[1],"Lock tidak ditemukan.")
    local L=begin(l and "Edit Lock" or "Tambah Custom Lock",item)
    if l then text(L,itemName(item).." / ID "..item) else input(L,"item","ITEM ID :","",10) end
    input(L,"value","POIN PER 1 LOCK :",l and number(l.value) or "1")
    L[#L+1]="add_checkbox|enabled|Aktifkan lock ini|"..((not l or l.enabled==1) and "1" or "0").."|\n"
    paragraph(L,"Nilai baru berlaku untuk recycle berikutnya. Poin yang sudah didapat tidak diubah.")
    button(L,"save","Simpan"); button(L,"locks","Back"); show(p,L,{view="lock_form",item=item,admin=true})
end
function UI.rewards(p)
    local L=begin("Hadiah Rank 1 - 10",7188)
    for rank=1,10 do
        local count=q("SELECT COUNT(*) AS n FROM re_rewards WHERE rank="..rank)[1].n
        button(L,"rank_"..rank,"Rank #"..rank.." / "..count.." jenis hadiah")
    end
    text(L,"Maksimal 5 jenis item per rank. Hadiah yang sudah dikirim tidak berubah.")
    button(L,"admin","Back"); show(p,L,{view="rewards",admin=true})
end
function UI.rewardForm(p,rank)
    local L=begin("Hadiah Rank #"..rank,7188)
    local list=q("SELECT * FROM re_rewards WHERE rank="..rank.." ORDER BY item")
    if #list==0 then text(L,"`9Belum ada hadiah.``") end
    for _,r in ipairs(list) do text(L,itemName(r.item).." x"..fmt(r.amount)); button(L,"remove_"..r.item,"Hapus #"..r.item) end
    space(L); input(L,"item","ITEM ID HADIAH :","",10); input(L,"amount","JUMLAH :","1")
    text(L,"Item ID yang sama memperbarui jumlah hadiah.")
    button(L,"save","`2Simpan Hadiah``"); button(L,"rewards","Back"); show(p,L,{view="reward_form",rank=rank,admin=true})
end
function UI.reset(p)
    local s=season(); local L=begin("Mulai Musim Baru?",7188)
    paragraph(L,"Leaderboard musim #"..s.id.." akan diarsipkan. Semua player memulai musim baru dengan 0 poin.")
    text(L,"Hadiah yang belum diklaim tetap bisa diambil lewat /re.")
    text(L,"Jika masih ada peserta, bagikan hadiah sebelum reset.")
    button(L,"confirm","`4RESET LEADERBOARD``"); button(L,"admin","Batal")
    show(p,L,{view="reset",season=s.id,admin=true})
end
local function guard(p,fn)
    if not p or not p:isOnline() then return end
    if not ready then tell(p,"`4Event belum tersedia: "..clean(initError,210)); return end
    local id=uid(p); if busy[id] then return end
    busy[id]=true
    local ok,err=pcall(function() touch(p); fn() end)
    busy[id]=nil
    if not ok then sessions[id]=nil; print("[recyle] uid="..id.." "..tostring(err)); tell(p,"`4"..clean(tostring(err):gsub("^.-:%d+:%s*",""),250)) end
end
local function dialog(world,p,d)
    if type(d)~="table" or type(d.dialog_name)~="string" or not d.dialog_name:match("^recycle_lock_") then return false end
    guard(p,function()
        local state=sessions[uid(p)]; local clicked=tostring(d.buttonClicked or "")
        if d.quit=="1" or d.quit==1 or clicked=="" or clicked=="Close" then
            if state and state.name==d.dialog_name then sessions[uid(p)]=nil end
            return
        end
        if not state or state.name~=d.dialog_name or state.expires<=os.time() then UI.home(p); return end
        if state.admin then assert(founder(p),"Panel khusus Founder.") end
        assert(state.buttons[clicked],"Tombol tidak tersedia pada menu ini.")
        sessions[uid(p)]=nil
        if state.revision~=cfg("revision") then tell(p,"Pengaturan/musim berubah. Menu diperbarui."); if state.admin then UI.admin(p) else UI.home(p) end; return end
        if clicked=="home" then UI.home(p); return end
        if clicked=="top" then UI.top(p); return end
        if clicked=="claims" then UI.claims(p); return end
        if clicked=="admin" then UI.admin(p); return end
        if clicked=="locks" then UI.locks(p); return end
        if clicked=="rewards" then UI.rewards(p); return end
        local page=integer(clicked:match("^page_(%d+)$"),1,MAX_AMOUNT)
        if state.view=="home" then
            if page then UI.home(p,page) else UI.recycleForm(p,assert(integer(clicked:match("^lock_(%d+)$"),1,MAX_AMOUNT))) end
        elseif state.view=="recycle_form" and clicked=="preview" then
            UI.preview(p,quote(p,state.item,d.amount,tostring(d.extra)=="1" and "extra" or "inventory"))
        elseif state.view=="recycle_confirm" and clicked=="confirm" then recycle(p,state.quote); UI.home(p)
        elseif state.view=="claims" then
            if page then UI.claims(p,page) else claim(p,assert(integer(clicked:match("^claim_(%d+)$"),1,MAX_AMOUNT))); UI.claims(p,state.page) end
        elseif state.view=="locks" then
            if page then UI.locks(p,page) elseif clicked=="new_lock" then UI.lockForm(p) else UI.lockForm(p,assert(integer(clicked:match("^edit_(%d+)$"),1,MAX_AMOUNT))) end
        elseif state.view=="lock_form" and clicked=="save" then
            local item=state.item or assert(integer(d.item,1,MAX_AMOUNT),"Item ID tidak valid.")
            local value=assert(quantity(d.value,MAX_POINTS),"Poin per lock harus bulat positif.")
            assert(getItem(item),"Item tidak tersedia di server.")
            tx(function()
                assert(founder(p),"Founder only.")
                if not state.item then assert(not q("SELECT item FROM re_locks WHERE item="..item)[1],"Lock sudah terdaftar. Gunakan Edit Lock.") end
                q("INSERT OR IGNORE INTO re_locks(item,value,enabled) VALUES("..item..","..number(value)..",1)")
                q("UPDATE re_locks SET value="..number(value)..",enabled="..(tostring(d.enabled)=="1" and 1 or 0).." WHERE item="..item)
                bump(); log(uid(p),"lock_saved",item,number(value).." poin")
            end)
            UI.locks(p)
        elseif state.view=="rewards" then UI.rewardForm(p,assert(integer(clicked:match("^rank_(%d+)$"),1,10)))
        elseif state.view=="reward_form" then
            local item=assert(integer(clicked=="save" and d.item or clicked:match("^remove_(%d+)$"),1,MAX_AMOUNT),"Item ID tidak valid.")
            tx(function()
                assert(founder(p),"Founder only.")
                if clicked=="save" then
                    local count=assert(quantity(d.amount,MAX_AMOUNT),"Jumlah hadiah harus bulat positif.")
                    assert(getItem(item),"Item hadiah tidak tersedia.")
                    assert(q("SELECT item FROM re_rewards WHERE rank="..state.rank.." AND item="..item)[1] or q("SELECT COUNT(*) AS n FROM re_rewards WHERE rank="..state.rank)[1].n<5,"Maksimal 5 jenis hadiah per rank.")
                    q("INSERT OR REPLACE INTO re_rewards(rank,item,amount) VALUES("..state.rank..","..item..","..count..")")
                else q("DELETE FROM re_rewards WHERE rank="..state.rank.." AND item="..item) end
                bump(); log(uid(p),"reward_changed",state.rank,"Item #"..item)
            end)
            UI.rewardForm(p,state.rank)
        elseif state.view=="reset" and clicked=="confirm" then
            local nextID=resetSeason(p,state.season); tell(p,"`2Musim #"..nextID.." dimulai. Leaderboard kembali kosong."); UI.admin(p)
        end
    end)
    return true
end
local COMMANDS={
    {name="re",role=0,description="Recycle lock untuk poin event dan klaim hadiah."},
    {name="topevent",role=0,description="Top 10 kompetisi recycle lock."},
    {name="setrecycle",role=1000,description="Founder: nilai lock dan hadiah rank 1-10."},
    {name="sendrewardrecyclelock",role=1000,description="Founder: bagikan hadiah dan akhiri musim recycle."},
    {name="resetleaderboardre",role=1000,description="Founder: mulai musim recycle baru."},
}
local commandRoles={}; for _,c in ipairs(COMMANDS) do commandRoles[c.name]=c.role end
local function command(world,p,full)
    local name=tostring(full):match("^%s*/?(%S+)"); name=name and name:lower()
    if commandRoles[name]==nil then return false end
    if commandRoles[name]==1000 and not founder(p) then if p then tell(p,"`4Perintah khusus Founder.") end; return true end
    guard(p,function()
        if name=="re" then UI.home(p)
        elseif name=="topevent" then UI.top(p)
        elseif name=="setrecycle" then UI.admin(p)
        elseif name=="resetleaderboardre" then UI.reset(p)
        else
            local result=sendRewards(p)
            tell(p,result.already and ("Hadiah musim #"..result.season.." sudah pernah dikirim.") or ("`2Hadiah untuk "..result.winners.." pemenang masuk Kotak Klaim /re. Musim #"..result.season.." selesai."))
        end
    end)
    return true
end
local function install(label,fn,arg)
    if type(fn)~="function" then print("[recyle] API tidak tersedia: "..label); return false end
    local ok,result=pcall(fn,arg)
    if not ok or result==false then print("[recyle] API gagal: "..label.." / "..tostring(result)); return false end
    return true
end
print("[recyle] BOOT "..VERSION.." | "..tostring(_VERSION))
local dialogOK=install("dialog",onPlayerDialogCallback,dialog)
local commandOK=install("command",onPlayerCommandCallback,command)
local inputOK=install("input",onPlayerActionCallback,function(w,p,d)
    if type(d)~="table" or d.action~="input" or type(d.text)~="string" or not d.text:match("^%s*/%S+") then return false end
    return command(w,p,d.text)
end)
local registered=true
for _,c in ipairs(COMMANDS) do
    local name=c.name
    local ok=install("/"..name,registerLuaCommand,{command=name,roleRequired=c.role,exactRole=c.role==1000,description=c.description,callback=function(p) return command(nil,p,name) end})
    registered=ok and registered
end
print("[recyle] ROUTES registered="..tostring(registered).." command="..tostring(commandOK).." input="..tostring(inputOK).." dialog="..tostring(dialogOK))
install("login",onPlayerLoginCallback,function(p)
    if not ready then return end
    guard(p,function()
        local count=q("SELECT COUNT(*) AS n FROM re_claims WHERE uid="..uid(p).." AND state='ready'")[1].n
        if count>0 then tell(p,"`2Ada "..count.." hadiah recycle menunggu. Buka /re > Kotak Klaim.") end
    end)
end)
install("disconnect",onPlayerDisconnectCallback,function(p) if p then sessions[uid(p)],busy[uid(p)]=nil,nil end end)
ready,initError=pcall(function()
    assert(dialogOK and (registered or commandOK or inputOK),"API dialog/command wajib tidak tersedia.")
    initialize()
end)
print(ready and "[recyle] Loaded /re /topevent /setrecycle /sendrewardrecyclelock /resetleaderboardre" or ("[recyle] INIT FAILED: "..tostring(initError)))
