---
name: plan
description: Decompose the intent notes in machines-at-work/updates/ into small, verifiable tasks. Run after dropping a note (or a batch).
disable-model-invocation: true
argument-hint: "[which note or area to plan, default: all unplanned]"
---

Turn the notes in `machines-at-work/updates/` into tasks. Focus: $ARGUMENTS

Headless mode — when $ARGUMENTS contains `headless` (Telegram-triggered, nobody at a terminal): never prompt; anything a step below would say or ask goes through `${CLAUDE_PLUGIN_ROOT}/scripts/notify.sh` instead.

1. Drain the topic inbox: run `${CLAUDE_PLUGIN_ROOT}/scripts/inbound.sh` so any messages texted into this project's Telegram topic land as notes in `updates/` before you plan (no-op if none). Then commit any uncommitted notes as-written — the user's words stay in git history, and that history *is* the record of intent (there is no living spec document to maintain). Ignore `README.md`. If there are no notes to plan, ask the user what to build and stop (headless: notify "plan: nothing queued — text intent first" and stop).
2. Read the notes, `machines-at-work/tasks/_log.md`, and `${CLAUDE_PLUGIN_ROOT}/scripts/task.sh status` output. Plan only what the notes ask for and is not already covered by a task — nor already present in the code: in a pre-existing codebase, check the repos before tasking described behavior.
3. Draft the task list. Each task MUST have:
   - a goal one implementer can finish and verify in a single green run,
   - testable acceptance criteria ("WHEN <condition> THE SYSTEM SHALL <behavior>"),
   - explicit non-goals ("don't touch X"),
   - the repos it spans (cross-repo only when the feature genuinely spans them).
   Too big to verify in one run → split it. Vague note → ask the user now, not the implementer later.
   If `DONE=pr` in agents.env, also group the tasks into **features** — one feature = one coherent, reviewable PR. Tasks in a feature land as single commits on a shared `feature/<slug>` branch and the PR opens when its last task finishes, so dependencies *within* a feature are fine; avoid depending on a task in a different, still-unmerged feature. A one-off task may stay featureless (it gets its own PR).
4. Order by dependency, then present the list (with its feature grouping) to the user for approval — the approved plan is the human's contract with the pipeline (headless: skip the prompt and proceed; approval is the 🚀 message that starts the build, sent after the human reads the list you post in step 5). Decomposition quality is the leading indicator of pipeline success — spend your effort here.
5. On approval, if `LINEAR_TEAM_KEY` is set in agents.env **and** `DONE=pr` (Linear links via the pushed PR branch, so it is meaningless under `DONE=local`), first create one issue for this whole plan run: `${CLAUDE_PLUGIN_ROOT}/scripts/linear.sh create "<plan title>" "<the task list as a markdown checklist, grouped by feature>"` — it prints `<KEY>\t<url>`. Then prefix every feature slug with the key lowercased (`eng-123-<slug>`) so each PR's branch auto-links to the issue, and group **every** task into a feature (wrap a one-off in its own feature — a featureless task's branch never carries the key). Skip this whole step if the key is unset.
   For each task run `${CLAUDE_PLUGIN_ROOT}/scripts/task.sh new "<title>" ["<repos>"] ["<feature-slug>"]` (each records the note commit it was planned from as `Intent:`) and fill Goal / Acceptance criteria / Non-goals in the created task.md. Then delete the notes you fully planned and commit the deletion — git history keeps them; `machines-at-work/updates/` holds only unplanned intent. Do not implement anything. Headless: finish by posting the created task list (titles + feature grouping, and the Linear url if one was created) via notify.sh — that post is what the human approves with 🚀.
