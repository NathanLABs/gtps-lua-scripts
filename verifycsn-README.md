# verifycsn.lua

## Command

- `/addverify NAMAWORLD`: Founder (role **1000**) menambahkan world ke daftar. World harus ada, nama 1–24 huruf/angka. Nama dinormalisasi menjadi uppercase. Duplikat ditolak.
- `/removeverify NAMAWORLD`: Founder (role **1000**) mencabut verifikasi satu world. Contoh: `/removeverify SPIN`. Nama tidak peka huruf besar/kecil. World yang sudah tidak ada di engine juga dapat dicabut jika masih terdaftar.
- `/verifycsn`: seluruh pemain membuka daftar dan menekan nama world untuk berkunjung. Native `player:enterWorld` tetap menentukan izin masuk.

Layout terbaru mengikuti `Cuplikan layar 2026-10-02 163510.png`: judul cream **Verified Casino Worlds**, ikon Roulette Wheel **758**, paragraf pembuka Inggris, subjudul **List of verified casino worlds:**, tombol world biru besar, dan tombol biru **Close Menu**. Latar berwarna biru transparan dengan border putih.

Format tombol mengikuti gambar terbaru:

```text
[#1] NAMAWORLD (10 Players) - Rated: 0.0 (0x)
```

`#1`, `#2`, dan seterusnya berwarna pink (kode warna client `` `# ``); teks lainnya cream (`` `o ``). Format `Rated` pada gambar terbaru menggantikan suffix owner dari permintaan sebelumnya. World diurutkan berdasarkan jumlah player online terbanyak, lalu rating dan nama world jika jumlahnya sama. Jumlah tidak mencakup NPC atau player yang sudah offline.

World baru belum memiliki penilaian sehingga tampil **0.0 (0x)**. Tidak memakai contoh **5.0 (1x)** sebagai rating palsu. Metadata `ratingTotal` dan `ratingCount` bila tersedia di data server digunakan sebagai total skor dan jumlah penilaian. Tidak ada menu rating/report tambahan dalam perubahan tampilan ini.

Daftar dibagi 18 world per halaman agar tidak melebihi batas dialog engine. Nomor berlanjut pada halaman berikutnya. Kontrol halaman hanya muncul jika diperlukan; daftar satu halaman tidak memiliki subtitle jumlah world/halaman. Jumlah player diperbarui setiap membuka halaman. Karena `getWorld` dapat memuat world dari disk, pembacaan daftar juga dapat memuat world terdaftar yang sedang tidak aktif.

## Dialog masuk world

Layout mengikuti `Cuplikan layar 2026-10-02 163539.png`. Setiap player yang masuk world terverifikasi mendapatkan judul besar hijau **Welcome to Verified Casino!**, paragraf pembuka putih, enam aturan cream dengan teks sama persis seperti gambar, serta tombol native kuning **Continue**. Tidak ada ikon lock, nama world, owner, jumlah player, atau tombol daftar pada welcome. World yang belum terdaftar tidak memunculkan dialog.

Continue menutup dialog tanpa memindahkan player. Teks aturan merupakan pemberitahuan yang diminta pengguna, bukan implementasi otomatis ban, nuke, refund, pembatasan level, atau pemantauan transaksi. Markup memakai elemen native, sehingga pembungkusan teks dan ukuran akhir mengikuti client/resolusi. Belum ada hasil render dari client GTPS aktual setelah perubahan ini.

## Penyimpanan

Daftar disimpan lewat API bawaan `saveDataToServer` / `loadDataFromServer` pada key **verifycsn_worlds_v1**. Versi data tetap **1** sehingga verifikasi lama tetap terbaca. Data berisi array world dengan `name`, `addedBy` (UID Founder), `addedAt` (timestamp), dan metadata rating opsional. Runtime baru diperbarui setelah penyimpanan sukses. Format tidak dikenal/rusak menghentikan inisialisasi dan tidak ditimpa. Maksimum 1.000 world.

