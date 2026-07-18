---
name: retro
description: Mine finished tasks for recurring pipeline weaknesses and propose machines-at-work improvements. Human-gated — proposes, never applies.
disable-model-invocation: true
---

Improve the pipeline from evidence. You may NOT edit the machines-at-work plugin — you write proposals; the human applies them in the machines-at-work repo.

1. Read every `machines-at-work/tasks/*/review.md` and `machines-at-work/tasks/*/feedback.md` (human-written) since the last retro (check `machines-at-work/retro/` for the last report date).
2. Look for PATTERNS, not incidents: a finding class the reviewer flags repeatedly, a misunderstanding recurring across implementer runs, human feedback contradicting an agent's instructions, cost outliers.
3. Rework signal: task.md records the update-note commit each task was planned from (`Intent:`), and repo commits carry `Task-Id` trailers — when later tasks rewrite files earlier tasks built, read the spawning note (`git show <Intent>`) to find out why. Rework from misunderstanding (agent built the wrong thing, decomposition drew bad boundaries) is a pipeline pattern; rework from a changed request ("now also do Y") is product evolution — never propose changes from it.
4. For each pattern (max 3 per retro — the highest-leverage ones), write `machines-at-work/retro/<date>-<slug>.md`:
   - **Evidence:** task ids + the recurring quote/finding.
   - **Root cause:** which prompt/script/rule allows it.
   - **Proposed change:** exact diff against the machines-at-work repo (agent prompt, skill, script, or hook) — the smaller the better. Prompt additions must pull their weight: would removing this line cause the mistake to recur?
   - **Risk:** what this change could regress.
5. One-off mistakes are not patterns — list them under "observed, no action" and move on.
6. Tell the user which proposals exist and your confidence in each.

Never edit files under the plugin root. Never edit agents' memory directly.
