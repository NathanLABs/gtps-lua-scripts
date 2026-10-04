-- Developer: Nathan
-- gemstobgl.lua - Command untuk semua player: /sell2
-- Upload hanya file ini ke Lua Scripts, lalu reload.
-- Dua arah: gems <-> BGL. 30.000.000 gems = 1 BGL, tanpa biaya tambahan.
-- Menggunakan gems yang dibawa serta BGL inventory/Extra Backpack, bukan bank.
-- Auto-convert aktif untuk semua player pada >= 1.950.000.000 gems.
-- Seluruh kelipatan kurs ditukar; sisa gems tetap disimpan. Cek tiap player tick.
-- Journal otomatis: gemstobgl_v1.db di folder server; backup bersama data player.
-- API engine tidak menyediakan transaksi/save atomik gems + item + SQLite.
-- Transaksi pending tidak dicoba ulang otomatis, termasuk setelah reload.

local GEMS_PER_BGL = 30000000
local BGL_ITEM_ID = 7188
local MAX_GEMS = 2000000000 -- Batas saldo gems engine.
local AUTO_CONVERT_GEMS = 1950000000 -- Ambang sebelum limit; dapat diubah admin.
local AUTO_RETRY_SECONDS = 30 -- Jeda setelah kegagalan; sukses bisa langsung aktif lagi.
local MAX_SAFE_INTEGER = 9007199254740991
local MAX_BGL = math.floor(MAX_GEMS / GEMS_PER_BGL)
local SESSION_SECONDS = 120
local DB_FILE = "gemstobgl_v1.db"
local DIALOG_PREFIX = "gemstobgl_"
local TO_BGL = "gems_to_bgl"
local TO_GEMS = "bgl_to_gems"
local sessions, busy = {}, {}
local autoState = {}
local db, ready, generation
local serial = 0

local function integer(value, minimum, maximum)
    if type(value) ~= "number" or value ~= value or value < minimum
        or value > maximum or value ~= math.floor(value) then return nil end
    return value
end

local function num(value)
    return string.format("%.0f", value)
end

local function fmt(value)
    return num(value):reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
end

local function sql(value)
    return "'" .. tostring(value):gsub("%z", ""):gsub("'", "''") .. "'"
end

local function query(statement)
    local rows = db:query(statement)
    assert(type(rows) == "table", "Database penukaran tidak dapat diakses.")
    return rows
end

local function uid(player)
    return assert(integer(player:getUserID(), 1, MAX_SAFE_INTEGER), "Invalid user ID")
end

local function notify(player, text)
    player:onConsoleMessage("`6[Gems / BGL]`` " .. text)
end

local function snapshot(player)
    return {
        gems = assert(integer(player:getGems(), 0, MAX_GEMS), "Invalid gems balance"),
        inventory = assert(integer(player:getItemAmount(BGL_ITEM_ID), 0, MAX_SAFE_INTEGER), "Invalid BGL inventory"),
        extra = assert(integer(player:getExtraBackpackAmount(BGL_ITEM_ID), 0, MAX_SAFE_INTEGER), "Invalid Extra Backpack"),
    }
end

local function sameItems(a, b)
    return a.inventory == b.inventory and a.extra == b.extra
end

local function pending(id)
    return query("SELECT id FROM exchanges WHERE uid=" .. num(id) .. " AND status='pending' LIMIT 1")[1]
end

local function available(player)
    local row = pending(uid(player))
    if not row then return true end
    sessions[uid(player)] = nil
    notify(player, "`4Penukaran #" .. num(row.id) .. " perlu diperiksa admin.`` Sampaikan nomor ini ke admin sebelum menukar lagi.")
    return false
end

local function heading(title)
    return {
        "add_label_with_icon|big|`w" .. title .. "``|left|" .. BGL_ITEM_ID .. "|\n",
        "add_spacer|small|\n",
    }
end

