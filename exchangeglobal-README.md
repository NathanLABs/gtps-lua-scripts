# Farming Exchange

Upload **`exchangeglobal.lua`** ke Lua Scripts server, lalu reload.

- **`/exchange2`**: menu player, terbuka untuk semua role.
- **`/setexchange2`**: panel **Founder, role 1000**, berisi hanya **Edit Provider**, **Edit Geiger**, dan **Edit Ghost**. Izin diperiksa kembali pada setiap aksi admin.
- Judul memakai `getServerName()`, dibersihkan dari kode warna dan dijadikan huruf besar. Contoh: **PUREGTPS SELL**.

Nama server tidak di-hardcode. Script tidak mengambil alih `/exchange`, `/sell`, atau `/sellfish`.

## Tampilan dan kategori

Menu mengikuti susunan referensi: judul server, sambutan, label kategori dengan ikon, deskripsi, dan tombol **GO TO EXCHANGE**.

Menu utama `/exchange2` tidak menampilkan tombol Refresh, Riwayat Transaksi, atau Panel Founder, termasuk saat dibuka Founder. Panel pengaturan tetap diakses lewat `/setexchange2`.

| Kategori | Ikon | Perilaku |
| --- | --- | --- |
| Sell Fish | 3000 | Menjalankan `/sellfish` bawaan melalui engine |
| Sell Ghost | 21264 | Resep item Ghost yang ditetapkan Founder |
| Sell Geiger | 2204 | Resep item Geiger |
| Sell Provider | 3044 | Resep item Provider |

Menu player memiliki **Fish, Ghost, Geiger, dan Provider**. Panel Founder hanya memiliki **Provider, Geiger, dan Ghost** karena Fish memakai fitur bawaan `/sellfish`. Resep lama pada kategori Global/Mix/Daily/Surgery/Crystals tetap tersimpan untuk menjaga data dan riwayat, tetapi tidak ditampilkan atau diperdagangkan pada versi empat kategori ini. Resep lama dengan beberapa bahan, BUY, atau kuota harian tetap didukung tanpa menambah menu kategori baru.

ID ikon yang diberikan hanya dipakai sebagai gambar kategori; bukan otomatis sebagai item yang dijual. ID item farming, harga, resep, dan set pakaian sengaja belum diisi karena belum ditetapkan pengelola. Kategori kosong memberi keterangan dan tetap dapat dikonfigurasi di game.

## Membuat resep dan mengatur harga

1. Buka `/setexchange2`, pilih **Edit Provider**, **Edit Geiger**, atau **Edit Ghost**.
2. Pilih **+ Tambahkan Exchange**. Form berjudul **EXCHANGE** berisi:

```text
FROM:
  ItemID
  Amount
TO:
  ItemID
  Amount
Duration (menit, 0 = Unlimited)
Limit Exchange per pemain (0 = Unlimited)
```

3. Isi item/jumlah yang dibayar pada FROM, lalu item/jumlah yang diterima pada TO.
4. Atur Duration dan Limit Exchange, lalu **Simpan Exchange**.

Contoh: FROM item bahan yang Anda pilih sejumlah `200`, TO ItemID `7188` sejumlah `5` berarti 200 bahan ditukar menjadi 5 BGL sebelum bonus. ID bahan mengikuti server; tidak ditebak dari gambar. Jumlah/ID memakai angka bulat tanpa pemisah ribuan; `1.000` bukan input untuk seribu.

Exchange baru langsung aktif, satu bahan ke satu reward, tanpa BUY balik. Nama resep dibuat otomatis dari nama item. Form edit memakai susunan yang sama. Data lama tetap disimpan: BUY, kuota harian, status aktif, dan bahan tambahan tidak dihapus saat edit. Bahan tambahan lama dijelaskan di bawah form agar Founder mengetahui bahwa bahan tersebut masih diperlukan. Konfigurasi tersimpan di SQLite dan bertahan saat reload.

Duration saat ini ditafsirkan sebagai **masa aktif exchange**, bukan waktu reset kuota. Contoh `60` berarti tersedia selama 60 menit sejak disimpan. Nilai `0` berarti tidak kedaluwarsa. Mengedit harga dengan durasi yang sama tidak memperpanjang exchange yang masih aktif. Mengubah durasi, atau menyimpan exchange yang sudah kedaluwarsa dengan durasi positif, memulai deadline baru. Exchange kedaluwarsa disembunyikan dari menu pemain, tetapi tetap bisa diedit Founder. Deadline diperiksa lagi sebelum item dipindahkan, termasuk jika dialog konfirmasi masih terbuka.

Limit Exchange saat ini ditafsirkan **per pemain, per resep, sepanjang riwayat resep itu**; nilai `0` berarti Unlimited. Satu batch memakai satu limit, jadi penukaran 10 batch memakai 10 limit. Limit menghitung transaksi `done` dan `pending`; transaksi yang dibatalkan tanpa perubahan aset tidak menghabiskan limit. Reload, edit harga, serta perpanjangan Duration tidak menghapus pemakaian. Batas ini berbeda dari kuota harian lama yang tetap reset pukul 00:00 WIB. Kedua penafsiran ini adalah asumsi sementara yang sudah disampaikan, sambil menunggu klarifikasi Duration/Limit dari pengguna.

