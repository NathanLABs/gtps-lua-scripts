# Credit Card Bank

Perbaikan kompatibilitas Lua: hashing PIN menggunakan operasi aritmetis, tanpa `>>`, `<<`, operator bit Lua 5.3, `string.pack/unpack`, atau `table.unpack`. Ini mengatasi sumber error kompilasi `unexpected symbol near '>'` pada engine Lua lama. Hasil HMAC-SHA-256 tetap sama; PIN dan saldo lama tidak perlu direset. Sintaks lolos parser Lua 5.1, 5.2, dan 5.3 melalui `tests/check-lua-syntax.cjs` (dependency `luaparse`, lokasi opsional lewat `LUA_PARSER_MODULES`). Pengujian perilaku lokal menggunakan Lua 5.4; integrasi tetap perlu dicek pada engine server.

Ganti/nonaktifkan script **bank.lua** lama di Lua Scripts server, upload **creditcard.lua**, lalu reload. Jangan aktifkan kedua versi bersamaan. Jalankan **`/cc`** atau gunakan item **Credit Card ID 9950**; semua player dapat membuat akun. Tidak ada syarat KTP. Alias `/vault` tetap tersedia untuk kompatibilitas. Command `/bank` tidak didaftarkan atau ditangani oleh script ini sehingga tetap tersedia untuk gem bank bawaan.

Script mengikuti alur video referensi menggunakan dialog native: Bank Card Account → login PIN → Bank Dashboard → Account Settings, Add Assets, Withdraw Assets, Transfer Assets, dan Logs. Identitas kartu ditampilkan sebagai `CC-<ID akun>`. `/cc` tetap dapat dipakai tanpa memiliki kartu fisik.

Pemakaian item `9950` ditangani melalui `onPlayerConsumableCallback` yang mengembalikan `true`, sehingga engine melewati menu Credit Card bawaan dan efek konsumsi item. `/cc` memakai callback langsung pada `registerLuaCommand`, hook paket `action=input` untuk teks `/cc`, dan callback command umum. Setiap rute yang ditangani mengembalikan `true` untuk menahan jalur bawaan. Jika engine menolak pendaftaran nama command yang sudah ada, error dicatat tetapi pemasangan input/command hook tetap berjalan. Menu baru membuka rekening pemakai, bukan target player. Jika PIN sudah terverifikasi, langsung tampil dashboard; jika belum, tampil login/setup PIN. Kartu tidak dikurangi dari inventory. Item lain, termasuk ID lama yang keliru `3936`, tidak diambil alih.

Sesudah upload/reload, pastikan log server menampilkan **`[bank] Loaded: /cc (Credit Card v2; item 9950; direct/input/command hooks)`**. Jika menu lama masih muncul, cek apakah baris ini ada atau muncul `INIT FAILED`/error Lua. Tanpa script berhasil dimuat, callback pengganti tidak bisa bekerja. Hasil tes lokal belum membuktikan script yang aktif pada server sudah versi terbaru.

Penggantian ini menahan menu bawaan melalui callback, bukan menghapus kode engine atau saldo bawaan. Data bank versi script sebelumnya tetap digunakan. Saldo pada sistem Credit Card bawaan engine yang berbeda tidak otomatis dimigrasikan oleh API ini.

## Pemakaian

1. Ketik `/cc` atau gunakan Credit Card `9950`, buat PIN **tepat 6 digit**, lalu ulangi PIN. Angka nol di depan didukung.
2. **Add Assets**: pilih lock/gems, masukkan jumlah, lalu konfirmasi. Lock dapat diambil dari backpack atau Extra Backpack melalui checkbox; satu sumber per transaksi.
3. **Withdraw Assets**: tarik saldo. Lock masuk backpack, kelebihannya ke Extra Backpack. Gems masuk saldo gems yang dibawa.
4. **Transfer Assets**: pilih aset, isi nama player online atau ID akun bank, dan jumlah. Periksa nama/ID penerima pada konfirmasi dan masukkan PIN lagi. Penerima offline dapat menerima melalui ID jika sudah terdaftar di bank.
5. **Logs**: cari ID transaksi, ID akun, ID aset, jenis transaksi (`deposit`, `withdraw`, `transfer`, `convert`), atau status (`done`, `pending`, `cancelled`). Pemain melihat maksimal 50 hasil terbaru miliknya, termasuk transfer masuk. Log baru mencatat saldo sebelum/sesudah; log lama tetap ditampilkan tanpa mengarang saldo historis.

