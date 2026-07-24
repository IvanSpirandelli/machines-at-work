#!/usr/bin/env bash
# Deterministic quality gate. Runs each repo's verify command from agents.env,
# then — if the repo defines one — its smoke command (SMOKE_<repo>): the app
# actually starts and answers. Unit tests can't see a startup path (a migration
# that fails on existing data, a bad env var, an import error at boot), so a
# repo that ships a runnable app should define one.
# Usage: verify.sh [--no-smoke] [repo ...]   (default: all repos, smoke on)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

smoke=1
[ "${1:-}" != "--no-smoke" ] || { smoke=0; shift; }

failed=""
[ $# -gt 0 ] || set -- $REPOS
for repo in "$@"; do
  echo "── verify: $repo"
  if ! (cd "$(repo_path "$repo")" && eval "$(verify_cmd "$repo")"); then
    echo "── FAIL: $repo" >&2
    failed="$failed $repo"
    continue    # a repo that fails its own tests has nothing to smoke
  fi
  cmd="$(smoke_cmd "$repo")"
  if [ "$smoke" -eq 0 ] || [ -z "$cmd" ]; then
    echo "── PASS: $repo"
    continue
  fi
  echo "── smoke: $repo"
  # `bash -c` (not eval) so `timeout` owns the process: a smoke command that
  # hangs — a container that never turns healthy, a curl with no deadline —
  # would otherwise wedge the whole loop. rc 124 = the timeout fired.
  if (cd "$(repo_path "$repo")" && timeout "${SMOKE_TIMEOUT:-300}" bash -c "$cmd"); then
    echo "── PASS: $repo"
  else
    rc=$?
    [ "$rc" -ne 124 ] || echo "── smoke timed out after ${SMOKE_TIMEOUT:-300}s" >&2
    echo "── FAIL: $repo (smoke)" >&2
    failed="$failed $repo"
  fi
done
[ -z "$failed" ] || { echo "VERIFY FAILED:$failed" >&2; exit 1; }
echo "VERIFY GREEN"
