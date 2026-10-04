# gemstouws.lua

## Pemakaian

Upload **gemstouws.lua** ke folder Lua aktif server dan reload. Semua player dapat memakai **`/buyuws`**.

1. Menu menampilkan ikon **Ultra World Spray (5926)**, harga yang sedang berlaku, saldo gems, dan jumlah yang dapat dibeli. Harga awal **100.000.000 gems per UWS**.
2. Isi **Jumlah UWS**, lalu tekan **Lanjut**, atau pilih **Beli Maksimal**.
3. Periksa jumlah item, total biaya, dan sisa gems pada halaman konfirmasi. Tekan **Beli ... UWS**.
4. Setelah sukses, menu menampilkan hasil pembelian dan tombol **Beli Lagi**.

**Refresh Saldo** membuka saldo terbaru tanpa memindahkan gems/item. Warna dialog abu gelap dengan teks putih dan aksen biru muda. Item memakai ikon native berdasarkan ID 5926. Rendering akhir mengikuti client GTPS.

Hanya gems yang dibawa digunakan; saldo gems bank tidak dipotong. Tidak ada biaya tambahan. Jumlah harus bilangan bulat positif. Maksimum satu pembelian mengikuti `floor(2.000.000.000 / harga)`, kemudian dibatasi saldo saat konfirmasi dan ruang jumlah item. Dengan harga awal 100.000.000 gems, maksimum **20 UWS**; harga 50.000.000 gems memungkinkan maksimum **40 UWS**. Input pecahan, negatif, nol, pemisah ribuan, atau melebihi batas harga saat ini ditolak.

`giveItem` bawaan engine mengirim ke inventory dan menggunakan Extra Backpack untuk overflow. Script memeriksa total inventory + Extra Backpack sebelum dan sesudah pemberian; jumlah gabungan UWS sesudah pembelian dibatasi **2.000.000.000**.

Jika `/sell2` atau script lain mengubah gems ketika dialog masih terbuka, pembelian tetap memeriksa saldo terbaru. Script ini tidak mengubah pengaturan auto-convert milik `gemstobgl.lua`.

## Mengatur harga

**Founder (role tepat 1000)** dapat mengatur harga langsung melalui command, tanpa dialog:

```text
/setpriceuws 50000000
```

Harga menjadi **50.000.000 gems per UWS**. Nominal harus angka bulat **1–2.000.000.000**, tanpa titik/koma, tanda minus, desimal, atau notasi eksponen. Konfirmasi tersimpan diberikan melalui pesan console. Player lain, role admin selain Founder, NPC, dan player offline tidak dapat mengubahnya.

Harga dan revision disimpan di **uws_config** dalam database yang sama. Nilai awal hanya dimasukkan bila belum ada; restart/reload tidak mengembalikan harga ke 100.000.000. Upgrade dari versi pertama mempertahankan seluruh jurnal pembelian dan pending.

Setelah harga berubah, form/konfirmasi pembelian yang memakai revision lama kembali ke form dengan harga terbaru tanpa debit atau pemberian item. Player perlu melihat total dan mengonfirmasi lagi. Perubahan A → B → A juga membatalkan quote lama. Menetapkan harga yang sama merupakan no-op dan tidak membatalkan quote yang masih berlaku.

Harga dicek ulang di transaksi SQLite sebelum intent pembelian dibuat. Setelah debit dimulai, pembelian dan refund memakai biaya yang sudah dikonfirmasi, walaupun Founder mengubah harga ketika pemberian/refund sedang berlangsung. Perubahan harga tidak membuka ulang pending atau mengubah riwayat biaya pembelian lama.

## Penyimpanan transaksi

Jurnal pembelian menggunakan SQLite **gemstouws_v1.db** di folder server, tabel **uws_purchases**, **uws_runtime**, dan **uws_config**. Database dibuat otomatis. Tidak membutuhkan plugin tambahan selain API SQLite bawaan yang dijelaskan dalam `docslua...txt`.

