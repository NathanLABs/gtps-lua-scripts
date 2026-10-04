# PUREGTPS Lua Scripts

**Developer: @PureGTPS**

Kumpulan script Lua untuk server GTPS. Upload file fitur yang dibutuhkan ke Lua Scripts, lalu reload server. Folder `tests` digunakan untuk pengujian lokal dan tidak perlu diupload ke server.

| File | Command utama | Fitur |
| --- | --- | --- |
| [12career.lua](12career.lua) | `/career`, `/12career`, `/setcareer` | Panduan, XP, dan hadiah 12 karir |
| [autosb.lua](autosb.lua) | `/autosb` | Pengaturan Auto Super Broadcast |
| [Chicken.lua](Chicken.lua) | `/setchicken` | Pengaturan hasil harvest Chicken |
| [cleardrop2.lua](cleardrop2.lua) | `/cleardrop2` | Membersihkan drop item pilihan |
| [cow.lua](cow.lua) | `/setcow` | Pengaturan hasil harvest Cow |
| [creditcard.lua](creditcard.lua) | `/cc` | Bank lock/gems, PIN, transfer, dan riwayat |
| [crypto.lua](crypto.lua) | `/crypto`, `/setcrypto` | Market dan pengaturan aset crypto |
| [exchangeglobal.lua](exchangeglobal.lua) | `/exchange2`, `/setexchange2` | Exchange Ghost, Geiger, Provider, dan pintasan Sellfish |
| [gemstobgl.lua](gemstobgl.lua) | `/sell2` | Konversi gems dan BGL |
| [gemstouws.lua](gemstouws.lua) | `/buyuws`, `/setpriceuws` | Pembelian Ultra World Spray dengan gems |
| [ghostplayer.lua](ghostplayer.lua) | `/ghost` | Akses ghost untuk owner world |
| [kitpass.lua](kitpass.lua) | `/kitpass` | Misi harian/mingguan dan hadiah Basic/Premium |
| [outmag.lua](outmag.lua) | `/outmag` | Kontrol pengeluaran isi MAG |
| [recyle.lua](recyle.lua) | `/re`, `/topevent`, `/setrecycle` | Event recycle lock dan Top 10 |
| [rent.lua](rent.lua) | `/rent`, `/setrent` | Menu rental, saldo, dan pengaturan blacklist |
| [scaneconomy.lua](scaneconomy.lua) | `/scaneconomy` | Scan ekonomi parsial khusus Founder |
| [shadowfarm.lua](shadowfarm.lua) | `/shadowfarm` | Kontrol sesi farm NPC |
| [verifycsn.lua](verifycsn.lua) | `/verifycsn`, `/addverify`, `/removeverify` | Daftar dan pengaturan world terverifikasi |

Baca README masing-masing fitur untuk command tambahan, izin role, konfigurasi, dan batas API. Script memakai API GTPS serta SQLite sesuai fitur; kompatibilitas harus dicocokkan dengan engine server.

Outmag, peminjaman item Rent, dan farming NPC Shadowfarm membutuhkan adapter native yang belum disertakan. Beberapa karir juga memerlukan integrasi event tambahan. Rincian tersedia pada README fitur tersebut; lolos tes mock tidak membuktikan integrasi di server.

Untuk instalasi lama, baca [PUBLISHING.md](PUBLISHING.md) sebelum mengganti file bank atau Auto SB. Dokumen itu menjelaskan pemilihan penyimpanan lama tanpa mereset saldo, PIN, atau konfigurasi.

Catatan pemeriksaan keamanan, perbaikan, dan batas audit tersedia di [SECURITY.md](SECURITY.md). Database, backup, nilai KV, dan log produksi tidak termasuk file untuk repository publik.

Semua file `.lua` mencantumkan kredit **@PureGTPS**. Dialog buatan script menampilkan footer kecil berwarna kuning **© Credit : @PureGTPS**. File referensi dokumentasi engine merupakan referensi API terpisah dari script.
