# Workspace: {{PROJECT_NAME}}

Machines at Work workspace. Intent notes: `machines-at-work/updates/` — drop a note (any shape) describing what to build or change, then run `/machines-at-work:plan`; your words are committed to git history (the record of intent — there is no living spec). Task state (single source of truth): `machines-at-work/tasks/` — status lives in each `task.md`; digest in `tasks/_log.md`. Config: `machines-at-work/agents.env`. Escalations: `machines-at-work/NEEDS_HUMAN.md`.

Pipeline: `/machines-at-work:plan` → `/machines-at-work:build` (or `scripts/loop.sh` headless). Mechanics (branching, merging, verification) are scripts under the machines-at-work plugin — never do them by hand.

Rules:
- Never commit to the default branch directly; `task.sh done` merges (or opens a PR when `DONE=pr`).
- Never mark work done with a red `verify.sh`.
- Repos: see `machines-at-work/agents.env`. Machines at Work state is versioned by this root repo; code lives in the top-level repo directories (each its own git repo, ignored here).
