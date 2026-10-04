# Cow Reward

`cow.lua` mengganti hasil susu dari **Cow, Item ID 866**, dengan lock yang dipilih. Pengaturan berlaku untuk seluruh Cow di server.

## Cara pakai

1. Upload **`cow.lua` saja** ke Lua Scripts, lalu reload server.
2. Buka **`/setcow`** sebagai **Owner server, role 999**, atau **Founder, role 1000**.
3. Tekan gambar lock, isi **Amount**, lalu **Save Reward**.

Contoh: pilih **BGL**, isi **1**, lalu Save. Setiap pengambilan hasil Cow menjadi **1 BGL** yang jatuh di posisi Cow; susu bawaan dibatalkan. Reward tidak dikirim langsung ke inventory dan tidak dikalikan jumlah susu ataupun bonus MAG.

Pilihan bawaan:

| Lock | Item ID |
| --- | ---: |
| World Lock | 242 |
| Diamond Lock | 1796 |
| Blue Gem Lock | 7188 |
| Golden Gem Lock | 8470 |

Gambar hanya ditampilkan jika item tersedia di engine. Tambahkan lock lain lewat **Custom Lock ItemID** → **Tambah Custom Lock**. Script memvalidasi keberadaan item; Owner/Founder menentukan bahwa ID tersebut benar-benar lock. Engine tidak menyediakan daftar seluruh custom lock, sehingga ID tambahan dimasukkan secara eksplisit.

Amount berupa angka bulat **1–2.000.000.000**, tanpa titik atau koma. Maksimal 100 pilihan lock. Memilih gambar atau menambah custom lock belum mengubah hasil Cow; pengaturan aktif setelah **Save Reward**. Tombol **Gunakan Susu Bawaan** mengembalikan hasil normal. Saat pertama dipasang, hasil tetap susu sampai pengaturan pertama disimpan.

## Penyimpanan dan proteksi

Pengaturan, pilihan custom lock, log perubahan, serta jurnal payout tersimpan di **`cow_v1.db`**, pada folder database server. Reload tidak mengembalikan pengaturan awal. Simpan file database ini saat memindahkan atau mencadangkan server.

Menu memeriksa role pada setiap aksi. Sesi menu terikat akun, kedaluwarsa setelah 120 detik, dan tidak dapat dipakai ulang. Form lama tidak menimpa pengaturan yang sudah diubah admin lain.

Sebelum reward dijatuhkan, script menyimpan jurnal siklus Cow dengan Item ID dan Amount yang berlaku saat itu. Perubahan setting selama pengiriman tidak mengubah reward yang sudah dijurnal. Payout selesai hanya jika API spawn mengembalikan `true` dan kenaikan total ground drop sesuai jumlah reward. Hasil gagal atau tidak pasti tetap dianggap sudah ditangani: tidak dicoba ulang dan tidak dilanjutkan menjadi susu.

Log **`[cow] NEEDS REVIEW`** atau **`[cow] PAYOUT ERROR`** perlu diperiksa admin. Status `pending` berarti hasil belum pasti; jangan memberi ulang otomatis. Jurnal yang sudah tercatat juga tetap menahan payout siklus yang sama setelah reload atau setelah pengaturan dikembalikan ke susu.

## Batas integrasi engine

Penggantian memakai callback live **`onProviderDropCallback`**, sebelum hasil provider masuk ke bonus MAG dan ground drop. Ini menangani **pengambilan hasil susu/provider Cow**. Callback penghancuran blok tidak dapat membatalkan drop bawaan; script tidak menambahkan reward kedua dari penghancuran Cow.

Penanda siklus menggunakan **nama world + posisi Cow + timestamp `tile:getTileData(1)`**. Engine harus memberikan timestamp berupa angka bulat nol atau positif, tetap sama pada semua callback item dalam satu siklus, dan berbeda untuk siklus berikutnya. Nilai nol dapat menandai siklus awal. Dokumentasi engine tidak menjamin urutan pembaruan timestamp tersebut dan tidak menyediakan ID payout khusus. Jika timestamp tidak tersedia atau tidak valid ketika penggantian aktif, script membatalkan susu dan mencatat error tanpa mengirim lock. Perilaku ini perlu diverifikasi pada Cow di server asli.

SQLite dan ground drop tidak berada dalam satu transaksi engine. Jika server berhenti setelah jurnal disimpan tetapi sebelum spawn, jurnal dapat tetap `pending` meskipun lock belum jatuh. Proteksi ini menghindari pengiriman ganda; tidak dapat menjamin pengiriman tepat sekali saat server crash. Pemasangan ulang Cow pada koordinat yang sama dengan timestamp yang identik juga akan dianggap siklus yang sama.

Pemeriksaan lokal memakai Lua 5.1/Lua 5.4, SQLite asli, serta simulasi API GTPS. Pemeriksaan tersebut tidak menggantikan verifikasi callback Cow, timestamp siklus, dan tampilan dialog pada client/server asli. Setelah reload, cari **`[cow] BOOT v1-cow-lock`**, **`provider=true`**, dan **`[cow] Loaded /setcow`** di console.
