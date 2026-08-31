# Handoff: land the Live Dashboard fix on Trading_DashBoard

GitHub App access to `khoanatran/Trading_DashBoard` has been granted, but a cloud
agent's GitHub token is scoped to its own repository when the VM boots. The run
that produced this fix was started on `khoanatran/git_test`, so its token lists only
`git_test` under `/installation/repositories` and cannot push to `Trading_DashBoard`
no matter how long it waits.

A **new** cloud agent started on `khoanatran/Trading_DashBoard` gets a token scoped
to that repo and can push immediately.

## Paste this into a new Cloud Agent on khoanatran/Trading_DashBoard

> The Live Dashboard shows 336 trades but should show 62 (July 29, 2026 onward).
> On Aug 29–30 an auto-sync ran `git merge origin/main -X ours`; that strategy only
> wins on conflicts, and `data/trades-snapshot.json` is a JSON array, so git
> auto-merged both sides and restored 274 archived April–July trades that the
> July 30 session reset had removed.
>
> A complete, verified fix already exists as a single commit. Apply it:
>
> ```bash
> curl -fsSL https://raw.githubusercontent.com/khoanatran/git_test/cursor/revert-live-trade-merge-4361/patches/restore-live-session-window.patch -o /tmp/fix.patch
> git checkout -b cursor/revert-live-trade-merge-4361
> git am --3way /tmp/fix.patch
> node -e "console.log(require('./data/trades-snapshot.json').trades.length)"  # expect 62
> npx tsc --noEmit && npm run build
> git push -u origin cursor/revert-live-trade-merge-4361
> ```
>
> Then open a pull request against `main`. Do not merge it without my approval.
>
> The commit pins `liveFromDate: "2026-07-29"` in `data/live-session.json` and
> enforces that window wherever trades enter the live session (snapshot save, MT5
> import, server restore, sync merge), so a future auto-merge cannot reintroduce
> archived dates. It was verified with `tsc --noEmit`, `npm run build`,
> `scripts/verify-live-from-date.ts`, and a browser check showing 62 trades.

## If you would rather not start a new agent

Fix the running dashboard directly — this needs no GitHub access at all:

```powershell
irm https://raw.githubusercontent.com/khoanatran/git_test/cursor/revert-live-trade-merge-4361/trading-dashboard-fix/FIX_LIVE_DASHBOARD.ps1 | iex
```

Then fully stop the dashboard, start it again, and hard-refresh (`Ctrl+Shift+R`).

Or apply the commit and push from your own clone, where your credentials already
have write access:

```bash
cd /path/to/Trading_DashBoard
curl -fsSL https://raw.githubusercontent.com/khoanatran/git_test/cursor/revert-live-trade-merge-4361/patches/restore-live-session-window.patch -o /tmp/fix.patch
git checkout -b cursor/revert-live-trade-merge-4361
git am --3way /tmp/fix.patch
git push -u origin cursor/revert-live-trade-merge-4361
```
