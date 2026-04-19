#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./helpers.sh disable=SC1091
source "${SCRIPT_DIR}/helpers.sh"

PROJECTIZER_FZF_HEIGHT="${PROJECTIZER_FZF_HEIGHT:-$(get_option "@projectizer-fzf-height" "40%")}"
PROJECTIZER_POPUP="${PROJECTIZER_POPUP:-$(get_option "@projectizer-popup" "auto")}"

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
  exit 0
fi

selection_file="$(mktemp -t tmux-projectizer-sessions.XXXXXX)"
register_temp_file "$selection_file"

popup_command="bash -lc 'tmux list-sessions -F \"#S\" | fzf --prompt=\"Session> \" --height=$(shell_quote "$PROJECTIZER_FZF_HEIGHT") > $(shell_quote "$selection_file")'"

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
