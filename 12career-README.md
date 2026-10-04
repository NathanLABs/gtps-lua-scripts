# 12career.lua

Sistem 12 karir untuk GTPS dengan XP terpisah per akun, level 0–10, panduan aktivitas, dan hadiah yang diklaim sekali per level. Menggunakan API engine dalam `docslua...txt` dan SQLite `career12_v1.db`.

## Command dan menu

| Command | Akses | Fungsi |
|---|---|---|
| `/career` | Semua player | Membuka daftar 12 karir. |
| `/12career` | Semua player | Alias menu yang sama. |
| `/setcareer` | Founder tepat role `1000` | Mengatur status, XP per aktivitas, dan reward setiap karir. |

Pilih karir untuk melihat XP, level, status, panduan, dan **Lihat Reward**. Halaman reward dibagi menjadi Level 1–5 dan Level 6–10. Akun dikenali melalui `getUserID()`; perubahan nickname tidak mengubah progress.

Panel Founder menampilkan **Pause Career / Enable Career**, **Set XP per Aktivitas**, dan dua form **Set Reward**. Setiap level berisi **ItemID :** dan **Amount :**. Isi keduanya `0` untuk mengosongkan hadiah. Satu level memiliki satu jenis hadiah.

Reward awal kosong agar script tidak menentukan ekonomi server tanpa konfigurasi. XP per aktivitas dapat diubah menjadi angka bulat `1`–`1.000.000`. Perubahan hanya memengaruhi aktivitas berikutnya; XP lama dan klaim yang sudah selesai tetap tersimpan. Menu yang terbuka sebelum perubahan pengaturan diperbarui sebelum tindakan berikutnya.

## Aktivitas dan dukungan engine

Delapan karir memakai callback live yang tersedia. Empat karir lainnya tampil sebagai **MENUNGGU** sampai sistem aktivitas server dihubungkan melalui API integrasi di bawah. Pengaturan **Enable Career** mengizinkan fitur; pengaturan tersebut tidak membuat callback yang belum tersedia menjadi aktif.

| Karir / ID integrasi | XP awal per aktivitas | Sumber aktivitas |
|---|---:|---|
| Hero / `hero` | 25 | Integrasi kemenangan/misi Hero dari script server. Callback Crime bawaan yang didokumentasikan masih stub. |
| Mystic / `mystic` | 20 | Integrasi aktivitas Mystic yang benar-benar berhasil. Callback Harmonic/DNA yang didokumentasikan masih stub. |
| Surgeon / `surgeon` | 20 | `onPlayerSurgeryCallback`: operasi selesai dengan ID hadiah valid dan jumlah hadiah positif. |
| Angler / `angler` | 10 | `onPlayerCatchFishCallback`: ikan berhasil ditangkap, ID item valid dan berat positif. |
| Trainer / `trainer` | 10 | `onPlayerTrainFishCallback`: ikan sudah dimasukkan ke Fish Tank. |
| Startopia / `startopia` | 25 | Integrasi misi Startopia berhasil. Dokumentasi engine belum menyediakan callback suksesnya. |
| Cooking / `cooking` | 20 | `onPlayerCookingCallback`: hasil positif dan akurasi memenuhi resep yang sesuai. |
| Ghost Hunter / `ghost` | 10 | `onPlayerCatchGhostCallback`: jar hasil tangkapan diberikan dengan ID/jumlah valid. |
| Farmer / `farmer` | 2 | `onPlayerHarvestCallback`: satu pohon dipanen dengan jumlah buah positif. |
| Firefighter / `firefighter` | 10 | `onPlayerPutOutFireCallback`: api sudah berhasil dipadamkan. |
| Provider / `provider` | 5 | `onPlayerProviderCallback`: siklus membayarkan item valid; XP ditujukan ke owner yang dilaporkan engine. |
| Gladiator / `gladiator` | 25 | Integrasi kemenangan duel dari sistem pertarungan server. Punch bukan bukti kemenangan. |

Setiap callback valid menambah **satu aktivitas**. Berat ikan, jumlah buah, jumlah hadiah operasi, jumlah jar, jumlah makanan, dan jumlah item provider tidak menggandakan XP. Script hanya menerima player asli yang sedang online. Karir yang dijeda atau belum terhubung tidak menambah XP. Callback aktivitas bersifat advisory; script tidak membatalkan aktivitas atau mengganti hadiahnya.

