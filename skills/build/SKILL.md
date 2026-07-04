---
name: build
description: Run the pipeline for one task (or the next todo one) — implement, verify, review, squash-merge.
disable-model-invocation: true
argument-hint: "[task-id | all]"
---

Target: $ARGUMENTS (empty or `all` → use `task.sh next`).
Scripts: `${CLAUDE_PLUGIN_ROOT}/scripts/`. You orchestrate; you do not write code yourself.

1. `preflight.sh --quick`; then `task.sh start <id>`.
2. Spawn the `implementer` agent: "Implement task <id>. Folder: tasks/<id>-<slug>/". If UI-heavy and no design.md exists, run /scaffold:design first.
3. `RESULT: blocked` → `task.sh block <id> "<question>"`, report to user, stop this task.
4. Spawn the `reviewer` agent on the task. Then:
   - `VERDICT: approve` → step 5.
   - `VERDICT: blocking` and Rounds < 2 → increment Rounds in task.md, send ONLY the blocking findings back to the implementer to fix, then review again.
   - still blocking at Rounds = 2 → `task.sh block <id> "review did not converge: <summary>"`, stop this task.
5. `task.sh done <id>` (verifies green, squash-merges one commit per repo, logs). If it fails, treat the failure output as a blocking finding: one repair round, then block.
6. Report ≤5 lines to the user: task, verdict, commits, cost if known, anything odd.
7. If the argument was `all`, repeat from step 1 until `task.sh next` is empty; stop immediately if two consecutive tasks end blocked.

Never edit code yourself, never merge manually, never bypass a red verify.
