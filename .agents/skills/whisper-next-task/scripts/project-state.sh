#!/usr/bin/env bash

set -uo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  echo "Not inside a Git repository." >&2
  exit 1
fi

cd "$repo_root"

required_files=(
  "AGENTS.md"
  "docs/implementation/task-backlog.md"
  "docs/implementation/task-workflow.md"
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing required Whisper workflow file: $required_file" >&2
    exit 1
  fi
done

account="unavailable"
if command -v gh >/dev/null 2>&1; then
  detected_account="$(gh api user --jq .login 2>/dev/null || true)"
  if [[ -n "$detected_account" ]]; then
    account="$detected_account"
  fi
fi

remote="$(git remote get-url origin 2>/dev/null || true)"
branch="$(git branch --show-current)"

backlog_statuses="$({
  awk -F '|' '
    /^\| WH-/ {
      id=$2; status=$4
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", status)
      print id "|" status
    }
  ' docs/implementation/task-backlog.md
} | sort)"

detail_statuses="$({
  awk '
    /^## WH-/ { id=$2 }
    /^- \*\*Status:\*\*/ {
      status=$0
      sub(/^- \*\*Status:\*\*[[:space:]]*/, "", status)
      print id "|" status
    }
  ' docs/implementation/tasks/*.md
} | sort)"

echo "Repository"
echo "  root: $repo_root"
echo "  account: $account"
echo "  remote: $remote"
echo "  branch: $branch"

if [[ "$account" == "yurybv" && "$remote" == "https://github.com/yurybv/whisper.git" && "$branch" == "master" ]]; then
  echo "  guard: pass"
else
  echo "  guard: FAIL"
fi

echo
echo "Worktree"
worktree_status="$(git status --short)"
if [[ -n "$worktree_status" ]]; then
  printf '%s\n' "$worktree_status"
else
  echo "  clean"
fi

echo
echo "Origin divergence"
if git rev-parse --verify origin/master >/dev/null 2>&1; then
  divergence="$(git rev-list --left-right --count origin/master...master)"
  behind="$(printf '%s\n' "$divergence" | awk '{print $1}')"
  ahead="$(printf '%s\n' "$divergence" | awk '{print $2}')"
  echo "  behind: $behind"
  echo "  ahead: $ahead"
else
  echo "  origin/master unavailable; fetch before task selection"
fi

echo
echo "Recent commits"
git log -5 --oneline | sed 's/^/  /'

echo
echo "Task status consistency"
if [[ "$backlog_statuses" == "$detail_statuses" ]]; then
  echo "  pass"
else
  echo "  FAIL: backlog and detailed task records differ"
  diff -u \
    <(printf '%s\n' "$backlog_statuses") \
    <(printf '%s\n' "$detail_statuses") || true
fi

active_tasks="$(printf '%s\n' "$detail_statuses" | awk -F '|' '$2 == "in-progress" || $2 == "review" { print $1 "|" $2 }')"
active_count="$(printf '%s\n' "$active_tasks" | awk 'NF { count++ } END { print count+0 }')"

ready_task="$(
  awk -F '|' '
    /^\| WH-/ {
      id=$2; status=$4
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", status)
      if (status == "ready") { print id; exit }
    }
  ' docs/implementation/task-backlog.md
)"

echo
echo "Recovery candidate"
if (( active_count > 1 )); then
  echo "  conflict: multiple active tasks"
  printf '%s\n' "$active_tasks" | sed 's/^/    /'
elif (( active_count == 1 )); then
  active_task="${active_tasks%%|*}"
  active_status="${active_tasks#*|}"
  echo "  resume: $active_task ($active_status)"
elif [[ -n "$ready_task" ]]; then
  echo "  inspect next ready: $ready_task"
else
  echo "  no active or ready task"
fi

echo
echo "Reminder"
echo "  Inspect dirty files, unpublished commits, dependencies, and acceptance criteria before changing task status."
