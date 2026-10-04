-- Developer: Nathan
-- /buyuws: Ultra World Spray (5926). /setpriceuws <gems>: Founder only.
-- Standalone GTPS Lua 5.1+ script. Purchase journal: gemstouws_v1.db.
-- Ambiguous item/gems changes stay pending; never replay after reload.
local VERSION, DB_FILE = "v2-price", "gemstouws_v1.db"
local ITEM_ID, DEFAULT_PRICE, MAX_AMOUNT = 5926, 100000000, 2000000000
local SESSION_SECONDS = 120
local sessions, busy, serial = {}, {}, 0
local db, ready, generation, initError, initialPrice

local function integer(n, low, high)
    return type(n)=="number" and n==n and n>=low and n<=high and n==math.floor(n) and n or nil
end
local function number(n) return string.format("%.0f", n) end
local function fmt(n) return number(n):reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "") end
local function clean(value, limit) return tostring(value or ""):gsub("`.", ""):gsub("[|%c]", " "):sub(1, limit or 200) end
local function sql(value) return "'" .. tostring(value):gsub("%z", ""):gsub("'", "''") .. "'" end
local function uid(p) return assert(integer(p:getUserID(), 1, 9007199254740991), "ID akun tidak valid.") end
local function realPlayer(p) return p and p:isOnline() and p:getType()==0 end
local function tell(p, message) p:onConsoleMessage("`3[UWS]`` " .. message) end
local function query(statement) return assert(db:query(statement), "Database pembelian tidak dapat diakses.") end
local function tx(callback)
    query("BEGIN IMMEDIATE")
    local ok, value = pcall(callback)
    if ok then ok, value = pcall(function() query("COMMIT"); return value end) end
    if not ok then pcall(function() query("ROLLBACK") end); error(value) end
    return value
end
local function pricing()
    local row = assert(query("SELECT price,revision FROM uws_config WHERE id=1")[1], "Harga UWS belum tersedia.")
    local price = assert(integer(tonumber(row.price), 1, MAX_AMOUNT), "Harga UWS tersimpan tidak valid.")
    local revision = assert(integer(tonumber(row.revision), 0, 9007199254740991), "Versi harga UWS tidak valid.")
    return price, revision
end
local function quantityLimit(price) return math.floor(MAX_AMOUNT/price) end
local function snapshot(p)
    return {
        gems=assert(integer(p:getGems(), 0, MAX_AMOUNT), "Saldo gems tidak valid."),
        inventory=assert(integer(p:getItemAmount(ITEM_ID), 0, MAX_AMOUNT), "Jumlah UWS tidak valid."),
        extra=assert(integer(p:getExtraBackpackAmount(ITEM_ID), 0, MAX_AMOUNT), "Jumlah UWS di Extra Backpack tidak valid."),
    }
end
local function sameItems(a, b) return a.inventory==b.inventory and a.extra==b.extra end
local function pending(id) return query("SELECT id FROM uws_purchases WHERE uid=" .. number(id) .. " AND status='pending' LIMIT 1")[1] end
local function available(p)
    local row = pending(uid(p))
    if not row then return true end
    tell(p, "`oPembelian #" .. number(row.id) .. " perlu diperiksa admin sebelum membeli lagi.``")
    return false
end
local function maximum(balance, price)
    return math.max(0, math.min(quantityLimit(price), math.floor(balance.gems/price), MAX_AMOUNT-balance.inventory-balance.extra))
end
local function parseAmount(value, price)
    if type(value)~="string" or #value>10 then return nil end
    local digits = value:match("^%s*(%d+)%s*$")
    return digits and integer(tonumber(digits), 1, quantityLimit(price)) or nil
end

local function begin(title)
    return {"set_default_color|`w\nset_bg_color|20,24,31,230|\nset_border_color|92,104,122,255|\n"
        .. "add_label_with_icon|big|`w" .. title .. "``|left|" .. ITEM_ID .. "|\nadd_spacer|small|\n"}
