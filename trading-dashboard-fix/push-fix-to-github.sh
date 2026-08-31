#!/usr/bin/env bash
# Push the Live Dashboard fix to khoanatran/Trading_DashBoard.
#
# Needs a credential with write access to that repo, supplied as any of:
#   GH_PAT, GITHUB_PAT, TRADING_DASHBOARD_TOKEN, or GITHUB_TOKEN
# (a fine-grained PAT with Contents: Read and write is enough)
#
#   export GH_PAT=github_pat_xxx
#   bash push-fix-to-github.sh
#
# With no token, the Cursor GitHub App credential is tried instead, which
# only works once the app is granted access to Trading_DashBoard.
set -euo pipefail

REPO_SLUG="${REPO_SLUG:-khoanatran/Trading_DashBoard}"
BRANCH="${BRANCH:-cursor/revert-live-trade-merge-4361}"
WORKDIR="${WORKDIR:-/tmp/td-clean}"
TOKEN="${GH_PAT:-${GITHUB_PAT:-${TRADING_DASHBOARD_TOKEN:-${GITHUB_TOKEN:-}}}}"

if [[ ! -d "$WORKDIR/.git" ]]; then
  echo "No git repo at $WORKDIR. Set WORKDIR to the prepared fix clone." >&2
  exit 1
fi
cd "$WORKDIR"

if ! git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
  echo "Branch $BRANCH not found in $WORKDIR." >&2
  exit 1
fi

trades="$(node -e "console.log(require('./data/trades-snapshot.json').trades.length)")"
echo "Branch $BRANCH is at $trades trades."
if [[ "$trades" != "62" ]]; then
  echo "Expected 62 trades, refusing to push a wrong snapshot." >&2
  exit 1
fi

if [[ -n "$TOKEN" ]]; then
  echo "Pushing with supplied token..."
  push_url="https://x-access-token:${TOKEN}@github.com/${REPO_SLUG}.git"
else
  echo "No token set; trying the existing remote credential..."
  push_url="$(git remote get-url origin)"
fi

if git push "$push_url" "$BRANCH:$BRANCH" 2>&1 | sed "s/${TOKEN:-__nope__}/***/g"; then
  echo
  echo "Pushed $BRANCH to $REPO_SLUG."
  echo "Open a pull request:"
  echo "  https://github.com/${REPO_SLUG}/compare/main...${BRANCH}?expand=1"
else
  echo
  echo "Push failed. The credential lacks write access to $REPO_SLUG." >&2
  echo "Grant the Cursor GitHub App access to that repo, or supply a PAT in GH_PAT." >&2
  exit 1
fi
