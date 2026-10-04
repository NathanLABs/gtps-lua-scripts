# Shadowfarm

**Status: belum bisa melakukan farming dengan API Lua yang tersedia di workspace ini.** `shadowfarm.lua` membutuhkan adapter engine `ShadowfarmNative` yang belum disediakan. File Lua ini adalah kontrol `/shadowfarm`; implementasi NPC dan BFG harus ada di engine server sebelum fitur bisa berjalan.

Target fitur adalah NPC yang menyalin pakaian owner dan mengambil alih autofarm/BFG native yang sedang aktif, termasuk konfigurasi 30 slot. NPC tetap bekerja di world farm semula ketika owner pindah world, selama owner masih online. Saat owner offline, engine harus menghentikan sesi, menghapus NPC, dan melepas world farm.

Referensi API `docslua...txt` pada workspace pengembang (tidak disertakan dalam paket upload ini) menyediakan pembuatan NPC, pakaian, target dan slot autofarm player, serta penanaman dari MAGPLANT yang terhubung ke player. Dokumentasi itu belum memberikan operasi untuk memindahkan hubungan MAGPLANT ke NPC, menjalankan scheduler BFG native atas nama owner, menempatkan blok BFG dari inventory owner, mengkreditkan seluruh hasil NPC ke owner, atau mempertahankan world tanpa player. Menyalin tampilan NPC dan mengaktifkan flag `autofarm` tidak membuktikan fungsi-fungsi tersebut tersedia.

Adapter harus memakai jalur reward dan bonus pakaian native. Bonus Lancer mengikuti engine; script tidak mengalikan gems atau XP secara manual dengan angka 600. Pemakaian item/stock MAGPLANT, izin world, kepemilikan reward, dan status online juga harus diperiksa oleh engine untuk setiap aksi.

Jangan menganggap lolos uji mock sebagai bukti NPC sudah farming di server. Uji lokal hanya dapat memeriksa kontrol Lua dan kontrak adapter. Bukti operasional memerlukan implementasi engine dan pengujian server dengan perpindahan world, kehilangan koneksi, reload, stock/item habis, serta perubahan izin world.

## Instalasi dan penggunaan

1. Pengembang engine harus mengimplementasikan dan mengaktifkan `ShadowfarmNative` sesuai kontrak di bawah. Adapter tersebut **tidak termasuk** dalam file ini.
2. Upload [shadowfarm.lua](shadowfarm.lua) ke Lua Scripts server dan reload. Script membutuhkan API command, dialog, tick, disconnect, akun/item, serta SQLite yang ada di dokumentasi lokal.
3. Periksa log `[shadowfarm]`. `Loaded /shadowfarm | native_bfg=false` berarti command tersedia tetapi farm belum bisa dijalankan. `INIT FAILED` berarti kontrol belum siap; perbaiki error log terlebih dahulu.
4. Jika adapter native sudah tersedia, masuk ke world BFG asal. Siapkan MAG/inventory, target block, delay, dan slot autofarm lewat `/cheats`, lalu aktifkan Autofarm. Untuk memakai 30 slot, konfigurasi autofarm owner harus sudah 30 sebelum mulai.
5. Pakai pakaian yang ingin dicerminkan, lalu ketik `/shadowfarm`. Setelah sesi native dikonfirmasi, owner boleh pindah world selama tetap online.

| Command | Fungsi |
| --- | --- |
| `/shadowfarm` atau `/shadowfarm start` | Mulai dari setting aktif saat ini; jika sudah aktif, buka status tanpa membuat sesi kedua |
| `/shadowfarm status` | Lihat world asal, clone, slot efektif, delay, durasi, block, dan gems yang dilaporkan engine |
| `/shadowfarm stop` | Hentikan sesi owner saat ini |
| `/shadowfarm help` | Buka panduan |

Script menyalin konfigurasi saat mulai; perubahan pakaian atau world owner setelah itu tidak memperbarui snapshot clone. Jumlah slot efektif tetap mengikuti izin dan batas native server, dan ditampilkan di status. Script tidak mengubah batas autofarm global atau memberikan role tambahan kepada NPC. `roleRequired=0` pada registrasi command bukan pemberian akses farming; adapter tetap wajib memeriksa hak native owner.

Menu terikat ke UID dan kedaluwarsa setelah 120 detik. Tombol Stop membawa ID sesi yang ditampilkan sehingga menu lama tidak boleh menghentikan sesi penggantinya. Jika start tidak dapat dikonfirmasi, kontrol mencoba membersihkan sesi dan tidak mengulang start otomatis. Bila cleanup belum dikonfirmasi, start/status harus menunggu cleanup berhasil; kegagalan dicatat di log.

