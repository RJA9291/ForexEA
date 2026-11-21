# Writes the Devil's Advocate review onto today's signal (signals.critique). Only that column is touched,
# so the MT5 engine's own updates to the signal are unaffected.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\post_critique.ps1 -CritiqueFile <path-to-json>
# JSON shape:
#   {"signal_id":123,"caution":"LOW|MEDIUM|HIGH","summary":"...","against_buy":["..."],"against_sell":["..."]}
# Use tools\today_signal.ps1 to find today's signal_id.
param([Parameter(Mandatory = $true)][string]$CritiqueFile)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\supabase_common.ps1"

$c = Get-Content $CritiqueFile -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not ($c.signal_id -as [long])) { throw "signal_id is required." }
if (@('LOW', 'MEDIUM', 'HIGH') -notcontains $c.caution) { throw "caution must be LOW, MEDIUM or HIGH." }
if (-not $c.summary) { throw "summary is required." }
if (@($c.against_buy).Count + @($c.against_sell).Count -eq 0) { throw "Give at least one argument against a side." }

$critique = [ordered]@{
    caution      = $c.caution
    summary      = [string]$c.summary
    against_buy  = @($c.against_buy)
    against_sell = @($c.against_sell)
    written_at   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}
$body = @{ critique = $critique } | ConvertTo-Json -Depth 5 -Compress
Invoke-Supabase -Method PATCH -Path "/rest/v1/signals?id=eq.$([long]$c.signal_id)" -Body $body -Prefer 'return=minimal' | Out-Null
"Posted Devil's Advocate review on signal $($c.signal_id): caution $($c.caution)."
