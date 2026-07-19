# Proposal 2026-07-19 · headless /plan (for Telegram triggers)

Proposal — **apply by hand in the machines-at-work repo**. Touches `skills/plan/SKILL.md`
only. Bump plugin version.
Motivated by `server-orchestrator/proposals/2026-07-19-emoji-keyword-triggers.md`: the
daemon spawns `claude -p "/machines-at-work:plan headless"` when 🧠 lands in a project's
topic. Two steps of the plan skill assume an interactive user and would strand a headless run.

## Evidence

- Step 1: "If there are no notes to plan, ask the user what to build and stop" — headless,
  there is no one to ask; the session ends silently and the phone hears nothing.
- Step 4: "present the list … to the user for approval" — headless, nobody can approve;
  the run stalls or the plan dies unseen.

## Proposed change

Add a headless branch, keyed on the literal argument `headless` (deterministic — no
"detect if anyone is listening" judgment):

1. **Step 1, no notes:** when `$ARGUMENTS` contains `headless`, run
   `${CLAUDE_PLUGIN_ROOT}/scripts/notify.sh "plan: nothing queued — text intent first"`
   and stop, instead of asking.
2. **Step 4/5, approval:** when headless, skip the interactive gate — create the tasks
   (step 5) and post the resulting task list (titles + feature grouping) to the topic via
   `notify.sh`. The human approves by sending 🚀, or corrects by texting a note and 🧠
   again. The approved-plan contract (DESIGN #13/#26) survives — the approval moved from
   a terminal reply to a Telegram message; no build starts without it.

Interactive behavior is unchanged when the argument is absent.

## Verify

`claude -p "/machines-at-work:plan headless"` in a workspace with (a) no notes → one
notify.sh message, no tasks, clean exit; (b) one queued `.inbox/` message → note drained
and committed, tasks created, task list posted via notify.sh, no prompt ever shown.

## Risks

Tasks now exist before any human said yes. Accepted: tasks are cheap and revisable
(`task.sh` edits, re-plan), and `loop.sh` still only starts on an explicit 🚀.
