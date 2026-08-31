#!/usr/bin/env bash
# Fix Live Dashboard showing 336 trades (restores 62 trades, July 29+).
# Run from any directory:
#   curl -fsSL https://raw.githubusercontent.com/khoanatran/git_test/cursor/revert-live-trade-merge-4361/trading-dashboard-fix/FIX_LIVE_DASHBOARD.sh | bash
# Or with explicit repo path:
#   REPO_PATH=/path/to/Trading_DashBoard bash FIX_LIVE_DASHBOARD.sh
set -euo pipefail

BASE="${FIX_PATCH_BASE:-https://raw.githubusercontent.com/khoanatran/git_test/cursor/revert-live-trade-merge-4361/patches}"

find_repo() {
  local candidates=()
  [[ -n "${REPO_PATH:-}" ]] && candidates+=("$REPO_PATH")
  candidates+=(
    "$HOME/Trading_DashBoard"
    "$HOME/Documents/Trading_DashBoard"
    "/mnt/c/Omen Trading/Trading_DashBoard"
    "/mnt/c/Trading_DashBoard"
  )
  for dir in "${candidates[@]}"; do
    [[ -f "$dir/data/trades-snapshot.json" ]] && { echo "$dir"; return 0; }
  done
  echo "Trading_DashBoard not found. Set REPO_PATH=/path/to/Trading_DashBoard" >&2
  exit 1
}

repo="$(find_repo)"
echo "Fixing Live Dashboard in: $repo"
cd "$repo"

before="$(node -e "const d=require('./data/trades-snapshot.json'); console.log((d.trades||d).length)")"
echo "Current trades: $before"

curl -fsSL "$BASE/trades-snapshot-fixed-62.json" -o data/trades-snapshot.json
curl -fsSL "$BASE/live-session-fixed.json" -o data/live-session.json
curl -fsSL "$BASE/flags-fixed.json" -o data/flags.json
curl -fsSL "$BASE/trade-tags-fixed.json" -o data/trade-tags.json

after="$(node -e "const d=require('./data/trades-snapshot.json'); console.log(d.trades.length)")"
echo "Fixed trades: $after (removed $((before - after)) archived May-July rows)"

# Stop dashboard from re-pulling 336 trades from GitHub on next launch
env_file="$repo/.env.local"
if [[ -f "$env_file" ]] && grep -q 'GITHUB_BACKUP_ENABLED' "$env_file"; then
  sed -i 's/^GITHUB_BACKUP_ENABLED=.*/GITHUB_BACKUP_ENABLED=false/' "$env_file"
else
  echo 'GITHUB_BACKUP_ENABLED=false' >> "$env_file"
fi
echo "Set .env.local -> GITHUB_BACKUP_ENABLED=false"

if [[ "${FIX_LOCAL_ONLY:-}" == "1" ]]; then
  echo "LOCAL FIX APPLIED ($after trades). Restart dashboard and hard-refresh browser."
  exit 0
fi

git add data/trades-snapshot.json data/live-session.json data/flags.json data/trade-tags.json
if git diff --cached --quiet; then
  echo "Data already fixed locally. Restart dashboard and hard-refresh browser."
else
  git commit -m "Fix live dashboard: keep July 29+ trades only ($after trades)"
  if git push origin main; then
    sed -i 's/^GITHUB_BACKUP_ENABLED=false/GITHUB_BACKUP_ENABLED=true/' "$env_file" 2>/dev/null || true
    echo "Pushed to GitHub. Restart the dashboard and refresh your browser."
  else
    echo "Push failed — local fix applied ($after trades). Sync stays disabled. Restart dashboard."
  fi
fi