## Cara player exchange

1. `/exchange2` → pilih kategori.
2. Kartu exchange menampilkan ikon FROM dan TO sesuai ItemID, jumlah bahan/reward, arah pertukaran, **You have**, **Duration**, dan **Limit**. Reward pemain mengikuti bonus aktif; tampilan Founder menunjukkan nilai dasar yang diedit.
3. Klik **GET!** untuk preview satu batch dari inventory biasa, lalu **KONFIRMASI**. Setelah selesai, kartu dibuka kembali dengan jumlah inventory terbaru.
4. Untuk jumlah lain atau Extra Backpack, klik ikon item. Form detail menerima jumlah batch atau `all`/`max`; pilihan BUY hanya tersedia jika resep lama memang mengaktifkannya.

Kartu menggunakan markup native `add_button_with_icon`, frame, nama item, dan teks arah berwarna. Ini tidak mengirim gambar statis; ikon mengikuti data client berdasarkan ItemID. Susunan/font/frame mengikuti renderer client dan belum diverifikasi pada client GTPS. Dua kartu per halaman; kategori dengan resep lama lebih dari tiga bahan memakai satu kartu per halaman agar tidak melewati batas paket 4096 byte.

Reward diberikan melalui `giveItem`; kelebihannya dapat masuk Extra Backpack. Maksimal 1.000.000 batch per transaksi, dan maksimal 2.000.000.000 item reward termasuk saldo inventory + Extra Backpack yang sudah dimiliki. Item reward tidak boleh sekaligus menjadi bahan resep yang sama.

Menu memakai ID sesi unik, bukan `embed_data`. Klik ganda, menu lama, kiriman milik player lain, dan menu setelah reload tidak menjalankan ulang transaksi. Ketik ulang `/exchange2` untuk membuka menu terbaru. Konfirmasi kedaluwarsa setelah 120 detik.

## Daily reset WIB

Kuota tersimpan per **ID akun + ID resep + tanggal WIB**. SELL dan BUY pada resep yang sama memakai kuota bersama. Reset mengikuti pukul **00:00 WIB (UTC+7)**, terlepas dari zona waktu mesin server, tanpa bergantung pada timer yang harus berjalan saat tengah malam.

Restart/reload tidak mereset kuota hari yang sama. Konfirmasi yang dibuat sebelum pergantian hari harus dibuka ulang sesudah tengah malam. Riwayat hari sebelumnya tetap disimpan.

## Clothing Buff Multiplier

Editor set pakaian tidak ditampilkan pada panel sederhana. Konfigurasi lama yang sudah tersimpan tetap dibaca, dengan struktur berikut:

- Nama set dan scope: `all`, `fish`, `ghost`, `geiger`, atau `provider`.
- Multiplier `1` sampai `10`, maksimal dua angka desimal.
- Daftar pakaian wajib dalam format `slot:ID,slot:ID`.

Slot engine:

| Slot | Bagian |
| --- | --- |
| 0 | Hair |
| 1 | Shirt |
| 2 | Pants |
| 3 | Feet |
| 4 | Face |
| 5 | Hand |
| 6 | Back |
| 7 | Mask |
| 8 | Necklace |
| 9 | Ances |

Semua pakaian yang dikonfigurasi harus sedang dikenakan pada slot yang benar. Jika beberapa set cocok, hanya set dengan multiplier tertinggi yang dipakai. Kepemilikan item tanpa mengenakannya tidak memberi bonus. Pakaian diperiksa lagi saat konfirmasi.

## Event multiplier realtime

Editor event tidak ditampilkan pada panel sederhana. Konfigurasi lama yang sudah tersimpan tetap dibaca, dengan struktur berikut:

- Scope `all` untuk event global, atau satu kategori tertentu.
- Multiplier `1`–`10`.
- Mode `manual`, `server`, atau `daily`.
- ID event engine, jika memakai mode `server`/`daily`.
- Durasi menit sejak Save; `0` berarti tanpa batas waktu. Menyimpan ulang event memulai ulang durasinya.

ID event yang didokumentasikan engine:

| Mode | ID | Event |
| --- | --- | --- |
| server | 3 | Halloween |
| server | 4 | Night of the Comet |
| server | 5 | Harvest |
| daily | 40 | Geiger Day |
| daily | 42 | Surgery Day |

ID `0` berarti tidak ada event engine; tidak dapat dipakai sebagai syarat event native aktif. Event manual tidak memerlukan ID.

Perhitungan SELL:

**Reward = floor(harga dasar × batch × bonus pakaian × event global × event kategori)**

Pada scope yang sama, hanya event aktif dengan multiplier tertinggi yang dipakai. Gabungan multiplier dibatasi **x100**. Pembulatan dilakukan pada total order, sehingga preview satu batch yang dibulatkan tidak selalu dapat dikalikan langsung untuk memperkirakan order besar.

