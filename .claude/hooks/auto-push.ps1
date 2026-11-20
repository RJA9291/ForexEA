# Stop hook: commit and push any changes. Always exits 0 so it never blocks Claude.
$ErrorActionPreference = 'Continue'
$repo = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
Set-Location $repo

$changes = git status --porcelain
if (-not $changes) { exit 0 }

git add -A | Out-Null
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
git commit -q -m "auto: $stamp" | Out-Null
if ($LASTEXITCODE -ne 0) { [Console]::Error.WriteLine('auto-push: commit failed'); exit 0 }

git push -q origin main 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { [Console]::Error.WriteLine('auto-push: push failed (committed locally)') }
exit 0
