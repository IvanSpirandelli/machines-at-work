# Retro 2026-07-08 · complete, green work blocked because review never produced a verdict

Proposal — **apply by hand in the machines-at-work repo** (`machines-at-work/scripts/{loop.sh,build skill}`);
the plugin is read-only inside projects. Sibling to `2026-07-08-orphaned-in-progress-skip.md` — that retro's
fix #1 (cold-start reconcile) shipped and worked here; this is the *next* failure the same run hit.

## Evidence
After 0037 was rebuilt clean and merged, the loop built **0038** (`Full-bleed pannable/zoomable home`) and
then blocked it:

```
Task 0038 blocked: loop.sh: still in-progress after 3 resume attempts
── task 0038 → blocked
next: blocked task 0038 gates the queue
── stopping: a blocked task gates the queue
```

But the work was **actually finished and green**:
- `flutter analyze` → No issues found.
- `flutter test` → All 136 tests pass, **including the three acceptance-criteria tests** for 0038.
- The branch `task/0038-…` holds a real commit (`0f32d45`, +244 lines). Working tree clean.

So a task that met every acceptance criterion, with a green verify, was marked `blocked` and halted the
whole queue. That is the opposite of what the gate is for.

## Root cause
The build pipeline is implement → review → `task.sh done`. Two facts combined:

1. **No `review.md` was ever produced** for 0038. The review sub-step never wrote a verdict.
2. loop.sh's deterministic safety-net merge merges without another model call **only when** `review.md`
   says `VERDICT: approve` *and* the branch has commits. With no `review.md`, that net can never fire — so
   finishing depended entirely on the model session itself running `task.sh done`.

Each of the 3 resume sessions exited cleanly (`rc=0`) but ended **in-progress**: the model committed its
work, then — on resume — saw an already-committed, already-green tree, concluded it was "done," and ended
the session **without** running review + `task.sh done`. Three no-op resumes exhausted `MAX_RESUME=3`, so
loop.sh ran `task.sh block 0038`, which gated successors and stopped the loop with 4 todo tasks untouched.

## Proposed change
1. **loop.sh — deterministic finish should fall back to "green + committed", not require review.md.** If
   there is no `review.md` but the branch has commits and verify is green, finish it (or spawn one review
   pass) — don't rely on the next resume. A task whose gate is green must never be blocked for lack of a
   review artifact.
2. **build skill — always emit a review verdict, even on a resume that finds work already complete.** The
   review sub-step must write `review.md` with a verdict on every invocation. Removes the missing-artifact
   case at the source.
3. **resume prompt / loop.sh — a resume that changes nothing and stays in-progress is a stall, treat it so.**
   Detect it (rc=0, no new commit, still in-progress) and run the deterministic finish immediately instead of
   burning another resume — or block with a message that says *why*.
4. **block message must carry the verify color.** Include the last `verify.sh` result (GREEN/RED + failing
   repos) in the block reason and notification.

## Manual recovery applied today (for the record)
Confirmed verify GREEN on the 0038 branch → `task.sh reopen 0038` (branch has commits → in-progress) →
`task.sh done 0038` (re-ran verify, green, merged to `main`). No code changed; no work lost. Resumed from 0039.

## Risk
- #1 auto-merging on green-without-review weakens the review gate. Scoped to the *resume/backstop* path only
  (a fresh first build still goes through review). #2 (always emit a verdict) is the cleaner fix and makes #1
  rarely needed.
- All changes are around an already-green tree — none discard committed work or merge a red tree
  (`task.sh done` still runs `verify.sh`).

## Resolution (applied 2026-07-08, v0.10.0)
Implemented all four. (2) build skill step 4 now always spawns the reviewer and writes a verdict, even on a
no-op resume; a branch that already looks finished still flows review → done. (1)+(3) loop.sh's in-progress
backstop finishes deterministically (`task.sh done`, which still runs verify) when the branch has commits and
either the review approved, the resume **stalled** (rc=0 + no new commit, detected via the new `branch_head`
fingerprint), or the resume budget is nearly spent — so green committed work is merged, not blocked, and a
stalled resume doesn't burn the budget. (4) when it must block, the reason names the verify color (GREEN/RED).
See DESIGN.md decision #22.
