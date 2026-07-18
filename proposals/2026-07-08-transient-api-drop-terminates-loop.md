# Retro 2026-07-08 · a transient API drop terminated the whole headless loop

Proposal — **apply by hand in the machines-at-work repo** (`machines-at-work/scripts/{loop.sh,lib.sh}`);
the plugin is read-only inside projects. Sibling to `2026-07-08-loop-error-handling.md` (which added the
*status=todo* transient-retry path) and `2026-07-08-green-work-blocked-no-review.md`. This is the gap those
two left: a transient drop that lands **after** the task flips to in-progress kills the entire run.

## Evidence
Headless run of the 0039–0042 batch. Preflight green, loop started **0039** (a backend task), then:

```
══ task 0039 (task 1/5, spent subscription)
Solving task with OPUS
── 0039 ended in-progress; resuming to finish (1/3)
=== loop.sh exited rc=1 ===        # ← the whole loop died here, mid-resume
```

`0039/loop-fail.log` captured the real cause — a **transient network error**, not a task failure:

```
# 2026-07-08T17:15:41Z  rc=1  status=in-progress  attempt=0/5
subtype=success is_error=True num_turns=7 duration_ms=42642
result: API Error: Connection closed mid-response. The response above may be incomplete.
```

State after the death: 0039 `in-progress` with a **zero-commit** branch (dropped after `task.sh start`, before
any work landed), backend repo **stranded on `task/0039-…`**, and 0040–0042 untouched. A **manual relaunch**
was required; the next run's cold-start reconcile then abandoned the empty 0039 → todo, rebuilt it, and
finished 0040–0042 cleanly. So the batch only completed because a human noticed and re-ran it.

## Root cause (in `loop.sh`)
loop.sh classifies exactly two non-task failure modes gracefully: **usage/rate limit** (park, sleep to reset,
retry — never against budget) and **out of credits** (park, clean `exit 4`). A **transient API/connection
error** is neither, so it falls through to the generic `rc -ne 0` path, and two things go wrong:

1. **It's routed into bounded auto-resume, not transient-retry.** The transient-retry logic (from the sibling
   retro) only fires when `status = todo`. But `/machines-at-work:build` runs `task.sh start` early, so by the drop
   the task is **`in-progress`** — even with 0 commits. The in-progress branch treats a network blip as
   "session made progress, resume it," counting against `MAX_RESUME`, instead of "no work done → retry."
2. **The loop terminated with rc=1 instead of surviving the blip.** Under `set -euo pipefail`, a command in
   the resume iteration returned nonzero and propagated, ending the whole run after a single transient error.
   The two recognized modes never do this; an unrecognized one bringing down the loop is the defect.

## Proposed change
1. **`lib.sh` — add `is_transient_api_error`** next to `limit_wait` / `is_out_of_credits`: matches
   "connection closed mid-response", ECONNRESET/ETIMEDOUT, 5xx/overloaded, service unavailable, etc.
2. **`loop.sh` — handle a transient drop before the generic path, regardless of status.** No committed work →
   `abandon` (clean restart, un-stranded); work landed → `park_wip`. Retry the SAME task on `MAX_RETRIES` /
   `RETRY_BACKOFF`, **without** spending `MAX_RESUME`; hard-stop only on a persistent outage.
3. **`loop.sh` — the transient/env guard must not key on `status = todo` alone.** Widen it so a nonzero exit
   with an in-progress-but-zero-commit branch counts as "no work done," not resume. (#2 is primary; #3 is
   defense in depth.)
4. **The block/stop message should name it as transient**, so the operator knows a plain relaunch clears it.

## Manual recovery applied (for the record)
Relaunched `loop.sh`. Cold-start reconcile saw 0039 in-progress + empty → `abandon` → todo (backend restored
to `main`) → rebuilt 0039 → continued 0040–0042. All merged; final verify GREEN. No work lost.

## Risk
- #2 retries on a substring match; a genuine failure whose text contains e.g. "internal server error" would be
  retried up to `MAX_RETRIES`. Mitigated by the cap + hard-stop notification; keep the regex tight and prefer
  the JSON envelope's `result` field over raw stderr.
- All paths either retry after backoff or hard-stop; none merge work or discard commits (`abandon` only
  touches zero-commit branches; `park_wip` preserves committed work).

## Resolution (applied 2026-07-08, v0.10.0)
Implemented all four. (1) `is_transient_api_error` added to lib.sh. (2) loop.sh handles a transient drop right
after the out-of-credits check, reading claude's JSON `result` field (not raw stderr) to avoid misreading a
task's own error text: 0-commit → `abandon` + fresh prompt, committed → `park_wip`, then retry on
`MAX_RETRIES`/`RETRY_BACKOFF` via `continue`, hard-stopping with `break 2` on a persistent outage — never
touching `MAX_RESUME`. (3) the env-retry guard now also matches an in-progress zero-commit branch (abandoning
it first), and the in-progress backstop only fires when there is committed work. (4) messages name it
"transient API error". See DESIGN.md decision #23.
