# Pindah MT5 ke VPS Windows

Tujuan: XauSignalEngine dan XauScalper berjalan 24 jam tanpa laptop. Pada 2026-11-24 laptop tidur dari 06:58
hingga 21:48 dan kedua-dua EA offline sepanjang sesi London dan New York; VPS mengelakkan masalah ini.

## 1. Sewa VPS

- **Sistem**: Windows Server 2019 atau 2022.
- **Saiz**: 2 vCPU, 4 GB RAM, 40 GB SSD sudah cukup untuk MT5 dengan dua EA.
- **Lokasi**: Eropah (Jerman, Belanda atau London). Server InstaForex dekat sana: MT5 sendiri mencadangkan
  "VPS Germany 01" (0.31 ms), berbanding kira-kira 180-290 ms dari Malaysia.
- **Kos**: lebih kurang USD 10-30 sebulan. Harga dan pakej berubah, jadi semak sendiri. Contoh pembekal yang
  menawarkan Windows: Contabo, Vultr, AWS Lightsail, atau pembekal "forex VPS" khas. Ini bukan cadangan
  pembekal tertentu.
- Pembekal akan beri **alamat IP, nama pengguna dan kata laluan** VPS. Simpan sendiri; jangan tulis dalam repo.

## 2. Sediakan pakej di laptop

```powershell
powershell -ExecutionPolicy Bypass -File tools\package_vps.ps1
```

Skrip ini membuat `ForexEA-VPS.zip` dalam folder **Downloads**. Ia tidak disimpan di Desktop kerana Desktop
disegerakkan ke OneDrive. Isi zip:

| Fail | Guna |
|---|---|
| `MQL5\Experts\XauSignalEngine.*`, `XauScalper.*` | Kedua-dua EA (sumber dan versi compiled) |
| `MQL5\Indicators\XauSetupView.*` | Paparan setup scalper |
| `MQL5\Include\AurumRest.mqh`, `XauRegime.mqh`, `XauStats.mqh` | Perlu jika EA di-compile semula |
| `MQL5\Files\aurum.env` | Kunci Supabase. **Rahsia**: hanya salin ke VPS awak sendiri |
| `MQL5\Profiles\Charts\ForexEA\` | Dua carta: Signal Engine (XAUUSD M15) dan Scalper (XAUUSD M5) dengan input semasa |

## 3. Masuk ke VPS

1. Buka **Remote Desktop Connection** di laptop, masukkan alamat IP VPS, kemudian nama pengguna dan kata laluan.
2. Salin `ForexEA-VPS.zip` dari folder Downloads laptop dan tampal (Ctrl+C, Ctrl+V) ke Desktop VPS. Selepas itu
   padam zip dari laptop.

## 4. Pasang MT5 di VPS

1. Dalam VPS, muat turun MT5 dari laman InstaForex dan pasang.
2. Log masuk akaun demo (File → Login to Trade Account). Taip kata laluan sendiri.
3. **File → Open Data Folder**, kemudian **tutup MT5**.
4. Extract `ForexEA-VPS.zip` ke dalam Data Folder itu supaya folder `MQL5` bergabung (pilih "Replace" jika ditanya).
5. Buka semula MT5.

## 5. Tetapan MT5 di VPS

1. **Tools → Options → Expert Advisors**:
   - tanda **Allow algorithmic trading**;
   - tanda **Allow WebRequest for listed URL** dan tambah `https://ukzbdszndqvgycsnjeof.supabase.co`.
2. **File → Profiles → ForexEA**. Dua carta akan terbuka dengan EA sudah dilekat.
3. Klik butang **Algo Trading** sehingga ikon hijau.
4. Pada carta M5, tambah paparan setup jika mahu: **Insert → Indicators → Custom → XauSetupView → OK**.
   (Indikator yang dimuat dari fail profil tidak dilukis; ia mesti ditambah dengan tangan.)
5. Jika EA berwajah kelabu atau tab Experts menunjukkan ralat versi: buka fail `.mq5` dalam MetaEditor (F4) dan
   tekan **F7** untuk compile semula.

## 6. Semak ia berfungsi

- Penjuru kiri atas carta M5 menunjukkan status XauScalper, contohnya "Bias SELL" atau "Waiting for HA flip at EMA".
- Tab **Toolbox → Experts** tiada ralat `WebRequest failed` atau `no SUPABASE_SERVICE_KEY`.
- App Aurum Desk: harga dan regime dikemas kini oleh Signal Engine.

## 7. Matikan MT5 di laptop

**Selepas VPS berfungsi, tutup MT5 di laptop atau buang EA dari cartanya.** Jika kedua-duanya hidup, dua salinan
XauScalper akan trade akaun yang sama dan setiap setup akan dibuka dua kali.

## 8. Biar VPS terus berjalan

- Bila selesai, **tutup tetingkap Remote Desktop dengan butang X**. Jangan pilih **Sign out**, kerana MT5 akan ikut tertutup.
- Supaya MT5 hidup semula selepas VPS restart (contohnya Windows Update):
  - tekan Win+R, taip `shell:startup`, Enter;
  - letak shortcut MT5 dalam folder itu.
  - Shortcut ini hanya berjalan selepas log masuk, jadi tetapkan juga auto-login Windows atau log masuk semula selepas
    setiap restart.
- Selepas restart, semak semula butang Algo Trading (hijau).

## Yang kekal di laptop

Tugas berjadual Claude dijalankan oleh app Claude di laptop, bukan oleh MT5:

- laporan berita (08:30);
- analisis fundamental (13:00);
- Devil's Advocate (14:20);
- jurnal mingguan (Sabtu).

Jika laptop tidur, tugas itu berjalan lewat bila laptop bangun. Selagi laporan berita hari itu belum masuk ke
Supabase, Signal Engine di VPS tidak tahu waktu berita HIGH. Akibatnya, semakan "News" pada clearance scalper lulus
walaupun berita besar akan keluar. Fundamental pula dicatat sebagai "No fundamental brief today" tanpa menyekat
trade. Jadi laptop perlu hidup sekitar 08:30 setiap hari bekerja. Pilihan lain ialah pasang app Claude di VPS dan
pindahkan tugas berjadual ke sana.
