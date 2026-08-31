<#
  Fix Live Dashboard showing 336 trades -> 62 trades (July 29, 2026 onward).

  Run in PowerShell (ideally from your Trading_DashBoard folder):
    irm https://raw.githubusercontent.com/khoanatran/git_test/cursor/revert-live-trade-merge-4361/trading-dashboard-fix/FIX_LIVE_DASHBOARD.ps1 | iex

  If the repo is somewhere unusual, point at it first:
    $env:DASHBOARD_REPO = 'C:\Omen Trading\Trading_DashBoard'
    irm https://raw.githubusercontent.com/khoanatran/git_test/cursor/revert-live-trade-merge-4361/trading-dashboard-fix/FIX_LIVE_DASHBOARD.ps1 | iex

  The JSON edit runs in Node (already required by the dashboard) because
  PowerShell's ConvertFrom-Json rewrites ISO timestamps into DateTime objects
  and would corrupt every trade record on save.

  Safe under `iex`: no #Requires, no param block, never calls exit.
#>

$ErrorActionPreference = 'Stop'
$LiveFrom = '2026-07-29'
$ScriptBase = 'https://raw.githubusercontent.com/khoanatran/git_test/cursor/revert-live-trade-merge-4361/trading-dashboard-fix'

# Embedded so the fix needs no further downloads.
$FixerSource = @'
const fs = require('fs')
const path = require('path')

const repoRoot = process.argv[2] || process.cwd()
const LIVE_FROM = process.argv[3] || '2026-07-29'
const dataDir = path.join(repoRoot, 'data')
const DATE_RE = /(\d{4}-\d{2}-\d{2})/

function readJson(name) {
  const file = path.join(dataDir, name)
  if (!fs.existsSync(file)) return null
  return JSON.parse(fs.readFileSync(file, 'utf8'))
}

function writeJson(name, value) {
  fs.writeFileSync(path.join(dataDir, name), JSON.stringify(value, null, 2) + '\n', 'utf8')
}

function tradeDay(trade) {
  for (const key of ['exitTime', 'timestamp', 'entryTime']) {
    const value = trade[key]
    if (typeof value === 'string') {
      const m = value.match(DATE_RE)
      if (m) return m[1]
    }
  }
  return null
}

function inLiveWindow(day) {
  return day === null || day >= LIVE_FROM
}

function filterKeyedByDate(record) {
  if (!record || typeof record !== 'object') return record
  const out = {}
  for (const [key, value] of Object.entries(record)) {
    const m = key.match(DATE_RE)
    if (inLiveWindow(m ? m[1] : null)) out[key] = value
  }
  return out
}

const snapshot = readJson('trades-snapshot.json')
if (!snapshot) {
  console.error('No data/trades-snapshot.json under ' + repoRoot)
  process.exit(1)
}

const allTrades = Array.isArray(snapshot) ? snapshot : snapshot.trades || []
const before = allTrades.length
const liveTrades = allTrades.filter(t => inLiveWindow(tradeDay(t)))
const after = liveTrades.length

if (Array.isArray(snapshot)) {
  writeJson('trades-snapshot.json', liveTrades)
} else {
  snapshot.trades = liveTrades
  snapshot.updatedAt = new Date().toISOString()
  writeJson('trades-snapshot.json', snapshot)
}
console.log('trades-snapshot.json: ' + before + ' -> ' + after + ' trades (removed ' + (before - after) + ')')

const session = readJson('live-session.json')
if (session) {
  session.liveFromDate = LIVE_FROM
  writeJson('live-session.json', session)
  console.log('live-session.json: liveFromDate = ' + LIVE_FROM)
}

const flags = readJson('flags.json')
if (flags) {
  if (flags.days) flags.days = filterKeyedByDate(flags.days)
  if (flags.trades) flags.trades = filterKeyedByDate(flags.trades)
  writeJson('flags.json', flags)
  console.log('flags.json: archived entries removed')
}

const tags = readJson('trade-tags.json')
if (tags) {
  writeJson('trade-tags.json', filterKeyedByDate(tags))
  console.log('trade-tags.json: archived entries removed')
}

if (before === after) {
  console.log('Nothing removed - data already matched the live window.')
}
'@

function Find-DashboardRepo {
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($env:DASHBOARD_REPO) { $candidates.Add($env:DASHBOARD_REPO) }

    # Walk up from the current directory so running inside app\ or data\ works.
    # Split-Path throws at a drive/filesystem root, so treat any failure as "stop".
    $dir = (Get-Location).ProviderPath
    for ($i = 0; $i -lt 6; $i++) {
        if ([string]::IsNullOrWhiteSpace($dir)) { break }
        $candidates.Add($dir)
        $parent = $null
        try { $parent = Split-Path -Path $dir -Parent } catch { $parent = $null }
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $dir) { break }
        $dir = $parent
    }

    if ($env:USERPROFILE) {
        foreach ($sub in 'Trading_DashBoard', 'Documents\Trading_DashBoard',
                         'Desktop\Trading_DashBoard', 'source\repos\Trading_DashBoard',
                         'Projects\Trading_DashBoard', 'OneDrive\Documents\Trading_DashBoard') {
            $candidates.Add((Join-Path $env:USERPROFILE $sub))
        }
    }
    foreach ($p in 'C:\Omen Trading\Trading_DashBoard', 'C:\Trading_DashBoard', 'D:\Trading_DashBoard') {
        $candidates.Add($p)
    }

    foreach ($c in $candidates) {
        if ([string]::IsNullOrWhiteSpace($c)) { continue }
        $snap = Join-Path (Join-Path $c 'data') 'trades-snapshot.json'
        if (Test-Path $snap) { return (Resolve-Path $c).Path }
    }
    return $null
}

