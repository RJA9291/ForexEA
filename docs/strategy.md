# XauTrendPullback: strategi

EA ini untuk XAUUSD sahaja. Ia buat analisis teknikal sendiri, pilih BUY atau SELL, dan buka trade tanpa campur tangan manusia.
Setiap peraturan ditulis dalam kod, jadi keputusan EA boleh diulang dan diuji dalam Strategy Tester.

## Aliran keputusan (setiap candle M15 baru)

1. **Trend H4**: EMA50 > EMA200 dan harga tutup di atas EMA200 → hanya cari BUY. Kalau sebaliknya → hanya cari SELL. Kalau bercampur → tiada trade.
2. **Struktur H1**: cari swing terakhir (fractal 3 bar). Untuk BUY: swing low → swing high (impulse). Untuk SELL: sebaliknya.
   - Impulse mesti ≥ 2.5 × ATR(H1).
   - Selepas swing tu, harga belum buat high/low baru dan belum pecah titik asal impulse.
3. **Zon pullback**: retracement Fibonacci 38.2%–61.8% dari impulse tu. Dalam istilah Elliott, ini zon entry gelombang 2 atau 4.
4. **Trigger M15**: candle M15 terakhir menyentuh zon dan tutup sebagai candle rejection, iaitu wick ≥ body atau candle engulfing ke arah trend.
5. **Entry**: satu market order.
   - SL di luar zon atau di luar wick candle, ditambah 0.2 × ATR.
   - TP sebenar order = **Final TP pada 4R**.
   - Trade dibatalkan kalau SL lebih lebar dari 2 × ATR.

## Checkpoint TP (satu order)

R = jarak entry ke SL asal. Bila harga terbaik (peak) sampai checkpoint, SL dikunci dan tak pernah diundur:

| Checkpoint | Paras | Tindakan |
|---|---|---|
| TP1 | 1R | SL ke breakeven (+1 pip) |
| TP2 | 2R | SL dikunci di TP1 |
| TP3 | 3R | SL dikunci di TP2 (pilihan: trailing ATR selepas ini) |
| Final TP | 4R | Order ditutup oleh broker |

Chart tunjuk status live: arah, tahap checkpoint, pip berjalan dan pip tertinggi (1 pip = $0.10), entry/SL/TP, dan sebab signal.
Sebab signal hilang kalau EA dimulakan semula semasa trade masih terbuka.

## Pengurusan risiko

| Peraturan | Default |
|---|---|
| Risiko setiap trade | 1% ekuiti (saiz lot dikira automatik) |
| Akaun kecil | Kalau lot 1% < lot minimum (0.01), EA guna 0.01 selagi rugi pada SL ≤ 10% ekuiti; kalau lebih, trade dilangkau |
| Maks trade sehari | 2 |
| Had rugi harian | 3% baki (dikira dari trade yang dah ditutup) |
| Satu posisi pada satu masa | Ya |
| Spread maksimum | 60 point |
| Sesi | 08:00–20:00 waktu server broker |
| Breakeven / kunci untung | Ikut checkpoint TP1–TP3 di atas |
| Trailing stop | Off (boleh hidupkan selepas TP3) |

Semua nilai di atas ialah input EA dan boleh diubah.

## Had yang perlu diketahui

- Tiada penapis berita. Data NFP, CPI dan FOMC boleh gerakkan gold dengan ganas, jadi pertimbangkan untuk matikan EA pada waktu tersebut.
- Had rugi harian tak kira kerugian yang belum ditutup (floating).
- Tiada strategi yang dijamin untung. Uji dalam Strategy Tester (mod "Every tick based on real ticks"), kemudian di akaun demo sekurang-kurangnya beberapa minggu, sebelum guna akaun sebenar.

## Cara pasang

1. Salin `Experts/XauTrendPullback.mq5` ke folder `MQL5/Experts/` dalam MT5 (MT5 → File → Open Data Folder).
2. Buka fail tu dalam MetaEditor dan tekan **Compile** (F7).
3. Lekatkan EA pada chart XAUUSD (timeframe chart tak penting), kemudian hidupkan **Algo Trading**.
