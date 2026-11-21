# Upserts one daily news brief into Supabase (table news_briefs, one row per brief_date).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\post_news_brief.ps1 -BriefFile <path-to-json>
# The JSON must look like:
#   {"brief_date":"2026-11-23","risk_level":"HIGH","summary":"...","events":[{"time":"21:30 MYT","title":"US CPI","impact":"HIGH"}]}
# Credentials come from .env in the repo root (SUPABASE_URL, SUPABASE_SERVICE_KEY). Never print them.
param([Parameter(Mandatory = $true)][string]$BriefFile)
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root '.env'
if (-not (Test-Path $envFile)) { throw "Missing $envFile. Copy .env.example to .env and fill in the service key." }
$cfg = @{}
foreach ($line in Get-Content $envFile) {
    if ($line -match '^\s*([A-Z_]+)\s*=\s*(.+?)\s*$') { $cfg[$Matches[1]] = $Matches[2].Trim('"') }
}
if (-not $cfg.SUPABASE_URL -or -not $cfg.SUPABASE_SERVICE_KEY) { throw ".env needs SUPABASE_URL and SUPABASE_SERVICE_KEY." }

$brief = Get-Content $BriefFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ($brief.brief_date -notmatch '^\d{4}-\d{2}-\d{2}$') { throw "brief_date must be YYYY-MM-DD." }
if (@('LOW', 'MEDIUM', 'HIGH') -notcontains $brief.risk_level) { throw "risk_level must be LOW, MEDIUM or HIGH." }
foreach ($e in @($brief.events)) {
    if (-not $e) { continue }
    if (@('LOW', 'MEDIUM', 'HIGH') -notcontains $e.impact) { throw "Event impact must be LOW, MEDIUM or HIGH: $($e.title)" }
    # The MT5 engine and the app time the avoid-trading window from "at" (UTC ISO 8601).
    if ($e.at -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$') { throw "Event needs at = YYYY-MM-DDTHH:MM:SSZ (UTC): $($e.title)" }
}

$body = [ordered]@{
    brief_date = $brief.brief_date
    risk_level = $brief.risk_level
    summary    = [string]$brief.summary
    events     = @($brief.events)
} | ConvertTo-Json -Depth 5 -Compress

$headers = @{
    apikey        = $cfg.SUPABASE_SERVICE_KEY
    Authorization = "Bearer $($cfg.SUPABASE_SERVICE_KEY)"
    Prefer        = 'resolution=merge-duplicates,return=minimal'
}
Invoke-RestMethod -Method Post -Uri "$($cfg.SUPABASE_URL)/rest/v1/news_briefs?on_conflict=brief_date" `
    -Headers $headers -ContentType 'application/json; charset=utf-8' `
    -Body ([Text.Encoding]::UTF8.GetBytes($body)) | Out-Null
"Posted news brief for $($brief.brief_date): risk $($brief.risk_level), $(@($brief.events).Count) events."
