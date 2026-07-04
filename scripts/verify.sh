#!/usr/bin/env bash
# Deterministic quality gate. Runs each repo's verify command from agents.env.
# Usage: verify.sh [repo ...]   (default: all repos)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

failed=""
for repo in "${@:-$REPOS}"; do
  echo "── verify: $repo"
  if (cd "$(repo_path "$repo")" && eval "$(verify_cmd "$repo")"); then
    echo "── PASS: $repo"
  else
    echo "── FAIL: $repo" >&2
    failed="$failed $repo"
  fi
done
[ -z "$failed" ] || { echo "VERIFY FAILED:$failed" >&2; exit 1; }
echo "VERIFY GREEN"
