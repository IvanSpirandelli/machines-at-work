#!/usr/bin/env bash
# Task lifecycle. Deterministic — no LLM involved.
# Usage: task.sh new "<title>" [repos] | start <id> | next | status | done <id> | block <id> "<reason>" | reopen <id>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() { grep '^# Usage' "$0" | cut -c3-; exit 1; }

cmd_new() {
  local title="${1:?usage: task.sh new \"<title>\" [repos]}"
  local repos="${2:-$REPOS}"
  local last id slug dir
  last=$(ls "$TASKS" 2>/dev/null | grep -E '^[0-9]{4}-' | sort | tail -1 | cut -d- -f1 || true)
  id=$(printf '%04d' $((10#${last:-0} + 1)))
  slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g' | cut -c1-40)
  dir="$TASKS/$id-$slug"
  mkdir -p "$dir"
  cat > "$dir/task.md" <<EOF
# $id · $title

Status: todo
Repos: $repos
Branch: task/$id-$slug
Commits: -
Rounds: 0
Cost: -

## Goal

## Acceptance criteria

- [ ]

## Non-goals

## Notes
EOF
  echo "$id"
}

cmd_start() {
  local id="${1:?task id}" dir md branch repo path
  dir=$(task_dir "$id"); md="$dir/task.md"
  [ "$(get_field "$md" Status)" = "todo" ] || { echo "ERROR: task $id is not todo" >&2; exit 1; }
  branch=$(get_field "$md" Branch)
  for repo in $(get_field "$md" Repos); do
    path=$(repo_path "$repo")
    git -C "$path" diff --quiet && git -C "$path" diff --cached --quiet \
      || { echo "ERROR: $repo has uncommitted changes" >&2; exit 1; }
    git -C "$path" checkout -q "$DEFAULT_BRANCH"
    git -C "$path" checkout -qb "$branch"
  done
  set_field "$md" Status in-progress
  echo "started $id on $branch"
}

cmd_next() {
  local d
  for d in "$TASKS"/[0-9]*/; do
    [ -f "$d/task.md" ] || continue
    [ "$(get_field "$d/task.md" Status)" = "todo" ] && { basename "$d" | cut -d- -f1; return 0; }
  done
  return 1
}

cmd_status() {
  local d md
  printf '%-6s %-12s %s\n' ID STATUS TITLE
  for d in "$TASKS"/[0-9]*/; do
    md="$d/task.md"; [ -f "$md" ] || continue
    printf '%-6s %-12s %s\n' "$(basename "$d" | cut -d- -f1)" "$(get_field "$md" Status)" "$(task_title "$md")"
  done
}

cmd_done() {
  local id="${1:?task id}" dir md branch title repo path shas sha
  dir=$(task_dir "$id"); md="$dir/task.md"
  [ "$(get_field "$md" Status)" = "in-progress" ] || { echo "ERROR: task $id is not in-progress" >&2; exit 1; }
  "$(dirname "${BASH_SOURCE[0]}")/verify.sh" || { echo "ERROR: verify failed — not merging" >&2; exit 1; }
  branch=$(get_field "$md" Branch); title=$(task_title "$md"); shas=""
  for repo in $(get_field "$md" Repos); do
    path=$(repo_path "$repo")
    git -C "$path" diff --quiet && git -C "$path" diff --cached --quiet \
      || { echo "ERROR: $repo has uncommitted changes on $branch" >&2; exit 1; }
    git -C "$path" checkout -q "$DEFAULT_BRANCH"
    if ! git -C "$path" merge --squash -q "$branch" >/dev/null; then
      git -C "$path" reset -q --hard "$DEFAULT_BRANCH"
      git -C "$path" checkout -q "$branch"
      echo "ERROR: squash-merge conflict in $repo — resolve on $branch, then rerun done" >&2
      exit 1
    fi
    if git -C "$path" diff --cached --quiet; then
      git -C "$path" reset -q --hard "$DEFAULT_BRANCH"   # no changes in this repo
    else
      git -C "$path" commit -qm "$title" -m "Task-Id: $id"
      sha=$(git -C "$path" rev-parse --short HEAD)
      shas="$shas $repo:$sha"
    fi
    git -C "$path" branch -qD "$branch"
  done
  set_field "$md" Status done
  set_field "$md" Commits "${shas# }"
  echo "- $id · $title ·${shas:- no changes}" >> "$TASKS/_log.md"
  echo "done $id →${shas:- no changes}"
}

cmd_block() {
  local id="${1:?task id}" reason="${2:?reason}" dir md
  dir=$(task_dir "$id"); md="$dir/task.md"
  set_field "$md" Status blocked
  { echo "## $(basename "$dir")"; echo "$reason"; echo; } >> "$WS/NEEDS_HUMAN.md"
  "$(dirname "${BASH_SOURCE[0]}")/notify.sh" "Task $id blocked: $reason" || true
  echo "blocked $id"
}

cmd_reopen() {
  local id="${1:?task id}" dir md branch repo path
  dir=$(task_dir "$id"); md="$dir/task.md"
  branch=$(get_field "$md" Branch)
  for repo in $(get_field "$md" Repos); do
    path=$(repo_path "$repo")
    if git -C "$path" rev-parse -q --verify "$branch" >/dev/null; then
      set_field "$md" Status in-progress; echo "reopened $id (branch exists)"; return
    fi
  done
  set_field "$md" Status todo
  echo "reopened $id"
}

case "${1:-}" in
  new|start|next|status|done|block|reopen) c="$1"; shift; "cmd_$c" "$@" ;;
  *) usage ;;
esac
