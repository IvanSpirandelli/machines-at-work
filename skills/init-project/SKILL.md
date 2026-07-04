---
name: init-project
description: Bootstrap the current directory as a scaffold workspace (control repo + code repos as subdirectories).
disable-model-invocation: true
---

Set up the current directory as a workspace. Templates: `${CLAUDE_PLUGIN_ROOT}/templates/`.

1. Interview the user (AskUserQuestion): project name; the code repos (existing URLs to clone, existing local dirs to move in, or new ones to create — each becomes a SUBDIRECTORY, never the workspace root itself); each repo's verify command (build + lint + test in one line); default branch.
2. Create: `agents.env` (from template, filled), `spec.md` (template), `tasks/_log.md`, `CLAUDE.md` (from CLAUDE.template.md), `.gitignore` (repo dirs + template entries), `.claude/settings.json` enabling this plugin: `{"enabledPlugins": {"scaffold@agentic-scaffold": true}}`.
3. Clone/create the repos. A new repo gets: git init, the default branch, a minimal toolchain that makes the verify command pass on empty code, and one initial commit.
4. `git init` the workspace itself and commit the state files.
5. Run `${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh` — it must print PREFLIGHT OK. Fix or report anything red.
6. Tell the user: write `spec.md`, then run `/scaffold:plan`, then `/scaffold:build all` (or `scripts/loop.sh` headless).
