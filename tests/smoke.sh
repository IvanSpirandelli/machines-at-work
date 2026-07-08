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
[ "$("$SCAFFOLD/scripts/task.sh" next)" = "0001" ] || fail "next should return the in-progress task to resume it"

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

# --- successor-gating: a blocked task halts next (exit 3) so its dependents
# don't run; CONTINUE_ON_BLOCK=1 skips the block to the later todo
"$SCAFFOLD/scripts/task.sh" block "$id2" "gate test" >/dev/null
id_after=$("$SCAFFOLD/scripts/task.sh" new "After the block")
rc=0; "$SCAFFOLD/scripts/task.sh" next >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "next must halt (exit 3) on a blocked predecessor, got $rc"
[ "$(CONTINUE_ON_BLOCK=1 "$SCAFFOLD/scripts/task.sh" next)" = "$id_after" ] \
  || fail "CONTINUE_ON_BLOCK=1 should skip the block to the next todo"
"$SCAFFOLD/scripts/task.sh" reopen "$id2" >/dev/null   # restore for later tests

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

# --- loop.sh merge enforcement: a session that ends in-progress with committed,
# review-approved work must be finishable. branch_has_commits detects the work;
# with an approving review.md the deterministic path runs task.sh done (no model).
id3=$("$SCAFFOLD/scripts/task.sh" new "Third thing")
"$SCAFFOLD/scripts/task.sh" start "$id3" >/dev/null
d3=$(echo scaffold/tasks/"$id3"-*/)   # resolve the task dir once (review.md doesn't exist yet)
lib() { bash -c "source '$SCAFFOLD/scripts/lib.sh'; $1"; }
lib "branch_has_commits $id3" && fail "branch_has_commits: true before any commit" || true
echo "world" > app/third.txt
git -C app add . && git -C app -c user.email=t@t -c user.name=t commit -qm "wip third"
lib "branch_has_commits $id3" || fail "branch_has_commits: false after commit"
# park_wip commits leftover WIP so a retry's preflight stays green; no-op when clean.
# "uncommitted" = tracked modifications (what preflight checks), so dirty a tracked file.
echo "dirty" >> app/third.txt
lib "park_wip $id3 'wip: parked'" || fail "park_wip failed"
{ git -C app diff --quiet && git -C app diff --cached --quiet; } || fail "park_wip left tree dirty"
git -C app log -1 --format=%s | grep -q "wip: parked" || fail "park_wip did not commit"
lib "park_wip $id3 'should-not-appear'" || fail "park_wip on clean tree failed"
git -C app log -1 --format=%s | grep -q "should-not-appear" && fail "park_wip committed on clean tree" || true
# approving review.md + committed work → deterministic done merges it (loop.sh's belt path)
printf '## Round 1\nno findings\nVERDICT: approve\n' > "$d3/review.md"
verdict=$(grep '^VERDICT:' "$d3/review.md" | tail -1)
[ "$verdict" = "VERDICT: approve" ] || fail "last-verdict parse gave '$verdict'"
"$SCAFFOLD/scripts/task.sh" done "$id3" >/dev/null || fail "approved work should merge"
grep -q "Status: done" "$d3/task.md" || fail "id3 not done after merge"
git -C app log -1 --format=%B | grep -q "Task-Id: $id3" || fail "id3 merge missing trailer"

# --- cold-start orphan: task.sh next returns an in-progress task (resume) instead
# of skipping it, so an orphan self-heals and gates its successors. The red-verify
# test above left id2 (0002) in-progress with commits, ahead of the 0003 todo.
[ "$("$SCAFFOLD/scripts/task.sh" next)" = "0002" ] \
  || fail "next must return the in-progress task, not skip to a later todo"

# a zero-commit orphan (killed before any work) → abandon resets to todo and
# un-strands the repo back to DEFAULT_BRANCH
orphan=$("$SCAFFOLD/scripts/task.sh" new "Orphan task")
"$SCAFFOLD/scripts/task.sh" start "$orphan" >/dev/null   # in-progress, on task branch, 0 commits
lib "branch_has_commits $orphan" && fail "orphan should have 0 commits" || true
"$SCAFFOLD/scripts/task.sh" abandon "$orphan" >/dev/null
grep -q "Status: todo" scaffold/tasks/"$orphan"-*/task.md || fail "abandon should reset to todo"
[ "$(git -C app rev-parse --abbrev-ref HEAD)" = "main" ] || fail "abandon should un-strand the repo to main"
git -C app rev-parse -q --verify "task/$orphan-orphan-task" >/dev/null && fail "abandon should delete the empty branch" || true