Pembacaan mendukung array Lua biasa serta object JSON dengan indeks teks `"1"`, `"2"`, dan seterusnya. Indeks rapat mulai dari `0` juga didukung. Script menghitung seluruh entry menggunakan `pairs`, mengurutkan indeks, lalu membuat array Lua mulai dari `1`; tidak memakai `#` atau `ipairs` pada data mentah hasil decode. Ini memperbaiki error **Daftar world tersimpan harus berupa array utuh** setelah reload pada engine yang mengembalikan indeks sebagai string.

Normalisasi hanya terjadi di memori saat load; key, versi data, daftar world, metadata Founder/timestamp, dan rating tetap dipertahankan. Load tidak menyimpan ulang atau mereset daftar. Semua record diperiksa sebelum daftar diterbitkan ke runtime. Indeks berlubang/duplikat, key asing, record rusak, rating tidak valid, dan jumlah berlebih tetap ditolak tanpa membuang entry.

Verifikasi berlaku pada nama world, bukan account pemilik; perubahan owner tidak mencabut verifikasi otomatis. Gunakan `/removeverify NAMAWORLD` untuk mencabut satu world. Setelah sukses, world tidak muncul lagi di daftar, tombol lama tidak dapat mengarahkannya lewat menu Verify CSN, dan entry berikutnya tidak memunculkan welcome. Penghapusan tetap tersimpan setelah reload. World lain beserta metadata/rating tetap dipertahankan; save gagal tidak mengubah daftar runtime. World dapat didaftarkan kembali melalui `/addverify` sebagai record baru. Jangan menghapus key untuk satu world karena itu menghilangkan seluruh daftar.

## Pemasangan dan pengujian

Taruh `verifycsn.lua` di folder Lua yang benar-benar dimuat server, lalu reload/restart script. Console harus menampilkan:

```text
[verifycsn] BOOT v4-remove | Lua ...
[verifycsn] ROUTES registered=true command=true dialog=true enter=true
[verifycsn] Loaded ... verified worlds | /addverify /removeverify /verifycsn
```

Jika `INIT FAILED`, periksa pesan setelahnya. Command tetap didaftarkan sebelum storage diinisialisasi sehingga error storage mendapat pesan penjelasan. Hook command mendukung format engine tanpa slash dan format dengan slash. Tidak mengganti script verify/command lain.

Jika log server menunjuk `lua/verifycsn-1.lua`, ganti isi file yang dimuat tersebut dengan versi terbaru ini, lalu reload. Pastikan log BOOT sudah **v4-remove**. Bila data memakai indeks string/berbasis 0, console juga menampilkan `[verifycsn] STORAGE normalized ... world indices to Lua array`. Tidak perlu menghapus data `verifycsn_worlds_v1` atau mendaftarkan ulang world yang sudah tersimpan.

Tes native Lua: `lua5.1.exe tests/verifycsn-test.lua` dari folder ini. Tes Lua 5.4: jalankan `node tests/run-verifycsn.cjs` dengan Wasmoon tersedia; `VERIFYCSN_TEST_MODULES` dapat menunjuk node_modules temporary.

**631 pemeriksaan lulus** pada Lua 5.1 asli dan Lua 5.4/Wasmoon. Tes memakai mock API GTPS, memeriksa pembatasan Founder, penambahan/pencabutan verifikasi, persistensi/reload, save gagal, normalisasi indeks JSON, siklus save/load dengan serialisasi indeks string/berbasis 0, data rusak, format warna, jumlah player, pagination, welcome, tombol stale/palsu, dan penolakan warp native. Pencabutan juga diuji pada world yang tidak ada di engine, penghapusan record terakhir, penolakan tombol lama, dan verifikasi ulang. Setelah memasang, uji `/addverify`, `/removeverify`, `/verifycsn`, pindah ke world terdaftar, serta restart di server aktual.

Referensi teknis: [dump item asli: Roulette Wheel 758](https://github.com/zephilion/growtopia-item-id/blob/main/click-here), [markup dialog dan flag bigBlueButton pada implementasi server](https://github.com/NetroIndonesia/Growtopia/blob/main/docs/09-dialog-system.md). API Lua memakai dokumentasi engine lokal `docslua...txt`.
