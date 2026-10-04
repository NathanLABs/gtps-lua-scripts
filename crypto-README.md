# Crypto Digital Marketplace

Ganti script `crypto.lua` lama dengan file ini, lalu reload. Jangan menjalankan dua salinan script sekaligus. `/crypto` tersedia untuk semua player; `/setcrypto` hanya untuk **Founder, role 1000**. Hak Founder diperiksa kembali ketika tombol pengaturan diklik.

## Tampilan sesuai referensi

- Header Crypto Digital Marketplace, dengan logo Bitcoin jika item logonya tersedia.
- Tombol Bitcoin, Ethereum, dan Litecoin memakai frame kuning, ditutup dengan `END_LIST` agar menjadi satu kelompok ikon.
- Harga setiap coin dalam **GGL**, portfolio per coin, perkiraan total aset, wallet, dan Refresh Market Prices.
- Detail coin: logo, trend, harga GGL, fee, saldo coin, input jumlah, BUY, SELL, dan Back.
- Panel Founder: edit harga/logo/peluang naik, Pump / Dump, pengaturan fee/interval, auto-fluctuation, serta nilai lock.

Dialog dibuat dengan markup native. Skala, pembungkusan teks, dan jumlah ikon per baris mengikuti ukuran layar serta client. Hasil visual belum diuji pada client GTPS langsung.

## Logo Bitcoin / Ethereum / Litecoin

Gambar yang dikirim melalui chat **belum otomatis menjadi item di client game**. Script menggunakan ID item server untuk menampilkan logo, sama seperti ikon pada dialog referensi.

ID logo sudah dipasang sesuai data server yang diberikan:

| Coin | ID item logo |
| --- | --- |
| Bitcoin (BTC) | 10002 |
| Ethereum (ETH) | 10012 |
| Litecoin (LTC) | 10014 |

Saat pertama load versi ini, konfigurasi coin yang sudah tersimpan juga mendapat ketiga ID tersebut. Migrasi hanya mengubah logo dan penanda versinya, tanpa mereset harga atau portfolio. Perubahan logo melalui `/setcrypto` setelah migrasi tetap dipertahankan saat reload berikutnya.

Jika logo belum muncul:

1. Pastikan ketiga logo sudah terpasang sebagai custom item/texture pada server dan client.
2. Buka `/setcrypto` → **Edit BTC - Price GGL / Logo**, isi **ID custom item logo** Bitcoin, lalu Save.
3. Ulangi untuk ETH dan LTC, lalu buka `/crypto`.

ID divalidasi harus tersedia di engine. Script tidak dapat memastikan isi gambar dari ID item, jadi pilih item logo yang benar. Jika item logo belum tersedia, menu memakai tombol teks dan panel Founder menjelaskan logo yang belum tersedia. Nilai `0` pada editor memilih tampilan teks.

## Harga GGL

Founder membuka `/setcrypto` → Edit coin, lalu mengisi **Harga per coin (GGL)**. Contoh `2.5` atau `2,5` berarti **2,5 GGL untuk 1 coin**. Tidak memakai pemisah ribuan pada input harga. Harga harus setara bilangan WL utuh, karena pembayaran dilakukan menggunakan item lock.

Untuk server baru, kurs default:

| Lock | Item ID | Nilai WL |
| --- | --- | --- |
| WL | 242 | 1 |
| DL | 1796 | 100 |
| BGL | 7188 | 10.000 |
| GGL | 8470 | 1.000.000 |

Nilai GGL baru mengikuti referensi dan konfigurasi bank. **Jika server sudah menyimpan `crypto_locks`, kurs lama dipertahankan.** Versi lama script memiliki default GGL 100.000 WL; periksa `/setcrypto` → Manage Lock Values sebelum mengubahnya. Mengubah kurs GGL memengaruhi nilai wallet dan harga yang ditampilkan dalam GGL, sementara harga internal coin tetap dalam WL.

