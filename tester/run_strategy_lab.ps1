# Backtests XauStrategyLab strategies over 2024-2026 and prints the EA's per-year / per-regime lines.
# MT5 must be closed first; it is reopened plainly at the end (the profile carries XauSignalEngine).
param([string[]]$Only = @())

$terminal  = "C:\Program Files\MetaTrader 5\terminal64.exe"
$dataId    = "D0E8209F77C8CF37AD8BF550E51FF075"
$agentLogs = "$env:APPDATA\MetaQuotes\Tester\$dataId\Agent-127.0.0.1-3000\logs"
$outDir    = Join-Path $PSScriptRoot "variants"
New-Item -ItemType Directory -Force $outDir | Out-Null
if (Get-Process terminal64 -ErrorAction SilentlyContinue) { throw "Close MetaTrader 5 first." }

# The tester reuses inputs from the previous run for anything not listed, so every input is written for every run.
$defaults = [ordered]@{
    InpStrategy = 1; InpRiskPercent = 1.0; InpTPR = 2.0; InpBreakevenR = 1.0; InpSLBufferATR = 0.2; InpMinSLATR = 0.3
    InpMaxSLATR = 2.0; InpMaxTradesPerDay = 2; InpStartHour = 8; InpEndHour = 21; InpMaxSpreadPoints = 150
    InpSRTouchATR = 0.15; InpTkMinSLPips = 20; InpTkMaxSLPips = 80; InpTkTouchHours = 12; InpTkTF = 5   # 5 = M5, 1 = M1
}
function Inputs($over) {
    $v = [ordered]@{}; foreach ($k in $defaults.Keys) { $v[$k] = $defaults[$k] }
    foreach ($k in $over.Keys) { $v[$k] = $over[$k] }
    foreach ($k in $v.Keys) { "$k=$($v[$k])||$($v[$k])||0||$($v[$k])||N" }
}
# Tokmat variants were declared before any of them was run. Pass rule: PF > 1 in 2024-25 AND in 2026, with >= 30 trades in 2026.
$variants = [ordered]@{
    "lab_bbma_reentry"   = @{ InpStrategy = 1 }
    "lab_bbma_extreme"   = @{ InpStrategy = 2 }
    "lab_sr_bounce"      = @{ InpStrategy = 3 }
    "lab_tokmat"         = @{ InpStrategy = 4 }
    "tk_tp3"             = @{ InpStrategy = 4; InpTPR = 3.0 }
    "tk_sl30_50"         = @{ InpStrategy = 4; InpTkMinSLPips = 30; InpTkMaxSLPips = 50 }
    "tk_sl30_50_tp3"     = @{ InpStrategy = 4; InpTkMinSLPips = 30; InpTkMaxSLPips = 50; InpTPR = 3.0 }
    "tk_allday"          = @{ InpStrategy = 4; InpStartHour = 0; InpEndHour = 24 }
    "tk_m1_sl30_50"      = @{ InpStrategy = 4; InpTkTF = 1; InpTkMinSLPips = 30; InpTkMaxSLPips = 50 }
}

foreach ($name in $variants.Keys) {
    if ($Only.Count -gt 0 -and $Only -notcontains $name) { continue }
    $ini = Join-Path $outDir "$name.ini"
    (@("[Tester]", "Expert=XauStrategyLab.ex5", "Symbol=XAUUSD", "Period=M5", "Model=0", "Optimization=0",
       "FromDate=2024.01.02", "ToDate=2026.11.20", "ForwardMode=0", "Deposit=10000", "Currency=USD", "Leverage=100",
       "ExecutionMode=0", "ShutdownTerminal=1", "", "[TesterInputs]") + @(Inputs $variants[$name])) | Set-Content $ini -Encoding ascii

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
