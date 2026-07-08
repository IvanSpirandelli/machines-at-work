# Agentic Engineering Scaffold

A Claude Code plugin that turns a spec file into working software through a verify-gated task loop: fresh-context implementer (TDD) → deterministic verification → fresh-context reviewer → one squash-commit per feature per repo (or, for shared repos, a pre-reviewed PR — `DONE=pr`). Everything mechanical is a script; LLMs only where judgment is needed. Rationale: `DESIGN.md`.

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
/scaffold:init-project          # interview → scaffold/ (state) + code repos
# write scaffold/specs/spec.md
/scaffold:plan                  # specs → sized, verifiable tasks
/scaffold:build all             # interactive: implement → verify → review → merge
$SCAFFOLD/scripts/loop.sh      # headless: fresh context per task, cost/task caps, rides out usage limits
```

Team repo (you're the only plugin user): set `DONE=pr` in `scaffold/agents.env`. Preflight fetches a fresh `origin/<default>` base, `task.sh done` pushes the task branch and opens a pre-reviewed PR instead of merging, and `task.sh sync` (run by preflight) completes tasks once their PRs merge. A red upstream parks `loop.sh` (retry after `UPSTREAM_BACKOFF`) instead of blocking tasks.

Iterate: drop update notes (any shape) in `scaffold/specs/updates/` and re-run `/scaffold:plan` — it integrates them into the living spec (your words are committed verbatim first; you approve the spec diff), then plans only the uncovered delta. Editing `scaffold/specs/` directly works too. Old spec versions live in the workspace's git history, not as spec_2 files; each task.md records the spec commit it was planned from (`Spec:`), and `/scaffold:retro` uses cross-version rework as evidence.

Human touchpoints: approve the plan, read `scaffold/NEEDS_HUMAN.md` when a task blocks, write `scaffold/tasks/<id>-*/feedback.md` after reviewing merged work, run `/scaffold:retro` to turn feedback into scaffold-improvement proposals (you apply them here — agents can't edit the plugin, a hook enforces it).

## Scripts

The mechanics live in `scripts/` inside the plugin, not in your workspace. Claude sessions reach them via `${CLAUDE_PLUGIN_ROOT}/scripts/…`; from your own terminal use the plugin root — for a directory-source marketplace that is simply where you cloned this repo (check `installLocation` in `~/.claude/plugins/known_marketplaces.json`). Set it once:

```
export SCAFFOLD=~/path/to/agentic-engineering-scaffold
```

Every script finds the workspace on its own by walking up from the current directory until it hits `agents.env` (directly or in a `scaffold/` child). So they run identically from the project root, from `scaffold/`, or from inside any code repo — `cd backend && $SCAFFOLD/scripts/verify.sh backend` works. The only requirement is being *somewhere below* the project root; there are no path arguments to get wrong.

| Script | What it does |
|---|---|
| `preflight.sh [--quick]` | Validate before agents run: repos exist and are clean, config sane, then a full verify run (`--quick` skips the verify). With `DONE=pr` it also checks `gh` auth + origin, fast-forwards each repo's default branch, and runs `task.sh sync`. Exit 3 means origin's default branch itself is red (wait it out, not your fault). |
| `verify.sh [repo …]` | The deterministic quality gate: runs each repo's `VERIFY_<repo>` command from agents.env. No args = all repos. Run it any time; it changes nothing. |
| `task.sh new "<title>" [repos]` | Create the next `NNNN-slug` task folder; prints the id. Then fill in Goal / Acceptance criteria (usually `/scaffold:plan` does this). |
| `task.sh start <id>` | Check out the task branch in each affected repo (creates it from the default branch, or resumes an existing one). |
| `task.sh next` / `task.sh status` | Print the first actionable task id — a todo, or an in-progress one to resume (so a killed session's orphan is picked back up and its dependents wait) / the full task table. Read-only. |
| `task.sh done <id>` | Finish a task: verify must be green, then `DONE=local` squash-merges one commit per repo; `DONE=pr` pushes the branch and opens a pre-reviewed PR (task parks at `Status: pr`). |
| `task.sh sync` | `DONE=pr` only: complete pr-status tasks whose PRs merged (records merge SHA, digests to `_log.md`, deletes local branches); a PR closed without merging blocks the task. Preflight runs this for you. |
| `task.sh block <id> "<reason>"` / `task.sh reopen <id>` / `task.sh abandon <id>` | Escalate a task to NEEDS_HUMAN.md (+ notification) / put a task back in play (a branch with commits resumes as in-progress, an empty one is abandoned to todo) / clean-restart a task: un-strand its repos to the default branch and delete the branch (refuses if it holds unmerged commits), back to todo. |
| `loop.sh` | Headless driver: runs `claude -p "/scaffold:build <id>"` with a fresh context per task. Caps via env vars: `MAX_TASKS` (default 5), `MAX_COST_USD` (15; skipped on a Claude subscription), `MAX_RESUME` (3 retries for sessions that die mid-task), `LIMIT_BACKOFF` / `UPSTREAM_BACKOFF` (seconds, default 1800). Run it from the project root. |
| `notify.sh "<msg>"` | The human-comms seam: prints, plus a macOS notification; a Telegram curl is sketched in the script — wire it in when async approval becomes the bottleneck. |

`preflight.sh`, `verify.sh`, `task.sh status`, and `task.sh sync` are safe to run by hand whenever you're curious; the rest mutate task state and are normally driven by `/scaffold:build` or `loop.sh`.

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
my-product/         run claude here; git repo versioning the scaffold state
  CLAUDE.md, .claude/, .gitignore   generated by init-project
  <repo>/           code repos, each its own git repo (ignored by the root repo)
  scaffold/
    agents.env      repos (../<repo>) + verify commands (validated by preflight)
    specs/          product spec — the human's input, versioned by the root repo
    tasks/          SINGLE SOURCE OF TRUTH: NNNN-slug/{task,review,feedback,design}.md
    tasks/_log.md   one line per merged task (bounded memory)
    NEEDS_HUMAN.md  escalations
```
