"""How much of a strategy's loss is the broker's spread? Re-prices backtest trades at lower spreads.

Every round trip in the tester paid the full spread once (InstaForex gold: 80 points = $0.80). A broker with spread s
would have saved (0.80 - s) in price per trade, i.e. (0.80 - s) / initial_risk in R. This replays each trade's
R-multiple with that saving and reports profit factor and total R per spread level. Slippage and commission are
not modelled (raw-spread accounts usually charge a commission, roughly $5-7 per lot round trip).

Usage: python -I tester/spread_sensitivity.py <tester log> [more logs...]
"""
import re
import sys
from pathlib import Path

ACTUAL_SPREAD = 0.80
SPREADS = [0.80, 0.40, 0.20, 0.10]

entry_res = [
    # XauScalper: "XauScalper BUY 0.03 lots @2650.12 SL 2645.00 TP 2670.60 -> sent"
    re.compile(r"(\d{4})\.\d\d\.\d\d \d\d:\d\d:\d\d\s+XauScalper (BUY|SELL) [\d.]+ lots @([\d.]+) SL ([\d.]+) TP [\d.]+ -> sent"),
    # Strategy lab: "CTrade::OrderSend: market buy 0.03 XAUUSD sl: 2064.01 tp: 2081.74 [done at 2069.92]"
    re.compile(r"(\d{4})\.\d\d\.\d\d \d\d:\d\d:\d\d\s+CTrade::OrderSend: market (buy|sell) [\d.]+ XAUUSD sl: ([\d.]+) tp: [\d.]+ \[done at ([\d.]+)\]"),
]
exit_res = [
    re.compile(r"(?:stop loss|take profit) triggered #\d+ (?:buy|sell) [\d.]+ XAUUSD [\d.]+ sl: [\d.]+ tp: [\d.]+ \[#\d+ \w+ [\d.]+ XAUUSD at ([\d.]+)\]"),
    re.compile(r"CTrade::OrderSend: market (?:buy|sell) [\d.]+ position #\d+ XAUUSD \[done at ([\d.]+)\]"),
]


def read(path):
    raw = Path(path).read_bytes()
    text = raw.decode("utf-16") if raw[:2] in (b"\xff\xfe", b"\xfe\xff") else raw.decode("utf-8-sig", errors="ignore")
    # A copied agent log can hold several runs; keep the last one.
    cut = max(text.rfind("XauScalper spec"), text.rfind("XauStrategyLab spec"))
    return text[cut:] if cut > 0 else text


def trades(text):
    out, open_t = [], None
    for line in text.splitlines():
        m = entry_res[0].search(line)
        if m:
            d = 1 if m.group(2) == "BUY" else -1
            entry, sl = float(m.group(3)), float(m.group(4))
            open_t = (d, entry, abs(entry - sl))
            continue
        m = entry_res[1].search(line)
        if m and "position #" not in line:
            d = 1 if m.group(2) == "buy" else -1
            entry, sl = float(m.group(4)), float(m.group(3))
            open_t = (d, entry, abs(entry - sl))
            continue
        if open_t:
            for rx in exit_res:
                m = rx.search(line)
                if m:
                    d, entry, risk = open_t
                    if risk > 0:
                        out.append(((float(m.group(1)) - entry) * d / risk, risk))
                    open_t = None
                    break
    return out


def main():
    for log in sys.argv[1:]:
        t = trades(read(log))
        if not t:
            print(f"\n== {Path(log).name}: no trades parsed")
            continue
        med_risk = sorted(r for _, r in t)[len(t) // 2]
        print(f"\n== {Path(log).name}: {len(t)} trades, median SL ${med_risk:.2f} ({med_risk * 10:.0f} pip); "
              f"spread $0.80 = {100 * ACTUAL_SPREAD / med_risk:.0f}% of the median SL")
        print(f"{'Spread':>12} {'Win%':>6} {'PF':>6} {'Total R':>9} {'Mean R':>8}")
        for s in SPREADS:
            rs = [r + (ACTUAL_SPREAD - s) / risk for r, risk in t]
            gp = sum(r for r in rs if r > 0)
            gl = -sum(r for r in rs if r <= 0)
            print(f"{s * 100:>5.0f} pt ${s:.2f} {100 * sum(r > 0 for r in rs) / len(rs):6.1f} {gp / gl if gl else 0:6.2f} "
                  f"{sum(rs):+9.1f} {sum(rs) / len(rs):+8.3f}")


if __name__ == "__main__":
    main()
