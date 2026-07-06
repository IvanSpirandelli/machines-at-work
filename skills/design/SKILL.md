---
name: design
description: Produce a concrete UI/UX design for one task before implementation. For user-facing tasks.
argument-hint: "<task-id>"
---

Write `scaffold/tasks/<id>-<slug>/design.md` for task $ARGUMENTS. The implementer will follow it literally — be concrete, not aspirational.

Cover, tersely:
1. Layout: components, hierarchy, spacing (ASCII sketch beats prose).
2. Visual language: colors (exact values), type scale, radii — consistent with the existing app (read it first).
3. States: empty, loading, error, success.
4. Interactions: what happens on click/hover/keyboard; motion only if it carries meaning.
5. One deliberate, fresh touch that elevates the design above the default — named explicitly so the implementer builds it.

≤60 lines. No mood boards, no alternatives — decide.
