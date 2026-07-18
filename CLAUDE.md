# Machines at Work repo (plugin development)

You are editing machines-at-work itself, not using it. Read `DESIGN.md` before changing behavior — every decision there has a reason.

Rules:
- Concision is a feature: agent/skill prompts earn every line ("would removing this cause a mistake?"). CLAUDE.mds < 200 lines.
- Mechanics belong in `scripts/` (deterministic), judgment in `agents/`/`skills/` (LLM). Never move logic from script to prompt.
- After editing scripts: `bash -n` them and run the smoke test in `tests/smoke.sh`.
- Changes motivated by a project retro should reference the proposal file in the commit message.
- Bump `version` in `.claude-plugin/plugin.json` on behavior changes.
