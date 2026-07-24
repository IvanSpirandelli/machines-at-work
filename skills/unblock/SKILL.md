---
name: unblock
description: Diagnose why the build queue is stuck and auto-resolve the safe cases (finished-but-unmerged, clean retry), escalating the rest with a precise reason.
disable-model-invocation: true
argument-hint: "[task-id | all] [headless]"
---

Target: $ARGUMENTS (empty or `all` → every blocked/in-progress item). You diagnose and orchestrate; you never write code, never bypass a red verify, never merge by hand.
Scripts: `${CLAUDE_PLUGIN_ROOT}/scripts/`.

Headless mode — when $ARGUMENTS contains `headless` (Telegram-triggered, nobody at a terminal): never prompt; the closing summary goes through `${CLAUDE_PLUGIN_ROOT}/scripts/notify.sh`.

1. Run `${CLAUDE_PLUGIN_ROOT}/scripts/task.sh diagnose`. It prints one global `verify:` color; per stuck item `commits=`, `review=`, `faillog=`, and the NEEDS_HUMAN `reason:`; and a `workspace <repo> dirty on <branch>` line for any repo with an uncommitted tree — a crashed session's leftover that preflight hard-fails on even when no task is blocked/in-progress (the block `unblock` used to be blind to). `(nothing blocked or in-progress)` → say so and stop. If a task id was given, act only on it.
2. For each item, read the evidence before deciding: the `reason:` line, `tasks/<id>/loop-fail.log` (Claude's failure envelope — read the tail) when `faillog=yes`, and `tasks/<id>/review.md` when the reason is about review. Classify against the table below.
3. **Auto-resolve only the safe, mechanical cases** — do these, then re-run `task.sh diagnose` to confirm the item cleared:
   - **Finished but unmerged** — `commits=yes` and `verify: GREEN` (the work is done; only the merge/PR step never ran, e.g. reason "still in-progress … verify GREEN"): `task.sh reopen <id>` then `task.sh done <id>`. Report the commits or PR URL. `done` re-runs verify, so it self-guards; if it fails, treat that as RED (escalate) — do not retry-loop.
   - **Nothing built** — `commits=no` (the session died before landing work: env crash, transient API drop, usage/credit stop): `task.sh reopen <id>`. Its branch is empty, so reopen resets the task to `todo` and un-strands its repo — a clean retry on the next build. Note the original reason so the human knows what stalled it (a credit stop still needs a top-up or `MODEL=` switch before the retry can succeed).
   - **Dirty workspace** — a `workspace <repo> dirty on <branch>` line (a crashed session left uncommitted edits; preflight fails on it though no task is blocked): `task.sh clean-repo <repo>`. It recoverably stashes the tree (`git stash push -u` — never discards; recover with `git -C <path> stash list`), so preflight passes on the next build. Report the stash so the human can inspect/recover it if the leftover mattered. (`reopen` on a `todo`/no-commits task does NOT clean the tree — clean-repo is the piece that does.)
4. **Escalate everything else** — do not touch code or force a merge. Leave the item blocked and record a crisp, specific line (the *why* plus the recommended human action) — these are judgment calls the safe pass deliberately won't guess at:
   - `verify: RED` with `commits=yes` → genuinely broken code; name the failing repo/finding from loop-fail.log and recommend a rebuild (`/machines-at-work:build <id>`).
   - reason mentions review did not converge → summarize the blocking finding from review.md.
   - a real implementer question in the reason → surface the question verbatim (answering it is the human's call).
   - a **feature** blocked, or a task reason "PR closed without merge" / "merged before this task landed" → a human decision (why it closed / replan against the fresh base); say which.
5. If `diagnose` reports `(nothing blocked or in-progress)` yet `updates/` still holds unplanned notes, the stall is upstream of the build queue — the plan step never ran or failed. Say so and point to re-running `/machines-at-work:plan` (headless: 🧠); do not plan here.
6. Close with a summary: what you auto-resolved, and each item still needing a human with its one-line reason. If you reset any task to `todo` or merged finished work, note the queue is now clear to run `/machines-at-work:build all` (headless: 🚀). Headless → post the summary via `notify.sh`. NEEDS_HUMAN.md stays the durable record; append nothing the diagnosis didn't establish.

Never edit code, never merge manually, never bypass a red verify. When unsure whether a case is safe, escalate — a wrong auto-fix is worse than an honest escalation.
