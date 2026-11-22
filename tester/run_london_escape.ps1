# Backtests XauLondonBreakout with each escape mode (none, A, B, C) over 2024-2026 and prints the EA's own
# per-year / per-regime / outcome lines. MT5 must be closed first; it is reopened with the signal engine at the end.
param([string[]]$Only = @())

$terminal  = "C:\Program Files\MetaTrader 5\terminal64.exe"
$dataId    = "D0E8209F77C8CF37AD8BF550E51FF075"
$agentLogs = "$env:APPDATA\MetaQuotes\Tester\$dataId\Agent-127.0.0.1-3000\logs"
$outDir    = Join-Path $PSScriptRoot "variants"
New-Item -ItemType Directory -Force $outDir | Out-Null
if (Get-Process terminal64 -ErrorAction SilentlyContinue) { throw "Close MetaTrader 5 first." }

# The tester reuses inputs from the previous run for anything not listed, so all relevant inputs are explicit.
function Inputs([int]$mode) {
    @(
        "InpRiskPercent=1.0||1.0||0.1||5||N", "InpKillSwitchDDPct=100||20||1||100||N",
        "InpRangeStartHour=3||0||1||23||N", "InpRangeEndHour=8||0||1||23||N", "InpCloseHour=21||0||1||23||N",
        "InpMinRangePct=0.30||0.1||0.05||1||N", "InpMaxRangePct=1.60||1||0.1||3||N", "InpBufferPips=5||0||1||20||N",
        "InpMaxSLPct=0.60||0.2||0.1||2||N", "InpTPR=2.5||1||0.5||5||N", "InpBreakevenR=1.5||0||0.5||3||N",
        "InpEscapeMode=$mode||0||1||3||N", "InpTimeStopHours=3||1||1||12||N", "InpTimeStopMinR=0.5||0||0.1||2||N"
    )
}
$variants = [ordered]@{ "esc0_none" = 0; "escA_failed" = 1; "escB_time" = 2; "escC_reverse" = 3 }

foreach ($name in $variants.Keys) {
    if ($Only.Count -gt 0 -and $Only -notcontains $name) { continue }
    $ini = Join-Path $outDir "$name.ini"
    (@("[Tester]", "Expert=XauLondonBreakout.ex5", "Symbol=XAUUSD", "Period=M5", "Model=0", "Optimization=0",
       "FromDate=2024.01.02", "ToDate=2026.11.20", "ForwardMode=0", "Deposit=10000", "Currency=USD", "Leverage=100",
       "ExecutionMode=0", "ShutdownTerminal=1", "", "[TesterInputs]") + (Inputs $variants[$name])) | Set-Content $ini -Encoding ascii

    $p = Start-Process $terminal -ArgumentList "/config:`"$ini`"" -PassThru
    $p.WaitForExit(2400000) | Out-Null
    while (Get-Process terminal64 -ErrorAction SilentlyContinue) { Start-Sleep 10 }
    $log = Get-ChildItem $agentLogs | Sort-Object LastWriteTime | Select-Object -Last 1
    $text = Get-Content $log.FullName -Encoding Unicode
    $start = ($text | Select-String "XauLondonBreakout spec" | Select-Object -Last 1).LineNumber
    $run = $text[($start - 1)..($text.Count - 1)]
    $run | Set-Content (Join-Path $outDir "$name.log") -Encoding utf8
    "===== $name"
    $run | Select-String "final balance|XLB year|XLB total|XLB regime|Escape" | ForEach-Object { $_.Line -replace '^\S+\s+\d+\s+\S+\s+(\S+\s+\(\S+\)\s+\S+\s+\S+\s+)?', '' }
}

# Plain start: the Default profile already carries XauSignalEngine on its XAUUSD chart; a startup config
# would attach a second copy and every signal would be sent twice.
Start-Process $terminal
"MT5 reopened (engine loads from the chart profile)"
