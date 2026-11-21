# Upserts one daily fundamental brief for gold (table fundamental_briefs, one row per brief_date).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\post_fundamental.ps1 -BriefFile <path-to-json>
# JSON shape:
#   {"brief_date":"YYYY-MM-DD","bias":"BULLISH|NEUTRAL|BEARISH","confidence":"LOW|MEDIUM|HIGH","summary":"...",
#    "drivers":[{"factor":"US 10Y real yield","reading":"1.85%, down 6bp","effect":"BULLISH"}],"sources":["https://..."]}
param([Parameter(Mandatory = $true)][string]$BriefFile)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\supabase_common.ps1"

$b = Get-Content $BriefFile -Raw -Encoding UTF8 | ConvertFrom-Json
$levels = @('BULLISH', 'NEUTRAL', 'BEARISH')
if ($b.brief_date -notmatch '^\d{4}-\d{2}-\d{2}$') { throw "brief_date must be YYYY-MM-DD." }
if ($levels -notcontains $b.bias) { throw "bias must be BULLISH, NEUTRAL or BEARISH." }
if (@('LOW', 'MEDIUM', 'HIGH') -notcontains $b.confidence) { throw "confidence must be LOW, MEDIUM or HIGH." }
if (-not $b.summary) { throw "summary is required." }
foreach ($d in @($b.drivers)) {
    if ($d -and $levels -notcontains $d.effect) { throw "driver effect must be BULLISH, NEUTRAL or BEARISH: $($d.factor)" }
}
if (@($b.sources).Count -lt 2) { throw "At least two sources are required." }

$body = [ordered]@{
    brief_date = $b.brief_date
    bias       = $b.bias
    confidence = $b.confidence
    summary    = [string]$b.summary
    drivers    = @($b.drivers)
    sources    = @($b.sources)
} | ConvertTo-Json -Depth 6 -Compress
Invoke-Supabase -Method POST -Path '/rest/v1/fundamental_briefs?on_conflict=brief_date' -Body $body -Prefer 'resolution=merge-duplicates,return=minimal' | Out-Null
"Posted fundamental brief for $($b.brief_date): $($b.bias) ($($b.confidence) confidence)."
