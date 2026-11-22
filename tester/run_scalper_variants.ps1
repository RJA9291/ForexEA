# Runs XauScalper input variants through the MT5 Strategy Tester and prints final balance per variant.
# MT5 must be closed first: the tester cannot start while the terminal is open on the same data folder.
param(
    [string]$From = "2026.08.20",
    [string]$To = "2026.11.20",
    [string[]]$Only = @()
)

$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$dataId = "D0E8209F77C8CF37AD8BF550E51FF075"
$agentLogs = "$env:APPDATA\MetaQuotes\Tester\$dataId\Agent-127.0.0.1-3000\logs"
$outDir = Join-Path $PSScriptRoot "variants"
New-Item -ItemType Directory -Force $outDir | Out-Null

# The tester reuses inputs from the previous run for anything not listed, so every
# variant states all varied inputs explicitly. Kill switch is disabled (100%) so each
# variant is measured over the whole period.
function Inputs([bool]$adx, [bool]$strong, [int]$start, [int]$end, [int]$swing, [int]$maxSl) {
    return @(
        "InpKillSwitchDDPct=100||20||1||100||N",
        "InpUseADX=$($adx.ToString().ToLower())||false||0||true||N",
        "InpRequireStrongHA=$($strong.ToString().ToLower())||false||0||true||N",
        "InpStartHour=$start||0||1||24||N", "InpEndHour=$end||0||1||24||N",
        "InpSwingBars=$swing||1||1||10||N", "InpMaxSLPips=$maxSl||10||1||100||N"
    )
}
$variants = [ordered]@{
    "A_v2_default"   = Inputs $true  $true  15 19 3 45
    "B_no_adx"       = Inputs $false $true  15 19 3 45
    "C_no_strong_ha" = Inputs $true  $false 15 19 3 45
    "D_wide_session" = Inputs $true  $true  9  21 3 45
    "E_v1_settings"  = Inputs $false $false 9  21 5 60
}

if (Get-Process terminal64 -ErrorAction SilentlyContinue) { throw "Close MetaTrader 5 first." }

foreach ($name in $variants.Keys) {
    if ($Only.Count -gt 0 -and $Only -notcontains $name) { continue }
    $ini = Join-Path $outDir "$name.ini"
    $lines = @(
        "[Tester]", "Expert=XauScalper.ex5", "Symbol=XAUUSD", "Period=M5", "Model=0", "Optimization=0",
        "FromDate=$From", "ToDate=$To", "ForwardMode=0", "Deposit=10000", "Currency=USD", "Leverage=100",
        "ExecutionMode=0", "ShutdownTerminal=1", "", "[TesterInputs]"
    ) + $variants[$name]
    $lines | Set-Content $ini -Encoding ascii

    $p = Start-Process $terminal -ArgumentList "/config:`"$ini`"" -PassThru
    $p.WaitForExit(900000) | Out-Null
    $log = Get-ChildItem $agentLogs | Sort-Object LastWriteTime | Select-Object -Last 1
    $text = Get-Content $log.FullName -Encoding Unicode
    $start = ($text | Select-String "XauScalper spec" | Select-Object -Last 1).LineNumber
    $run = $text[($start - 1)..($text.Count - 1)]
    Copy-Item $log.FullName (Join-Path $outDir "$name.log") -Force

    $balance = ($run | Select-String "final balance ([\d.]+)" | Select-Object -Last 1).Matches.Groups[1].Value
    $opened = ($run | Select-String "lots @.*-> sent").Count
    $tps = ($run | Select-String "take profit triggered").Count
    "{0,-16} balance {1,10}  trades {2,4}  finalTP {3,3}" -f $name, $balance, $opened, $tps
}
