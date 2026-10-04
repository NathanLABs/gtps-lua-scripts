# Recycle Lock Event — recyle.lua

Event kompetisi daur ulang lock dengan leaderboard Top 10, musim persisten, dan kotak klaim hadiah berbasis SQLite.

## Pemasangan

1. Upload **`recyle.lua`** ke folder/panel Lua server, simpan, lalu aktifkan atau reload. Nama file mengikuti permintaan: `recyle.lua`.
2. Muat satu salinan saja. Jangan mengunggah folder `tests` sebagai script server.
3. Log pemuatan versi ini:

```text
[recyle] BOOT v1 | Lua ...
[recyle] ROUTES registered=true command=true input=true dialog=true
[recyle] Loaded /re /topevent /setrecycle /sendrewardrecyclelock /resetleaderboardre
```

Database **`recycle_lock_v1.db`** dibuat di folder database server melalui `sqlite.open`. Harga poin, hadiah, skor, musim, dan klaim tidak kembali ke default saat reload. Backup database beserta data player; jangan menghapusnya ketika ada hadiah yang belum diambil.

Command didaftarkan secara terpisah dari inisialisasi SQLite. Jika database gagal, command yang berhasil terdaftar memberi pesan `Event belum tersedia`; rincian dicetak sebagai `INIT FAILED`. Callback command, callback langsung, dan input fallback dipasang secara independen sesuai API yang tersedia.

## Command

| Command | Akses | Fungsi |
| --- | --- | --- |
| `/re` | Semua player | Pilih lock, hitung poin, konfirmasi recycle, buka leaderboard dan Kotak Klaim |
| `/topevent` | Semua player | Daftar peringkat 1–10 sebagai teks, tanpa tombol per nama |
| `/setrecycle` | Founder, role 1000 | Tambah/edit custom lock, nilai poin, aktif/nonaktif lock, dan hadiah rank 1–10 |
| `/sendrewardrecyclelock` | Founder, role 1000 | Tetapkan pemenang, kirim hadiah ke Kotak Klaim, dan akhiri musim berjalan |
| `/resetleaderboardre` | Founder, role 1000 | Konfirmasi pembukaan musim baru dengan leaderboard kosong |

Role 999 tidak dapat memakai ketiga command Founder. Role diperiksa kembali saat tombol admin ditekan.

## Poin dan recycle

Default yang disetujui memakai nilai setara WL:

| Lock | Item ID | Poin per lock |
| --- | ---: | ---: |
| World Lock | 242 | 1 |
| Diamond Lock | 1796 | 100 |
| Blue Gem Lock | 7188 | 10,000 |
| Golden Gem Lock | 8470 | 1,000,000 |

Default hanya didaftarkan jika Item ID tersedia di server. Untuk custom lock lainnya, buka `/setrecycle` → **Lock & Nilai Poin** → **Tambah Custom Lock**, masukkan Item ID dan poin per unit. Engine tidak menyediakan pembacaan semua denominasi custom beserta nilainya; script tidak menebak harga dari nama item dan tidak mengubah nilai ekonomi lock di fitur lain.

Melalui `/re`, player memilih jenis lock, memasukkan jumlah, lalu menekan **HITUNG POIN**. Konfirmasi menampilkan jumlah lock, sumber, poin yang didapat, dan total poin setelah recycle. **DAUR ULANG** menghapus lock secara permanen dan menambahkan poin setelah debit inventory terverifikasi.

- Jumlah menerima bilangan bulat positif, pemisah ribuan koma (`1,000`), atau `all`/`max`.
- Default mengambil dari inventory. Centang **Ambil dari Extra Backpack** untuk mengambil seluruh transaksi dari Extra Backpack. Kedua sumber tidak dicampur diam-diam.
- Poin = jumlah lock × nilai poin yang tersimpan pada saat konfirmasi. Client tidak menentukan nilai poin.
- Perubahan konfigurasi atau musim membatalkan konfirmasi lama dan membuka menu terbaru. Poin historis tidak dihitung ulang ketika Founder mengedit nilai lock.
- Batas per transaksi 2,000,000,000 item, tetap dibatasi jumlah yang dimiliki. Batas poin per akun per musim adalah 9,000,000,000,000; perkalian diperiksa sebelum dijalankan agar tetap tepat pada Lua 5.1.
- Lock dapat dinonaktifkan tanpa menghapus skor yang sudah didapat.

## Tampilan `/topevent`

```text
#1 GROWID
TOTAL RECYCLE : 1,000,000 poin

#2 GROWID
TOTAL RECYCLE : 850,000 poin
...
#10 GROWID
TOTAL RECYCLE : 10,000 poin
```

Maksimal sepuluh peserta dengan poin positif ditampilkan. Jika baru ada tiga peserta, hanya tiga baris peringkat yang muncul. Tidak ada tombol nama, halaman profil, atau posisi tambahan di leaderboard; hanya tombol penutup dialog bawaan.

`TOTAL RECYCLE` adalah jumlah poin setara WL, sehingga jenis lock yang berbeda bisa dibandingkan. Urutan: poin tertinggi, lalu transaksi paling awal yang mencapai jumlah poin tersebut, kemudian User ID sebagai penentu terakhir. Skor dan kepemilikan hadiah terikat **User ID persisten**, bukan teks nama. Nama yang ditampilkan memakai nama player yang disediakan engine, dibersihkan dari warna dan karakter dialog; jika server mengubah nama tampilan lewat `/nick`, nama tampilan itu dapat ikut tampil. Nama pemenang dan poin dibekukan saat hadiah dikirim.

## Hadiah per rank dan Kotak Klaim

