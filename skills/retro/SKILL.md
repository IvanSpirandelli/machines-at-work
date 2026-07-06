---
name: retro
description: Mine finished tasks for recurring pipeline weaknesses and propose scaffold improvements. Human-gated — proposes, never applies.
disable-model-invocation: true
---

Improve the pipeline from evidence. You may NOT edit the scaffold plugin — you write proposals; the human applies them in the scaffold repo.

1. Read every `scaffold/tasks/*/review.md` and `scaffold/tasks/*/feedback.md` (human-written) since the last retro (check `scaffold/retro/` for the last report date).
2. Look for PATTERNS, not incidents: a finding class the reviewer flags repeatedly, a misunderstanding recurring across implementer runs, human feedback contradicting an agent's instructions, cost outliers.
3. Rework signal: task.md records the spec commit each task was planned from (`Spec:`), and repo commits carry `Task-Id` trailers — when tasks from a later spec version rewrite files earlier tasks built, find out why. Rework from misunderstanding (agent built the wrong thing, decomposition drew bad boundaries) is a pipeline pattern; rework from changed requirements is product evolution — never propose changes from it.
4. For each pattern (max 3 per retro — the highest-leverage ones), write `scaffold/retro/<date>-<slug>.md`:
   - **Evidence:** task ids + the recurring quote/finding.
   - **Root cause:** which prompt/script/rule allows it.
   - **Proposed change:** exact diff against the scaffold repo (agent prompt, skill, script, or hook) — the smaller the better. Prompt additions must pull their weight: would removing this line cause the mistake to recur?
   - **Risk:** what this change could regress.
5. One-off mistakes are not patterns — list them under "observed, no action" and move on.
6. Tell the user which proposals exist and your confidence in each.

Never edit files under the plugin root. Never edit agents' memory directly.
