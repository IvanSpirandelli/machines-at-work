# Workspace: {{PROJECT_NAME}}

Scaffold workspace. Product spec: `spec.md`. Task state (single source of truth): `tasks/` — status lives in each `task.md`; digest in `tasks/_log.md`. Config: `agents.env`. Escalations: `NEEDS_HUMAN.md`.

Pipeline: `/scaffold:plan` → `/scaffold:build` (or `scripts/loop.sh` headless). Mechanics (branching, merging, verification) are scripts under the scaffold plugin — never do them by hand.

Rules:
- Never commit to the default branch directly; `task.sh done` merges.
- Never mark work done with a red `verify.sh`.
- Repos: see `agents.env`. Workspace files (spec, tasks) are versioned here, code lives in the repo subdirectories.