Input **nilai lock dalam WL** menerima `1000000`, `1.000.000`, `1,000,000`, atau `1 000 000`. Ini berbeda dari input **harga coin dalam GGL**, yang memakai desimal seperti `2.5`. Nilai baru dikonfirmasi setelah penyimpanan konfigurasi dan pembacaan ulang berhasil. Data konfigurasi kosong/rusak yang ditemukan tidak ditimpa dengan default.

Harga internal dan portfolio lama tidak dikalikan saat migrasi. Contoh harga BTC lama 51.500 WL ditampilkan sebagai 0,0515 GGL pada kurs 1.000.000 WL/GGL, atau 0,515 GGL pada kurs lama 100.000 WL/GGL. Founder bisa menetapkan harga baru langsung dalam GGL.

Pembayaran BUY dapat menggunakan gabungan lock terdaftar dari backpack. Kembalian/payout SELL dibagi ke lock terdaftar, dengan overflow ke Extra Backpack melalui API engine. Extra Backpack tidak digunakan sebagai sumber pembayaran BUY. Nilai payout SELL dibulatkan ke bawah ke WL utuh setelah fee.

Jumlah coin per order wajib bulat 1–10.000. Total satu order maksimal 2.000.000.000 WL, harga satu coin maksimal 1.000.000.000 WL internal, dan saldo maksimal 2.000.000.000 per coin. WL wajib bernilai 1; WL/GGL tidak dapat dihapus dari daftar lock. Mendukung maksimal 8 coin dan 8 jenis lock untuk menjaga ukuran dialog.

## Pengaturan Founder

- **Edit**: harga GGL, nama, ID logo, serta peluang naik coin tersebut 0–100.
- **Pump / Dump**: persentase cepat atau custom.
- **Toggle Auto-Fluctuation**: default server baru OFF agar harga tetap sesuai input Founder. Pengaturan server lama dipertahankan.
- **Configure Fee & Update Interval**: fee jual, interval update, peluang naik default, dan perubahan maksimum. Coin yang memiliki override memakai peluang naiknya sendiri.
- **Manage Lock Values**: mengatur ID/kurs lock; custom lock harus tersedia di engine.

Total di panel Founder mencakup **player online**, sesuai API yang tersedia. Ini tidak diklaim sebagai total seluruh akun offline.

## Tombol dan transaksi

Setiap dialog memakai ID unik per sesi/reload dan masa berlaku 120 detik. Menu lama, double-click, atau paket palsu tidak menjalankan ulang transaksi. Jika harga, fee, atau konfigurasi berubah setelah menu dibuka, player mendapat menu terbaru sebelum bertransaksi. Refresh membuka marketplace terbaru; menutup dialog tidak menyimpan perubahan.

Tick harga otomatis tidak membatalkan input Founder yang sedang dibuka. Edit konfigurasi lain oleh Founder tetap membatalkan form lama agar tidak saling menimpa. Setelah menyimpan harga coin, pesan sukses menunjukkan nilai GGL yang tersimpan dan mengingatkan jika Auto-Fluctuation masih ON. Matikan fitur itu untuk mempertahankan harga coin yang tetap; nilai lock GGL tidak ikut berfluktuasi.

Script memeriksa hasil API pengurangan/pemberian lock dan keberhasilan penyimpanan portfolio. Sebelum mutasi, marker persisten `crypto_pending_<uid>` mencatat jenis transaksi, coin, jumlah, harga/fee, saldo coin sebelumnya, serta wallet inventory/Extra Backpack.

Jika API memindahkan sebagian aset, payout gagal, atau penyimpanan gagal setelah mutasi, marker tetap `pending` dan akun ditahan dari transaksi crypto berikutnya. Pengelola perlu mencocokkan marker dengan data player dan backup sebelum memperbaiki saldo. **Jangan sekadar menghapus marker atau mengulang payout.** Marker kosong `{}` berarti tidak ada transaksi yang sedang ditahan.

