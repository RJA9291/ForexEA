# Keputusan backtest

## 2026-11-20 — XauTrendPullback v1 (checkpoint TP), XAUUSD M15

Broker: InstaForex demo (`InstaForex-Server`). Tempoh: 2025-11-20 → 2026-11-20. Model: 1-minute OHLC (bukan real ticks).
Spec simbol: **saiz kontrak 500 auns/lot** (0.01 lot = $5 setiap $1 pergerakan), lot minimum 0.01, spread 80 point ($0.80), stops level 80.
Had spread EA dinaikkan ke 100 point untuk ujian ini (60 asal menyekat semua trade).

| Deposit | Trade | Keputusan |
|---|---|---|
| $100 | 0 | Tiada trade. 381 setup dilangkau sebab rugi 0.01 lot pada SL > 10% akaun |
| $10,000 (risiko 1%) | 150 | Baki akhir **$10,826.15 (+8.3%)** |

Butiran $10,000 (dikira dari log tester; untung kasar sebelum kos ialah $1,234.50, beza dengan baki akhir ialah kos dagangan):

| Metrik | Nilai |
|---|---|
| Kalah penuh (SL asal) | 75 |
| Tutup di breakeven (selepas TP1) | 40 |
| Tutup dengan untung dikunci (TP2/TP3) | 27 |
| Sampai Final TP (4R) | 8 |
| Profit factor (sebelum kos) | 1.17 |
| Max drawdown (baki tertutup) | 11.9% |
| Kalah berturut-turut terpanjang | 6 |
| Jarak SL | min $4.12, median $16.06, max $161.85 |

### Kesimpulan
- Strategi ada kelebihan kecil dalam tempoh ini, tapi nipis (PF 1.17 sebelum kos). Ini satu tempoh dan satu model sahaja; belum diuji dengan real ticks atau tempoh lain.
- Dengan kontrak 500 auns InstaForex, median SL $16 = **$80 rugi untuk 0.01 lot**. Akaun $100 tak boleh jalankan strategi ini dengan selamat.
- Daripada 21,000+ penilaian M15, kebanyakan berhenti di "tiada impulse sah" (14,690) — penapis struktur sangat ketat.

Konfigurasi: `tester/backtest_1y.ini` ($100), `tester/backtest_1y_10k.ini` ($10,000).

## 2026-11-21 — XauScalper v1, XAUUSD M5

Tempoh: 2026-08-20 → 2026-11-20. Model: **Every tick (dijana dari M1)** — real ticks InstaForex gagal dimuat turun (server hantar data kosong, sambungan terputus selepas 2 jam).

| Deposit | Trade | Keputusan |
|---|---|---|
| $100 | 0 | Tiada trade: 132 setup dilangkau (0.01 lot > 10% risiko), 269 SL > 60 pip |
| $10,000 (risiko 1%) | 58 | Baki akhir **$8,120.20 (−18.8%)**. **Kill switch aktif 2026-10-14** (ekuiti −20% dari puncak $10,176.75); tiada trade selepas itu |

Pecahan 58 trade ($10,000):

| Keluar | Bilangan |
|---|---|
| Kalah penuh (SL asal) | 37 |
| Time stop (rugi) | 1 |
| Breakeven selepas TP1 | 13 |
| Untung dikunci (TP2/TP3) | 5 |
| Final TP (4R) | 2 |

Jarak SL: min 33, median 50, max 60 pip. Spread 8 pip = ~16% daripada SL median.

### Kesimpulan
- Versi ini **rugi**: 38 kalah daripada 58 (66%), dan checkpoint tak cukup untuk menampung.
- Peraturan escape berfungsi seperti direka: losing streak hentikan 81 penilaian, kill switch hentikan EA sebelum kerugian melebihi 20%.
- Jangan jalankan versi ini di akaun sebenar. Perlu reka semula entry (contoh: penapis sesi London–NY sahaja, SL lebih ketat dengan broker spread rendah) dan uji semula.

## 2026-11-21 — XauScalper v2 (reka semula), perbandingan variasi

Model: Every tick (dijana dari M1). Deposit $10,000, risiko 1%, kill switch dimatikan supaya setiap variasi diukur sepanjang tempoh.
Skrip: `tester/run_scalper_variants.ps1`. Nota: Strategy Tester guna semula input run sebelumnya untuk input yang tak dinyatakan — skrip kini nyatakan semua input yang diuji.

| Variasi | ADX ≥22 | HA kuat | Sesi (server) | SL swing / maks | 3 bulan (Ogos–Nov 2026) | 1 tahun (Nov 2025–Nov 2026) |
|---|---|---|---|---|---|---|
| A v2 default | ya | ya | 15–19 | 3 / 45 pip | 1 trade, −0.9% | 1 trade, −0.9% |
| B tanpa ADX | tidak | ya | 15–19 | 3 / 45 | 1 trade, −0.9% | 1 trade, −0.9% |
| C tanpa HA kuat | ya | tidak | 15–19 | 3 / 45 | 6 trade, −2.7% | 17 trade, −7.5% |
| D sesi luas | ya | ya | 9–21 | 3 / 45 | 4 trade, −1.7% | 12 trade, −1.6% |
| E tetapan v1 | tidak | tidak | 9–21 | 5 / 60 | 112 trade, −24.6% | 357 trade, −47.4% |

