#!/usr/bin/env bash
# End-to-end smoke test: builds a scratch workspace, runs the full task
# lifecycle, and checks the guard hook. Run from anywhere; no side effects.
set -euo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "SMOKE FAIL: $*" >&2; exit 1; }

# --- project root with one fake repo, state in scaffold/ (default layout)
WS="$TMP/ws"; mkdir -p "$WS/app" "$WS/scaffold/tasks"
git -C "$WS" init -qb main && git -C "$WS" config user.email t@t && git -C "$WS" config user.name t
git -C "$WS/app" init -qb main
git -C "$WS/app" -c user.email=t@t -c user.name=t commit -qm init --allow-empty
cat > "$WS/scaffold/agents.env" <<'EOF'
PROJECT_NAME=smoke
DEFAULT_BRANCH=main
REPOS="app"
REPO_app=../app
VERIFY_app="test -f ok.txt"
EOF
echo ok > "$WS/app/ok.txt"
git -C "$WS/app" add . && git -C "$WS/app" -c user.email=t@t -c user.name=t commit -qm "add ok"
cd "$WS"

# --- preflight
"$SCAFFOLD/scripts/preflight.sh" >/dev/null || fail "preflight should pass"

# --- new / next / start
id=$("$SCAFFOLD/scripts/task.sh" new "Add greeting feature")
[ "$id" = "0001" ] || fail "expected id 0001, got $id"
[ "$("$SCAFFOLD/scripts/task.sh" next)" = "0001" ] || fail "next should return 0001"
"$SCAFFOLD/scripts/task.sh" start "$id" >/dev/null
git -C app rev-parse --abbrev-ref HEAD | grep -q "task/0001" || fail "not on task branch"
"$SCAFFOLD/scripts/task.sh" next >/dev/null && fail "next should be empty while in-progress" || true

# --- implement something on the branch
echo "hello" > app/greeting.txt
git -C app add . && git -C app -c user.email=t@t -c user.name=t commit -qm "wip greeting"

# --- done: squash-merge, trailer, log
"$SCAFFOLD/scripts/task.sh" done "$id" >/dev/null
[ "$(git -C app rev-parse --abbrev-ref HEAD)" = "main" ] || fail "should be back on main"
git -C app log -1 --format=%B | grep -q "Task-Id: 0001" || fail "missing Task-Id trailer"
git -C app log --oneline | wc -l | grep -q 3 || fail "expected exactly 3 commits (squash)"
grep -q "Status: done" scaffold/tasks/0001-*/task.md || fail "status not done"
grep -q "app:" scaffold/tasks/0001-*/task.md || fail "commit sha not recorded"
grep -q "^Spec:" scaffold/tasks/0001-*/task.md || fail "no Spec field"
grep -q "0001" scaffold/tasks/_log.md || fail "no log line"
git -C "$WS" log --oneline | grep -q "task 0001 done" || fail "no workspace snapshot commit"
git -C app rev-parse -q --verify task/0001-add-greeting-feature >/dev/null && fail "branch not deleted" || true

# --- block / reopen / NEEDS_HUMAN
id2=$("$SCAFFOLD/scripts/task.sh" new "Second thing")
"$SCAFFOLD/scripts/task.sh" block "$id2" "unclear spec" >/dev/null
grep -q "unclear spec" scaffold/NEEDS_HUMAN.md || fail "no NEEDS_HUMAN entry"
"$SCAFFOLD/scripts/task.sh" next >/dev/null && fail "blocked task must not be next" || true
"$SCAFFOLD/scripts/task.sh" reopen "$id2" >/dev/null
[ "$("$SCAFFOLD/scripts/task.sh" next)" = "0002" ] || fail "reopened task should be next"

# --- red verify blocks done
"$SCAFFOLD/scripts/task.sh" start "$id2" >/dev/null
"$SCAFFOLD/scripts/task.sh" start "$id2" >/dev/null || fail "start must resume an in-progress task"
git -C app rev-parse --abbrev-ref HEAD | grep -q "task/0002" || fail "resume not on task branch"
rm app/ok.txt && git -C app add -A && git -C app -c user.email=t@t -c user.name=t commit -qm "break verify"
"$SCAFFOLD/scripts/task.sh" done "$id2" >/dev/null 2>&1 && fail "done must refuse red verify" || true

# --- limit_wait: parses reset epoch, falls back to LIMIT_BACKOFF, ignores other errors
w=$(bash -c "source '$SCAFFOLD/scripts/lib.sh'; limit_wait 'Claude AI usage limit reached|$(( $(date +%s) + 600 ))'")
{ [ "$w" -ge 600 ] && [ "$w" -le 700 ]; } || fail "limit_wait epoch parse gave $w"
w=$(bash -c "source '$SCAFFOLD/scripts/lib.sh'; LIMIT_BACKOFF=42 limit_wait '5-hour limit reached'")
[ "$w" = 42 ] || fail "limit_wait fallback gave $w"
bash -c "source '$SCAFFOLD/scripts/lib.sh'; limit_wait 'ordinary task failure'" >/dev/null \
  && fail "limit_wait matched non-limit output" || true

# --- no-arg verify must run every repo (regression: "${@:-$REPOS}" collapsed
# multi-repo REPOS into one word, silently verifying nothing); flat layout
# (agents.env at the workspace root) must keep working
WS2="$TMP/ws2"; mkdir -p "$WS2/a" "$WS2/b"
cat > "$WS2/agents.env" <<'EOF'
PROJECT_NAME=smoke2
REPOS="a b"
REPO_a=a
REPO_b=b
VERIFY_a="touch ran_a"
VERIFY_b="touch ran_b"
EOF
(cd "$WS2" && "$SCAFFOLD/scripts/verify.sh" >/dev/null) || fail "two-repo verify should pass"
[ -f "$WS2/a/ran_a" ] && [ -f "$WS2/b/ran_b" ] || fail "no-arg verify skipped a repo"
cd "$WS"

# --- guard hook
g() { echo "$1" | python3 "$SCAFFOLD/hooks/guard.py" >/dev/null 2>&1; }
g '{"tool_name":"Bash","tool_input":{"command":"git push --force origin x"}}' && fail "guard: force push allowed" || true
g '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' && fail "guard: push to main allowed" || true
g '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' && fail "guard: rm -rf / allowed" || true
g '{"tool_name":"Bash","tool_input":{"command":"git push origin task/0001-x"}}' || fail "guard: task-branch push blocked"
g '{"tool_name":"Bash","tool_input":{"command":"rm -rf node_modules"}}' || fail "guard: normal rm blocked"
CLAUDE_PLUGIN_ROOT="$SCAFFOLD" python3 -c 'import json,subprocess,sys,os
p=subprocess.run(["python3", os.environ["CLAUDE_PLUGIN_ROOT"]+"/hooks/guard.py"], input=json.dumps({"tool_name":"Edit","tool_input":{"file_path":os.environ["CLAUDE_PLUGIN_ROOT"]+"/agents/implementer.md"}}), capture_output=True, text=True)
sys.exit(0 if p.returncode==2 else 1)' || fail "guard: plugin self-edit allowed"

echo "SMOKE OK"
