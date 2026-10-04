# Auto Super Broadcast — autosb.lua

**Developer: Nathan**

`/autosb` membuka menu **Start**, **Stop**, dan **Configure** untuk semua player. Broadcast memakai command `/sb` bawaan; izin, biaya, dan cooldown tetap diperiksa engine. Script tidak memberi role atau hak broadcast tambahan.

## Pemasangan dan penggunaan

1. Sesuaikan `SERVER_SB_COOLDOWN_SECONDS` di bagian atas `autosb.lua` dengan cooldown `/sb` server yang sebenarnya. Nilai harus bilangan bulat 1–86.400 detik. Default `nil` sengaja menolak Start sampai pengelola mengisinya; perbarui juga bila cooldown engine berubah.
2. Upload satu salinan `autosb.lua` ke pemuat Lua server, lalu reload. Log pemuatan: `[autosb] Loaded. Use /autosb -> Start / Stop / Configure.`
3. Masuk world, ketik `/autosb`, lalu **Configure**. Isi teks pesan saja, tanpa menambahkan `/sb`, dan durasi dalam menit. Tekan **Simpan**, lalu **Start**.
4. **Stop** menghentikan pengiriman. Menutup menu tidak menghentikan Auto SB yang sedang berjalan.

Teks maksimal 300 byte dan tidak boleh kosong atau hanya berupa kode warna. Baris baru, karakter kontrol, dan `|` ditolak. Durasi berupa bilangan bulat 0–1.440 menit; `0` berarti berjalan sampai Stop atau disconnect. Mengubah konfigurasi ketika aktif memakai teks baru pada pengiriman berikutnya dan menghitung ulang durasi dari waktu penyimpanan.

Disconnect dan reload menghentikan Auto SB. Setelah login/reload, player perlu menekan Start lagi. Jika player belum berada di world, pengiriman menunggu, tetapi durasi tetap berjalan. Tick yang terlambat tidak dikejar dengan broadcast beruntun. Kegagalan dispatch atau error menghentikan sesi.

## Penyimpanan dan batas integrasi

Teks serta durasi disimpan per UID melalui KV `autosb_config_v1_<UID>`, tanpa database SQLite. Status berjalan tidak disimpan. Instalasi lama dapat memilih prefix yang sudah ada melalui `autosb_storage_prefix_v1`; ikuti [PUBLISHING.md](PUBLISHING.md) sebelum mengganti script agar konfigurasi lama tetap terbaca. Prefix yang tidak valid menonaktifkan penggunaan fitur.

API yang diperlukan mencakup command/dialog/disconnect, timer, lookup player/world, KV server, dan dispatch pesan native. Nilai sukses dispatch berarti command diproses, bukan bukti bahwa broadcast diterima. Perilaku biaya, cooldown, dan pengiriman perlu diverifikasi di engine server.

Pesan SB terlihat oleh pemain sesuai perilaku engine. Jangan masukkan data rahasia pada teks broadcast atau mengunggah backup KV/log produksi ke repository. Dialog menampilkan teks kecil kuning **© Dibuat Oleh : Nathan**.
