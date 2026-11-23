"""Replay strategy-lab trades (market entries, one position at a time) under martingale sizing vs fixed risk.

Each trade becomes an R-multiple from prices (exit - entry) / initial risk, so the result does not depend on the
lot size the backtest used. Lot rounding and the broker minimum lot are ignored; a balance at or below zero is ruin.

Usage: python -I tester/mm_martingale.py tester/variants/lab_tokmat.log [more logs...]
"""
import re
import sys
from pathlib import Path

START = 10_000.0
entry_re = re.compile(r"(\d{4})\.\d\d\.\d\d \d\d:\d\d:\d\d\s+CTrade::OrderSend: market (buy|sell) [\d.]+ XAUUSD sl: ([\d.]+) tp: [\d.]+ \[done at ([\d.]+)\]")
exit_re = re.compile(r"(?:stop loss|take profit) triggered #\d+ (?:buy|sell) [\d.]+ XAUUSD [\d.]+ sl: [\d.]+ tp: [\d.]+ \[#\d+ \w+ [\d.]+ XAUUSD at ([\d.]+)\]")


def trades_from(path):
    out, open_t = [], None
    for line in Path(path).read_text(encoding="utf-8-sig", errors="ignore").splitlines():
        if m := entry_re.search(line):
            d = 1 if m.group(2) == "buy" else -1
            entry, sl = float(m.group(4)), float(m.group(3))
            open_t = (int(m.group(1)), d, entry, abs(entry - sl))
        elif open_t and (m := exit_re.search(line)):
            y, d, entry, risk = open_t
            if risk > 0:
                out.append((y, (float(m.group(1)) - entry) * d / risk))
            open_t = None
    return out


def run(trades, base, mult, cap):
    """Risk base% per trade; after each loss multiply risk by `mult` (capped at `cap`%); reset after a win."""
    eq, peak, dd, pct, max_pct, worst_streak, streak = START, START, 0.0, base, base, 0, 0
    for _, r in trades:
        eq += eq * pct / 100 * r
        if eq <= 0:
            return 0.0, 100.0, max_pct, worst_streak, True
        peak = max(peak, eq)
        dd = max(dd, (peak - eq) / peak)
        if r < 0:
            streak += 1
            pct = min(pct * mult, cap)
        else:
            streak = 0
            pct = base
        worst_streak = max(worst_streak, streak)
        max_pct = max(max_pct, pct)
    return eq, dd * 100, max_pct, worst_streak, False


def main():
    schemes = [
        ("Fixed 1% (no martingale)", 1.0, 1.0, 1.0),
        ("Martingale x1.5 after loss, cap 8%", 1.0, 1.5, 8.0),
        ("Martingale x2 after loss, cap 8%", 1.0, 2.0, 8.0),
        ("Martingale x2 after loss, cap 16%", 1.0, 2.0, 16.0),
        ("Martingale x2 after loss, no cap", 1.0, 2.0, 100.0),
    ]
    for log in sys.argv[1:]:
        t = extract = trades_from(log)
        wins = sum(r > 0 for _, r in t)
        print(f"\n== {Path(log).name}: {len(t)} trades, win {100 * wins / max(1, len(t)):.1f}%, mean {sum(r for _, r in t) / max(1, len(t)):+.3f}R")
        print(f"{'Scheme':38} {'Final':>10} {'Return':>8} {'Max DD':>7} {'Peak risk':>9}  Result")
        for name, base, mult, cap in schemes:
            final, dd, peak_pct, streak, ruined = run(t, base, mult, cap)
            print(f"{name:38} {final:10,.0f} {100 * (final / START - 1):+7.1f}% {dd:6.1f}% {peak_pct:8.1f}%  "
                  + ("RUIN (account wiped)" if ruined else f"longest losing streak {streak}"))


if __name__ == "__main__":
    main()
