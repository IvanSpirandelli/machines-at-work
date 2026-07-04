#!/usr/bin/env bash
# Notify the human. Extend with Telegram/ntfy/etc. when file-based escalation
# proves insufficient — this script is the single seam for human comms.
set -euo pipefail
msg="${*:?usage: notify.sh <message>}"
echo "[notify] $msg"
if [ "$(uname)" = "Darwin" ]; then
  osascript -e "display notification \"${msg//\"/}\" with title \"Agent Scaffold\"" 2>/dev/null || true
fi
# Telegram example (set TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID in agents.env):
# curl -fsS "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
#   -d chat_id="$TELEGRAM_CHAT_ID" -d text="$msg" >/dev/null