`shadowfarm_v1.db` menyimpan penghitung generasi di tabel `sf_runtime`, bukan worker farm atau saldo reward. Reload menaikkan generasi dan membuat callback/menu sebelumnya tidak berlaku. Sesi farm harus dibersihkan oleh engine; script tidak melanjutkan farming otomatis dari database. Jangan menghapus atau mengatur ulang database generasi saat server masih menjalankan sesi Shadowfarm.

## Kontrak adapter engine v1

`ShadowfarmNative` adalah tabel global yang disediakan implementasi engine. Nama ini adalah kontrak integrasi baru, bukan fungsi yang sudah ada di `docslua...txt`. Menambahkan tabel Lua yang hanya mengembalikan sukses atau menyalin NPC tidak memenuhi kontrak.

```lua
ShadowfarmNative = {
    apiVersion = 1,
    capabilities = {
        npcMirror = true, ownerLinkedBfg = true, ownerRewards = true,
        onlineOnly = true, worldLease = true, nativeMultipliers = true,
        playerHandoff = true, cleanupOnReload = true,
    },
    beginGeneration = function(generation) end,
    start = function(owner, profile, requestId) end,
    status = function(ownerID) end,
    stop = function(ownerID, expectedSessionId) end,
}
```

Ini hanya bentuk kontrak, **bukan adapter yang dapat digunakan**. Semua capability harus bernilai boolean `true` dan seluruh method harus berupa fungsi. Pemanggilan memakai titik (`api.start(...)`), tanpa argumen `self`.

| Method | Hasil dan kewajiban |
| --- | --- |
| `beginGeneration(generation)` | Kembalikan tepat `true` hanya setelah sesi generasi sebelumnya beserta NPC, scheduler, dan world lease selesai dibersihkan. Panggilan ulang pada generasi sama harus aman. Tolak generasi lebih rendah tanpa menyentuh sesi generasi baru. Fence generasi lama agar request tertunda tidak bisa membuat worker baru. |
| `start(owner, profile, requestId)` | Operasi sinkron dan atomik. Sukses mengembalikan `{ok=true, sessionId="..."}`; penolakan mengembalikan `{ok=false, reason="..."}` tanpa worker tersisa. Validasi ulang akun online, setting, sumber item/MAG, dan izin menggunakan engine. Satu owner hanya boleh mempunyai satu sesi; request yang sama harus idempotent. |
| `status(ownerID)` | Kembalikan status otoritatif owner dengan schema di bawah. Sukses start harus langsung terlihat oleh panggilan status berikutnya. |
| `stop(ownerID, expectedSessionId)` | Jika ID sesi diberikan, hentikan hanya sesi tersebut. Jika `nil`, bersihkan seluruh sesi Shadowfarm owner. Harus idempotent dan menyelesaikan penghentian sebelum kembali. Nilai return tidak dipakai kontrol; kontrol memeriksa `status` sesudahnya. |

`requestId` dibuat sebagai `sf:<generation>:<ownerID>:<serial>`. Native harus memastikan UID dan generasi request cocok dengan `profile.ownerID`, `profile.generation`, akun owner, serta generasi yang masih berlaku; start dari generasi yang sudah dicabut harus ditolak. ID sesi harus unik dan tidak digunakan ulang lintas generasi, agar Stop lama tidak mengenai sesi baru. Method tidak boleh menyimpan handle Lua `owner` untuk digunakan di luar callback; simpan identitas dan referensi native yang sah.

Profile yang diterima `start`:

| Field | Nilai |
| --- | --- |
| `ownerID`, `ownerName`, `role` | UID akun; nama tampilan yang dibersihkan hingga 30 karakter; snapshot role. Role ini bukan izin untuk menaikkan role NPC. |
| `generation` | Generasi kontrol saat request dibuat; harus cocok dengan request ID dan fence generasi aktif native |
| `world`, `x`, `y` | Nama world asal, serta posisi owner dalam **pixel**, bukan tile |
| `clothes` | Array Lua indeks 1..10 yang berisi slot engine 0..9: hair, shirt, pants, feet, face, hand, back, mask, necklace, ances. ID `0` berarti kosong. |
| `skin` | Array `{r,g,b,a}`, masing-masing integer 0..255 |
| `cheats` | Boolean untuk 14 cheat yang didokumentasikan, dengan `autofarm=true` wajib |
| `target`, `slots`, `delayMs` | ID target block, jumlah slot owner, override delay 0..60000 ms. Delay `0` berarti default server. |
| `serverMaxFar` | Opsional, snapshot batas global jika getter tersedia; `-1` berarti tanpa cap tambahan. Adapter wajib memeriksa batas native aktual. |

Empat belas key `cheats` adalah `autofarm`, `autocollect`, `autofish`, `antibounce`, `fastdrop`, `fastpull`, `fasttrash`, `speed`, `jump`, `double_jump`, `heat_resist`, `strong_punch`, `long_punch`, dan `long_build`. Semua field profile berasal dari kontrol Lua dan tetap harus divalidasi oleh engine.

