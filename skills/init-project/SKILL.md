---
name: init-project
description: Bootstrap the current directory as a machines-at-work workspace (control repo + code repos as subdirectories).
disable-model-invocation: true
---

Set up the current directory as a workspace. Templates: `${CLAUDE_PLUGIN_ROOT}/templates/`.

1. Interview the user (AskUserQuestion): project name; the code repos (existing URLs to clone, existing local dirs to move in, or new ones to create — each becomes a top-level directory of the project root, never the root itself); each repo's verify command (build + lint + test in one line — for an existing repo, propose one derived from its CI config, e.g. `.github/workflows`, and confirm); default branch; how finished tasks land — `DONE=local` (squash-merge; solo repos) or `DONE=pr` (push branch + GitHub PR; shared repos, needs `gh` authenticated).
2. Layout — repos and machines-at-work state are siblings under the project root. Create `machines-at-work/` with: `agents.env` (from template, filled — repo paths are relative to it, e.g. `REPO_backend=../backend`), `updates/README.md` (from `templates/updates-README.md` — the folder where the user drops intent notes), `tasks/_log.md`. Create at the root: `CLAUDE.md` (from CLAUDE.template.md), `.gitignore` (repo dirs + template entries), `.claude/settings.json` enabling this plugin: `{"enabledPlugins": {"machines-at-work@machines-at-work": true}}`.
3. Clone/create the repos. A new repo gets: git init, the default branch, a minimal toolchain that makes the verify command pass on empty code, and one initial commit.
4. `git init` the project root and commit the state files (repo dirs stay ignored — each is its own git repo).
5. Run `${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh` — it must print PREFLIGHT OK. Fix or report anything red.
6. Tell the user: drop a first note in `machines-at-work/updates/` describing what to build (greenfield: the whole thing; an existing codebase: the first change), then run `/machines-at-work:plan`, then `/machines-at-work:build all` (or `scripts/loop.sh` headless). To iterate later: drop another note in `machines-at-work/updates/` and re-run `/machines-at-work:plan` — it turns the notes into tasks; your words live in git history, there is no spec document to maintain.
