# XauScalper: strategi scalping XAUUSD

EA scalping untuk gold. Fail: `Experts/XauScalper.mq5` (magic 920101, berbeza dari XauTrendPullback supaya boleh jalan serentak).

## Aliran keputusan (setiap candle M5 baru)

1. **Bias M15**: EMA50 > EMA200 dan harga tutup di atas EMA50 → hanya BUY. Sebaliknya → hanya SELL. Selain itu → tiada trade.
2. **Pullback M5**: dalam 3 candle terakhir, harga turun (atau naik untuk SELL) ke dalam 0.3 × ATR dari EMA20.
3. **Trigger Heikin Ashi**: candle HA sebelumnya lawan arah, candle HA terakhir ikut arah, dan candle sebenar tutup di sebelah betul EMA20.
4. **SL**: di luar swing 5 candle + 0.1 × ATR. Minimum 20 pip, maksimum 60 pip (1 pip = $0.10). Lebih lebar → dilangkau.
5. **Checkpoint TP** (satu order): TP1 1R → BE, TP2 2R → kunci TP1, TP3 3R → kunci TP2, Final TP 4R.

## Peraturan "escape"

| Peraturan | Default |
|---|---|
| Time stop | Tutup kalau TP1 tak dicapai dalam 12 candle M5 (1 jam) |
| Had rugi harian | 3% baki |
| Kalah berturut-turut | Berhenti untuk hari itu selepas 3 kalah |
| Kill switch | Berhenti sepenuhnya kalau ekuiti jatuh 20% dari puncak. Reset: padam Global Variable `XSC_peak_920101` (F3 dalam MT5) |
| Penapis ATR spike | Langkau kalau ATR M5 > 2.5 × purata 100 candle (berita/volatiliti melampau) |
| Spread | Maks 100 point, dan spread mesti ≤ 25% jarak SL |
| Sesi | 09:00–21:00 waktu server broker |
| Maks trade sehari | 6 |

## Money management

- Risiko 1% ekuiti setiap trade.
- Akaun kecil: guna 0.01 lot kalau rugi pada SL ≤ 10% ekuiti; kalau lebih, langkau.
- Tiada martingale, tiada grid, satu posisi pada satu masa.

## Nota InstaForex

Kontrak gold 500 auns: 0.01 lot = $5 setiap $1. SL 20 pip ($2) = rugi $10 untuk 0.01 lot.
Dengan akaun $100 dan had 10%, hanya setup dengan SL minimum (20 pip) yang lepas.

## Ujian

- Backtest real ticks 3 bulan: `tester/scalper_3m_100.ini`, `tester/scalper_3m_10k.ini` (MT5 mesti ditutup dulu).
- Demo live: lekat EA pada chart XAUUSD (sebarang timeframe), hidupkan Algo Trading.

## Forward test demo (bermula 2026-11-23)

- Akaun demo InstaForex baharu, baki $10,000, hedging. Nombor akaun tidak disimpan di sini.
- XauScalper dilekat pada XAUUSD M5 melalui profil carta MT5 (`chart06.chr`), magic 920101. Signal Engine kekal pada XAUUSD M15.
- Input: risiko 1%, maks 6 trade sehari, had rugi harian 3%, berhenti selepas 3 kalah berturut-turut, kill switch 20%,
  `InpUseADX=false`, `InpRequireStrongHA=false`, SL maks 60 pip, sesi 24 jam (`InpStartHour=0`, `InpEndHour=24`,
  diubah 2026-11-23 atas permintaan; penapis spread masih menyekat waktu rollover yang spreadnya melebar).
- Jangkaan: backtest rugi pada spread $0.80 (lihat `tester/spread_sensitivity.py`). Tujuan demo ialah membandingkan
  keputusan pasaran sebenar dengan backtest, bukan membuktikan untung.
- Selepas tukar akaun, MT5 mematikan Algo Trading; butang mesti dihidupkan semula secara manual.

### Clearance dan app (ditambah 2026-11-23, v2.10)

- Signal Engine menulis konteks clearance ke Global Variables MT5 setiap beberapa saat (`AURUM_ctx_*`, lihat
  `Include/AurumRest.mqh`): tetingkap berita, regime, bias fundamental dan keyakinannya.
- Sebelum setiap entry, scalper menjalankan clearance sendiri:
  - **Berita** dalam tetingkap HIGH-impact → NOT_CLEARED (hard stop, trade dilangkau).
  - **Fundamental** bertentangan dengan keyakinan HIGH → gagal lembut.
  - **Konteks engine** tiada atau lebih lama dari 5 minit → gagal lembut.
  - 1 gagal lembut = CAUTION (masih trade), 2 = NOT_CLEARED (dilangkau). Regime direkod sahaja.
  - Devil's Advocate tidak digunakan: ia mengulas setup London sahaja.
- Tiada syarat ini diuji dengan backtest untuk scalper. Demo mengumpul trade CLEARED dan CAUTION supaya keputusan
  kedua-dua kumpulan boleh dibandingkan (tab Sejarah dalam app).
- Setiap trade dihantar ke jadual `signals` dengan `strategy = M5_SCALPER`; status dikemas kini pada TP1/TP2/TP3
  dan setiap 60 saat, dan keputusan direkod bila posisi ditutup (juga selepas MT5 restart, melalui `XSC_sig_<ticket>`).
- Money management London, jurnal mingguan dan Devil's Advocate kini membaca `strategy = LONDON_BREAKOUT` sahaja,
  supaya trade scalper tidak mengubah statistik signal London.
- Strategy Tester tidak terjejas: clearance dan penghantaran dimatikan semasa backtest.

### Paparan setup (Indicators/XauSetupView.mq5, ditambah 2026-11-24)

- Indikator pada carta XAUUSD M5 (`chart06.chr`): EMA20 M5 (ungu), EMA50/EMA200 M15 (oren/biru), candle Heikin Ashi,
  dan anak panah pada setiap candle tertutup di mana syarat entry scalper lengkap (bias, pullback, HA flip, had SL,
  spread dianggap $0.80, penapis ATR). Anak panah tidak mengambil kira posisi terbuka, had harian atau clearance.
- Dengan `InpShowHA=true` candle biasa disembunyikan; warna asal dipulihkan bila indikator dibuang.
