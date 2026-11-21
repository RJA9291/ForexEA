# Shared Supabase helpers for the tools/ scripts. Dot-source it: . "$PSScriptRoot\supabase_common.ps1"
# Reads SUPABASE_URL and SUPABASE_SERVICE_KEY from the repo's .env. Never print the key.

function Get-SupabaseConfig {
    $envFile = Join-Path (Split-Path -Parent $PSScriptRoot) '.env'
    if (-not (Test-Path $envFile)) { throw "Missing $envFile. Copy .env.example to .env and fill in the service key." }
    $cfg = @{}
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*([A-Z_]+)\s*=\s*(.+?)\s*$') { $cfg[$Matches[1]] = $Matches[2].Trim('"') }
    }
    if (-not $cfg.SUPABASE_URL -or -not $cfg.SUPABASE_SERVICE_KEY) { throw ".env needs SUPABASE_URL and SUPABASE_SERVICE_KEY." }
    return $cfg
}

function Invoke-Supabase {
    param([string]$Method, [string]$Path, [string]$Body = '', [string]$Prefer = '')
    $cfg = Get-SupabaseConfig
    $headers = @{ apikey = $cfg.SUPABASE_SERVICE_KEY; Authorization = "Bearer $($cfg.SUPABASE_SERVICE_KEY)" }
    if ($Prefer) { $headers.Prefer = $Prefer }
    # Supabase rejects secret keys from browser-like User-Agents, and PowerShell 5.1 defaults to "Mozilla/5.0 ...".
    $params = @{ Method = $Method; Uri = "$($cfg.SUPABASE_URL)$Path"; Headers = $headers; UserAgent = 'ForexEA-tools/1.0' }
    if ($Body) { $params.ContentType = 'application/json; charset=utf-8'; $params.Body = [Text.Encoding]::UTF8.GetBytes($Body) }
    return Invoke-RestMethod @params
}
