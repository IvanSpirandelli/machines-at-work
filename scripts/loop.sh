#!/usr/bin/env bash
# Headless driver: fresh Claude context per task, deterministic task selection,
# hard iteration + cost caps. Run from the workspace root.
# Usage: MAX_TASKS=5 MAX_COST_USD=15 loop.sh
set -euo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS/lib.sh"

MAX_TASKS="${MAX_TASKS:-5}"
MAX_COST_USD="${MAX_COST_USD:-15}"
BUILD_SKILL="${BUILD_SKILL:-/scaffold:build}"
total_cost=0 n=0

"$SCRIPTS/preflight.sh"

while [ "$n" -lt "$MAX_TASKS" ]; do
  id=$("$SCRIPTS/task.sh" next) || { echo "no todo tasks left"; break; }
  n=$((n + 1))
  echo "══ task $id ($n/$MAX_TASKS, spent \$$total_cost)"
  out=$(claude -p "$BUILD_SKILL $id" \
        --permission-mode acceptEdits \
        --allowedTools "Bash,Read,Edit,Write,Glob,Grep,Agent,Skill,TodoWrite" \
        --output-format json) || echo "WARN: claude exited nonzero on $id" >&2
  cost=$(echo "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("total_cost_usd", 0))' 2>/dev/null || echo 0)
  total_cost=$(python3 -c "print(round($total_cost + $cost, 2))")
  dir=$(task_dir "$id"); status=$(get_field "$dir/task.md" Status)
  set_field "$dir/task.md" Cost "\$$cost"
  echo "── task $id → $status (\$$cost)"
  if [ "$status" = "in-progress" ]; then
    "$SCRIPTS/task.sh" block "$id" "loop.sh: session ended without done/blocked"
  fi
  if python3 -c "exit(0 if $total_cost >= $MAX_COST_USD else 1)"; then
    "$SCRIPTS/notify.sh" "loop.sh stopped: cost cap \$$MAX_COST_USD reached"
    break
  fi
done
"$SCRIPTS/notify.sh" "loop.sh finished: $n task(s), \$$total_cost. $("$SCRIPTS/task.sh" status | tail -n +2 | awk '{print $2}' | sort | uniq -c | tr '\n' ' ')"
