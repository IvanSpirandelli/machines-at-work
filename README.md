# Agentic Engineering Scaffold

A Claude Code plugin that turns a spec file into working software through a verify-gated task loop: fresh-context implementer (TDD) → deterministic verification → fresh-context reviewer → one squash-commit per feature per repo. Everything mechanical is a script; LLMs only where judgment is needed. Rationale: `DESIGN.md`.

## Install (once)

```
/plugin marketplace add [path-to-cloned-repo]
/plugin install scaffold@agentic-scaffold
```

Enable per workspace in `.claude/settings.json` (init-project does this): `{"enabledPlugins": {"scaffold@agentic-scaffold": true}}`.
Propagate improvements to all projects: commit here, then `/plugin marketplace update agentic-scaffold`.

## Use

```
mkdir my-product && cd my-product && claude
/scaffold:init-project          # interview → agents.env, spec.md, tasks/, repos
# write spec.md
/scaffold:plan                  # spec → sized, verifiable tasks in tasks/
/scaffold:build all             # interactive: implement → verify → review → merge
scripts/loop.sh                 # headless: fresh context per task, cost/task caps
```

Human touchpoints: approve the plan, read `NEEDS_HUMAN.md` when a task blocks, write `tasks/<id>-*/feedback.md` after reviewing merged work, run `/scaffold:retro` to turn feedback into scaffold-improvement proposals (you apply them here — agents can't edit the plugin, a hook enforces it).

## Layout

```
agents/       implementer, reviewer            (the only standing agents)
skills/       init-project, plan, build, design, retro, toolsmith
scripts/      task.sh (lifecycle) · verify.sh (gate) · preflight.sh ·
              loop.sh (headless driver) · notify.sh (human comms seam) · lib.sh
hooks/        guard.py — blocks force-push, push-to-default, destructive rm,
              plugin self-modification
templates/    project-side starter files
DESIGN.md     every decision + why
```

## Workspace anatomy (per project)

```
my-product/
  agents.env      repos + verify commands (validated by preflight)
  spec.md         product spec — the human's input
  tasks/          SINGLE SOURCE OF TRUTH: NNNN-slug/{task,review,feedback,design}.md
  tasks/_log.md   one line per merged task (bounded memory)
  NEEDS_HUMAN.md  escalations
  <repo>/         code repos, each its own git repo
```