Contoh jumlah: `1000`, `1.000`, `1,000`, `1 000`, `1k`, `1.5m`, `1,5m`, `2b`, `all`, atau `max`. Tanpa suffix, titik/koma/spasi berarti pemisah ribuan. Pecahan item seperti `1.5` ditolak. `all/max` mengikuti saldo, sumber, serta ruang saldo bank atau gems yang dibawa.

Dashboard menampilkan saldo per aset, status akun, dan perkiraan nilai lock dalam WL. Gems dan lock tanpa kurs tidak dimasukkan ke nilai WL. Tidak ada biaya transaksi tambahan.

**Refresh** membuka dashboard terbaru. Klik pada menu lama/kedaluwarsa membuka menu baru tanpa menjalankan transaksi lama. Tombol memakai ID dialog unik di sisi server, tanpa bergantung pada `embed_data`. Menutup dialog tidak membukanya kembali.

## Account Settings dan PIN

- **Ubah PIN** memerlukan PIN lama dan dua input PIN baru.
- **Convert Locks** menukar saldo lock di bank mengikuti kurs konfigurasi; hasil harus bilangan utuh.
- **Buka Gem Bank Bawaan** meneruskan `/bank` ke engine. Saldo bank gems bawaan tetap terpisah dari script ini.
- **Kunci Bank / Logout** mengunci akses segera. Sesi juga terkunci setelah 5 menit tidak digunakan, disconnect, atau reload script.
- Setiap transfer meminta PIN lagi. Lima kegagalan verifikasi mengunci akses selama 15 menit; jumlah kegagalan dan waktu blokir bertahan setelah reload.

Gunakan PIN khusus game ini. Script tidak menyimpan PIN mentah: verifier memakai HMAC-SHA-256, salt per akun, dan secret/pepper terpisah pada KV server. Ini adalah perlindungan PIN tambahan untuk game, **bukan password KDF lambat seperti Argon2/PBKDF2 dan bukan jaminan keamanan perbankan nyata**. Jika database dan secret server keduanya bocor, ruang PIN 6 digit tetap mudah ditebak secara offline. Tidak ada PIN admin universal atau reset PIN melalui command. Pemulihan PIN yang terlupa memerlukan prosedur verifikasi pemilik akun oleh pengelola server.

## Konfigurasi

Edit bagian atas `creditcard.lua`:

| Pengaturan | Default / fungsi |
| --- | --- |
| `COMMAND` | `cc`, command utama tanpa slash |
| `LEGACY_COMMAND` | `vault`, alias versi lama |
| `ADMIN_ROLE` | `4`, Dev ke atas dapat membaca Admin Logs |
| `CREDIT_CARD_ITEM_ID` | `9950`, item yang membuka menu Credit Card baru |
| `CARD_ICON_ID` | Mengikuti `CREDIT_CARD_ITEM_ID`, ikon judul menu |
| `AUTH_SECONDS` | `300`, masa sesi setelah aktivitas terakhir |
| `DIALOG_SECONDS` | `120`, masa berlaku satu dialog |
| `PIN_MAX_ATTEMPTS` | `5`, batas PIN salah |
| `PIN_LOCK_SECONDS` | `900`, lama blokir PIN |
| `LOCKS` | Daftar ID, nama opsional, dan kurs dalam WL |
| `DB_FILE` | `creditcard_v1.db`, default untuk instalasi baru |
| `DB_PATH_KEY` | `creditcard_database_file_v1`, KV opsional untuk memilih database yang sudah ada |

Default lock mengikuti konfigurasi sebelumnya: WL `242` = 1 WL, DL `1796` = 100 WL, BGL `7188` = 10.000 WL, GGL `8470` = 1.000.000 WL. Nama diambil dari item engine. Item yang tidak tersedia tidak diaktifkan.

Contoh tambahan pada `LOCKS`:

```lua
{ id = 25000, name = "Custom Lock", value = 100000000 },
```

Ganti ID dan kurs dengan milik server; contoh tersebut bukan ID yang dijamin tersedia. `value = 0` mendukung simpan/tarik/transfer tanpa conversion. Nama lock custom pada video tidak dipaksakan karena ID servernya belum diketahui.

Mengubah kurs memengaruhi conversion saldo yang sudah ada. Lock yang dihapus dari konfigurasi tetap dapat ditarik selama itemnya masih tersedia di engine. Jangan hapus item engine sebelum saldo pemain ditarik.

Conversion gems ↔ BGL tetap melalui script **`gemstobgl.lua` / `/sell2`**, dengan gems/BGL yang dibawa pemain. Bank ini menyimpan keduanya sebagai aset terpisah.

## Admin Logs