Di `/setrecycle` → **Hadiah Rank 1–10**, pilih rank lalu isi Item ID hadiah dan jumlahnya. Setiap rank mendukung **maksimal lima jenis item**. Menyimpan Item ID yang sama memperbarui jumlah; tombol Hapus menghapus jenis item tersebut. Tidak ada hadiah ekonomi yang ditentukan sembarang pada instalasi awal.

Sebelum menjalankan `/sendrewardrecyclelock`, isi hadiah untuk setiap rank yang memiliki pemenang. Jika hanya tiga peserta, rank 1–3 wajib terisi; rank lainnya boleh disiapkan belakangan. Item hadiah harus tersedia di server.

Pengiriman hadiah dilakukan dalam satu transaksi SQLite:

1. Pastikan tidak ada recycle yang belum jelas hasil debitnya.
2. Ambil dan simpan snapshot Top 10.
3. Buat hadiah milik tiap pemenang di Kotak Klaim, termasuk ketika pemenang offline.
4. Tandai musim selesai; kontribusi baru berhenti sampai musim berikutnya.

Jika satu rank belum memiliki hadiah, item tidak tersedia, atau database gagal, seluruh pengiriman dibatalkan. Menjalankan command lagi setelah berhasil tidak menggandakan hadiah, termasuk setelah restart. Mengedit hadiah setelah pengiriman hanya memengaruhi musim yang belum dibagikan; hadiah yang sudah masuk Kotak Klaim tidak berubah.

**Kotak Klaim adalah menu milik script ini di `/re` → Kotak Klaim**, bukan API mailbox bawaan engine. Hadiah menunggu di SQLite dan tidak langsung dimasukkan ke inventory player offline. Saat login, player mendapat pemberitahuan jika ada hadiah siap diambil.

Player mengambil setiap jenis hadiah lewat tombol **Ambil Hadiah**. Script memeriksa pemilik, status, dan kapasitas, kemudian menggunakan `giveItem`; overflow ke Extra Backpack ditangani engine. Hadiah hanya ditandai sudah diambil setelah jumlah item bertambah tepat sesuai hadiah. Klaim tidak kedaluwarsa ketika leaderboard direset.

## Musim baru

`/resetleaderboardre` menampilkan konfirmasi. Jika musim memiliki peserta, hadiah harus dibagikan dahulu melalui `/sendrewardrecyclelock`. Musim kosong boleh langsung direset. Recycle yang masih pending harus direkonsiliasi terlebih dahulu.

Reset mengarsipkan musim lama dan membuat musim baru dengan poin nol. Skor lama, snapshot pemenang, log, serta hadiah yang belum diklaim tetap disimpan. Pilihan lock dan hadiah tetap berlaku. Tidak ada `DELETE` massal leaderboard atau klaim dalam proses reset.

## Jurnal inventory dan kegagalan

SQLite dan penyimpanan inventory engine bukan satu transaksi atomik. Script menulis intent ke `re_moves` sebelum menghapus lock atau memberi hadiah, lalu membandingkan inventory dan Extra Backpack sebelum/sesudah operasi.

- Penolakan eksplisit engine dengan kedua saldo inventory tetap sama menandai transaksi `cancelled`, sehingga bisa dicoba lagi.
- Perubahan sebagian, hasil tidak sesuai, acknowledgment hilang, atau kegagalan finalisasi database meninggalkan transaksi `pending`. Tidak ada pemberian ulang atau penambahan poin berdasarkan perkiraan.
- Akun dengan transaksi pending diblokir dari recycle/klaim berikutnya. Recycle pending pada musim berjalan juga menahan pengiriman hadiah/reset agar pemenang tidak ditentukan dari skor yang belum selesai.
- Pending klaim dari musim lama tidak menghapus hadiah dan tidak membatalkan musim baru; akun terkait tetap perlu direkonsiliasi sebelum bertransaksi lagi.

Founder perlu mencocokkan `re_moves` (jenis, akun, item, jumlah, poin, snapshot sebelum/sesudah), data player, log engine, dan backup untuk kasus pending. Jangan menandai transaksi selesai atau mengulang `giveItem` tanpa memverifikasi hasil sebenarnya. Jaminan pemulihan otomatis semua crash inventory membutuhkan dukungan transaksi/receipt native dari engine; script ini tidak mengklaim jaminan tersebut.

Tabel utama: `re_config`, `re_players`, `re_seasons`, `re_locks`, `re_rewards`, `re_scores`, `re_awards`, `re_claims`, `re_moves`, dan `re_log`.

## Pengujian

Node 22+ dengan SQLite sungguhan. Untuk memakai interpreter Lua 5.1 asli:

```powershell
$env:RECYCLE_LUA51 = 'C:\path\to\lua5.1.exe'
node tests/run-recyle.cjs
```

Alternatif memakai Wasmoon/Lua 5.4:

```powershell
$env:RECYCLE_TEST_MODULES = 'C:\path\to\node_modules'
node tests/run-recyle.cjs
```

534 pemeriksaan lulus pada Lua 5.1.5 dan Lua 5.4: denominasi default/custom, inventory/Extra Backpack, input salah, poin dan batas angka, replay, rate yang berubah, role, urutan tie, Top 10 tanpa tombol nama, hadiah offline/multi-item, pengiriman satu kali, reload, reset dan arsip, klaim lintas musim, klaim milik akun lain, penolakan native, debit/pemberian sebagian, rollback database, hadiah terkunci saat finalisasi gagal, serta fallback command dan kegagalan inisialisasi. File juga dikompilasi menggunakan compiler Lua 5.1.5, bukan hanya parser grammar.

API inventory dan callback GTPS disimulasikan dalam tes. Tampilan client dan pemasangan di server live belum diuji langsung.
