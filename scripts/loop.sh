#!/usr/bin/env bash
# Headless driver: fresh Claude context per task, deterministic task selection,
# hard iteration + cost caps. On a Claude subscription the cost cap is skipped
# (no per-token bill; cost is only an API-equiv estimate). A usage/rate-limit
# exit pauses until the reset and retries the task instead of blocking it.
# Out of credits (billing exhausted — doesn't reset on a timer) hard-stops with
# exit 4; a human must top up or switch MODEL, so retrying is pointless.
# A session that ends still in-progress (work committed but not merged) is driven
# to a terminal state: finished deterministically when the branch is green +
# committed (review approved, or a resume that stalled — so it is never blocked
# merely for lacking a review verdict), else re-invoked up to MAX_RESUME times,
# else blocked with the verify color (GREEN/RED) in the reason.
# DONE=pr: a red origin/DEFAULT_BRANCH (preflight exit 3) parks the loop and
# retries after UPSTREAM_BACKOFF — teammate breakage is not a task failure.
# Run from the project root.
# Task selection halts on a blocked task (task.sh next gates its successors);
# CONTINUE_ON_BLOCK=1 skips past it. A transient API/network drop and an env crash
# before any work (no network, stranded tree) are retried up to MAX_RETRIES with
# RETRY_BACKOFF between tries — never counting against MAX_RESUME — then hard-stop
# with the captured reason; a zero-commit branch is abandoned so the retry is clean.
# MODEL pins the model passed to claude -p (default opus) so the session never
# silently falls back to a cheaper default; set MODEL=sonnet|fable to switch.
# Usage: MODEL=opus MAX_TASKS=5 MAX_COST_USD=15 MAX_RESUME=3 MAX_RETRIES=10 RETRY_BACKOFF=60 LIMIT_BACKOFF=1800 UPSTREAM_BACKOFF=1800 CONTINUE_ON_BLOCK=0 loop.sh
set -euo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPTS/lib.sh"

MAX_TASKS="${MAX_TASKS:-5}"
MAX_COST_USD="${MAX_COST_USD:-15}"
MAX_RESUME="${MAX_RESUME:-3}"
MAX_RETRIES="${MAX_RETRIES:-10}"
RETRY_BACKOFF="${RETRY_BACKOFF:-60}"
BUILD_SKILL="${BUILD_SKILL:-/machines-at-work:build}"
# Pin the model so a one-shot session never silently falls back to a cheaper
# default. Friendly names map to what claude --model accepts.
MODEL="${MODEL:-opus}"
case "$MODEL" in
  opus)   MODEL_ARG="opus" ;;
  sonnet) MODEL_ARG="sonnet" ;;
  fable)  MODEL_ARG="claude-fable-5" ;;
  *) echo "ERROR: MODEL must be opus, sonnet, or fable (got '$MODEL')" >&2; exit 1 ;;
esac
MODEL_UC=$(echo "$MODEL" | tr '[:lower:]' '[:upper:]')
total_cost=0 n=0 retries=0

# On a Claude subscription there's no per-token bill, so total_cost_usd is an
# API-equivalent estimate, not real spend — record it but don't cap on it.
# Detect it: no API credentials and not routed through Bedrock/Vertex.
SUBSCRIPTION=
[ -z "${ANTHROPIC_API_KEY:-}${ANTHROPIC_AUTH_TOKEN:-}" ] \
  && [ "${CLAUDE_CODE_USE_BEDROCK:-}" != "1" ] && [ "${CLAUDE_CODE_USE_VERTEX:-}" != "1" ] \
  && SUBSCRIPTION=1
errf=$(mktemp); trap 'rm -f "$errf"' EXIT

until "$SCRIPTS/preflight.sh"; do
  rc=$?
  [ "$rc" -eq 3 ] || exit "$rc"
  wait="${UPSTREAM_BACKOFF:-1800}"
  echo "── upstream red; retrying preflight in $((wait / 60))m"
  "$SCRIPTS/notify.sh" "loop.sh: origin/$DEFAULT_BRANCH is red — retrying in $((wait / 60))m" || true
  sleep "$wait"
done

