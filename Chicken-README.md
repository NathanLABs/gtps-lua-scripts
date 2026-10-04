# Chicken Reward

`Chicken.lua` mengganti hasil telur dari **Chicken, Item ID 872**, dengan lock yang dipilih. Pengaturan berlaku untuk seluruh Chicken di server.

Bisa dipakai bersama `cow.lua`. Menu `/setchicken`, database `chicken_v1.db`, dan pengaturan Chicken terpisah dari `/setcow` serta database Cow.

## Cara pakai

1. Upload **`Chicken.lua` saja** ke Lua Scripts, lalu reload server.
2. Buka **`/setchicken`** sebagai **Owner server, role 999**, atau **Founder, role 1000**.
3. Tekan gambar lock, isi **Amount**, lalu **Save Reward**.

Contoh: pilih **BGL**, isi **1**, lalu Save. Setiap pengambilan hasil Chicken menjadi **1 BGL** yang jatuh di posisi Chicken; telur bawaan dibatalkan. Reward tidak dikirim langsung ke inventory dan tidak dikalikan jumlah telur ataupun bonus MAG.

Pilihan bawaan:

| Lock | Item ID |
| --- | ---: |
| World Lock | 242 |
| Diamond Lock | 1796 |
| Blue Gem Lock | 7188 |
| Golden Gem Lock | 8470 |

Gambar hanya ditampilkan jika item tersedia di engine. Tambahkan lock lain lewat **Custom Lock ItemID** → **Tambah Custom Lock**. Script memvalidasi keberadaan item; Owner/Founder menentukan bahwa ID tersebut benar-benar lock. Engine tidak menyediakan daftar seluruh custom lock, sehingga ID tambahan dimasukkan secara eksplisit.

Amount berupa angka bulat **1–2.000.000.000**, tanpa titik atau koma. Maksimal 100 pilihan lock. Memilih gambar atau menambah custom lock belum mengubah hasil Chicken; pengaturan aktif setelah **Save Reward**. Tombol **Gunakan Telur Bawaan** mengembalikan hasil normal. Saat pertama dipasang, hasil tetap telur sampai pengaturan pertama disimpan.

## Penyimpanan dan proteksi

Pengaturan, pilihan custom lock, log perubahan, serta jurnal payout tersimpan di **`chicken_v1.db`**, pada folder database server. Reload tidak mengembalikan pengaturan awal. Simpan file database ini saat memindahkan atau mencadangkan server.

Menu memeriksa role pada setiap aksi. Sesi menu terikat akun, kedaluwarsa setelah 120 detik, dan tidak dapat dipakai ulang. Form lama tidak menimpa pengaturan yang sudah diubah admin lain.

Sebelum reward dijatuhkan, script menyimpan jurnal siklus Chicken dengan Item ID dan Amount yang berlaku saat itu. Perubahan setting selama pengiriman tidak mengubah reward yang sudah dijurnal. Payout selesai hanya jika API spawn mengembalikan `true` dan kenaikan total ground drop sesuai jumlah reward. Hasil gagal atau tidak pasti tetap dianggap sudah ditangani: tidak dicoba ulang dan tidak dilanjutkan menjadi telur.

Log **`[chicken] NEEDS REVIEW`** atau **`[chicken] PAYOUT ERROR`** perlu diperiksa admin. Status `pending` berarti hasil belum pasti; jangan memberi ulang otomatis. Jurnal yang sudah tercatat juga tetap menahan payout siklus yang sama setelah reload atau setelah pengaturan dikembalikan ke telur.

## Batas integrasi engine

Penggantian memakai callback live **`onProviderDropCallback`**, sebelum hasil provider masuk ke bonus MAG dan ground drop. Ini menangani **pengambilan hasil telur/provider Chicken**. Callback penghancuran blok tidak dapat membatalkan drop bawaan; script tidak menambahkan reward kedua dari penghancuran Chicken.

Penanda siklus menggunakan **nama world + posisi Chicken + timestamp `tile:getTileData(1)`**. Engine harus memberikan timestamp berupa angka bulat nol atau positif, tetap sama pada semua callback item dalam satu siklus, dan berbeda untuk siklus berikutnya. Nilai nol dapat menandai siklus awal. Dokumentasi engine tidak menjamin urutan pembaruan timestamp tersebut dan tidak menyediakan ID payout khusus. Jika timestamp tidak tersedia atau tidak valid ketika penggantian aktif, script membatalkan telur dan mencatat error tanpa mengirim lock. Perilaku ini perlu diverifikasi pada Chicken di server asli.

SQLite dan ground drop tidak berada dalam satu transaksi engine. Jika server berhenti setelah jurnal disimpan tetapi sebelum spawn, jurnal dapat tetap `pending` meskipun lock belum jatuh. Proteksi ini menghindari pengiriman ganda; tidak dapat menjamin pengiriman tepat sekali saat server crash. Pemasangan ulang Chicken pada koordinat yang sama dengan timestamp yang identik juga akan dianggap siklus yang sama.

Pemeriksaan lokal memakai Lua 5.1/Lua 5.4, SQLite asli, serta simulasi API GTPS. Pemeriksaan tersebut tidak menggantikan verifikasi callback Chicken, timestamp siklus, dan tampilan dialog pada client/server asli. Setelah reload, cari **`[chicken] BOOT v1-chicken-lock`**, **`provider=true`**, dan **`[chicken] Loaded /setchicken`** di console.
