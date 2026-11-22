# Money management

Diuji pada 543 trade London Breakout yang sama (backtest 2024-01-02 → 2026-11-20). Setiap trade ditukar kepada
R-multiple (untung/rugi ÷ risiko awal), kemudian dimain semula di bawah setiap kaedah saiz lot pada akaun $10,000.
Skrip: `tester/mm_simulate.py`. Pembundaran lot dan lot minimum diabaikan, jadi akaun kecil akan lebih teruk daripada ini.
Semakan: "Fixed 1%" dalam simulasi = $17,450, berbanding $16,857 dalam MT5 (beza dari pembundaran lot dan kos).

Statistik trade: win rate 47.9%, purata +0.110R setiap trade, kalah berturut-turut terpanjang 9, Kelly penuh 7.4%.

| Kaedah | Baki akhir | Pulangan | Max DD | 2024–25 | 2026 | Pulangan ÷ DD |
|---|---|---|---|---|---|---|
| Tetap 0.5% | $13,342 | +33.4% | 12.0% | +11.4% | +19.7% | 2.79 |
| Tetap 1% | $17,450 | +74.5% | 22.9% | +22.6% | +42.3% | 3.25 |
| Tetap 2% | $28,148 | +181.5% | 41.8% | +43.1% | +96.7% | 4.35 |
| Tangga drawdown 1% / 0.5% / 0.25% | $16,409 | +64.1% | 17.4% | +17.6% | +39.5% | 3.69 |
| **Penapis kurva ekuiti 1% / 0.5%** | **$18,061** | **+80.6%** | **15.3%** | **+27.7%** | **+41.4%** | **5.27** |
| Anti-martingale 1% → 1.5% selepas 2 menang | $18,717 | +87.2% | 23.9% | +27.4% | +46.9% | 3.65 |
| Separuh Kelly (3.7%) | $53,276 | +432.8% | 65.5% | +66.8% | +219.4% | 6.61 |
| Martingale (gandakan selepas kalah, had 8%) | $47,003 | +370.0% | 47.2% | +128.9% | +105.3% | 7.84 |

## Kaedah yang dipilih: penapis kurva ekuiti
Risiko penuh (input `InpRiskPercent`) bila ekuiti signal berada di atas purata 20 signal terakhirnya; separuh bila di bawah.
Berbanding tetap 1%: pulangan lebih tinggi **dan** drawdown lebih rendah, dalam kedua-dua tempoh. Ia juga peraturan yang
diterbitkan secara umum (LuxAlgo, Macro Ops), bukan parameter yang dicari dari data ini — hanya satu tetapan yang diuji.

Signal Engine mengira ini daripada keputusan sebenar signal yang ditutup (bukan baki akaun broker), dan memaparkan risiko
dicadangkan dalam app. Sebelum 20 signal ditutup, saiz penuh digunakan.

## Kenapa bukan martingale atau Kelly
- **Martingale** nampak untung di sini hanya kerana kalah berturut-turut terpanjang dalam sampel ialah 9. Drawdown 47% sudah
  separuh akaun; jujukan kalah lebih panjang (yang pasti berlaku akhirnya) menghabiskan akaun. Untuk "recover" kerugian,
  saiz mesti dikecilkan, bukan dibesarkan: rugi 20% memerlukan untung 25% untuk pulih; rugi 50% memerlukan 100%.
- **Separuh Kelly** bergantung pada anggaran edge yang tepat; edge kita nipis (+0.11R) dan berbeza antara tahun.
  Drawdown 65% tidak boleh diterima.

## "Maximize" bila untung
Risiko sebagai peratus ekuiti sudah menambah saiz lot secara automatik bila akaun berkembang (compounding) dan
mengecilkannya bila akaun menyusut. Kemas kini `InpAccountSize` dalam EA bila baki akaun sebenar berubah.
Anti-martingale (1.5% selepas 2 menang) menambah sedikit pulangan tapi drawdown lebih tinggi; tidak digunakan.

## Sumber
- [Martingale versus a bigger fixed lot: 55 strategies (MQL5)](https://www.mql5.com/en/blogs/post/773495)
- [Fixed fractional (LuxAlgo)](https://www.luxalgo.com/library/concept/fixed-fractional.md)
- [Equity-curve-based throttling (LuxAlgo)](https://www.luxalgo.com/library/concept/equity-curve-based-throttling.md)
- [Position Sizing and Drawdowns (Macro Ops)](https://operators.macro-ops.com/wp-content/uploads/2017/06/Position-Sizing-and-Drawdowns.pdf)
- [Risk of ruin in trading (EarnForex)](https://www.earnforex.com/guides/risk-of-ruin-in-trading/)
- [On drawdown-modulated feedback control in stock trading (arXiv)](https://arxiv.org/pdf/1710.01503)
