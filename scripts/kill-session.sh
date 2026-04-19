#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./helpers.sh disable=SC1091
source "${SCRIPT_DIR}/helpers.sh"

PROJECTIZER_FZF_HEIGHT="${PROJECTIZER_FZF_HEIGHT:-$(get_option "@projectizer-fzf-height" "40%")}"
PROJECTIZER_POPUP="${PROJECTIZER_POPUP:-$(get_option "@projectizer-popup" "auto")}"
PROJECTIZER_HISTORY_FILE="${PROJECTIZER_HISTORY_FILE:-$(get_history_file)}"
PROJECTIZER_HISTORY_SIZE="${PROJECTIZER_HISTORY_SIZE:-$(get_history_size)}"

cleanup_paths=()

cleanup() {
  local file_path

  if ((${#cleanup_paths[@]} == 0)); then
    return 0
  fi

  for file_path in "${cleanup_paths[@]-}"; do
    if [[ -n "$file_path" && -e "$file_path" ]]; then
      rm -f "$file_path"
    fi
  done
}

trap cleanup EXIT

shell_quote() {
  printf '%q' "$1"
}

register_temp_file() {
  cleanup_paths+=("$1")
}

should_require_popup() {
  [[ "$PROJECTIZER_POPUP" == "always" ]]
}

should_use_popup() {
  case "$PROJECTIZER_POPUP" in
    auto|always) has_popup ;;
    never) return 1 ;;
    *) has_popup ;;
  esac
}

if ! has_fzf || ! should_use_popup; then
  if should_require_popup && ! has_popup; then
    tmux display-message "projectizer popup mode requires tmux >= 3.2"
    exit 1
  fi

  tmux choose-tree -s
  tmux display-message "projectizer kill-session requires popup + fzf; use tmux kill-session manually"
  exit 0
fi

current_session="$(tmux display-message -p '#S' 2>/dev/null || true)"
selection_file="$(mktemp -t tmux-projectizer-kill-session.XXXXXX)"
sessions_file="$(mktemp -t tmux-projectizer-killable-sessions.XXXXXX)"
register_temp_file "$selection_file"
register_temp_file "$sessions_file"
write_ordered_sessions "$sessions_file" "$current_session"

if [[ ! -s "$sessions_file" ]]; then
  tmux display-message "projectizer: no other sessions to kill"
  exit 0
fi

popup_command="bash -lc 'cat $(shell_quote "$sessions_file") | fzf --prompt=\"Kill session> \" --height=$(shell_quote "$PROJECTIZER_FZF_HEIGHT") > $(shell_quote "$selection_file")'"

set +e
tmux display-popup -E "$popup_command"
popup_status=$?
set -e

case "$popup_status" in
  0) ;;
  1|130) exit 130 ;;
  *)
    tmux display-message "projectizer kill-session picker failed (status ${popup_status})"
    exit "$popup_status"
    ;;
esac

selected_session="$(cat "$selection_file" 2>/dev/null || true)"
if [[ -z "$selected_session" ]]; then
  exit 1
fi

tmux kill-session -t "$selected_session"
remove_from_recent_sessions "$selected_session"
tmux display-message "Killed session: $selected_session"