Trainer mengikuti perilaku nyata API Fish Tank. Script tidak mengklaim mendeteksi kemenangan pertarungan ikan. Callback `onPlayerKillCallback` tidak dipakai untuk Gladiator karena engine mengirim korban sebagai kedua argumen dan tidak mengenali pemenang.

Untuk Cooking, `resultID` tetap menunjuk hidangan yang dimaksud meskipun masakan gagal. Jumlah hasil positif juga dapat berasal dari `ruinedResult`. Script membaca `getCookingRecipes()`, mencari `recipe.result` yang cocok, dan membandingkan akurasi dengan `minAccuracy` (default `25`). Jika beberapa resep menghasilkan ID yang sama, minimum tertinggi dipakai; ini dapat melewatkan keberhasilan resep yang memiliki ambang lebih rendah. Hasil tanpa resep yang dapat diverifikasi tidak menghasilkan XP.

Jika callback live atau API tambahan Cooking tidak tersedia, karir terkait tetap **MENUNGGU** dan karir lain tetap dapat digunakan. Ikon Fish `3000`, Ghost `21264`, dan Provider `3044` ditampilkan jika item ada; judul memakai teks apabila tidak ada ikon yang terverifikasi. Angka XP tetap terlihat pada client yang tidak menggambar elemen progress bar.

## Level dan hadiah

XP diperlukan secara kumulatif dengan rumus `100 × level × (level + 1) / 2`.

| Level | Total XP diperlukan |
|---:|---:|
| 1 | 100 |
| 2 | 300 |
| 3 | 600 |
| 4 | 1.000 |
| 5 | 1.500 |
| 6 | 2.100 |
| 7 | 2.800 |
| 8 | 3.600 |
| 9 | 4.500 |
| 10 | 5.500 |

Level dibatasi 10. XP dan jumlah aktivitas tetap dapat bertambah sampai batas masing-masing `2.000.000.000`. XP satu karir tidak membuka level karir lain dan tidak mengubah level akun atau role engine. Tidak ada reset musiman otomatis.

Hadiah diklaim manual setelah level terbuka, hadiah dikonfigurasi, karir diaktifkan dan sumbernya terhubung. Satu hadiah hanya dapat diambil sekali per kombinasi **UID + karir + level**. Bila Founder mengganti atau menghapus reward setelah klaim, kartu klaim tetap menampilkan item dan jumlah dari receipt asli. Inventory penuh memakai Extra Backpack melalui `giveItem()`.

## Penyimpanan dan klaim pending

Database menyimpan pengaturan, XP/aktivitas, reward, receipt integrasi, jurnal klaim, generasi dialog, dan log perubahan. Database berada di folder server sesuai perilaku `sqlite.open()`, bukan otomatis di folder Lua lokal. Simpan database ini saat memindahkan atau memperbarui server. Upload script Lua saja; README dan file di folder `tests` bukan script server.

Klaim menyimpan intent **pending** sebelum memanggil API inventory, lalu memeriksa perubahan inventory dan Extra Backpack. Penolakan `giveItem()==false` yang terbukti tidak mengubah keduanya ditandai **cancelled** dan dapat dicoba ulang. Hasil parsial, exception, pembacaan tidak pasti, atau kegagalan finalisasi database tetap **pending**. Klaim pending menahan klaim reward akun tersebut pada semua karir dan tidak diberikan ulang otomatis setelah reload. XP aktivitas yang valid masih dapat disimpan.

SQLite dan penyimpanan inventory engine tidak memiliki transaksi atomik bersama. Script tidak menjanjikan penyimpanan item tepat sekali jika server crash di antara dua penyimpanan. Founder perlu membandingkan jurnal dengan inventory, Extra Backpack, log dan backup engine sebelum menyelesaikan kasus pending. Tidak ada command di script untuk menebak hasil atau membuka ulang jurnal secara otomatis.

Untuk melihat jurnal tanpa mengubah data:

```sql
SELECT id, uid, career, level, item, amount, state,
       before_inv, before_extra, after_inv, after_extra, at, note
FROM c12_claims
WHERE state = 'pending'
ORDER BY id;
```

Backup SQLite sebaiknya menggunakan mekanisme backup SQLite atau dilakukan saat server berhenti. Jika menyalin database aktif dalam mode WAL, file `career12_v1.db-wal` dan `career12_v1.db-shm` juga perlu diperhitungkan; menyalin `.db` saja dapat kehilangan perubahan yang belum checkpoint.

## Integrasi empat karir yang belum mempunyai callback

