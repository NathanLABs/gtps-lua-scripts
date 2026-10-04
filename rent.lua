-- Developer: Nathan
-- Item Rental / SQLite. Currency is always stored as whole WL.
-- Engine inventory mutations are journaled separately from SQLite transactions.
local COMMAND, ADMIN_COMMAND = "rent", "setrent"
-- REQUIRED integration supplied by the engine owner; this is NOT a built-in API.
-- See rent-README.md. Leave nil until native temporary inventory is available.
local RENTAL_BACKEND = nil
-- Keep the database name and receipt tokens stable when upgrading market.lua.
local DB_FILE = "player_market_v1.db"
local MAX_AMOUNT, MAX_BALANCE, MAX_SLOTS, PAGE_SIZE = 2000000000, 2000000000, 10, 5
local RENT_ICON_ID, GRID_SIZE, GRID_COLUMNS = 13812, 18, 6
local db, ready, generation, initError
local sessions, busy, serial = {}, {}, 0
local function integer(v,lo,hi)
    if type(v)=="string" and not v:match("^%d+$") then return nil end
    local n=tonumber(v)
    return n and n==n and n>=lo and n<=hi and n==math.floor(n) and n or nil
end
local function num(n) return string.format("%.0f",n) end
local function sql(v) return "'"..tostring(v):gsub("%z",""):gsub("'","''").."'" end
local function clean(v,n) return tostring(v or ""):gsub("`.",""):gsub("[|%c]"," "):sub(1,n or 60) end
local function fmt(n) return num(n):reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","") end
local function amount(v,lo,hi)
    local s=tostring(v or ""):match("^%s*(.-)%s*$")
    if s:find(",",1,true) then
        local head,tail=s:match("^(%d%d?%d?),(.*)$")
        if not head then return nil end
        for part in (tail..","):gmatch("(.-),") do if not part:match("^%d%d%d$") then return nil end end
        s=head..tail:gsub(",","")
    end
    return integer(s,lo,hi)
