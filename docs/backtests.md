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
