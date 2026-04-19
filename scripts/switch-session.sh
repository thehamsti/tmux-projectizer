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

build_ordered_session_list() {
  local output_file="$1"
  local session_file
  local remaining_file
  local recent_session

  session_file="$(mktemp -t tmux-projectizer-sessions-all.XXXXXX)"
  remaining_file="$(mktemp -t tmux-projectizer-sessions-remaining.XXXXXX)"
  register_temp_file "$session_file"
  register_temp_file "$remaining_file"

  tmux list-sessions -F "#S" | awk 'NF && !seen[$0]++ { print }' | sort >"$session_file"
  : >"$output_file"

  while IFS= read -r recent_session; do
    [[ -n "$recent_session" ]] || continue

    if grep -Fxq "$recent_session" "$session_file"; then
      printf '%s\n' "$recent_session" >>"$output_file"
    fi
  done < <(read_recent_sessions)

  if [[ -s "$output_file" ]]; then
    grep -Fvx -f "$output_file" "$session_file" >"$remaining_file" || true
    cat "$remaining_file" >>"$output_file"
    return 0
  fi

  cat "$session_file" >"$output_file"
}

if ! has_fzf || ! should_use_popup; then
  if should_require_popup && ! has_popup; then
    tmux display-message "projectizer popup mode requires tmux >= 3.2"
    exit 1
  fi
  tmux choose-tree -s
  exit 0
fi

selection_file="$(mktemp -t tmux-projectizer-sessions.XXXXXX)"
sessions_file="$(mktemp -t tmux-projectizer-sessions-ordered.XXXXXX)"
register_temp_file "$selection_file"
register_temp_file "$sessions_file"
build_ordered_session_list "$sessions_file"

popup_command="bash -lc 'cat $(shell_quote "$sessions_file") | fzf --prompt=\"Session> \" --height=$(shell_quote "$PROJECTIZER_FZF_HEIGHT") > $(shell_quote "$selection_file")'"

set +e
tmux display-popup -E "$popup_command"
popup_status=$?
set -e

case "$popup_status" in
  0) ;;
  1|130) exit 130 ;;
  *)
    tmux display-message "projectizer session picker failed (status ${popup_status})"
    exit "$popup_status"
    ;;
esac

selected_session="$(cat "$selection_file" 2>/dev/null || true)"
if [[ -z "$selected_session" ]]; then
  exit 1
fi

tmux switch-client -t "$selected_session"
record_recent_session "$selected_session"
