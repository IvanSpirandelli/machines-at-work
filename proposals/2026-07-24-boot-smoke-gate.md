# Design 2026-07-24 · Verify never boots the app: optional `SMOKE_<repo>` gate

**Status:** applied · 2026-07-24 · v0.23.0
**Scope:** machines-at-work only; the project side (a `tyf-api` healthcheck so `--wait` means *serving*, plus `SMOKE_core`) lands in tell-your-friends.

## Evidence / observation

Incident, 2026-07-24. The Cloudflare-served preview frontend showed "Configuration Error" for every
visitor. Cause: `tyf-api` had exited on start — task 0031's migration
(`d1e2f3a4b5c6_drop_thanks_and_liked_notification`) narrowed the notification type CHECK to exclude
`'liked'` without deleting the `'liked'` rows the dropped feature had already written, so
`alembic upgrade head` aborted with a `CheckViolationError` inside `db-upgrade`.

The task passed `verify.sh`, passed review, and merged. Three reasons nothing caught it:

1. **Every gate builds its database new.** CI starts a fresh Postgres service container per run;
   `tests/conftest.py` migrates a test DB that only ever holds what `tests/seed.py` plants.
2. **The same commit removed the seed code that produced the offending rows.** After 0031, no gate
   could *generate* the data that breaks the migration. A removal task is structurally untestable
   against a from-scratch database — the highest-risk migration class is the least covered.
3. **`VERIFY_core` never starts the app.** It runs tox + infra pytest. `db-upgrade` — the thing that
   actually failed — is executed nowhere in the pipeline. The first execution of a shipped startup
   path is a human opening the preview.

Generalizes past migrations: a bad env var, an import error at module scope, a failing startup hook,
a broken seed all land the same way — green verify, dead app, discovered by a human.

## Root cause

`scripts/verify.sh` runs exactly one command per repo (`VERIFY_<repo>`), and by convention that
command is build+lint+test. Nothing in the pipeline asserts *the artifact starts and answers*.

## Proposed change

An optional second command per repo, run by `verify.sh` after the repo's verify command passes:

```sh
SMOKE_core='docker compose up -d --force-recreate --wait tyf-api'
```

- **Optional.** Repos without `SMOKE_<repo>` behave exactly as today (libraries, config repos).
- **Explicit, not auto-detected.** The plugin cannot know which service is the app, which endpoint
  proves readiness, or whether the project uses compose at all. Same reasoning as #17 (`DONE` is a
  declared knob, not a sniffed origin remote) and #43 (agents.env is a generic repo list, not a
  hardcoded topology). A wrong guess either hangs the gate or greenlights a dying app.
- **Timeout-owned.** `timeout ${SMOKE_TIMEOUT:-300}` wraps it — a container that never turns healthy
  must fail the gate, not wedge the loop.
- **`--no-smoke`** for callers that want the fast, side-effect-free color: `task.sh diagnose`
  (documented read-only) and `loop.sh`'s block-reason color. `preflight.sh` and `task.sh done` — the
  two real gates — run the full thing.

Measured on the tyf box: 33s for a force-recreate boot (drop schema → 30+ migrations → seed).
Verified the gate catches the failure: with the container command replaced by `exit 1`,
`docker compose up --wait` returns rc=1 (`container tyf-api exited (1)`).

## Risk

- **Slower inner loop.** The implementer runs `verify.sh` after each change; +33s per run on tyf.
  Mitigated by `--no-smoke`, at the cost of the implementer not seeing boot failures until `done`.
- **Side effects in the gate.** Unlike verify, smoke mutates the dev environment (restarts
  containers, and on tyf rebuilds the dev DB). `verify.sh` stops being "run it any time; it changes
  nothing" — README must say so. `--force-recreate` is what makes it meaningful: a plain `up -d` on
  an already-running container is a no-op and proves nothing.
- **A hung smoke command** costs `SMOKE_TIMEOUT` seconds before failing.

## Not proposed

Auto-detecting a compose file / API and starting it unasked. Rejected on #17's grounds — and the tyf
smoke command needs a healthcheck to be meaningful (`--wait` without one returns as soon as the
container is *running*, not serving), which is project knowledge by definition.
