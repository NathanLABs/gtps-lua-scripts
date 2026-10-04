# Gems dan BGL

Upload **gemstobgl.lua** ke **Lua Scripts** server GTPS, lalu reload. Hanya file tersebut yang perlu diupload; database dibuat otomatis.

1. Player mengetik **/sell2**.
2. Menu awal adalah **Gems ke BGL**. Untuk konversi balik, tekan **Ganti: BGL ke Gems**. Tombol yang sama bisa mengganti arah kembali.
3. Isi jumlah **BGL** yang ingin diterima/ditukar, atau pilih **Tukar Maksimal**.
4. Periksa biaya/hasil dan saldo gems setelah penukaran, lalu tekan **Tukar Sekarang**.

Kurs dua arah: **30.000.000 gems = 1 BGL**, tanpa biaya tambahan. Contoh: 2 BGL membutuhkan 60.000.000 gems, dan menukar 2 BGL kembali menghasilkan 60.000.000 gems. Gems diambil dari/masuk ke saldo yang sedang dibawa, bukan gem bank. Lock yang didukung adalah **BGL ID 7188**, sesuai script bank di project ini.

Menu menampilkan saldo, batas penukaran, konfirmasi, dan bukti transaksi. Untuk **Gems ke BGL**, BGL masuk inventory; jika penuh, kelebihannya masuk **Extra Backpack**. Sisa gems tidak ikut ditukar.

Untuk **BGL ke Gems**, BGL diambil dari inventory terlebih dahulu, lalu Extra Backpack jika diperlukan. Jumlah maksimal mengikuti jumlah BGL yang dimiliki dan ruang saldo gems. Saldo akhir tidak boleh melebihi **2.000.000.000 gems**; penukaran ditolak sebelum mengambil BGL jika batas itu terlampaui. Misalnya, saldo 1.970.000.000 gems hanya dapat menerima hasil 1 BGL. Jumlah terbesar per penukaran adalah 66 BGL jika ruang saldo mencukupi.

Input harus angka bulat positif, tanpa pemisah ribuan, pecahan, atau notasi seperti `1e2`. Saldo dicek lagi saat konfirmasi. Menu berlaku 120 detik. Tombol **Refresh Saldo** langsung membuka menu terbaru, termasuk jika sesi lama hilang setelah auto-convert atau reload; tidak perlu mengetik `/sell2` lagi. Arah penukaran dipertahankan selama sesi server masih ada, atau kembali ke menu awal jika sesinya hilang.

Tombol dari menu kedaluwarsa membuka form baru tanpa menjalankan transaksi lama. Player perlu memilih jumlah dan mengonfirmasi kembali. Menutup menu tetap menutupnya. Sesi diikat ke `dialog_name` yang unik; semua tombol memakai field standar dialog dan tidak membutuhkan kiriman `sell2_token` dari `embed_data` client. Klik konfirmasi berulang tetap tidak mengulangi penukaran.

## Auto-convert sebelum limit gems

Aktif otomatis untuk semua player online, tanpa perlu membuka `/sell2`. Saat saldo gems yang dibawa mencapai **1.950.000.000 atau lebih**, semua kelipatan **30.000.000 gems** ditukar menjadi BGL. Sisa yang belum cukup untuk 1 BGL tetap menjadi gems.

| Gems sebelum | BGL diterima | Gems tersisa |
| --- | --- | --- |
| 1.949.999.999 | Belum auto-convert | 1.949.999.999 |
| 1.950.000.000 | 65 | 0 |
| 1.970.000.000 | 65 | 20.000.000 |
| 2.000.000.000 | 66 | 20.000.000 |

Pemeriksaan memakai `onPlayerTick`, sekitar sekali per detik untuk setiap player, termasuk setelah login/reload. BGL masuk inventory atau Extra Backpack jika penuh. Player menerima pesan hasil dan nomor transaksi tanpa dialog baru. Jika ada konfirmasi `/sell2` lama, sesi itu dibatalkan saat auto-convert akan memproses saldo; klik tombolnya akan membuka form dengan saldo terbaru tanpa menjalankan transaksi lama.

Ambang bisa diubah melalui `AUTO_CONVERT_GEMS` di bagian atas script. Default menyisakan jarak 50.000.000 gems dari limit engine. Script hanya menukar saldo aktual yang terbaca; award besar yang melewati cap sebelum pemeriksaan dan gems yang sudah terpotong oleh engine tidak dapat dipulihkan oleh script.

