#!/usr/bin/env bash
# Headless driver: fresh Claude context per task, deterministic task selection,
# hard iteration + cost caps. On a Claude subscription the cost cap is skipped
# (no per-token bill; cost is only an API-equiv estimate). A usage/rate-limit
# exit pauses until the reset and retries the task instead of blocking it.
# Run from the project root.
# Usage: MAX_TASKS=5 MAX_COST_USD=15 LIMIT_BACKOFF=1800 loop.sh
set -euo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS/lib.sh"

MAX_TASKS="${MAX_TASKS:-5}"
MAX_COST_USD="${MAX_COST_USD:-15}"
BUILD_SKILL="${BUILD_SKILL:-/scaffold:build}"
total_cost=0 n=0

# On a Claude subscription there's no per-token bill, so total_cost_usd is an
# API-equivalent estimate, not real spend — record it but don't cap on it.
# Detect it: no API credentials and not routed through Bedrock/Vertex.
SUBSCRIPTION=
[ -z "${ANTHROPIC_API_KEY:-}${ANTHROPIC_AUTH_TOKEN:-}" ] \
  && [ "${CLAUDE_CODE_USE_BEDROCK:-}" != "1" ] && [ "${CLAUDE_CODE_USE_VERTEX:-}" != "1" ] \
  && SUBSCRIPTION=1
errf=$(mktemp); trap 'rm -f "$errf"' EXIT

"$SCRIPTS/preflight.sh"

while [ "$n" -lt "$MAX_TASKS" ]; do
  id=$("$SCRIPTS/task.sh" next) || { echo "no todo tasks left"; break; }
  n=$((n + 1))
  if [ -n "$SUBSCRIPTION" ]; then spent="subscription"; else spent="\$$total_cost"; fi
  echo "══ task $id ($n/$MAX_TASKS, spent $spent)"
  while :; do
    rc=0
    out=$(claude -p "$BUILD_SKILL $id" \
          --permission-mode acceptEdits \
          --allowedTools "Bash,Read,Edit,Write,Glob,Grep,Agent,Skill,TodoWrite" \
          --output-format json 2>"$errf") || rc=$?
    dir=$(task_dir "$id"); status=$(get_field "$dir/task.md" Status)
    if [ "$rc" -ne 0 ] && [ "$status" != "done" ] \
       && wait=$(limit_wait "$out"$'\n'"$(cat "$errf")"); then
      # usage limit, not a task failure: park WIP so preflight passes on retry
      # (squashed away by task.sh done), reopen if the dying session blocked it,
      # then wait out the window and rerun the same task.
      branch=$(get_field "$dir/task.md" Branch)
      for repo in $(get_field "$dir/task.md" Repos); do
        path=$(repo_path "$repo")
        [ "$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null)" = "$branch" ] || continue
        git -C "$path" diff --quiet && git -C "$path" diff --cached --quiet \
          || { git -C "$path" add -A; git -C "$path" commit -qm "wip: interrupted by usage limit"; }
      done
      [ "$status" = "blocked" ] && "$SCRIPTS/task.sh" reopen "$id" >/dev/null
      echo "── usage limit on $id; retrying in $((wait / 60))m"
      "$SCRIPTS/notify.sh" "loop.sh: usage limit — retrying task $id in $((wait / 60))m" || true
      sleep "$wait"
      continue
    fi
    if [ "$rc" -ne 0 ]; then echo "WARN: claude exited nonzero on $id" >&2; cat "$errf" >&2; fi
    break
  done
  cost=$(echo "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("total_cost_usd", 0))' 2>/dev/null || echo 0)
  total_cost=$(python3 -c "print(round($total_cost + $cost, 2))")
  if [ -n "$SUBSCRIPTION" ]; then
    set_field "$dir/task.md" Cost "subscription"
    echo "── task $id → $status (subscription; ~\$$cost API-equiv)"
  else
    set_field "$dir/task.md" Cost "\$$cost"
    echo "── task $id → $status (\$$cost)"
  fi
  if [ "$status" = "in-progress" ]; then
    "$SCRIPTS/task.sh" block "$id" "loop.sh: session ended without done/blocked"
  fi
  if [ -z "$SUBSCRIPTION" ] && python3 -c "exit(0 if $total_cost >= $MAX_COST_USD else 1)"; then
    "$SCRIPTS/notify.sh" "loop.sh stopped: cost cap \$$MAX_COST_USD reached"
    break
  fi
done
if [ -n "$SUBSCRIPTION" ]; then spent="subscription (~\$$total_cost API-equiv)"; else spent="\$$total_cost"; fi
"$SCRIPTS/notify.sh" "loop.sh finished: $n task(s), $spent. $("$SCRIPTS/task.sh" status | tail -n +2 | awk '{print $2}' | sort | uniq -c | tr '\n' ' ')"
