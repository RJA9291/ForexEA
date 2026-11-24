# Builds a zip with everything MT5 on a Windows VPS needs to run XauSignalEngine and XauScalper.
# The zip holds the Supabase service key (aurum.env), so it is written outside the repo and must not be shared.
# Usage: powershell -ExecutionPolicy Bypass -File tools\package_vps.ps1 [-Out <folder>]
param([string]$Out = [Environment]::GetFolderPath('Desktop'))

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$data = Get-ChildItem "$env:APPDATA\MetaQuotes\Terminal" -Directory |
        Where-Object { Test-Path "$($_.FullName)\MQL5\Experts\XauScalper.ex5" } | Select-Object -First 1
if (-not $data) { throw 'No MT5 data folder with XauScalper.ex5 found under %APPDATA%\MetaQuotes\Terminal.' }
$mql = Join-Path $data.FullName 'MQL5'

$stage = Join-Path $env:TEMP "forexea-vps-$(Get-Date -Format yyyyMMddHHmmss)"
$files = @(
    @{ From = "$repo\Experts\XauSignalEngine.mq5";   To = 'MQL5\Experts\XauSignalEngine.mq5' },
    @{ From = "$mql\Experts\XauSignalEngine.ex5";    To = 'MQL5\Experts\XauSignalEngine.ex5' },
    @{ From = "$repo\Experts\XauScalper.mq5";        To = 'MQL5\Experts\XauScalper.mq5' },
    @{ From = "$mql\Experts\XauScalper.ex5";         To = 'MQL5\Experts\XauScalper.ex5' },
    @{ From = "$repo\Indicators\XauSetupView.mq5";   To = 'MQL5\Indicators\XauSetupView.mq5' },
    @{ From = "$mql\Indicators\XauSetupView.ex5";    To = 'MQL5\Indicators\XauSetupView.ex5' },
    @{ From = "$repo\Include\AurumRest.mqh";         To = 'MQL5\Include\AurumRest.mqh' },
    @{ From = "$repo\Include\XauRegime.mqh";         To = 'MQL5\Include\XauRegime.mqh' },
    @{ From = "$repo\Include\XauStats.mqh";          To = 'MQL5\Include\XauStats.mqh' },
    @{ From = "$mql\Files\aurum.env";                To = 'MQL5\Files\aurum.env' },
    @{ From = "$repo\docs\vps.md";                   To = 'BACA-SAYA-vps.md' }
)
foreach ($f in $files) {
    if (-not (Test-Path $f.From)) { throw "Missing $($f.From)" }
    $dest = Join-Path $stage $f.To
    New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
    Copy-Item $f.From $dest
}

$zip = Join-Path $Out 'ForexEA-VPS.zip'
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path "$stage\*" -DestinationPath $zip
Remove-Item -Recurse -Force $stage
Write-Output "Wrote $zip ($($files.Count) files). It contains the Supabase service key: copy it only to your own VPS."
