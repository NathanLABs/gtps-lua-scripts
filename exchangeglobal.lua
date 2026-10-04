-- Developer: Nathan
-- exchangeglobal.lua - Public: /exchange2; Founder: /setexchange2.
-- Harga/resep/buff tidak ditebak. Tambahkan melalui panel Founder di game.
-- Fish meneruskan /sellfish; API multiplier di akhir file untuk integrasi script Fish.
local COMMAND, ADMIN_COMMAND, ADMIN_ROLE = "exchange2", "setexchange2", 1000
local DB_FILE = "exchangeglobal_v1.db"
local MAX_AMOUNT, MAX_BATCHES, PAGE_SIZE = 2000000000, 1000000, 5
local WIB_OFFSET, DIALOG_SECONDS = 25200, 120
local CATEGORIES = {
    {id="fish", name="SELL FISH", icon=3000, description="Sell your fish item for lock!"},
    {id="ghost", name="SELL GHOST", icon=21264, description="Sell your ghost item for lock!"},
    {id="geiger", name="SELL GEIGER", icon=2204, description="Sell your geiger item for lock!"},
    {id="provider", name="SELL PROVIDER", icon=3044, description="Sell your provider item for lock!"},
}
local categories={}
for _,c in ipairs(CATEGORIES) do categories[c.id]=c end
local db,ready,generation
local serial,sessions,busy=0,{},{}
local function int(v,lo,hi)
    if type(v)=="string" and not v:match("^%d+$") then return nil end
    local n=tonumber(v)
    return n and n==n and n>=lo and n<=hi and n==math.floor(n) and n or nil
end
local function num(n) return string.format("%.0f",n) end
local function clean(s,n) return tostring(s or ""):gsub("`.",""):gsub("[|%c]"," "):sub(1,n or 60) end
local function sql(s) return "'"..tostring(s):gsub("%z",""):gsub("'","''").."'" end
local function fmt(n) return num(n):reverse():gsub("(%d%d%d)","%1."):reverse():gsub("^%.","") end
local function q(s) local rows=db:query(s); assert(type(rows)=="table","Database exchange gagal diakses."); return rows end
local function tx(fn)
    q("BEGIN IMMEDIATE")
    local ok,result=pcall(fn)
    if ok then ok,result=pcall(function() q("COMMIT"); return result end) end
    if not ok then pcall(function() q("ROLLBACK") end); error(result) end
    return result
end
local function id(p) return assert(int(p:getUserID(),1,MAX_AMOUNT),"ID player tidak valid.") end
local function admin(p) return p and p:isOnline() and p:getRole()==ADMIN_ROLE end
local function tell(p,s) p:onConsoleMessage("`6[Exchange]`` "..s) end
local function itemName(item) local it=getItem(item); return it and clean(it:getName(),40) or ("Item #"..item) end
local function day() return math.floor((os.time()+WIB_OFFSET)/86400) end
local function wibDate() return os.date("!%Y-%m-%d",os.time()+WIB_OFFSET) end
local function cfg(key) local row=q("SELECT value FROM ex_config WHERE key="..sql(key))[1]; return assert(row,"Konfigurasi tidak ada").value end
local function revision() return cfg("revision") end
local function bump() q("UPDATE ex_config SET value=value+1 WHERE key='revision'") end
local function category(key) return q("SELECT * FROM ex_categories WHERE id="..sql(key))[1] end
local function audit(p,event,detail)
    q("INSERT INTO ex_audit(actor,event,detail,at) VALUES("..id(p)..","..sql(event)..","..sql(clean(detail,200))..","..os.time()..")")
end
local function mutate(p,event,fn)
    assert(admin(p),"Panel ini khusus Founder.")
    tx(function() fn(); bump(); audit(p,event,"Konfigurasi exchange diperbarui") end)
end
local function held(uid) return q("SELECT id FROM ex_journal WHERE actor="..uid.." AND status='pending' LIMIT 1")[1] end
local function usage(uid,recipe,today)
    local row=q("SELECT amount FROM ex_daily WHERE actor="..uid.." AND recipe="..recipe.." AND day="..today)[1]
    return row and row.amount or 0
end
local function totalUsage(uid,rid)
    return q("SELECT COALESCE(SUM(batches),0) AS amount FROM ex_journal WHERE actor="..uid.." AND recipe="..rid.." AND status IN ('done','pending')")[1].amount
end
local function recipe(rid)
    local r=q("SELECT * FROM ex_recipes WHERE id="..rid)[1]
    if r then r.inputs=q("SELECT item,amount FROM ex_inputs WHERE recipe="..rid.." ORDER BY item") end
    return r
end
local function quantity(raw,max)
    local s=tostring(raw or ""):lower():match("^%s*(.-)%s*$")
    if s=="all" or s=="max" then return int(max,1,MAX_BATCHES) end
    return s:match("^%d+$") and int(s,1,MAX_BATCHES) or nil
end
local function factor(raw)
    local s=tostring(raw or ""):gsub(",",".")
    assert(s:match("^%d+$") or s:match("^%d+%.%d%d?$") ,"Multiplier: 1 sampai 10, maksimal 2 desimal.")
    local n=tonumber(s)*100
    return assert(int(math.floor(n+0.5),100,1000),"Multiplier harus 1 sampai 10.")
end
local function factorText(n) return string.format("%.2f",n/100):gsub("0+$",""):gsub("%.$","") end
local function multiply(base,numerator)
    -- Batasi sebelum mengalikan: setiap hasil antara tetap integer tepat (<2^53).
    assert(base<=math.floor(MAX_AMOUNT*1000000/numerator),"Reward melebihi batas. Kurangi jumlah batch.")
    return math.floor(base*numerator/1000000)
end
local function previewReward(base,numerator)
    if base>math.floor(MAX_AMOUNT*1000000/numerator) then return "melewati batas reward" end
    return fmt(multiply(base,numerator))
end
local function multipliers(p,cat)
    local clothes,global,event=100,100,100
    local clothingName="Tanpa set bonus"
    if cfg("buffs")==1 then
        for _,b in ipairs(q("SELECT * FROM ex_buffs WHERE enabled=1 AND (category='all' OR category="..sql(cat)..") ORDER BY factor DESC,id")) do
            local slots=q("SELECT slot,item FROM ex_clothes WHERE buff="..b.id)
            local matches=#slots>0
            for _,s in ipairs(slots) do if p:getClothingItemID(s.slot)~=s.item then matches=false end end
            if matches then clothes=b.factor; clothingName=b.name; break end
        end
    end
    if cfg("events")==1 then
        local now=os.time()
        for _,e in ipairs(q("SELECT * FROM ex_events WHERE enabled=1 AND start_at<="..now.." AND (end_at=0 OR end_at>"..now..") AND (category='all' OR category="..sql(cat)..")")) do
            local active=e.mode=="manual"
            if e.mode=="server" then active=type(getCurrentServerEvent)=="function" and getCurrentServerEvent()==e.event_id end
            if e.mode=="daily" then active=type(getCurrentServerDailyEvent)=="function" and getCurrentServerDailyEvent()==e.event_id end
            if active then
                if e.category=="all" then global=math.max(global,e.factor) else event=math.max(event,e.factor) end
            end
        end
    end
    return math.min(clothes*global*event,100000000), {clothes=clothes,global=global,event=event,name=clothingName}
