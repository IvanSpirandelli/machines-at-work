#!/usr/bin/env bash
# Shared helpers. Source, don't execute.
set -euo pipefail

# Walk up from cwd to find the workspace (dir containing agents.env — either
# directly or in a machines-at-work/ child, so it's found from the project root and repos).
find_workspace() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    [ -f "$dir/agents.env" ] && { echo "$dir"; return 0; }
    [ -f "$dir/machines-at-work/agents.env" ] && { echo "$dir/machines-at-work"; return 0; }
    dir="$(dirname "$dir")"
  done
  echo "ERROR: no agents.env found between $PWD and /" >&2
  return 1
}

WS="$(find_workspace)"
# shellcheck disable=SC1091
source "$WS/agents.env"
: "${DEFAULT_BRANCH:=main}"
: "${DONE:=local}"   # local = squash-merge | pr = push branch + GitHub PR
: "${REPOS:?agents.env must set REPOS}"
TASKS="$WS/tasks"

repo_path() { # repo_path <name> -> absolute path
  local var="REPO_$1"
  local rel="${!var:?agents.env must set REPO_$1}"
  echo "$WS/$rel"
}

verify_cmd() { # verify_cmd <name> -> command string
  local var="VERIFY_$1"
  echo "${!var:?agents.env must set VERIFY_$1}"
}

smoke_cmd() { # smoke_cmd <name> -> command string, empty when the repo defines none
  # Optional (`:-`), unlike verify_cmd's `:?`: most repos have nothing to boot.
  local var="SMOKE_$1"
  echo "${!var:-}"
}

task_dir() { # task_dir <id> -> path (fails if missing)
  local d
  d=$(ls -d "$TASKS/$1-"*/ 2>/dev/null | head -1) || true
  [ -n "${d:-}" ] || { echo "ERROR: no task $1" >&2; return 1; }
  echo "${d%/}"
}

get_field() { # get_field <task.md> <Field>
  grep -m1 "^$2:" "$1" | sed "s/^$2:[[:space:]]*//"
}

set_field() { # set_field <task.md> <Field> <value>
  FIELD="$2" VALUE="$3" perl -pi -e 's/^$ENV{FIELD}:.*/$ENV{FIELD}: $ENV{VALUE}/' "$1"
}

task_title() { head -1 "$1" | sed 's/^# [0-9]* · //'; }

is_out_of_credits() { # rc 0 if <output> is a credit/billing exhaustion, not a
  # timer-based limit. Anthropic's canonical message is "Your credit balance is
  # too low to access the Anthropic API. … upgrade or purchase credits." These
  # do NOT reset on a schedule (unlike limit_wait), so retrying is pointless.
  echo "$1" | grep -qiE 'credit balance (is )?too low|purchase credits|insufficient (credit|funds)|out of (usage )?credits?'
}

is_transient_api_error() { # rc 0 if <output> looks like a transient, self-clearing
  # API/network drop worth an immediate retry — distinct from a usage limit (waits
  # for a reset), out-of-credits (human must act), or a genuine task failure. Keep
  # the pattern tight: prefer claude's JSON `result` field over raw stderr so a task
  # whose own output mentions "internal server error" isn't misread as a drop.
  echo "$1" | grep -qiE 'connection closed mid-response|connection reset|connection error|econnreset|etimedout|socket hang up|network( error|.*unreachable)|error 5[0-9][0-9]|overloaded_error|internal server error|service unavailable'
}

limit_wait() { # limit_wait <claude output> -> seconds to wait, or rc 1 if not a usage/rate limit
  echo "$1" | grep -qiE 'usage limit|rate.?limit|(hour|weekly|session) limit' || return 1
  local reset now
  reset=$(echo "$1" | grep -oE '\|[0-9]{10}' | head -1 | tr -d '|' || true)
  now=$(date +%s)
  if [ -n "$reset" ] && [ "$reset" -gt "$now" ] && [ $((reset - now)) -lt $((8 * 86400)) ]; then
    echo $((reset - now + 60))   # buffer past the advertised reset
  else
    echo "${LIMIT_BACKOFF:-1800}"
  fi
}

task_base() { # task_base <task.md> -> branch this task integrates into: its
  # feature branch (DONE=pr + Feature set) or DEFAULT_BRANCH
  local f
  f=$(get_field "$1" Feature) || f=""
  if [ "$DONE" = "pr" ] && [ -n "$f" ] && [ "$f" != "-" ]; then
    echo "feature/$f"
  else
    echo "$DEFAULT_BRANCH"
  fi
}

park_wip() { # park_wip <id> <msg>: commit leftover WIP on the task branch so
  # preflight passes on a retry (task.sh done squashes it away). No-op if clean.
  local id="$1" msg="$2" dir branch repo path
  dir=$(task_dir "$id"); branch=$(get_field "$dir/task.md" Branch)
  for repo in $(get_field "$dir/task.md" Repos); do
    path=$(repo_path "$repo")
    [ "$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null)" = "$branch" ] || continue
    git -C "$path" diff --quiet && git -C "$path" diff --cached --quiet \
      || { git -C "$path" add -A; git -C "$path" commit -qm "$msg"; }
  done
}

branch_has_commits() { # rc 0 if any affected repo's task branch is ahead of its base
  local id="$1" dir branch base repo path
  dir=$(task_dir "$id"); branch=$(get_field "$dir/task.md" Branch)
  base=$(task_base "$dir/task.md")
  for repo in $(get_field "$dir/task.md" Repos); do
    path=$(repo_path "$repo")
    git -C "$path" rev-parse -q --verify "$branch" >/dev/null || continue
    [ -n "$(git -C "$path" log --oneline "$base..$branch" 2>/dev/null)" ] && return 0
  done
  return 1
}

branch_head() { # branch_head <id> -> "repo:sha …" tips of the task branch (- if absent),
  # a cheap fingerprint for detecting whether a resume session committed anything.
  local id="$1" dir branch repo path sha out=""
  dir=$(task_dir "$id"); branch=$(get_field "$dir/task.md" Branch)
  for repo in $(get_field "$dir/task.md" Repos); do
    path=$(repo_path "$repo")
    sha=$(git -C "$path" rev-parse -q --verify "$branch" 2>/dev/null) || sha="-"
    out="$out $repo:$sha"
  done
  echo "${out# }"
}
