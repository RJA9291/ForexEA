# Computes the weekly journal numbers from the signals table, so the journal agent never does arithmetic itself.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\journal_stats.ps1 [-WeekStart YYYY-MM-DD] [-OutFile path]
# WeekStart is the Monday (MYT) of the week to review; default = the latest trading week whose Friday has passed
# (this week on Saturday/Sunday, last week on Monday-Friday).
param([string]$WeekStart = '', [string]$OutFile = '')
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\supabase_common.ps1"

$BACKTEST_WIN_RATE = 47.5   # London breakout 2024-2026 backtest, see docs/backtests.md
$mytNow = (Get-Date).ToUniversalTime().AddHours(8)
if ($WeekStart) { $monday = [datetime]::ParseExact($WeekStart, 'yyyy-MM-dd', $null) }
else {
    $offset = ([int]$mytNow.DayOfWeek + 6) % 7          # days since this week's Monday (Sat = 5, Sun = 6)
    $monday = if ($offset -ge 5) { $mytNow.Date.AddDays(-$offset) } else { $mytNow.Date.AddDays(-$offset - 7) }
}
$fromUtc = $monday.AddHours(-8).ToString('yyyy-MM-ddTHH:mm:ssZ')
$toUtc   = $monday.AddDays(7).AddHours(-8).ToString('yyyy-MM-ddTHH:mm:ssZ')

function Summarize($rows) {
    $closed = @($rows | Where-Object { $_.status -like 'CLOSED_*' })
    $wins   = @($closed | Where-Object { $_.result_pips -gt 0 })
    $losses = @($closed | Where-Object { $_.result_pips -lt 0 })
    $pips   = ($closed | Measure-Object -Property result_pips -Sum).Sum
    [ordered]@{
        setups          = @($rows).Count
        no_trade_days   = @($rows | Where-Object { $_.status -eq 'NO_TRADE' }).Count
        cancelled       = @($rows | Where-Object { $_.status -eq 'CANCELLED' }).Count
        closed          = $closed.Count
        closed_tp       = @($closed | Where-Object { $_.status -eq 'CLOSED_TP' }).Count
        closed_sl       = @($closed | Where-Object { $_.status -eq 'CLOSED_SL' }).Count
        closed_be       = @($closed | Where-Object { $_.status -eq 'CLOSED_BE' }).Count
        closed_time     = @($closed | Where-Object { $_.status -eq 'CLOSED_TIME' }).Count
        win_rate        = if ($closed.Count) { [math]::Round(100.0 * $wins.Count / $closed.Count, 1) } else { $null }
        total_pips      = if ($closed.Count) { [math]::Round([double]$pips, 1) } else { 0 }
        avg_win_pips    = if ($wins.Count) { [math]::Round(($wins | Measure-Object result_pips -Average).Average, 1) } else { $null }
        avg_loss_pips   = if ($losses.Count) { [math]::Round(($losses | Measure-Object result_pips -Average).Average, 1) } else { $null }
        news_window     = @($rows | Where-Object { $_.escape.rule -eq 'NEWS_WINDOW' } | ForEach-Object { [ordered]@{ id = $_.id; status = $_.status; result_pips = $_.result_pips } })
        escape_a_flagged = @($rows | Where-Object { $_.escape.rule -eq 'A_FAILED_BREAKOUT' } | ForEach-Object { [ordered]@{ id = $_.id; status = $_.status; result_pips = $_.result_pips } })
    }
}

$select = 'id,created_at,status,side,result_pips,peak_pips,risk_pips,news_risk,escape'
$week = Invoke-Supabase -Method GET -Path "/rest/v1/signals?select=$select&created_at=gte.$fromUtc&created_at=lt.$toUtc&order=created_at"
$all  = Invoke-Supabase -Method GET -Path "/rest/v1/signals?select=$select&created_at=lt.$toUtc&order=created_at"

$result = [ordered]@{
    week_start         = $monday.ToString('yyyy-MM-dd')
    week_end           = $monday.AddDays(6).ToString('yyyy-MM-dd')
    backtest_win_rate  = $BACKTEST_WIN_RATE
    week               = Summarize $week
    since_start        = Summarize $all
    note               = 'Small samples: a week has at most 5 setups, so weekly win rates swing widely.'
}
$json = $result | ConvertTo-Json -Depth 6
if ($OutFile) { [IO.File]::WriteAllText($OutFile, $json, [Text.UTF8Encoding]::new($false)) }
$json