end
local function text(lines, value) lines[#lines+1] = "add_smalltext|" .. value .. "|\n" end
local function button(lines, key, label) lines[#lines+1] = "add_button|" .. key .. "|" .. label .. "|noflags|0|0|\n" end
local function show(p, lines, state)
    serial = serial+1
    state.name = "gemstouws_" .. state.view .. "_" .. number(generation) .. "_" .. number(serial)
    state.expires, state.buttons = os.time()+SESSION_SECONDS, {}
    for _, line in ipairs(lines) do
        local key = line:match("^add_button|([^|]+)|")
        if key then state.buttons[key] = true end
    end
    lines[#lines+1] = "add_spacer|small|\nadd_smalltext|`9© Dibuat Oleh : Nathan``|\n"
    lines[#lines+1] = "end_dialog|" .. state.name .. "|Tutup||\n"
    local markup = table.concat(lines)
    assert(#markup<=4096, "Dialog terlalu panjang.")
    sessions[uid(p)] = state
    local ok, result = pcall(p.onDialogRequest, p, markup)
    if not ok or result==false then sessions[uid(p)] = nil; error("Tidak dapat membuka menu pembelian.") end
end
local function form(p, amount, notice)
    if not available(p) then return end
    assert(getItem(ITEM_ID), "Ultra World Spray (5926) belum tersedia di server.")
    local price, revision = pricing()
    local balance = snapshot(p)
    local max = maximum(balance, price)
    local lines = begin("ULTRA WORLD SPRAY")
    text(lines, "`oBeli UWS menggunakan gems yang kamu bawa.``")
    text(lines, "Harga: `w" .. fmt(price) .. " gems`` / `31 UWS``")
    text(lines, "Gems kamu: `w" .. fmt(balance.gems) .. "``")
    text(lines, "Bisa dibeli sekarang: `3" .. fmt(max) .. " UWS``")
    if notice then text(lines, "`o" .. notice .. "``") end
    if balance.gems<price then text(lines, "Butuh " .. fmt(price-balance.gems) .. " gems lagi untuk 1 UWS.")
    elseif max==0 then text(lines, "Jumlah UWS kamu sudah mencapai batas penyimpanan.") end
    lines[#lines+1] = "add_spacer|small|\nadd_text_input|buy_amount|Jumlah UWS :|" .. number(amount or 1) .. "|10|\n"
    text(lines, "Periksa total biaya di halaman berikutnya.")
    if max>0 then
        button(lines, "review", "Lanjut")
        button(lines, "maximum", "Beli Maksimal (" .. fmt(max) .. " UWS)")
    end
    button(lines, "refresh", "Refresh Saldo")
    show(p, lines, {view="form", price=price, revision=revision})
end
local function review(p, amount)
    local price, revision = pricing()
    if not integer(amount, 1, quantityLimit(price)) then form(p, nil, "Isi angka bulat 1-" .. fmt(quantityLimit(price)) .. ", tanpa titik atau koma."); return end
    if not available(p) then return end
    local balance = snapshot(p)
    local cost = amount*price
    if balance.gems<cost then form(p, amount, "Gems kurang " .. fmt(cost-balance.gems) .. "."); return end
    if amount>maximum(balance, price) then form(p, amount, "Jumlah UWS melebihi batas penyimpanan."); return end
    assert(getItem(ITEM_ID), "Ultra World Spray (5926) belum tersedia di server.")
    local lines = begin("KONFIRMASI PEMBELIAN")
    text(lines, "Kamu menerima: `3" .. fmt(amount) .. " Ultra World Spray``")
    text(lines, "Harga per item: " .. fmt(price) .. " gems")
    text(lines, "Total biaya: `w" .. fmt(cost) .. " gems``")
    text(lines, "Sisa gems: `w" .. fmt(balance.gems-cost) .. "``")
    text(lines, "`oJika inventory penuh, UWS masuk ke Extra Backpack.``")
    button(lines, "confirm", "Beli " .. fmt(amount) .. " UWS")
    button(lines, "back", "Ubah Jumlah")
    show(p, lines, {view="confirm", amount=amount, price=price, revision=revision})
end
local function intent(id, amount, cost, before, quote)
    return tx(function()
        local price, revision = pricing()
        assert(price==quote.price and revision==quote.revision, "Harga UWS berubah. Buka /buyuws untuk melihat harga terbaru.")
        assert(not pending(id), "Ada pembelian pending. Hubungi admin.")
        query("INSERT INTO uws_purchases(uid,item_id,amount,cost,gems_before,inventory_before,extra_before,status,created_at) VALUES("
            .. number(id) .. "," .. ITEM_ID .. "," .. amount .. "," .. number(cost) .. "," .. number(before.gems)
            .. "," .. number(before.inventory) .. "," .. number(before.extra) .. ",'pending'," .. os.time() .. ")")
        return assert(integer(tonumber(query("SELECT last_insert_rowid() AS id")[1].id), 1, 9007199254740991), "Jurnal pembelian tidak valid.")
    end)
end
local function finish(id, status, after, note)
    tx(function()
        assert(query("SELECT status FROM uws_purchases WHERE id=" .. number(id))[1].status=="pending", "Status pembelian berubah.")
        query("UPDATE uws_purchases SET status=" .. sql(status) .. ",gems_after=" .. number(after.gems)
            .. ",inventory_after=" .. number(after.inventory) .. ",extra_after=" .. number(after.extra)
            .. ",finished_at=" .. os.time() .. ",note=" .. sql(note) .. " WHERE id=" .. number(id) .. " AND status='pending'")
    end)
end
local function hold(id, stage, apiOK, result, readOK, after)
    local details = stage .. " api_ok=" .. tostring(apiOK) .. " result=" .. tostring(result)
        .. (readOK and (" gems=" .. number(after.gems) .. " inventory=" .. number(after.inventory) .. " extra=" .. number(after.extra))
            or (" read_error=" .. tostring(after)))
    pcall(function() query("UPDATE uws_purchases SET note=" .. sql(details) .. " WHERE id=" .. number(id)) end)
    print("[gemstouws] NEEDS REVIEW #" .. number(id) .. " " .. details)
    error("Pembelian #" .. number(id) .. " perlu diperiksa admin sebelum membeli lagi.")
end
local function purchase(p, amount, quote)
    assert(integer(quote.price, 1, MAX_AMOUNT) and integer(amount, 1, quantityLimit(quote.price)), "Jumlah pembelian tidak valid.")
    if not available(p) then return end
    local price, revision = pricing()
    if price~=quote.price or revision~=quote.revision then form(p, amount, "Harga UWS berubah. Periksa harga terbaru sebelum membeli."); return end
    assert(getItem(ITEM_ID), "Ultra World Spray (5926) belum tersedia di server.")
    local before = snapshot(p)
    local cost = amount*quote.price
    if before.gems<cost then form(p, amount, "Saldo berubah. Gems kurang " .. fmt(cost-before.gems) .. "."); return end
    if amount>maximum(before, quote.price) then form(p, amount, "Jumlah UWS melebihi batas penyimpanan."); return end
    local id = intent(uid(p), amount, cost, before, quote)
    local debitOK, debitedResult = pcall(p.removeGems, p, cost)
    local debitRead, debited = pcall(snapshot, p)
    if debitOK and debitedResult==false and debitRead and debited.gems==before.gems and sameItems(debited, before) then
        finish(id, "cancelled", debited, "Debit refused; no assets changed")
        form(p, amount, "Pemotongan gems ditolak server. Saldo kamu tidak berubah."); return
    end
    if not (debitOK and debitedResult==true and debitRead and debited.gems==before.gems-cost and sameItems(debited, before)) then
        hold(id, "debit", debitOK, debitedResult, debitRead, debited)
    end
    local giveOK, given = pcall(p.giveItem, p, ITEM_ID, amount)
    local afterRead, after = pcall(snapshot, p)
    if giveOK and given==true and afterRead and after.gems==debited.gems and after.inventory>=before.inventory and after.extra>=before.extra
        and after.inventory-before.inventory+after.extra-before.extra==amount then
        finish(id, "done", after, "Purchase completed")
        tell(p, "`2Berhasil membeli " .. fmt(amount) .. " UWS!`` Sisa " .. fmt(after.gems) .. " gems.")
        local lines = begin("PEMBELIAN BERHASIL")
        text(lines, "Kamu menerima `3" .. fmt(amount) .. " Ultra World Spray``.")
        text(lines, "Gems terpakai: " .. fmt(cost))
        text(lines, "Sisa gems: " .. fmt(after.gems))
        if after.extra>before.extra then text(lines, "UWS masuk Extra Backpack: " .. fmt(after.extra-before.extra)) end
        button(lines, "again", "Beli Lagi")
        show(p, lines, {view="success"}); return
    end
    -- Refund only a refused grant with zero item movement and unchanged debited gems.
    if giveOK and given==false and afterRead and after.gems==debited.gems and sameItems(after, before) then
        local refundOK, refundedResult = pcall(p.addGems, p, cost)
        local refundRead, refunded = pcall(snapshot, p)
        if refundOK and refundRead and refunded.gems==before.gems and sameItems(refunded, before) then
            finish(id, "refunded", refunded, "Grant refused; exact refund verified")
            form(p, amount, "UWS gagal dikirim. " .. fmt(cost) .. " gems sudah dikembalikan penuh."); return
        end
        hold(id, "refund", refundOK, refundedResult, refundRead, refunded)
    end
    hold(id, "give", giveOK, given, afterRead, after)
end

local function setPrice(p, input)
    assert(p:getRole()==1000, "Perintah /setpriceuws khusus Founder.")
    local digits = type(input)=="string" and #input<=32 and input:match("^%s*(%d+)%s*$")
    local price = digits and integer(tonumber(digits), 1, MAX_AMOUNT)
    assert(price, "Gunakan /setpriceuws NOMINALGEMS (1-2000000000), tanpa titik atau koma.")
    local changed = tx(function()
        assert(p:getRole()==1000, "Perintah /setpriceuws khusus Founder.")
        local current, revision = pricing()
        if current==price then return false end
        assert(revision<9007199254740991, "Versi harga mencapai batas. Hubungi pengelola server.")
        query("UPDATE uws_config SET price=" .. number(price) .. ",revision=revision+1 WHERE id=1")
        return true
    end)
    tell(p, changed and ("`2Harga UWS diubah menjadi " .. fmt(price) .. " gems per item.``")
        or ("Harga UWS sudah " .. fmt(price) .. " gems per item."))
    if changed then print("[gemstouws] PRICE updated=" .. number(price) .. " founder_uid=" .. number(uid(p))) end
end

local function guard(p, callback)
    if not realPlayer(p) then return end
    local id = uid(p)
    if busy[id] then return end
    busy[id] = true
    local ok, err = pcall(function()
        assert(ready, "Toko UWS belum tersedia. Periksa log [gemstouws] di console server.")
        callback()
    end)
    busy[id] = nil
    if not ok then
        sessions[id] = nil
        print("[gemstouws] ERROR uid=" .. number(id) .. " / " .. tostring(err))
        local checked, row = false, nil
        if ready then checked, row = pcall(pending, id) end
        tell(p, "`o" .. (checked and row and ("Pembelian #" .. number(row.id) .. " perlu diperiksa admin sebelum membeli lagi.")
            or clean(err):gsub("^.-:%d+:%s*", "")) .. "``")
    end
end
local function command(_, p, full)
    if type(full)~="string" then return false end
    local name, args = full:match("^%s*/?(%S+)%s*(.-)%s*$")
    name = name and name:lower()
    if name~="buyuws" and name~="setpriceuws" then return false end
    guard(p, function()
        if name=="setpriceuws" then setPrice(p, args)
        else form(p, nil, args~="" and "Pilih jumlah melalui kolom Jumlah UWS." or nil) end
    end)
    return true
end
local function dialog(_, p, data)
    if type(data)~="table" or type(data.dialog_name)~="string" or not data.dialog_name:match("^gemstouws_") then return false end
    guard(p, function()
        local id = uid(p)
        local state = sessions[id]
        local matches = state and state.name==data.dialog_name
        local clicked = data.buttonClicked
        if data.quit=="1" or data.quit==1 or clicked==nil or clicked=="" or clicked=="cancel" or clicked=="Tutup" then
            if matches then sessions[id] = nil end
            return
        end
        if state and not matches then tell(p, "`oGunakan menu UWS yang terbaru.``"); return end
        if not matches or os.time()>=state.expires then
            if matches then sessions[id] = nil end
            form(p, state and state.amount); return
        end
        if not state.buttons[clicked] then return end
        if state.view=="form" or state.view=="confirm" then
            local price, revision = pricing()
            if price~=state.price or revision~=state.revision then
                sessions[id] = nil
                form(p, state.amount, "Harga UWS berubah. Periksa harga terbaru sebelum membeli."); return
            end
        end
        sessions[id] = nil
        if clicked=="refresh" then form(p)
        elseif state.view=="form" then
            if clicked=="review" then review(p, parseAmount(data.buy_amount, state.price))
            elseif clicked=="maximum" then
                local amount = maximum(snapshot(p), state.price)
                if amount>0 then review(p, amount) else form(p) end
            end
        elseif state.view=="confirm" then
            if clicked=="confirm" then purchase(p, state.amount, state) elseif clicked=="back" then form(p, state.amount) end
        elseif state.view=="success" and clicked=="again" then form(p) end
    end)
    return true
end
local function install(label, fn, argument)
    if type(fn)~="function" then print("[gemstouws] Missing API: " .. label); return false end
    local ok, result = pcall(fn, argument)
    if not ok or result==false then print("[gemstouws] Registration failed: " .. label .. " / " .. tostring(result)); return false end
    return true
end

print("[gemstouws] BOOT " .. VERSION .. " | " .. tostring(_VERSION))
local commandOK = install("command", onPlayerCommandCallback, command)
local dialogOK = install("dialog", onPlayerDialogCallback, dialog)
local registered = true
for _, spec in ipairs({{name="buyuws",role=0,description="Beli Ultra World Spray dengan gems."},
    {name="setpriceuws",role=1000,description="Founder: atur harga UWS dalam gems."}}) do
    local name = spec.name
    local ok = install("/" .. name, registerLuaCommand, {command=name, roleRequired=spec.role, exactRole=spec.role==1000,
        description=spec.description, callback=function(p, args) return command(nil, p, name .. " " .. (args or "")) end})
    registered = ok and registered
end
install("disconnect", onPlayerDisconnectCallback, function(p) if p then sessions[uid(p)], busy[uid(p)] = nil, nil end end)
ready, initError = pcall(function()
    assert((registered or commandOK) and dialogOK, "API command/dialog tidak tersedia.")
    assert(type(getItem)=="function", "API item tidak tersedia.")
    assert(type(sqlite)=="table" and type(sqlite.open)=="function", "SQLite tidak tersedia.")
    db = assert(sqlite.open(DB_FILE), "Database UWS tidak dapat dibuka.")
    query("PRAGMA synchronous=FULL")
    query("CREATE TABLE IF NOT EXISTS uws_purchases(id INTEGER PRIMARY KEY AUTOINCREMENT,uid INTEGER NOT NULL,item_id INTEGER NOT NULL,amount INTEGER NOT NULL,cost INTEGER NOT NULL,gems_before INTEGER NOT NULL,inventory_before INTEGER NOT NULL,extra_before INTEGER NOT NULL,gems_after INTEGER,inventory_after INTEGER,extra_after INTEGER,status TEXT NOT NULL CHECK(status IN ('pending','done','cancelled','refunded')),created_at INTEGER NOT NULL,finished_at INTEGER,note TEXT NOT NULL DEFAULT '')")
    query("CREATE UNIQUE INDEX IF NOT EXISTS uws_pending ON uws_purchases(uid) WHERE status='pending'")
    query("CREATE TABLE IF NOT EXISTS uws_runtime(id INTEGER PRIMARY KEY CHECK(id=1),generation INTEGER NOT NULL)")
    query("CREATE TABLE IF NOT EXISTS uws_config(id INTEGER PRIMARY KEY CHECK(id=1),price INTEGER NOT NULL CHECK(price BETWEEN 1 AND 2000000000),revision INTEGER NOT NULL CHECK(revision>=0))")
    query("INSERT OR IGNORE INTO uws_config(id,price,revision) VALUES(1," .. DEFAULT_PRICE .. ",0)")
    initialPrice = pricing()
    generation = tx(function()
        query("INSERT OR IGNORE INTO uws_runtime(id,generation) VALUES(1,0)")
        query("UPDATE uws_runtime SET generation=generation+1 WHERE id=1")
        return assert(integer(tonumber(query("SELECT generation FROM uws_runtime WHERE id=1")[1].generation), 1, 9007199254740991), "Generasi dialog tidak valid.")
    end)
end)
print("[gemstouws] ROUTES registered=" .. tostring(registered) .. " command=" .. tostring(commandOK) .. " dialog=" .. tostring(dialogOK))
print(ready and ("[gemstouws] Loaded /buyuws /setpriceuws | 5926 | " .. fmt(initialPrice) .. " gems per UWS") or ("[gemstouws] INIT FAILED: " .. tostring(initError)))