Bonus diperiksa saat preview dan konfirmasi. Event yang berakhir, pakaian yang berubah, atau konfigurasi/harga yang diedit membatalkan hitungan lama sebelum bahan diambil. Pilih ulang untuk memakai harga terbaru. Founder perlu mengatur harga BUY/SELL dengan mempertimbangkan bonus agar tidak menciptakan keuntungan tak terbatas dari beli lalu jual kembali.

## Khusus Sellfish bawaan engine

Sesuai permintaan, tombol Fish langsung meneruskan command `/sellfish` yang sudah tersedia. Script ini **tidak membuat proses penjualan ikan kedua**.

API Lua lokal yang tersedia tidak menyediakan callback transaksi atau setter payout Sellfish bawaan. Karena itu, harga/bonus penjualan ikan bawaan tetap mengikuti engine. Pengaturan event scope `fish` pada script ini **tidak otomatis mengubah hasil `/sellfish` native**.

Untuk integrasi masa depan jika ada script/hook Sellfish yang bisa diedit, file menyediakan API kalkulasi tanpa mutasi inventory:

```lua
local multiplier, details = ExchangeGlobal.getSellMultiplier(player, "fish")
local reward = ExchangeGlobal.calculateSellReward(player, "fish", baseReward)
```

API menghitung Clothing × Event Global × Event Fish; kode penjualan yang memanggilnya tetap bertanggung jawab atas debit, reward, dan jurnal. API tersedia pada konteks Lua tempat file dijalankan, dan juga dikembalikan oleh file. Jangan memuat dua salinan script hanya untuk mengambil API, dan jangan memberi payout tambahan di atas reward native yang sudah diberikan. Integrasi tersebut belum terhubung ke `/sellfish` bawaan karena tidak ada hook yang didokumentasikan.

Fish tidak memiliki panel pengaturan di `/setexchange2`; penjualan ikan tetap mengikuti fitur bawaan engine.

## Panel Founder dan log

Panel utama hanya menyediakan tiga tombol: **Edit Provider**, **Edit Geiger**, dan **Edit Ghost**. Masing-masing membuka daftar exchange, form FROM/TO + Duration/Limit, serta toggle kategori. Harga yang diedit tidak bisa diproses memakai konfirmasi lama. Owner role 999 atau Dev bukan Founder tidak mendapat akses panel.

Tombol Fish, toggle global, pakaian, event, Admin Logs, dan pratinjau menu player tidak ditampilkan di panel Founder. Riwayat dan jurnal tetap disimpan di database untuk pemeriksaan pengelola; penyederhanaan menu tidak menghapus data atau mengubah harga lama.

## Penyimpanan dan transaksi pending

Database: **`exchangeglobal_v1.db`** pada folder server. Backup bersama data player, menggunakan backup SQLite yang konsisten dengan WAL. Jangan menghapus database untuk reload.

Sebelum engine memindahkan item, script menyimpan jurnal `pending`, snapshot jumlah bahan/reward, dan reservasi kuota dalam satu transaksi database. Jurnal menyimpan rincian setiap langkah di `ex_legs`, termasuk sumber inventory/Extra Backpack dan jumlah sebelum/sesudah.

- Jika seluruh aset tetap sama saat engine menolak, transaksi dibatalkan dan reservasi kuota dikembalikan.
- Jika sebagian bahan sudah diambil, reward gagal, atau database gagal setelah mutasi, transaksi tetap pending. Akun ditahan dari transaksi exchange berikutnya.
- Transaksi pending tidak dicoba ulang otomatis. Founder perlu mencocokkan `ex_journal`, `ex_legs`, `ex_daily`, data player, dan backup sebelum rekonsiliasi. Jangan sekadar mengubah status atau mengulang reward.

Tidak ada transaksi atomik bersama antara SQLite dan inventory/save engine. Crash setelah jurnal selesai tetapi sebelum player tersimpan masih dapat memerlukan pemeriksaan backup. Kartu kredit, crypto, gemstobgl, dan saldo native tidak disentuh oleh script ini.

## Pengujian

`tests/run-exchangeglobal.cjs` menggunakan Lua 5.4 (Wasmoon) dan SQLite sungguhan; API game memakai mock. Node 22+ diperlukan untuk `node:sqlite`.

```powershell
$env:EXCHANGE_TEST_MODULES = 'C:\path\to\node_modules'
node tests/run-exchangeglobal.cjs
```

548 pemeriksaan mencakup empat kategori player, tiga tombol Founder, form enam field, kartu ikon, GET satu batch, migrasi database lama, Duration/expiry pada konfirmasi, limit per pemain dan `all`, persistensi limit saat reload, pembatalan tanpa penggunaan limit, role Founder, SELL/BUY/resep lama, Extra Backpack, kuota WIB, multiplier lama, replay, kegagalan engine/SQL, pending, serta batas ukuran paket kartu. Konfigurasi lanjutan lama disiapkan langsung sebagai data tes karena editornya sudah tidak ditampilkan. Tampilan pada client GTPS dan routing `/sellfish` tetap perlu dicoba di server asli.