### Kesimpulan
- **Tiada variasi yang untung.** Penapis v2 kurangkan kerugian hanya dengan mengurangkan bilangan trade, bukan dengan memilih trade yang lebih baik.
- Entry "pullback EMA20 + flip Heikin Ashi" tiada kelebihan pada kos InstaForex (spread 8 pip). Menambah lebih banyak penapis pada entry ini berisiko curve-fitting.
- Ujian out-of-sample tidak dijalankan kerana tiada variasi yang layak.

## 2026-11-21 — XauLondonBreakout v1, XAUUSD M5

Peraturan dari [mql5.com/en/blogs/post/777540](https://www.mql5.com/en/blogs/post/777540): julat Asia 03:00–08:00 server, buy/sell stop OCO pada 08:00 (+5 pip), SL hujung bertentangan (maks 0.6% harga), TP 2.5R, BE pada 1.5R, tutup 21:00, satu trade sehari, langkau julat <0.30% atau >1.60%.
Tempoh 2024-01-02 → 2026-11-20. Model: Every tick (dijana dari M1). Spread 80 point. Kill switch dimatikan untuk ukuran penuh.

| Deposit | Trade | Keputusan |
|---|---|---|
| $100 | 0 | 551 hari dilangkau: rugi 0.01 lot pada SL > 10% akaun (kontrak 500 auns) |
| $10,000 (risiko 1%) | 543 | Baki akhir **$16,856.98 (+68.6%)**, max drawdown (baki tertutup) **23.7%** |

| Tahun | Trade | Win rate | Net | PF |
|---|---|---|---|---|
| 2024 | 166 | 48.2% | +$642.00 | 1.12 |
| 2025 | 194 | 44.8% | +$1,385.48 | 1.15 |
| 2026 (hingga 20 Nov) | 183 | 49.7% | +$4,829.50 | 1.46 |

Hari dilangkau: julat sempit 69, julat lebar 51, harga terlalu dekat hujung julat (dalam stops level broker) 57, harga dah keluar julat pada 08:00 18.

### Kesimpulan
- Untung dalam ketiga-tiga tahun, tapi 2024–2025 nipis (PF 1.12–1.15); sebahagian besar untung datang dari 2026. Ini selari dengan kajian lain yang dapati strategi ini tak stabil merentasi tempoh.
- Drawdown 23.7% pada risiko 1% — risiko 0.5% lebih munasabah untuk permulaan.
- Belum diuji dengan real ticks (data tick InstaForex gagal dimuat turun) dan tanpa slippage sebenar semasa breakout.

## 2026-11-22 — London Breakout mengikut regime pasaran

Pengelas regime: `Include/XauRegime.mqh` (sama dalam backtest dan Signal Engine), dinilai pada 08:00 server dengan bar yang dah tutup.
HIGH_VOL = ATR D1 > 1.5× purata 100 hari; TREND_UP/DOWN = ADX H4 ≥ 25 + susunan EMA50/200 + harga di sebelah EMA50; RANGING = ADX H4 < 20; MIXED = selain itu.
Backtest yang sama seperti di atas (2024-01-02 → 2026-11-20, $10,000, risiko 1%, baki akhir $16,856.98 — tak berubah).

| Regime | Trade | Win | PF semua | PF 2024–25 | PF 2026 | Kesimpulan |
|---|---|---|---|---|---|---|
| RANGING | 78 | 53.8% | 1.90 | 1.11 (51) | 3.64 (27) | Untung dalam kedua-dua tempoh |
| MIXED | 178 | 50.6% | 1.26 | 1.07 (112) | 1.47 (66) | Untung dalam kedua-dua tempoh |
| TREND_UP | 168 | 37.5% | **0.82** | **0.79** (140) | **0.91** (28) | **Rugi dalam kedua-dua tempoh** (−$1,699) |
| HIGH_VOL | 57 | 59.6% | 2.10 | 3.69 (45) | 0.50 (12) | Tak konsisten |
| TREND_DOWN | 62 | 46.8% | 1.45 | 0.68 (12) | 1.57 (50) | Tak konsisten |

(Nombor dalam kurungan = bilangan trade.)

### Kesimpulan
- TREND_UP ialah satu-satunya regime yang rugi secara konsisten. Tanpa hari TREND_UP, untung bersih akan menjadi lebih kurang +$8,556 atas 375 trade — tapi ini dikira selepas melihat data, jadi anggap ia hipotesis untuk diuji ke hadapan, bukan fakta.
- Signal Engine kini menanda hari TREND_UP sebagai "sejarah lebih baik langkau" dan memaparkan statistik regime dalam app. Ia tak menyekat signal; keputusan kekal pada pengguna.
- HIGH_VOL dan TREND_DOWN mempunyai sampel kecil dalam satu tempoh, jadi tiada kesimpulan.