local function line(lines, text)
    lines[#lines + 1] = "add_smalltext|" .. text .. "|\n"
end

local function button(lines, name, text)
    lines[#lines + 1] = "add_button|" .. name .. "|" .. text .. "|noflags|0|0|\n"
end

local function show(player, lines, state)
    serial = serial + 1
    -- dialog_name selalu dikirim kembali oleh client; custom embed_data belum
    -- tentu ikut. Ikat sesi ke nama dialog unik, bukan field sell2_token.
    state.dialogName = DIALOG_PREFIX .. state.view .. "_" .. num(generation) .. "_" .. num(serial)
    state.expires = os.time() + SESSION_SECONDS
    sessions[uid(player)] = state
    lines[#lines + 1] = "add_spacer|small|\nadd_smalltext|`9© Dibuat Oleh : Nathan``|\n"
    lines[#lines + 1] = "end_dialog|" .. state.dialogName .. "|Tutup||\n"
    local markup = table.concat(lines)
    assert(#markup < 4096, "Dialog exceeds packet limit")
    player:onDialogRequest(markup)
end

local function maximumFor(balance, direction)
    if direction == TO_GEMS then
        -- Batasi tiap sumber sebelum dijumlahkan agar tidak overflow.
        return math.min(math.floor((MAX_GEMS - balance.gems) / GEMS_PER_BGL),
            math.min(balance.inventory, MAX_BGL) + math.min(balance.extra, MAX_BGL))
    end
    return math.floor(balance.gems / GEMS_PER_BGL)
end

local function reverseError(balance, amount)
    if balance.inventory < amount and balance.extra < amount - balance.inventory then
        return "BGL di inventory dan Extra Backpack tidak cukup untuk menukar " .. fmt(amount) .. " BGL."
    end
    if amount * GEMS_PER_BGL > MAX_GEMS - balance.gems then
        return "Saldo gems akan melebihi " .. fmt(MAX_GEMS) .. ". Maksimal saat ini "
            .. fmt(maximumFor(balance, TO_GEMS)) .. " BGL."
    end
end

local function form(player, amount, notice, direction)
    direction = direction or TO_BGL
    if not available(player) then return end
    local balance = snapshot(player)
    local reverse = direction == TO_GEMS
    local maximum = maximumFor(balance, direction)
    local lines = heading(reverse and "BGL TO GEMS" or "GEMS TO BGL")
    button(lines, reverse and "to_bgl" or "to_gems", reverse and "Ganti: Gems ke BGL" or "Ganti: BGL ke Gems")
    line(lines, reverse and "Tukar Blue Gem Lock kamu menjadi gems." or "Tukar gems kamu menjadi Blue Gem Lock.")
    line(lines, "`9Kurs tetap: `w" .. fmt(GEMS_PER_BGL) .. " gems `9= `21 BGL``")
    line(lines, "Biaya tambahan: `2Tidak ada``")
    line(lines, "`2Auto-convert aktif`` mulai " .. fmt(AUTO_CONVERT_GEMS) .. " gems; sisa gems tetap disimpan.")
    lines[#lines + 1] = "add_spacer|small|\n"
    line(lines, "Gems kamu: `w" .. fmt(balance.gems) .. "``")
    line(lines, "BGL di inventory: `w" .. fmt(balance.inventory) .. "``  -  Extra Backpack: `w" .. fmt(balance.extra) .. "``")
    line(lines, "Bisa ditukar sekarang: `2" .. fmt(maximum) .. " BGL``")
    if notice then line(lines, "`4" .. notice .. "``") end
    if maximum == 0 then
        if reverse then
            line(lines, balance.inventory == 0 and balance.extra == 0
                and "Kamu belum memiliki BGL di inventory atau Extra Backpack."
                or "Ruang saldo gems belum cukup untuk menerima hasil 1 BGL.")
        else
            line(lines, "Butuh `w" .. fmt(GEMS_PER_BGL - balance.gems) .. " gems`` lagi untuk 1 BGL.")
        end
    end
    lines[#lines + 1] = "add_spacer|small|\n"
    lines[#lines + 1] = "add_text_input|sell2_amount|Jumlah BGL|" .. num(amount or 1) .. "|10|\n"
    if reverse then
        line(lines, "Isi jumlah BGL yang ingin ditukar, contoh: 2 BGL = " .. fmt(2 * GEMS_PER_BGL) .. " gems.")
        line(lines, "BGL diambil dari inventory dahulu, lalu Extra Backpack jika diperlukan.")
        line(lines, "Gems masuk ke saldo yang dibawa. Batas saldo: " .. fmt(MAX_GEMS) .. " gems.")
    else
        line(lines, "Isi jumlah BGL yang ingin diterima, contoh: 2 = " .. fmt(2 * GEMS_PER_BGL) .. " gems.")
        line(lines, "Gems di bank tidak digunakan. Sisa gems tetap milikmu.")
        line(lines, "Inventory penuh? BGL otomatis masuk ke Extra Backpack.")
    end
    if maximum > 0 then
        button(lines, "review", "`2Lanjut ke Konfirmasi``")
        button(lines, "maximum", "Tukar Maksimal (" .. fmt(maximum) .. " BGL)")
    end
    button(lines, "refresh", "Refresh Saldo")
    show(player, lines, { view = "form", direction = direction })
end

local function parseAmount(value)
    if type(value) ~= "string" or #value > 10 then return nil end
    local digits = value:match("^%s*(%d+)%s*$")
    if not digits then return nil end
    return integer(tonumber(digits), 1, MAX_BGL)
end

local function review(player, amount, direction)
    direction = direction or TO_BGL
    if not available(player) then return end
    if not amount then
        form(player, nil, "Isi angka bulat 1-" .. MAX_BGL .. ", tanpa titik atau koma.", direction)
        return
    end
    local balance = snapshot(player)
    local cost = amount * GEMS_PER_BGL
    local reverse = direction == TO_GEMS
    if reverse then
        local why = reverseError(balance, amount)
        if why then form(player, amount, why, direction); return end
    elseif balance.gems < cost then
        form(player, amount, "Gems kurang " .. fmt(cost - balance.gems) .. " untuk " .. fmt(amount) .. " BGL.")
        return
    end
    local lines = heading("KONFIRMASI PENUKARAN")
    if reverse then
        local fromInventory = math.min(balance.inventory, amount)
        line(lines, "BGL yang ditukar: `4" .. fmt(amount) .. " Blue Gem Lock``")
        line(lines, "Kamu menerima: `2" .. fmt(cost) .. " gems``")
        line(lines, "Gems sekarang: `w" .. fmt(balance.gems) .. "``")
        line(lines, "Gems setelah ditukar: `w" .. fmt(balance.gems + cost) .. "``")
        line(lines, "Dari inventory: " .. fmt(fromInventory) .. " BGL; Extra Backpack: " .. fmt(amount - fromInventory) .. " BGL.")
        line(lines, "Sumber BGL dicek ulang saat konfirmasi; inventory selalu digunakan lebih dahulu.")
        if balance.gems + cost >= AUTO_CONVERT_GEMS then
            line(lines, "`4Hasil mencapai ambang auto-convert: gems akan otomatis ditukar kembali menjadi BGL.``")
            line(lines, "Pilih jumlah lebih kecil jika ingin menyimpan hasilnya sebagai gems.")
        end
    else
        line(lines, "Kamu menerima: `2" .. fmt(amount) .. " Blue Gem Lock``")
        line(lines, "Total biaya: `4" .. fmt(cost) .. " gems``")
        line(lines, "Gems sekarang: `w" .. fmt(balance.gems) .. "``")
        line(lines, "Sisa gems: `w" .. fmt(balance.gems - cost) .. "``")
    end
    lines[#lines + 1] = "add_spacer|small|\n"
    line(lines, "Periksa jumlahnya, lalu tekan Tukar Sekarang.")
    line(lines, "Konfirmasi berlaku " .. SESSION_SECONDS .. " detik. Saldo dicek kembali saat menukar.")
    button(lines, "confirm", "`2Tukar Sekarang: " .. (reverse and (fmt(cost) .. " Gems") or (fmt(amount) .. " BGL")) .. "``")
    button(lines, "back", "Ubah Jumlah / Kembali")
    -- Harga dan jumlah dipercaya dari state server, bukan field kiriman client.
    show(player, lines, { view = "confirm", amount = amount, direction = direction })
end

local function beginExchange(id, amount, cost, before, direction, automatic)
    query("BEGIN IMMEDIATE")
    local ok, result = pcall(function()
        query("INSERT INTO exchanges(uid,item_id,amount,cost,gems_before,inventory_before,extra_before,status,created_at,direction,automatic) VALUES("
            .. num(id) .. "," .. BGL_ITEM_ID .. "," .. num(amount) .. "," .. num(cost) .. ","
            .. num(before.gems) .. "," .. num(before.inventory) .. "," .. num(before.extra) .. ",'pending'," .. os.time()
            .. "," .. sql(direction or TO_BGL) .. "," .. (automatic and "1" or "0") .. ")")
        return assert(tonumber(query("SELECT last_insert_rowid() AS id")[1].id), "Missing journal ID")
    end)
    if not ok then
        pcall(function() query("ROLLBACK") end)
        error(result)
    end
    local committed, why = pcall(function() query("COMMIT") end)
    if not committed then
        pcall(function() query("ROLLBACK") end)
        error(why)
    end
    return result
end

local function finishExchange(id, status, after, note)
    query("UPDATE exchanges SET status=" .. sql(status) .. ",gems_after=" .. num(after.gems)
        .. ",inventory_after=" .. num(after.inventory) .. ",extra_after=" .. num(after.extra)
        .. ",finished_at=" .. os.time() .. ",note=" .. sql(note or "")
        .. " WHERE id=" .. num(id) .. " AND status='pending'")
end

local function hold(id, stage, apiOK, result, readOK, after)
    local details = stage .. " api_ok=" .. tostring(apiOK) .. " result=" .. tostring(result)
        .. (readOK and (" gems=" .. num(after.gems) .. " inventory=" .. num(after.inventory) .. " extra=" .. num(after.extra))
            or (" read_error=" .. tostring(after)))
    -- Tetap pending. Catatan sebisa mungkin disimpan; jangan memindahkan aset lagi.
    pcall(function() query("UPDATE exchanges SET note=" .. sql(details) .. " WHERE id=" .. num(id)) end)
    print("[gemstobgl] NEEDS REVIEW #" .. num(id) .. " " .. details)
    error("Penukaran #" .. num(id) .. " perlu diperiksa admin.")
end

local function exchangeNotice(player, amount, text, automatic)
    if automatic then notify(player, "`4Auto-convert: ``" .. text)
    else form(player, amount, text) end
end

local function exchange(player, amount, automatic)
    assert(integer(amount, 1, MAX_BGL), "Invalid server-side amount")
    if not available(player) then return end
    assert(getItem(BGL_ITEM_ID), "Item BGL tidak tersedia di server.")
    local before = snapshot(player)
    if automatic then
        if before.gems < AUTO_CONVERT_GEMS then return false end
        amount = math.floor(before.gems / GEMS_PER_BGL)
    end
    local cost = amount * GEMS_PER_BGL
    if before.gems < cost then
        exchangeNotice(player, amount, "Saldo berubah. Gems kurang " .. fmt(cost - before.gems) .. "; belum ada gems dipotong.", automatic)
        return false
    end
    -- Hindari penjumlahan jumlah item yang melewati presisi integer Lua.
    assert(before.inventory <= MAX_SAFE_INTEGER - before.extra - amount, "BGL balance exceeds numeric limit")
    local id = beginExchange(uid(player), amount, cost, before, TO_BGL, automatic)
    local debitOK, removed = pcall(function() return player:removeGems(cost) end)
    local readOK, debited = pcall(snapshot, player)
    if debitOK and removed == false and readOK and debited.gems == before.gems and sameItems(debited, before) then
        finishExchange(id, "cancelled", debited, "Engine refused debit; no assets changed")
        exchangeNotice(player, amount, "Pemotongan gems ditolak server. Saldo kamu tidak berubah.", automatic)
        return false
    end
    if not (debitOK and removed == true and readOK and debited.gems == before.gems - cost and sameItems(debited, before)) then
        hold(id, "debit", debitOK, removed, readOK, debited)
    end

    local giveOK, given = pcall(function() return player:giveItem(BGL_ITEM_ID, amount) end)
    local afterOK, after = pcall(snapshot, player)
    if giveOK and given == true and afterOK and after.gems == debited.gems
        and after.inventory >= before.inventory and after.extra >= before.extra
        and (after.inventory - before.inventory) + (after.extra - before.extra) == amount then
        finishExchange(id, "done", after, "Exchange completed")
        if automatic then
            notify(player, "`2Auto-convert berhasil!`` " .. fmt(cost) .. " gems menjadi " .. fmt(amount)
                .. " BGL. Sisa " .. fmt(after.gems) .. " gems. Inventory +" .. fmt(after.inventory - before.inventory)
                .. " BGL; Extra Backpack +" .. fmt(after.extra - before.extra) .. " BGL. Transaksi #" .. num(id) .. ".")
            return true
        end
        local lines = heading("PENUKARAN BERHASIL!")
        line(lines, "Kamu menerima `2" .. fmt(amount) .. " BGL``.")
        line(lines, "Gems terpakai: `w" .. fmt(cost) .. "``")
        line(lines, "Sisa gems: `w" .. fmt(after.gems) .. "``")
        line(lines, "Masuk inventory: `2" .. fmt(after.inventory - before.inventory) .. " BGL``")
        line(lines, "Masuk Extra Backpack: `2" .. fmt(after.extra - before.extra) .. " BGL``")
        line(lines, "Nomor transaksi: `w#" .. num(id) .. "``")
        button(lines, "again", "Tukar Lagi")
        notify(player, "`2Berhasil!`` " .. fmt(cost) .. " gems ditukar menjadi " .. fmt(amount) .. " BGL. Transaksi #" .. num(id) .. ".")
        show(player, lines, { view = "success" })
        return true
    end

    -- Refund hanya jika engine menolak give dan terverifikasi NOL BGL masuk.
    -- Jangan refund buta pada pemberian parsial/error; itu bisa memberi item gratis.
    if giveOK and given == false and afterOK and after.gems == debited.gems and sameItems(after, before) then
        local refundOK, refundResult = pcall(function() player:addGems(cost) end)
        local checked, refunded = pcall(snapshot, player)
        if refundOK and checked and refunded.gems == before.gems and sameItems(refunded, before) then
            finishExchange(id, "refunded", refunded, "Item rejected; full gems refund verified")
            exchangeNotice(player, amount, "BGL gagal dikirim. " .. fmt(cost) .. " gems sudah dikembalikan penuh.", automatic)
            return false
        end
        hold(id, "refund", refundOK, refundResult, checked, refunded)
    end
    hold(id, "give", giveOK, given, afterOK, after)
end

local function takeBgl(player, id, before, amount, fromExtra)
    local ok, result = pcall(function()
        if fromExtra then return player:takeFromExtraBackpack(BGL_ITEM_ID, amount) end
        return player:changeItem(BGL_ITEM_ID, -amount)
    end)
    local readOK, after = pcall(snapshot, player)
    local success = (fromExtra and result == amount) or (not fromExtra and result == true)
    local refused = (fromExtra and result == 0) or (not fromExtra and result == false)
    if ok and success and readOK and after.gems == before.gems
        and after.inventory == before.inventory - (fromExtra and 0 or amount)
        and after.extra == before.extra - (fromExtra and amount or 0) then return after end
    if ok and refused and readOK and after.gems == before.gems and sameItems(after, before) then return nil end
    hold(id, fromExtra and "take_extra" or "take_inventory", ok, result, readOK, after)
end

local function refundBgl(player, id, amount, before, requested, reason)
    -- Dipanggil hanya untuk debit BGL yang sudah diverifikasi, tanpa gems masuk.
    local ok, result = pcall(function() return player:giveItem(BGL_ITEM_ID, amount) end)
    local readOK, after = pcall(snapshot, player)
    if ok and result == true and readOK and after.gems == before.gems
        and after.inventory >= before.inventory and after.extra >= before.extra
        and (after.inventory - before.inventory) + (after.extra - before.extra) == amount then
        finishExchange(id, "refunded", after, reason .. "; verified BGL refund=" .. num(amount))
        form(player, requested, "Penukaran dibatalkan. " .. fmt(amount) .. " BGL sudah dikembalikan ke inventory/Extra Backpack.", TO_GEMS)
        return
    end
    hold(id, "refund_bgl", ok, result, readOK, after)
end

local function exchangeBgl(player, amount)
    assert(integer(amount, 1, MAX_BGL), "Invalid server-side amount")
    if not available(player) then return end
    assert(getItem(BGL_ITEM_ID), "Item BGL tidak tersedia di server.")
    local before = snapshot(player)
    local why = reverseError(before, amount)
    if why then form(player, amount, why .. " Belum ada BGL dipotong.", TO_GEMS); return end
    local gems = amount * GEMS_PER_BGL
    local fromInventory = math.min(before.inventory, amount)
    local fromExtra = amount - fromInventory
    local id = beginExchange(uid(player), amount, gems, before, TO_GEMS)
    local debited = before
    if fromInventory > 0 then
        local after = takeBgl(player, id, debited, fromInventory, false)
        if not after then
            finishExchange(id, "cancelled", debited, "Inventory debit refused; no assets changed")
            form(player, amount, "BGL tidak dapat diambil dari inventory. Saldo kamu tidak berubah.", TO_GEMS)
            return
        end
        debited = after
    end
    if fromExtra > 0 then
        local after = takeBgl(player, id, debited, fromExtra, true)
        if not after then
            if fromInventory > 0 then
                refundBgl(player, id, fromInventory, debited, amount, "Extra Backpack debit refused")
            else
                finishExchange(id, "cancelled", debited, "Extra Backpack debit refused; no assets changed")
                form(player, amount, "BGL tidak dapat diambil dari Extra Backpack. Saldo kamu tidak berubah.", TO_GEMS)
            end
            return
        end
        debited = after
    end
    -- addGems tidak mengembalikan boolean; buktikan saldo bertambah tepat.
    local creditOK, result = pcall(function() player:addGems(gems) end)
    local readOK, after = pcall(snapshot, player)
    if creditOK and readOK and after.gems == before.gems + gems and sameItems(after, debited) then
        finishExchange(id, "done", after, "BGL to gems completed")
        local lines = heading("PENUKARAN BERHASIL!")
        line(lines, "Kamu menerima `2" .. fmt(gems) .. " gems``.")
        line(lines, "BGL ditukar: `w" .. fmt(amount) .. "``")
        line(lines, "Dari inventory: " .. fmt(fromInventory) .. " BGL; Extra Backpack: " .. fmt(fromExtra) .. " BGL.")
        line(lines, "Saldo gems sekarang: `w" .. fmt(after.gems) .. "``")
        if after.gems >= AUTO_CONVERT_GEMS then
            line(lines, "Auto-convert aktif: saldo ini akan otomatis ditukar kembali menjadi BGL.")
        end
        line(lines, "Sisa BGL di inventory: " .. fmt(after.inventory) .. "; Extra Backpack: " .. fmt(after.extra) .. ".")
        line(lines, "Nomor transaksi: `w#" .. num(id) .. "``")
        button(lines, "again", "Tukar Lagi")
        notify(player, "`2Berhasil!`` " .. fmt(amount) .. " BGL ditukar menjadi " .. fmt(gems) .. " gems. Transaksi #" .. num(id) .. ".")
        show(player, lines, { view = "success", direction = TO_GEMS })
        return
    end
    if creditOK and readOK and after.gems == debited.gems and sameItems(after, debited) then
        refundBgl(player, id, amount, debited, amount, "Gems credit had no effect")
        return
    end
    -- Credit parsial/ambigu tidak boleh diulang atau di-refund otomatis.
    hold(id, "credit_gems", creditOK, result, readOK, after)
end

local function guard(player, fn)
    if not player or not player:isOnline() then return end
    if not ready then
        notify(player, "`4Penukaran sedang tidak tersedia.`` Hubungi admin.")
        return
    end
    local id = uid(player)
    if busy[id] then return end
    busy[id] = true
    local ok, err = pcall(fn)
    busy[id] = nil
    if not ok then
        sessions[id] = nil
        print("[gemstobgl] uid=" .. num(id) .. " " .. tostring(err))
        local checked, row = pcall(pending, id)
        if checked and row then
            notify(player, "`4Penukaran #" .. num(row.id) .. " perlu diperiksa admin.`` Sampaikan nomor ini ke admin sebelum menukar lagi.")
        else
            notify(player, "`4Penukaran tidak dapat diselesaikan.`` Hubungi admin untuk memeriksa status transaksi.")
        end
    end
end

local function autoConvert(player)
    if not ready or not player or not player:isOnline() or player:getType() ~= 0 then return end
    local id = uid(player)
    if busy[id] then return end
    local now = os.time()
    local state = autoState[id]
    if state and now < state.retryAt then return end
    if not state then state = { retryAt = 0 }; autoState[id] = state end
    -- Jika pembacaan/SQL/API gagal, guard menangani error; jeda sudah terpasang.
    state.retryAt = now + AUTO_RETRY_SECONDS
    guard(player, function()
        local gems = assert(integer(player:getGems(), 0, MAX_GEMS), "Invalid gems balance")
        if gems < AUTO_CONVERT_GEMS then state.retryAt = 0; return end
        local row = pending(id)
        if row then
            if state.pending ~= row.id then
                notify(player, "`4Auto-convert ditahan: transaksi #" .. num(row.id) .. " perlu diperiksa admin.``")
                state.pending = row.id
            end
            return
        end
        state.pending = nil
        -- Saldo akan berubah: tolak konfirmasi lama tanpa membuka dialog baru.
        sessions[id] = nil
        if exchange(player, math.floor(gems / GEMS_PER_BGL), true) then state.retryAt = 0 end
    end)
end

local initialized, initError = pcall(function()
    assert(integer(GEMS_PER_BGL, 1, MAX_GEMS), "Invalid exchange rate")
    assert(integer(AUTO_CONVERT_GEMS, GEMS_PER_BGL, MAX_GEMS - 1), "Invalid auto-convert threshold")
    assert(integer(AUTO_RETRY_SECONDS, 1, 3600), "Invalid auto-convert retry delay")
    assert(integer(BGL_ITEM_ID, 1, 2000000000) and getItem(BGL_ITEM_ID), "BGL item is unavailable")
    db = assert(sqlite.open(DB_FILE), "Cannot open exchange database")
    query("PRAGMA synchronous=FULL")
    query("CREATE TABLE IF NOT EXISTS exchanges(id INTEGER PRIMARY KEY AUTOINCREMENT,uid INTEGER NOT NULL,item_id INTEGER NOT NULL,amount INTEGER NOT NULL,cost INTEGER NOT NULL,gems_before INTEGER NOT NULL,inventory_before INTEGER NOT NULL,extra_before INTEGER NOT NULL,gems_after INTEGER,inventory_after INTEGER,extra_after INTEGER,status TEXT NOT NULL,created_at INTEGER NOT NULL,finished_at INTEGER,note TEXT NOT NULL DEFAULT '')")
    -- Upgrade database lama tanpa menghapus riwayat atau melepas pending.
    local columns = {}
    for _, column in ipairs(query("PRAGMA table_info(exchanges)")) do
        columns[column.name] = true
    end
    if not columns.direction then
        query("ALTER TABLE exchanges ADD COLUMN direction TEXT NOT NULL DEFAULT 'gems_to_bgl'")
    end
    if not columns.automatic then
        query("ALTER TABLE exchanges ADD COLUMN automatic INTEGER NOT NULL DEFAULT 0")
    end
    query("CREATE UNIQUE INDEX IF NOT EXISTS gemstobgl_pending ON exchanges(uid) WHERE status='pending'")
    query("CREATE TABLE IF NOT EXISTS runtime(id INTEGER PRIMARY KEY CHECK(id=1),generation INTEGER NOT NULL)")
    query("INSERT OR IGNORE INTO runtime(id,generation) VALUES(1,0)")
    query("UPDATE runtime SET generation=generation+1 WHERE id=1")
    generation = assert(integer(tonumber(query("SELECT generation FROM runtime WHERE id=1")[1].generation), 1, MAX_SAFE_INTEGER), "Invalid generation")
end)
ready = initialized
if not ready then print("[gemstobgl] INIT FAILED: " .. tostring(initError)) end

registerLuaCommand {
    command = "sell2",
    roleRequired = 0,
    description = "Tukar gems ke BGL atau BGL ke gems. Kurs: 30.000.000 gems = 1 BGL.",
}

onPlayerCommandCallback(function(world, player, fullCommand)
    local command, args = tostring(fullCommand):match("^%s*/?(%S+)%s*(.-)%s*$")
    if not command or command:lower() ~= "sell2" then return false end
    guard(player, function()
        form(player, nil, args ~= "" and "Ketik /sell2, lalu isi jumlah BGL pada kolom di bawah." or nil)
    end)
    return true
end)

onPlayerDialogCallback(function(world, player, data)
    if type(data) ~= "table" or type(data.dialog_name) ~= "string" then return false end
    local view = data.dialog_name:match("^gemstobgl_(%a+)_%d+_%d+$")
        or data.dialog_name:match("^gemstobgl_(%a+)$") -- Menu versi lama: buka form terbaru.
    if view ~= "form" and view ~= "confirm" and view ~= "success" then return false end
    guard(player, function()
        local id = uid(player)
        local state = sessions[id]
        local clicked = data.buttonClicked
        local matches = state and state.view == view and data.dialog_name == state.dialogName
        -- Tutup menu lama tidak boleh membuka dialog atau membatalkan sesi baru.
        if data.quit == "1" or data.quit == 1 or clicked == nil or clicked == "" then
            if matches then sessions[id] = nil end
            return
        end
        -- Refresh hanya membaca saldo: boleh membuka menu baru meski sesi lama
        -- hilang/kedaluwarsa, termasuk setelah auto-convert atau reload script.
        if clicked == "refresh" then
            form(player, nil, nil, state and state.direction)
            return
        end
        if not matches or os.time() >= state.expires then
            -- Kiriman lama tidak pernah menjalankan transaksi. Buka form baru;
            -- player harus review dan konfirmasi lagi dengan token yang baru.
            form(player, state and state.amount, nil, state and state.direction)
            return
        end
        -- Konsumsi token sebelum memproses input atau memindahkan aset.
        sessions[id] = nil
        if view == "form" then
            if clicked == "to_gems" then form(player, nil, nil, TO_GEMS)
            elseif clicked == "to_bgl" then form(player, nil, nil, TO_BGL)
            elseif clicked == "review" then review(player, parseAmount(data.sell2_amount), state.direction)
            elseif clicked == "maximum" then
                local maximum = maximumFor(snapshot(player), state.direction)
                if maximum > 0 then review(player, maximum, state.direction) else form(player, nil, nil, state.direction) end
            end
        elseif view == "confirm" then
            if clicked == "confirm" then
                if state.direction == TO_GEMS then exchangeBgl(player, state.amount) else exchange(player, state.amount) end
            elseif clicked == "back" then form(player, state.amount, nil, state.direction) end
        elseif view == "success" and clicked == "again" then form(player, nil, nil, state.direction) end
    end)
    return true
end)

onPlayerDisconnectCallback(function(player)
    if not player then return end
    local id = uid(player)
    sessions[id], busy[id] = nil, nil
    autoState[id] = nil
end)

-- Callback engine memberi handle player yang valid tiap tick, tanpa timer/scan global.
-- Periksa saldo aktual; jangan menebak jumlah award atau memodifikasi payout yang sedang berjalan.
onPlayerTick(function(player) autoConvert(player) end)

print("[gemstobgl] " .. (ready and ("Loaded: /sell2 | Gems <-> BGL | Auto >= " .. fmt(AUTO_CONVERT_GEMS) .. " gems") or "Unavailable; check initialization errors"))
