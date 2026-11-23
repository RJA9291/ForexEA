# Prints today's (MYT) London breakout signal plus today's news and fundamental briefs as one JSON object,
# so the Devil's Advocate agent reads everything from a single command. Prints "null" fields when missing.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\today_signal.ps1
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\supabase_common.ps1"

$myt = (Get-Date).ToUniversalTime().AddHours(8)
$date = $myt.ToString('yyyy-MM-dd')
$fromUtc = $myt.Date.AddHours(-8).ToString('yyyy-MM-ddTHH:mm:ssZ')
$sig  = Invoke-Supabase -Method GET -Path "/rest/v1/signals?select=*&strategy=eq.LONDON_BREAKOUT&created_at=gte.$fromUtc&order=created_at.desc&limit=1"
$news = Invoke-Supabase -Method GET -Path "/rest/v1/news_briefs?select=risk_level,summary,events&brief_date=eq.$date"
$fund = Invoke-Supabase -Method GET -Path "/rest/v1/fundamental_briefs?select=bias,confidence,summary,drivers&brief_date=eq.$date"
$mkt  = Invoke-Supabase -Method GET -Path "/rest/v1/market?select=bid,ask,regime,regime_detail,updated_at"

[ordered]@{
    date_myt    = $date
    signal      = @($sig)[0]
    news        = @($news)[0]
    fundamental = @($fund)[0]
    market      = @($mkt)[0]
} | ConvertTo-Json -Depth 8
