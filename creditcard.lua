-- Developer: Nathan
-- creditcard.lua - Credit Card Bank. Command: /cc
-- Upload HANYA file ini ke Lua Scripts. Data: creditcard_v1.db di folder server.
-- Gems terpisah dari gem bank bawaan (buka lewat Account Settings).
-- Konfigurasi lock: id, nama opsional, value = nilai 1 item dalam WL.
-- value=0 mengizinkan penyimpanan/transfer tetapi tidak conversion.
-- Gunakan ID asli server untuk custom lock. Jangan menebak ID dari nama/gambar.
local COMMAND = "cc"
local LEGACY_COMMAND = "vault" -- Alias kompatibilitas script sebelumnya.
local ADMIN_ROLE = 4 -- Dev ke atas dapat membaca Admin Logs; tidak dapat melihat PIN.
local CREDIT_CARD_ITEM_ID = 9950 -- Gunakan kartu ini untuk membuka menu pengganti.
local CARD_ICON_ID = CREDIT_CARD_ITEM_ID
local AUTH_SECONDS = 300
local DIALOG_SECONDS = 120
local PIN_MAX_ATTEMPTS = 5
local PIN_LOCK_SECONDS = 900
local PIN_PEPPER_KEY = "blackcard_pin_secret_v1" -- Disimpan terpisah di KV server.
local LOCKS = {
    { id = 8470, value = 1000000 }, -- GGL
    { id = 7188, value = 10000 },   -- BGL
    { id = 1796, value = 100 },     -- DL
    { id = 242, value = 1 },        -- WL
    -- { id = 25000, name = "Custom Lock", value = 100000000 },
}

-- Saldo per aset dibatasi mengikuti batas bulk give/gems engine.
local MAX_BALANCE = 2000000000
local MAX_SAFE_INTEGER = 9007199254740991
local PAGE_SIZE = 6
local DB_FILE = "creditcard_v1.db"
-- Existing installations can select their current DB through this server KV.
-- Set it BEFORE loading this release; see PUBLISHING.md. Never reset PIN keys.
local DB_PATH_KEY = "creditcard_database_file_v1"
local sessions, busy, unlocked, nativePass = {}, {}, {}, {}
local ticket = 0
local db, ready, generation, pepper

-- SQLite melindungi transfer/conversion internal secara atomik. Tidak ada
-- transaksi atomik lintas SQLite dan inventory/save player milik engine.
-- Deposit/withdraw memakai journal pending SEBELUM memindahkan aset.
-- Jika hasil ambigu/error, akun ditahan; jangan mengulang transaksi pending.
-- Pending harus direkonsiliasi pengelola dengan data player + journal.
-- Crash setelah journal selesai tetapi sebelum engine menyimpan player
-- tetap memerlukan pemeriksaan backup. API tidak menyediakan flush player.

local function int(value, minimum, maximum)
    if type(value) ~= "string" and type(value) ~= "number" then return nil end
    local n = tonumber(value)
    if not n or n ~= n or n < minimum or n > maximum or n ~= math.floor(n) then return nil end
    return n
end

local function clean(value, limit)
    return tostring(value or ""):gsub("`.", ""):gsub("[|%c]", " "):sub(1, limit or 64)
end

local function sql(value)
    return "'" .. tostring(value):gsub("%z", ""):gsub("'", "''") .. "'"
end

local function num(value)
    return string.format("%.0f", value)
end

local function fmt(value)
    return num(value):reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
end

-- SHA-256 / HMAC-SHA-256 untuk verifier PIN game, bukan hash password login.
-- PIN tidak disimpan mentah. Pepper 256-bit ada di KV engine, bukan database bank.
-- Perlindungan tebakan online: batas percobaan persisten + jeda 15 menit.
-- Operasi 32-bit aritmetis: kompatibel Lua 5.1+, tanpa operator bit Lua 5.3.
local MOD32 = 4294967296
local xorNibbles, andNibbles = {}, {}
for a = 0, 15 do
    for b = 0, 15 do
        local x, y, xorValue, andValue, weight = a, b, 0, 0, 1
        for _ = 1, 4 do
            local ax, by = x % 2, y % 2
            if ax ~= by then xorValue = xorValue + weight end
            if ax == 1 and by == 1 then andValue = andValue + weight end
            x, y, weight = math.floor(x / 2), math.floor(y / 2), weight * 2
        end
        xorNibbles[a * 16 + b], andNibbles[a * 16 + b] = xorValue, andValue
    end
end
local function bit32op(a, b, lookup)
    local value, weight = 0, 1
    for _ = 1, 8 do
        value = value + lookup[(a % 16) * 16 + b % 16] * weight
        a, b, weight = math.floor(a / 16), math.floor(b / 16), weight * 16
    end
    return value
end
local function bxor(a, b) return bit32op(a, b, xorNibbles) end
local function band(a, b) return bit32op(a, b, andNibbles) end
local function xor3(a, b, c) return bxor(bxor(a, b), c) end
local function pack32(n)
    return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256,
        math.floor(n / 256) % 256, n % 256)
