---
name: plan
description: Decompose the spec (scaffold/specs/*.md) into small, verifiable tasks. Run after writing or changing the spec.
disable-model-invocation: true
argument-hint: "[section of spec to plan, default: all unplanned]"
---

Turn `scaffold/specs/` into tasks. Focus: $ARGUMENTS

1. If `scaffold/specs/` has uncommitted changes, commit them — each new task records the spec commit it was planned from (`Spec:` in task.md).
2. Read all `scaffold/specs/*.md`, `scaffold/tasks/_log.md`, and `${CLAUDE_PLUGIN_ROOT}/scripts/task.sh status` output. Only plan what is specced and not yet covered by a task.
3. Draft the task list. Each task MUST have:
   - a goal one implementer can finish and verify in a single green run,
   - testable acceptance criteria ("WHEN <condition> THE SYSTEM SHALL <behavior>"),
   - explicit non-goals ("don't touch X"),
   - the repos it spans (cross-repo only when the feature genuinely spans them).
   Too big to verify in one run → split it. Vague spec → ask the user now, not the implementer later.
4. Order by dependency, then present the list to the user for approval. Decomposition quality is the leading indicator of pipeline success — spend your effort here.
5. On approval, for each task run `${CLAUDE_PLUGIN_ROOT}/scripts/task.sh new "<title>" ["<repos>"]` and fill Goal / Acceptance criteria / Non-goals in the created task.md. Do not implement anything.