end
local function sourceAmount(p,item,source)
    return assert(int(source=="extra" and p:getExtraBackpackAmount(item) or p:getItemAmount(item),0,MAX_AMOUNT),"Jumlah item tidak valid.")
end
local function buildQuote(p,rid,direction,batches,source)
    assert(cfg("enabled")==1,"Exchange sedang dinonaktifkan.")
    assert(not held(id(p)),"Ada transaksi pending. Hubungi pengelola; jangan mengulang transaksi.")
    local r=assert(recipe(rid),"Resep tidak ditemukan.")
    assert(categories[r.category] and r.category~="fish","Kategori resep ini tidak tersedia.")
    assert(r.enabled==1 and category(r.category).enabled==1,"Kategori/resep sedang dinonaktifkan.")
    assert(r.expires_at==0 or os.time()<r.expires_at,"Duration exchange sudah habis.")
    assert(source=="inventory" or source=="extra","Sumber item tidak valid.")
    assert(direction=="sell" or direction=="buy","Arah transaksi tidak valid.")
    local numerator,parts=1000000,{clothes=100,global=100,event=100,name="Tidak berlaku untuk BUY"}
    local costs,rewardItem,rewardPer={}
    if direction=="sell" then
        assert(r.sell_amount>0,"SELL tidak tersedia untuk resep ini.")
        costs=r.inputs; rewardItem=r.reward; rewardPer=r.sell_amount
        numerator,parts=multipliers(p,r.category)
    else
        assert(cfg("buy")==1 and r.buy_amount>0 and #r.inputs==1,"BUY tidak tersedia.")
        costs={{item=r.reward,amount=r.buy_amount}}; rewardItem=r.inputs[1].item; rewardPer=r.inputs[1].amount
    end
    assert(#costs>0,"Resep tidak memiliki bahan.")
    local maximum=MAX_BATCHES
    for _,c in ipairs(costs) do
        assert(getItem(c.item),"Item bahan #"..c.item.." tidak tersedia.")
        maximum=math.min(maximum,math.floor(sourceAmount(p,c.item,source)/c.amount))
    end
    assert(getItem(rewardItem),"Item reward tidak tersedia.")
    local room=MAX_AMOUNT-p:getItemAmount(rewardItem)-p:getExtraBackpackAmount(rewardItem)
    maximum=math.min(maximum,math.floor(math.max(0,room)*1000000/numerator/rewardPer))
    local today=day()
    local used=usage(id(p),rid,today)
    if r.daily_limit>0 then maximum=math.min(maximum,math.max(0,r.daily_limit-used)) end
    if r.exchange_limit>0 then maximum=math.min(maximum,math.max(0,r.exchange_limit-totalUsage(id(p),rid))) end
    local count=assert(quantity(batches,maximum),"Isi jumlah batch bulat 1-1.000.000 atau all/max.")
    assert(count<=maximum,"Bahan, ruang reward, atau sisa limit exchange tidak cukup.")
    local legs={}
    for _,c in ipairs(costs) do legs[#legs+1]={item=c.item,amount=c.amount*count,source=source,kind="take"} end
    assert(rewardPer<=math.floor(MAX_AMOUNT/count),"Total reward terlalu besar.")
    local payout=multiply(rewardPer*count,numerator)
    assert(payout>0,"Reward harus lebih dari nol.")
    legs[#legs+1]={item=rewardItem,amount=payout,source="all",kind="give"}
    return {actor=id(p),recipe=rid,name=r.name,category=r.category,direction=direction,count=count,source=source,
        numerator=numerator,parts=parts,legs=legs,payout=payout,reward=rewardItem,day=today,used=used,limit=r.daily_limit,
        totalLimit=r.exchange_limit,expiresAt=r.expires_at,revision=revision()}
end
local function execute(p,quote)
    assert(quote.actor==id(p),"Akun tidak sesuai.")
    assert(quote.revision==revision() and quote.day==day(),"Harga/konfigurasi atau hari WIB berubah. Buka ulang konfirmasi.")
    local current=buildQuote(p,quote.recipe,quote.direction,tostring(quote.count),quote.source)
    assert(current.numerator==quote.numerator and current.payout==quote.payout,"Event atau pakaian berubah. Periksa harga terbaru.")
    local journal
    tx(function()
        assert(not held(id(p)),"Akun memiliki transaksi pending.")
        assert(current.expiresAt==0 or os.time()<current.expiresAt,"Duration exchange sudah habis.")
        if current.totalLimit>0 then assert(totalUsage(id(p),quote.recipe)+quote.count<=current.totalLimit,"Limit exchange habis.") end
        q("INSERT INTO ex_journal(actor,recipe,kind,batches,reward,amount,multiplier,day,status,at) VALUES("..id(p)..","..quote.recipe..","..sql(quote.direction)..","..quote.count..","..quote.reward..","..quote.payout..","..quote.numerator..","..quote.day..",'pending',"..os.time()..")")
        journal=q("SELECT last_insert_rowid() AS id")[1].id
        if quote.limit>0 then
            assert(usage(id(p),quote.recipe,quote.day)+quote.count<=quote.limit,"Kuota harian habis.")
            q("INSERT OR IGNORE INTO ex_daily(actor,recipe,day,amount) VALUES("..id(p)..","..quote.recipe..","..quote.day..",0)")
            q("UPDATE ex_daily SET amount=amount+"..quote.count.." WHERE actor="..id(p).." AND recipe="..quote.recipe.." AND day="..quote.day)
        end
        for i,l in ipairs(current.legs) do
            l.beforeInv=p:getItemAmount(l.item); l.beforeExtra=p:getExtraBackpackAmount(l.item)
            q("INSERT INTO ex_legs(journal,seq,item,kind,amount,source,before_inv,before_extra) VALUES("..journal..","..i..","..l.item..","..sql(l.kind)..","..l.amount..","..sql(l.source)..","..l.beforeInv..","..l.beforeExtra..")")
        end
    end)
    local ok,err=pcall(function()
        for i,l in ipairs(current.legs) do
            if l.kind=="give" then
                assert(p:giveItem(l.item,l.amount)==true,"Pemberian reward ditolak engine.")
                assert(p:getItemAmount(l.item)+p:getExtraBackpackAmount(l.item)==l.beforeInv+l.beforeExtra+l.amount,"Jumlah reward tidak sesuai.")
            elseif l.source=="extra" then
                assert(p:takeFromExtraBackpack(l.item,l.amount)==l.amount,"Pengambilan Extra Backpack tidak sesuai.")
                assert(p:getExtraBackpackAmount(l.item)==l.beforeExtra-l.amount and p:getItemAmount(l.item)==l.beforeInv,"Perubahan bahan tidak sesuai.")
            else
                assert(p:changeItem(l.item,-l.amount)==true,"Pengambilan bahan ditolak engine.")
                assert(p:getItemAmount(l.item)==l.beforeInv-l.amount and p:getExtraBackpackAmount(l.item)==l.beforeExtra,"Perubahan bahan tidak sesuai.")
            end
            q("UPDATE ex_legs SET after_inv="..p:getItemAmount(l.item)..",after_extra="..p:getExtraBackpackAmount(l.item).." WHERE journal="..journal.." AND seq="..i)
        end
        tx(function() q("UPDATE ex_journal SET status='done' WHERE id="..journal) end)
    end)
    if not ok then
        -- Hanya batalkan otomatis jika seluruh inventory/Extra identik dengan snapshot awal.
        local unchanged=true
        local readOK=pcall(function()
            for _,l in ipairs(current.legs) do
                if p:getItemAmount(l.item)~=l.beforeInv or p:getExtraBackpackAmount(l.item)~=l.beforeExtra then unchanged=false end
            end
        end)
        if readOK and unchanged then
            tx(function()
                q("UPDATE ex_journal SET status='cancelled' WHERE id="..journal)
                if quote.limit>0 then q("UPDATE ex_daily SET amount=amount-"..quote.count.." WHERE actor="..id(p).." AND recipe="..quote.recipe.." AND day="..quote.day) end
            end)
        end
        print("[exchangeglobal] journal="..journal.." "..tostring(err))
        error("Transaksi #"..journal..((readOK and unchanged) and " dibatalkan; aset tidak berubah." or " pending. Pengelola perlu memeriksa bahan/reward; jangan ulangi."))
    end
    return journal
end

-- UI native, tanpa embed_data dan tanpa nama server yang di-hardcode.
local function title() local s=clean(getServerName(),40):upper(); return (s~="" and s or "SERVER").." SELL" end
local function begin(text,icon)
    return {(icon and icon>0 and getItem(icon)) and ("add_label_with_icon|big|`w"..text.."``|left|"..icon.."|\n")
        or ("add_label|big|`w"..text.."``|left|\n"),"add_spacer|small|\n"}
end
local function line(L,s) L[#L+1]="add_smalltext|"..s.."|\n" end
local function button(L,key,text) L[#L+1]="add_button|"..key.."|"..text.."|noflags|0|0|\n" end
local function input(L,key,label,value,len) L[#L+1]="add_text_input|"..key.."|"..label.."|"..clean(value,len or 100).."|"..(len or 100).."|\n" end
local function check(L,key,label,on) L[#L+1]="add_checkbox|"..key.."|"..label.."|"..(on and 1 or 0).."|\n" end
local function show(p,L,state)
    serial=serial+1
    state.name="exchangeglobal_"..generation.."_"..serial
    state.expires=os.time()+DIALOG_SECONDS; state.revision=revision()
    state.buttons={}
    for _,s in ipairs(L) do local key=s:match("^add_button[^|]*|([^|]+)|"); if key and key~="" then state.buttons[key]=true end end
    L[#L+1]="add_spacer|small|\nadd_smalltext|`9© Dibuat Oleh : Nathan``|\n"
    L[#L+1]="end_dialog|"..state.name.."|Tutup||\n"
    local text=table.concat(L); assert(#text<4096,"Dialog terlalu besar.")
    sessions[id(p)]=state; p:onDialogRequest(text)
end
local function pageRows(rows,page,size)
    size=size or PAGE_SIZE
    local pages=math.max(1,math.ceil(#rows/size)); page=math.max(1,math.min(page or 1,pages))
    local result={}; for i=(page-1)*size+1,math.min(page*size,#rows) do result[#result+1]=rows[i] end
    return result,page,pages
end
local function pagination(L,page,pages)
    line(L,"Halaman "..page.." / "..pages)
    if page>1 then button(L,"page_"..(page-1),"Sebelumnya") end
    if page<pages then button(L,"page_"..(page+1),"Berikutnya") end
end
local function exchangeCard(p,L,r,editing)
    local numerator=editing and 1000000 or multipliers(p,r.category)
    local payout=r.sell_amount>0 and previewReward(r.sell_amount,numerator) or "OFF"
    L[#L+1]="add_spacer|small|\n"
    for index,c in ipairs(r.inputs) do
        local key=index==1 and ("recipe_"..r.id) or ("material_"..r.id.."_"..index)
        L[#L+1]="add_button_with_icon|"..key.."|`wFROM: "..fmt(c.amount).." "..itemName(c.item).."|staticYellowFrame|"..c.item.."||\n"
    end
    L[#L+1]="add_button_with_icon|reward_"..r.id.."|`2TO: "..payout.." "..itemName(r.reward).."|staticYellowFrame|"..r.reward.."||\n"
    L[#L+1]="add_button_with_icon||END_LIST|noflags|0||\n"
    local sources={}
    for _,c in ipairs(r.inputs) do sources[#sources+1]=fmt(c.amount).." "..itemName(c.item) end
    line(L,table.concat(sources," + ").." `4--> `2"..payout.." "..itemName(r.reward).."``")
    line(L,"Duration: "..(r.expires_at==0 and "`2Unlimited``" or (r.expires_at<=os.time() and "`4Expired``" or ("`w"..fmt(math.ceil((r.expires_at-os.time())/60)).." menit tersisa``"))))
    if editing then
        button(L,"edit_"..r.id,"Edit Exchange"..(r.enabled==0 and " [OFF]" or ""))
    else
        for _,c in ipairs(r.inputs) do line(L,"You have `w"..fmt(p:getItemAmount(c.item)).."/"..fmt(c.amount).."`` "..itemName(c.item)) end
        local limit=r.exchange_limit>0 and (fmt(math.max(0,r.exchange_limit-totalUsage(id(p),r.id))).." / "..fmt(r.exchange_limit).." per pemain") or "Unlimited"
        if r.daily_limit>0 then limit=limit.." / Harian: "..fmt(math.max(0,r.daily_limit-usage(id(p),r.id,day()))) end
        line(L,"Limit: `2"..limit.."``")
        if r.sell_amount>0 and (r.expires_at==0 or os.time()<r.expires_at) then button(L,"get_"..r.id,"GET!") end
    end
end
local home, listing, tradeForm, adminHome, recipeForm, buffForm, eventForm, logs
home=function(p)
    local L=begin(title(),21264)
    line(L,"Welcome to "..clean(getServerName(),40).." Sell. Jual item kamu dan dapatkan reward dari server!")
    line(L,"Tanggal "..wibDate().." WIB / Daily reset 00:00 WIB")
    if cfg("enabled")==0 then line(L,"`4Exchange sedang dinonaktifkan.``") end
    local hold=held(id(p)); if hold then line(L,"`4Transaksi #"..hold.id.." menunggu pemeriksaan pengelola.``") end
    for _,c in ipairs(CATEGORIES) do
        local row=category(c.id)
        L[#L+1]="add_spacer|small|\n"
        L[#L+1]=begin(c.name,c.icon)[1]
        line(L,c.description)
        button(L,"cat_"..c.id,row.enabled==1 and "GO TO EXCHANGE" or "EXCHANGE OFFLINE")
    end
    show(p,L,{view="home"})
end
listing=function(p,cat,page,editing)
    assert(categories[cat] and cat~="fish","Kategori ini memakai /sellfish.")
    if editing then assert(admin(p),"Founder only.") else assert(cfg("enabled")==1 and category(cat).enabled==1,"Kategori sedang dinonaktifkan.") end
    local allRows=q("SELECT *, (SELECT COUNT(*) FROM ex_inputs WHERE recipe=ex_recipes.id) AS input_count FROM ex_recipes WHERE category="..sql(cat)..(editing and "" or (" AND enabled=1 AND (expires_at=0 OR expires_at>"..os.time()..")")).." ORDER BY id")
    local cardPageSize=2
    -- Large legacy recipes retain all ingredients without overflowing native dialogs.
    for _,r in ipairs(allRows) do if r.input_count>3 then cardPageSize=1; break end end
    local rows,at,pages=pageRows(allRows,page,cardPageSize)
    local L=begin(categories[cat].name,categories[cat].icon)
    line(L,editing and "Tambahkan exchange, lalu isi item FROM dan TO." or "GET! untuk menukar satu kali. Klik ikon untuk mengatur jumlah atau Extra Backpack.")
    if #rows==0 then line(L,"Belum ada resep aktif. Pengelola dapat menambahnya melalui /"..ADMIN_COMMAND..".") end
    for _,r in ipairs(rows) do
        exchangeCard(p,L,recipe(r.id),editing)
    end
    pagination(L,at,pages)
    if editing then button(L,"new","+ Tambahkan Exchange"); button(L,"toggle_category",category(cat).enabled==1 and "Nonaktifkan Kategori" or "Aktifkan Kategori") end
    button(L,editing and "admin" or "home","Kembali")
    show(p,L,{view="listing",category=cat,editing=editing,page=at})
end
tradeForm=function(p,rid)
    local r=assert(recipe(rid),"Resep tidak ditemukan.")
    local L=begin(clean(r.name),r.reward)
    line(L,"Duration: "..(r.expires_at==0 and "Unlimited" or (fmt(math.max(0,math.ceil((r.expires_at-os.time())/60))).." menit tersisa")))
    line(L,"Limit Exchange: "..(r.exchange_limit>0 and (fmt(math.max(0,r.exchange_limit-totalUsage(id(p),rid))).." / "..fmt(r.exchange_limit).." per pemain") or "Unlimited"))
    line(L,"Bahan per batch:")
    for _,c in ipairs(r.inputs) do line(L,fmt(c.amount).." "..itemName(c.item).." / Backpack "..fmt(p:getItemAmount(c.item)).." / Extra "..fmt(p:getExtraBackpackAmount(c.item))) end
    local numerator,parts=multipliers(p,r.category)
    line(L,"SELL dasar: "..fmt(r.sell_amount).." "..itemName(r.reward).." / batch")
    if r.sell_amount>0 then line(L,"SELL sekarang: `2"..previewReward(r.sell_amount,numerator).." "..itemName(r.reward).."`` / batch") end
    line(L,"Clothing x"..factorText(parts.clothes).." / Event x"..factorText(parts.global).." / Kategori x"..factorText(parts.event))
    line(L,"Set: "..clean(parts.name).." / Gabungan maksimum x100; pecahan dibulatkan ke bawah pada total order.")
    if r.buy_amount>0 then line(L,"BUY: "..fmt(r.buy_amount).." "..itemName(r.reward).." / batch. Bonus hanya untuk SELL.") end
    if r.daily_limit>0 then line(L,"Sisa kuota "..wibDate().." WIB: "..math.max(0,r.daily_limit-usage(id(p),rid,day())).." batch (SELL + BUY)") end
    input(L,"amount","Jumlah batch / all / max","1",20)
    check(L,"extra","Ambil bahan/pembayaran dari Extra Backpack",false)
    if r.sell_amount>0 then button(L,"sell","SELL / EXCHANGE") end
    if r.buy_amount>0 and cfg("buy")==1 then button(L,"buy","BUY") end
    button(L,"back","Kembali ke Kategori")
    show(p,L,{view="trade",recipe=rid,category=r.category})
end
local function review(p,state,data,kind)
    local quote=buildQuote(p,state.recipe,kind,data.amount,tostring(data.extra)=="1" and "extra" or "inventory")
    local L=begin("KONFIRMASI EXCHANGE",quote.reward)
    line(L,"`w"..clean(quote.name).." / "..kind:upper().." / "..fmt(quote.count).." batch``")
    for _,l in ipairs(quote.legs) do line(L,(l.kind=="take" and "`4Bayar: " or "`2Terima: ")..fmt(l.amount).." "..itemName(l.item).."``") end
    line(L,"Sumber: "..(quote.source=="extra" and "Extra Backpack" or "Backpack"))
    line(L,"Harga dan bonus diperiksa lagi saat konfirmasi. Reward dapat masuk Extra Backpack.")
    button(L,"confirm","KONFIRMASI")
    button(L,"back","Batal")
    show(p,L,{view="confirm",quote=quote,recipe=quote.recipe,quick=state.quick,page=state.page,category=quote.category})
end
adminHome=function(p)
    assert(admin(p),"Panel khusus Founder.")
    local L=begin("PENGATURAN EXCHANGE",21264)
    line(L,"Pilih kategori untuk mengatur item dan harga exchange.")
    for _,entry in ipairs({{"provider","Provider"},{"geiger","Geiger"},{"ghost","Ghost"}}) do
        button(L,"manage_"..entry[1],"Edit "..entry[2])
    end
    show(p,L,{view="admin"})
end
local function parsePairs(raw,clothing)
    raw=tostring(raw or ""):gsub("%s","")
    assert(#raw>0 and #raw<=240 and not raw:match(",$"),"Isi pasangan angka, contoh 242:100,1796:1.")
    local result,seen={},{}
    for part in (raw..","):gmatch("(.-),") do
        local a,b=part:match("^(%d+):(%d+)$")
        a=int(a,clothing and 0 or 1,clothing and 9 or MAX_AMOUNT)
        b=int(b,1,MAX_AMOUNT)
        assert(a and b and not seen[a],"Bahan/slot tidak valid atau duplikat.")
        assert(getItem(clothing and b or a),"ID item tidak ditemukan.")
        seen[a]=true; result[#result+1]={a=a,b=b}
    end
    assert(#result<=(clothing and 10 or 6),"Maksimal 6 bahan atau 10 slot pakaian.")
    return result
end
recipeForm=function(p,cat,rid)
    assert(admin(p),"Founder only.")
    local r=rid and assert(recipe(rid),"Resep tidak ditemukan.") or {inputs={},reward=7188,sell_amount=1,duration_minutes=0,exchange_limit=0}
    assert(categories[cat] and cat~="fish" and (not rid or r.category==cat),"Kategori tidak valid.")
    local source=r.inputs[1] or {item="",amount=1}
    local L=begin("EXCHANGE")
    L[#L+1]="add_label|small|`wFROM:``|left|\n"
    input(L,"from_item","ItemID",source.item,10)
    input(L,"from_amount","Amount",source.amount,10)
    L[#L+1]="add_spacer|small|\nadd_label|small|`wTO:``|left|\n"
    input(L,"to_item","ItemID",r.reward,10)
    input(L,"to_amount","Amount",r.sell_amount,10)
    L[#L+1]="add_spacer|small|\n"
    input(L,"duration","Duration (menit, 0 = Unlimited)",r.duration_minutes,6)
    input(L,"limit","Limit Exchange per pemain (0 = Unlimited)",r.exchange_limit,10)
    if #r.inputs>1 then
        line(L,"Resep lama: bahan tambahan berikut tetap dipertahankan.")
        for i=2,#r.inputs do line(L,fmt(r.inputs[i].amount).." "..itemName(r.inputs[i].item).." (#"..r.inputs[i].item..")") end
    end
    button(L,"save_recipe","Simpan Exchange")
    button(L,"back","Kembali")
    show(p,L,{view="recipe_edit",category=cat,recipe=rid})
end
local function saveRecipe(p,state,d)
    local from=assert(int(d.from_item,1,MAX_AMOUNT),"FROM ItemID tidak valid.")
    local amount=assert(int(d.from_amount,1,MAX_AMOUNT),"FROM Amount harus angka bulat positif.")
    local reward=assert(int(d.to_item,1,MAX_AMOUNT),"TO ItemID tidak valid.")
    local sell=assert(int(d.to_amount,1,MAX_AMOUNT),"TO Amount harus angka bulat positif.")
    assert(getItem(from) and getItem(reward),"ItemID FROM/TO tidak ditemukan.")
    local old=state.recipe and assert(recipe(state.recipe),"Resep tidak ditemukan.")
    local duration=assert(int(d.duration,0,525600),"Duration: 0 sampai 525600 menit.")
    local exchangeLimit=assert(int(d.limit,0,MAX_AMOUNT),"Limit Exchange harus angka bulat 0 sampai 2.000.000.000.")
    local expires=0
    if duration>0 then
        expires=old and old.duration_minutes==duration and old.expires_at>os.time() and old.expires_at or os.time()+duration*60
    end
    local inputs={{a=from,b=amount}}
    if old then
        for i=2,#old.inputs do
            assert(old.inputs[i].item~=from,"FROM sama dengan bahan tambahan resep lama.")
            inputs[#inputs+1]={a=old.inputs[i].item,b=old.inputs[i].amount}
        end
    end
    for _,c in ipairs(inputs) do assert(c.a~=reward,"Item reward tidak boleh menjadi bahan resep yang sama.") end
    local name=clean(itemName(from).." -> "..itemName(reward),50)
    local buy,quota,active=old and old.buy_amount or 0,old and old.daily_limit or 0,old and old.enabled or 1
    mutate(p,"recipe_saved",function()
        local rid=state.recipe
        if not rid then
            q("INSERT INTO ex_recipes(category,name,reward,sell_amount,buy_amount,daily_limit,enabled,duration_minutes,expires_at,exchange_limit) VALUES("..sql(state.category)..","..sql(name)..","..reward..","..sell..","..buy..","..quota..","..active..","..duration..","..expires..","..exchangeLimit..")")
            rid=q("SELECT last_insert_rowid() AS id")[1].id
        else
            assert(recipe(rid).category==state.category,"Kategori resep berubah.")
            q("UPDATE ex_recipes SET name="..sql(name)..",reward="..reward..",sell_amount="..sell..",buy_amount="..buy..",daily_limit="..quota..",enabled="..active..",duration_minutes="..duration..",expires_at="..expires..",exchange_limit="..exchangeLimit.." WHERE id="..rid)
            q("DELETE FROM ex_inputs WHERE recipe="..rid)
        end
        for _,c in ipairs(inputs) do q("INSERT INTO ex_inputs(recipe,item,amount) VALUES("..rid..","..c.a..","..c.b..")") end
    end)
    tell(p,"`2Exchange berhasil disimpan.")
    listing(p,state.category,1,true)
end
local function configList(p,kind,page)
    assert(admin(p),"Founder only.")
    local rows,at,pages=pageRows(q("SELECT * FROM ex_"..kind.." ORDER BY id"),page)
    local L=begin(kind=="buffs" and "CLOTHING BUFFS" or "EVENT MULTIPLIER")
    if #rows==0 then line(L,"Belum ada konfigurasi. Tambahkan menggunakan tombol di bawah.") end
    for _,r in ipairs(rows) do
        line(L,"#"..r.id.." "..clean(r.name).." / "..r.category.." / x"..factorText(r.factor).." ["..(r.enabled==1 and "ON" or "OFF").."]")
        button(L,"edit_"..r.id,"Edit")
    end
    pagination(L,at,pages); button(L,"new","+ Tambah"); button(L,"admin","Kembali")
    show(p,L,{view="config_list",kind=kind,page=at})
end
buffForm=function(p,bid)
    assert(admin(p),"Founder only.")
    local b=bid and assert(q("SELECT * FROM ex_buffs WHERE id="..bid)[1],"Buff tidak ada") or {name="",category="all",factor=100,enabled=1}
    local parts={}
    if bid then for _,s in ipairs(q("SELECT * FROM ex_clothes WHERE buff="..bid.." ORDER BY slot")) do parts[#parts+1]=s.slot..":"..s.item end end
    local L=begin("CLOTHING SET / MULTIPLIER")
    input(L,"name","Nama set",b.name,50); input(L,"category","Kategori (all atau kode kategori)",b.category,12)
    line(L,"Kategori: all, fish, ghost, geiger, provider.")
    input(L,"factor","Multiplier (1 - 10)",factorText(b.factor),5)
    input(L,"slots","Pakaian wajib (slot:ID,slot:ID)",table.concat(parts,","),180)
    line(L,"Slot: 0 hair, 1 shirt, 2 pants, 3 feet, 4 face, 5 hand, 6 back, 7 mask, 8 necklace, 9 ances.")
    line(L,"Semua slot harus dipakai. Jika beberapa set cocok, gunakan bonus tertinggi; tidak ditumpuk.")
    check(L,"active","Aktif",b.enabled==1)
    button(L,"save_buff","Simpan Set"); button(L,"back","Kembali")
    show(p,L,{view="buff_edit",record=bid})
end
eventForm=function(p,eid)
    assert(admin(p),"Founder only.")
    local e=eid and assert(q("SELECT * FROM ex_events WHERE id="..eid)[1],"Event tidak ada") or {name="",category="all",factor=100,enabled=1,mode="manual",event_id=0,end_at=0}
    local L=begin("EVENT SELL MULTIPLIER")
    input(L,"name","Nama event",e.name,50); input(L,"category","Kategori (all atau kode kategori)",e.category,12)
    line(L,"all = Event global. fish = Event Sellfish. Hasil: clothing x global x kategori, maksimum x100.")
    input(L,"factor","Multiplier (1 - 10)",factorText(e.factor),5)
    input(L,"mode","Mode: manual / server / daily",e.mode,10)
    input(L,"native_id","ID event engine (manual isi 0)",e.event_id,8)
    line(L,"Server: 3 Halloween, 4 Comet, 5 Harvest. Daily: 40 Geiger, 42 Surgery. Dicek saat transaksi.")
    input(L,"minutes","Durasi sejak Save (menit; 0 = tanpa akhir)",0,6)
    if eid then line(L,"Batas saat ini: "..(e.end_at==0 and "Tanpa akhir" or os.date("!%Y-%m-%d %H:%M WIB",e.end_at+WIB_OFFSET))) end
    line(L,"Save memulai ulang durasi. Pada scope sama, hanya event aktif dengan multiplier tertinggi yang berlaku.")
    check(L,"active","Aktif",e.enabled==1)
    button(L,"save_event","Simpan Event"); button(L,"back","Kembali")
    show(p,L,{view="event_edit",record=eid})
end
local function saveBuff(p,state,d)
    local name=clean(d.name,50); assert(name:match("%S"),"Nama set wajib diisi.")
    local cat=tostring(d.category or ""):lower(); assert(cat=="all" or categories[cat],"Kategori tidak valid.")
    local f=factor(d.factor); local slots=parsePairs(d.slots,true); local active=tostring(d.active)=="1" and 1 or 0
    mutate(p,"buff_saved",function()
        local bid=state.record
        if bid then
            q("UPDATE ex_buffs SET name="..sql(name)..",category="..sql(cat)..",factor="..f..",enabled="..active.." WHERE id="..bid)
            q("DELETE FROM ex_clothes WHERE buff="..bid)
        else
            q("INSERT INTO ex_buffs(name,category,factor,enabled) VALUES("..sql(name)..","..sql(cat)..","..f..","..active..")")
            bid=q("SELECT last_insert_rowid() AS id")[1].id
        end
        for _,s in ipairs(slots) do q("INSERT INTO ex_clothes(buff,slot,item) VALUES("..bid..","..s.a..","..s.b..")") end
    end)
    configList(p,"buffs",1)
end
local function saveEvent(p,state,d)
    local name=clean(d.name,50); assert(name:match("%S"),"Nama event wajib diisi.")
    local cat=tostring(d.category or ""):lower(); assert(cat=="all" or categories[cat],"Kategori tidak valid.")
    local mode=tostring(d.mode or ""):lower(); assert(mode=="manual" or mode=="server" or mode=="daily","Mode tidak valid.")
    local native=assert(int(d.native_id,0,MAX_AMOUNT),"ID event tidak valid.")
    if mode~="manual" then assert(native>0,"ID event engine wajib positif.") end
    local minutes=assert(int(d.minutes,0,525600),"Durasi maksimal 1 tahun.")
    local f=factor(d.factor); local active=tostring(d.active)=="1" and 1 or 0
    local ends=minutes==0 and 0 or os.time()+minutes*60
    mutate(p,"event_saved",function()
        local values="name="..sql(name)..",category="..sql(cat)..",factor="..f..",enabled="..active..",mode="..sql(mode)..",event_id="..native..",start_at="..os.time()..",end_at="..ends
        if state.record then q("UPDATE ex_events SET "..values.." WHERE id="..state.record)
        else q("INSERT INTO ex_events(name,category,factor,enabled,mode,event_id,start_at,end_at) VALUES("..sql(name)..","..sql(cat)..","..f..","..active..","..sql(mode)..","..native..","..os.time()..","..ends..")") end
    end)
    configList(p,"events",1)
end
logs=function(p,page,editing,pendingOnly,securityLog)
    if editing then assert(admin(p),"Founder only.") end
    securityLog=editing and securityLog or false
    local tab=securityLog and "ex_audit" or "ex_journal"
    local filter=editing and " WHERE 1=1" or (" WHERE actor="..id(p))
    if pendingOnly and not securityLog then filter=filter.." AND status='pending'" end
    local count=q("SELECT COUNT(*) AS n FROM "..tab..filter)[1].n
    local pages=math.max(1,math.ceil(count/PAGE_SIZE)); page=math.max(1,math.min(page or 1,pages))
    local rows=q("SELECT * FROM "..tab..filter.." ORDER BY id DESC LIMIT "..PAGE_SIZE.." OFFSET "..((page-1)*PAGE_SIZE))
    local L=begin(editing and "ADMIN EXCHANGE LOGS" or "RIWAYAT EXCHANGE")
    if #rows==0 then line(L,"Belum ada catatan.") end
    for _,r in ipairs(rows) do
        if securityLog then line(L,"#"..r.id.." / Akun #"..r.actor.." / "..clean(r.event))
        else
            line(L,"#"..r.id.." / "..r.kind:upper().." / "..r.batches.." batch / "..r.status)
            line(L,"Akun #"..r.actor.." / Reward "..fmt(r.amount).." "..itemName(r.reward).." / Resep #"..r.recipe)
        end
        line(L,os.date("!%Y-%m-%d %H:%M:%S WIB",r.at+WIB_OFFSET))
    end
    pagination(L,page,pages)
    if editing then button(L,"pending",pendingOnly and "Semua Transaksi" or "Hanya Pending"); button(L,"audit",securityLog and "Log Transaksi" or "Log Perubahan Admin") end
    button(L,editing and "admin" or "home","Kembali")
    show(p,L,{view="logs",editing=editing,page=page,pending=pendingOnly,securityLog=securityLog})
end
local function guard(p,fn)
    if not p or not p:isOnline() then return end
    if not ready then tell(p,"`4Exchange belum tersedia. Periksa log server."); return end
    local uid=id(p); if busy[uid] then return end
    busy[uid]=true; local ok,err=pcall(fn); busy[uid]=nil
    if not ok then
        sessions[uid]=nil
        tell(p,"`4"..clean(tostring(err):gsub("^.-:%d+:%s*",""),220))
        print("[exchangeglobal] uid="..uid.." "..tostring(err))
        pcall(home,p)
    end
end
local function dispatchFish(world,p)
    assert(cfg("enabled")==1 and category("fish").enabled==1,"Kategori Fish sedang dinonaktifkan.")
    assert(world,"Masuk world terlebih dahulu.")
    assert(world:sendPlayerMessage(p,"/sellfish")~=false,"Command /sellfish tidak tersedia.")
end

local initialized,initError=pcall(function()
    db=assert(sqlite.open(DB_FILE),"Database exchange tidak dapat dibuka.")
    q("PRAGMA synchronous=FULL")
    q("CREATE TABLE IF NOT EXISTS ex_config(key TEXT PRIMARY KEY,value INTEGER NOT NULL)")
    q("CREATE TABLE IF NOT EXISTS ex_categories(id TEXT PRIMARY KEY,enabled INTEGER NOT NULL DEFAULT 1)")
    q("CREATE TABLE IF NOT EXISTS ex_recipes(id INTEGER PRIMARY KEY AUTOINCREMENT,category TEXT NOT NULL,name TEXT NOT NULL,reward INTEGER NOT NULL,sell_amount INTEGER NOT NULL,buy_amount INTEGER NOT NULL,daily_limit INTEGER NOT NULL,enabled INTEGER NOT NULL)")
    q("CREATE TABLE IF NOT EXISTS ex_inputs(recipe INTEGER NOT NULL,item INTEGER NOT NULL,amount INTEGER NOT NULL,PRIMARY KEY(recipe,item))")
    q("CREATE TABLE IF NOT EXISTS ex_daily(actor INTEGER NOT NULL,recipe INTEGER NOT NULL,day INTEGER NOT NULL,amount INTEGER NOT NULL CHECK(amount>=0),PRIMARY KEY(actor,recipe,day))")
    q("CREATE TABLE IF NOT EXISTS ex_buffs(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,category TEXT NOT NULL,factor INTEGER NOT NULL,enabled INTEGER NOT NULL)")
    q("CREATE TABLE IF NOT EXISTS ex_clothes(buff INTEGER NOT NULL,slot INTEGER NOT NULL,item INTEGER NOT NULL,PRIMARY KEY(buff,slot))")
    q("CREATE TABLE IF NOT EXISTS ex_events(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,category TEXT NOT NULL,factor INTEGER NOT NULL,enabled INTEGER NOT NULL,mode TEXT NOT NULL,event_id INTEGER NOT NULL,start_at INTEGER NOT NULL,end_at INTEGER NOT NULL)")
    q("CREATE TABLE IF NOT EXISTS ex_journal(id INTEGER PRIMARY KEY AUTOINCREMENT,actor INTEGER NOT NULL,recipe INTEGER NOT NULL,kind TEXT NOT NULL,batches INTEGER NOT NULL,reward INTEGER NOT NULL,amount INTEGER NOT NULL,multiplier INTEGER NOT NULL,day INTEGER NOT NULL,status TEXT NOT NULL,at INTEGER NOT NULL)")
    q("CREATE TABLE IF NOT EXISTS ex_legs(journal INTEGER NOT NULL,seq INTEGER NOT NULL,item INTEGER NOT NULL,kind TEXT NOT NULL,amount INTEGER NOT NULL,source TEXT NOT NULL,before_inv INTEGER NOT NULL,before_extra INTEGER NOT NULL,after_inv INTEGER,after_extra INTEGER,PRIMARY KEY(journal,seq))")
    q("CREATE TABLE IF NOT EXISTS ex_audit(id INTEGER PRIMARY KEY AUTOINCREMENT,actor INTEGER NOT NULL,event TEXT NOT NULL,detail TEXT NOT NULL,at INTEGER NOT NULL)")
    q("CREATE INDEX IF NOT EXISTS ex_journal_actor ON ex_journal(actor,status)")
    q("CREATE INDEX IF NOT EXISTS ex_journal_recipe_actor ON ex_journal(recipe,actor,status)")
    tx(function()
        local columns={}
        for _,c in ipairs(q("PRAGMA table_info(ex_recipes)")) do columns[c.name]=true end
        for _,name in ipairs({"duration_minutes","expires_at","exchange_limit"}) do
            if not columns[name] then q("ALTER TABLE ex_recipes ADD COLUMN "..name.." INTEGER NOT NULL DEFAULT 0") end
        end
        for _,key in ipairs({"enabled","buy","buffs","events"}) do q("INSERT OR IGNORE INTO ex_config(key,value) VALUES("..sql(key)..",1)") end
        for _,key in ipairs({"revision","generation"}) do q("INSERT OR IGNORE INTO ex_config(key,value) VALUES("..sql(key)..",0)") end
        for _,c in ipairs(CATEGORIES) do q("INSERT OR IGNORE INTO ex_categories(id,enabled) VALUES("..sql(c.id)..",1)") end
        q("UPDATE ex_config SET value=value+1 WHERE key='generation'"); generation=cfg("generation")
    end)
end)
ready=initialized
if not ready then print("[exchangeglobal] INIT FAILED: "..tostring(initError)) end

registerLuaCommand{command=COMMAND,roleRequired=0,description="Sell Ghost, Geiger, Provider, dan Fish."}
registerLuaCommand{command=ADMIN_COMMAND,roleRequired=ADMIN_ROLE,exactRole=true,description="Founder: FROM/TO, Duration, Limit Exchange."}
onPlayerCommandCallback(function(world,p,full)
    local cmd=tostring(full):match("^%s*/?(%S+)"); cmd=cmd and cmd:lower()
    if cmd==COMMAND then guard(p,function() home(p) end); return true end
    if cmd==ADMIN_COMMAND then guard(p,function() adminHome(p) end); return true end
    return false
end)
onPlayerDialogCallback(function(world,p,d)
    if type(d)~="table" or type(d.dialog_name)~="string" or not d.dialog_name:match("^exchangeglobal_") then return false end
    guard(p,function()
        local state=sessions[id(p)]; local clicked=tostring(d.buttonClicked or "")
        if d.quit=="1" or d.quit==1 or clicked=="" or clicked=="cancel" then
            if state and state.name==d.dialog_name then sessions[id(p)]=nil end
            return
        end
        if not state or state.name~=d.dialog_name or state.expires<=os.time() then home(p); return end
        local isAdminView=state.view=="admin" or state.editing or state.view=="recipe_edit" or state.view=="config_list" or state.view=="buff_edit" or state.view=="event_edit"
        if isAdminView then assert(admin(p),"Akses Founder sudah tidak tersedia.") end
        assert(state.buttons[clicked],"Tombol tidak tersedia pada menu ini.")
        sessions[id(p)]=nil
        if clicked=="home" or clicked=="refresh" then home(p); return end
        if clicked=="admin" then adminHome(p); return end
        if state.revision~=revision() then tell(p,"Konfigurasi berubah. Periksa menu terbaru sebelum melanjutkan."); if isAdminView then adminHome(p) else home(p) end; return end
        local page=clicked:match("^page_(%d+)$"); page=page and int(page,1,MAX_AMOUNT)
        if state.view=="home" then
            if clicked=="logs" then logs(p,1,false); return end
            local cat=clicked:match("^cat_(%a+)$")
            if cat=="fish" then dispatchFish(world,p) elseif cat then listing(p,cat,1,false) end
        elseif state.view=="listing" then
            if page then listing(p,state.category,page,state.editing)
            elseif clicked=="new" and state.editing then recipeForm(p,state.category)
            elseif clicked=="toggle_category" and state.editing then mutate(p,"category_toggled",function() q("UPDATE ex_categories SET enabled=1-enabled WHERE id="..sql(state.category)) end); listing(p,state.category,1,true)
            else
                local get=clicked:match("^get_(%d+)$")
                local rid=tonumber(get or clicked:match("^recipe_(%d+)$") or clicked:match("^edit_(%d+)$")
                    or clicked:match("^reward_(%d+)$") or clicked:match("^material_(%d+)_%d+$"))
                if rid then
                    assert(recipe(rid).category==state.category,"Mismatched category")
                    if state.editing then recipeForm(p,state.category,rid)
                    elseif get then review(p,{recipe=rid,quick=true,page=state.page},{amount="1",extra="0"},"sell")
                    else tradeForm(p,rid) end
                end
            end
        elseif state.view=="trade" then
            if clicked=="back" then listing(p,state.category,1,false) else review(p,state,d,clicked) end
        elseif state.view=="confirm" then
            if clicked=="back" then
                if state.quick then listing(p,state.category,state.page,false) else tradeForm(p,state.recipe) end
            elseif clicked=="confirm" then
                local journal=execute(p,state.quote); tell(p,"`2Exchange berhasil.`` Transaksi #"..journal)
                if state.quick then listing(p,state.category,state.page,false) else tradeForm(p,state.recipe) end
            end
        elseif state.view=="admin" then
            local cat=clicked:match("^manage_(%a+)$"); local feature=clicked:match("^feature_(%a+)$")
            if cat=="fish" then
                local L=begin("SELLFISH / ROUTING",3000)
                line(L,"Fish membuka /sellfish yang sudah ada. Harga dan proses jual milik command tersebut.")
                line(L,"Bonus Fish hanya berlaku pada payout jika script /sellfish memanggil API ExchangeGlobal.")
                button(L,"toggle_fish",category("fish").enabled==1 and "Nonaktifkan Tombol Fish" or "Aktifkan Tombol Fish")
                button(L,"events","Atur Event Sellfish"); button(L,"admin","Kembali")
                show(p,L,{view="fish_admin",editing=true})
            elseif cat then listing(p,cat,1,true)
            elseif feature then mutate(p,"feature_toggled",function() q("UPDATE ex_config SET value=1-value WHERE key="..sql(feature)) end); adminHome(p)
            elseif clicked=="buffs" or clicked=="events" then configList(p,clicked,1)
            elseif clicked=="admin_logs" then logs(p,1,true) end
        elseif state.view=="fish_admin" then
            if clicked=="toggle_fish" then mutate(p,"fish_toggled",function() q("UPDATE ex_categories SET enabled=1-enabled WHERE id='fish'") end); adminHome(p)
            elseif clicked=="events" then configList(p,"events",1) end
        elseif state.view=="recipe_edit" then
            if clicked=="back" then listing(p,state.category,1,true) elseif clicked=="save_recipe" then saveRecipe(p,state,d) end
        elseif state.view=="config_list" then
            if page then configList(p,state.kind,page)
            else local record=tonumber(clicked:match("^edit_(%d+)$")); if state.kind=="buffs" then buffForm(p,record) else eventForm(p,record) end end
        elseif state.view=="buff_edit" then
            if clicked=="back" then configList(p,"buffs",1) elseif clicked=="save_buff" then saveBuff(p,state,d) end
        elseif state.view=="event_edit" then
            if clicked=="back" then configList(p,"events",1) elseif clicked=="save_event" then saveEvent(p,state,d) end
        elseif state.view=="logs" then
            if clicked=="pending" then logs(p,1,true,not state.pending,false)
            elseif clicked=="audit" then logs(p,1,true,false,not state.securityLog)
            elseif page then logs(p,page,state.editing,state.pending,state.securityLog) end
        end
    end)
    return true
end)
onPlayerDisconnectCallback(function(p) if p then sessions[id(p)],busy[id(p)]=nil,nil end end)

-- Integration API: calculate only. Tidak memberi item atau memodifikasi payout /sellfish bawaan.
ExchangeGlobal={}
function ExchangeGlobal.getSellMultiplier(p,cat)
    assert(ready,"Exchange unavailable")
    assert(categories[cat],"Unknown category")
    if cfg("enabled")==0 or category(cat).enabled==0 then return 1 end
    local numerator,parts=multipliers(p,cat)
    return numerator/1000000,parts
end
function ExchangeGlobal.calculateSellReward(p,cat,baseAmount)
    assert(ready and categories[cat],"Exchange/category unavailable")
    local base=assert(int(baseAmount,0,MAX_AMOUNT),"Invalid base amount")
    local numerator=cfg("enabled")==1 and category(cat).enabled==1 and multipliers(p,cat) or 1000000
    return multiply(base,numerator)
end
print("[exchangeglobal] "..(ready and ("Loaded /"..COMMAND.." + /"..ADMIN_COMMAND) or "Unavailable"))
return ExchangeGlobal
