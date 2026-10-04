# Item Rental — rent.lua

**Status: menu, database, saldo, storage, dan alur rental sudah dibuat. Peminjaman item belum dapat diaktifkan pada engine yang sekarang tanpa tambahan backend rental native.** Dokumentasi `docslua...txt` menyediakan perubahan inventory biasa, tetapi tidak menyediakan temporary ownership yang tidak dapat dipindahkan dan bisa dicabut saat pemain offline. File tidak menganggap API tambahan tersebut sudah ada.

## Command dan pemasangan

- Ganti `market.lua` dengan satu salinan `rent.lua`, lalu reload/restart pemuat Lua server. Jangan memuat kedua file bersamaan; callback lama perlu dilepas agar command dan scheduler tidak ganda.
- `/rent`: semua pemain.
- `/setrent`: Founder, **role 1000**. Role 999 tidak diberi akses panel ini. Script ini tidak lagi mendaftarkan `/setmarket`.
- Database: `player_market_v1.db`, dibuat SQLite pada folder server.
- Log pemuatan: `[rent] Loaded /rent + /setrent. Native rental=false`.
- Penanda versi sekarang: `[rent] BOOT r3-founder /rent + /setrent | Lua ...`, lalu `[rent] ROUTES r3-founder /rent=true /setrent=true command=true input=true dialog=true`. Nilai route menunjukkan callback mana yang berhasil dipasang; satu jalur command yang tersedia cukup untuk menangani perintah.
- `Native rental=false` berarti menu dan saldo bisa digunakan, tetapi pembuatan listing baru dan pembayaran rental ditolak sebelum stok ditarik atau penyewa ditagih. Dialog utama menampilkan keterangan tersebut.
- Nama database, tabel, ID transaksi, saldo, harga, dan token native tetap memakai format lama. Jangan mengganti atau menghapus `player_market_v1.db` saat upgrade. Jalankan hanya satu instance script untuk database yang sama.

### Perbaikan pemuatan r2-lua51

