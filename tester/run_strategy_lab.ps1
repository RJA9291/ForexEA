# Backtests XauStrategyLab strategies over 2024-2026 and prints the EA's per-year / per-regime lines.
# MT5 must be closed first; it is reopened plainly at the end (the profile carries XauSignalEngine).
param([string[]]$Only = @())

$terminal  = "C:\Program Files\MetaTrader 5\terminal64.exe"
$dataId    = "D0E8209F77C8CF37AD8BF550E51FF075"
$agentLogs = "$env:APPDATA\MetaQuotes\Tester\$dataId\Agent-127.0.0.1-3000\logs"
$outDir    = Join-Path $PSScriptRoot "variants"
New-Item -ItemType Directory -Force $outDir | Out-Null
if (Get-Process terminal64 -ErrorAction SilentlyContinue) { throw "Close MetaTrader 5 first." }

# The tester reuses inputs from the previous run for anything not listed, so all inputs are explicit.
function Inputs([int]$strategy) {
    @(
        "InpStrategy=$strategy||1||1||3||N", "InpRiskPercent=1.0||1.0||0.1||5||N", "InpTPR=2.0||1||0.5||5||N",
        "InpBreakevenR=1.0||0||0.5||3||N", "InpSLBufferATR=0.2||0||0.1||1||N", "InpMinSLATR=0.3||0.1||0.1||1||N",
        "InpMaxSLATR=2.0||1||0.5||5||N", "InpMaxTradesPerDay=2||1||1||10||N", "InpStartHour=8||0||1||23||N",
        "InpEndHour=21||0||1||23||N", "InpMaxSpreadPoints=150||50||10||300||N", "InpSRTouchATR=0.15||0.05||0.05||1||N"
    )
}
$variants = [ordered]@{ "lab_bbma_reentry" = 1; "lab_bbma_extreme" = 2; "lab_sr_bounce" = 3 }

foreach ($name in $variants.Keys) {
    if ($Only.Count -gt 0 -and $Only -notcontains $name) { continue }
    $ini = Join-Path $outDir "$name.ini"
    (@("[Tester]", "Expert=XauStrategyLab.ex5", "Symbol=XAUUSD", "Period=M15", "Model=0", "Optimization=0",
       "FromDate=2024.01.02", "ToDate=2026.11.20", "ForwardMode=0", "Deposit=10000", "Currency=USD", "Leverage=100",
       "ExecutionMode=0", "ShutdownTerminal=1", "", "[TesterInputs]") + (Inputs $variants[$name])) | Set-Content $ini -Encoding ascii

    $p = Start-Process $terminal -ArgumentList "/config:`"$ini`"" -PassThru
    $p.WaitForExit(3600000) | Out-Null
    while (Get-Process terminal64 -ErrorAction SilentlyContinue) { Start-Sleep 10 }
    $log = Get-ChildItem $agentLogs | Sort-Object LastWriteTime | Select-Object -Last 1
    $text = Get-Content $log.FullName -Encoding Unicode
    $start = ($text | Select-String "XauStrategyLab spec" | Select-Object -Last 1).LineNumber
    if (-not $start) { "===== ${name}: no run found in agent log"; continue }
    $run = $text[($start - 1)..($text.Count - 1)]
    $run | Set-Content (Join-Path $outDir "$name.log") -Encoding utf8
    "===== $name"
    $run | Select-String "final balance|LAB .* year|LAB .* total|LAB .* regime|LAB outcome" | ForEach-Object { $_.Line -replace '^\S+\s+\d+\s+\S+\s+(\S+\s+\(\S+\)\s+\S+\s+\S+\s+)?', '' }
}

Start-Process $terminal
"MT5 reopened (engine loads from the chart profile)"