# Cold-start reconcile: a session killed mid-task leaves an orphan in-progress
# that a fresh run's task.sh next would otherwise skip. One with committed work is
# resumed (task.sh next now returns in-progress); one with a zero-commit branch was
# killed before any work landed — abandon it so its repo is restored to
# DEFAULT_BRANCH and it restarts clean rather than resuming an empty branch. Either
# way task.sh next gates its dependents until it reaches a terminal state.
for d in "$TASKS"/[0-9]*/; do
  [ -f "$d/task.md" ] || continue
  [ "$(get_field "$d/task.md" Status)" = "in-progress" ] || continue
  oid=$(basename "$d" | cut -d- -f1)
  if branch_has_commits "$oid"; then
    echo "── cold start: $oid is in-progress with commits — will resume"
  else
    echo "── cold start: $oid is in-progress but empty — abandoning to todo"
    "$SCRIPTS/task.sh" abandon "$oid" >/dev/null
  fi
done

while [ "$n" -lt "$MAX_TASKS" ]; do
  nrc=0; id=$("$SCRIPTS/task.sh" next) || nrc=$?
  if [ "$nrc" -ne 0 ]; then
    if [ "$nrc" -eq 3 ]; then
      echo "── stopping: a blocked task gates the queue (set CONTINUE_ON_BLOCK=1 to skip)"
      "$SCRIPTS/notify.sh" "loop.sh stopped: a blocked task gates the queue" || true
    else
      echo "no todo tasks left"
    fi
    break
  fi
  if [ -n "$SUBSCRIPTION" ]; then spent="subscription"; else spent="\$$total_cost"; fi
  echo "══ task $id (task $((n + 1))/$MAX_TASKS, spent $spent)"
  echo "Solving task with $MODEL_UC"
  resume=0; task_cost=0; fail_reason=""; prompt="$BUILD_SKILL $id"
  while :; do
    before=$(branch_head "$id")   # branch tips before the session, to detect a no-op resume
    rc=0
    out=$(claude -p "$prompt" \
          --model "$MODEL_ARG" \
          --permission-mode acceptEdits \
          --allowedTools "Bash,Read,Edit,Write,Glob,Grep,Agent,Skill,TodoWrite" \
          --output-format json 2>"$errf") || rc=$?
    dir=$(task_dir "$id"); status=$(get_field "$dir/task.md" Status)
    if [ "$rc" -ne 0 ] && [ "$status" != "done" ] && [ "$status" != "pr" ] \
       && wait=$(limit_wait "$out"$'\n'"$(cat "$errf")"); then
      # usage limit, not a task failure: park WIP so preflight passes on retry,
      # reopen if the dying session blocked it, then wait it out and rerun.
      park_wip "$id" "wip: interrupted by usage limit"
      [ "$status" = "blocked" ] && "$SCRIPTS/task.sh" reopen "$id" >/dev/null
      echo "── usage limit on $id; retrying in $((wait / 60))m"
      "$SCRIPTS/notify.sh" "loop.sh: usage limit — retrying task $id in $((wait / 60))m" || true
      sleep "$wait"
      continue
    fi
    if [ "$rc" -ne 0 ] && is_out_of_credits "$out"$'\n'"$(cat "$errf")"; then
      # Out of credits doesn't reset on a timer, so waiting/retrying is useless.
      # Park any WIP and hard-stop (exit 4) with an exact, actionable message
      # rather than burning MAX_RETRIES on a condition only a human can clear.
      park_wip "$id" "wip: interrupted, out of credits"
      echo "── stopped: out of credits on $id — top up (/usage-credits) or switch model (MODEL=sonnet|fable)"
      "$SCRIPTS/notify.sh" "loop.sh stopped: out of credits on $id — top up or switch model" || true
      exit 4
    fi
    if [ "$rc" -ne 0 ] && [ "$status" != "done" ] && [ "$status" != "pr" ] \
       && is_transient_api_error "$(echo "$out" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("result",""))