end
local function price(raw)
    local s=tostring(raw or ""):match("^%s*(.-)%s*$")
    local whole,fraction=s:match("^(%d+)%.(%d+)$")
    if not whole then whole=s:match("^%d+$"); fraction="" end
    assert(whole and #whole<=9 and #fraction<=4,"Harga BGL: angka positif, maksimal 4 desimal. Contoh 1 atau 0.5.")
    return assert(integer(tonumber(whole)*10000+tonumber(fraction..string.rep("0",4-#fraction)),1,MAX_BALANCE),"Harga melewati batas.")
end
local function bgl(n) return (string.format("%.4f",n/10000):gsub("0+$",""):gsub("%.$","")) end
local function money(n)
    return fmt(math.floor(n/10000)).." BGL + "..fmt(math.floor(n/100)%100).." DL + "..fmt(n%100).." WL"
end
local function q(query)
    local rows=db:query(query)
    assert(type(rows)=="table","Database market gagal diakses.")
    return rows
end
local function tx(fn)
    q("BEGIN IMMEDIATE")
    local ok,result=pcall(fn)
    if ok then ok,result=pcall(function() q("COMMIT"); return result end) end
    if not ok then pcall(function() q("ROLLBACK") end); error(result) end
    return result
end
local function uid(p) return assert(integer(p:getUserID(),1,MAX_AMOUNT),"ID akun tidak valid.") end
local function isAdmin(p) return p and p:isOnline() and p:getRole()==1000 end
local function tell(p,s) p:onConsoleMessage("`6[Rent]`` "..s) end
local function config(k) return assert(q("SELECT value FROM market_config WHERE key="..sql(k))[1],"Konfigurasi tidak ada.").value end
local function revision() return config("revision") end
local function bump() q("UPDATE market_config SET value=value+1 WHERE key='revision'") end
local function audit(actor,event,ref,detail)
    q("INSERT INTO market_log(actor,event,ref,detail,at) VALUES("..actor..","..sql(event)..","..(ref or 0)..","..sql(clean(detail,240))..","..os.time()..")")
end
local function touch(p)
    local id=uid(p)
    q("INSERT OR IGNORE INTO market_accounts(uid,name,balance,reserved,shop,mascot,slots) VALUES("
        ..id..","..sql(clean(p:getName(),40))..",0,0,"..sql("Toko "..clean(p:getName(),32))..",0,0)")
    q("UPDATE market_accounts SET name="..sql(clean(p:getName(),40)).." WHERE uid="..id)
end
local function account(id) return assert(q("SELECT * FROM market_accounts WHERE uid="..id)[1],"Akun market tidak ditemukan.") end
local function balanceChange(id,delta)
    local a=account(id)
    assert(a.balance+delta>=0 and a.balance+delta+a.reserved<=MAX_BALANCE,"Saldo tidak cukup atau melewati batas.")
    q("UPDATE market_accounts SET balance=balance+"..num(delta).." WHERE uid="..id)
end
local function held(id) return q("SELECT id FROM market_moves WHERE uid="..id.." AND status='pending' LIMIT 1")[1] end
local function available(id) assert(not held(id),"Ada perpindahan aset pending. Hubungi Founder; jangan ulangi transaksi.") end
local function addPlayerBalance(p,data)
    assert(isAdmin(p),"Panel khusus Founder.")
    local growid=tostring(data.growid or ""):match("^%s*(.-)%s*$")
    assert(#growid>=1 and #growid<=40 and growid:match("^[%w_]+$"),"GROWID tidak valid.")
    local raw=tostring(data.balance or ""):match("^%s*(.-)%s*$")
    local whole,fraction=raw:match("^(.-)%.(%d+)$")
    if not whole then whole=raw; fraction="" end
    whole=amount(whole,0,math.floor(MAX_BALANCE/10000))
    assert(whole and #fraction<=4,"BALANCE (BGL) harus angka positif, maksimal 4 desimal. Contoh: 10 atau 0.5.")
    local credit=assert(integer(whole*10000+tonumber(fraction..string.rep("0",4-#fraction)),1,MAX_BALANCE),"BALANCE (BGL) melewati batas atau bernilai nol.")
    assert(type(getPlayerByName)=="function","Pencarian GrowID belum tersedia pada engine.")
    local target=assert(getPlayerByName(growid),"GrowID tidak ditemukan. Player tujuan harus online.")
    assert(target:isOnline(),"Player tujuan harus online.")
    local id=uid(target)
    local result=tx(function()
        assert(isAdmin(p),"Panel khusus Founder.")
        assert(target:isOnline() and uid(target)==id,"Akun tujuan berubah atau sudah offline.")
        available(id); touch(target)
        balanceChange(id,credit)
        local updated=account(id).balance
        audit(uid(p),"admin_balance_added",id,"GrowID "..growid.." / +"..bgl(credit).." BGL / saldo "..bgl(updated).." BGL")
        return updated
    end)
    return {growid=growid,uid=id,credit=credit,balance=result}
end
local function itemName(id) local item=getItem(id); return item and clean(item:getName(),42) or ("Item #"..id) end
local function storage(id,item)
    local row=q("SELECT amount FROM market_storage WHERE uid="..id.." AND item="..item)[1]
    return row and row.amount or 0
end
local function storeChange(id,item,delta)
    local n=storage(id,item)+delta
    assert(n>=0 and n<=MAX_AMOUNT,"Storage tidak cukup atau melewati batas.")
    q("INSERT OR IGNORE INTO market_storage(uid,item,amount) VALUES("..id..","..item..",0)")
    q("UPDATE market_storage SET amount="..num(n).." WHERE uid="..id.." AND item="..item)
end
local function total(p,item) return p:getItemAmount(item)+p:getExtraBackpackAmount(item) end
local function currency()
    return {{id=config("bgl"),value=10000,name="BGL"},{id=config("dl"),value=100,name="DL"},{id=config("wl"),value=1,name="WL"}}
end
local function allowedItem(item)
    local it=assert(getItem(item),"Item ID tidak ditemukan.")
    for _,c in ipairs(currency()) do assert(item~=c.id,"Mata uang tidak dapat dimasukkan sebagai barang market.") end
    assert(not q("SELECT item FROM market_blacklist WHERE item="..item)[1],"Item dibatasi oleh Founder.")
    assert(not it:isBlacklisted(),"Item ini dibatasi engine.")
    for _,info in ipairs(it:getInfo()) do
        local s=tostring(info):lower()
        assert(not s:find("untradeable",1,true) and not s:find("untradable",1,true),"Item tidak dapat diperdagangkan.")
    end
    return it
end

-- Persist intent before touching the engine. A partial/ambiguous result stays
-- pending and is never retried automatically, even after script/server reload.
local function move(p,kind,item,n,value)
    local id=uid(p); available(id)
    local legs={}
    if kind=="money_in" or kind=="item_in" then
        assert(p:getItemAmount(item)>=n,"Item di inventory tidak cukup.")
        legs={{item=item,delta=-n}}
    elseif kind=="money_out" then
        local rem=value
        for _,c in ipairs(currency()) do
            local count=math.floor(rem/c.value); rem=rem-count*c.value
            if count>0 then legs[#legs+1]={item=c.id,delta=count} end
        end
    elseif kind=="item_out" then legs={{item=item,delta=n}}
    else error("Jenis perpindahan tidak valid.") end
    for _,l in ipairs(legs) do
        l.before_inv=p:getItemAmount(l.item); l.before_extra=p:getExtraBackpackAmount(l.item)
        assert(l.before_inv+l.before_extra+math.max(0,l.delta)<=MAX_AMOUNT,"Inventory/Extra Backpack melewati batas.")
    end
    local journal=tx(function()
        available(id)
        if kind=="money_out" then balanceChange(id,-value) end
        if kind=="item_out" then storeChange(id,item,-n) end
        if kind=="money_in" then assert(account(id).balance+account(id).reserved+value<=MAX_BALANCE,"Saldo melewati batas.") end
        if kind=="item_in" then assert(storage(id,item)+n<=MAX_AMOUNT,"Storage melewati batas.") end
        q("INSERT INTO market_moves(uid,kind,item,amount,value,status,at) VALUES("..id..","..sql(kind)..","..item..","..n..","..value..",'pending',"..os.time()..")")
        local key=q("SELECT last_insert_rowid() AS id")[1].id
        for _,l in ipairs(legs) do
            q("INSERT INTO market_move_legs(move,item,delta,before_inv,before_extra) VALUES("..key..","..l.item..","..l.delta..","..l.before_inv..","..l.before_extra..")")
        end
        audit(id,"move_pending",key,kind)
        return key
    end)
    for _,l in ipairs(legs) do
        local ok
        if l.delta<0 then ok=p:changeItem(l.item,l.delta) else ok=p:giveItem(l.item,l.delta) end
        local inv,extra=p:getItemAmount(l.item),p:getExtraBackpackAmount(l.item)
        q("UPDATE market_move_legs SET after_inv="..inv..",after_extra="..extra.." WHERE move="..journal.." AND item="..l.item)
        assert(ok==true and inv+extra==l.before_inv+l.before_extra+l.delta,"Perpindahan item gagal/tidak pasti. Transaksi #"..journal.." ditahan untuk pemeriksaan Founder.")
    end
    tx(function()
        assert(q("SELECT status FROM market_moves WHERE id="..journal)[1].status=="pending","Jurnal sudah diproses.")
        if kind=="money_in" then balanceChange(id,value) end
        if kind=="item_in" then storeChange(id,item,n) end
        q("UPDATE market_moves SET status='done' WHERE id="..journal)
        audit(id,"move_done",journal,kind.." / "..fmt(value).." WL / item "..item.." x"..n)
    end)
end

local function initialize()
    db=assert(sqlite.open(DB_FILE),"SQLite market tidak dapat dibuka.")
    q("PRAGMA synchronous=FULL")
    q("CREATE TABLE IF NOT EXISTS market_config(key TEXT PRIMARY KEY,value INTEGER NOT NULL)")
    q("CREATE TABLE IF NOT EXISTS market_accounts(uid INTEGER PRIMARY KEY,name TEXT NOT NULL,balance INTEGER NOT NULL CHECK(balance>=0),reserved INTEGER NOT NULL CHECK(reserved>=0),shop TEXT NOT NULL,mascot INTEGER NOT NULL,slots INTEGER NOT NULL)")
    q("CREATE TABLE IF NOT EXISTS market_storage(uid INTEGER NOT NULL,item INTEGER NOT NULL,amount INTEGER NOT NULL CHECK(amount>=0),PRIMARY KEY(uid,item))")
    q("CREATE TABLE IF NOT EXISTS market_blacklist(item INTEGER PRIMARY KEY)")
    q("CREATE TABLE IF NOT EXISTS market_moves(id INTEGER PRIMARY KEY AUTOINCREMENT,uid INTEGER NOT NULL,kind TEXT NOT NULL,item INTEGER NOT NULL,amount INTEGER NOT NULL,value INTEGER NOT NULL,status TEXT NOT NULL,at INTEGER NOT NULL)")
    q("CREATE TABLE IF NOT EXISTS market_move_legs(move INTEGER NOT NULL,item INTEGER NOT NULL,delta INTEGER NOT NULL,before_inv INTEGER NOT NULL,before_extra INTEGER NOT NULL,after_inv INTEGER,after_extra INTEGER,PRIMARY KEY(move,item))")
    q("CREATE TABLE IF NOT EXISTS market_log(id INTEGER PRIMARY KEY AUTOINCREMENT,actor INTEGER NOT NULL,event TEXT NOT NULL,ref INTEGER NOT NULL,detail TEXT NOT NULL,at INTEGER NOT NULL)")
    q("CREATE TABLE IF NOT EXISTS market_listings(id INTEGER PRIMARY KEY AUTOINCREMENT,owner INTEGER NOT NULL,item INTEGER NOT NULL,price INTEGER NOT NULL,minutes INTEGER NOT NULL,available INTEGER NOT NULL CHECK(available>=0),relist INTEGER NOT NULL,closed INTEGER NOT NULL DEFAULT 0,version INTEGER NOT NULL DEFAULT 1,at INTEGER NOT NULL)")
    q("CREATE TABLE IF NOT EXISTS market_rentals(id INTEGER PRIMARY KEY AUTOINCREMENT,listing INTEGER NOT NULL,seller INTEGER NOT NULL,buyer INTEGER NOT NULL,item INTEGER NOT NULL,gross INTEGER NOT NULL,tax INTEGER NOT NULL,net INTEGER NOT NULL,relist INTEGER NOT NULL,started INTEGER NOT NULL,expires INTEGER NOT NULL,state TEXT NOT NULL,token TEXT UNIQUE)")
    q("CREATE TABLE IF NOT EXISTS market_reviews(rental INTEGER PRIMARY KEY,seller INTEGER NOT NULL,buyer INTEGER NOT NULL,rating INTEGER NOT NULL CHECK(rating>=1 AND rating<=5),comment TEXT NOT NULL,at INTEGER NOT NULL)")
    q("CREATE INDEX IF NOT EXISTS market_listings_open ON market_listings(closed,id)")
    q("CREATE INDEX IF NOT EXISTS market_rentals_state ON market_rentals(state,expires,id)")
    q("CREATE INDEX IF NOT EXISTS market_rentals_buyer ON market_rentals(buyer,id)")
    q("CREATE INDEX IF NOT EXISTS market_rentals_seller ON market_rentals(seller,state,expires,id)")
    q("CREATE INDEX IF NOT EXISTS market_rentals_listing ON market_rentals(listing,state)")
    q("CREATE INDEX IF NOT EXISTS market_moves_pending ON market_moves(uid,status)")
    q("CREATE INDEX IF NOT EXISTS market_log_actor ON market_log(actor,id)")
    tx(function()
        local defaults={wl=242,dl=1796,bgl=7188,tax=0,slots=10,enabled=1,revision=0,generation=0,treasury=0,tax_reserved=0}
        for key,value in pairs(defaults) do q("INSERT OR IGNORE INTO market_config(key,value) VALUES("..sql(key)..","..value..")") end
        q("UPDATE market_config SET value=value+1 WHERE key='generation'")
        generation=config("generation")
    end)
    local seen={}
    for _,c in ipairs(currency()) do
        assert(integer(c.id,1,MAX_AMOUNT) and getItem(c.id) and not seen[c.id],"Mata uang market tidak tersedia/duplikat.")
        seen[c.id]=true
    end
    assert(integer(config("slots"),1,MAX_SLOTS) and integer(config("tax"),0,10000),"Konfigurasi slot/pajak tidak valid.")
end

local function backendReady()
    local b=RENTAL_BACKEND
    return type(b)=="table" and b.version==1 and b.offlineExpiry==true and b.nonTransferable==true
        and type(b.supports)=="function" and type(b.grant)=="function" and type(b.status)=="function" and type(b.revoke)=="function"
end
local function requireBackend(item)
    assert(backendReady(),"Rental native belum terhubung. Founder perlu memasang backend item sementara.")
    assert(RENTAL_BACKEND.supports(item)==true,"Item ini tidak didukung rental native.")
end
local function listing(id) return assert(q("SELECT * FROM market_listings WHERE id="..id)[1],"Listing tidak ditemukan.") end
local function rental(id) return assert(q("SELECT * FROM market_rentals WHERE id="..id)[1],"Rental tidak ditemukan.") end
local function remaining(list)
    return q("SELECT COUNT(*) AS n FROM market_rentals WHERE listing="..list.." AND state IN ('allocating','active')")[1].n
end
local function closeEmpty(list)
    q("UPDATE market_listings SET closed=1 WHERE id="..list.." AND available=0 AND NOT EXISTS(SELECT 1 FROM market_rentals WHERE listing="..list.." AND state IN ('allocating','active'))")
end
local function claim(p,item)
    available(uid(p))
    local n=storage(uid(p),item)
    if n>0 then move(p,"item_out",item,n,0) end
end
local function claimReturns(p)
    if not ready or held(uid(p)) then return end
    for _,row in ipairs(q("SELECT item FROM market_storage WHERE uid="..uid(p).." AND amount>0 LIMIT 5")) do claim(p,row.item) end
end
local function slotsFor(id)
    local a=account(id)
    return math.min(MAX_SLOTS,a.slots>0 and a.slots or config("slots"))
end
local function checkListing(p,item)
    available(uid(p)); allowedItem(item); requireBackend(item)
    for slot=0,9 do assert(p:getClothingItemID(slot)~=item,"Lepaskan item yang sedang dipakai sebelum menitipkannya ke RENT.") end
    assert(config("enabled")==1,"Market sedang ditutup untuk transaksi baru.")
    assert(q("SELECT COUNT(*) AS n FROM market_listings WHERE owner="..uid(p).." AND closed=0")[1].n<slotsFor(uid(p)),"Slot toko penuh (maksimal 10 listing).")
end
local function addListing(p,data)
    local item=assert(integer(data.item,1,MAX_AMOUNT),"ITEMID tidak valid.")
    local cost=price(data.price)
    local minutes=assert(integer(data.minutes,1,525600),"Durasi 1 sampai 525,600 menit.")
    local stock=assert(amount(data.stock,1,200),"Stock 1 sampai 200 per listing.")
    local relist=tostring(data.relist)=="1" and 1 or 0
    checkListing(p,item)
    local missing=math.max(0,stock-storage(uid(p),item))
    if missing>0 then move(p,"item_in",item,missing,0) end
    return tx(function()
        checkListing(p,item)
        storeChange(uid(p),item,-stock)
        q("INSERT INTO market_listings(owner,item,price,minutes,available,relist,closed,at) VALUES("
            ..uid(p)..","..item..","..cost..","..minutes..","..stock..","..relist..",0,"..os.time()..")")
        local key=q("SELECT last_insert_rowid() AS id")[1].id
        audit(uid(p),"listing_added",key,"Item "..item.." x"..stock.." / "..cost.." WL / "..minutes.." menit")
        return key
    end)
end
local function delist(p,key,adminAction)
    local item=tx(function()
        local l=listing(key)
        assert(l.owner==uid(p) or (adminAction and isAdmin(p)),"Bukan toko Anda.")
        assert(l.closed==0,"Listing sudah ditutup.")
        storeChange(l.owner,l.item,l.available)
        q("UPDATE market_listings SET available=0,closed=1,version=version+1 WHERE id="..key)
        audit(uid(p),"listing_closed",key,"Rental aktif diselesaikan sesuai durasinya.")
        return l.item
    end)
    if not adminAction then claim(p,item) end
end
local function changeStock(p,key,n,take,version)
    available(uid(p))
    local function check()
        local l=listing(key)
        assert(l.owner==uid(p) and l.closed==0 and l.version==version,"Listing sudah berubah atau bukan milik Anda.")
        if take then assert(l.available>=n,"Stok tersedia tidak cukup. Item yang sedang disewa tidak dapat ditarik.")
        else
            allowedItem(l.item); requireBackend(l.item)
            assert(config("enabled")==1,"Rental sedang ditutup untuk stok baru.")
            assert(l.available+remaining(key)+n<=200,"Total stok tersedia dan disewa maksimal 200 per listing.")
            for slot=0,9 do assert(p:getClothingItemID(slot)~=l.item,"Lepaskan item yang sedang dipakai terlebih dahulu.") end
        end
        return l
    end
    local l=check()
    if not take then
        local missing=math.max(0,n-storage(uid(p),l.item))
        if missing>0 then move(p,"item_in",l.item,missing,0) end
    end
    tx(function()
        check()
        storeChange(uid(p),l.item,take and n or -n)
        q("UPDATE market_listings SET available=available+"..(take and -n or n)..",version=version+1 WHERE id="..key)
        if take then closeEmpty(key) end
        audit(uid(p),take and "stock_taken" or "stock_added",key,"Item "..l.item.." x"..n)
    end)
    if take then claim(p,l.item) end
end
local function quoteRent(p,key)
    local l=listing(key)
    available(uid(p)); allowedItem(l.item); requireBackend(l.item)
    assert(config("enabled")==1 and l.closed==0 and l.available>0,"Rental tidak tersedia.")
    assert(l.owner~=uid(p),"Tidak dapat menyewa item dari toko sendiri.")
    assert(account(uid(p)).balance>=l.price,"Saldo kurang. Pilih Isi Saldo untuk membayar sewa.")
    local tax=math.floor(l.price*config("tax")/10000)
    local net=l.price-tax
    local seller=account(l.owner)
    assert(seller.balance+seller.reserved+net<=MAX_BALANCE,"Saldo pemilik toko penuh.")
    assert(config("treasury")+config("tax_reserved")+tax<=MAX_BALANCE,"Saldo pajak market penuh.")
    return {listing=key,version=l.version,revision=revision(),gross=l.price,tax=tax,net=net,item=l.item,minutes=l.minutes}
end
local function requestRent(p,quote)
    local current=quoteRent(p,quote.listing)
    assert(current.version==quote.version and current.revision==quote.revision,"Harga/pengaturan berubah. Buka rental kembali.")
    return tx(function()
        local l=listing(quote.listing)
        assert(l.closed==0 and l.available>0 and l.version==quote.version,"Stock atau harga berubah.")
        balanceChange(uid(p),-quote.gross)
        q("UPDATE market_accounts SET reserved=reserved+"..quote.gross.." WHERE uid="..uid(p))
        q("UPDATE market_accounts SET reserved=reserved+"..quote.net.." WHERE uid="..l.owner)
        q("UPDATE market_config SET value=value+"..quote.tax.." WHERE key='tax_reserved'")
        q("UPDATE market_listings SET available=available-1 WHERE id="..l.id)
        local now=os.time()
        q("INSERT INTO market_rentals(listing,seller,buyer,item,gross,tax,net,relist,started,expires,state) VALUES("
            ..l.id..","..l.owner..","..uid(p)..","..l.item..","..quote.gross..","..quote.tax..","..quote.net..","..l.relist..","..now..","..(now+l.minutes*60)..",'allocating')")
        local key=q("SELECT last_insert_rowid() AS id")[1].id
        q("UPDATE market_rentals SET token="..sql("player-market-v1:"..key).." WHERE id="..key)
        audit(uid(p),"rent_reserved",key,"Listing #"..l.id.." / "..quote.gross.." WL")
        return key
    end)
end
-- External grants must be durable and idempotent by token. No ordinary giveItem
-- fallback is allowed: it cannot protect a rented asset or revoke it offline.
local function processRental(key)
    local r=rental(key)
    if r.state~="allocating" and r.state~="active" then return end
    requireBackend(r.item)
    local status=RENTAL_BACKEND.status(r.token)
    if r.state=="allocating" and status=="absent" and os.time()<r.expires then
        RENTAL_BACKEND.grant(r.token,r.buyer,r.item,1,r.expires)
        status=RENTAL_BACKEND.status(r.token)
    end
    if status=="active" and os.time()>=r.expires then
        RENTAL_BACKEND.revoke(r.token)
        status=RENTAL_BACKEND.status(r.token)
    end
    assert(status=="active" or status=="expired" or status=="rejected" or status=="absent","Status rental native belum pasti; saldo dan stock ditahan.")
    assert(status~="active" or os.time()<r.expires,"Native engine belum menarik item yang kedaluwarsa; stok tetap ditahan.")
    if r.state=="active" then assert(status=="active" or status=="expired","Receipt rental aktif hilang/berubah; stok tetap ditahan.") end
    if r.state=="allocating" then
        local neverGranted=status=="rejected" or (status=="absent" and os.time()>=r.expires)
        if status=="absent" then assert(neverGranted,"Pemberian item masih menunggu native engine.") end
        tx(function()
            assert(rental(key).state=="allocating","Status rental berubah.")
            q("UPDATE market_accounts SET reserved=reserved-"..r.gross.." WHERE uid="..r.buyer)
            q("UPDATE market_accounts SET reserved=reserved-"..r.net.." WHERE uid="..r.seller)
            q("UPDATE market_config SET value=value-"..r.tax.." WHERE key='tax_reserved'")
            if neverGranted then
                balanceChange(r.buyer,r.gross)
                local l=listing(r.listing)
                if l.closed==0 then q("UPDATE market_listings SET available=available+1 WHERE id="..l.id)
                else storeChange(r.seller,r.item,1) end
                q("UPDATE market_rentals SET state='refunded' WHERE id="..key)
                audit(r.buyer,"rent_refunded",key,"Item tidak pernah diberikan; pembayaran dikembalikan.")
            else
                balanceChange(r.seller,r.net)
                q("UPDATE market_config SET value=value+"..r.tax.." WHERE key='treasury'")
                q("UPDATE market_rentals SET state='active' WHERE id="..key)
                audit(r.buyer,"rent_paid",key,"Gross "..r.gross.." WL; tax "..r.tax.." WL; seller #"..r.seller.." net "..r.net.." WL")
            end
        end)
        r=rental(key)
    end
    if r.state=="active" and status=="expired" then
        tx(function()
            assert(rental(key).state=="active","Rental sudah dikembalikan.")
            local l=listing(r.listing)
            if r.relist==1 and l.closed==0 then
                q("UPDATE market_listings SET available=available+1 WHERE id="..l.id)
            else storeChange(r.seller,r.item,1) end
            q("UPDATE market_rentals SET state='returned' WHERE id="..key)
            closeEmpty(r.listing)
            audit(r.buyer,"rent_returned",key,"Item ditarik native engine; kembali ke pemilik #"..r.seller)
        end)
    end
end

local function label(lines,text) lines[#lines+1]="add_smalltext|"..text.."|\n" end
local function button(lines,key,text) lines[#lines+1]="add_button|"..key.."|"..text.."|noflags|0|0|\n" end
local function spacer(lines) lines[#lines+1]="add_spacer|small|\n" end
local function textBox(lines,text) lines[#lines+1]="add_textbox|"..text.."|left|\n" end
local function heading(lines,text)
    spacer(lines); lines[#lines+1]="add_label|big|`w"..text.."``|left|\n"
end
local function iconLabel(lines,item,text)
    lines[#lines+1]="add_label_with_icon|small|"..text.."``|left|"..item.."|\n"
end
local function gridEnd(lines) lines[#lines+1]="add_button_with_icon||END_LIST|noflags|0||\n" end
local function iconButton(lines,key,item,count)
    lines[#lines+1]="add_button_with_icon|"..key.."|`w"..clean(itemName(item),28).."|staticBlueFrame|"..item.."|"..num(count).."|\n"
end
local function input(lines,key,text,value,length)
    lines[#lines+1]="add_text_input|"..key.."|"..text.."|"..clean(value,240).."|"..(length or 40).."|\n"
end
local function checkbox(lines,key,text,checked)
    lines[#lines+1]="add_checkbox|"..key.."|"..text.."|"..(checked and "1" or "0").."|\n"
end
local function begin(title,icon)
    local chosen=icon or RENT_ICON_ID
    if not getItem(chosen) then chosen=config("bgl") end
    return {"set_default_color|`w\nset_bg_color|32,28,54,225|\nset_border_color|126,93,190,255|\n"
        .."add_label_with_icon|big|`w"..title.."``|left|"..chosen.."|\n"}
end
local function show(p,lines,state)
    serial=serial+1
    state.name="player_market_"..generation.."_"..serial
    state.expires=os.time()+120; state.buttons={}; state.revision=revision()
    for _,s in ipairs(lines) do
        local key=s:match("^add_button[^|]*|([^|]+)|")
        if key then state.buttons[key]=true end
    end
    lines[#lines+1]="add_spacer|small|\nadd_smalltext|`9© Dibuat Oleh : Nathan``|\n"
    lines[#lines+1]="add_quick_exit|\nend_dialog|"..state.name.."|`9Close``||"
    local markup=table.concat(lines)
    assert(#markup<4096,"Dialog terlalu panjang.")
    sessions[uid(p)]=state
    p:onDialogRequest(markup)
end
local function pageRows(query,page,size)
    size=size or PAGE_SIZE
    local count=q("SELECT COUNT(*) AS n FROM ("..query..")")[1].n
    local pages=math.max(1,math.ceil(count/size))
    page=math.max(1,math.min(page or 1,pages))
    return q(query.." LIMIT "..size.." OFFSET "..((page-1)*size)),page,pages
end
local function pageButtons(lines,page,pages)
    if pages>1 then
        label(lines,"Halaman "..page.." / "..pages)
        if page>1 then button(lines,"page_"..(page-1),"Sebelumnya") end
        if page<pages then button(lines,"page_"..(page+1),"Berikutnya") end
    end
end
local function rating(seller)
    local row=q("SELECT COUNT(*) AS n,COALESCE(AVG(rating),0) AS score FROM market_reviews WHERE seller="..seller)[1]
    return string.format("%.1f",row.score).."/5 ("..fmt(row.n).." review)"
end
local home,manage,wallet,funding,myRent,rentedOut,adminHome,logs,storageView,detail,ownDetail
home=function(p,page)
    local L=begin("Item Rental")
    textBox(L,"Sewa item dari player lain, atau sewakan itemmu sendiri.")
    spacer(L)
    button(L,"manage","`2KELOLA MY RENT``")
    button(L,"rentals","`!MY RENT``")
    button(L,"wallet","`#Withdraw Currency``")
    heading(L,"Item Tersedia Disewa:")
    if not backendReady() or config("enabled")==0 then textBox(L,"`9Penyewaan belum dibuka.``") end
    local rows,at,pages=pageRows("SELECT * FROM market_listings WHERE closed=0 AND available>0 AND item NOT IN (SELECT item FROM market_blacklist) ORDER BY id DESC",page,GRID_SIZE)
    if #rows==0 then textBox(L,"`9Belum ada item tersedia. Tambahkan item melalui Kelola My Rent.``") end
    for i,l in ipairs(rows) do
        iconButton(L,"rent_"..l.id,l.item,l.available)
        if i%GRID_COLUMNS==0 or i==#rows then gridEnd(L) end
    end
    if #rows>0 then label(L,"`oPilih ikon untuk melihat toko, harga, dan durasi sewa.``") end
    pageButtons(L,at,pages); show(p,L,{view="home",page=at})
end
manage=function(p,page)
    local a=account(uid(p)); local L=begin("Kelola My Rent",a.mascot>0 and a.mascot or nil)
    local used=q("SELECT COUNT(*) AS n FROM market_listings WHERE owner="..uid(p).." AND closed=0")[1].n
    textBox(L,"Kelola stok item yang kamu sewakan dan lihat siapa yang sedang menyewa.")
    label(L,"`o"..clean(a.shop).."  /  Slot "..used.."/"..slotsFor(uid(p)).."  /  "..rating(uid(p)).."``")
    spacer(L); button(L,"add","`2+ TAMBAH ITEM BARU UNTUK DISEWAKAN``")
    heading(L,"Stock Yang Kamu Sewakan:")
    local rows,at,pages=pageRows("SELECT * FROM market_listings WHERE owner="..uid(p).." AND closed=0 ORDER BY id DESC",page)
    if #rows==0 then textBox(L,"`9Tidak ada stok tersedia. Tekan tombol di atas untuk menambah item.``") end
    for _,l in ipairs(rows) do
        iconButton(L,"own_"..l.id,l.item,l.available)
    end
    if #rows>0 then gridEnd(L); label(L,"`oAngka pada ikon = stok siap disewa. Pilih ikon untuk tambah, tarik, atau edit stok.``") end
    pageButtons(L,at,pages)
    heading(L,"Item Idle / Menunggu Pengembalian:")
    local stored=q("SELECT * FROM market_storage WHERE uid="..uid(p).." AND amount>0 ORDER BY item LIMIT 4")
    if #stored==0 then textBox(L,"`9Tidak ada item idle.``")
    else
        for _,r in ipairs(stored) do iconButton(L,"stored_"..r.item,r.item,r.amount) end
        gridEnd(L); button(L,"storage","Ambil Item Kembali")
    end
    heading(L,"Sedang Disewa Orang Lain:")
    local activeQuery="SELECT r.*,a.name FROM market_rentals r JOIN market_accounts a ON a.uid=r.buyer WHERE r.seller="..uid(p).." AND r.state IN ('allocating','active') ORDER BY r.expires,r.id"
    local active,_,activePages=pageRows(activeQuery,1,2)
    if #active==0 then textBox(L,"`9Tidak ada item yang sedang disewa orang lain saat ini.``") end
    for _,r in ipairs(active) do
        iconLabel(L,r.item,"`w"..itemName(r.item).."  `o/  "..clean(r.name,32))
        label(L,r.state=="allocating" and "`9Menyiapkan item...``" or ("`oSisa "..fmt(math.max(0,math.ceil((r.expires-os.time())/60))).." menit``"))
    end
    if activePages>1 then button(L,"outgoing","Lihat Semua Penyewa") end
    spacer(L); button(L,"profile","Nama & Maskot Toko"); button(L,"logs","Riwayat Transaksi")
    button(L,"home","Back"); show(p,L,{view="manage",page=at})
end
local function listingForm(p,key)
    local l=key and listing(key)
    if l then assert(l.owner==uid(p) and l.closed==0,"Bukan listing aktif Anda.") end
    local L=begin(l and "Edit Item Rental" or "List / Tambah Stock Item",l and l.item)
    textBox(L,"Harga dalam `9BGL`` per unit untuk satu masa sewa.")
    label(L,"`oDurasi 1 - 525,600 menit. Stok maksimal 200 per listing.``")
    spacer(L)
    if l then iconLabel(L,l.item,"`w"..itemName(l.item)) else input(L,"item","Item ID", "",10) end
    input(L,"price","Harga per unit (BGL)",l and bgl(l.price) or "1",18)
    input(L,"minutes","Durasi Sewa (menit)",l and l.minutes or "60",6)
    if not l then input(L,"stock","Jumlah Stock","1",3) end
    checkbox(L,"relist","Otomatis sewakan lagi setelah masa sewa habis",not l or l.relist==1)
    spacer(L)
    textBox(L,"`9Jika dimatikan: item kembali ke inventory kamu setelah masa sewa habis. Saat offline, item menunggu di Item Kembali sampai kamu login.``")
    label(L,"`oPajak dipotong dari hasil sewa. Perubahan harga berlaku untuk penyewaan berikutnya.``")
    spacer(L); button(L,"save",l and "`2SIMPAN PERUBAHAN``" or "`2LIST / TAMBAH STOCK``"); button(L,"manage","Back")
    show(p,L,{view="listing_form",record=key,version=l and l.version})
end
ownDetail=function(p,key)
    local l=listing(key); assert(l.owner==uid(p),"Bukan toko Anda.")
    local L=begin(itemName(l.item),l.item)
    textBox(L,"Harga: `2"..bgl(l.price).." BGL``  /  "..fmt(l.minutes).." menit")
    label(L,"Stok siap disewa: `2"..fmt(l.available).."``  /  Sedang disewa: `!"..fmt(remaining(key)).."``")
    label(L,"Otomatis sewakan lagi: "..(l.relist==1 and "`2ON``" or "`9OFF``"))
    spacer(L)
    if l.closed==0 then
        button(L,"add_stock","`2+ Tambah Stock``")
        if l.available>0 then button(L,"take_stock","`9Ambil Stock``") end
        button(L,"edit","Edit Harga / Durasi / Auto-relist")
        button(L,"delist","`4Tutup RENT & Kembalikan Stok``")
    end
    textBox(L,"`oItem yang sedang disewa kembali setelah waktunya habis.``")
    button(L,"manage","Back"); show(p,L,{view="own",record=key,version=l.version})
end
detail=function(p,key)
    local l=listing(key); local shop=account(l.owner)
    local L=begin(itemName(l.item),l.item)
    if shop.mascot>0 and getItem(shop.mascot) then
        L[#L+1]="add_label_with_icon|small|`w"..clean(shop.shop).."``|left|"..shop.mascot.."|\n"
        label(L,rating(l.owner))
    else label(L,"Toko: `w"..clean(shop.shop).."`` / "..rating(l.owner)) end
    heading(L,"Detail Sewa")
    textBox(L,"Harga: `2"..bgl(l.price).." BGL`` per item  /  `9"..fmt(l.minutes).." menit``")
    label(L,"Stok tersedia: `2"..fmt(l.available).."``")
    label(L,"Saldo kamu: `!"..money(account(uid(p)).balance).."``")
    spacer(L); textBox(L,"`oItem hanya dipinjam selama durasi sewa. Item tidak dapat dipindahkan dan kembali otomatis saat waktunya habis.``")
    spacer(L)
    if l.owner==uid(p) then button(L,"manage","Kelola Item Saya")
    elseif q("SELECT item FROM market_blacklist WHERE item="..l.item)[1] then textBox(L,"`9Item ini diblacklist dan tidak dapat disewa.``")
    elseif l.closed==0 and l.available>0 and backendReady() and config("enabled")==1 then
        if account(uid(p)).balance>=l.price then button(L,"hire","`2SEWA 1 ITEM``")
        else textBox(L,"`9Saldo belum cukup. Isi saldo terlebih dahulu.``"); button(L,"funding","`2Isi Saldo``") end
    else textBox(L,"`9Item belum tersedia untuk disewa.``") end
    button(L,"reviews","Review Toko"); button(L,"home","Back")
    show(p,L,{view="detail",record=key,seller=l.owner})
end
wallet=function(p)
    local a=account(uid(p)); local L=begin("Ambil `9"..itemName(config("bgl")),config("bgl"))
    textBox(L,"Saldo tersimpan: `2"..money(a.balance).."``")
    label(L,"`oPendapatan dari sewa itemmu masuk ke sini, termasuk saat kamu offline.``")
    if a.reserved>0 then label(L,"Penyelesaian rental tertunda: "..fmt(a.reserved).." WL") end
    if held(uid(p)) then label(L,"`4Ada perpindahan pending; hubungi Founder.``") end
    spacer(L)
    if a.balance==0 then textBox(L,"`9Saldo kamu kosong.``")
    else
        input(L,"withdraw","Jumlah saldo yang ditarik (WL)",num(a.balance),16)
        label(L,"`o10,101 WL = 1 BGL + 1 DL + 1 WL. Lock dikonversi otomatis saat ditarik.``")
        button(L,"withdraw","`2TARIK SALDO``")
    end
    spacer(L); button(L,"funding","Isi Saldo untuk Sewa"); button(L,"logs","Riwayat Transaksi"); button(L,"home","Back")
    show(p,L,{view="wallet"})
end
funding=function(p)
    local L=begin("Isi Saldo Rental",config("bgl"))
    textBox(L,"Saldo kamu: `2"..money(account(uid(p)).balance).."``")
    label(L,"`oSetor lock dari inventory untuk membayar sewa item.``")
    spacer(L)
    input(L,"amount","Jumlah lock yang akan disetor","1",16)
    for _,c in ipairs(currency()) do button(L,"deposit_"..c.id,"`2Deposit "..c.name.."``") end
    spacer(L); label(L,"`o100 WL = 1 DL. 100 DL = 1 BGL.``")
    button(L,"wallet","Back"); button(L,"home","Lihat Item Rental"); show(p,L,{view="funding"})
end
storageView=function(p,page)
    local L=begin("STORAGE / ITEM KEMBALI")
    label(L,"Item yang menunggu pengiriman kembali ke inventory Anda.")
    local rows,at,pages=pageRows("SELECT * FROM market_storage WHERE uid="..uid(p).." AND amount>0 ORDER BY item",page)
    if #rows==0 then label(L,"Storage kosong.") end
    for _,r in ipairs(rows) do label(L,itemName(r.item).." x"..fmt(r.amount)); button(L,"claim_"..r.item,"Ambil Item") end
    pageButtons(L,at,pages); button(L,"manage","Kembali"); show(p,L,{view="storage",page=at})
end
myRent=function(p,page,history)
    local L=begin(history and "Riwayat Sewa" or "My Rent")
    textBox(L,history and "Sewa yang sudah selesai atau dibatalkan." or "Item yang sedang kamu sewa dari player lain.")
    heading(L,history and "Riwayat Item Rental:" or "Item Yang Kamu Sewa:")
    local filter=history and " IN ('returned','refunded')" or " IN ('active','allocating')"
    local rows,at,pages=pageRows("SELECT r.*,a.shop FROM market_rentals r JOIN market_accounts a ON a.uid=r.seller WHERE r.buyer="..uid(p).." AND r.state"..filter.." ORDER BY r.id DESC",page)
    if #rows==0 then textBox(L,history and "`9Belum ada riwayat sewa.``" or "`9Kamu belum menyewa item apapun.``") end
    for _,r in ipairs(rows) do
        local names={allocating="Menunggu pemberian item",active="Sedang disewa",returned="Selesai / dikembalikan",refunded="Dibatalkan / saldo kembali"}
        iconLabel(L,r.item,"`w"..itemName(r.item).." `o/ "..clean(r.shop,35))
        label(L,(names[r.state] or r.state).." / "..bgl(r.gross).." BGL")
        if r.state=="active" then label(L,"`2Sisa "..fmt(math.max(0,math.ceil((r.expires-os.time())/60))).." menit`` / selesai "..os.date("!%d/%m %H:%M",r.expires+25200).." WIB") end
        if r.state=="returned" and not q("SELECT rental FROM market_reviews WHERE rental="..r.id)[1] then button(L,"review_"..r.id,"Beri Review") end
    end
    pageButtons(L,at,pages)
    if not history and q("SELECT id FROM market_rentals WHERE buyer="..uid(p).." AND state IN ('returned','refunded') LIMIT 1")[1] then button(L,"rental_history","Riwayat Sewa & Review") end
    button(L,history and "rentals" or "home","Back"); show(p,L,{view="rentals",page=at,history=history})
end
rentedOut=function(p,page)
    local L=begin("Penyewa Item Saya")
    textBox(L,"Item milikmu yang sedang dipakai player lain.")
    local rows,at,pages=pageRows("SELECT r.*,a.name FROM market_rentals r JOIN market_accounts a ON a.uid=r.buyer WHERE r.seller="..uid(p).." AND r.state IN ('allocating','active') ORDER BY r.expires,r.id",page)
    if #rows==0 then textBox(L,"`9Belum ada penyewa aktif.``") end
    for _,r in ipairs(rows) do
        spacer(L); iconLabel(L,r.item,"`w"..itemName(r.item).." `o/ "..clean(r.name,32))
        label(L,r.state=="allocating" and "`9Menyiapkan item...``" or ("`2Sisa "..fmt(math.max(0,math.ceil((r.expires-os.time())/60))).." menit``"))
        label(L,"Sewa #"..r.id.." / "..bgl(r.gross).." BGL / selesai "..os.date("!%d/%m %H:%M",r.expires+25200).." WIB")
    end
    pageButtons(L,at,pages); button(L,"manage","Back"); show(p,L,{view="outgoing",page=at})
end
local function reviews(p,seller,page)
    local L=begin("REVIEW / "..clean(account(seller).shop,35))
    label(L,rating(seller))
    local rows,at,pages=pageRows("SELECT * FROM market_reviews WHERE seller="..seller.." ORDER BY at DESC,rental DESC",page)
    if #rows==0 then label(L,"Belum ada review.") end
    for _,r in ipairs(rows) do label(L,r.rating.."/5 / "..clean(account(r.buyer).name)); label(L,clean(r.comment,120)) end
    pageButtons(L,at,pages); button(L,"home","Kembali"); show(p,L,{view="reviews",seller=seller,page=at})
end
logs=function(p,page)
    local filter=" WHERE actor="..uid(p).." OR (event='rent_paid' AND ref IN (SELECT id FROM market_rentals WHERE seller="..uid(p)..")) OR (event='admin_balance_added' AND ref="..uid(p)..")"
    local rows,at,pages=pageRows("SELECT * FROM market_log"..filter.." ORDER BY id DESC",page)
    local L=begin("RIWAYAT TRANSAKSI")
    if #rows==0 then label(L,"Belum ada transaksi.") end
    for _,r in ipairs(rows) do
        label(L,"#"..r.id.." "..os.date("!%d/%m %H:%M",r.at+25200).." WIB / "..clean(r.event).." / #"..r.actor)
        label(L,clean(r.detail,200))
    end
    pageButtons(L,at,pages); button(L,"home","Kembali")
    show(p,L,{view="logs",page=at})
end
adminHome=function(p)
    assert(isAdmin(p),"Panel khusus Founder.")
    local L=begin("Rental / Founder")
    textBox(L,"Atur item yang dilarang dan tambah saldo player.")
    spacer(L)
    button(L,"blacklist","`4Blacklist Item``")
    button(L,"add_balance","`2Add Balance Player``")
    show(p,L,{view="admin",admin=true})
end
local function addBalanceForm(p,result)
    assert(isAdmin(p),"Panel khusus Founder.")
    local L=begin("Add Balance Player")
    if result then
        textBox(L,"`2Berhasil menambahkan "..bgl(result.credit).." BGL ke "..clean(result.growid)..".``")
        label(L,"Saldo sekarang: "..money(result.balance))
    end
    spacer(L)
    input(L,"growid","GROWID :","",40)
    input(L,"balance","BALANCE ( BGL ) :","",24)
    label(L,"Player tujuan harus online. Jumlah ini ditambahkan ke saldo rental.")
    spacer(L); button(L,"save","`2TAMBAH BALANCE``"); button(L,"admin","Back")
    show(p,L,{view="add_balance",admin=true})
end
local function blacklistView(p,page)
    local L=begin("Blacklist Item")
    input(L,"item","Item ID :","",10); button(L,"block","`4+ Tambah Blacklist``")
    local rows,at,pages=pageRows("SELECT item FROM market_blacklist ORDER BY item",page)
    for _,r in ipairs(rows) do button(L,"unblock_"..r.item,"Hapus #"..r.item.." "..itemName(r.item)) end
    label(L,"Item No-/Buy, untradeable, dan mata uang selalu ditolak meskipun tidak ada di daftar ini.")
    pageButtons(L,at,pages); button(L,"admin","Kembali"); show(p,L,{view="blacklist",page=at,admin=true})
end
local function guard(p,fn)
    if not p or not p:isOnline() then return end
    if not ready then tell(p,"`4Rental belum tersedia: "..clean(initError,250)); return end
    local id=uid(p)
    if busy[id] then return end
    busy[id]=true
    local ok,err=pcall(function() touch(p); fn() end)
    busy[id]=nil
    if not ok then
        sessions[id]=nil
        print("[rent] uid="..id.." "..tostring(err))
        tell(p,"`4"..clean(tostring(err):gsub("^.-:%d+:%s*",""),260))
    end
end
-- Keep this callback below Lua 5.1's 60-upvalue limit. Navigation
-- references share one table instead of capturing every page separately.
local dialogPages={
    home=home,
    manage=manage,
    wallet=wallet,
    funding=funding,
    myRent=myRent,
    logs=logs,
    detail=detail,
    storageView=storageView,
    rentedOut=rentedOut,
    listingForm=listingForm,
    ownDetail=ownDetail,
    reviews=reviews,
    addBalanceForm=addBalanceForm,
    blacklistView=blacklistView,
    adminHome=adminHome
}
local function dialogHandler(world,p,d)
    if type(d)~="table" or type(d.dialog_name)~="string" or not d.dialog_name:match("^player_market_") then return false end
    guard(p,function()
        local state=sessions[uid(p)]; local clicked=tostring(d.buttonClicked or "")
        if d.quit=="1" or d.quit==1 or clicked=="" or clicked=="Tutup" or clean(clicked)=="Close" then
            if state and state.name==d.dialog_name then sessions[uid(p)]=nil end
            return
        end
        if not state or state.name~=d.dialog_name or state.expires<=os.time() then dialogPages.home(p); return end
        if state.admin then assert(isAdmin(p),"Panel khusus Founder.") end
        assert(state.buttons[clicked],"Tombol tidak tersedia pada menu ini.")
        sessions[uid(p)]=nil
        if state.revision~=revision() then tell(p,"Pengaturan berubah. Silakan buka kembali menu terbaru."); if state.admin then dialogPages.adminHome(p) else dialogPages.home(p) end; return end
        if clicked=="home" then dialogPages.home(p); return end
        if clicked=="manage" then dialogPages.manage(p); return end
        if clicked=="wallet" then dialogPages.wallet(p); return end
        if clicked=="funding" then dialogPages.funding(p); return end
        if clicked=="rentals" then dialogPages.myRent(p); return end
        if clicked=="rental_history" then dialogPages.myRent(p,1,true); return end
        if clicked=="admin" then dialogPages.adminHome(p); return end
        if clicked=="logs" then dialogPages.logs(p,1); return end
        local page=clicked:match("^page_(%d+)$"); page=page and integer(page,1,MAX_AMOUNT)
        if state.view=="home" then
            if page then dialogPages.home(p,page) else dialogPages.detail(p,assert(integer(clicked:match("^rent_(%d+)$"),1,MAX_AMOUNT))) end
        elseif state.view=="manage" then
            if page then dialogPages.manage(p,page)
            elseif clicked=="add" then dialogPages.listingForm(p)
            elseif clicked=="storage" then dialogPages.storageView(p)
            elseif clicked:match("^stored_%d+$") then dialogPages.storageView(p)
            elseif clicked=="outgoing" then dialogPages.rentedOut(p)
            elseif clicked=="profile" then
                local a=account(uid(p)); local L=begin("TOKO SAYA")
                input(L,"name","Nama toko",a.shop,40); input(L,"mascot","Item ID maskot (0 = default)",a.mascot,10)
                button(L,"save","Simpan Toko"); button(L,"manage","Kembali"); show(p,L,{view="profile"})
            else dialogPages.ownDetail(p,assert(integer(clicked:match("^own_(%d+)$"),1,MAX_AMOUNT))) end
        elseif state.view=="profile" and clicked=="save" then
            local name=clean(d.name,40); assert(name:match("%S"),"Isi nama toko.")
            local mascot=assert(integer(d.mascot,0,MAX_AMOUNT),"ID maskot tidak valid.")
            assert(mascot==0 or getItem(mascot),"Item maskot tidak ada.")
            tx(function() q("UPDATE market_accounts SET shop="..sql(name)..",mascot="..mascot.." WHERE uid="..uid(p)); audit(uid(p),"shop_saved",0,name) end)
            dialogPages.manage(p)
        elseif state.view=="listing_form" and clicked=="save" then
            if state.record then
                local cost=price(d.price); local minutes=assert(integer(d.minutes,1,525600),"Durasi tidak valid.")
                tx(function()
                    local l=listing(state.record)
                    assert(l.owner==uid(p) and l.closed==0 and l.version==state.version,"Listing sudah berubah.")
                    q("UPDATE market_listings SET price="..cost..",minutes="..minutes..",relist="..(tostring(d.relist)=="1" and 1 or 0)..",version=version+1 WHERE id="..l.id)
                    audit(uid(p),"listing_edited",l.id,"Harga "..cost.." WL / "..minutes.." menit")
                end)
            else addListing(p,d) end
            tell(p,"`2RENT tersimpan."); dialogPages.manage(p)
        elseif state.view=="own" then
            if clicked=="edit" then dialogPages.listingForm(p,state.record)
            elseif clicked=="add_stock" or clicked=="take_stock" then
                local l=listing(state.record); assert(l.owner==uid(p) and l.closed==0,"Bukan listing aktif Anda.")
                local take=clicked=="take_stock"; local L=begin(take and "Ambil Stock Item" or "Tambah Stock Item",l.item)
                textBox(L,itemName(l.item).." / tersedia: `2"..fmt(l.available).."`` / disewa: "..fmt(remaining(l.id)))
                input(L,"stock","Jumlah Stock","1",3)
                label(L,take and "`oHanya stok yang belum disewa yang dapat diambil.``" or "`oHarga, durasi, dan auto-relist mengikuti pengaturan listing ini.``")
                button(L,"save",take and "`2AMBIL STOCK``" or "`2TAMBAH STOCK``"); button(L,"manage","Back")
                show(p,L,{view="stock_form",record=l.id,version=l.version,take=take})
            elseif clicked=="delist" then
                local L=begin("TUTUP RENT?")
                label(L,"Stok ready dikembalikan ke inventory. Sewa aktif selesai sesuai durasinya.")
                button(L,"confirm","Tutup & Kembalikan"); button(L,"manage","Batal")
                show(p,L,{view="delist_confirm",record=state.record})
            end
        elseif state.view=="stock_form" and clicked=="save" then
            local n=assert(amount(d.stock,1,200),"Jumlah stock 1 sampai 200.")
            changeStock(p,state.record,n,state.take,state.version)
            tell(p,"`2Stok diperbarui."); dialogPages.ownDetail(p,state.record)
        elseif state.view=="delist_confirm" and clicked=="confirm" then delist(p,state.record,false); dialogPages.manage(p)
        elseif state.view=="detail" then
            if clicked=="reviews" then dialogPages.reviews(p,state.seller)
            elseif clicked=="hire" then
                local quote=quoteRent(p,state.record); local L=begin("KONFIRMASI RENT",quote.item)
                label(L,itemName(quote.item).." x1 / "..quote.minutes.." menit")
                label(L,"Total bayar: `2"..bgl(quote.gross).." BGL`` ("..fmt(quote.gross).." WL)")
                label(L,"Pajak pemilik: "..fmt(quote.tax).." WL. Item otomatis ditarik saat waktunya habis.")
                button(L,"confirm","Bayar & Sewa"); button(L,"home","Batal")
                show(p,L,{view="rent_confirm",quote=quote})
            end
        elseif state.view=="rent_confirm" and clicked=="confirm" then
            local key=requestRent(p,state.quote)
            local ok,err=pcall(processRental,key)
            if not ok then print("[rent] rental #"..key.." "..tostring(err)); tell(p,"Rental #"..key.." menunggu engine. Saldo ditahan sampai hasilnya pasti.") end
            dialogPages.myRent(p)
        elseif state.view=="wallet" and clicked=="withdraw" then
            local n=assert(amount(d.withdraw,1,MAX_BALANCE),"Jumlah WL tidak valid.")
            move(p,"money_out",0,0,n); dialogPages.wallet(p)
        elseif state.view=="funding" then
            available(uid(p))
            local item=assert(integer(clicked:match("^deposit_(%d+)$"),1,MAX_AMOUNT)); local rate
            for _,c in ipairs(currency()) do if c.id==item then rate=c.value end end
            assert(rate,"Mata uang tidak tersedia.")
            local n=assert(amount(d.amount,1,math.floor(MAX_BALANCE/rate)),"Jumlah deposit tidak valid.")
            move(p,"money_in",item,n,n*rate)
            dialogPages.wallet(p)
        elseif state.view=="storage" then
            if page then dialogPages.storageView(p,page) else claim(p,assert(integer(clicked:match("^claim_(%d+)$"),1,MAX_AMOUNT))); dialogPages.storageView(p,state.page) end
        elseif state.view=="rentals" then
            if page then dialogPages.myRent(p,page,state.history)
            else
                local key=assert(integer(clicked:match("^review_(%d+)$"),1,MAX_AMOUNT)); local r=rental(key)
                assert(r.buyer==uid(p) and r.state=="returned","Rental belum selesai atau bukan milik Anda.")
                local L=begin("REVIEW TOKO")
                input(L,"rating","Rating (1 sampai 5)","5",1); input(L,"comment","Komentar","",120)
                button(L,"save","Kirim Review"); button(L,"rentals","Batal"); show(p,L,{view="review_form",record=key})
            end
        elseif state.view=="review_form" and clicked=="save" then
            local score=assert(integer(d.rating,1,5),"Rating 1 sampai 5.")
            tx(function()
                local r=rental(state.record)
                assert(r.buyer==uid(p) and r.buyer~=r.seller and r.state=="returned","Review hanya setelah rental sendiri selesai.")
                assert(not q("SELECT rental FROM market_reviews WHERE rental="..r.id)[1],"Review sudah diberikan.")
                q("INSERT INTO market_reviews(rental,seller,buyer,rating,comment,at) VALUES("..r.id..","..r.seller..","..r.buyer..","..score..","..sql(clean(d.comment,120))..","..os.time()..")")
                audit(uid(p),"review_added",r.id,"Rating "..score)
            end)
            dialogPages.myRent(p,1,true)
        elseif state.view=="outgoing" and page then dialogPages.rentedOut(p,page)
        elseif state.view=="reviews" and page then dialogPages.reviews(p,state.seller,page)
        elseif state.view=="logs" and page then dialogPages.logs(p,page)
        elseif state.view=="admin" then
            if clicked=="blacklist" then dialogPages.blacklistView(p)
            elseif clicked=="add_balance" then dialogPages.addBalanceForm(p) end
        elseif state.view=="add_balance" and clicked=="save" then
            local result=addPlayerBalance(p,d)
            tell(p,"`2Saldo rental "..clean(result.growid).." bertambah "..bgl(result.credit).." BGL.")
            dialogPages.addBalanceForm(p,result)
        elseif state.view=="blacklist" then
            if page then dialogPages.blacklistView(p,page)
            else
                local item=assert(integer(clicked=="block" and d.item or clicked:match("^unblock_(%d+)$"),1,MAX_AMOUNT),"Item ID tidak valid.")
                tx(function()
                    if clicked=="block" then assert(getItem(item),"Item tidak ada."); q("INSERT OR IGNORE INTO market_blacklist(item) VALUES("..item..")")
                    else q("DELETE FROM market_blacklist WHERE item="..item) end
                    bump(); audit(uid(p),"blacklist_changed",item,clicked)
                end)
                dialogPages.blacklistView(p,state.page)
            end
        end
    end)
    return true
end

local lastPoll,cursor=0,0
local errorTimes,lastReturnCheck={},{}
local function poll()
    if not ready or not backendReady() or os.time()-lastPoll<5 then return end
    lastPoll=os.time()
    local rows=q("SELECT id FROM market_rentals WHERE (state='allocating' OR (state='active' AND expires<="..os.time()..")) AND id>"..cursor.." ORDER BY id LIMIT 20")
    if #rows==0 then cursor=0; return end
    for _,row in ipairs(rows) do
        cursor=row.id
        local ok,err=pcall(processRental,row.id)
        if not ok and os.time()-(errorTimes[row.id] or 0)>=60 then
            errorTimes[row.id]=os.time(); print("[rent] rental #"..row.id.." pending: "..tostring(err))
        end
    end
end
local function handleCommand(world,p,cmd)
    local c=tostring(cmd):match("^%s*/?(%S+)"); c=c and c:lower()
    if c~=COMMAND and c~=ADMIN_COMMAND then return false end
    if c==ADMIN_COMMAND and not isAdmin(p) then if p then tell(p,"`4Panel khusus Founder.") end; return true end
    guard(p,function()
        if c==ADMIN_COMMAND then adminHome(p) else claimReturns(p); home(p) end
    end)
    return true
end
local function install(name,fn,arg)
    if type(fn)~="function" then print("[rent] API tidak tersedia: "..name); return false end
    local ok,result=pcall(fn,arg)
    if not ok or result==false then print("[rent] Gagal memasang "..name..": "..tostring(result)); return false end
    return true
end
print("[rent] BOOT r3-founder /rent + /setrent | "..tostring(_VERSION))
local dialogOK=install("dialog",onPlayerDialogCallback,dialogHandler)
local commandOK=install("command",onPlayerCommandCallback,handleCommand)
local inputOK=install("input",onPlayerActionCallback,function(w,p,d)
    if type(d)~="table" or d.action~="input" or type(d.text)~="string" or not d.text:match("^%s*/%S+") then return false end
    return handleCommand(w,p,d.text)
end)
local publicOK=install("/rent",registerLuaCommand,{command=COMMAND,roleRequired=0,description="Pasar rental pemain.",callback=function(p) return handleCommand(nil,p,COMMAND) end})
local adminOK=install("/setrent",registerLuaCommand,{command=ADMIN_COMMAND,roleRequired=1000,exactRole=true,description="Founder: blacklist item dan tambah saldo rental.",callback=function(p) return handleCommand(nil,p,ADMIN_COMMAND) end})
print("[rent] ROUTES r3-founder /rent="..tostring(publicOK).." /setrent="..tostring(adminOK)
    .." command="..tostring(commandOK).." input="..tostring(inputOK).." dialog="..tostring(dialogOK))
local tickOK=install("tick",onTick,function()
    local ok,err=pcall(poll); if not ok then print("[rent] Scheduler: "..tostring(err)) end
end)
install("login",onPlayerLoginCallback,function(p) guard(p,function() claimReturns(p) end) end)
install("player tick",onPlayerTick,function(p)
    if not ready or not p or not p:isOnline() then return end
    local id=uid(p)
    if os.time()-(lastReturnCheck[id] or 0)<30 then return end
    lastReturnCheck[id]=os.time()
    guard(p,function() claimReturns(p) end)
end)
install("disconnect",onPlayerDisconnectCallback,function(p)
    if p then local id=uid(p); sessions[id],busy[id],lastReturnCheck[id]=nil,nil,nil end
end)
ready,initError=pcall(function()
    assert(dialogOK and tickOK and (commandOK or inputOK or (publicOK and adminOK)),"API dialog/tick/command wajib tidak tersedia.")
    initialize()
end)
print(ready and ("[rent] Loaded /rent + /setrent. Native rental="..tostring(backendReady())) or ("[rent] INIT FAILED: "..tostring(initError)))
