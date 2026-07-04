#!/usr/bin/env bash
# Shared helpers. Source, don't execute.
set -euo pipefail

# Walk up from cwd to find the workspace root (dir containing agents.env).
find_workspace() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    [ -f "$dir/agents.env" ] && { echo "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  echo "ERROR: no agents.env found between $PWD and /" >&2
  return 1
}

WS="$(find_workspace)"
# shellcheck disable=SC1091
source "$WS/agents.env"
: "${DEFAULT_BRANCH:=main}"
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
