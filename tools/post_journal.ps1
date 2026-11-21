# Upserts one weekly journal report (table journal_reports, one row per week_start).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\post_journal.ps1 -ReportFile <path-to-json>
# JSON shape: {"week_start":"YYYY-MM-DD","stats":{...output of journal_stats.ps1...},"summary":"...","lessons":["...","..."]}
param([Parameter(Mandatory = $true)][string]$ReportFile)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\supabase_common.ps1"

$r = Get-Content $ReportFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ($r.week_start -notmatch '^\d{4}-\d{2}-\d{2}$') { throw "week_start must be YYYY-MM-DD." }
if (-not $r.stats) { throw "stats is required (use the output of journal_stats.ps1)." }
if (-not $r.summary) { throw "summary is required." }

$body = [ordered]@{
    week_start = $r.week_start
    stats      = $r.stats
    summary    = [string]$r.summary
    lessons    = @($r.lessons)
} | ConvertTo-Json -Depth 8 -Compress
Invoke-Supabase -Method POST -Path '/rest/v1/journal_reports?on_conflict=week_start' -Body $body -Prefer 'resolution=merge-duplicates,return=minimal' | Out-Null
"Posted journal for week starting $($r.week_start)."