end
local function sha256(message)
    local k = {
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
    }
    local function rotr(x, n) return math.floor(x / 2^n) + (x % 2^n) * 2^(32 - n) end
    local length = #message * 8
    message = message .. "\128" .. string.rep("\0", (55 - #message) % 64)
        .. pack32(math.floor(length / MOD32)) .. pack32(length % MOD32)
    local h = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
    for offset = 1, #message, 64 do
        local w = {}
        for i = 1, 16 do
            local pos = offset + (i - 1) * 4
            local a, b, c, d = message:byte(pos, pos + 3)
            w[i] = a * 16777216 + b * 65536 + c * 256 + d
        end
        for i = 17, 64 do
            local x, y = w[i - 15], w[i - 2]
            w[i] = (w[i - 16] + xor3(rotr(x, 7), rotr(x, 18), math.floor(x / 8)) + w[i - 7]
                + xor3(rotr(y, 17), rotr(y, 19), math.floor(y / 1024))) % MOD32
        end
        local a,b,c,d,e,f,g,z = h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8]
        for i = 1, 64 do
            local t1 = (z + xor3(rotr(e, 6), rotr(e, 11), rotr(e, 25))
                + bxor(band(e, f), band(MOD32 - 1 - e, g)) + k[i] + w[i]) % MOD32
            local t2 = (xor3(rotr(a, 2), rotr(a, 13), rotr(a, 22))
                + xor3(band(a, b), band(a, c), band(b, c))) % MOD32
            z,g,f,e,d,c,b,a = g,f,e,(d + t1) % MOD32,c,b,a,(t1 + t2) % MOD32
        end
        local v = {a,b,c,d,e,f,g,z}
        for i = 1, 8 do h[i] = (h[i] + v[i]) % MOD32 end
    end
    local parts = {}
    for i = 1, 8 do parts[i] = pack32(h[i]) end
    return table.concat(parts)
end

local function hmac(key, message)
    if #key > 64 then key = sha256(key) end
    key = key .. string.rep("\0", 64 - #key)
    local inner, outer = {}, {}
    for i = 1, 64 do
        inner[i] = string.char(bxor(key:byte(i), 0x36))
        outer[i] = string.char(bxor(key:byte(i), 0x5c))
    end
    return (sha256(table.concat(outer) .. sha256(table.concat(inner) .. message)):gsub(".", function(c)
        return string.format("%02x", c:byte())
    end))
end

local function pinDigest(id, salt, pin)
    return hmac(pepper, "blackcard-pin-v1:" .. num(id) .. ":" .. salt .. ":" .. pin)
end

local function sameDigest(a, b)
    if type(a) ~= "string" or type(b) ~= "string" or #a ~= #b then return false end
    local different = 0
    for i = 1, #a do different = different + bxor(a:byte(i), b:byte(i)) end
    return different == 0
end

local function validPin(value)
    return type(value) == "string" and #value == 6 and value:match("^%d%d%d%d%d%d$") ~= nil
end

local function amountInput(value, maximum)
    if type(value) ~= "string" or #value > 40 then return nil end
    local input = value:match("^%s*(.-)%s*$"):lower()
    if input == "all" or input == "max" then return int(maximum, 1, MAX_BALANCE) end
    local unit = input:match("([kmb])$")
    local multiplier = unit == "k" and 1000 or unit == "m" and 1000000 or unit == "b" and 1000000000 or 1
    if unit then
        input = input:sub(1, -2):match("^%s*(.-)%s*$")
        if not input:match("^%d+$") and not input:match("^%d+[.,]%d+$") then return nil end
        local whole, fraction = input:match("^(%d+)[.,](%d+)$")
        if fraction then
            local digits = unit == "k" and 3 or unit == "m" and 6 or 9
            if #fraction > digits then return nil end
            return int(tonumber(whole) * multiplier + tonumber(fraction) * 10 ^ (digits - #fraction), 1, MAX_BALANCE)
        end
    elseif input:find("[., ]") then
        -- Tanpa suffix, titik/koma/spasi hanya pemisah ribuan, bukan pecahan.
        local separator = input:match("[., ]")
        local escaped = separator == "." and "%." or separator
        local head, rest = input:match("^(%d+)" .. escaped .. "(.+)$")
        if not head or #head > 3 then return nil end
        for group in (rest .. separator):gmatch("(.-)" .. escaped) do
            if #group ~= 3 or not group:match("^%d%d%d$") then return nil end
        end
        input = head .. rest:gsub(escaped, "")
    end
    if not input:match("^%d+$") then return nil end
    return int(tonumber(input) * multiplier, 1, MAX_BALANCE)
end

local function query(statement)
    local rows = db:query(statement)
    if type(rows) ~= "table" then error("Database query failed") end
    return rows
end

local function transaction(fn)
    query("BEGIN IMMEDIATE")
    local ok, result = pcall(fn)
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

local function notify(player, text)
    player:onConsoleMessage("`6[Credit Card Bank]`` " .. text)
end

local function uid(player)
    local id = int(player:getUserID(), 1, MAX_BALANCE)
    if not id then error("Invalid user ID") end
    return id
end

local function touch(player)
    local id = uid(player)
    query("INSERT OR IGNORE INTO accounts(uid,name) VALUES(" .. id .. ","
        .. sql(clean(player:getCleanName())) .. ")")
    query("UPDATE accounts SET name=" .. sql(clean(player:getCleanName())) .. " WHERE uid=" .. id)
    query("INSERT OR IGNORE INTO bank_security(uid) VALUES(" .. id .. ")")
    return id
end

local function security(id)
    return query("SELECT * FROM bank_security WHERE uid=" .. id)[1]
end

local function audit(actor, event, detail)
    query("INSERT INTO bank_audit(actor,event,detail,at) VALUES(" .. actor .. "," .. sql(event)
        .. "," .. sql(clean(detail, 160)) .. "," .. os.time() .. ")")
end

local function randomHex(bytes)
    local value = query("SELECT lower(hex(randomblob(" .. bytes .. "))) AS value")[1].value
    assert(type(value) == "string" and #value == bytes * 2 and value:match("^[a-f0-9]+$"), "Random generator unavailable")
    return value
end

local function verifyPin(player, input)
    local id, now = uid(player), os.time()
    local row = assert(security(id), "Akun bank belum tersedia.")
    if not row.pin_hash or row.pin_hash == "" then return false, "Buat PIN 6 digit terlebih dahulu." end
    if row.blocked_until > now then
        unlocked[id] = nil
        return false, "PIN diblokir sementara. Coba lagi dalam " .. (row.blocked_until - now) .. " detik."
    end
    local correct = validPin(input) and sameDigest(pinDigest(id, row.pin_salt, input), row.pin_hash)
    transaction(function()
        if correct then
            query("UPDATE bank_security SET failed=0,blocked_until=0 WHERE uid=" .. id)
        else
            local failures = (row.blocked_until > 0 and 0 or row.failed) + 1
            local untilTime = failures >= PIN_MAX_ATTEMPTS and now + PIN_LOCK_SECONDS or 0
            query("UPDATE bank_security SET failed=" .. failures .. ",blocked_until=" .. untilTime .. " WHERE uid=" .. id)
            audit(id, untilTime > 0 and "pin_locked" or "pin_failed", "PIN verification rejected")
        end
    end)
    if not correct then
        unlocked[id] = nil
        return false, "PIN tidak sesuai. Setelah " .. PIN_MAX_ATTEMPTS .. " percobaan salah, akses diblokir 15 menit."
    end
    unlocked[id] = { expires = now + AUTH_SECONDS, revision = row.revision }
    return true
end

local function storePin(player, pin, changing)
    local id = uid(player)
    assert(validPin(pin), "PIN wajib tepat 6 digit angka.")
    local salt = randomHex(16)
    local digest = pinDigest(id, salt, pin)
    transaction(function()
        local row = assert(security(id), "Akun bank belum tersedia.")
        assert(changing or row.pin_hash == "", "PIN sudah dibuat. Login menggunakan PIN kamu.")
        query("UPDATE bank_security SET pin_hash=" .. sql(digest) .. ",pin_salt=" .. sql(salt)
            .. ",failed=0,blocked_until=0,revision=revision+1 WHERE uid=" .. id)
        audit(id, changing and "pin_changed" or "pin_created", "Credit Card PIN updated")
    end)
    unlocked[id] = { expires = os.time() + AUTH_SECONDS, revision = security(id).revision }
end

local function asset(id)
    local rows = query("SELECT * FROM assets WHERE id=" .. num(id))
    return rows[1]
end

local function balance(id, currency)
    local rows = query("SELECT amount FROM balances WHERE uid=" .. id .. " AND asset=" .. currency)
    return rows[1] and tonumber(rows[1].amount) or 0
end

local function setBalance(id, currency, amount)
    assert(int(amount, 0, MAX_BALANCE), "Balance out of range")
    query("INSERT OR IGNORE INTO balances(uid,asset,amount) VALUES(" .. id .. "," .. currency .. ",0)")
    query("UPDATE balances SET amount=" .. num(amount) .. " WHERE uid=" .. id .. " AND asset=" .. currency)
end

local function pending(id)
    return query("SELECT id FROM journal WHERE status='pending' AND actor=" .. id .. " LIMIT 1")[1]
end

local function ensureAvailable(id)
    if pending(id) then error("Akun memiliki transaksi pending; hubungi pengelola server.") end
end

local function wallet(player, currency, source)
    local amount
    if currency == 0 then amount = player:getGems()
    elseif source == "extra" then amount = player:getExtraBackpackAmount(currency)
    elseif source == "all" then
        amount = player:getItemAmount(currency) + (player:getExtraBackpackAmount(currency) + 0.0)
    else amount = player:getItemAmount(currency) end
    assert(int(amount, 0, MAX_SAFE_INTEGER), "Invalid wallet amount")
    return amount
end

local function logOperation(op, status, before)
    query("INSERT INTO journal(actor,peer,kind,asset,amount,to_asset,to_amount,source,wallet_before,status,at,bank_before,peer_before) VALUES("
        .. op.actor .. "," .. (op.peer or 0) .. "," .. sql(op.kind) .. "," .. op.asset .. ","
        .. num(op.amount) .. "," .. (op.toAsset or 0) .. "," .. num(op.toAmount or 0) .. ","
        .. sql(op.source or "bank") .. "," .. num(before or 0) .. "," .. sql(status) .. "," .. os.time()
        .. "," .. num(balance(op.actor, op.asset)) .. ","
        .. (op.peer and num(balance(op.peer, op.asset)) or "NULL") .. ")")
    return tonumber(query("SELECT last_insert_rowid() AS id")[1].id)
end

local function finishLog(id, op)
    query("UPDATE journal SET status='done',bank_after=" .. num(balance(op.actor, op.asset))
        .. ",peer_after=" .. (op.peer and num(balance(op.peer, op.asset)) or "NULL") .. " WHERE id=" .. id)
end

local function validate(op)
    ensureAvailable(op.actor)
    local from = asset(op.asset)
    assert(from, "Mata uang tidak ditemukan.")
    if op.kind ~= "withdraw" then assert(from.active == 1, "Mata uang ini hanya dapat ditarik.") end
    local old = balance(op.actor, op.asset)
    if op.kind == "deposit" then
        assert(op.amount <= MAX_BALANCE - old, "Saldo bank melewati batas.")
    else
        assert(old >= op.amount, "Saldo bank tidak cukup.")
    end
    if op.kind == "transfer" then
        assert(op.peer ~= op.actor, "Tidak dapat transfer ke akun sendiri.")
        ensureAvailable(op.peer)
        assert(query("SELECT uid FROM accounts WHERE uid=" .. op.peer)[1], "Akun tujuan tidak ditemukan.")
        assert(op.amount <= MAX_BALANCE - balance(op.peer, op.asset), "Saldo penerima melewati batas.")
    elseif op.kind == "convert" then
        local to = asset(op.toAsset)
        assert(to and to.active == 1 and from.id ~= to.id and from.value > 0 and to.value > 0,
            "Pasangan conversion tidak tersedia.")
        assert(op.amount <= math.floor(MAX_SAFE_INTEGER / from.value), "Jumlah conversion terlalu besar.")
        local worth = op.amount * (from.value + 0.0)
        assert(worth % to.value == 0, "Jumlah harus menghasilkan lock tujuan yang utuh.")
        local received = worth / to.value
        assert(int(received, 1, MAX_BALANCE), "Hasil conversion melewati batas.")
        if op.toAmount then assert(op.toAmount == received, "Kurs berubah; buka ulang menu.") end
        op.toAmount = received
        assert(received <= MAX_BALANCE - balance(op.actor, op.toAsset), "Saldo tujuan melewati batas.")
    end
    return from
end

local function applyBank(op)
    local old = balance(op.actor, op.asset)
    setBalance(op.actor, op.asset, old + (op.kind == "deposit" and op.amount or -op.amount))
    if op.kind == "transfer" then
        setBalance(op.peer, op.asset, balance(op.peer, op.asset) + op.amount)
    elseif op.kind == "convert" then
        setBalance(op.actor, op.toAsset, balance(op.actor, op.toAsset) + op.toAmount)
    end
end

local function external(player, op)
    local source = op.kind == "withdraw" and "all" or op.source
    local before = wallet(player, op.asset, source)
    validate(op)
    if op.asset ~= 0 then assert(getItem(op.asset), "Item tidak tersedia di server.") end
    if op.kind == "deposit" then
        assert(before >= op.amount, "Aset yang dibawa tidak cukup.")
    elseif op.asset == 0 then
        assert(op.amount <= MAX_BALANCE - before, "Gems yang dibawa akan melewati batas.")
    end
    local journalID = transaction(function()
        validate(op)
        return logOperation(op, "pending", before)
    end)
    local ok, result = pcall(function()
        if op.asset == 0 then
            if op.kind == "deposit" then return player:removeGems(op.amount) end
            player:addGems(op.amount)
            return true
        elseif op.kind == "withdraw" then
            return player:giveItem(op.asset, op.amount)
        elseif op.source == "extra" then
            return player:takeFromExtraBackpack(op.asset, op.amount) == op.amount
        else
            return player:changeItem(op.asset, -op.amount)
        end
    end)
    local readOK, after = pcall(wallet, player, op.asset, source)
    local expected = before + (op.kind == "deposit" and -op.amount or op.amount)
    if ok and result == true and readOK and after == expected then
        transaction(function()
            local row = query("SELECT status FROM journal WHERE id=" .. journalID)[1]
            assert(row and row.status == "pending", "Journal state changed")
            applyBank(op)
            finishLog(journalID, op)
        end)
        return journalID
    elseif ok and result == false and readOK and after == before then
        transaction(function() query("UPDATE journal SET status='cancelled' WHERE id=" .. journalID) end)
        error("Engine menolak perpindahan aset. Saldo bank tidak berubah.")
    end
    print("[bank] NEEDS REVIEW journal=" .. journalID .. " uid=" .. op.actor
        .. " before=" .. num(before) .. " expected=" .. num(expected)
        .. " after=" .. tostring(after) .. " api=" .. tostring(result))
    error("Transaksi #" .. journalID .. " perlu diperiksa pengelola; akun ditahan agar tidak terulang.")
end

local function execute(player, op)
    assert(op.actor == uid(player), "Akun tidak sesuai.")
    if op.kind == "deposit" or op.kind == "withdraw" then return external(player, op) end
    return transaction(function()
        validate(op)
        local id = logOperation(op, "done")
        applyBank(op)
        finishLog(id, op)
        return id
    end)
end

local function beginDialog(title)
    local header = CARD_ICON_ID > 0 and ("add_label_with_icon|big|`w" .. title .. "``|left|" .. CARD_ICON_ID .. "|\n")
        or ("add_label|big|`w" .. title .. "``|left|\n")
    return { header, "add_spacer|small|\n" }
end

local function line(lines, text)
    lines[#lines + 1] = "add_smalltext|" .. text .. "|\n"
end

local function button(lines, id, text)
    lines[#lines + 1] = "add_button|" .. id .. "|" .. text .. "|noflags|0|0|\n"
end

local function show(player, lines, name, state)
    ticket = ticket + 1
    state.dialogName = "blackcard_" .. state.view .. "_" .. num(generation) .. "_" .. num(ticket)
    state.expires = os.time() + DIALOG_SECONDS
    sessions[uid(player)] = state
    lines[#lines + 1] = "add_spacer|small|\nadd_smalltext|`9© Dibuat Oleh : Nathan``|\n"
    lines[#lines + 1] = "end_dialog|" .. state.dialogName .. "|Tutup||\n"
    local markup = table.concat(lines)
    assert(#markup < 4096, "Dialog exceeds packet limit")
    player:onDialogRequest(markup)
end

local function pinInput(lines, field, label)
    lines[#lines + 1] = "add_text_input_password|" .. field .. "|" .. label .. "||6|\n"
end

local function login(player, notice)
    local id = touch(player)
    local row = security(id)
    local setup = row.pin_hash == ""
    local lines = beginDialog("Credit Card - Bank Card Account")
    line(lines, "Hello `w" .. clean(player:getCleanName()) .. "``. Selamat datang di Credit Card Bank.")
    line(lines, "Account: `w#" .. id .. "``")
    if notice then line(lines, "`4" .. clean(notice, 180) .. "``") end
    if row.blocked_until > os.time() then
        line(lines, "`4Akses PIN diblokir sementara.`` Sisa " .. (row.blocked_until - os.time()) .. " detik.")
        button(lines, "refresh", "Refresh")
    else
        line(lines, setup and "Buat PIN 6 digit untuk mengaktifkan Credit Card kamu."
            or "Masukkan PIN 6 digit untuk membuka bank kamu.")
        line(lines, "Gunakan PIN khusus game ini. Jangan bagikan PIN kepada siapa pun.")
        pinInput(lines, "bank_pin", setup and "Buat PIN" or "PIN")
        if setup then pinInput(lines, "bank_pin_repeat", "Ulangi PIN") end
        button(lines, "unlock", setup and "`2Aktifkan Credit Card``" or "`2Buka Bank``")
    end
    show(player, lines, nil, { view = "login", setup = setup })
end

local function authenticated(player)
    local id = uid(player)
    local state, row = unlocked[id], security(id)
    if not state or not row or state.expires <= os.time() or state.revision ~= row.revision
        or row.blocked_until > os.time() or row.pin_hash == "" then
        unlocked[id] = nil
        login(player)
        return false
    end
    state.expires = os.time() + AUTH_SECONDS
    return true
end

local function isAdmin(player)
    return player:hasRole(ADMIN_ROLE)
end

local function listAssets(kind)
    if kind == "withdraw" then return query("SELECT * FROM assets ORDER BY id=0,value DESC,id") end
    local filter = (kind == "convert" or kind == "convert_to") and " AND value>0" or ""
    return query("SELECT * FROM assets WHERE active=1" .. filter .. " ORDER BY id=0,value DESC,id")
end

local function dashboard(player, page)
    local id = touch(player)
    local rows = query("SELECT a.*,COALESCE(b.amount,0) AS amount FROM assets a LEFT JOIN balances b"
        .. " ON b.asset=a.id AND b.uid=" .. id .. " WHERE a.active=1 OR COALESCE(b.amount,0)>0"
        .. " ORDER BY a.id=0,a.value DESC,a.id")
    local pages = math.max(1, math.ceil(#rows / PAGE_SIZE))
    page = math.max(1, math.min(page or 1, pages))
    local lines = beginDialog("Credit Card - Bank Dashboard")
    line(lines, "`2Account Authenticated!`` Welcome to your secure vault.")
    line(lines, "Bank Account Username: `w" .. clean(player:getCleanName()) .. " (#" .. id .. ")``")
    line(lines, "Bank Account Status: `2Secured (PIN Active)``")
    line(lines, "Credit Card: `wCC-" .. string.format("%010d", id) .. "``")
    button(lines, "settings", "Account Settings")
    local hold = pending(id)
    line(lines, hold and ("`4Status: pemeriksaan transaksi #" .. hold.id .. " diperlukan.``") or "Status: `2Aktif``")
    line(lines, "Simpan lock dan gems, cek nilai aset, dan transfer saldo dari satu akun bank.")
    local worth, unpriced = 0, false
    for _, row in ipairs(rows) do
        if row.id ~= 0 and row.amount > 0 then
            if row.value == 0 then unpriced = true
            elseif worth then
                if row.amount > math.floor((MAX_SAFE_INTEGER - worth) / row.value) then worth = nil
                else worth = worth + row.amount * (row.value + 0.0) end
            end
        end
    end
    for i = (page - 1) * PAGE_SIZE + 1, math.min(page * PAGE_SIZE, #rows) do
        local row = rows[i]
        local text = "`w" .. fmt(row.amount) .. " " .. clean(row.name) .. "``"
        if row.active ~= 1 then text = text .. " (withdraw only)" end
        if row.id > 0 then
            lines[#lines + 1] = "add_label_with_icon|small|" .. text .. "|left|" .. row.id .. "|\n"
        else lines[#lines + 1] = "add_label|big|" .. text .. "|left|\n" end
    end
    line(lines, "`wEstimated Net Worth: " .. (worth and fmt(worth) or "melewati batas hitung") .. " World Locks``")
    line(lines, "Nilai di atas tidak memasukkan gems" .. (unpriced and " atau lock tanpa kurs." or "."))
    button(lines, "deposit", "`2Add Assets``")
    button(lines, "withdraw", "`2Withdraw Assets``")
    button(lines, "transfer", "`2Transfer Assets``")
    button(lines, "logs", "`2Logs``")
    button(lines, "refresh", "Refresh")
    if isAdmin(player) then button(lines, "admin_logs", "Admin Logs") end
    if page > 1 then button(lines, "page_" .. (page - 1), "Sebelumnya") end
    if page < pages then button(lines, "page_" .. (page + 1), "Berikutnya") end
    show(player, lines, "creditcard_main", { view = "main" })
end

local function settings(player, notice)
    local lines = beginDialog("Credit Card - Account Settings")
    line(lines, "Account: `w" .. clean(player:getCleanName()) .. " (#" .. uid(player) .. ")``")
    line(lines, "Keamanan: `2PIN 6 digit aktif``. Bank terkunci setelah 5 menit tidak digunakan.")
    line(lines, "Transfer selalu memerlukan PIN lagi sebelum saldo dipindahkan.")
    if notice then line(lines, "`4" .. clean(notice, 160) .. "``") end
    button(lines, "change_pin", "Ubah PIN")
    button(lines, "convert", "Convert Locks")
    button(lines, "native_bank", "Buka Gem Bank Bawaan")
    button(lines, "lock_bank", "Kunci Bank / Logout")
    button(lines, "home", "Back to Bank Dashboard")
    show(player, lines, nil, { view = "settings" })
end

local function changePinForm(player, notice)
    local lines = beginDialog("Credit Card - Ubah PIN")
    if notice then line(lines, "`4" .. clean(notice, 160) .. "``") end
    pinInput(lines, "bank_old_pin", "PIN lama")
    pinInput(lines, "bank_new_pin", "PIN baru (6 digit)")
    pinInput(lines, "bank_repeat_pin", "Ulangi PIN baru")
    button(lines, "save_pin", "Simpan PIN")
    button(lines, "home", "Batal")
    show(player, lines, nil, { view = "pin" })
end

local function choose(player, kind, page, from)
    local rows = listAssets(kind)
    local pages = math.max(1, math.ceil(#rows / PAGE_SIZE))
    page = math.max(1, math.min(page or 1, pages))
    local titles = { deposit = "Bank Addition", withdraw = "Bank Withdrawal", transfer = "Transfer Assets",
        convert = "Convert - Pilih Lock Asal", convert_to = "Convert - Pilih Lock Tujuan" }
    local lines = beginDialog(titles[kind])
    line(lines, "Pilih jenis lock atau gems. Saldo yang tampil adalah saldo bank kamu.")
    for i = (page - 1) * PAGE_SIZE + 1, math.min(page * PAGE_SIZE, #rows) do
        local row = rows[i]
        if row.id ~= from then
            button(lines, "asset_" .. row.id, "`2" .. clean(row.name) .. "`` / Bank: " .. fmt(balance(uid(player), row.id)))
        end
    end
    if page > 1 then button(lines, "page_" .. (page - 1), "Sebelumnya") end
    if page < pages then button(lines, "page_" .. (page + 1), "Berikutnya") end
    button(lines, "home", "Back to Bank Dashboard")
    show(player, lines, "creditcard_choose", { view = "choose", kind = kind, from = from })
end

local function form(player, kind, currency, to)
    local item = asset(currency)
    assert(item, "Mata uang tidak ditemukan.")
    local lines = beginDialog(kind .. " - " .. clean(item.name))
    line(lines, "Saldo bank: " .. fmt(balance(uid(player), currency)))
    if kind == "deposit" then
        line(lines, (currency == 0 and "Gems dibawa: " or "Backpack: ") .. fmt(wallet(player, currency, "inventory")))
        if currency > 0 then
            line(lines, "Extra Backpack: " .. fmt(wallet(player, currency, "extra")))
            lines[#lines + 1] = "add_checkbox|bank_extra|Ambil dari Extra Backpack|0|\n"
        end
    elseif kind == "withdraw" then
        line(lines, currency == 0 and "Gems masuk ke saldo gems yang kamu bawa."
            or "Item masuk ke backpack; kelebihannya masuk Extra Backpack.")
    elseif kind == "transfer" then
        lines[#lines + 1] = "add_text_input|bank_target|Nama online atau ID akun bank||40|\n"
        line(lines, "Transfer menggunakan saldo bank. Periksa nama dan ID pada konfirmasi.")
    elseif kind == "convert" then
        local target = asset(to)
        assert(target, "Mata uang tujuan tidak ditemukan.")
        line(lines, "Tujuan: " .. clean(target.name))
        line(lines, "1 " .. clean(item.name) .. " = " .. fmt(item.value) .. " WL")
        line(lines, "1 " .. clean(target.name) .. " = " .. fmt(target.value) .. " WL")
        line(lines, "Conversion memakai saldo bank dan hasilnya harus bilangan utuh.")
    end
    lines[#lines + 1] = "add_text_input|bank_amount|Amount||40|\n"
    line(lines, "Contoh: 1000, 1.000, 1,000, 1k, 1.5m, 1,5m, all atau max.")
    line(lines, "all/max mengikuti saldo, sumber yang dipilih, dan batas penyimpanan.")
    button(lines, "review", "Lanjut")
    button(lines, "home", "Kembali")
    show(player, lines, "creditcard_form", { view = "form", kind = kind, asset = currency, toAsset = to })
end

local function recipient(text)
    text = tostring(text or ""):match("^%s*(.-)%s*$")
    assert(#text > 0 and #text <= 40 and not text:find("[|%c]"), "Isi nama/ID tujuan yang benar.")
    local id = text:match("^#?(%d+)$")
    local online
    if id then
        id = int(id, 1, MAX_BALANCE)
        assert(id, "ID akun tidak valid.")
        online = getPlayer(id)
    else online = getPlayerByName(text) end
    if online and online:isOnline() then id = touch(online) end
    assert(id, "Nama tidak ditemukan online. Gunakan ID bank untuk penerima offline.")
    local row = query("SELECT uid,name FROM accounts WHERE uid=" .. id)[1]
    assert(row, "Akun tujuan belum terdaftar. Minta penerima membuka /" .. COMMAND .. " dulu.")
    return row
end

local function review(player, state, data)
    local source = "bank"
    if state.kind == "deposit" then source = state.asset == 0 and "gems" or "inventory"
    elseif state.kind == "withdraw" then source = state.asset == 0 and "gems" or "all" end
    if state.kind == "deposit" and state.asset > 0 and tostring(data.bank_extra) == "1" then source = "extra" end
    local maximum = balance(uid(player), state.asset)
    if state.kind == "deposit" then
        maximum = math.min(wallet(player, state.asset, source), MAX_BALANCE - maximum)
    elseif state.kind == "withdraw" and state.asset == 0 then
        maximum = math.min(maximum, MAX_BALANCE - wallet(player, 0, "gems"))
    end
    local amount = amountInput(data.bank_amount, maximum)
    assert(amount, "Jumlah tidak valid. Gunakan angka bulat, pemisah ribuan, k/m/b, atau all/max.")
    local op = { actor = uid(player), kind = state.kind, asset = state.asset,
        amount = amount, toAsset = state.toAsset, source = source }
    if op.kind == "transfer" then
        local target = recipient(data.bank_target)
        op.peer, op.peerName = target.uid, target.name
    end
    local from = validate(op)
    if op.kind == "deposit" or op.kind == "withdraw" then
        assert(amount <= maximum, "Jumlah melewati aset yang tersedia atau batas penyimpanan.")
    end
    local lines = beginDialog("Konfirmasi Transaksi")
    line(lines, "Aksi: " .. op.kind)
    line(lines, "Jumlah: `w" .. fmt(amount) .. " " .. clean(from.name) .. "``")
    if op.kind == "transfer" then
        line(lines, "Penerima: `w" .. clean(op.peerName) .. " (#" .. op.peer .. ")``")
        line(lines, "Saldo bank setelah transfer: " .. fmt(balance(op.actor, op.asset) - amount) .. " " .. clean(from.name))
        line(lines, "Periksa nama dan ID penerima. Masukkan PIN untuk mengizinkan transfer ini.")
        pinInput(lines, "bank_pin", "PIN 6 digit")
    elseif op.kind == "convert" then
        line(lines, "Diterima: `2" .. fmt(op.toAmount) .. " " .. clean(asset(op.toAsset).name) .. "``")
    elseif op.kind == "deposit" then
        line(lines, "Diambil dari: " .. (op.asset == 0 and "gems dibawa" or (op.source == "extra" and "Extra Backpack" or "backpack")))
    end
    button(lines, "confirm", "Konfirmasi")
    button(lines, "home", "Batal")
    show(player, lines, "creditcard_confirm", { view = "confirm", op = op })
end

local function history(player, page, search, admin, securityLog)
    local id = uid(player)
    if admin then assert(isAdmin(player), "Admin Logs hanya untuk pengelola server.") end
    securityLog = admin and securityLog or false
    search = clean(search, 40):lower()
    local filter = admin and " WHERE 1=1" or (" WHERE (actor=" .. id .. " OR (kind='transfer' AND peer=" .. id .. "))")
    local tableName = securityLog and "bank_audit" or "journal"
    if search ~= "" then
        local fields = securityLog and "id||' '||actor||' '||event||' '||detail"
            or "id||' '||actor||' '||peer||' '||kind||' '||asset||' '||status"
        filter = filter .. " AND instr(lower(" .. fields .. ")," .. sql(search) .. ")>0"
    end
    -- Pemain melihat paling banyak 50 hasil terakhir; admin dapat membaca semua.
    local count = tonumber(query("SELECT COUNT(*) AS n FROM " .. tableName .. filter)[1].n)
    if not admin then count = math.min(count, 50) end
    local pages = math.max(1, math.ceil(count / PAGE_SIZE))
    page = math.max(1, math.min(page or 1, pages))
    local limit = math.max(0, math.min(PAGE_SIZE, count - (page - 1) * PAGE_SIZE))
    local rows = query("SELECT * FROM " .. tableName .. filter .. " ORDER BY id DESC LIMIT " .. limit .. " OFFSET " .. ((page - 1) * PAGE_SIZE))
    local lines = beginDialog((admin and (securityLog and "Admin Security Logs" or "Admin Bank Logs") or "My Bank Logs") .. " - " .. page .. "/" .. pages)
    line(lines, admin and "Catatan server (read-only)." or "Maksimal 50 hasil transaksi terakhir, termasuk transfer masuk.")
    lines[#lines + 1] = "add_text_input|bank_search|Search|" .. search .. "|40|\n"
    line(lines, securityLog and "Cari ID akun, ID log, atau jenis kejadian." or "Cari ID akun, ID log, ID aset, jenis transaksi, atau status.")
    button(lines, "search", "Search")
    if #rows == 0 then line(lines, "Belum ada transaksi.") end
    for _, row in ipairs(rows) do
        if securityLog then
            line(lines, "#" .. row.id .. " / Akun #" .. row.actor .. " / " .. clean(row.event))
            line(lines, clean(row.detail, 160) .. " / " .. os.date("%Y-%m-%d %H:%M:%S", row.at))
        else
        local currency = asset(row.asset)
        local label = currency and currency.name or ("Item #" .. row.asset)
        local text = "#" .. row.id .. " " .. row.kind .. " / " .. fmt(row.amount) .. " " .. clean(label)
        if row.kind == "transfer" then
            text = text .. (row.actor == id and (" -> #" .. row.peer) or (" <- #" .. row.actor))
        elseif row.kind == "convert" then
            local target = asset(row.to_asset)
            text = text .. " -> " .. fmt(row.to_amount) .. " " .. clean(target and target.name or row.to_asset)
        end
        if admin then text = text .. " / Akun #" .. row.actor end
        line(lines, text)
        line(lines, "Status: " .. row.status .. " / Waktu server: " .. os.date("%Y-%m-%d %H:%M:%S", row.at))
        local incoming = not admin and row.kind == "transfer" and row.peer == id
        local before = incoming and row.peer_before or row.bank_before
        local after = incoming and row.peer_after or row.bank_after
        if before ~= nil and after ~= nil then line(lines, "Saldo: " .. fmt(before) .. " -> " .. fmt(after)) end
        end
    end
    if page > 1 then button(lines, "page_" .. (page - 1), "Sebelumnya") end
    if page < pages then button(lines, "page_" .. (page + 1), "Berikutnya") end
    if admin then button(lines, "toggle_logs", securityLog and "Transaction Logs" or "Security Logs") end
    button(lines, "home", "Kembali")
    show(player, lines, nil, { view = "logs", search = search, admin = admin, securityLog = securityLog })
end

local function guard(player, fn)
    if not player or not player:isOnline() then return end
    if not ready then notify(player, "`4Bank belum tersedia. Periksa konfigurasi/log server."); return end
    local id = uid(player)
    if busy[id] then return end
    busy[id] = true
    local ok, err = pcall(fn)
    busy[id] = nil
    if not ok then
        print("[bank] uid=" .. id .. " " .. tostring(err))
        local message = tostring(err):gsub("^.-:%d+:%s*", "")
        notify(player, "`4" .. clean(message, 220))
        sessions[id] = nil
        -- Validasi gagal tetap mengembalikan menu yang dapat dipakai.
        local reopened = pcall(function() if authenticated(player) then dashboard(player, 1) end end)
        if not reopened then notify(player, "Buka /" .. COMMAND .. " untuk mencoba kembali.") end
    end
end

local ok, why = pcall(function()
    local configuredFile = loadStringFromServer(DB_PATH_KEY)
    if configuredFile ~= nil then
        assert(type(configuredFile) == "string" and #configuredFile >= 4 and #configuredFile <= 128
            and configuredFile:match("^[%w_%-%.]+%.db$") and not configuredFile:find("..", 1, true),
            "Invalid configured bank database filename. Use a basename ending in .db.")
        DB_FILE = configuredFile
    end
    db = sqlite.open(DB_FILE)
    assert(db, "Cannot open bank database")
    query("PRAGMA synchronous=FULL")
    query("CREATE TABLE IF NOT EXISTS accounts(uid INTEGER PRIMARY KEY,name TEXT NOT NULL)")
    query("CREATE TABLE IF NOT EXISTS assets(id INTEGER PRIMARY KEY,name TEXT NOT NULL,value INTEGER NOT NULL,active INTEGER NOT NULL)")
    query("CREATE TABLE IF NOT EXISTS balances(uid INTEGER NOT NULL,asset INTEGER NOT NULL,amount INTEGER NOT NULL CHECK(amount>=0 AND amount<=2000000000),PRIMARY KEY(uid,asset))")
    query("CREATE TABLE IF NOT EXISTS journal(id INTEGER PRIMARY KEY AUTOINCREMENT,actor INTEGER NOT NULL,peer INTEGER NOT NULL DEFAULT 0,kind TEXT NOT NULL,asset INTEGER NOT NULL,amount INTEGER NOT NULL,to_asset INTEGER NOT NULL DEFAULT 0,to_amount INTEGER NOT NULL DEFAULT 0,source TEXT NOT NULL,wallet_before INTEGER NOT NULL DEFAULT 0,status TEXT NOT NULL,at INTEGER NOT NULL)")
    query("CREATE INDEX IF NOT EXISTS bank_journal_actor ON journal(actor,status)")
    query("CREATE INDEX IF NOT EXISTS bank_journal_peer ON journal(peer)")
    query("CREATE TABLE IF NOT EXISTS bank_security(uid INTEGER PRIMARY KEY,pin_hash TEXT NOT NULL DEFAULT '',pin_salt TEXT NOT NULL DEFAULT '',failed INTEGER NOT NULL DEFAULT 0,blocked_until INTEGER NOT NULL DEFAULT 0,revision INTEGER NOT NULL DEFAULT 0)")
    query("CREATE TABLE IF NOT EXISTS bank_audit(id INTEGER PRIMARY KEY AUTOINCREMENT,actor INTEGER NOT NULL,event TEXT NOT NULL,detail TEXT NOT NULL,at INTEGER NOT NULL)")
    query("CREATE TABLE IF NOT EXISTS bank_meta(key TEXT PRIMARY KEY,value TEXT NOT NULL)")
    local columns = {}
    for _, column in ipairs(query("PRAGMA table_info(journal)")) do columns[column.name] = true end
    transaction(function()
        for _, column in ipairs({"bank_before", "bank_after", "peer_before", "peer_after"}) do
            if not columns[column] then query("ALTER TABLE journal ADD COLUMN " .. column .. " INTEGER") end
        end
        query("INSERT OR IGNORE INTO bank_meta(key,value) VALUES('generation','0')")
        query("UPDATE bank_meta SET value=CAST(value AS INTEGER)+1 WHERE key='generation'")
        generation = tonumber(query("SELECT value FROM bank_meta WHERE key='generation'")[1].value)
        assert(int(generation, 1, MAX_SAFE_INTEGER), "Invalid dialog generation")
    end)
    pepper = loadStringFromServer(PIN_PEPPER_KEY)
    local savedFingerprint = query("SELECT value FROM bank_meta WHERE key='pepper_fingerprint'")[1]
    assert(pepper == nil or pepper == "" or savedFingerprint
        or tonumber(query("SELECT COUNT(*) AS n FROM accounts")[1].n) > 0,
        "Bank database is empty but a PIN secret already exists. Select the existing database before updating; see PUBLISHING.md.")
    if pepper == nil or pepper == "" then
        assert(not savedFingerprint and tonumber(query("SELECT COUNT(*) AS n FROM bank_security WHERE pin_hash<>''")[1].n) == 0,
            "PIN secret missing. Restore server KV backup; do not reset bank database.")
        pepper = randomHex(32)
        assert(saveStringToServer(PIN_PEPPER_KEY, pepper) == true, "Cannot save PIN secret")
        assert(loadStringFromServer(PIN_PEPPER_KEY) == pepper, "Cannot verify saved PIN secret")
    end
    assert(type(pepper) == "string" and #pepper == 64 and pepper:match("^[a-f0-9]+$"), "Invalid PIN secret")
    local fingerprint = hmac(pepper, "blackcard-pepper-fingerprint-v1")
    assert(not savedFingerprint or sameDigest(savedFingerprint.value, fingerprint), "PIN secret changed. Restore matching KV backup.")
    query("INSERT OR IGNORE INTO bank_meta(key,value) VALUES('pepper_fingerprint'," .. sql(fingerprint) .. ")")
    assert(int(CARD_ICON_ID, 0, MAX_BALANCE), "Invalid CARD_ICON_ID")
    if CARD_ICON_ID > 0 then assert(getItem(CARD_ICON_ID), "CARD_ICON_ID is not an item on this server") end
    transaction(function()
        query("UPDATE assets SET active=0")
        query("INSERT OR IGNORE INTO assets(id,name,value,active) VALUES(0,'Normal Gems',0,1)")
        query("UPDATE assets SET active=1 WHERE id=0")
        local seen = {}
        for _, entry in ipairs(LOCKS) do
            local id = int(entry.id, 1, MAX_BALANCE)
            local value = int(entry.value, 0, 1000000000)
            assert(id and value and not seen[id], "Invalid/duplicate LOCKS config")
            seen[id] = true
            local item = getItem(id)
            if item then
                local name = clean(entry.name or item:getName(), 40)
                query("INSERT OR IGNORE INTO assets(id,name,value,active) VALUES(" .. id .. "," .. sql(name) .. "," .. num(value) .. ",1)")
                query("UPDATE assets SET name=" .. sql(name) .. ",value=" .. num(value) .. ",active=1 WHERE id=" .. id)
            else print("[bank] Item #" .. id .. " missing; skipped") end
        end
    end)
end)
ready = ok
if not ok then print("[bank] INIT FAILED: " .. tostring(why)) end

local function openCreditCard(player)
    guard(player, function()
        touch(player)
        if authenticated(player) then dashboard(player, 1) end
    end)
end

local function registeredCreditCard(player, args)
    openCreditCard(player)
    return true
end

-- Callback langsung dicoba engine sebelum callback command umum/built-in.
local function registerCardCommand(command, description)
    local registered, result = pcall(registerLuaCommand, { command = command, roleRequired = 0,
        description = description, callback = registeredCreditCard })
    if not registered or result == false then
        -- Beberapa engine menolak mendaftarkan nama command bawaan.
        -- Tetap pasang input/command hooks; error registrasi tidak boleh menghentikan file.
        print("[bank] Command registration /" .. command .. " rejected: " .. tostring(result)
            .. ". Continuing with input/command hooks.")
    end
end
registerCardCommand(COMMAND, "Credit Card Bank: lock, gems, transfer PIN, logs.")
if LEGACY_COMMAND ~= COMMAND then
    registerCardCommand(LEGACY_COMMAND, "Alias /" .. COMMAND)
end

-- Tangkap input /cc sebelum engine memilih rute command bawaan.
-- Hanya action=input dengan slash; chat biasa dan dialog lain tetap diteruskan.
onPlayerActionCallback(function(world, player, data)
    if type(data) ~= "table" or data.action ~= "input" or type(data.text) ~= "string" then return false end
    local command = data.text:match("^%s*/(%S+)")
    command = command and command:lower()
    if command ~= COMMAND and command ~= LEGACY_COMMAND then return false end
    openCreditCard(player)
    return true
end)

onPlayerCommandCallback(function(world, player, fullCommand)
    local command = tostring(fullCommand):match("^%s*/?(%S+)")
    if not command then return false end
    command = command:lower()
    if command ~= COMMAND and command ~= LEGACY_COMMAND then return false end
    if player and nativePass[uid(player)] then return false end
    openCreditCard(player)
    return true
end)

onPlayerDialogCallback(function(world, player, data)
    if type(data) ~= "table" then return false end
    local dialog = tostring(data.dialog_name or "")
    if not dialog:match("^blackcard_") and not dialog:match("^creditcard_") then return false end
    guard(player, function()
        local id = uid(player)
        local state = sessions[id]
        local clicked = tostring(data.buttonClicked or "")
        if data.quit == "1" or data.quit == 1 or clicked == "" or clicked == "cancel" or clicked == "exit" then
            if state and state.dialogName == dialog then sessions[id] = nil end
            return
        end
        if not state or state.dialogName ~= dialog or state.expires <= os.time() then
            if authenticated(player) then dashboard(player, 1) end
            return
        end
        local view = state.view
        if view == "login" and clicked == "unlock" then
            sessions[id] = nil
            if state.setup then
                if not validPin(data.bank_pin) or data.bank_pin ~= data.bank_pin_repeat then
                    login(player, "PIN harus tepat 6 digit dan kedua input harus sama."); return
                end
                storePin(player, data.bank_pin, false)
            else
                local accepted, reason = verifyPin(player, data.bank_pin)
                if not accepted then login(player, reason); return end
            end
            dashboard(player, 1)
            return
        end
        if not authenticated(player) then return end
        if clicked == "home" or clicked == "refresh" then dashboard(player, 1); return end
        local page = clicked:match("^page_(%d+)$")
        page = page and int(page, 1, 1000000)
        if view == "main" then
            if page then dashboard(player, page)
            elseif clicked == "logs" then history(player, 1)
            elseif clicked == "admin_logs" then history(player, 1, nil, true)
            elseif clicked == "settings" then settings(player)
            elseif clicked == "deposit" or clicked == "withdraw" or clicked == "convert" or clicked == "transfer" then
                choose(player, clicked, 1)
            end
        elseif view == "settings" then
            if clicked == "change_pin" then changePinForm(player)
            elseif clicked == "convert" then choose(player, "convert", 1)
            elseif clicked == "lock_bank" then
                unlocked[id], sessions[id] = nil, nil
                login(player, "Bank berhasil dikunci.")
            elseif clicked == "native_bank" then
                assert(world, "Masuk world terlebih dahulu.")
                sessions[id] = nil
                nativePass[id] = true
                local dispatched, result = pcall(function() return world:sendPlayerMessage(player, "/bank") end)
                nativePass[id] = nil
                assert(dispatched and result ~= false, "Gem bank bawaan tidak tersedia.")
            end
        elseif view == "pin" and clicked == "save_pin" then
            if not validPin(data.bank_new_pin) or data.bank_new_pin ~= data.bank_repeat_pin then
                changePinForm(player, "PIN baru harus tepat 6 digit dan kedua input harus sama."); return
            end
            sessions[id] = nil
            local accepted, reason = verifyPin(player, data.bank_old_pin)
            if not accepted then login(player, reason); return end
            storePin(player, data.bank_new_pin, true)
            notify(player, "`2PIN berhasil diubah.")
            dashboard(player, 1)
        elseif view == "choose" then
            if page then choose(player, state.kind, page, state.from); return end
            local currency = clicked:match("^asset_(%d+)$")
            currency = currency and int(currency, 0, MAX_BALANCE)
            if currency then
                local allowed = false
                for _, item in ipairs(listAssets(state.kind)) do if item.id == currency then allowed = true end end
                assert(allowed, "Mata uang tidak diizinkan.")
                if state.kind == "convert" then choose(player, "convert_to", 1, currency)
                elseif state.kind == "convert_to" then form(player, "convert", state.from, currency)
                else form(player, state.kind, currency) end
            end
        elseif view == "form" and clicked == "review" then
            review(player, state, data)
        elseif view == "confirm" and clicked == "confirm" then
            -- Konsumsi sesi sebelum mutasi: double-click/replay tidak mengulang.
            sessions[id] = nil
            if state.op.kind == "transfer" then
                local accepted, reason = verifyPin(player, data.bank_pin)
                if not accepted then login(player, reason); return end
            end
            local logID = execute(player, state.op)
            notify(player, "`2Transaksi berhasil.`` Log #" .. logID)
            if state.op.kind == "transfer" then
                local target = getPlayer(state.op.peer)
                if target and target:isOnline() then
                    notify(target, "Transfer bank diterima: " .. fmt(state.op.amount) .. " " .. clean(asset(state.op.asset).name)
                        .. " dari " .. clean(player:getCleanName()) .. " (#" .. id .. ").")
                end
            end
            dashboard(player, 1)
        elseif view == "logs" then
            if state.admin then assert(isAdmin(player), "Akses Admin Logs sudah tidak tersedia.") end
            if page then history(player, page, state.search, state.admin, state.securityLog)
            elseif clicked == "search" then history(player, 1, data.bank_search, state.admin, state.securityLog)
            elseif clicked == "toggle_logs" and state.admin then history(player, 1, nil, true, not state.securityLog) end
        end
    end)
    return true
end)

onPlayerDisconnectCallback(function(player)
    local id = uid(player)
    sessions[id], busy[id], unlocked[id], nativePass[id] = nil, nil, nil, nil
end)

onPlayerConsumableCallback(function(world, player, tile, itemID, targetPlayer)
    if itemID ~= CREDIT_CARD_ITEM_ID then return false end
    -- Klaim sebelum built-in: menu lama dan efek konsumsi engine dilewati.
    -- Selalu buka rekening pemakai kartu, bukan targetPlayer.
    openCreditCard(player)
    return true
end)

print("[bank] " .. (ready and ("Loaded: /" .. COMMAND .. " (Credit Card v2; item 9950; direct/input/command hooks)") or "Unavailable; check initialization errors"))
