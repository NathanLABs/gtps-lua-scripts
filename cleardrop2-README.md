# Clear Drop Selektif — cleardrop2.lua

**Developer: Nathan**

`/cleardrop2` membersihkan item yang terjatuh di world melalui preview dan pilihan checkbox. Hanya **owner world** yang dikenali akun native engine dapat menggunakannya. Admin world, access, nickname yang menyerupai owner, atau role staf tanpa kepemilikan world tidak memberikan izin.

## Pemasangan dan penggunaan

1. Upload satu salinan `cleardrop2.lua` ke pemuat Lua server, lalu reload. Log pemuatan: `[cleardrop2] Loaded. /cleardrop2: native owner authorization and one-use drop preview.`
2. Masuk world milikmu dan ketik `/cleardrop2`.
3. Centang jenis item yang ingin dihapus, atau **Pilih Semua Item di Atas**, lalu tekan **Bersihkan Item Terpilih**. **Batal** menutup preview tanpa menghapus item.

Penghapusan bersifat permanen: item tidak masuk inventory atau menghasilkan reward. Preview menampilkan jumlah unit dan tumpukan per jenis item, maksimal 20 jenis dengan jumlah terbanyak. Jenis yang tidak ditampilkan tidak ikut dihapus, termasuk saat memilih semua. Buka command lagi untuk preview baru jika masih ada item lain.

## Perlindungan dan batas

Preview berlaku 120 detik, terikat pada UID pemakai, world, dan snapshot UID/jenis/jumlah setiap tumpukan. Sesi dipakai sekali. Command dan penghapusan memiliki jeda 3 detik. Ownership diperiksa kembali saat konfirmasi dan selama penghapusan.

Item baru di luar snapshot tidak ikut dihapus. Jika tumpukan terpilih hilang atau berubah sebelum konfirmasi, tindakan ditolak sebelum penghapusan pertama; buka preview baru. Keluar/pindah world, disconnect, reload, Batal, atau replay membatalkan akses preview lama.

Penghapusan native dilakukan per tumpukan, bukan satu transaksi atomik. Error, penolakan native, atau perubahan izin selama proses dapat menyebabkan hanya sebagian tumpukan terhapus; tidak ada rollback atau pengembalian otomatis. Periksa hasil aktual sebelum membuka preview berikutnya.

Script memerlukan API akun/owner/access native, lookup player online, pembacaan drop beserta UID, dan `removeDroppedItem`. Jika identitas owner tidak dapat diverifikasi, penghapusan ditolak. Penggunaan engine asli tetap perlu diperiksa setelah pemasangan.

Tidak ada database SQLite atau penyimpanan riwayat sendiri; sesi dan cooldown berada di memori. Log error dicetak ke console server, dan log produksi tidak perlu dipublikasikan. Dialog menampilkan teks kecil kuning **© Dibuat Oleh : Nathan**.