Jika konversi **BGL ke Gems** menghasilkan saldo di atas/sama dengan ambang, hasilnya juga akan otomatis ditukar kembali pada pemeriksaan berikutnya. Dialog konfirmasi menampilkan pemberitahuan ini; gunakan jumlah lebih kecil bila ingin menyimpan gems.

Auto-convert memakai validasi, journal, dan refund yang sama dengan penukaran manual. Kegagalan yang terverifikasi bersih dapat dicoba lagi setelah 30 detik; hasil ambigu tetap `pending` dan tidak diulang otomatis. Akun lain tetap dapat diproses. Tidak ada penundaan tambahan setelah transaksi sukses jika saldo kembali mencapai ambang.

## Catatan untuk admin

Riwayat tersimpan di **gemstobgl_v1.db**, tabel `exchanges`, dengan user ID, arah penukaran, jumlah, nilai gems, saldo sebelum/sesudah, waktu, status, dan catatan. Kolom `direction` berisi `gems_to_bgl` atau `bgl_to_gems`; `amount` selalu jumlah BGL dan `cost` selalu nilai gems yang ditukar (biaya untuk arah pertama, hasil untuk arah kedua). Kolom `automatic` bernilai `1` untuk auto-convert, dan `0` untuk transaksi manual.

Database versi sebelumnya diupgrade otomatis. Kolom arah yang sudah ada dipertahankan; riwayat dari versi pertama diberi arah `gems_to_bgl`. Riwayat lama diberi `automatic=0`, dan transaksi pending tetap ditahan. Jangan hapus database saat reload. Backup SQLite yang konsisten bersama data player; perhatikan file WAL jika server masih berjalan.

- `done`: aset sumber terpotong dan aset tujuan masuk sesuai jumlah/arah penukaran.
- `cancelled`: engine menolak pengambilan aset dan saldo terverifikasi tidak berubah.
- `refunded`: aset yang sudah diambil berhasil dikembalikan, tanpa aset tujuan diberikan. Untuk arah balik, ini juga berlaku jika pengambilan dari Extra Backpack ditolak setelah BGL inventory terambil. Refund BGL dapat masuk inventory atau Extra Backpack.
- `pending`: transaksi belum selesai atau hasil API tidak dapat dipastikan. Penukaran `/sell2` untuk akun tersebut ditahan, termasuk setelah reconnect/reload.

Jika muncul transaksi pending, periksa baris transaksi, log `[gemstobgl]`, gems player, inventory, Extra Backpack, dan backup. Rekonsiliasi dengan akses akun dikendalikan/server dihentikan. Setelah memastikan jumlah aset benar, admin dapat menandai hasil akhir dan mengisi `note`; jangan menghapus pending atau mengulang pengiriman/refund tanpa pemeriksaan.

Journal ditulis sebelum aset dipindahkan. API yang tersedia tidak menyediakan transaksi atomik antara gems, item, dan database, serta tidak menyediakan pemaksaan save player. Karena itu, crash server tetap memerlukan rekonsiliasi; journal bukan jaminan pemulihan otomatis.

## Pengujian lokal

117 pengujian lulus menggunakan Lua 5.4 (Wasmoon), SQLite sungguhan, dan mock API player. Semua kiriman tombol dalam pengujian memakai field standar tanpa custom `embed_data`, termasuk perpindahan arah, lanjut, konfirmasi, maksimal, dan refresh. Cakupan lain: pengambilan BGL dari satu/dua penyimpanan, batas saldo gems, input invalid, inventory penuh, manipulasi dialog, replay, kedaluwarsa, isolasi akun, reconnect/reload, migrasi database lama, kegagalan API/database, dan refund. Auto-convert diuji di sekitar ambang/limit, saat saldo bertambah kembali, bersamaan dengan transaksi manual, saat pending, dan pada kegagalan API/SQL. Pengujian bolak-balik untuk seluruh jumlah 1-66 BGL memastikan gems dan total BGL tetap sama. Tampilan dialog, interval tick, dan perilaku engine tetap perlu dicoba di server GTPS.

Runner: `node tests/run-gemstobgl.cjs [path-ke-package-wasmoon]`, menggunakan Node yang menyediakan `node:sqlite` dan package `wasmoon`. Folder `tests` hanya untuk pengujian lokal, bukan untuk diupload ke Lua Scripts.
