#!/usr/bin/env bash
# Notify the human — the single seam for human comms. Always prints; adds a
# macOS notification (Darwin) and, when Telegram creds are set, a message into
# the project's forum topic. Tolerant by design: never fails its caller.
set -euo pipefail
msg="${*:?usage: notify.sh <message>}"
echo "[notify] $msg"

if [ "$(uname)" = "Darwin" ]; then
  osascript -e "display notification \"${msg//\"/}\" with title \"Machines at Work\"" 2>/dev/null || true
fi

# Telegram: shared bot creds from a global file, per-project topic from agents.env.
# All optional — missing creds or no workspace just means "print only".
tg_env="${TELEGRAM_ENV:-$HOME/.agent-orchestrator/telegram.env}"
# shellcheck disable=SC1090
if [ -f "$tg_env" ]; then . "$tg_env"; fi
dir="$PWD"
while [ "$dir" != "/" ]; do
  # shellcheck disable=SC1090
  if [ -f "$dir/agents.env" ]; then . "$dir/agents.env"; break; fi
  # shellcheck disable=SC1090
  if [ -f "$dir/machines-at-work/agents.env" ]; then . "$dir/machines-at-work/agents.env"; break; fi
  dir="$(dirname "$dir")"
done

if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
  curl -fsS "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
    ${TELEGRAM_TOPIC_ID:+--data-urlencode "message_thread_id=$TELEGRAM_TOPIC_ID"} \
    --data-urlencode "text=$msg" >/dev/null \
    || echo "[notify] telegram send failed" >&2
fi
