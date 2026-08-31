#Requires -Version 5.1
<#
  Fix Live Dashboard showing 336 trades (restores 62 trades, July 29+).

  INSTANT FIX (PowerShell, any folder):
    irm https://raw.githubusercontent.com/khoanatran/git_test/cursor/revert-live-trade-merge-4361/trading-dashboard-fix/FIX_LIVE_DASHBOARD.ps1 | iex

  Local-only (no git push — fixes UI immediately, blocks GitHub re-sync):
    irm ... | iex; FIX_LOCAL_ONLY=1

  With explicit repo path:
    & .\FIX_LIVE_DASHBOARD.ps1 -RepoPath "C:\path\to\Trading_DashBoard"
#>
param(
  [string]$RepoPath = "",
  [switch]$LocalOnly
)

$ErrorActionPreference = 'Stop'
$Base = 'https://raw.githubusercontent.com/khoanatran/git_test/cursor/revert-live-trade-merge-4361/patches'
if ($env:FIX_LOCAL_ONLY -eq '1') { $LocalOnly = $true }

function Find-DashboardRepo {
  $candidates = @(
    $RepoPath,
    (Join-Path $env:USERPROFILE 'Trading_DashBoard'),
    (Join-Path $env:USERPROFILE 'Documents\Trading_DashBoard'),
    (Join-Path $env:USERPROFILE 'source\repos\Trading_DashBoard'),
    (Join-Path $env:USERPROFILE 'Projects\Trading_DashBoard'),
    'C:\Omen Trading\Trading_DashBoard',
    'C:\Trading_DashBoard',
    'D:\Trading_DashBoard'
  ) | Where-Object { $_ -and (Test-Path (Join-Path $_ 'data\trades-snapshot.json')) }

  if ($candidates.Count -gt 0) { return $candidates[0] }

  # Search common drives (shallow)
  foreach ($root in @('C:\', 'D:\')) {
    if (-not (Test-Path $root)) { continue }
    $hit = Get-ChildItem -Path $root -Filter 'trades-snapshot.json' -Recurse -Depth 5 -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -match '\\Trading_DashBoard\\data\\trades-snapshot\.json$' } |
      Select-Object -First 1
    if ($hit) { return $hit.Directory.Parent.FullName }
  }

  throw @"
Trading_DashBoard not found.

Run again with your repo path:
  `$script = irm 'https://raw.githubusercontent.com/khoanatran/git_test/cursor/revert-live-trade-merge-4361/trading-dashboard-fix/FIX_LIVE_DASHBOARD.ps1'
  `$script | Out-File fix.ps1; .\fix.ps1 -RepoPath 'C:\path\to\Trading_DashBoard'
"@
}

function Disable-GitHubSync {
  param([string]$RepoRoot)
  $envFile = Join-Path $RepoRoot '.env.local'
  $line = 'GITHUB_BACKUP_ENABLED=false'
  if (Test-Path $envFile) {
    $content = Get-Content $envFile -Raw
    if ($content -match 'GITHUB_BACKUP_ENABLED\s*=') {
      $content = $content -replace 'GITHUB_BACKUP_ENABLED\s*=.*', $line
    } else {
      $content = "$content`n$line`n"
    }
    Set-Content -Path $envFile -Value $content -NoNewline
  } else {
    Set-Content -Path $envFile -Value "$line`n"
  }
  Write-Host "Set $envFile -> GITHUB_BACKUP_ENABLED=false (stops re-pulling 336 trades from GitHub)" -ForegroundColor Yellow
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
Write-Host "Fixed local data: $after trades (removed $($before - $after) archived May-July rows)" -ForegroundColor Green

Disable-GitHubSync -RepoRoot $repo

if ($LocalOnly) {
  Write-Host @"

LOCAL FIX APPLIED ($after trades).
1. Close the dashboard app completely
2. Start it again
3. Hard-refresh browser: Ctrl+Shift+R

GitHub main still has 336 trades; sync is disabled so they will not come back.
To fix GitHub permanently later: git add data/ && git commit -m "Fix live dashboard" && git push
"@ -ForegroundColor Green
  exit 0
}

& git add data/trades-snapshot.json data/live-session.json data/flags.json data/trade-tags.json
$status = & git status --porcelain -- data/
if ($status) {
  & git commit -m "Fix live dashboard: keep July 29+ trades only ($after trades)"
  try {
    & git push origin main
    Write-Host 'Pushed to GitHub. Restart dashboard and hard-refresh (Ctrl+Shift+R).' -ForegroundColor Green
    # Re-enable sync after successful push if we disabled it in .env.local
    $envFile = Join-Path $repo '.env.local'
    if (Test-Path $envFile) {
      (Get-Content $envFile) -replace 'GITHUB_BACKUP_ENABLED=false', 'GITHUB_BACKUP_ENABLED=true' | Set-Content $envFile
    }
  } catch {
    Write-Host "Push failed: $_" -ForegroundColor Red
    Write-Host @"

Local fix is still applied ($after trades). GitHub sync stays OFF.
Restart dashboard + Ctrl+Shift+R — you should see 62 trades now.
"@ -ForegroundColor Yellow
  }
} else {
  Write-Host @"

Data files already matched fix. Restart dashboard + Ctrl+Shift+R.
If you still see 336, sync may be re-pulling from GitHub — .env.local now disables that.
"@ -ForegroundColor Yellow
}
