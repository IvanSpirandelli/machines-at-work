# Design

Why the scaffold looks the way it does. Grounded in Anthropic docs/engineering posts and 2025-26 practitioner evidence (sources at bottom).

## Core thesis

The intuitive design is an org chart of specialist agents (supervisor, frontend/backend engineers, designer, test engineer, reviewer, meta-agents). The evidence says the working part of autonomous coding is not the org chart — it is a **verify-gated loop over small tasks with fresh context and file-based state**. Multi-agent parallelism wins on independent *read* work (research, review); it loses on interdependent *write* work like coding (Anthropic: ~15x tokens, "most coding tasks involve fewer truly parallelizable tasks"; Cognition: conflicting implicit decisions).

So the spine is:

```
specs/ → /plan → tasks/NNNN-slug/ → per task:
  fresh implementer (TDD) → verify.sh (deterministic gate) →
  fresh reviewer (≤2 rounds) → squash-merge (one commit/repo) →
  digest to tasks/_log.md → next task
escalation at every step → NEEDS_HUMAN.md + notify
```

Everything mechanical is a script; LLMs are invoked only where judgment is required (decompose, implement, review, arbitrate). Fewer calls, less drift.

## Where the specialist roles landed

| Role | Became | Why |
|---|---|---|
| Supervisor | Main session running `/build` + `scripts/task.sh` | Orchestration is mostly mechanical → code. Judgment (decompose, arbitrate) stays in the main loop with minimal context. |
| Backend Engineer | `implementer` agent | One implementer per task **spanning all repos** — a split frontend/backend pair drifts on the API contract (Cognition's core failure mode). |
| Frontend Engineer | `implementer` agent | Same. Cross-repo task still yields one commit per repo via squash-merge. |
| Frontend Designer | `/design` skill | A standing concept agent produces unverifiable prose. As a skill it runs on demand for UI-heavy tasks, output lands in the task folder where the implementer uses it. |
| Test Engineer | Implementer's TDD contract + `verify.sh` | Writing tests ≠ running them. Red-before-green is in the implementer prompt; execution is a deterministic gate, not an agent. |
| Reviewer | `reviewer` agent | The one specialist that clearly earns its context: fresh-context critique beats self-review. Findings are severity-typed; only `blocking` re-loops; hard cap 2 rounds. |
| Agentic Resources | `/retro` skill | Meta-improvement is kept, but **human-gated**: it writes proposals + diffs, never edits live prompts. Unsupervised prompt self-editing measurably degrades pipelines (slop accumulation, goal drift). A hook physically blocks writes into the plugin dir. |
| Tool Engineer | `/toolsmith` skill | YAGNI as a standing agent. Invoked when a repetitive need is *observed*, it wraps it as a project script/skill. |

## Decisions (with the socratic objection that shaped each)

1. **Task folders named `NNNN-slug`, not commit names.** *Objection:* the commit hash doesn't exist until after the work — chicken-and-egg. Folder id is stable pre-commit; the resulting SHA is written into task.md and a `Task-Id: NNNN` trailer goes in the commit message. Bidirectional link, no paradox.
2. **One commit per feature = presentation, not unit of work.** *Objection:* a single end-of-feature commit kills the incremental red/green signal that makes loops converge. So: implementer commits freely on `task/NNNN-slug`, verify runs per change, and `task.sh done` squash-merges to exactly one commit per repo. One-commit rule satisfied, verification cadence preserved.
3. **tasks/ is the single source of truth.** No separate TODO list to drift. Status lives in each task.md; `task.sh next/status` read it; `tasks/_log.md` is an append-only one-line digest per finished task (bounded supervisor memory). Crash-resume falls out for free: all state transitions hit disk before proceeding.
4. **Deterministic verification is the engine.** `verify.sh` (per-repo build/lint/test from agents.env) gates every step. Hierarchy of trust: compiler/tests >> fresh-context critic >> LLM-as-judge. Implementer is forbidden from weakening tests to pass — and the reviewer checks for it.
5. **Review converges by construction.** Findings typed `[blocking|nit]`; nits are logged, not re-looped; max 2 rounds; still blocking → `task.sh block` escalates to human. Never an unbounded ping-pong.
6. **Escalation is a first-class outcome.** Stuck detection (blocked result, failed verify loop, round cap, budget cap) → status `blocked`, entry in NEEDS_HUMAN.md, `notify.sh`. An autonomous system without a designed exit thrashes.
7. **agents.env is generic and preflighted.** Named repos (`REPOS="frontend backend"`), not a hardcoded frontend/backend topology — works for CLI tools, libraries, monorepos. `preflight.sh` validates it (repos exist, trees clean, verify green) before any agent runs; config is verified, not assumed.
8. **Distribution = Claude Code plugin, per-project state = files in the workspace.** Cloning the scaffold into each project forks and drifts; submodules are friction. A plugin installs once, is enabled per project, propagates via `/plugin update`, and is consumed read-only. Project-specific bits (agents.env, specs/, tasks/) live in the workspace.
9. **Self-improvement = self-*proposing*.** `/retro` mines review.md + human feedback.md for recurring failures and writes `proposals/` entries with evidence and a concrete diff against this repo. Human reviews and commits. Prompt changes are release-engineered like code.
10. **Human comms: files first.** NEEDS_HUMAN.md + notify.sh (stub: macOS notification; add a Telegram/ntfy curl when async mobile approval is proven to be the bottleneck — don't build the messaging layer before the loop is validated).
11. **Two drive modes, same contracts.** Interactive: you run `/plan` then `/build` in a session. Headless: `scripts/loop.sh` runs `claude -p "/build <id>"` per task with iteration/cost caps — fresh context per task (the ralph insight) with deterministic task selection.
12. **Budgets are hard stops.** loop.sh caps tasks per run and cost per run (parses `total_cost_usd`); per-task cost is recorded in task.md so /retro sees spend, not just outcome. *Exception:* on a Claude subscription there is no per-token bill, so `total_cost_usd` is an API-equivalent estimate, not real spend — loop.sh detects subscription mode (no `ANTHROPIC_API_KEY`/`ANTHROPIC_AUTH_TOKEN`, not Bedrock/Vertex), skips the cost cap, and records `Cost: subscription`. The task cap stays the only hard stop there.
13. **Spec iteration = edit `specs/` in place, replan the delta.** No spec_2 files: versions live in the workspace repo's git history (`task.sh done` snapshots workspace state; /plan commits spec changes before planning). Each task.md records the spec commit it came from (`Spec:` field), and code commits carry `Task-Id` — so /retro can trace cross-version rework and separate misunderstanding (pipeline signal) from changed requirements (product evolution, not actionable). Humans write deltas, not merges: notes dropped in `specs/updates/` are committed verbatim, then /plan integrates them into the living spec — gated on the user approving the spec diff, because the spec is the human's contract with the pipeline.
14. **Usage limits pause the loop; they don't block tasks.** *Objection:* loop.sh treated every nonzero `claude -p` exit as a task failure, so a subscription limit cascaded — each remaining task got blocked and NEEDS_HUMAN.md filled with non-problems. A limit is an environment condition, not a task outcome: `limit_wait` (lib.sh) recognizes the limit message, sleeps until the advertised reset (fallback `LIMIT_BACKOFF`, default 30 min), and loop.sh retries the *same* task. Interrupted WIP is parked as a commit on the task branch (squash-merge erases it later) so preflight stays green, and `task.sh start` resumes an in-progress task by checking out its existing branch. Only genuine failures still escalate.
15. **Repos and scaffold state are siblings under the project root.** State lives in `scaffold/` (agents.env, specs/, tasks/, NEEDS_HUMAN.md); code repos are top-level dirs referenced as `../<repo>`; the root keeps only CLAUDE.md + .claude/. `find_workspace` probes `scaffold/agents.env` too, so scripts work from the root, the state dir, or inside a repo. Flat layouts (agents.env at the root) keep working.

## Steelman we accepted

"Why not a single agent loop and nothing else?" — Mostly right, and this design *is* that loop at its core. The only standing specialists are the implementer (fresh context per task) and the reviewer (generate/critique separation — cheap, well-evidenced). Everything else was demoted to skills or scripts. Roles get added back only when a specific context demonstrably doesn't fit — earn the agent.

## Deliberately not built (yet)

- Parallel implementers in worktrees (agent teams): worktrees solve file collisions, not decision conflicts. Add when tasks are provably disjoint and the sequential loop is trusted.
- Telegram/WhatsApp bridge: notify.sh is the seam; wire it when needed.
- LLM-as-judge quality gates: weakest verifier class; deterministic gates + reviewer cover it.
- Token-level budget accounting inside interactive sessions (CLI exposes cost only in headless JSON output).

## Sources

Anthropic: [multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system) · [effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) · [effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) · [building effective agents](https://www.anthropic.com/engineering/building-effective-agents) · [best practices](https://code.claude.com/docs/en/best-practices) · [sub-agents](https://code.claude.com/docs/en/sub-agents) · [plugins](https://code.claude.com/docs/en/plugins) · [hooks](https://code.claude.com/docs/en/hooks)
Practitioners: [ghuntley.com/ralph](https://ghuntley.com/ralph/) · [Cognition: Don't Build Multi-Agents](https://cognition.com/blog/dont-build-multi-agents) · [12-factor agents](https://github.com/humanlayer/12-factor-agents) · [ACE-FCA](https://github.com/humanlayer/advanced-context-engineering-for-coding-agents) · [Willison: red/green TDD](https://simonwillison.net/guides/agentic-engineering-patterns/red-green-tdd/) · [Fowler/Böckeler on SDD](https://martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html)