API engine/KV tidak menyediakan satu transaksi atomik bersama inventory dan save player. Mekanisme ini tidak menjamin pemulihan otomatis untuk semua crash. Backup KV dan data player bersama; rekonsiliasi harus dilakukan saat akses akun dikendalikan.

Data lama tetap memakai `crypto_coins`, `crypto_locks`, `crypto_settings`, dan `crypto_p_<uid>`. Data sesi memakai `crypto_ui_generation`. Tidak menghapus data tersebut saat reload.

Pembacaan konfigurasi menerima daftar berindeks angka maupun teks (`1` atau `"1"`), termasuk indeks berurutan mulai nol. Angka yang tersimpan sebagai teks juga dinormalisasi. Harga dan portfolio tetap dipertahankan; data kosong, ambigu, atau rusak tidak ditimpa default. Pemeriksaan hasil penyimpanan tetap membandingkan nilainya setelah normalisasi.

Jika market belum tersedia, Founder dapat membuka `/setcrypto` untuk melihat **Market Offline**, rincian penyebab, dan tombol **Coba Muat Ulang Market**. Tombol membaca ulang data tersimpan serta memulai timer jika aktif; tidak mengulang transaksi atau menghapus marker pending. Kegagalan tetap dicatat dengan awalan `[crypto] INIT FAILED`, `Recovery failed`, atau `Auto-update failed`. Player biasa hanya mendapat pemberitahuan market belum tersedia. Rincian ini diperlukan untuk memastikan penyebab di server; format indeks teks baru direproduksi sebagai salah satu penyebab dalam tes lokal.

## Tes

`tests/run-crypto.cjs` membutuhkan Node dan `wasmoon`. Dependency boleh berada di folder terpisah:

```powershell
$env:CRYPTO_TEST_MODULES = 'C:\path\to\node_modules'
node tests/run-crypto.cjs
```

296 pemeriksaan lolos menggunakan Lua 5.4 dan mock API engine/persistence: migrasi nilai lama dan ID logo, harga GGL, logo terkonfigurasi/tidak tersedia, role Founder, buy/sell, fee/kembalian, input tidak valid, replay/sesi kedaluwarsa, perubahan harga, kegagalan save/API, pending, pump/dump, fluctuation, ukuran dialog, penyimpanan saat tick harga berlangsung, persistensi setelah reload, indeks teks/nol, nilai angka/boolean berbentuk teks, data rusak, panel pemulihan, pencabutan role, pemulihan kegagalan timer, callback command langsung, input command, registrasi ditolak, dan hook opsional tidak tersedia. Upload hanya `crypto.lua`, bukan folder pengujian.

## Jika command tidak dikenal

Versi `v3-command-routing` memasang callback langsung pada `/crypto` dan `/setcrypto`, callback command umum, serta hook `action=input`. Pemeriksaan Founder tetap dilakukan di setiap jalur `/setcrypto`. Registrasi setiap jalur dilindungi terpisah agar satu kegagalan tidak menghentikan pemasangan lainnya. Kegagalan konfigurasi market tetap menyediakan command menuju pemberitahuan/panel diagnostik.

Setelah mengganti file server dan reload, periksa log:

```text
[crypto] BOOT v3-command-routing
[crypto] ROUTES v3: /crypto=true, /setcrypto=true, command=true, input=true, dialog=true
[crypto] Loaded. /crypto: marketplace GGL, /setcrypto: Founder.
```

`BOOT` menandai file mulai dieksekusi; `ROUTES` menunjukkan API registrasi yang berhasil dipanggil tanpa error/hasil `false`, bukan bukti pengiriman command pada engine sudah teruji. Jika `BOOT` tidak muncul, periksa error kompilasi dan apakah file terbaru aktif. Jika ada `ROUTE FAILED`, catat rincian baris tersebut; jika `INIT FAILED`, catat penyebab inisialisasi. Jalur ini diuji lokal dengan mock engine; penyebab `unknown command` di server nyata memerlukan log server. Upload hanya satu versi script crypto agar handler lama tidak bertabrakan.