`Career12` adalah API script ini, bukan API native engine. API juga dikembalikan oleh `require("12career")`. Hanya script server yang sudah memvalidasi keberhasilan aktivitas yang boleh memanggilnya. Jangan memberi XP langsung dari dialog, input player, punch, pickup item, atau receipt yang dikirim client.

| API | Hasil dan fungsi |
|---|---|
| `Career12.connect(id, label)` | `true, "connected"` setelah sumber sukses karir ditautkan. |
| `Career12.disconnect(id)` | Memutus sumber; progress tersimpan. |
| `Career12.complete(player, id, receipt)` | `true, "awarded"` jika satu keberhasilan tersimpan; receipt yang sama menghasilkan `false, "duplicate"`. |
| `Career12.getProgress(player, id)` | Tabel `xp`, `activities`, `level`, `maxLevel`, `enabled`, `connected` atau `nil` jika tidak tersedia. |

`connect`, `disconnect`, dan `complete` hanya menerima ID karir yang menggunakan bridge: `hero`, `mystic`, `startopia`, `gladiator`. Delapan jalur native tidak boleh dikreditkan lagi lewat bridge.

Receipt harus berupa string `1`–`96` karakter berisi huruf/angka, `_`, `:`, `-`, atau `.`. Gunakan ID keberhasilan yang dibuat dan disimpan server. Receipt harus tetap sama ketika aktivitas yang sama dicoba ulang dan berbeda untuk setiap keberhasilan baru. Keunikannya diperiksa per **UID + karir + receipt**, dalam transaksi yang sama dengan perubahan XP. Jangan membuat receipt baru dari waktu sekarang setiap retry: itu akan menganggap retry sebagai keberhasilan baru.

Contoh di script Hero server, dipanggil hanya setelah sistem Hero sendiri mengonfirmasi misi berhasil:

```lua
local connectedAPI

local function currentHeroAPI()
    -- Memakai instance yang sudah dimuat; require hanya sebagai fallback.
    local api = _G.Career12 or require("12career")
    if connectedAPI ~= api then
        local ok, reason = api.connect("hero", "Hero mission success")
        if not ok then return nil, reason end
        connectedAPI = api
    end
    return api
end

local function recordConfirmedHeroSuccess(player, savedMissionReceipt)
    local api, reason = currentHeroAPI()
    if not api then return false, reason end
    return api.complete(player, "hero", savedMissionReceipt)
end

-- Setelah keberhasilan asli tervalidasi dan ID tersebut tersimpan oleh server:
-- recordConfirmedHeroSuccess(player, "hero:mission:18452")
```

Sumber bridge harus dihubungkan kembali setiap reload. `_G.Career12` menunjuk instance terbaru; instance lama sengaja menolak integrasi setelah digantikan. Contoh di atas memeriksa perubahan instance agar reload tidak kehilangan sambungan pada keberhasilan berikutnya. Jangan memanggil `require("12career")` berulang untuk membuat instance tambahan.

Jika `complete()` mengembalikan `busy`, `unavailable`, atau `database_error`, sistem aktivitas dapat mengantrekan retry dengan receipt asli setelah penyebabnya selesai dan player masih online. `paused` berarti Founder menjeda karir; `disconnected` berarti bridge belum dihubungkan. Kebijakan mengulang keberhasilan lama saat fitur dijeda tetap menjadi keputusan sistem aktivitas server.

## Pemasangan dan pemeriksaan

1. Upload `12career.lua` ke folder Lua server. Hindari memuat salinan script yang sama dengan nama berbeda secara bersamaan.
2. Reload Lua atau restart server sesuai mekanisme server Anda.
3. Periksa `[12career] BOOT v1-careers`, hasil `ROUTES`, dan pesan `Loaded /career /12career /setcareer` di console.
4. Tanpa plugin bridge, engine yang menyediakan kedelapan callback menampilkan `8/12 sources connected`. Callback yang hilang menurunkan angka ini dan mencatat alasannya.
5. Founder mengisi reward melalui `/setcareer`, lalu player mencoba aktivitas yang sesuai dan memeriksa `/career`.

`INIT FAILED` berarti menu akan menjawab bahwa sistem belum tersedia; command dan dialog didaftarkan sebelum init storage agar kesalahan backend tidak berubah menjadi unknown command. Jika command tetap unknown dan tidak ada BOOT, pastikan script dimuat oleh engine yang benar.

Pengujian lokal memakai interpreter Lua dan SQLite asli dengan API GTPS simulasi. Perilaku callback dan tampilan akhir masih perlu diverifikasi di server/client GTPS asli; README ini tidak menyatakan uji live sudah dilakukan.
