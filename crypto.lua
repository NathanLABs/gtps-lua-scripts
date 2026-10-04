-- Developer: Nathan
-- crypto.lua - Digital crypto marketplace.
-- Crypto Digital Marketplace. Player: /crypto, Founder: /setcrypto
-- Data persisten via saveDataToServer. Upload 1 file ini saja.
-- Logo memakai item custom yang SUDAH terpasang di client.
-- ID logo server: BTC=10002, ETH=10012, LTC=10014.
-- /setcrypto -> Edit: isi ID item logo BTC/ETH/LTC; 0 = teks sementara.
-- Harga ditampilkan/diinput dalam GGL, disimpan dalam unit WL agar data lama utuh.
print("[crypto] BOOT v3-command-routing")

local FOUNDER_ROLE = 1000
local GGL_ITEM_ID = 8470
local MAX_VALUE = 2000000000
local MAX_PRICE = 1000000000 -- WL internal; total order <= MAX_VALUE WL.
local MAX_COINS = 8
local COIN_LOGOS = { BTC = 10002, ETH = 10012, LTC = 10014 }
local LOGO_MAPPING_VERSION = 1 -- Migrasi sekali; edit logo Founder berikutnya tetap disimpan.
local sessions, busy, handlers = {}, {}, {}
local nativeDialogCallback = onPlayerDialogCallback
local function onPlayerDialogCallback(fn) handlers[#handlers + 1] = fn end
local serial, generation, marketRevision, ready = 0, 0, 0, false
local configRevision = 0 -- Hanya edit Founder; tick harga tidak membatalkan form pengaturan.
local unavailableReason = "Market belum diinisialisasi."
local initialize
local DLG_MAIN  = "crypto_main"
local DLG_COIN  = "crypto_coin"
local DLG_ADMIN = "crypto_admin"
local DLG_EDIT  = "crypto_edit"
local DLG_PUMP  = "crypto_pump"
local DLG_LOCKS = "crypto_locks"
local DLG_LVAL  = "crypto_lval"
local DLG_SET   = "crypto_set"
local DLG_ADD   = "crypto_addcoin"
local DLG_RECOVERY = "crypto_recovery"

local DEFAULT_COINS = {
    { id = "BTC", name = "Bitcoin",  iconID = COIN_LOGOS.BTC, price = 51500 },
    { id = "ETH", name = "Ethereum", iconID = COIN_LOGOS.ETH, price = 24200 },
    { id = "LTC", name = "Litecoin", iconID = COIN_LOGOS.LTC, price = 16100 },
}
local DEFAULT_LOCKS = {
    { itemID = 242,  name = "World Lock",     value = 1 },
    { itemID = 1796, name = "Diamond Lock",    value = 100 },
    { itemID = 7188, name = "Blue Gem Lock",   value = 10000 },
    { itemID = 8470, name = "Golden Gem Lock", value = 1000000 },
}
local DEFAULT_SETTINGS = {
    fee = 5, interval = 30, autoFluct = false, upChance = 55, maxChange = 3,
}

local coins, locks, settings = {}, {}, {}
local fluctTimer = nil

-- Util --
local function isFounder(p) return p and p:isOnline() and p:getRole() == FOUNDER_ROLE end
local function msg(p, t) p:onConsoleMessage("`6[Crypto] ``" .. t) end
local function fmt(v)
    local s = string.format("%.0f", v)
    return s:reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
end
local function dec(v, d) return string.format("%." .. (d or 2) .. "f", v) end
local function clean(t,limit) return tostring(t or ""):gsub("`.", ""):gsub("[|%c]", " "):sub(1, limit or 80) end
local function integer(v, lo, hi)
    local n = tonumber(v)
    return n and n == n and n >= lo and n <= hi and n == math.floor(n) and n or nil
end
local function lockValue(raw)
    local s=tostring(raw or ""):match("^%s*(.-)%s*$")
    if #s>24 then return nil end
    if s:match("^%d+$") then return integer(s,1,MAX_PRICE) end
    local sep=s:match("[., ]")
    if not sep then return nil end
    local escaped=sep=="." and "%." or sep
    local first,rest=s:match("^(%d+)"..escaped.."(.+)$")
    if not first or #first>3 then return nil end
    for group in (rest..sep):gmatch("(.-)"..escaped) do
        if not group:match("^%d%d%d$") then return nil end
    end
    return integer(first..rest:gsub(escaped,""),1,MAX_PRICE)
end
local function save(key, value)
    assert(saveDataToServer(key, value) == true, "Penyimpanan gagal. Coba lagi; hubungi pengelola jika berulang.")
end
local function sendDialog(p, markup)
    local original = assert(markup:match("end_dialog|([^|]+)|"), "Dialog tidak valid")
    serial = serial + 1
    local name = "crypto_v2_" .. generation .. "_" .. serial
    local allowed = {}
    for line in markup:gmatch("[^\n]+") do
        local button = line:match("^add_button[^|]*|([^|]+)|")
        if button then allowed[button] = true end
    end
    -- end_dialog's right-hand caption is returned as buttonClicked by the client.
    local accept = markup:match("end_dialog|[^|]+|[^|]*|([^|]*)|")
    if accept and accept ~= "" then allowed[accept] = true end
    sessions[p:getUserID()] = {name=name, original=original, allowed=allowed,
        expires=os.time()+120, revision=marketRevision, configRevision=configRevision}
    markup = markup:gsub("end_dialog|[^|]+|", function()
        return "add_spacer|small|\nadd_smalltext|`9© Dibuat Oleh : Nathan``|\nend_dialog|" .. name .. "|"
    end, 1)
    assert(#markup < 4096, "Dialog terlalu besar. Kurangi jumlah coin/lock.")
    p:onDialogRequest(markup)
end
local function coinLabel(size, text, coin)
    if coin.iconID and coin.iconID > 0 and getItem(coin.iconID) then
        return "add_label_with_icon|" .. size .. "|" .. text .. "|left|" .. coin.iconID .. "|"
    end
    return "add_label|" .. size .. "|" .. text .. "|left|"
end

-- Persistence --
local function savedList(data,key)
    assert(type(data)=="table",key..": data bukan tabel; tidak direset.")
    local rows,indexes={},{}
    -- JSON serializer dapat mengembalikan {"1": row} alih-alih array Lua.
    -- Keduanya disusun kembali tanpa membuang entry, menebak harga, atau memakai default.
    for k,row in pairs(data) do
        assert(type(k)=="number" or (type(k)=="string" and k:match("^%d+$")),key..": indeks daftar tidak valid.")
        local index=assert(integer(k,0,100000),key..": indeks di luar batas.")
        assert(not rows[index] and type(row)=="table",key..": entry duplikat/tidak valid.")
        rows[index]=row; indexes[#indexes+1]=index
    end
    assert(#indexes>0,key..": data kosong; default tidak akan menimpanya.")
    table.sort(indexes)
    local first=indexes[1]
    assert(first==0 or first==1,key..": daftar harus dimulai pada indeks 0 atau 1.")
    local result={}
    for i,index in ipairs(indexes) do
        assert(index==first+i-1,key..": indeks daftar berlubang; periksa data tersimpan.")
        result[i]=rows[index]
    end
    return result
end
local function normalizeConfig(key,data)
    if key=="crypto_coins" then
        data=savedList(data,key)
        for _,c in ipairs(data) do
            assert(type(c.id)=="string",key..": kode coin tidak valid.")
            c.price=assert(integer(c.price,1,MAX_PRICE),key.." / "..c.id..": harga tidak valid.")
            if c.prevPrice~=nil then c.prevPrice=assert(integer(c.prevPrice,0,MAX_PRICE),key.." / "..c.id..": prevPrice tidak valid.") end
            if c.iconID~=nil then c.iconID=assert(integer(c.iconID,0,MAX_VALUE),key.." / "..c.id..": iconID tidak valid.") end
            if c.upChance~=nil then c.upChance=assert(integer(c.upChance,0,100),key.." / "..c.id..": upChance tidak valid.") end
            if c.logoMappingVersion~=nil then c.logoMappingVersion=assert(integer(c.logoMappingVersion,0,MAX_VALUE),key..": versi logo tidak valid.") end
        end
    elseif key=="crypto_locks" then
        data=savedList(data,key)
        for _,l in ipairs(data) do
            l.itemID=assert(integer(l.itemID,1,MAX_VALUE),key..": itemID tidak valid.")
            l.value=assert(integer(l.value,1,MAX_PRICE),key.." / "..l.itemID..": nilai WL tidak valid.")
        end
    elseif key=="crypto_settings" then
        assert(type(data)=="table",key..": data bukan tabel; tidak direset.")
        local ranges={fee={0,100},interval={1,3600},upChance={0,100},maxChange={1,50}}
        for field,bounds in pairs(ranges) do
            if data[field]~=nil then data[field]=assert(integer(data[field],bounds[1],bounds[2]),key..": "..field.." tidak valid.") end
        end
        local v=data.autoFluct
        if v=="true" or v==1 or v=="1" then data.autoFluct=true
        elseif v=="false" or v==0 or v=="0" then data.autoFluct=false
        else assert(v==nil or type(v)=="boolean",key..": autoFluct tidak valid.") end
    end
    return data
end
local function sameData(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not sameData(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function saveConfig(key,value)
    save(key,value)
    local stored=loadDataFromServer(key)
    assert(stored~=nil,key..": hasil simpan tidak dapat dibaca kembali.")
    assert(sameData(normalizeConfig(key,value),normalizeConfig(key,stored)),key..": isi pembacaan ulang berbeda dari nilai yang disimpan.")
end
local function saveCoins(automatic)
    saveConfig("crypto_coins", coins)
    marketRevision=marketRevision+1
    if not automatic then configRevision=configRevision+1 end
end
local function saveLocks()
    saveConfig("crypto_locks", locks); marketRevision=marketRevision+1; configRevision=configRevision+1
end
local function saveSettings()
    saveConfig("crypto_settings", settings); marketRevision=marketRevision+1; configRevision=configRevision+1
end
local function savePort(uid, p) save("crypto_p_" .. uid, p) end

local function loadPort(uid)
    local d = loadDataFromServer("crypto_p_" .. uid)
    assert(d==nil or type(d)=="table", "Data portfolio rusak; hubungi pengelola.")
    if not d then d = {} end
    for _, c in ipairs(coins) do
        if d[c.id] == nil then d[c.id] = 0 end
        d[c.id]=assert(integer(d[c.id], 0, MAX_VALUE), "Saldo crypto tidak valid; hubungi pengelola.")
    end
    return d
end

local function loadAll()
    local cd = loadDataFromServer("crypto_coins")
    if cd~=nil then
        coins = normalizeConfig("crypto_coins",cd)
    else
        coins = {}
        for _, c in ipairs(DEFAULT_COINS) do
            coins[#coins + 1] = { id = c.id, name = c.name, iconID = c.iconID,
                price = c.price, prevPrice = c.price }
        end
        saveCoins()
    end
    local ld = loadDataFromServer("crypto_locks")
    if ld~=nil then locks = normalizeConfig("crypto_locks",ld)
    else
        locks = {}
        for _, l in ipairs(DEFAULT_LOCKS) do
            locks[#locks + 1] = { itemID = l.itemID, name = l.name, value = l.value }
        end
        saveLocks()
    end
    local sd = loadDataFromServer("crypto_settings")
    if sd~=nil then settings = normalizeConfig("crypto_settings",sd)
    else settings = {}; for k, v in pairs(DEFAULT_SETTINGS) do settings[k] = v end; saveSettings() end
    for k, v in pairs(DEFAULT_SETTINGS) do if settings[k] == nil then settings[k] = v end end
    -- Terapkan ID yang dikonfirmasi pemilik server ke data baru/lama sekali saja.
    local migrated, seen, foundGGL, foundWL = false, {}, false, false
    assert(#coins <= MAX_COINS and #locks <= 8, "Maksimal 8 coin/lock untuk ukuran dialog.")
    for _, c in ipairs(coins) do
        assert(type(c.id)=="string" and c.id:match("^[A-Z0-9]+$") and #c.id<=5 and not seen[c.id], "Kode coin tidak valid/duplikat")
        seen[c.id] = true
        assert(integer(c.price, 1, MAX_PRICE), "Harga coin tidak valid")
        c.name = clean(c.name):sub(1,30)
        if not c.prevPrice then c.prevPrice=c.price end
        if COIN_LOGOS[c.id] and c.logoMappingVersion ~= LOGO_MAPPING_VERSION then
            c.iconID = COIN_LOGOS[c.id]
            c.logoMappingVersion = LOGO_MAPPING_VERSION
            migrated = true
        end
        c.iconID = integer(c.iconID,0,MAX_VALUE) or 0
    end
    seen={}
    for _, l in ipairs(locks) do
        assert(integer(l.itemID,1,MAX_VALUE) and integer(l.value,1,MAX_PRICE) and not seen[l.itemID], "Konfigurasi lock tidak valid")
        seen[l.itemID]=true
        if l.itemID==GGL_ITEM_ID then foundGGL=true end
        if l.itemID==242 and l.value==1 then foundWL=true end
    end
    assert(foundGGL and foundWL, "Konfigurasi membutuhkan GGL dan WL dengan value=1.")
    assert(integer(settings.fee,0,100) and integer(settings.interval,1,3600)
        and integer(settings.upChance,0,100) and integer(settings.maxChange,1,50), "Konfigurasi market tidak valid")
    if migrated then saveCoins() end
end

-- Lock helpers --
local function locksDesc()
    local s = {}
    for _, l in ipairs(locks) do s[#s + 1] = l end
    table.sort(s, function(a, b) return a.value > b.value end)
    return s
end

local function walletWL(p)
    local t = 0
    for _, l in ipairs(locks) do
        local amount=assert(integer(p:getItemAmount(l.itemID),0,MAX_VALUE), "Jumlah lock tidak valid")
        assert(amount<=math.floor((9007199254740991-t)/l.value), "Nilai wallet terlalu besar untuk dihitung tepat.")
        t=t+amount*(l.value+0.0)
    end
    return t
end

local function priceText(wl)
    for _, l in ipairs(locks) do
        if l.itemID == GGL_ITEM_ID then
            return string.format("%.9f", wl / l.value):gsub("0+$", ""):gsub("%.$", "") .. " GGL"
        end
    end
    error("GGL belum dikonfigurasi")
end

local function parseGGL(raw)
    local s = tostring(raw or ""):match("^%s*(.-)%s*$"):gsub(",", ".")
    assert(#s<=24 and (s:match("^%d+$") or s:match("^%d+%.%d+$")), "Harga GGL tidak valid. Contoh: 2 atau 0.5 (tanpa pemisah ribuan).")
    local amount=tonumber(s)
    for _, l in ipairs(locks) do
        if l.itemID==GGL_ITEM_ID then
            local rawValue=amount*l.value
            local value=math.floor(rawValue+0.5)
            assert(integer(value,1,MAX_PRICE) and math.abs(rawValue-value)<0.000001,
                "Harga harus setara WL utuh dan tidak melewati batas.")
            return value
        end
    end
    error("GGL belum dikonfigurasi")
end

local function breakdown(wl)
    local parts, rem = {}, math.floor(wl)
    for _, l in ipairs(locksDesc()) do
        if l.value > 0 and rem >= l.value then
            local n = math.floor(rem / l.value)
            rem = rem - n * l.value
            parts[#parts + 1] = fmt(n) .. " " .. l.name
        end
    end
    if rem > 0 then parts[#parts + 1] = fmt(rem) .. " WL" end
    return #parts > 0 and table.concat(parts, " + ") or "0 WL"
end

local function walletLine(p)
    local parts = {}
    for _, l in ipairs(locksDesc()) do
        local a = p:getItemAmount(l.itemID) or 0
        if a > 0 then parts[#parts + 1] = fmt(a) .. " " .. l.name end
    end
    return #parts > 0 and table.concat(parts, " + ") or "Kosong"
end

local function giveLocks(p, wl)
    local rem = math.floor(wl)
    for _, l in ipairs(locksDesc()) do
        if l.value > 0 and rem >= l.value then
            local n = math.floor(rem / l.value)
            if n > 0 then
                local before=p:getItemAmount(l.itemID)+p:getExtraBackpackAmount(l.itemID)
                assert(p:giveItem(l.itemID, n)==true, "Engine gagal memberikan lock; transaksi perlu diperiksa.")
                assert(p:getItemAmount(l.itemID)+p:getExtraBackpackAmount(l.itemID)==before+n,
                    "Jumlah lock diterima tidak sesuai; transaksi perlu diperiksa.")
                rem = rem - n * l.value
            end
        end
    end
    assert(rem==0, "Kembalian tidak dapat dibentuk dari lock terdaftar.")
end

local function takeLocks(p, take)
    for id,n in pairs(take) do
        local before=p:getItemAmount(id)
        assert(p:changeItem(id,-n)==true and p:getItemAmount(id)==before-n,
            "Pengurangan lock gagal/tidak sesuai; transaksi perlu diperiksa.")
    end
end

local function deductLocks(p, wl)
    local cost = math.floor(wl)
    if cost <= 0 then return true end
    if walletWL(p) < cost then return false end
    local sd = locksDesc()
    local take, rem = {}, cost
    for _, l in ipairs(sd) do
        if l.value > 0 and rem >= l.value then
            local have = p:getItemAmount(l.itemID) or 0
            local t = math.min(math.floor(rem / l.value), have)
            if t > 0 then take[l.itemID] = t; rem = rem - t * l.value end
        end
    end
    if rem > 0 then
        for _, l in ipairs(sd) do
            if l.value > rem then
                local have = p:getItemAmount(l.itemID) or 0
                local already = take[l.itemID] or 0
                if have > already then
                    take[l.itemID] = already + 1
                    local change = l.value - rem; rem = 0
                    takeLocks(p,take)
                    if change > 0 then giveLocks(p, change) end
                    return true
                end
            end
        end
    end
    if rem > 0 then return false end
    takeLocks(p,take)
    return true
end

local function trend(c)
    if not c.prevPrice or c.prevPrice == 0 then return "`w--", 0 end
    local pct = ((c.price - c.prevPrice) / c.prevPrice) * 100
    if pct > 0 then return "`2UP (+" .. dec(pct) .. "%)", pct end
    if pct < 0 then return "`4DOWN (" .. dec(pct) .. "%)", pct end
    return "`w0.00%", 0
end

local function serverTotals()
    local t = {}
    for _, c in ipairs(coins) do t[c.id] = 0 end
    for _, p in ipairs(getServerPlayers()) do
        local port = loadPort(p:getUserID())
        for _, c in ipairs(coins) do t[c.id] = t[c.id] + (port[c.id] or 0) end
    end
    return t
end

---------------------------------------------------------------------------
-- PLAYER: /crypto  (tampilan mirip referensi)
---------------------------------------------------------------------------
local function showMain(player)
    local port = loadPort(player:getUserID())
    local L = {}
    local function ln(s) L[#L + 1] = s .. "\n" end

    -- Header: icon + judul besar.
    ln(coinLabel("big", "`wCrypto Digital Marketplace``", coins[1] or {}))
    ln("add_smalltext|`oBitcoin / Ethereum / Litecoin - harga dalam Golden Gem Lock (GGL).``|")

    -- Select Crypto Coin.
    ln("add_spacer|small|")
    ln("add_label|small|`2Select Crypto Coin:``|left|")
    for _, c in ipairs(coins) do
        local caption = clean(c.name)
        if c.iconID and c.iconID>0 and getItem(c.iconID) then
            ln("add_button_with_icon|sel_" .. c.id .. "|" .. caption .. "|staticYellowFrame|" .. c.iconID .. "||")
        else
            local color = c.id=="BTC" and "`6" or c.id=="LTC" and "`1" or "`w"
            ln("add_button|sel_" .. c.id .. "|" .. color .. caption .. " (" .. c.id .. ")``|noflags|0|0|")
        end
    end
    ln("add_button_with_icon||END_LIST|noflags|0||")
    for _, c in ipairs(coins) do
        ln("add_smalltext|`w1 " .. c.id .. " = `2" .. priceText(c.price) .. "``|")
    end

    -- Portfolio.
    ln("add_spacer|small|")
    ln("add_label|small|`wYour Digital Crypto Portfolio:``|left|")
    local totalWL = 0
    for _, c in ipairs(coins) do
        local amt = port[c.id] or 0
        local worth = amt * c.price
        totalWL = totalWL + worth
        local tr = trend(c)
        ln(coinLabel("small", "`w" .. c.name .. ": `2" .. fmt(amt) .. " " .. c.id
            .. "`` (Worth: `w" .. priceText(worth) .. "``) " .. tr .. "``", c))
    end

    -- Totals.
    ln("add_spacer|small|")
    ln("add_smalltext|`wTotal Estimated Assets: `2" .. priceText(totalWL) .. "``|")
    ln("add_smalltext|`wWallet Balance: `o" .. walletLine(player) .. "``|")
    ln("add_smalltext|`wBuying Power: `2" .. priceText(walletWL(player)) .. "``|")

    -- Refresh.
    ln("add_spacer|small|")
    ln("add_button|refresh|`2Refresh Market Prices``|noflags|0|0|")
    ln("end_dialog|" .. DLG_MAIN .. "|Close||")

    sendDialog(player, table.concat(L))
end

local function showCoin(player, coinID)
    local coin
    for _, c in ipairs(coins) do if c.id == coinID then coin = c; break end end
    if not coin then msg(player, "`4Coin not found."); return end
    local port = loadPort(player:getUserID())
    local amt = port[coin.id] or 0
    local worth = amt * coin.price
    local fee = settings.fee or 0
    local tr = trend(coin)

    local L = {}
    local function ln(s) L[#L + 1] = s .. "\n" end

    ln(coinLabel("big", "`w" .. coin.name .. " Market (" .. coin.id .. ")``", coin))
    ln("add_smalltext|`wMarket Trend: ``" .. tr .. "``|")
    ln("add_spacer|small|")
    ln("add_smalltext|`w1 " .. coin.id .. " = `2" .. priceText(coin.price) .. "``|")
    if fee > 0 then
        local net = math.floor(coin.price * (100 - fee) / 100)
        ln("add_smalltext|`wSell Fee: `4" .. fee .. "%`` - Net per coin: `2" .. priceText(net) .. "``|")
    end
    ln("add_smalltext|`wYour Digital Balance: `2" .. fmt(amt) .. " " .. coin.id
        .. "`` (Worth: `w" .. priceText(worth) .. "``)|")
    ln("add_smalltext|`wWallet Balance: `o" .. walletLine(player) .. "``|")
    ln("add_smalltext|Harga dalam GGL; pembayaran memakai lock yang terdaftar, dengan kembalian bila diperlukan.|")

    ln("add_spacer|small|")
    ln("add_text_input|amount|Coin Amount (Buy/Sell):|1|5|")
    ln("add_spacer|small|")
    ln("add_button|buy_" .. coin.id .. "|`2BUY (Add to Digital Wallet)``|noflags|0|0|")
    ln("add_button|sell_" .. coin.id .. "|`4SELL (Liquidate to Locks)``|noflags|0|0|")
    ln("add_spacer|small|")
    ln("add_button|back|`wBack to Coin List``|noflags|0|0|")
    ln("end_dialog|" .. DLG_COIN .. "|Close||")

    sendDialog(player, table.concat(L))
end

---------------------------------------------------------------------------
-- BUY / SELL
---------------------------------------------------------------------------
local function pendingKey(player) return "crypto_pending_" .. player:getUserID() end
local function ensureAvailable(player)
    local hold=loadDataFromServer(pendingKey(player))
    assert(not hold or (type(hold)=="table" and next(hold)==nil),
        "Transaksi sebelumnya perlu diperiksa pengelola. Jangan ulangi transaksi.")
end
local function beginTrade(player, coin, amount, kind, total, port)
    ensureAvailable(player)
    local wallet={}
    for _, l in ipairs(locks) do
        wallet[#wallet+1]={id=l.itemID,value=l.value,inventory=player:getItemAmount(l.itemID),extra=player:getExtraBackpackAmount(l.itemID)}
    end
    save(pendingKey(player), {status="pending",kind=kind,coin=coin.id,amount=amount,totalWL=total,
        price=coin.price,fee=settings.fee,portfolioBefore=port[coin.id],wallet=wallet,at=os.time()})
end

local function doBuy(player, coinID, raw)
    local coin
    for _, c in ipairs(coins) do if c.id == coinID then coin = c; break end end
    if not coin then msg(player, "`4Coin not found."); return end
    ensureAvailable(player)
    local amount = tostring(raw or ""):match("^%d+$") and integer(raw,1,10000) or 0
    if amount <= 0 or amount > 10000 then msg(player, "`4Invalid amount (1-10000)."); showCoin(player,coinID); return end
    local cost = coin.price * amount
    assert(integer(cost,1,MAX_VALUE), "Total order melewati batas 2.000.000.000 WL.")
    if walletWL(player) < cost then
        msg(player, "`4Not enough locks. Need: `w" .. priceText(cost) .. "``.")
        showCoin(player,coinID)
        return
    end
    local uid = player:getUserID()
    local port = loadPort(uid)
    assert(port[coin.id]<=MAX_VALUE-amount, "Saldo coin melewati batas.")
    beginTrade(player,coin,amount,"buy",cost,port)
    assert(deductLocks(player,cost), "Gagal mengambil pembayaran; transaksi perlu diperiksa.")
    port[coin.id] = (port[coin.id] or 0) + amount
    savePort(uid, port)
    save(pendingKey(player), {})
    msg(player, "`2Bought " .. fmt(amount) .. " " .. coin.id .. " for " .. priceText(cost) .. ".")
    showCoin(player, coinID)
end

local function doSell(player, coinID, raw)
    local coin
    for _, c in ipairs(coins) do if c.id == coinID then coin = c; break end end
    if not coin then msg(player, "`4Coin not found."); return end
    ensureAvailable(player)
    local amount = tostring(raw or ""):match("^%d+$") and integer(raw,1,10000) or 0
    if amount <= 0 or amount > 10000 then msg(player, "`4Invalid amount (1-10000)."); showCoin(player,coinID); return end
    local uid = player:getUserID()
    local port = loadPort(uid)
    if (port[coin.id] or 0) < amount then
        msg(player, "`4You only have " .. fmt(port[coin.id] or 0) .. " " .. coin.id .. ".")
        showCoin(player,coinID)
        return
    end
    local fee = settings.fee or 0
    local gross = coin.price * amount
    assert(integer(gross,1,MAX_VALUE), "Total order melewati batas 2.000.000.000 WL.")
    local net = math.floor(gross * (100 - fee) / 100)
    assert(net>0, "Hasil jual setelah fee harus lebih dari nol.")
    beginTrade(player,coin,amount,"sell",net,port)
    port[coin.id] = port[coin.id] - amount
    savePort(uid, port)
    giveLocks(player, net)
    save(pendingKey(player), {})
    local feeWL = gross - net
    msg(player, "`2Sold " .. fmt(amount) .. " " .. coin.id .. " -> " .. priceText(net)
        .. (feeWL > 0 and (" `9(Fee: " .. priceText(feeWL) .. ")``") or "") .. ".")
    showCoin(player, coinID)
end

---------------------------------------------------------------------------
-- ADMIN: /setcrypto
---------------------------------------------------------------------------
local function showAdmin(player)
    local L = {}
    local function ln(s) L[#L + 1] = s .. "\n" end

    ln(coinLabel("big", "`wCrypto Market Management``", coins[1] or {}))
    ln("add_smalltext|`wAuto-Update Status: ``"
        .. (settings.autoFluct and "`2ACTIVE``" or "`4INACTIVE``") .. "|")
    for _, c in ipairs(coins) do
        if not c.iconID or c.iconID==0 or not getItem(c.iconID) then
            ln("add_smalltext|`9Logo " .. c.id .. " belum terhubung. Edit coin dan isi ID item logo asli.``|")
        end
    end
    ln("add_spacer|small|")

    -- Control buttons.
    ln("add_button|locks|`wManage Lock Values & Currency ID``|noflags|0|0|")
    ln("add_button|toggle|`wToggle Auto-Fluctuation``|noflags|0|0|")
    ln("add_button|cfg|`wConfigure Fee & Update Interval``|noflags|0|0|")
    ln("add_spacer|small|")

    -- Server total assets.
    ln("add_label|small|`wTotal Assets of Online Players:``|left|")
    local st = serverTotals()
    local grandTotal = 0
    for _, c in ipairs(coins) do
        local a = st[c.id] or 0
        local w = a * c.price
        grandTotal = grandTotal + w
        ln(coinLabel("small", "`w" .. c.name .. ": `2" .. fmt(a) .. " " .. c.id
            .. "`` = `w" .. priceText(w) .. "``", c))
    end
    ln("add_smalltext|`wGrand Total: `2" .. priceText(grandTotal) .. "``|")
    ln("add_spacer|small|")

    -- Manage coins.
    ln("add_label|small|`wManage Coins, Up/Down Chances & Manipulation:``|left|")
    for _, c in ipairs(coins) do
        ln(coinLabel("small", "`w" .. c.name .. " (" .. c.id .. ")`` = `2"
            .. priceText(c.price) .. "``", c))
        ln("add_button|edit_" .. c.id .. "|`2Edit " .. c.id .. " - Price GGL / Logo``|noflags|0|0|")
        ln("add_button|pump_" .. c.id .. "|`7Pump / Dump``|noflags|0|0|")
    end

    ln("add_spacer|small|")
    ln("add_button|addcoin|`2+ Add New Coin``|noflags|0|0|")
    ln("add_spacer|small|")
    ln("end_dialog|" .. DLG_ADMIN .. "|Close||")

    sendDialog(player, table.concat(L))
end

local function showEditCoin(player, coinID)
    local coin
    for _, c in ipairs(coins) do if c.id == coinID then coin = c; break end end
    if not coin then msg(player, "`4Coin not found."); return end

    local L = {}
    local function ln(s) L[#L + 1] = s .. "\n" end

    ln(coinLabel("big", "`wEdit: " .. coin.name .. " (" .. coin.id .. ")``", coin))
    ln("add_smalltext|Current price: `2" .. priceText(coin.price) .. "``|")
    ln("add_spacer|small|")
    ln("add_text_input|price|Harga per coin (GGL):|" .. priceText(coin.price):gsub(" GGL$", "") .. "|24|")
    ln("add_smalltext|Contoh: 2.5 berarti 2,5 GGL. Harga tersimpan mengikuti kurs GGL pada Manage Lock Values.|")
    ln("add_text_input|name|Coin Name:|" .. clean(coin.name) .. "|30|")
    ln("add_text_input|icon|ID custom item logo (0 = teks):|" .. (coin.iconID or 0) .. "|8|")
    ln("add_smalltext|Isi ID item dengan gambar " .. clean(coin.name) .. " yang sudah terpasang di client.|")
    ln("add_text_input|up|Peluang naik coin ini (0-100):|" .. (coin.upChance or settings.upChance) .. "|3|")
    ln("add_spacer|small|")
    ln("add_button|del_" .. coin.id .. "|`4Delete This Coin``|noflags|0|0|")
    ln("add_button|save_edit|`2Save Price / Logo``|noflags|0|0|")
    ln("add_button|back_admin|Back|noflags|0|0|")
    ln("end_dialog|" .. DLG_EDIT .. "_" .. coin.id .. "|Close||")

    sendDialog(player, table.concat(L))
end

local function showPump(player, coinID)
    local coin
    for _, c in ipairs(coins) do if c.id == coinID then coin = c; break end end
    if not coin then msg(player, "`4Coin not found."); return end

    local L = {}
    local function ln(s) L[#L + 1] = s .. "\n" end

    ln(coinLabel("big", "`wPump / Dump: " .. coin.name .. "``", coin))
    ln("add_smalltext|Current: `2" .. priceText(coin.price) .. "``|")
    ln("add_spacer|small|")
    ln("add_button|qp5_" .. coin.id .. "|`2Pump +5%``|noflags|0|0|")
    ln("add_button|qp10_" .. coin.id .. "|`2Pump +10%``|noflags|0|0|")
    ln("add_button|qp25_" .. coin.id .. "|`2Pump +25%``|noflags|0|0|")
    ln("add_button|qp50_" .. coin.id .. "|`2Pump +50%``|noflags|0|0|")
    ln("add_spacer|small|")
    ln("add_button|qd5_" .. coin.id .. "|`4Dump -5%``|noflags|0|0|")
    ln("add_button|qd10_" .. coin.id .. "|`4Dump -10%``|noflags|0|0|")
    ln("add_button|qd25_" .. coin.id .. "|`4Dump -25%``|noflags|0|0|")
    ln("add_button|qd50_" .. coin.id .. "|`4Dump -50%``|noflags|0|0|")
    ln("add_spacer|small|")
    ln("add_text_input|pct|Custom Percentage (%):|10|5|")
    ln("add_button|cpump_" .. coin.id .. "|`2Custom Pump``|noflags|0|0|")
    ln("add_button|cdump_" .. coin.id .. "|`4Custom Dump``|noflags|0|0|")
    ln("add_spacer|small|")
    ln("add_button|back_admin|`wBack``|noflags|0|0|")
    ln("end_dialog|" .. DLG_PUMP .. "_" .. coin.id .. "|Close||")

    sendDialog(player, table.concat(L))
end

local function showLocks(player)
    local L = {}
    local function ln(s) L[#L + 1] = s .. "\n" end

    ln("add_label|big|`w+ Register New Lock ID``|left|")
    ln("add_spacer|small|")
    ln("add_label|small|`wActive Registered Locks (Sorted by Value):``|left|")
    for _, l in ipairs(locksDesc()) do
        ln("add_label_with_icon|small|`w" .. l.name .. "`` (ID: " .. l.itemID
            .. ") = `2" .. fmt(l.value) .. " WL``|left|" .. l.itemID .. "|")
        ln("add_button|elck_" .. l.itemID .. "|`2Edit Value``|noflags|0|0|")
        ln("add_button|dlck_" .. l.itemID .. "|`4Delete Lock``|noflags|0|0|")
    end
    ln("add_spacer|small|")
    ln("add_text_input|nlid|New Lock Item ID:|0|8|")
    ln("add_text_input|nlval|Value (WL):|100|24|")
    ln("add_button|addlck|`2+ Register Lock``|noflags|0|0|")
    ln("add_spacer|small|")
    ln("add_button|back_admin|`wBack``|noflags|0|0|")
    ln("end_dialog|" .. DLG_LOCKS .. "|Close||")

    sendDialog(player, table.concat(L))
end

local function showLockEdit(player, itemID)
    local lock
    for _, l in ipairs(locks) do if l.itemID == itemID then lock = l; break end end
    if not lock then msg(player, "`4Lock not found."); return end
    local L = {}
    local function ln(s) L[#L + 1] = s .. "\n" end
    ln("add_label_with_icon|big|`wEdit: " .. lock.name .. "``|left|" .. lock.itemID .. "|")
    ln("add_smalltext|Item ID: " .. lock.itemID .. "|")
    ln("add_text_input|val|New Value (WL):|" .. math.floor(lock.value) .. "|24|")
    ln("add_smalltext|Contoh nilai lock: 1000000 atau 1.000.000 WL.|")
    ln("add_button|save_lock|`2Save``|noflags|0|0|")
    ln("add_button|back_locks|Back|noflags|0|0|")
    ln("end_dialog|" .. DLG_LVAL .. "_" .. lock.itemID .. "|Close||")
    sendDialog(player, table.concat(L))
end

local function showSettings(player)
    local L = {}
    local function ln(s) L[#L + 1] = s .. "\n" end
    ln("add_label|big|`wConfigure Settings``|left|")
    ln("add_spacer|small|")
    ln("add_text_input|fee|Selling Admin Fee (%):|" .. (settings.fee or 5) .. "|5|")
    ln("add_text_input|interval|Price Update Interval (Seconds):|" .. (settings.interval or 30) .. "|5|")
    ln("add_text_input|up|Up Chance (0-100):|" .. (settings.upChance or 55) .. "|5|")
    ln("add_text_input|maxc|Max Change per Tick (%):|" .. (settings.maxChange or 3) .. "|5|")
    ln("add_spacer|small|")
    ln("add_button|save_cfg|`2Save Settings``|noflags|0|0|")
    ln("add_button|back_admin|`wBack``|noflags|0|0|")
    ln("end_dialog|" .. DLG_SET .. "|Close||")
    sendDialog(player, table.concat(L))
end

local function showAddCoin(player)
    local L = {}
    local function ln(s) L[#L + 1] = s .. "\n" end
    ln("add_label|big|`wAdd New Coin``|left|")
    ln("add_text_input|cid|Code (max 5, e.g. DOGE):|DOGE|5|")
    ln("add_text_input|cname|Coin Name:|Dogecoin|20|")
    ln("add_text_input|cprice|Initial Price (GGL):|1|24|")
    ln("add_text_input|cicon|ID custom item logo (0 = teks):|0|8|")
    ln("add_button|save_add|`2Add Coin``|noflags|0|0|")
    ln("add_button|back_admin|Back|noflags|0|0|")
    ln("end_dialog|" .. DLG_ADD .. "|Close||")
    sendDialog(player, table.concat(L))
end

---------------------------------------------------------------------------
-- AUTO FLUCTUATION
---------------------------------------------------------------------------
local function fluctuate()
    if not settings.autoFluct then return end
    for _, c in ipairs(coins) do
        local up = c.upChance or settings.upChance or 55
        local maxPct = settings.maxChange or 3
        local pct = math.random(1, math.max(1, maxPct * 100)) / 100
        c.prevPrice = c.price
        if math.random(1, 100) <= up then
            c.price = math.min(MAX_PRICE, math.floor(c.price * (1 + pct / 100)))
        else
            c.price = math.max(1, math.floor(c.price * (1 - pct / 100)))
        end
    end
    saveCoins(true)
end

local function startFluct()
    if fluctTimer then timer.clearInterval(fluctTimer) end
    if not settings.autoFluct then return end
    fluctTimer = timer.setInterval(math.max(1, math.min(3600, settings.interval or 30)),
        function()
            if not ready then return end
            local ok,err=pcall(fluctuate)
            if not ok then
                ready=false; unavailableReason="Auto-update: "..tostring(err)
                print("[crypto] Auto-update failed: "..tostring(err))
            end
        end)
end

local function stopFluct()
    if fluctTimer then timer.clearInterval(fluctTimer); fluctTimer = nil end
end

local function applyPD(player, coinID, pct, isPump)
    for _, c in ipairs(coins) do
        if c.id == coinID then
            c.prevPrice = c.price
            if isPump then c.price = math.min(MAX_PRICE, math.floor(c.price * (1 + pct / 100)))
            else c.price = math.max(1, math.floor(c.price * (1 - pct / 100))) end
            saveCoins()
            msg(player, "`2" .. (isPump and "PUMP +" or "DUMP -") .. dec(pct)
                .. "% " .. c.id .. ". New: " .. priceText(c.price))
            return
        end
    end
end

---------------------------------------------------------------------------
-- CALLBACKS
---------------------------------------------------------------------------
onPlayerDialogCallback(function(w, p, d)
    if d.dialog_name ~= DLG_MAIN then return false end
    local btn = d.buttonClicked or ""
    if btn == "refresh" then showMain(p); return true end
    local id = tostring(btn):match("^sel_(.+)$")
    if id then showCoin(p, id); return true end
    return true
end)

onPlayerDialogCallback(function(w, p, d)
    if d.dialog_name ~= DLG_COIN then return false end
    local btn = d.buttonClicked or ""
    if btn == "back" then showMain(p); return true end
    local b = tostring(btn):match("^buy_(.+)$")
    if b then doBuy(p, b, d.amount); return true end
    local s = tostring(btn):match("^sell_(.+)$")
    if s then doSell(p, s, d.amount); return true end
    return true
end)

onPlayerDialogCallback(function(w, p, d)
    if d.dialog_name ~= DLG_ADMIN then return false end
    if not isFounder(p) then return true end
    local btn = d.buttonClicked or ""
    if btn == "locks" then showLocks(p); return true end
    if btn == "cfg" then showSettings(p); return true end
    if btn == "addcoin" then showAddCoin(p); return true end
    if btn == "toggle" then
        settings.autoFluct = not settings.autoFluct; saveSettings()
        if settings.autoFluct then startFluct(); msg(p, "`2Auto-fluctuation ON.")
        else stopFluct(); msg(p, "`4Auto-fluctuation OFF.") end
        showAdmin(p); return true
    end
    local e = tostring(btn):match("^edit_(.+)$")
    if e then showEditCoin(p, e); return true end
    local pm = tostring(btn):match("^pump_(.+)$")
    if pm then showPump(p, pm); return true end
    return true
end)

onPlayerDialogCallback(function(w, p, d)
    local cid = tostring(d.dialog_name or ""):match("^" .. DLG_EDIT .. "_(.+)$")
    if not cid then return false end
    if not isFounder(p) then return true end
    local btn = d.buttonClicked or ""
    local del = tostring(btn):match("^del_(.+)$")
    if btn=="back_admin" then showAdmin(p); return true end
    if del then
        assert(del~="BTC" and del~="ETH" and del~="LTC", "BTC, ETH, dan LTC adalah aset utama; tidak dapat dihapus.")
        for i, c in ipairs(coins) do
            if c.id == del then table.remove(coins, i); saveCoins()
                msg(p, "`2" .. del .. " deleted."); break end
        end
        showAdmin(p); return true
    end
    if btn~="save_edit" then return true end
    local np = parseGGL(d.price)
    local nn = clean(d.name or "")
    local ni = integer(d.icon, 0, MAX_VALUE)
    assert(ni and (ni==0 or getItem(ni)), "ID item logo tidak tersedia di server.")
    local up = assert(integer(d.up,0,100), "Peluang naik harus 0-100.")
    if np <= 0 then msg(p, "`4Price must be > 0."); showEditCoin(p, cid); return true end
    if nn == "" then msg(p, "`4Name empty."); showEditCoin(p, cid); return true end
    for _, c in ipairs(coins) do
        if c.id == cid then
            c.prevPrice = c.price; c.price = np; c.name = nn:sub(1, 30)
            c.iconID = ni; c.upChance=up; break
        end
    end
    saveCoins(); msg(p, "`2Harga " .. cid .. " tersimpan: " .. priceText(np) .. "."
        .. (settings.autoFluct and " Auto-Fluctuation ON: harga dapat berubah lagi. Matikan Toggle Auto-Fluctuation untuk harga tetap." or ""))
    showAdmin(p); return true
end)

onPlayerDialogCallback(function(w, p, d)
    local cid = tostring(d.dialog_name or ""):match("^" .. DLG_PUMP .. "_(.+)$")
    if not cid then return false end
    if not isFounder(p) then return true end
    local btn = d.buttonClicked or ""
    if btn == "back_admin" then showAdmin(p); return true end
    local qp = tostring(btn):match("^qp(%d+)_")
    if qp then applyPD(p, cid, tonumber(qp), true); showPump(p, cid); return true end
    local qd = tostring(btn):match("^qd(%d+)_")
    if qd then applyPD(p, cid, tonumber(qd), false); showPump(p, cid); return true end
    local cp = tostring(btn):match("^cpump_")
    local cd = tostring(btn):match("^cdump_")
    if cp or cd then
        local pct = math.abs(tonumber(d.pct) or 0)
        if pct > 0 and pct <= 500 then applyPD(p, cid, pct, cp ~= nil)
        else msg(p, "`4Percentage 1-500.") end
        showPump(p, cid); return true
    end
    return true
end)

onPlayerDialogCallback(function(w, p, d)
    if d.dialog_name ~= DLG_LOCKS then return false end
    if not isFounder(p) then return true end
    local btn = d.buttonClicked or ""
    if btn == "back_admin" then showAdmin(p); return true end
    if btn == "addlck" then
        assert(#locks<8, "Maksimal 8 lock.")
        local nid = integer(d.nlid,1,MAX_VALUE) or 0
        local nv = lockValue(d.nlval) or 0
        if nid <= 0 then msg(p, "`4Invalid ID."); showLocks(p); return true end
        if nv <= 0 then msg(p, "`4Value > 0."); showLocks(p); return true end
        for _, l in ipairs(locks) do
            if l.itemID == nid then msg(p, "`4ID exists."); showLocks(p); return true end
        end
        local item = assert(getItem(nid), "Item lock tidak ditemukan.")
        local nm = "Item #" .. nid
        if item then local n = clean(item:getName()); if n ~= "" then nm = n end end
        locks[#locks + 1] = { itemID = nid, name = nm, value = nv }
        saveLocks(); msg(p, "`2" .. nm .. " registered."); showLocks(p); return true
    end
    local el = tostring(btn):match("^elck_(%d+)$")
    if el then showLockEdit(p, tonumber(el)); return true end
    local dl = tostring(btn):match("^dlck_(%d+)$")
    if dl then
        local did = tonumber(dl)
        assert(did~=242 and did~=GGL_ITEM_ID, "WL dan GGL wajib tersedia untuk harga serta kembalian.")
        for i, l in ipairs(locks) do
            if l.itemID == did then msg(p, "`2" .. l.name .. " deleted.")
                table.remove(locks, i); saveLocks(); break end
        end
        showLocks(p); return true
    end
    return true
end)

onPlayerDialogCallback(function(w, p, d)
    local lid = tostring(d.dialog_name or ""):match("^" .. DLG_LVAL .. "_(%d+)$")
    if not lid then return false end
    if not isFounder(p) then return true end
    if d.buttonClicked=="back_locks" then showLocks(p); return true end
    if d.buttonClicked~="save_lock" then return true end
    local nv = lockValue(d.val)
    if not nv then msg(p, "`4Nilai lock tidak valid. Gunakan angka seperti 1000000 atau 1.000.000."); showLockEdit(p,tonumber(lid)); return true end
    lid = tonumber(lid)
    assert(lid~=242 or nv==1, "Nilai WL wajib 1.")
    for _, l in ipairs(locks) do
        if l.itemID == lid then l.value = nv; break end
    end
    saveLocks(); msg(p,"`2Nilai lock #" .. lid .. " tersimpan: " .. fmt(nv) .. " WL."); showLocks(p); return true
end)

onPlayerDialogCallback(function(w, p, d)
    if d.dialog_name ~= DLG_SET then return false end
    if not isFounder(p) then return true end
    local btn = d.buttonClicked or ""
    if btn == "back_admin" then showAdmin(p); return true end
    if btn == "save_cfg" then
        settings.fee = math.max(0, math.min(100, math.floor(tonumber(d.fee) or 5)))
        settings.interval = math.max(1, math.min(3600, math.floor(tonumber(d.interval) or 30)))
        settings.upChance = math.max(0, math.min(100, math.floor(tonumber(d.up) or 55)))
        settings.maxChange = math.max(1, math.min(50, math.floor(tonumber(d.maxc) or 3)))
        saveSettings()
        if settings.autoFluct then startFluct() end
        msg(p, "`2Settings saved.")
        showAdmin(p); return true
    end
    return true
end)

onPlayerDialogCallback(function(w, p, d)
    if d.dialog_name ~= DLG_ADD then return false end
    if not isFounder(p) then return true end
    if d.buttonClicked=="back_admin" then showAdmin(p); return true end
    if d.buttonClicked~="save_add" then return true end
    local id = tostring(d.cid or ""):upper():gsub("[^A-Z0-9]", ""):sub(1, 5)
    local nm = clean(d.cname or ""):sub(1, 30)
    assert(#coins<MAX_COINS, "Maksimal 8 coin.")
    local pr = parseGGL(d.cprice)
    local ic = integer(d.cicon,0,MAX_VALUE)
    assert(ic and (ic==0 or getItem(ic)), "ID item logo tidak ditemukan.")
    if id == "" or nm == "" or pr <= 0 then msg(p, "`4Fill all fields."); showAddCoin(p); return true end
    for _, c in ipairs(coins) do
        if c.id == id then msg(p, "`4" .. id .. " exists."); showAddCoin(p); return true end
    end
    coins[#coins + 1] = { id = id, name = nm, price = pr, prevPrice = pr, iconID = ic }
    saveCoins(); msg(p, "`2" .. nm .. " (" .. id .. ") added.")
    showAdmin(p); return true
end)

---------------------------------------------------------------------------
-- COMMANDS
---------------------------------------------------------------------------
local function showUnavailable(p)
    if not isFounder(p) then msg(p,"`4Market sementara belum tersedia. Hubungi Founder."); return end
    sendDialog(p,"add_label|big|`4Crypto - Market Offline``|left|\n"
        .."add_smalltext|`wPenyebab: "..clean(unavailableReason,300).."``|\n"
        .."add_smalltext|Muat ulang membaca data tersimpan; tidak mereset harga/saldo atau mengulang transaksi.|\n"
        .."add_button|retry_init|Coba Muat Ulang Market|noflags|0|0|\n"
        .."end_dialog|"..DLG_RECOVERY.."|Close||")
end

local function guard(p, fn)
    if not p or not p:isOnline() then return end
    if not ready then showUnavailable(p); return end
    local uid=p:getUserID()
    if busy[uid] then return end
    busy[uid]=true
    local ok,err=pcall(fn)
    busy[uid]=nil
    if not ok then
        sessions[uid]=nil
        msg(p,"`4"..clean(tostring(err):gsub("^.-:%d+:%s*", "")))
        print("[crypto] uid="..uid.." "..tostring(err))
        -- Muat konfigurasi terakhir yang tersimpan jika penyimpanan edit gagal.
        local loaded,loadError=pcall(loadAll)
        if not loaded then
            ready=false; unavailableReason=tostring(loadError)
            print("[crypto] Recovery failed: "..unavailableReason)
            showUnavailable(p); return
        end
        pcall(showMain,p)
    end
end

local function handleDialog(w,p,d)
    if type(d)~="table" or type(d.dialog_name)~="string" or not d.dialog_name:match("^crypto_") then return false end
    if not p or not p:isOnline() then return true end
    local uid=p:getUserID()
    local recovery=sessions[uid]
    if recovery and recovery.original==DLG_RECOVERY and recovery.name==d.dialog_name then
        if busy[uid] then return true end
        sessions[uid]=nil
        if d.quit=="1" or d.quit==1 or d.buttonClicked=="Close" or not d.buttonClicked or d.buttonClicked=="" then return true end
        if not isFounder(p) then msg(p,"`4Founder only."); return true end
        if recovery.expires<=os.time() or d.buttonClicked~="retry_init" then
            if ready then showAdmin(p) else showUnavailable(p) end
            return true
        end
        busy[uid]=true
        if not ready then initialize() end
        busy[uid]=nil
        if ready then showAdmin(p) else showUnavailable(p) end
        return true
    end
    guard(p,function()
        local uid=p:getUserID()
        local state=sessions[uid]
        local clicked=tostring(d.buttonClicked or "")
        if d.quit=="1" or d.quit==1 or clicked=="" or clicked=="Close" or clicked=="Cancel" then
            if state and state.name==d.dialog_name then sessions[uid]=nil end
            return
        end
        if not state or state.name~=d.dialog_name or state.expires<=os.time() then showMain(p); return end
        local admin=state.original~=DLG_MAIN and state.original~=DLG_COIN
        if admin and not isFounder(p) then sessions[uid]=nil; msg(p,"`4Founder only."); showMain(p); return end
        if not state.allowed[clicked] then showMain(p); return end
        sessions[uid]=nil -- satu dialog hanya dapat dipakai sekali, tanpa embed_data.
        local changed=(admin and state.configRevision~=configRevision) or (not admin and state.revision~=marketRevision)
        if changed and clicked~="refresh" and clicked~="back" and clicked~="back_admin" then
            msg(p,"Harga/pengaturan berubah. Menu terbaru sudah dibuka; periksa sebelum melanjutkan.")
            if admin then showAdmin(p) else showMain(p) end
            return
        end
        local data={}
        for key,value in pairs(d) do data[key]=value end
        data.dialog_name=state.original
        for _,fn in ipairs(handlers) do if fn(w,p,data) then return end end
    end)
    return true
end

local function handleCommand(w, p, cmd)
    local c = tostring(cmd):match("^%s*/?(%S+)")
    if not c then return false end
    c = c:lower()
    if c == "crypto" then guard(p,function() showMain(p) end); return true end
    if c == "setcrypto" then
        if not isFounder(p) then msg(p, "`4Founder only."); return true end
        guard(p,function() showAdmin(p) end); return true
    end
    return false
end

-- Pasang setiap jalur secara independen: kegagalan registrasi nama command
-- atau hook opsional tidak boleh menghentikan pemasangan jalur lainnya.
local function install(label,fn,arg)
    if type(fn)~="function" then
        print("[crypto] ROUTE FAILED "..label..": API tidak tersedia")
        return false
    end
    local ok,result=pcall(fn,arg)
    if not ok or result==false then
        print("[crypto] ROUTE FAILED "..label..": "..tostring(result))
        return false
    end
    return true
end

local dialogInstalled=install("dialog",nativeDialogCallback,handleDialog)
local commandInstalled=install("command",onPlayerCommandCallback,handleCommand)
local inputInstalled=install("input",onPlayerActionCallback,function(w,p,data)
    if type(data)~="table" or data.action~="input" or type(data.text)~="string" then return false end
    -- Chat biasa dan command dengan awalan mirip tidak diambil alih.
    if not data.text:match("^%s*/%S+") then return false end
    return handleCommand(w,p,data.text)
end)
local cryptoInstalled=install("/crypto",registerLuaCommand,{
    command="crypto",roleRequired=0,description="Open Crypto Digital Marketplace.",
    callback=function(p,args) return handleCommand(nil,p,"crypto") end,
})
local adminInstalled=install("/setcrypto",registerLuaCommand,{
    command="setcrypto",roleRequired=FOUNDER_ROLE,exactRole=true,description="Founder: manage crypto market.",
    callback=function(p,args) return handleCommand(nil,p,"setcrypto") end,
})
install("disconnect",onPlayerDisconnectCallback,function(p)
    if p then sessions[p:getUserID()],busy[p:getUserID()]=nil,nil end
end)
print("[crypto] ROUTES v3: /crypto="..tostring(cryptoInstalled)..", /setcrypto="..tostring(adminInstalled)
    ..", command="..tostring(commandInstalled)..", input="..tostring(inputInstalled)..", dialog="..tostring(dialogInstalled))

initialize=function()
    ready=false
    sessions={}
    local initialized, initError=pcall(function()
        assert(dialogInstalled,"Hook dialog gagal dipasang; periksa log ROUTE FAILED.")
        assert(commandInstalled or inputInstalled or (cryptoInstalled and adminInstalled),
            "Jalur command gagal dipasang; periksa log ROUTE FAILED.")
        stopFluct()
        loadAll()
        local stored=loadDataFromServer("crypto_ui_generation")
        assert(stored==nil or type(stored)=="table","crypto_ui_generation: data bukan tabel")
        generation=(stored and assert(integer(stored.value,0,9007199254740990),"Invalid generation") or 0)+1
        save("crypto_ui_generation",{value=generation})
        startFluct()
    end)
    ready=initialized
    unavailableReason=initialized and nil or tostring(initError)
    print(ready and "[crypto] Loaded. /crypto: marketplace GGL, /setcrypto: Founder."
        or ("[crypto] INIT FAILED: "..tostring(initError)))
    return initialized
end
initialize()
