# Retro 2026-07-08 · orphaned in-progress task skipped; dependent built out of order

Proposal — **apply by hand in the machines-at-work repo** (`machines-at-work/scripts/{loop.sh,task.sh}`);
the plugin is read-only inside projects. Sibling to `2026-07-08-loop-error-handling.md` (a different
failure mode: that one is *blocked* tasks + no-work crashes; this one is an *orphaned in-progress* task).

## Evidence
A loop run was interrupted (process killed) mid-iteration on **0037** (`Parametric room scene…`):
- 0037 was left `Status: in-progress` with its frontend branch `task/0037-…` holding **0 commits** (it
  pointed at the 0036 tip `10b2ee8`) — i.e. flipped to in-progress but the implementer never committed.
- The **frontend repo was left checked out on `task/0037-…`** (stranded off `main`).
- A fresh loop invocation then ran `task.sh next`, which returned **0038** — skipping the orphaned
  in-progress 0037 — and began `/machines-at-work:build 0038`. **0038 `Depends on 0037`**, so it was building a
  feature on top of a nonexistent prerequisite, in a repo parked on the empty 0037 branch.

Two distinct weaknesses: (1) an orphaned in-progress task is silently skipped by `task.sh next` and never
resumed on a cold start; (2) that skip does **not** gate the orphan's dependents, so a dependent runs out
of order on a missing prerequisite.

## Root cause
- `loop.sh`'s resume-to-finish path (the `status = in-progress` block) only fires **within the same
  iteration** that just built the task — it reads the local `status` var. A **fresh** loop invocation
  never sees the orphan: it calls `task.sh next`, which skips in-progress and returns the next `todo`.
- `task.sh next`'s dependency gate blocks a successor behind a `todo`/`blocked` dependency but **not** an
  `in-progress` one (treated as "in flight, will land"). For an *orphaned* in-progress dep that assumption
  is false, so 0038 was released.
- Recovery friction: `task.sh reopen 0037` with the (empty) branch still present **kept** it in-progress
  (`reopened 0037 (branch exists)`); it only dropped to `todo` after the empty branch was deleted **by
  hand**. There is no `task.sh` verb to cleanly abandon/restart a zero-work in-progress task.

## Proposed change

### 1) `loop.sh` — reconcile any in-progress task on cold start, before `task.sh next`
Before the main selection loop, detect an existing in-progress task and either resume it (mirror the
in-iteration resume path) or, if its branch has 0 commits vs `DEFAULT_BRANCH`, abandon it back to `todo`.
This closes the "killed mid-iteration → orphan never resumed" gap.

### 2) `task.sh next` — gate successors behind a not-done dependency, not just todo/blocked
An `in-progress` dependency should gate its dependents too (a dep is satisfied only when `done`/`pr`).
This prevents 0038 from being released while 0037 is unfinished, regardless of how 0037 got stuck.

### 3) `task.sh` — treat a zero-work branch as "no work" on reopen; add an explicit abandon
`task.sh reopen <id>`: if `git log DEFAULT_BRANCH..task/<id>` is empty, delete the branch and set `todo`
(a resumable branch with commits keeps today's behavior). Add `task.sh abandon <id>` for a clean restart
so operators don't hand-delete branches (as was required here).

### 4) Un-strand repos on interrupt/block (reinforces prior retro #3, still unapplied)
The frontend was left on `task/0037-…` after the kill — the same stranding the sibling retro flagged for
`task.sh block`. Restoring repos to `DEFAULT_BRANCH` should also happen on cold-start reconcile (#1), since
a stranded repo breaks `preflight` for every later task.

## Manual recovery applied today (for the record)
Killed loop + 0038 build → `git -C frontend checkout main` → deleted empty `task/0037` branch →
`task.sh reopen 0037` (now `todo`) → reverted a stray `Cost:` edit the aborted 0038 build left. Tree clean;
0037 and 0038 both `todo`; `task.sh next` → 0037. Loop restart left to the operator.

## Risk
- #2 is the sharpest behavior change: if a task set intentionally runs dependents alongside an in-progress
  dep, gating would serialize them. For this project's strictly dependency-ordered sets, serializing is the
  safe default. Guard with the existing `CONTINUE_ON_BLOCK`-style override if broader parallelism is wanted.
- #1/#3 only act on a zero-commit branch, so no committed work is ever discarded.

## Resolution (applied 2026-07-08, v0.9.0)
Implemented as a consolidation of #1–#4: `task.sh next` returns the first todo **or** in-progress task in
id order — one change that both self-heals the orphan (loop.sh builds it, `task.sh start` resumes its
branch) and gates its dependents (an unfinished task sorts first and holds the queue). `loop.sh` reconciles
at cold start (empty orphan → `abandon`, committed orphan → resume). New `task.sh abandon <id>` un-strands
repos and deletes the branch via `git branch -d` (refuses unmerged commits); `reopen` abandons an empty
branch instead of keeping it in-progress. `cmd_block` was deliberately left un-stranding its repo (blocked
WIP is committed and inspected there; the `next` gate already stops the cascade). See DESIGN.md decision #21.
