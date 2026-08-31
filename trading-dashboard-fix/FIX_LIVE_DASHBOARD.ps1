#Requires -Version 5.1
<#
  Fix Live Dashboard showing 336 trades (restores 62 trades, July 29+).
  Run in PowerShell from ANY folder:
    irm https://raw.githubusercontent.com/khoanatran/git_test/cursor/revert-live-trade-merge-4361/trading-dashboard-fix/FIX_LIVE_DASHBOARD.ps1 | iex
  Or with explicit repo path:
    & .\FIX_LIVE_DASHBOARD.ps1 -RepoPath "C:\path\to\Trading_DashBoard"
#>
param(
  [string]$RepoPath = ""
)

$ErrorActionPreference = 'Stop'
$Base = 'https://raw.githubusercontent.com/khoanatran/git_test/cursor/revert-live-trade-merge-4361/patches'

function Find-DashboardRepo {
  $candidates = @(
    $RepoPath,
    (Join-Path $env:USERPROFILE 'Trading_DashBoard'),
    (Join-Path $env:USERPROFILE 'Documents\Trading_DashBoard'),
    'C:\Omen Trading\Trading_DashBoard',
    'C:\Trading_DashBoard'
  ) | Where-Object { $_ -and (Test-Path (Join-Path $_ 'data\trades-snapshot.json')) }
  if ($candidates.Count -gt 0) { return $candidates[0] }
  throw 'Trading_DashBoard not found. Pass -RepoPath "C:\path\to\Trading_DashBoard"'
}

$repo = Find-DashboardRepo
Write-Host "Fixing Live Dashboard in: $repo" -ForegroundColor Cyan
Set-Location $repo

$before = (Get-Content 'data\trades-snapshot.json' -Raw | ConvertFrom-Json).trades.Count
Write-Host "Current trades: $before"

Invoke-WebRequest "$Base/trades-snapshot-fixed-62.json" -OutFile 'data\trades-snapshot.json'
Invoke-WebRequest "$Base/live-session-fixed.json" -OutFile 'data\live-session.json'
Invoke-WebRequest "$Base/flags-fixed.json" -OutFile 'data\flags.json'
Invoke-WebRequest "$Base/trade-tags-fixed.json" -OutFile 'data\trade-tags.json'

$after = (Get-Content 'data\trades-snapshot.json' -Raw | ConvertFrom-Json).trades.Count
Write-Host "Fixed trades: $after (removed $($before - $after) archived May-July rows)" -ForegroundColor Green

& git add data/trades-snapshot.json data/live-session.json data/flags.json data/trade-tags.json
$status = & git status --porcelain -- data/
if ($status) {
  & git commit -m "Fix live dashboard: keep July 29+ trades only ($after trades)"
  & git push origin main
  Write-Host 'Pushed to GitHub. Restart the dashboard and refresh your browser.' -ForegroundColor Green
} else {
  Write-Host 'Data already fixed locally. Restart dashboard and hard-refresh browser (Ctrl+Shift+R).' -ForegroundColor Yellow
}
