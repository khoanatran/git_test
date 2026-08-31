#Requires -Version 5.1
<#
  Drop archived May–July trades from Live Dashboard (keeps July 29+ only).
  Usage (from Trading_DashBoard root):
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/fix-live-dashboard-now.ps1
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $ProjectRoot

Write-Host 'Fixing Live Dashboard data (July 29+ trades only)...' -ForegroundColor Cyan
npx --yes tsx scripts/fix-live-dashboard-now.ts
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ''
Write-Host 'Committing and pushing to GitHub...' -ForegroundColor Cyan
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
  Write-Warning 'Git not found — data is fixed locally. Restart the dashboard and refresh the browser.'
  exit 0
}

& git add data/trades-snapshot.json data/live-session.json data/flags.json data/trade-tags.json
$status = & git status --porcelain -- data/
if ($status) {
  & git commit -m "Fix live dashboard: keep July 29+ trades only"
  & git push origin main
  Write-Host 'Pushed. Refresh Live Dashboard in the browser.' -ForegroundColor Green
} else {
  Write-Host 'No data changes to commit — refresh the browser or clear localStorage.' -ForegroundColor Yellow
}
