# kitpass.lua

Satu KitPass dengan tiga level dan dua jalur reward: **Basic** untuk semua pemain dan **Premium** yang diberikan Founder. Level didapat dari XP misi harian/mingguan, bukan level akun Growtopia atau pergantian hari otomatis. Tidak ada pembelian Premium oleh pemain.

## Command

- `/kitpass`: menu **Basic Rewards**, **Premium Rewards**, **Daily & Weekly Missions**, **Preview All Rewards**, **Refresh**, dan **How to Play**.
- `/setkitpass`: Founder role **1000**, dengan **Set Duration**, **Set Reward**, **Set Premium Reward**, dan **Set Mission**.
- `/givepremiumkit GROWID`: Founder memberikan Premium untuk musim KitPass yang sedang aktif. Target **harus online**, sesuai API engine `getPlayerByName`. Identitas disimpan berdasarkan UID akun. Pemberian berulang pada musim sama tidak mengulang grant.

## Dialog pemain

Latar abu gelap, teks utama putih, aksen biru muda untuk Basic dan emas untuk Premium. Warna hijau hanya menandai reward/misi selesai; warna merah menandai klaim pending. Semua halaman memakai palet yang sama.

Menu utama menampilkan status musim, sisa hari/jam/menit, tanggal berakhir **WIB**, level, progress bar XP, XP menuju level berikutnya, akses Premium, dan jumlah reward siap klaim. Pada level maksimum, XP yang melebihi batas tetap tercatat sebagai total XP musim.

Halaman Basic/Premium menampilkan tiga reward dengan ikon item server, jumlah, kebutuhan XP, dan status **terkunci / siap diklaim / sudah diklaim / pending**. Preview menampilkan kedua track tanpa mengirim item. Reward yang sudah diklaim menampilkan item/jumlah dari bukti klaim, termasuk apabila Founder kemudian mengganti konfigurasi reward.

Misi menampilkan progress angka dan persen, progress bar, hadiah XP, status penyelesaian, serta hitung mundur reset harian/mingguan. Level baru memunculkan notifikasi setelah XP misi diterima. **How to Play** menjelaskan level, akses Premium, klaim, dan aturan musim.

