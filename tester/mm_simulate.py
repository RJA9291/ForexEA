"""Compare money-management (position sizing) schemes on the London breakout backtest trades.

Reads a tester log written by tester/run_london_escape.ps1 (default: variants/esc0_none.log), turns each trade
into an R-multiple (result / initial risk, from prices, so it does not depend on the lot size the backtest used),
then replays the same trade sequence under each sizing scheme on a $10,000 account.
Lot rounding and the broker's minimum lot are ignored, so small accounts behave worse than shown.

Usage: python -I tester/mm_simulate.py [path-to-log]
"""
import re
import sys
from pathlib import Path

LOG = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent / "variants" / "esc0_none.log"
START = 10_000.0

place = re.compile(r"(\d{4})\.\d\d\.\d\d \d\d:\d\d:\d\d\s+CTrade::OrderSend: (buy|sell) stop [\d.]+ XAUUSD at ([\d.]+) sl: ([\d.]+)")
trig = re.compile(r"(\d{4})\.\d\d\.\d\d \d\d:\d\d:\d\d\s+order \[#\d+ (buy|sell) stop [\d.]+ XAUUSD at ([\d.]+)\] triggered")
stop = re.compile(r"(?:stop loss|take profit) triggered #\d+ (?:buy|sell) [\d.]+ XAUUSD [\d.]+ sl: [\d.]+ tp: [\d.]+ \[#\d+ \w+ [\d.]+ XAUUSD at ([\d.]+)\]")
close = re.compile(r"CTrade::OrderSend: market (?:buy|sell) [\d.]+ position #\d+ XAUUSD \[done at ([\d.]+)\]")


def extract_trades(path):
    pending, trades, open_trade = {}, [], None
    for line in path.read_text(encoding="utf-8-sig", errors="ignore").splitlines():
        if m := place.search(line):
            pending[m.group(2)] = (float(m.group(3)), float(m.group(4)))
        elif m := trig.search(line):
            side = m.group(2)
            order_price, sl0 = pending[side]
            open_trade = (int(m.group(1)), 1 if side == "buy" else -1, float(m.group(3)), abs(order_price - sl0))
        elif open_trade and ((m := stop.search(line)) or (m := close.search(line))):
            year, d, entry, risk = open_trade
            trades.append((year, (float(m.group(1)) - entry) * d / risk))
            open_trade = None
    return trades


def simulate(trades, risk_fn):
    eq, peak, max_dd, hist = START, START, 0.0, []
    period_start = {}
    for year, r in trades:
        period = "2024-25" if year <= 2025 else "2026"
        period_start.setdefault(period, eq)
        pct = risk_fn(eq, peak, hist)
        eq += eq * pct / 100.0 * r
        hist.append((r, eq))
        peak = max(peak, eq)
        max_dd = max(max_dd, (peak - eq) / peak)
        if eq <= 0:
            return 0.0, 100.0, period_start, eq
    return eq, max_dd * 100, period_start, eq


def fixed(p):
    return lambda eq, peak, hist: p


def dd_ladder(eq, peak, hist):
    dd = (peak - eq) / peak
    return 0.25 if dd >= 0.20 else 0.5 if dd >= 0.10 else 1.0


def equity_filter(eq, peak, hist):
    if len(hist) < 20:
        return 1.0
    ma = sum(e for _, e in hist[-20:]) / 20
    return 1.0 if eq >= ma else 0.5


def anti_martingale(eq, peak, hist):
    wins = 0
    for r, _ in reversed(hist):
        if r <= 0:
            break
        wins += 1
    return 1.5 if wins >= 2 else 1.0


def martingale(eq, peak, hist):
    losses = 0
    for r, _ in reversed(hist):
        if r > 0:
            break
        losses += 1
    return min(1.0 * 2 ** losses, 8.0)


def main():
    trades = extract_trades(LOG)
    rs = [r for _, r in trades]
    n = len(rs)
    wins = sum(r > 0 for r in rs)
    mean = sum(rs) / n
    kelly = mean / (sum(r * r for r in rs) / n)          # fraction of equity per 1R of risk (continuous approximation)
    streak = cur = 0
    for r in rs:
        cur = cur + 1 if r <= 0 else 0
        streak = max(streak, cur)
    print(f"trades {n}, win rate {100 * wins / n:.1f}%, mean {mean:+.3f}R, longest losing streak {streak}, "
          f"full Kelly {100 * kelly:.1f}% risk per trade")

    schemes = [
        ("Fixed 0.5%", fixed(0.5)),
        ("Fixed 1%", fixed(1.0)),
        ("Fixed 2%", fixed(2.0)),
        ("Drawdown ladder 1% / 0.5% / 0.25%", dd_ladder),
        ("Equity-curve filter 1% / 0.5%", equity_filter),
        ("Anti-martingale 1% -> 1.5% after 2 wins", anti_martingale),
        (f"Half Kelly ({50 * kelly:.1f}%)", fixed(50 * kelly)),
        ("Martingale (double after loss, cap 8%)", martingale),
    ]
    print(f"{'Scheme':44} {'Final':>12} {'Return':>8} {'Max DD':>7} {'2024-25':>9} {'2026':>9}  Return/DD")
    for name, fn in schemes:
        final, dd, starts, _ = simulate(trades, fn)
        ret = 100 * (final / START - 1)
        s26 = starts.get("2026", final)
        r1 = 100 * (s26 / START - 1)
        r2 = 100 * (final / s26 - 1) if s26 > 0 else -100
        ratio = ret / dd if dd > 0 else float("inf")
        print(f"{name:44} {final:12,.0f} {ret:+7.1f}% {dd:6.1f}% {r1:+8.1f}% {r2:+8.1f}%  {ratio:5.2f}")


if __name__ == "__main__":
    main()
