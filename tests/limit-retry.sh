#!/usr/bin/env bash
# Functional test: loop.sh must ride out a usage-limit exit (park WIP, wait,
# retry the same task) instead of blocking it. Uses a fake `claude` on PATH
# that dies with a limit message mid-task, then finishes the task on retry.
set -euo pipefail
MACHINES_AT_WORK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "LIMIT-RETRY FAIL: $*" >&2; exit 1; }

WS="$TMP/ws"; mkdir -p "$WS/app" "$WS/machines-at-work/tasks"
git -C "$WS" init -qb main && git -C "$WS" config user.email t@t && git -C "$WS" config user.name t
git -C "$WS/app" init -qb main
git -C "$WS/app" -c user.email=t@t -c user.name=t commit -qm init --allow-empty
cat > "$WS/machines-at-work/agents.env" <<'EOF'
PROJECT_NAME=limitretry
DEFAULT_BRANCH=main
REPOS="app"
REPO_app=../app
VERIFY_app="test -f ok.txt"
EOF
echo ok > "$WS/app/ok.txt"
git -C "$WS/app" add . && git -C "$WS/app" -c user.email=t@t -c user.name=t commit -qm "add ok"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<EOF
#!/usr/bin/env bash
FAKE_DIR="$TMP" MACHINES_AT_WORK="$MACHINES_AT_WORK" exec bash "$TMP/fake-claude-body.sh"
EOF
cat > "$TMP/fake-claude-body.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
n=$(cat "$FAKE_DIR/count" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$FAKE_DIR/count"
if [ "$n" -eq 1 ]; then
  # simulate /build: start task, leave tracked + untracked WIP, die on a usage limit
  "$MACHINES_AT_WORK/scripts/task.sh" start 0001 >/dev/null
  echo "wip line" >> app/wip.txt
  echo "tracked change" >> app/ok.txt   # tracked dirt: must be parked or retry fails preflight
  echo "Claude AI usage limit reached|9999999999"   # absurd epoch -> fallback backoff path
  exit 1
fi
# retry: tree must be clean (loop parked WIP) and task resumable
git -C app diff --quiet || { echo "RETRY SAW DIRTY TREE" >&2; exit 3; }
"$MACHINES_AT_WORK/scripts/task.sh" start 0001 >/dev/null    # resume in-progress
git -C app add -A
git -C app -c user.email=t@t -c user.name=t commit -qm "finish work" 2>/dev/null || true
"$MACHINES_AT_WORK/scripts/task.sh" done 0001 >/dev/null
echo '{"total_cost_usd": 0.05}'
EOF
chmod +x "$TMP/bin/claude"

cd "$WS"
"$MACHINES_AT_WORK/scripts/task.sh" new "Limit retry feature" >/dev/null

out=$(PATH="$TMP/bin:$PATH" LIMIT_BACKOFF=2 MAX_TASKS=3 bash "$MACHINES_AT_WORK/scripts/loop.sh" 2>&1) || fail "loop.sh exited nonzero: $out"

[ "$(cat "$TMP/count")" = 2 ] || fail "expected 2 claude calls, got $(cat "$TMP/count")"
echo "$out" | grep -q "usage limit on 0001" || fail "no limit-retry log line: $out"
grep -q "Status: done" machines-at-work/tasks/0001-*/task.md || fail "task not done after retry"
[ ! -s machines-at-work/NEEDS_HUMAN.md ] || fail "task was escalated: $(cat machines-at-work/NEEDS_HUMAN.md)"
git -C app log -1 main --format=%B | grep -q "Task-Id: 0001" || fail "no squash commit on main"
git -C app show main:wip.txt | grep -q "wip line" || fail "untracked WIP lost"
git -C app show main:ok.txt | grep -q "tracked change" || fail "parked tracked WIP lost"
echo "LIMIT-RETRY OK"