Progress bar memakai elemen dialog native `add_progress_bar` yang didokumentasikan pada [dialog syntax](https://github.com/nperma/Growsoft-Luascript-Documentation/blob/main/docs/dialog-syntax.md). Angka progress juga ditampilkan sebagai teks terpisah agar informasi tetap terbaca bila versi client tidak merender bar.

**Claim All** muncul ketika sedikitnya dua reward siap diambil. Menu utama mengumpulkan Basic dan Premium yang berhak diterima; tombol pada halaman track hanya mengambil reward track tersebut. Halaman konfirmasi menampilkan daftar item sebelum pengiriman. Premium tetap memerlukan grant Founder dan level yang sesuai.

## Pengaturan sederhana

**Set Reward** dan **Set Premium Reward** masing-masing berisi langsung:

```text
Level 1
ItemID :
Amount :

Level 2
ItemID :
Amount :

Level 3
ItemID :
Amount :
```

Setiap level mendukung satu jenis item. `ItemID 0` dan `Amount 0` mengosongkan reward; nilai lainnya harus merupakan item server yang valid dengan jumlah positif. Semua input divalidasi sebelum perubahan disimpan. Basic/Premium menyimpan reward terpisah. Perubahan reward tidak membuat level yang sudah diklaim bisa diklaim ulang.

**Set Duration** menggunakan hari, 1–365, hanya Founder. Belum ada musim aktif sebelum Founder memulai. Menyimpan durasi sebelum musim pertama atau setelah musim berakhir membuka konfirmasi **Start KitPass**. Saat musim aktif, pengubahan durasi menghitung akhir dari timestamp awal yang sama dan mempertahankan XP, klaim, serta Premium; durasi yang menghasilkan waktu akhir sudah lewat ditolak. Durasi 1 hari berarti 24 jam sejak dimulai, bukan sampai tengah malam.

Musim berakhir berdasarkan timestamp tanpa perlu timer. Klaim dan progress misi berhenti saat durasi habis. Memulai musim berikutnya memberikan progress XP dan status Premium baru; konfigurasi reward/misi tetap digunakan. Premium perlu diberikan kembali tiap musim. Riwayat musim lama tetap disimpan.

## Misi dan XP

Default, dapat disesuaikan lewat **Set Mission**:

| Misi | Target | Hadiah |
| --- | --- | --- |
| Harian | Pecahkan 100 foreground block | 100 XP |
| Mingguan | Panen 500 pohon | 300 XP |

Default **100 XP per level**: Level 1 pada 100 XP, Level 2 pada 200 XP, Level 3 pada 300 XP. Level awal **0**. Basic dan Premium memakai XP/level yang sama. Misi lengkap memberi XP otomatis, tanpa tombol klaim misi. Menekan tombol reward level tetap diperlukan untuk menerima item.

Founder dapat memilih action `break` atau `harvest`, target, dan Reward XP untuk masing-masing misi. `break` menghitung satu foreground block pada callback break engine; background tidak dihitung. `harvest` menghitung satu pohon per callback, bukan jumlah buah. Remote/MAG planting tidak dihitung sebagai panen. Tindakan offline/NPC atau setelah musim berakhir diabaikan.

Harian reset **00.00 WIB**, mingguan **Senin 00.00 WIB**. Reset dihitung dari waktu Unix dengan UTC+7, tidak bergantung zona waktu mesin. Progress periode berikutnya muncul saat menu/aktivitas pertama; tidak ada timer besar untuk mereset semua player. Reset misi tidak menghapus XP musim, status Premium, atau klaim.

Misi pemain yang sudah dibuat menyimpan snapshot action, target, dan XP. Pengubahan aturan oleh Founder berlaku bagi misi yang belum dibuat/periode berikutnya; progress yang sudah berjalan tetap memakai aturan lama. XP per Level hanya dapat diubah sebelum musim aktif atau setelah selesai, agar level tidak berubah di tengah musim.

Progress dan reward XP penyelesaian disimpan bersama dalam transaksi SQLite. Satu misi hanya memberi XP sekali dalam periodenya. Mundurnya jam atau reload tidak membuka ulang periode yang sudah selesai. Engine tidak memberi ID event unik untuk callback; script bergantung pada engine mengirim callback break/harvest yang benar.

## Penyimpanan dan klaim

SQLite: **kitpass_v1.db** di folder server. Simpan dan cadangkan database beserta berkas WAL saat server masih berjalan, atau cadangkan setelah server berhenti. Tabel `kp_config`, `kp_seasons`, `kp_rewards`, `kp_members`, `kp_progress`, `kp_mission_rules`, `kp_missions`, `kp_claims`, dan `kp_log` menyimpan konfigurasi, XP, izin Premium, periode misi, serta klaim. Data default hanya dimasukkan jika belum ada; restart tidak mengembalikan konfigurasi ke default.

Klaim memakai kunci unik `(musim, UID, Basic/Premium, level)` dan jurnal sebelum pemberian item. Script menggunakan `giveItem` serta memeriksa kenaikan inventory + Extra Backpack secara tepat. Inventory biasa penuh dapat memakai overflow Extra Backpack. Jumlah total satu item sesudah klaim dibatasi 2.000.000.000.

Claim All memeriksa gabungan jumlah item sebelum mengirim reward pertama. Setiap reward kemudian menggunakan jurnal klaim yang sama dengan klaim satuan. Apabila salah satu pemberian gagal, pengiriman berikutnya dihentikan; reward yang sudah berhasil tetap tercatat. Konfirmasi lama setelah pengubahan pengaturan/musim ditolak. Claim All bukan satu transaksi inventory atomik.

Jika engine menolak klaim tanpa perubahan inventory, jurnal diberi status `cancelled` sehingga dapat dicoba kembali. Pemberian parsial, exception engine, atau kegagalan finalisasi SQL meninggalkan status **pending** dan tidak dikirim ulang. Pending milik UID tersebut menahan klaim selanjutnya, termasuk setelah reload; Founder perlu memeriksa `kp_claims`, `kp_log`, dan inventory engine sebelum rekonsiliasi. Jangan mengganti status pending tanpa pemeriksaan item yang sudah diberikan.

SQLite dan save inventory engine tidak berbagi transaksi atomik. Script tidak menjamin atomisitas item/database saat proses server crash. Backup dan pemeriksaan jurnal diperlukan untuk kegagalan tersebut. Tidak ada tombol rekonsiliasi otomatis yang menganggap item pasti belum diberikan.

## Pemasangan dan verifikasi

Upload **kitpass.lua** ke folder Lua aktif dan reload/restart script. Console:

```text
[kitpass] BOOT v2-pass-ui | Lua ...
[kitpass] ROUTES registered=true command=true dialog=true
[kitpass] Loaded /kitpass /setkitpass /givepremiumkit
```

Jika `INIT FAILED`, lihat alasannya. Hook command dan deklarasi command dipasang sebelum SQLite diinisialisasi supaya error mendapat pesan, bukan hilang menjadi unknown command.

Atur reward dan misi melalui `/setkitpass`, lalu **Set Duration** → **Start KitPass**. Berikan Premium melalui `/givepremiumkit GROWID` ketika target online.

**1.006 pemeriksaan lulus** pada Lua 5.1 asli dan Lua 5.4/Wasmoon, masing-masing dengan SQLite asli dan mock API GTPS. Pengujian mencakup navigasi, progress XP/reset WIB, snapshot reward, klaim satuan/bulk, izin Premium, replay, batas inventory, serta kegagalan engine/database. Rendering dialog belum diuji di client GTPS langsung. Runner Node 22+:

```powershell
$env:KITPASS_LUA51 = 'PATH/TO/lua5.1.exe'
node tests/run-kitpass.cjs
```

Untuk Lua 5.4, hapus variabel `KITPASS_LUA51` lalu jalankan runner dengan Wasmoon tersedia; `KITPASS_TEST_MODULES` dapat menunjuk folder node_modules temporary. Jalankan kompilasi Lua 5.1 asli pada `kitpass.lua` karena parser saja tidak memeriksa batas upvalue interpreter.
