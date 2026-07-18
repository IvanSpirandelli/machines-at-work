# Intent notes

Drop a note here — any shape, any filename — describing what you want built or changed.
`/machines-at-work:plan` turns notes into tasks and commits your words to git history; that history
is the record of intent. There is no living spec document to maintain.

A good note carries, in whatever form fits:
- **What it is / what changes** — the product, or the delta.
- **Requirements** as testable statements — prefer "WHEN <condition> THE SYSTEM SHALL <behavior>".
- **Out of scope** — explicit non-goals; agents treat these as forbidden.
- **How it's proven** — the commands or flows that show a finished result works end-to-end.

Notes are consumed by `/machines-at-work:plan` and removed from this folder once planned; recover any
past note from git history. This README stays; `/machines-at-work:plan` ignores it.
