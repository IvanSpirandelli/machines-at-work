---
name: plan
description: Decompose spec.md into small, verifiable tasks in tasks/. Run after writing or changing the spec.
disable-model-invocation: true
argument-hint: "[section of spec to plan, default: all unplanned]"
---

Turn `spec.md` into tasks. Focus: $ARGUMENTS

1. Read `spec.md`, `tasks/_log.md`, and `${CLAUDE_PLUGIN_ROOT}/scripts/task.sh status` output. Only plan what is specced and not yet covered by a task.
2. Draft the task list. Each task MUST have:
   - a goal one implementer can finish and verify in a single green run,
   - testable acceptance criteria ("WHEN <condition> THE SYSTEM SHALL <behavior>"),
   - explicit non-goals ("don't touch X"),
   - the repos it spans (cross-repo only when the feature genuinely spans them).
   Too big to verify in one run → split it. Vague spec → ask the user now, not the implementer later.
3. Order by dependency, then present the list to the user for approval. Decomposition quality is the leading indicator of pipeline success — spend your effort here.
4. On approval, for each task run `${CLAUDE_PLUGIN_ROOT}/scripts/task.sh new "<title>" ["<repos>"]` and fill Goal / Acceptance criteria / Non-goals in the created task.md. Do not implement anything.