Harga dan jumlah konfirmasi disimpan pada sesi server berdasarkan UID. Payload client tidak dipercaya untuk harga/jumlah konfirmasi. Nama dialog mengandung nomor generasi persisten dan nomor sesi; replay, konfirmasi milik akun lain, dialog lama setelah reload, dan konfirmasi kedaluwarsa tidak melakukan pembelian. Konfirmasi berlaku **120 detik**. Menu kedaluwarsa milik sesi yang sama otomatis kembali ke formulir. Dialog lama tidak mengganti sesi yang lebih baru.

Intent transaksi disimpan **sebelum gems dipotong**. Debit gems dan pemberian UWS masing-masing diverifikasi dari perubahan saldo/item yang tepat. Klik ulang tidak mengirim item tambahan.

- Engine menolak debit dan saldo/item tidak berubah: transaksi **cancelled**, dapat dicoba kembali.
- Engine menolak pemberian item, tidak ada UWS masuk, dan gems tetap pada saldo setelah debit: gems dikembalikan menggunakan `addGems`, lalu diperiksa pengembaliannya. Hasil **refunded** dapat dicoba kembali.
- Pemberian parsial, exception, perubahan saldo yang tidak sesuai, refund gagal, atau finalisasi database gagal: transaksi tetap **pending**; tidak dikirim/refund ulang secara otomatis, termasuk setelah reload. UID tersebut ditahan dari pembelian berikutnya. Nomor transaksi ditampilkan pada pesan pemain dan log server.

Admin perlu memeriksa **uws_purchases**, catatan log `[gemstouws] NEEDS REVIEW`/`ERROR`, serta inventory/gems engine sebelum merekonsiliasi pending. Jangan melepas pending tanpa memeriksa aset yang sudah berpindah. Tidak ada command admin untuk menganggap transaksi ambigu pasti gagal.

SQLite dan penyimpanan player engine tidak berbagi transaksi atomik. Script tidak menjamin commit gabungan item/gems/database ketika server crash. Cadangkan database bersama data player; jika server masih hidup, sertakan berkas WAL atau lakukan backup SQLite yang konsisten.

## Pemeriksaan pemasangan

Setelah reload, console harus menampilkan:

```text
[gemstouws] BOOT v2-price | Lua ...
[gemstouws] ROUTES registered=true command=true dialog=true
[gemstouws] Loaded /buyuws /setpriceuws | 5926 | ... gems per UWS
```

Command dan callback didaftarkan sebelum database diinisialisasi. Jika `INIT FAILED`, `/buyuws` dan `/setpriceuws` tetap memberikan pesan ketersediaan selama jalur command berhasil didaftarkan; lihat alasan di console. API native yang dipakai: `getItem`, `getGems`, `removeGems`, `addGems`, `giveItem`, `getItemAmount`, `getExtraBackpackAmount`, `getRole`, dan `sqlite.open`.

## Tes

**1.019 pemeriksaan lulus** pada Lua 5.1 asli dan Lua 5.4/Wasmoon dengan SQLite asli. Meliputi pembelian/jumlah/total biaya, saldo berubah, overflow, replay dan sesi, refund, pending setelah reload, kegagalan database/engine, serta pendaftaran command ketika init gagal. Pengaturan harga juga diuji untuk izin Founder, persistensi, jumlah dinamis, quote lama/perubahan A → B → A, rollback SQL, batas harga, serta biaya/refund asli ketika harga berubah selama transaksi berlangsung.

Runner memakai SQLite asli dan mock API player GTPS; tidak terhubung dengan server/client langsung. Node 22+:

```powershell
$env:GEMSTOUWS_LUA51 = 'PATH/TO/lua5.1.exe'
node tests/run-gemstouws.cjs
```

Untuk Lua 5.4/Wasmoon, hapus variabel `GEMSTOUWS_LUA51` dan jalankan runner dengan Wasmoon tersedia. `GEMSTOUWS_TEST_MODULES` dapat menunjuk folder node_modules sementara. Jalankan juga kompilasi menggunakan `luac5.1.exe -p gemstouws.lua`.