$repo = Find-DashboardRepo
if (-not $repo) {
    Write-Host ''
    Write-Host 'Could not find Trading_DashBoard.' -ForegroundColor Red
    Write-Host 'Point at the repo and re-run:' -ForegroundColor Yellow
    Write-Host "  `$env:DASHBOARD_REPO = 'C:\path\to\Trading_DashBoard'" -ForegroundColor Cyan
    Write-Host "  irm $ScriptBase/FIX_LIVE_DASHBOARD.ps1 | iex" -ForegroundColor Cyan
    return
}

Write-Host "Trading_DashBoard: $repo" -ForegroundColor Cyan

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    Write-Host 'Node.js not found on PATH, but the dashboard needs it to run.' -ForegroundColor Red
    Write-Host 'Open the terminal you normally start the dashboard from and re-run this.' -ForegroundColor Yellow
    return
}

# Back up data/ before touching anything
$backup = Join-Path $repo ('data-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
Copy-Item (Join-Path $repo 'data') $backup -Recurse -Force
Write-Host "Backup: $backup" -ForegroundColor DarkGray

$fixJs = Join-Path $env:TEMP 'fix-live-dashboard.js'
Set-Content -Path $fixJs -Value $FixerSource -Encoding UTF8
& node $fixJs $repo $LiveFrom
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Fix script failed - data restored from backup.' -ForegroundColor Red
    Copy-Item (Join-Path $backup '*') (Join-Path $repo 'data') -Recurse -Force
    return
}

# Stop the launch-time GitHub pull from restoring the archived trades.
# Re-enabled below if the push succeeds, since GitHub is correct at that point.
function Set-GitHubSync {
    param([string]$RepoRoot, [bool]$Enabled)
    $file = Join-Path $RepoRoot '.env.local'
    $lines = @()
    if (Test-Path $file) {
        $lines = @(Get-Content $file | Where-Object { $_ -notmatch '^\s*GITHUB_BACKUP_ENABLED\s*=' })
    }
    if (-not $Enabled) { $lines += 'GITHUB_BACKUP_ENABLED=false' }
    Set-Content -Path $file -Value $lines
}

$envFile = Join-Path $repo '.env.local'
Set-GitHubSync -RepoRoot $repo -Enabled $false
Write-Host '.env.local: GITHUB_BACKUP_ENABLED=false (blocks the re-pull of 336)' -ForegroundColor Green

$nextCache = Join-Path $repo '.next\cache'
if (Test-Path $nextCache) {
    Remove-Item $nextCache -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host '.next\cache cleared' -ForegroundColor Green
}

# Commit and push if credentials allow; the local fix stands either way
$pushed = $false
Push-Location $repo
try {
    & git add data/trades-snapshot.json data/live-session.json data/flags.json data/trade-tags.json 2>&1 | Out-Null
    $dirty = & git status --porcelain -- data/ 2>&1
    if ($dirty) {
        & git commit -q -m "Fix live dashboard: keep July 29+ trades only" 2>&1 | Out-Null
        & git push origin main 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $pushed = $true }
    }
} catch {
} finally {
    Pop-Location
}

Write-Host ''
if ($pushed) {
    # GitHub now holds the corrected snapshot, so restore normal backup behaviour
    Set-GitHubSync -RepoRoot $repo -Enabled $true
    Write-Host 'Pushed the fix to GitHub main.' -ForegroundColor Green
    Write-Host '.env.local: GitHub sync re-enabled (remote is correct now)' -ForegroundColor Green
} else {
    Write-Host 'Not pushed to GitHub (no write access). Sync stays off, so 336 will not come back.' -ForegroundColor Yellow
    Write-Host 'Re-enable it later by deleting the GITHUB_BACKUP_ENABLED line in .env.local,' -ForegroundColor Yellow
    Write-Host 'once GitHub main holds the 62-trade snapshot.' -ForegroundColor Yellow
}
Write-Host ''
Write-Host 'NOW DO THIS:' -ForegroundColor Cyan
Write-Host '  1. Fully stop the dashboard (close the npm/node process window)'
Write-Host '  2. Start it again'
Write-Host '  3. In the browser, press Ctrl+Shift+R'
Write-Host ''
Write-Host 'Still 336? The browser cached the old trades in localStorage.' -ForegroundColor Yellow
Write-Host 'Press F12 -> Console, then run:' -ForegroundColor Yellow
Write-Host '  localStorage.clear(); location.reload()' -ForegroundColor Cyan
