#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./helpers.sh disable=SC1091
source "${SCRIPT_DIR}/helpers.sh"

index="${1:-}"

if [[ ! "$index" =~ ^[0-9]+$ ]] || ((index < 1)) || ((index > 9)); then
  tmux display-message "projectizer quick-switch: invalid index ${index}"
  exit 1
fi

session_name="$(read_recent_sessions | sed -n "${index}p")"

if [[ -z "$session_name" ]]; then
  tmux display-message "projectizer: no session at position ${index}"
  exit 0
fi

if ! tmux has-session -t "$session_name" 2>/dev/null; then
  tmux display-message "projectizer: session '${session_name}' no longer exists"
  exit 0
fi

tmux switch-client -t "$session_name"
record_recent_session "$session_name"