# abandon must refuse to discard committed work (git branch -d, not -D)
keep=$("$SCAFFOLD/scripts/task.sh" new "Keep work")
"$SCAFFOLD/scripts/task.sh" start "$keep" >/dev/null
echo data > app/keep.txt
git -C app add . && git -C app -c user.email=t@t -c user.name=t commit -qm "real work"
rc=0; "$SCAFFOLD/scripts/task.sh" abandon "$keep" >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "abandon must refuse a branch with unmerged commits"
git -C app rev-parse -q --verify "task/$keep-keep-work" >/dev/null || fail "abandon must not delete a committed branch"
grep -q "Status: in-progress" scaffold/tasks/"$keep"-*/task.md || fail "abandon refusal must leave status in-progress"

# reopen: a committed branch resumes (in-progress); an empty branch abandons (todo)
"$SCAFFOLD/scripts/task.sh" block "$keep" "reopen test" >/dev/null
"$SCAFFOLD/scripts/task.sh" reopen "$keep" >/dev/null
grep -q "Status: in-progress" scaffold/tasks/"$keep"-*/task.md || fail "reopen of a committed branch → in-progress"
empty=$("$SCAFFOLD/scripts/task.sh" new "Empty branch")
"$SCAFFOLD/scripts/task.sh" start "$empty" >/dev/null   # in-progress, 0 commits
"$SCAFFOLD/scripts/task.sh" reopen "$empty" >/dev/null
grep -q "Status: todo" scaffold/tasks/"$empty"-*/task.md || fail "reopen of an empty branch → todo"
[ "$(git -C app rev-parse --abbrev-ref HEAD)" = "main" ] || fail "reopen-abandon should un-strand the repo"

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

# --- DONE=pr: fresh base from origin, done pushes branch + opens PR (gh is
# stubbed, origin is a local bare repo), sync completes on merge, and a red
# origin/main makes preflight exit 3 (UPSTREAM RED)
WS3="$TMP/ws3"; mkdir -p "$WS3/app" "$WS3/scaffold/tasks" "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "auth status") exit 0 ;;
  "pr view") case "$3" in
               https://*) [ -n "${GH_PR_STATE:-}" ] || exit 1
                          echo "$GH_PR_STATE ${GH_PR_SHA:-}" ;;
               *) exit 1 ;;   # no PR exists for this branch yet
             esac ;;
  "pr create") echo "https://example.test/pr/1" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
git init --bare -qb main "$TMP/app-origin"
git -C "$WS3/app" init -qb main
git -C "$WS3/app" config user.email t@t && git -C "$WS3/app" config user.name t
echo ok > "$WS3/app/ok.txt"
git -C "$WS3/app" add . && git -C "$WS3/app" commit -qm init
git -C "$WS3/app" remote add origin "$TMP/app-origin"
git -C "$WS3/app" push -qu origin main
cat > "$WS3/scaffold/agents.env" <<'EOF'
PROJECT_NAME=smoke3
DEFAULT_BRANCH=main
DONE=pr
REPOS="app"
REPO_app=../app
VERIFY_app="test -f ok.txt"
EOF
cd "$WS3"
"$SCAFFOLD/scripts/preflight.sh" >/dev/null || fail "pr-mode preflight should pass"
idp=$("$SCAFFOLD/scripts/task.sh" new "Pr flow")
"$SCAFFOLD/scripts/task.sh" start "$idp" >/dev/null
echo feature > app/feat.txt
git -C app add . && git -C app commit -qm "wip pr flow"
"$SCAFFOLD/scripts/task.sh" done "$idp" >/dev/null || fail "pr-mode done failed"
dp=$(echo scaffold/tasks/"$idp"-*/)
grep -q "Status: pr" "$dp/task.md" || fail "status should be pr, not merged"
grep -q "PR: app:https://example.test/pr/1" "$dp/task.md" || fail "PR url not recorded"
[ "$(git -C app rev-parse --abbrev-ref HEAD)" = "main" ] || fail "should be back on main after pr"
git -C "$TMP/app-origin" rev-parse -q --verify "task/$idp-pr-flow" >/dev/null || fail "branch not pushed to origin"
GH_PR_STATE=OPEN "$SCAFFOLD/scripts/task.sh" sync >/dev/null
grep -q "Status: pr" "$dp/task.md" || fail "open PR must not complete the task"
GH_PR_STATE=MERGED GH_PR_SHA=1234567890abcdef "$SCAFFOLD/scripts/task.sh" sync >/dev/null
grep -q "Status: done" "$dp/task.md" || fail "merged PR should complete the task"
grep -q "app:1234567" "$dp/task.md" || fail "merge sha not recorded"
grep -q "$idp" scaffold/tasks/_log.md || fail "no log line after sync"
git -C app rev-parse -q --verify "task/$idp-pr-flow" >/dev/null && fail "local branch not cleaned up" || true
# red origin/main: verify fails with the repo exactly at origin → exit 3
rm app/ok.txt && git -C app add -A && git -C app commit -qm "teammate breaks main"
git -C app push -q origin main
rc=0; "$SCAFFOLD/scripts/preflight.sh" >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "red upstream should exit 3, got $rc"
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
