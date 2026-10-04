# Ghost untuk owner world

Upload **ghostplayer.lua** ke **Lua Scripts** server GTPS, lalu reload. File ini memakai **command `/ghost` yang sudah ada**.

Cara pakai:

1. Masuk ke world yang kamu miliki sebagai owner world lock.
2. Ketik **/ghost** untuk mengaktifkan ghost bawaan server.
3. Ketik **/ghost** lagi untuk mematikannya.

| Pemakai | Izin |
| --- | --- |
| Player biasa, VIP, Mod/Moderator yang menjadi owner world | Bisa di world miliknya |
| Admin world atau player yang hanya mendapat access | Tidak bisa, kecuali juga memiliki role staf Dev ke atas |
| Pengunjung atau player di world tanpa owner | Tidak bisa |
| Dev (4), SDev (5), dan staf di atasnya | Tetap menggunakan izin staf, mengikuti pengaturan ghost world |

Pengecekan owner dilakukan oleh policy native engine, bukan perbandingan nickname atau `world:hasAccess()`. Hak `/ghost` dari role editor tidak dipakai sebagai pengecualian untuk player non-owner. Pengaturan world yang melarang ghost tetap diikuti engine, dengan pengecualian owner sesuai API.

Untuk player nonstaf, ghost dimatikan saat keluar world. Saat berpindah ke world sendiri yang lain, ketik `/ghost` lagi. Kepemilikan yang berubah karena world dijual atau lock dihapus menyebabkan ghost dimatikan pada player tick berikutnya (sekitar satu detik). Setelah reload script, ghost player nonstaf yang sudah aktif perlu diaktifkan ulang; sesi lama tidak dianggap sebagai bukti izin. Dev/SDev tetap ditangani engine.

Script mengatur `setGhostModePolicy` dan mengamati callback ghost bawaan. Jangan memakai script lain yang menimpa policy atau memaksa hasil `onPlayerGhostModeCallback` bersamaan. Sesuai dokumentasi engine, `/rs` mereset ghost policy; reload script ini sesudahnya untuk menerapkan pengaturan lagi.

26 pengujian lokal lulus memakai runtime Lua 5.4 dan mock API engine: izin owner/admin/staf, nickname, toggle, perpindahan world, penjualan world, penghapusan lock, demosi role, reload, dan kegagalan API. Aturan kepemilikan native, toggle, perpindahan world, dan pembatasan role perlu dicoba juga di server GTPS.

Runner lokal: `node tests/run-ghostplayer.cjs [path-ke-package-wasmoon]`. Folder `tests` tidak perlu diupload ke server.
