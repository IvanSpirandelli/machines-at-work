#!/usr/bin/env bash
# Validate the workspace before any agent runs. Fail loud, fail early.
# Usage: preflight.sh [--quick]   (--quick skips the verify run)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

err=0
for repo in $REPOS; do
  path="$(repo_path "$repo")" || { err=1; continue; }
  [ -d "$path" ] || { echo "FAIL: $repo path missing: $path" >&2; err=1; continue; }
  [ "$(cd "$path" && pwd)" != "$WS" ] || { echo "FAIL: $repo must be a subdirectory, not the workspace root" >&2; err=1; continue; }
  git -C "$path" rev-parse --git-dir >/dev/null 2>&1 || { echo "FAIL: $repo is not a git repo" >&2; err=1; continue; }
  git -C "$path" diff --quiet && git -C "$path" diff --cached --quiet \
    || { echo "FAIL: $repo has uncommitted changes" >&2; err=1; }
  git -C "$path" rev-parse -q --verify "$DEFAULT_BRANCH" >/dev/null \
    || { echo "FAIL: $repo has no branch $DEFAULT_BRANCH" >&2; err=1; }
  verify_cmd "$repo" >/dev/null || err=1
done
[ -d "$TASKS" ] || { echo "FAIL: no tasks/ dir (run /scaffold:init-project)" >&2; err=1; }
[ "$err" -eq 0 ] || { echo "PREFLIGHT FAILED" >&2; exit 1; }

[ "${1:-}" = "--quick" ] || "$(dirname "${BASH_SOURCE[0]}")/verify.sh"
echo "PREFLIGHT OK"