Status tidak aktif minimal:

```lua
{ ownerID = 123, active = false, reason = "Alasan opsional" }
```

Status aktif:

```lua
{
    ownerID = 123, active = true,
    sessionId = "ID-native-unik", requestId = "sf:1:123:1", generation = 1,
    world = "FARM", npcName = "Nama clone",
    target = 4584, slots = 30, delayMs = 190,
    startedAt = 1800000000, gemsEarned = 0, blocksBroken = 0,
}
```

Angka dalam contoh bukan konfigurasi bawaan. `sessionId` dan `requestId` harus 1..96 karakter alfanumerik atau `_ : - .` tanpa spasi. `world` harus 1..24 karakter alfanumerik; `npcName` 1..30 karakter. UID dan generasi harus integer positif hingga `9007199254740991`; target dan slot integer positif hingga `2000000000`. `startedAt` adalah epoch detik nonnegatif; statistik nonnegatif, integer, hingga `9007199254740991`. Statistik yang tidak dikirim dianggap `0` oleh kontrol.

Kontrol hanya menampilkan start aktif jika hasil dan status cocok pada UID, session ID, request ID, generasi, world asal, target, serta delay. Slot efektif harus positif, tidak melebihi slot snapshot dan cap server yang diketahui. Receipt ini tidak memeriksa seluruh keadaan NPC secara langsung; native bertanggung jawab memastikan penampilan, MAG, scheduler, bonus, reward, dan world lease benar-benar sudah berlaku.

## Jaminan yang harus diimplementasikan native

| Capability | Jaminan engine |
| --- | --- |
| `npcMirror` | Spawn satu clone dengan pakaian dan skin snapshot, termasuk slot kosong; penampilan harus benar secara native. |
| `ownerLinkedBfg` | Jalankan scheduler BFG native di world asal dengan target, slot efektif, delay, dan sumber MAG/inventory owner yang benar. Penempatan block harus mengonsumsi resource native secara atomik. |
| `ownerRewards` | Semua gems, item, dan XP dari worker diberikan tepat sekali ke akun owner melalui jalur reward native; tidak jatuh sebagai reward akun NPC atau dicredit dua kali. |
| `onlineOnly` | Sebelum setiap aksi, periksa koneksi akun owner yang sebenarnya. Offline langsung menghentikan scheduler dan membersihkan NPC, tanpa menunggu tick Lua. |
| `worldLease` | Pertahankan world farm meskipun seluruh player nyata meninggalkan world. Lepas lease pada setiap jalur penghentian atau kegagalan. |
| `nativeMultipliers` | Terapkan bonus pakaian snapshot menggunakan aturan engine, termasuk stacking/cap Lancer yang benar. Jangan menambahkan multiplier manual atau efek duplikat. |
| `playerHandoff` | Atomik saat mengambil alih autofarm asli: tidak ada worker ganda, dan kegagalan meninggalkan konfigurasi awal dalam keadaan aman. Berhenti tidak boleh mengaktifkan autofarm owner secara keliru di world baru. |
| `cleanupOnReload` | Batalkan sesi dan pekerjaan tertunda pada reload, disconnect, shutdown, atau pergantian generasi; bersihkan NPC, source binding, task, dan lease tanpa bergantung pada callback Lua lama. |

Izin world/MAG dan hak cheat harus diperiksa dengan identitas owner pada setiap aksi; penyalinan nama, role, atau pakaian tidak memberi NPC izin baru. Hubungan sumber farm harus tetap merujuk world/MAG awal saat owner berpindah world. Semua langkah start, debit resource, reward, dan cleanup harus mempunyai aturan atomik serta rollback yang mencegah duplikasi atau resource hilang.

## Verifikasi

Runner kontrol lokal: `node tests/run-shadowfarm.cjs`. Runner memakai SQLite nyata dan adapter farming mock, dengan Lua 5.1 melalui environment `SHADOWFARM_LUA51` atau Lua 5.4 Wasmoon. Environment `SHADOWFARM_TEST_MODULES` dapat menunjuk direktori modul Wasmoon. Folder `tests` tidak perlu diupload.

Pengujian server wajib membuktikan clone dan pakaian muncul, slot 30 dan delay sesuai aturan native, stok MAG/inventory berkurang dengan benar, serta seluruh gems/item/XP masuk ke owner. Uji saat owner pindah world dan world asal kosong, ketika koneksi putus di tengah aksi/start, saat reload atau shutdown, ketika izin berubah, dan ketika stock habis. Periksa tidak ada sesi ganda, reward ganda, NPC tertinggal, atau world lease bocor. Pengujian ini belum dilakukan karena implementasi engine belum tersedia di workspace.