Dev ke atas mendapatkan tombol **Admin Logs** setelah login PIN miliknya sendiri. Admin dapat mencari seluruh jurnal transaksi serta **Security Logs** untuk pembuatan/perubahan PIN, kegagalan PIN, dan blokir. PIN tidak ditampilkan di log. Akses diperiksa ulang setiap membuka/mencari/mengganti halaman. Fitur admin ini hanya membaca catatan; tidak memberikan hak mengambil saldo player lain.

## Data lama dan backup

Instalasi baru memakai **`creditcard_v1.db`**. Instalasi lama wajib memilih database yang sudah ada melalui KV **`creditcard_database_file_v1`** sebelum mengganti script; langkahnya ada di [PUBLISHING.md](PUBLISHING.md). Nama file ini tidak menentukan nama command. Script menambahkan tabel keamanan/metadata dan kolom jurnal saat pertama dijalankan. Pemain lama diminta membuat PIN jika akun belum memiliki PIN.

Backup database bank **bersama data player dan KV server**, termasuk key **`blackcard_pin_secret_v1`**. Jangan mengganti nama file database atau key secret untuk sekadar mengganti tampilan. Backup SQLite harus konsisten; jangan menyalin `.db` saja sambil mengabaikan WAL pada server aktif.

Jika secret hilang atau berubah saat sudah ada data keamanan, bank menolak aktif. Pulihkan backup KV yang cocok; jangan menghapus database atau membuat secret baru untuk melewati pemeriksaan. Database bank saja tidak cukup untuk memulihkan akses PIN.

## Transaksi pending

Batas saldo bank adalah **2.000.000.000 per aset per akun**. Transfer dan conversion internal diproses dalam satu transaksi SQLite. Konfirmasi ulang/replay tidak memindahkan saldo lagi.

API engine tidak menyediakan transaksi atomik lintas SQLite dan inventory/save player. Deposit/withdraw mencatat `pending` sebelum memindahkan aset, memeriksa hasil API dan perubahan jumlah, lalu menyelesaikan saldo/jurnal. Penolakan API tanpa perubahan aset dicatat `cancelled`. Hasil sebagian/ambigu atau kegagalan database setelah aset berpindah tetap `pending`; akun ditahan dari transaksi berikutnya. Transfer ke akun yang ditahan juga ditolak.

Jika dashboard meminta pemeriksaan:

1. Catat ID transaksi dan hentikan upaya mengulangnya.
2. Pengelola mencocokkan `actor`, `kind`, `asset`, `amount`, `source`, `wallet_before`, `bank_before`, `status`, dan waktu jurnal dengan inventory, Extra Backpack, gems, log engine, serta backup.
3. Rekonsiliasi saat akses akun dikendalikan/server dihentikan dan backup tersedia. Koreksi saldo dan status journal bersama dalam transaksi database. Jangan sekadar menandai `done` karena saldo bank mungkin belum diperbarui.

Crash setelah journal selesai tetapi sebelum engine menyimpan player tetap memerlukan pemeriksaan backup. API yang tersedia tidak memberi pemaksaan save player atau transaksi bersama dengan database script.

## Pengujian lokal

`tests/run-bank.cjs` menjalankan `tests/bank-test.lua` dengan Lua 5.4 (Wasmoon) dan SQLite sungguhan melalui Node `node:sqlite`. Jalankan dengan Node 22+ dan dependency `wasmoon`; `BANK_TEST_MODULES` dapat menunjuk folder `node_modules` di luar project.

```powershell
$env:BANK_TEST_MODULES = 'C:\path\to\node_modules'
node tests/run-bank.cjs
```

Pengujian mencakup migrasi data lama, format angka, deposit/withdraw, Extra Backpack, custom lock, transfer online/offline, rollback SQL, pending, batas saldo, PIN/lockout, pergantian PIN, sesi/replay, privasi log, pencabutan role admin, dan pencocokan HMAC dengan Node crypto. Jalur kartu menguji callback command langsung, input `/cc`, kegagalan registrasi nama command, pengambilalihan menu bawaan, ikon 9950, kartu tidak dikonsumsi, rekening pemakai yang benar, PIN tetap wajib, serta item lain tidak terpengaruh. Semua 519 pemeriksaan lolos saat implementasi. API game memakai mock; tampilan client, routing item/menu bawaan, dan perilaku penyimpanan engine tetap perlu diverifikasi di server GTPS.

Upload hanya `creditcard.lua`, bukan folder `tests`. Untuk server lama, pilih database yang sudah ada sebelum reload sesuai [PUBLISHING.md](PUBLISHING.md). Pertahankan seluruh data bank dan KV PIN `blackcard_pin_secret_v1`; jangan membuat database kosong sebagai pengganti saldo lama.
