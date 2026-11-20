# ForexEA

Expert Advisor (EA) forex untuk MetaTrader 5 (MQL5), fokus XAUUSD.

## Struktur
- `Experts/XauTrendPullback.mq5` — EA auto-trade gold: trend H4, pullback Fibonacci H1, rejection M15
- `Experts/XauScalper.mq5` — EA scalping gold: bias M15, pullback EMA20 M5, trigger Heikin Ashi
- `docs/strategy.md` — penerangan strategi, risiko dan cara pasang
- `docs/scalper.md` — strategi scalping, peraturan escape dan money management
- `docs/backtests.md` — keputusan backtest
- `tester/` — konfigurasi Strategy Tester

## Nota
Repo ini auto-push ke GitHub selepas setiap sesi kerja dengan Claude Code.
Jangan simpan nombor akaun broker, password atau API key dalam repo.