File sebelum revisi ini ditolak compiler Lua 5.1 dengan `function at line 717 has more than 60 upvalues`. Penanganan dialog menangkap terlalu banyak fungsi halaman sebagai variabel luar; Lua 5.1 membatasi jumlah tersebut menjadi 60 ([sumber Lua 5.1](https://www.lua.org/source/5.1/luaconf.h.html#LUAI_MAXUPVALUES)). Akibatnya seluruh file gagal dikompilasi sebelum command sempat didaftarkan. Parser sintaks dan pengujian runtime Lua 5.4 sebelumnya tidak mendeteksi batas compiler tersebut.

Referensi navigasi sekarang disatukan dalam satu tabel lokal. File lama sudah diuji gagal pada `luac 5.1.5`, sedangkan file baru lolos compiler yang sama dan menjalankan seluruh tes menggunakan interpreter Lua 5.1.5. Ini membuktikan perbaikan kompatibilitas; versi engine dan pemuatan file di server pengguna tetap perlu diverifikasi lewat penanda BOOT/ROUTES setelah file diganti dan diaktifkan ulang.

Kegagalan SQLite menghasilkan respons `Rental belum tersedia` ketika command dipanggil. Backend rental native yang belum dipasang menghasilkan menu `Penyewaan belum dibuka`. Keduanya berbeda dari command yang sama sekali belum terdaftar.

## Menu pemain

Tampilan mengikuti susunan referensi: panel indigo transparan, judul dengan ikon, teks putih/emas, dan tiga tombol utama berurutan:

1. **KELOLA MY RENT** berwarna hijau.
2. **MY RENT** berwarna biru muda.
3. **Withdraw Currency** berwarna merah muda.

**Item Tersedia Disewa** menampilkan grid ikon sesuai Item ID, nama item, dan jumlah stok. Satu halaman berisi maksimal 18 listing dalam tiga baris, masing-masing enam ikon; pagination muncul ketika diperlukan. Tekan ikon untuk melihat toko, harga, durasi, rating, dan konfirmasi penyewaan. Stok dan harga selalu diperiksa ulang saat pembayaran.

Header memakai Item ID `13812`, dengan fallback ke ikon mata uang jika item itu tidak tersedia. Nilainya dapat diubah melalui `RENT_ICON_ID` di bagian atas script. Dialog memakai elemen native client; ukuran akhir tombol, frame ikon, warna, dan skala font perlu dicek di client GTPS. Tidak ada gambar latar dunia buatan dalam script.

Harga tetap **BGL**, sesuai permintaan awal. Gambar referensi yang menampilkan GGL dipakai sebagai acuan tampilan; data ekonomi lama tidak dikonversi diam-diam.

**Kelola My Rent** menyediakan tombol **+ TAMBAH ITEM BARU UNTUK DISEWAKAN**, lalu tiga bagian: **Stock Yang Kamu Sewakan**, **Item Idle / Menunggu Pengembalian**, serta **Sedang Disewa Orang Lain**. Stok dapat dikelola lewat ikon; bagian penyewa menampilkan nama player dan sisa waktu, dengan halaman lanjutan ketika banyak penyewa. Profil nama/maskot toko dan riwayat tersedia di bawah. Form **List / Tambah Stock Item** berisi:

| Field | Arti |
| --- | --- |
| Item ID | Item yang dititipkan ke rental |
| Harga per unit (BGL) | Harga untuk meminjam satu item selama satu masa sewa; maksimal empat desimal |
| Durasi Sewa (menit) | Waktu peminjaman, bukan masa tayang iklan; 1 sampai 525,600 menit |
| Jumlah Stock | Jumlah item titipan, 1 sampai 200 per listing |
| Otomatis sewakan lagi setelah masa sewa habis | Setelah native engine mengonfirmasi item telah ditarik, stok kembali tersedia untuk disewa |

Harga `0.5` berarti setengah BGL, setara 5,000 WL. Default batas toko 10 listing aktif; batas per akun yang sudah tersimpan dari versi lama tetap dipakai. Satu listing memiliki satu jenis item dan bisa menyediakan beberapa stok; satu transaksi menyewa satu item. Field harga/durasi dapat diedit untuk penyewaan berikutnya tanpa mengubah kontrak yang sudah berjalan.

Kotak relist **dicentang secara default untuk listing baru**, mengikuti referensi. Saat mengedit, checkbox mengikuti pilihan yang tersimpan; listing lama tidak diubah otomatis. Jika tidak dicentang, item masuk storage pengembalian setelah selesai disewa, lalu dikirim otomatis ke inventory pemilik saat login, membuka `/rent`, atau paling lambat sekitar 30 detik ketika sedang online. Inventory penuh menggunakan Extra Backpack. Pemilik offline tidak diubah secara langsung; item menunggu di SQLite. Bagian Item Idle menampilkan item yang masih menunggu pengiriman, dengan tombol ambil manual. Ini mempertahankan permintaan awal bahwa auto-relist OFF mengembalikan item ke inventory, bukan menyimpan item idle tanpa batas.

Tekan ikon stok milik sendiri untuk **Tambah Stock**, **Ambil Stock**, mengubah harga/durasi/auto-relist, atau menutup listing. Penambahan memakai harga listing yang sama dan tetap membatasi gabungan stok tersedia + sedang disewa sampai 200. Pengambilan sebagian tidak menutup listing. Jika seluruh stok diambil dan tidak ada penyewa aktif, slot listing dilepas. Item yang sedang disewa tidak dapat ditarik sebelum kontraknya selesai.

Menutup listing mengembalikan stok yang belum disewa. Penyewaan aktif tetap berjalan hingga selesai. Item dari listing yang sudah ditutup tidak dipasang ulang meskipun checkbox relist sebelumnya aktif.

**Withdraw Currency** membuka halaman **Ambil [nama item mata uang]**, menampilkan saldo dan form penarikan. Jika saldo nol, hanya pesan **Saldo kamu kosong** dan tombol navigasi yang ditampilkan. Deposit dipisah ke halaman **Isi Saldo Rental**, yang dapat dibuka dari sini atau dari detail item saat saldo kurang. Pemain dapat deposit WL/DL/BGL dari inventory biasa untuk membayar sewa. Ledger memakai satuan WL dengan rasio tetap:

- 100 WL = 1 DL.
- 100 DL = 1 BGL.
- Penarikan 10,101 WL menjadi 1 BGL + 1 DL + 1 WL.
- Angka dikelompokkan dengan koma, misalnya `1,000,000`.
- Saldo dan batas gabungan saldo + reservasi adalah 2,000,000,000 WL per akun.

**My Rent** menampilkan item yang sedang disewa, waktu tersisa, dan proses pemberian yang tertunda. Sewa selesai/refund dipisahkan ke **Riwayat Sewa & Review**, sehingga halaman utama My Rent tidak penuh oleh riwayat lama. Review 1–5 bintang dan komentar tersedia hanya bagi penyewa setelah rental miliknya selesai, sekali per transaksi. Nama toko, maskot, dan rating terlihat pada detail toko/item.

## Founder

`/setrent` khusus role **1000** sekarang hanya berisi dua tombol:

1. **Blacklist Item**: masukkan Item ID yang dilarang dijual/disewakan. Daftar blacklist menyediakan tombol hapus per item. Listing yang diblacklist disembunyikan dari katalog; stok tetap milik penjual dan bisa ditarik. Sewa yang sudah berjalan tetap diselesaikan sesuai kontraknya.
2. **Add Balance Player**: form dengan tepat dua input:

```text
GROWID :
BALANCE ( BGL ) :
```

Jumlah BGL **ditambahkan** ke saldo rental yang sudah ada, bukan menggantikan saldo dan bukan mengirim lock langsung ke inventory. Saldo bisa dipakai menyewa atau ditarik melalui Withdraw Currency. Ini pemberian saldo oleh Founder, tanpa mendebit inventory atau saldo Founder.

GrowID dicari melalui `getPlayerByName`, API engine yang hanya menemukan pemain **online**. Huruf besar/kecil tidak dibedakan. Player online yang belum pernah membuka /rent otomatis dibuatkan akun rental. Target offline/tidak ditemukan ditolak; script tidak menebak penerima dari nama tampilan yang tersimpan di SQLite.

Contoh: `10` menambah 10 BGL; `0.5` menambah 5,000 WL; `1,000.25` menambah 1,000 BGL + 25 DL. Maksimal empat desimal dan hanya angka positif. Total saldo + reservasi rental tidak boleh melewati 2,000,000,000 WL. Akun dengan perpindahan inventory pending perlu diselesaikan dahulu. Tombol yang dikirim ulang dari dialog yang sama tidak menggandakan saldo.

Kredit dan log `admin_balance_added` ditulis dalam satu transaksi SQLite, mencatat Founder, ID penerima, GrowID yang diinput, jumlah, dan saldo akhir. Kegagalan log membatalkan kredit. Riwayat penambahan terlihat pada Riwayat Transaksi milik penerima dan Founder yang melakukan penambahan.

Menu pengaturan mata uang/pajak/slot, manajemen listing, log admin, jurnal pending, dan pengambilan pajak sudah dihapus dari panel serta routing tombol. Konfigurasi ekonomi, saldo pajak, database, dan kontrak yang sudah ada tetap dipertahankan. Default instalasi baru tetap WL 242, DL 1796, BGL 7188, pajak 0%, dan 10 slot.

Item No-/Buy, untradeable/untradable, dan mata uang rental tetap ditolak sebagai barang rental walaupun tidak ada dalam blacklist Founder. Pemeriksaan blacklist diulang sebelum pembayaran; perubahan blacklist membatalkan konfirmasi lama. Penambahan stok juga memeriksa blacklist sebelum mengambil item.

## Backend rental native yang masih diperlukan

Ini adalah **kontrak integrasi baru**, bukan daftar fungsi bawaan GTPS yang sudah tersedia. Pengembang engine perlu menyediakan implementasi, kemudian menghubungkannya melalui `RENTAL_BACKEND` di bagian atas `rent.lua`.

| Anggota backend | Kontrak wajib |
| --- | --- |
| `version = 1` | Versi kontrak integrasi |
| `offlineExpiry = true` | Engine sendiri menegakkan masa berlaku ketika offline/restart, bahkan jika script market tidak berjalan |
| `nonTransferable = true` | Item pinjaman tidak dapat dipindahkan, dijual, di-drop, di-trash, dikonsumsi, ditempatkan, dijadikan bahan, masuk vending/storage/bank, atau diambil oleh script lain |
| `supports(itemID)` | `true` hanya untuk jenis item yang bisa digunakan sementara dan ditarik tanpa merusak item milik pribadi |
| `grant(token, userID, itemID, count, expiresAt)` | Memberikan hak pakai sementara yang persisten; token yang sama tidak boleh pernah memberikan dua item atau memperpanjang durasi |
| `status(token)` | Mengembalikan receipt persisten: `absent`, `active`, `expired`, atau `rejected` |
| `revoke(token)` | Menghapus hak pakai sementara dan melepas efek/equipment yang berasal dari pinjaman itu; aman dipanggil berulang |

Kontrak receipt:

- `absent`: belum pernah memberikan item untuk token tersebut. Tidak boleh dikembalikan hanya karena penyewa offline atau cache hilang.
- `active`: pemberian item sudah persisten dan sesuai user/item/jumlah/deadline yang disimpan.
- `expired`: item **pernah diberikan**, kemudian hak pakai/item/efeknya telah dicabut secara persisten. Tidak ada salinan yang masih dapat digunakan.
- `rejected`: pemberian ditolak secara final dan **tidak pernah** memberi item. Receipt harus tetap tersedia saat restart.
- Kegagalan/hasil yang tidak pasti harus melempar error atau memberi status lain; script akan menahan pembayaran/stok. Jangan mengubah hasil tidak pasti menjadi `absent` atau `expired`.

Receipt token harus disimpan lama, konsisten dengan database market. Pemberian dan receipt harus atomik pada engine. Engine harus menolak token yang digunakan lagi dengan parameter berbeda, menjaga item pinjaman terpisah dari aset milik pribadi, dan tidak memasukkannya ke saldo item yang dapat didebit API inventory biasa. Penggunaan clothing/effect harus ikut berakhir; mencabut sejumlah item biasa dengan ID yang sama bukan pengganti identitas item pinjaman.

Script memeriksa status receipt sebelum mencoba pemberian, setelah pemberian, dan ketika durasi habis. Polling maksimal 20 record per putaran lima detik; listing mungkin baru ready pada putaran berikutnya. Polling Lua **bukan** mekanisme utama pencabutan hak pakai: expiry harus ditegakkan engine. Jika salah satu operasi gagal, stok tidak digandakan untuk membuat replacement.

Contoh alur integrasi tanpa mengarang API engine:

1. Pengembang engine mengimplementasikan temporary inventory/ownership beserta receipt token dan batas penggunaan.
2. Bungkus API tersebut dalam tabel sesuai kontrak di atas, lalu isi `RENTAL_BACKEND` dengan tabel itu. Jangan hanya mengubah flag menjadi `true`.
3. Uji pemain online/offline, reconnect, restart, seluruh jalur transfer termasuk Lua, expiry saat server mati, serta duplikat request dengan token sama.
4. Aktifkan rental setelah pengujian engine selesai. File test lokal memakai simulator backend, bukan implementasi engine tersebut.

## Konsistensi, kegagalan, dan backup

Reservasi stok, debit saldo penyewa, reservasi ruang saldo, pendapatan penjual, pajak, review, dan pengembalian stok menggunakan transaksi SQLite. Selama hasil native belum pasti, uang serta stok ditahan. Native `rejected`, atau `absent` setelah deadline tanpa pernah memberi item, mengembalikan saldo penyewa. Grant yang terbukti berhasil dibayar satu kali walaupun acknowledgment hilang atau finalisasi SQL sempat gagal.

Deposit/withdraw inventory menggunakan jurnal intent persisten sebelum memanggil engine. Hasil API dan delta inventory + Extra Backpack diperiksa. Jika hasil ambigu, akun ditahan dari perpindahan item/saldo berikutnya. Jangan menghapus jurnal atau mengulang pemberian untuk menghilangkan status pending. Snapshot sebelum/sesudah tetap tersimpan di tabel market_move_legs; rekonsiliasi perlu mencocokkan data player, log engine, dan backup. Panel sederhana tidak menyediakan tombol rekonsiliasi.

API yang tersedia tidak memberikan satu transaksi atomik bersama inventory/save player. Crash antara perubahan inventory dan penyimpanan player tetap memerlukan rekonsiliasi. Implementasi ini tidak menjanjikan pemulihan otomatis semua crash inventory. Tidak ada tombol pemulihan yang menerbitkan item atau saldo berdasarkan perkiraan.

Backup SQLite secara konsisten beserta data player, database/receipt backend native, dan WAL sesuai mekanisme backup server. Jangan reset database market ketika masih ada rental native: token lama harus tetap mengacu ke rental yang sama. Penonaktifan script tidak boleh menonaktifkan expiry native.

## Pengujian

```powershell
$env:RENT_TEST_MODULES = 'C:\path\to\node_modules'
node tests/run-rent.cjs
```

Dependency: Node 22+ dengan `node:sqlite`, serta `wasmoon`. Tes menggunakan SQLite sungguhan, runtime Lua 5.4, mock API engine, dan **simulator** backend rental. Jangan upload folder `tests` sebagai script server.

Untuk menjalankan tes pada interpreter Lua 5.1 asli (tidak membutuhkan Wasmoon):

```powershell
$env:RENT_LUA51 = 'C:\path\to\lua5.1.exe'
node tests/run-rent.cjs
```

Untuk memeriksa batas compiler, selain grammar parser:

```powershell
$env:LUA_PARSER_MODULES = 'C:\path\to\node_modules'
$env:LUA51_COMPILER = 'C:\path\to\luac5.1.exe'
node tests/check-lua-syntax.cjs
```

812 pemeriksaan lokal meliputi command/role, menu, parsing angka, konversi, deposit/withdraw, escrow, seller offline, expiry offline, pengiriman saat login, auto relist, pembatalan listing aktif, satu stok diperebutkan dua pembeli, replay, receipt hilang sementara, refund, rollback SQL, review, blacklist, item yang sedang dikenakan, batas 10 slot, profil/maskot, pagination, pajak, serta persistensi setelah reload. Cek UI mencakup lima halaman referensi, form deposit terpisah, ikon sesuai item/stok, whitelist tombol ikon, grid 18 item, navigasi Back/Close, daftar penyewa, serta pemisahan rental aktif dan riwayat. Tambah/tarik stok diuji terhadap replay, form lama, item dipakai, stok pinjaman, batas stok, kegagalan SQL, dan pengembalian dari storage. Setiap dialog diuji di bawah batas 4,096 byte, termasuk halaman pengelolaan yang berisi stok, item kembali, dan penyewa sekaligus. Sintaks juga diperiksa sebagai Lua 5.1/5.2/5.3. Tampilan client dan integrasi native belum diuji pada server GTPS.

Pengujian juga mencakup jalur command generik ketika register command gagal, callback langsung ketika hook generik tidak tersedia, fallback input, pemeriksaan role pada jalur langsung, serta command yang tetap memberi respons saat SQLite gagal. Sebanyak 812 pemeriksaan lulus pada Lua 5.1.5 dan Lua 5.4 dengan SQLite sungguhan; API GTPS dan backend rental tetap disimulasikan.

Revisi r3 menguji panel dua tombol, GrowID online tanpa akun rental sebelumnya, pencarian yang tidak memakai nickname, kredit BGL bulat/pecahan/pemisah ribuan, sifat penambahan saldo, duplikasi callback, batas saldo dan reservasi, role yang dicabut, rollback kredit saat log gagal, target offline/tidak ditemukan, input tidak valid, blacklist katalog, pengambilan stok terlarang, serta penolakan semua tombol admin lama.
