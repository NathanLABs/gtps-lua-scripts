# Scan Economy — scaneconomy.lua

**Developer: Nathan**

`/scaneconomy` membuat laporan **parsial** jumlah lock yang teramati. Hanya **Founder tepat role 1000** yang dapat menjalankan dan melihatnya; Owner server role 999 tidak mendapat akses. Script membaca data tanpa mengambil, memindahkan, atau mengubah item.

## Pemasangan dan penggunaan

1. Upload satu salinan `scaneconomy.lua` ke pemuat Lua server, lalu reload. Log pemuatan: `[scaneconomy] Loaded. /scaneconomy: founder only; partial online/loaded scan.`
2. Sebagai Founder online, ketik `/scaneconomy` tanpa argumen. Proses berjalan bertahap, lalu membuka laporan dengan empat jenis item per halaman.
3. Selama scan berjalan, command yang sama menampilkan progres. Hanya satu scan berjalan pada satu waktu, dengan jeda minimal 30 detik sejak scan sebelumnya dimulai.

Jika peminta disconnect atau kehilangan role Founder, scan berhenti. Error menghentikan scan tanpa menerbitkan laporan baru. Hasil berada di memori dan hilang saat disconnect/reload. Command berikutnya memulai scan baru; tombol halaman membaca hasil scan yang telah selesai.

## Data yang dihitung

- Backpack dan Extra Backpack player asli yang online pada saat pembacaan.
- Drop serta lock terpasang pada world yang loaded saat daftar awal dibuat.
- Stok vending dan WL hasil penjualan vending yang dapat dibaca API.

Player offline, world unloaded, storage box, vault, donation box, dan isi container lain tidak tercakup. Pemain/world yang baru muncul setelah daftar scan dibuat juga tidak otomatis ditambahkan.

Default mengenali WL 242, DL 1796, BGL 7188, dan GGL 8470. Custom lock yang teramati dikenali dari nama yang berakhir dengan kata `Lock`/`Locks`; tanda `*` pada laporan menandai kandidat heuristik. Edit `LOCK_OVERRIDES` untuk menambahkan ID/nama yang benar atau nilai `false` untuk mengecualikan item. Script tidak mengetahui kurs custom secara otomatis.

Total adalah **unit per Item ID**, bukan hasil konversi semua denominasi ke WL. Laporan merinci backpack, Extra Backpack, drop, terpasang, stok vending, dan earnings. Scan bertahap bukan snapshot atomik: item yang berpindah selama proses dapat terlewat atau terhitung dua kali.

API yang diperlukan mencakup daftar player/world loaded, inventory/Extra Backpack, drop/tile/vending, timer, command, dan dialog. Budget default pembacaan world adalah 600 drop/tile per tick satu detik; pembacaan satu player dilakukan dalam satu langkah. Performa dan kecocokan API tetap perlu diperiksa pada engine asli.

Laporan tidak disimpan ke database atau dikirim ke layanan luar. Akses diperiksa ulang pada tick dan halaman laporan. Angka ekonomi server pada laporan/screenshot tetap merupakan data operasional; tidak perlu diunggah bersama source. Dialog menampilkan teks kecil kuning **© Dibuat Oleh : Nathan**.
