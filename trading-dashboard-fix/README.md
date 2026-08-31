# Live Dashboard fix: 336 trades back down to 62

The Live Dashboard shows 336 trades instead of 62 because the Aug 29–30 auto-sync
ran `git merge origin/main -X ours`. That strategy only wins on *conflicts*, and
`data/trades-snapshot.json` is a JSON array, so git auto-merged both sides without
conflicting and restored the 274 archived April–July trades that the July 30
session reset had removed.

The fix is committed and verified, but it lives in this repo (`git_test`) because
the Cursor GitHub App is not installed on `khoanatran/Trading_DashBoard`, so every
write there returns 403.

## Option 1 — fix your local dashboard now (no GitHub access needed)

```powershell
irm https://raw.githubusercontent.com/khoanatran/git_test/cursor/revert-live-trade-merge-4361/trading-dashboard-fix/FIX_LIVE_DASHBOARD.ps1 | iex
```

Then fully stop the dashboard, start it again, and hard-refresh (`Ctrl+Shift+R`).
If the count is stale, the browser cached it: press F12 and run
`localStorage.clear(); location.reload()`.

If the repo isn't found automatically, point at it first:

```powershell
$env:DASHBOARD_REPO = 'C:\path\to\Trading_DashBoard'
```

This repairs `data/` in place and sets `.env.local` → `GITHUB_BACKUP_ENABLED=false`,
because GitHub `main` still holds the 336-trade snapshot and `pullFromGitHub()` runs
on every launch.

## Option 2 — grant GitHub access so the fix can be pushed

Add `khoanatran/Trading_DashBoard` to the Cursor GitHub App at
<https://github.com/settings/installations> (Configure → Repository access), or add a
fine-grained PAT with **Contents: Read and write** as the `GH_PAT` secret in the
Cursor Dashboard under Cloud Agents → Secrets.

Then push the prepared branch:

```bash
GH_PAT=github_pat_xxx bash push-fix-to-github.sh
```

The script refuses to push unless the snapshot is exactly 62 trades.

## Option 3 — apply the branch yourself

```bash
cd /path/to/Trading_DashBoard
git fetch https://github.com/khoanatran/git_test.git cursor/revert-live-trade-merge-4361
git am ../patches/restore-live-session-window.patch   # or: git pull <bundle> <branch>
```

`patches/trading-dashboard-fix.bundle` carries the same commit as a git bundle.

## What the code change does

`data/live-session.json` gains `liveFromDate: "2026-07-29"`, and that window is
enforced wherever trades enter the live session — snapshot save, MT5 import, server
restore, and the sync merge — so a future auto-merge cannot reintroduce archived
dates. `github-backup-server` reapplies the window after an auto-merge.

`scripts/fix-live-dashboard.js` does the data repair in **Node**, not PowerShell:
PowerShell's `ConvertFrom-Json` coerces ISO timestamps into `[DateTime]` objects,
which both breaks date comparisons and rewrites every timestamp on save.

## Verified

- `tsc --noEmit` clean, `npm run build` succeeds, `scripts/verify-live-from-date.ts` passes
- Fix run against a repo seeded from live GitHub `main`: 336 → 62, output deep-equal
  to the known-good snapshot with no mangled timestamps
- Idempotent on re-run (62 → 62)
- Dev server API returns 62 trades, 2026-07-29 through 2026-08-28
- Browser UI shows 62 in both the sidebar and the TOTAL TRADES card
