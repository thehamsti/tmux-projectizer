#!/usr/bin/env bash
set -euo pipefail

TMUX_STUB_DIR="${TMUX_STUB_DIR:?TMUX_STUB_DIR is required}"
LOG_FILE="${TMUX_STUB_DIR}/commands.log"
mkdir -p "$TMUX_STUB_DIR"
touch "$LOG_FILE"

log_command() {
  printf '%s\n' "$*" >>"$LOG_FILE"
}

option_to_env() {
  local option_name="$1"
  option_name="${option_name#@}"
  option_name="${option_name//-/_}"
  option_name="${option_name^^}"
  printf 'TMUX_OPTION_%s' "$option_name"
}

session_file() {
  local session_name="$1"
  printf '%s/session_%s' "$TMUX_STUB_DIR" "$session_name"
}

read_session_state() {
  local session_name="$1"
  local file_path

  file_path="$(session_file "$session_name")"
  if [[ -f "$file_path" ]]; then
    # shellcheck disable=SC1090
    source "$file_path"
  else
    window_count=0
    current_window=1
  fi
}

write_session_state() {
  local session_name="$1"
  local file_path

  file_path="$(session_file "$session_name")"
  cat >"$file_path" <<EOF
window_count=${window_count}
current_window=${current_window}
EOF
}

parse_session_name() {
  local target="$1"
  target="${target#*:}"
  target="${target%%:*}"
  target="${target%%.*}"
  printf '%s' "$target"
}

parse_window_index() {
  local target="$1"
  if [[ "$target" == *:* ]]; then
    local after_colon="${target##*:}"
    printf '%s' "${after_colon%%.*}"
    return 0
  fi
  printf '1'
}

extract_popup_source() {
  local popup_command="$1"
  local popup_source

  popup_source="$(printf '%s' "$popup_command" | sed -nE "s/.*cat ([^|]+) \\| fzf.*/\\1/p")"
  popup_source="${popup_source#\'}"
  popup_source="${popup_source%\'}"
  printf '%s' "$popup_source"
}

command_name="${1:-}"
shift || true
log_command "${command_name} $*"

case "$command_name" in
  show-option)
    option_name="${*: -1}"
    env_name="$(option_to_env "$option_name")"
    printf '%s' "${!env_name-}"
    ;;
  list-commands)
    if [[ "${TMUX_STUB_HAS_POPUP:-0}" == "1" ]]; then
      printf 'display-popup\n'
    fi
    ;;
  list-sessions)
    find "$TMUX_STUB_DIR" -maxdepth 1 -type f -name 'session_*' -print |
      sed 's|.*/session_||' |
      sort
    ;;
  has-session)
    while (($#)); do
      case "$1" in
        -t)
          target="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    session_name="$(parse_session_name "${target:-}")"
    [[ -f "$(session_file "$session_name")" ]]
    ;;
  new-session)
    while (($#)); do
      case "$1" in
        -s)
          session_name="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    window_count=1
    current_window=1
    write_session_state "$session_name"
    ;;
  new-window)
    while (($#)); do
      case "$1" in
        -t)
          target="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    session_name="$(parse_session_name "${target:-}")"
    read_session_state "$session_name"
    window_count=$((window_count + 1))
    current_window="$window_count"
    write_session_state "$session_name"
    ;;
  select-window)
    while (($#)); do
      case "$1" in
        -t)
          target="$2"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    session_name="$(parse_session_name "${target:-}")"
    read_session_state "$session_name"
    current_window="$(parse_window_index "${target:-}")"
    write_session_state "$session_name"
    ;;
  display-message)
    format_mode=0
    target=""
    format=""
    while (($#)); do
      case "$1" in
        -p)
          format_mode=1
          shift
          ;;
        -t)
          target="$2"
          shift 2
          ;;
        *)
          format="$1"
          shift
          ;;
      esac
    done
    if ((format_mode)); then
      session_name="$(parse_session_name "${target:-}")"
      read_session_state "$session_name"
      if [[ "$format" == "#{window_index}" ]]; then
        printf '%s' "$current_window"
      fi
    fi
    ;;
  display-popup)
    popup_command="${*: -1}"
    if [[ -n "${TMUX_STUB_POPUP_STATUS:-}" ]]; then
      popup_status="$TMUX_STUB_POPUP_STATUS"
    else
      popup_status=0
    fi
    if [[ "$popup_status" == "0" ]]; then
      if [[ -n "${TMUX_STUB_POPUP_SELECTION:-}" ]]; then
        redirect_target="${popup_command##*> }"
        redirect_target="${redirect_target%\'}"
        redirect_target="${redirect_target#\'}"
        if [[ -n "${TMUX_STUB_POPUP_CAPTURE_FILE:-}" ]]; then
          popup_source="$(extract_popup_source "$popup_command")"
          if [[ -n "$popup_source" && -f "$popup_source" ]]; then
            cat "$popup_source" >"$TMUX_STUB_POPUP_CAPTURE_FILE"
          fi
        fi
        printf '%s\n' "$TMUX_STUB_POPUP_SELECTION" >"$redirect_target"
      else
        eval "$popup_command"
      fi
    fi
    exit "$popup_status"
    ;;
  choose-tree|command-prompt|switch-client|rename-window|split-window|select-layout|select-pane|set-window-option|bind-key|set-option|send-keys)
    ;;
  *)
    printf 'Unsupported fake tmux command: %s\n' "$command_name" >&2
    exit 1
    ;;
esac
