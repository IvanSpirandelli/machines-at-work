#!/usr/bin/env bash
# Inbound comms seam (mirror of notify.sh's outbound leg). The scaffold owns
# both legs of its own Telegram topic. It cannot hold the inbound stream itself:
# a shared bot's getUpdates is single-consumer and the plugin has no always-on
# process, so a separate server-side orchestrator is the one persistent consumer.
# That orchestrator demuxes by topic and drops each raw message for this project
# into <workspace>/updates/.inbox/ — the whole cross-project contract. This
# script turns those raw messages into updates/ intent notes; note naming and
# format are the plugin's business, not the server's. Tolerant by design: no
# workspace, no inbox, nothing queued → no-op, never fails its caller.
set -euo pipefail
shopt -s nullglob

# Find the workspace (dir holding agents.env — directly or in a
# machines-at-work/ child), same walk-up as notify.sh.
dir="$PWD"; ws=""
while [ "$dir" != "/" ]; do
  if [ -f "$dir/agents.env" ]; then ws="$dir"; break; fi
  if [ -f "$dir/machines-at-work/agents.env" ]; then ws="$dir/machines-at-work"; break; fi
  dir="$(dirname "$dir")"
done
[ -n "$ws" ] || { echo "[inbound] no workspace found; nothing to drain" >&2; exit 0; }

inbox="$ws/updates/.inbox"
[ -d "$inbox" ] || exit 0   # server has delivered nothing

# Oldest first (server names files <epoch>-<msgid>.md, so lexical = chronological)
# so a multi-message intent keeps its order. Move, don't copy: a drained message
# is a note now, and re-draining must not duplicate it.
n=0
for f in "$inbox"/*.md; do
  mv "$f" "$ws/updates/tg-$(basename "$f")"
  n=$((n + 1))
done
[ "$n" -gt 0 ] && echo "[inbound] drained $n message(s) into updates/"
exit 0