except Exception: pass' 2>/dev/null)"$'\n'"$(cat "$errf")"; then
      # Transient network/API drop (e.g. "connection closed mid-response") — external
      # and self-clearing, not the task's fault. It must never count against MAX_RESUME
      # nor terminate the loop. No committed work → abandon so the branch/repo restart
      # clean and the retry starts fresh; work landed → park it. Retry the SAME task,
      # bounded by MAX_RETRIES so a persistent outage still hard-stops.
      if branch_has_commits "$id"; then
        park_wip "$id" "wip: interrupted by transient API error" || true
      else
        "$SCRIPTS/task.sh" abandon "$id" >/dev/null 2>&1 || true
        resume=0; prompt="$BUILD_SKILL $id"   # empty branch is gone; start fresh
      fi
      retries=$((retries + 1))
      if [ "$retries" -ge "$MAX_RETRIES" ]; then
        echo "── $id: transient API error ${retries}× — persistent outage, stopping the loop" >&2
        "$SCRIPTS/notify.sh" "loop.sh hard-stop: transient API error on $id ${retries}× — relaunch to retry" || true
        break 2
      fi
      echo "── $id: transient API error ($retries/$MAX_RETRIES) — retrying in ${RETRY_BACKOFF}s"
      sleep "$RETRY_BACKOFF"
      continue
    fi
    if [ "$rc" -ne 0 ]; then
      # Preserve the full failure and surface a concise reason from claude's JSON
      # result envelope (subtype/is_error/result), not just "nonzero".
      log="$dir/loop-fail.log"
      { echo "# $(date -u +%FT%TZ)  rc=$rc  status=$status  attempt=$n/$MAX_TASKS"
        echo "## reason (claude JSON envelope)"
        echo "$out" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    print("subtype=%s is_error=%s num_turns=%s duration_ms=%s"%(
        d.get("subtype"), d.get("is_error"), d.get("num_turns"), d.get("duration_ms")))
    r=d.get("result") or d.get("error") or ""
    if r: print("result: "+str(r))
except Exception as e:
    print("(stdout was not a JSON envelope: %s)"%e)'
        echo "## stdout(raw)"; echo "$out"
        echo "## stderr"; cat "$errf"
      } >"$log" 2>&1
      # One-line reason for messages + the resume prompt: prefer the last stderr
      # line (where a connection/network error lands), else the parsed envelope.
      fail_reason=$(grep -v '^[[:space:]]*$' "$errf" 2>/dev/null | tail -1 | cut -c1-200)
      [ -n "$fail_reason" ] || fail_reason=$(sed -n '3,4p' "$log" | tr '\n' ' ' | cut -c1-200)
      echo "WARN: claude exited nonzero (rc=$rc) on $id — full detail in $log" >&2
      sed -n '2,6p' "$log" | sed 's/^/    /' >&2
    fi
    cost=$(echo "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("total_cost_usd", 0))' 2>/dev/null || echo 0)
    task_cost=$(python3 -c "print(round($task_cost + $cost, 2))")
    # A stalled resume: the session exited cleanly but committed nothing new — so
    # resuming again would just no-op. Detected by comparing branch tips.
    stalled=; { [ "$rc" -eq 0 ] && [ "$(branch_head "$id")" = "$before" ]; } && stalled=1
    # The merge (task.sh done) runs inside the model session; a session that ends a
    # step early leaves the task in-progress — work committed, unmerged. Drive it to
    # a terminal state rather than accepting that as a failure. This handles the
    # committed-work case; a nonzero exit with NO work falls through to the env-retry
    # guard below (there is nothing to resume).
    if [ "$status" = "in-progress" ] && branch_has_commits "$id"; then
      approved=; [ "VERDICT: approve" = "$(grep '^VERDICT:' "$dir/review.md" 2>/dev/null | tail -1)" ] && approved=1
      # Deterministic finish (no extra model call): merge when the review approved,
      # or when resuming is pointless — the session stalled (no new commit) or the
      # resume budget is nearly spent. task.sh done re-runs verify.sh, so a red tree
      # is never merged; green committed work is finished, not blocked for lack of a
      # review verdict (the failure this guards against).
      if { [ -n "$approved" ] || [ -n "$stalled" ] || [ "$resume" -ge "$((MAX_RESUME - 1))" ]; } \
         && "$SCRIPTS/task.sh" done "$id" >/dev/null 2>&1; then
        status=$(get_field "$dir/task.md" Status)   # done, or pr when DONE=pr
      elif [ "$resume" -lt "$MAX_RESUME" ] && [ -z "$stalled" ]; then
        # Bounded auto-resume: re-invoke the same task. task.sh start resumes its
        # existing branch, so build continues into review + merge. The prior failure
        # reason rides along so the retry doesn't repeat the mistake.
        resume=$((resume + 1))
        park_wip "$id" "wip: interrupted session"
        echo "── $id ended in-progress; resuming to finish ($resume/$MAX_RESUME)"
        prompt="$BUILD_SKILL $id — already in progress on its branch; finish the pipeline (review if needed) and RUN task.sh done to verify + merge. Do not stop until Status is done or blocked.${fail_reason:+ Previous attempt failed: $fail_reason}"
        continue
      else
        # Can't finish and can't usefully resume — block, naming the verify color so
        # a human can tell finished-but-unmerged (GREEN) from genuinely broken (RED).
        if "$SCRIPTS/verify.sh" >/dev/null 2>&1; then vcolor="verify GREEN"; else vcolor="verify RED"; fi
        "$SCRIPTS/task.sh" block "$id" "loop.sh: still in-progress after $resume resume attempt(s); $vcolor${fail_reason:+ — last failure: $fail_reason}"
        status=blocked
      fi
    fi
    # A clean session (rc=0) that ended in-progress with no committed work did
    # nothing to resume or merge — block for a human rather than spin on it.
    if [ "$status" = "in-progress" ] && [ "$rc" -eq 0 ]; then
      "$SCRIPTS/task.sh" block "$id" "loop.sh: session ended in-progress with no committed work"
      status=blocked
    fi
    break
  done
  total_cost=$(python3 -c "print(round($total_cost + $task_cost, 2))")
  # Env failure with no work done: claude errored before anything was committed —
  # status still todo (never started), or in-progress on a zero-commit branch (a
  # drop right after task.sh start). No network, a stranded tree, a crash. Not the
  # task's fault: retry the SAME task up to MAX_RETRIES WITHOUT spending the task
  # budget (n). Abandon a zero-commit in-progress branch first so the retry starts
  # clean and its repo is un-stranded. A standing condition (MAX_RETRIES straight
  # fails) hard-stops with the captured reason; the task is left todo.
  if [ "$rc" -ne 0 ] && { [ "$status" = "todo" ] || [ -z "$status" ] \
       || { [ "$status" = "in-progress" ] && ! branch_has_commits "$id"; }; }; then
    if [ "$status" = "in-progress" ]; then "$SCRIPTS/task.sh" abandon "$id" >/dev/null 2>&1 || true; fi
    retries=$((retries + 1))
    if [ "$retries" -ge "$MAX_RETRIES" ]; then
      echo "── $id failed $retries× before doing any work — giving up (task left todo)"
      "$SCRIPTS/notify.sh" "loop.sh hard-stop: $id failed $retries× with no work — ${fail_reason:-see loop-fail.log}" || true
      break
    fi
    echo "── $id errored before any work ($retries/$MAX_RETRIES) — ${fail_reason:-see loop-fail.log}; retrying in ${RETRY_BACKOFF}s"
    sleep "$RETRY_BACKOFF"
    continue
  fi
  retries=0   # a task that reached a real state clears the transient-failure streak
  n=$((n + 1))
  if [ -n "$SUBSCRIPTION" ]; then
    set_field "$dir/task.md" Cost "subscription"
    echo "── task $id → $status ($n/$MAX_TASKS; subscription; ~\$$task_cost API-equiv)"
  else
    set_field "$dir/task.md" Cost "\$$task_cost"
    echo "── task $id → $status ($n/$MAX_TASKS; \$$task_cost)"
  fi
  if [ -z "$SUBSCRIPTION" ] && python3 -c "exit(0 if $total_cost >= $MAX_COST_USD else 1)"; then
    "$SCRIPTS/notify.sh" "loop.sh stopped: cost cap \$$MAX_COST_USD reached"
    break
  fi
done
if [ -n "$SUBSCRIPTION" ]; then spent="subscription (~\$$total_cost API-equiv)"; else spent="\$$total_cost"; fi
"$SCRIPTS/notify.sh" "loop.sh finished: $n task(s), $spent. $("$SCRIPTS/task.sh" status | tail -n +2 | awk '{print $2}' | sort | uniq -c | tr '\n' ' ')"
