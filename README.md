# PUREGTPS Lua Scripts

**Developer: Nathan**

Paket script Lua untuk server GTPS, lengkap dengan panduan setiap fitur. Untuk publikasi GitHub, upload isi folder ini termasuk `.gitignore`. Untuk pemasangan di server, upload hanya file `.lua` yang diperlukan ke Lua Scripts, lalu reload server sesuai panduan fitur.

Paket ini berisi 18 script, 18 README fitur, README utama, panduan migrasi, catatan audit, dan `.gitignore`. Folder `tests`, dependency lokal, serta referensi API `docslua...txt` tidak disertakan. Instruksi pengujian di README fitur merujuk ke workspace pengembang dan bukan langkah pemasangan di server.

| File | Command utama | Fitur | Panduan |
| --- | --- | --- | --- |
| [12career.lua](12career.lua) | `/career`, `/12career`, `/setcareer` | Panduan, XP, dan hadiah 12 karir | [README](12career-README.md) |
| [autosb.lua](autosb.lua) | `/autosb` | Pengaturan Auto Super Broadcast | [README](autosb-README.md) |
| [Chicken.lua](Chicken.lua) | `/setchicken` | Pengaturan hasil harvest Chicken | [README](Chicken-README.md) |
| [cleardrop2.lua](cleardrop2.lua) | `/cleardrop2` | Membersihkan drop item pilihan | [README](cleardrop2-README.md) |
| [cow.lua](cow.lua) | `/setcow` | Pengaturan hasil harvest Cow | [README](cow-README.md) |
| [creditcard.lua](creditcard.lua) | `/cc` | Bank lock/gems, PIN, transfer, dan riwayat | [README](creditcard-README.md) |
| [crypto.lua](crypto.lua) | `/crypto`, `/setcrypto` | Market dan pengaturan aset crypto | [README](crypto-README.md) |
| [exchangeglobal.lua](exchangeglobal.lua) | `/exchange2`, `/setexchange2` | Exchange Ghost, Geiger, Provider, dan pintasan Sellfish | [README](exchangeglobal-README.md) |
| [gemstobgl.lua](gemstobgl.lua) | `/sell2` | Konversi gems dan BGL | [README](gemstobgl-README.md) |
| [gemstouws.lua](gemstouws.lua) | `/buyuws`, `/setpriceuws` | Pembelian Ultra World Spray dengan gems | [README](gemstouws-README.md) |
| [ghostplayer.lua](ghostplayer.lua) | `/ghost` | Akses ghost untuk owner world | [README](ghostplayer-README.md) |
| [kitpass.lua](kitpass.lua) | `/kitpass` | Misi harian/mingguan dan hadiah Basic/Premium | [README](kitpass-README.md) |
| [outmag.lua](outmag.lua) | `/outmag` | Kontrol pengeluaran isi MAG | [README](outmag-README.md) |
| [recyle.lua](recyle.lua) | `/re`, `/topevent`, `/setrecycle` | Event recycle lock dan Top 10 | [README](recyle-README.md) |
| [rent.lua](rent.lua) | `/rent`, `/setrent` | Menu rental, saldo, dan pengaturan blacklist | [README](rent-README.md) |
| [scaneconomy.lua](scaneconomy.lua) | `/scaneconomy` | Scan ekonomi parsial khusus Founder | [README](scaneconomy-README.md) |
| [shadowfarm.lua](shadowfarm.lua) | `/shadowfarm` | Kontrol sesi farm NPC | [README](shadowfarm-README.md) |
| [verifycsn.lua](verifycsn.lua) | `/verifycsn`, `/addverify`, `/removeverify` | Daftar dan pengaturan world terverifikasi | [README](verifycsn-README.md) |

Baca README masing-masing fitur untuk command tambahan, izin role, konfigurasi, dan batas API. Script memakai API GTPS serta SQLite sesuai fitur; kompatibilitas harus dicocokkan dengan engine server.

Outmag, peminjaman item Rent, dan farming NPC Shadowfarm membutuhkan adapter native yang belum disertakan. Beberapa karir juga memerlukan integrasi event tambahan. Rincian tersedia pada README fitur tersebut; lolos tes mock tidak membuktikan integrasi di server.

Untuk instalasi lama, baca [PUBLISHING.md](PUBLISHING.md) sebelum mengganti file bank atau Auto SB. Dokumen itu menjelaskan pemilihan penyimpanan lama tanpa mereset saldo, PIN, atau konfigurasi.

Catatan pemeriksaan keamanan, perbaikan, dan batas audit tersedia di [SECURITY.md](SECURITY.md). Database, backup, nilai KV, dan log produksi tidak termasuk file untuk repository publik.

Semua file `.lua` mencantumkan **Developer: Nathan**. Setiap dialog buatan script menampilkan footer kecil berwarna kuning **© Dibuat Oleh : Nathan**. Nama Nathan sengaja dicantumkan sebagai kredit publik sesuai permintaan developer. File referensi dokumentasi engine merupakan referensi API terpisah dari script.
