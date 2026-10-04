# outmag.lua — tombol per MAG

**Status: integrasi tombol dibuat; pengeluaran isi MAG masih membutuhkan tambahan API engine.** Tidak ada source engine/binding MAG dalam workspace ini. Tes lokal menggunakan mock, belum diuji pada dialog GTPS asli.

## Cara penggunaan

Wrench MAG dengan salah satu ID **5638, 5930, 9850, 10266, 21220**, lalu tekan **DROP ALL ITEM**. Targetnya hanya MAG yang dibuka. Seluruh stok item/blok/seed di MAG tersebut harus dikeluarkan satu tile di depan player menurut arah hadap saat tombol ditekan. `/outmag` sekarang menampilkan petunjuk wrench, bukan mengosongkan seluruh world.

Script menambahkan tombol ke dialog bawaan tanpa mengganti nama dialog, field konfigurasi, dan tombol aslinya. Hook wrench menyimpan world, koordinat, serta ID MAG di server. Hook outgoing hanya menambahkan tombol pada dialog pertama setelah wrench jika icon judul sesuai ID MAG. Dialog lebih dari 4096 byte, judul yang tidak cocok, atau dialog tanpa `end_dialog` diteruskan tanpa perubahan. Jika format dialog engine berbeda, diperlukan contoh markup dialog aktual untuk menyesuaikan pencocokannya.

Setiap tombol terkait sesi 120 detik dan hanya bisa dipakai satu kali; client tidak dapat memilih koordinat MAG melalui field palsu. Pergantian world, disconnect, dialog baru, atau tombol native membatalkan sesi lama. Klik memvalidasi kembali world serta foreground MAG. Otorisasi mesin, jangkauan, dan validasi perubahan mesin tetap wajib dilakukan engine pada saat transaksi.

Jika tile tujuan berisi foreground block, hasil yang dituju adalah penolakan tanpa perubahan stok:

> Cannot drop items: the tile in front of you is blocked.

Background saja boleh. Tanpa extension, tombol memberi pesan `Cannot empty this MAG: this server needs the OutmagNative engine extension.` Stok dan drop tidak diubah.

## API yang belum tersedia

`docslua...txt` menyediakan `onTileWrenchCallback`, `onPlayerSendRaw`, `onPlayerDialogCallback`, dan `world:spawnItem`, tetapi tidak menyediakan pembacaan arah hadap maupun pembacaan/pengosongan stok MAG tertentu. `getMagplantStock(player)` hanya membaca MAG yang terhubung ke player. `item:getMachineCap()` adalah kapasitas, bukan stok; `tile:getTileData()` untuk pohon/provider, bukan penyimpanan MAG.

Mengetahui ID MAG belum menyediakan akses stok. Script tidak memanggil spawnItem sendiri agar tidak menggandakan item.

## Kontrak extension yang perlu diimplementasikan pada engine

Berikut **API integrasi baru yang belum tersedia**, bukan nama fungsi bawaan yang diasumsikan ada:

```lua
OutmagNative = {
    apiVersion = 2,
    drainMagInFront = function(world, player, tileX, tileY, expectedMagID)
        -- Implementasi native engine wajib dibuat terlebih dahulu.
        -- Sukses: {ok=true, items=total_unit_yang_dikeluarkan}
        -- Ditolak tanpa perubahan: {ok=false, code="blocked"}
    end,
}
```

Extension wajib melakukan operasi berikut sebagai satu transaksi engine:

1. Validasi player online di world tersebut, jangkauan wrench, hak mengambil stok menurut izin MAG/lock engine, serta tipe dan identitas mesin yang dituju. Jangan mengotorisasi dari nama tampilan player. Jangan menggunakan MAG remote/link lain.
2. Ambil arah hadap dan posisi terkini player. Tujuan `(blockX - 1, blockY)` jika kiri, `(blockX + 1, blockY)` jika kanan. Tolak jika di luar world atau foreground tidak nol, termasuk block non-solid.
3. Baca stok asli MAG terpilih; cek batas drop, stack, dan kapasitas sebelum mengubah stok.
4. Kosongkan stok dan buat seluruh drop persis di tile tujuan dengan perlindungan terhadap mutasi/pickup bersamaan serta penyerapan kembali oleh MAG selama operasi. Persistensi stok dan drop harus konsisten saat gagal simpan/restart. Jika gagal, rollback seluruh perubahan. Jangan sukses parsial.
5. Kembalikan receipt jumlah unit aktual. Kode penolakan yang didukung: `blocked`, `bounds`, `denied`, `protected`, `empty`, `capacity`, `changed`, `distance`, `failed`.

API v1 `drainWorldInFront` tidak lagi dipakai: tombol per MAG tidak boleh memicu pengosongan seluruh world.

## Verifikasi

Reload script dari folder Lua server aktif. Log harus memuat `[outmag] BOOT v2-per-mag` dan `BUTTON wrench=true outgoing=true dialog=true`. `NOT READY` berarti engine extension belum tersedia; command dan integrasi tombol tetap didaftarkan.

Tes lokal: `lua5.1.exe tests/outmag-test.lua` dari folder ini. Tes memeriksa kelima ID, preservasi dialog, target MAG, token palsu/kedaluwarsa/replay, tile berubah, error, serta hasil wrapper. Tes tidak membuktikan engine dapat memindahkan stok. Setelah extension tersedia, uji langsung arah kiri/kanan, tile terhalang, izin, MAG kosong/campuran, kapasitas drop, dan restart.
