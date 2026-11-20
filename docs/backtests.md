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
