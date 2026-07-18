# Retro 2026-07-16 · retire the living spec; intent notes are the only input surface

Proposal — **apply by hand in the machines-at-work repo** (the plugin is read-only inside projects).
Touches `skills/{init-project,plan,retro}/SKILL.md`, `scripts/task.sh`, `templates/CLAUDE.template.md`,
and DESIGN.md #13. Supersedes the pending init-spec-gap changes (they patched a workflow this removes).

## Evidence / observation
Not an incident — a design review of what `specs/` earns. Every consumer, traced:

- `init-project`: creates `specs/spec.md` and tells the user to "write the spec first."
- `plan`: absorbs `specs/updates/` into a living `specs/*.md`, commits, decomposes into tasks, stamps `Spec:`.
- `retro`: uses the `Spec:` commit to tell *misunderstanding* (pipeline defect) from *changed requirements*.
- `task.sh` / template CLAUDE.md: write and document the field.

Only `plan` and `retro` use the spec as more than a funnel — and even there:

1. **It doesn't drive tasks.** The task *driver* is the delta (`specs/updates/`) plus a "not yet covered"
   check against `tasks/` and the repos. The accumulated living document is re-read but generates nothing;
   it functions as a coverage ledger, not a spec.
2. **It's imprecise where it matters.** In a mature codebase the code is the source of truth; `plan` already
   half-admits this (line 12: "check the repos before tasking specced behavior"). A retrofitted spec is a
   lossy copy that drifts.
3. **It contradicts DESIGN #3.** #3 forbids "a separate TODO list to drift" and makes `tasks/` the single
   source of truth for *status*. The living spec is exactly such a second ledger, for *intent* — same drift
   risk, opposite ruling.

## Root cause
The spec model is greenfield-shaped: `write spec -> plan -> build`. That shape assumes intent lives in a
document because there is no code yet. Once code exists, the document's three claimed jobs each collapse:

- **Source of truth** -> the code is, plus the *first* intent note (which flows through `updates -> plan`
  like any other; the accumulated document adds nothing).
- **The human's contract with the pipeline** (DESIGN #13) -> redundant with the **task plan**, which the
  human already approves at `/plan` time and which is more concrete (tasks are what actually run).
- **Retro's misunderstanding-vs-evolution discriminator** -> recoverable *more directly* from the intent note
  that spawned the rework: "actually make it X" is a correction (pipeline signal); "now also do Y" is
  evolution. Read intent from the note, not from diffing two spec versions.

## Proposed change

### 1) One flat input surface, no `specs/` tree
Replace `machines-at-work/specs/` and its `specs/updates/` subfolder with a single flat folder of intent notes -
`machines-at-work/updates/` (sibling of `tasks/`). No living document to maintain, no subfolder nesting. A note is
the human's words; git history of the folder is the durable record of intent. Notes are consumed by `/plan`
and deleted (or archived) - they are not accumulated into a standing document. `updates/` names what the
folder is - a stream of consumed deltas - rather than `specs/`, which would keep re-summoning the
living-document model this proposal removes.

### 2) `/plan` — decompose the delta, drop the absorb step
`plan` reads unplanned notes in `updates/` + `tasks/_log.md` + `task.sh status` + repo state, then
decomposes into tasks/features. Remove step 1 (absorb-into-spec) and the spec-diff approval; the human
approves the **task plan** instead. `plan` commits the notes as-written (words stay in history), then plans.

### 3) `Spec:` -> `Intent:` in `task.md`
`task.sh` stamps `Intent: <note-commit>` (the commit that introduced the spawning request) instead of
`Spec:`. One field rename in `task.sh` (line 46) and the task template.

### 4) `/retro` — read the spawning note, not a spec diff
Rework signal (step 3) reads the `Intent:` note to classify correction vs new requirement. Same
discrimination, one fewer artifact.

### 5) `init-project` + template CLAUDE.md — no "write the spec first"
Onboarding becomes uniform: greenfield drops one big intent note describing the whole system; a mature
project drops its first change note. Both flow through `updates -> plan -> build`. No retrofit-a-spec
make-work, which was the pending init-spec-gap friction - this removes its cause rather than patching it.

### 6) DESIGN.md #13 — rewrite
Reframe: intent iteration = drop a note in `updates/`, replan the delta; the durable record is git history
of the notes; the human's contract is the approved task plan; `Intent:` links each task to its spawning
note for retro traceability. Remove the living-spec / `specs/updates/` / spec-diff-approval machinery.

## Risk
- **Loses the single-document "what is this system?" view.** The one real casualty: a human can no longer
  read one accumulated spec. But that is a *product* doc, not a *pipeline* input - a drifting one is worse
  than none, and anyone who wants it can keep a `README`/design doc the pipeline doesn't depend on. Calling
  this out so the removal is a deliberate trade, not an oversight.
- **Retro discrimination leans on note quality.** A terse note ("fix login") classifies worse than a spec
  diff. Mitigation: notes already carry the human's framing; the reviewer/feedback signals `/retro` mines
  are unchanged. Net: same evidence, one fewer indirection.
- **Migration for a project mid-flight.** Existing `specs/` + `Spec:` fields: leave old task.md fields as-is
  (historical), point new tasks at `Intent:`. `/retro` reads whichever field a task carries.

## Decisions settled with the human
- No subfolder (settled).
- Folder name: `updates/`. Rejected `specs/` (re-summons the living-document model) and `requests/`.
  Trade-off accepted: calling a greenfield project's first note an "update" is cosmetically odd at t=0, but
  the word matches the steady state (updates all the way down). One-word swap if reversed later.

## Resolution (staged 2026-07-16, v0.13.0 — smoke green on the merged tree)
Implemented as changes 1–6:
- `scripts/task.sh` — `snapshot_ws` and `cmd_new` read `updates/` not `specs/`; the task.md field is
  `Intent:` (last commit touching `updates/`) not `Spec:`.
- `skills/plan/SKILL.md` — reads `machines-at-work/updates/` (ignores `README.md`), drops the absorb-into-spec step
  and spec-diff approval (the human approves the task plan), records `Intent:`, removes planned notes.
- `skills/init-project/SKILL.md` — creates `machines-at-work/updates/README.md` (not `specs/spec.md`); onboarding
  tells the user to drop a first note.
- `skills/retro/SKILL.md` — rework signal reads the `Intent:` note (`git show`) instead of a spec diff.
- `templates/` — `spec.md` **deleted**, replaced by `updates-README.md` (keeps the WHEN/SHALL + out-of-scope
  guidance as note-writing advice); `CLAUDE.template.md` reworded.
- `README.md` — headline, quickstart, iterate paragraph, workspace-anatomy line.
- `DESIGN.md` — spine diagram `specs/`→`updates/`, #13 rewritten, #24 ref updated, new decision #26.
- `.claude-plugin/plugin.json` — 0.12.0 → 0.13.0.
- `tests/smoke.sh` — asserts the `Intent:` field; full smoke run green.

Migration (project mid-flight): rename `machines-at-work/specs/updates/*` up to `machines-at-work/updates/`, drop
`machines-at-work/specs/spec.md`; leave old tasks' `Spec:` fields as historical (`/retro` reads whichever field a
task carries). Supersedes the staged-but-unapplied `2026-07-15-init-spec-gap` changes — do not apply those.
