#!/usr/bin/env bash
set -uo pipefail

PROJECTIZER_VERSION="0.1.1"

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEFAULT_PROJECTIZER_PATHS="${HOME}/projects"
DEFAULT_PROJECTIZER_SEARCH_DEPTH="2"
DEFAULT_PROJECTIZER_NEW_SESSION_KEY="S"
DEFAULT_PROJECTIZER_SWITCH_SESSION_KEY="f"
DEFAULT_PROJECTIZER_KILL_SESSION_KEY="X"
DEFAULT_PROJECTIZER_LAYOUT="main-vertical"
DEFAULT_PROJECTIZER_MAIN_PANE_WIDTH="66%"
DEFAULT_PROJECTIZER_WINDOWS="main bg logs"
DEFAULT_PROJECTIZER_INITIAL_WINDOW="1"
DEFAULT_PROJECTIZER_FZF_HEIGHT="40%"
DEFAULT_PROJECTIZER_POPUP="auto"
DEFAULT_PROJECTIZER_HISTORY_SIZE="50"
DEFAULT_PROJECTIZER_HISTORY_FILE="${HOME}/.tmux/projectizer-recent"
DEFAULT_PROJECTIZER_QUICK_SWITCH="on"

set_default_option() {
  local option_name="$1"
  local default_value="$2"

  tmux show-option -gv "$option_name" >/dev/null 2>&1 ||
    tmux set-option -gq "$option_name" "$default_value" >/dev/null 2>&1 ||
    true
}

get_option_value() {
  local option_name="$1"
  local default_value="$2"
  local value

  value="$(tmux show-option -gv "$option_name" 2>/dev/null || true)"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return 0
  fi

  printf '%s' "$default_value"
}

shell_quote() {
  printf '%q' "$1"
}

build_run_shell_command() {
  local script_path="$1"
  shift

  local command_parts=()
  local key
  local value

  while (($#)); do
    key="$1"
    value="$2"
    command_parts+=("${key}=$(shell_quote "$value")")
    shift 2
  done

  command_parts+=("bash $(shell_quote "$script_path")")
  (IFS=' '; printf '%s' "${command_parts[*]}")
}

set_default_option "@projectizer-paths" "$DEFAULT_PROJECTIZER_PATHS"
set_default_option "@projectizer-search-depth" "$DEFAULT_PROJECTIZER_SEARCH_DEPTH"
set_default_option "@projectizer-new-session-key" "$DEFAULT_PROJECTIZER_NEW_SESSION_KEY"
set_default_option "@projectizer-switch-session-key" "$DEFAULT_PROJECTIZER_SWITCH_SESSION_KEY"
set_default_option "@projectizer-kill-session-key" "$DEFAULT_PROJECTIZER_KILL_SESSION_KEY"
set_default_option "@projectizer-layout" "$DEFAULT_PROJECTIZER_LAYOUT"
set_default_option "@projectizer-main-pane-width" "$DEFAULT_PROJECTIZER_MAIN_PANE_WIDTH"
set_default_option "@projectizer-windows" "$DEFAULT_PROJECTIZER_WINDOWS"
set_default_option "@projectizer-initial-window" "$DEFAULT_PROJECTIZER_INITIAL_WINDOW"
set_default_option "@projectizer-fzf-height" "$DEFAULT_PROJECTIZER_FZF_HEIGHT"
set_default_option "@projectizer-popup" "$DEFAULT_PROJECTIZER_POPUP"
set_default_option "@projectizer-history-size" "$DEFAULT_PROJECTIZER_HISTORY_SIZE"
set_default_option "@projectizer-history-file" "$DEFAULT_PROJECTIZER_HISTORY_FILE"
set_default_option "@projectizer-quick-switch" "$DEFAULT_PROJECTIZER_QUICK_SWITCH"

PROJECTIZER_PATHS="$(get_option_value "@projectizer-paths" "$DEFAULT_PROJECTIZER_PATHS")"
PROJECTIZER_SEARCH_DEPTH="$(get_option_value "@projectizer-search-depth" "$DEFAULT_PROJECTIZER_SEARCH_DEPTH")"
PROJECTIZER_NEW_SESSION_KEY="$(get_option_value "@projectizer-new-session-key" "$DEFAULT_PROJECTIZER_NEW_SESSION_KEY")"
PROJECTIZER_SWITCH_SESSION_KEY="$(get_option_value "@projectizer-switch-session-key" "$DEFAULT_PROJECTIZER_SWITCH_SESSION_KEY")"
PROJECTIZER_KILL_SESSION_KEY="$(get_option_value "@projectizer-kill-session-key" "$DEFAULT_PROJECTIZER_KILL_SESSION_KEY")"
PROJECTIZER_LAYOUT="$(get_option_value "@projectizer-layout" "$DEFAULT_PROJECTIZER_LAYOUT")"
PROJECTIZER_MAIN_PANE_WIDTH="$(get_option_value "@projectizer-main-pane-width" "$DEFAULT_PROJECTIZER_MAIN_PANE_WIDTH")"
PROJECTIZER_WINDOWS="$(get_option_value "@projectizer-windows" "$DEFAULT_PROJECTIZER_WINDOWS")"
PROJECTIZER_INITIAL_WINDOW="$(get_option_value "@projectizer-initial-window" "$DEFAULT_PROJECTIZER_INITIAL_WINDOW")"
PROJECTIZER_FZF_HEIGHT="$(get_option_value "@projectizer-fzf-height" "$DEFAULT_PROJECTIZER_FZF_HEIGHT")"
PROJECTIZER_POPUP="$(get_option_value "@projectizer-popup" "$DEFAULT_PROJECTIZER_POPUP")"
PROJECTIZER_HISTORY_SIZE="$(get_option_value "@projectizer-history-size" "$DEFAULT_PROJECTIZER_HISTORY_SIZE")"
PROJECTIZER_HISTORY_FILE="$(get_option_value "@projectizer-history-file" "$DEFAULT_PROJECTIZER_HISTORY_FILE")"
PROJECTIZER_QUICK_SWITCH="$(get_option_value "@projectizer-quick-switch" "$DEFAULT_PROJECTIZER_QUICK_SWITCH")"

NEW_SESSION_COMMAND="$(build_run_shell_command \
  "${CURRENT_DIR}/scripts/new-project-session.sh" \
  "PROJECTIZER_PATHS" "$PROJECTIZER_PATHS" \
  "PROJECTIZER_SEARCH_DEPTH" "$PROJECTIZER_SEARCH_DEPTH" \
  "PROJECTIZER_LAYOUT" "$PROJECTIZER_LAYOUT" \
  "PROJECTIZER_MAIN_PANE_WIDTH" "$PROJECTIZER_MAIN_PANE_WIDTH" \
  "PROJECTIZER_WINDOWS" "$PROJECTIZER_WINDOWS" \
  "PROJECTIZER_INITIAL_WINDOW" "$PROJECTIZER_INITIAL_WINDOW" \
  "PROJECTIZER_FZF_HEIGHT" "$PROJECTIZER_FZF_HEIGHT" \
  "PROJECTIZER_POPUP" "$PROJECTIZER_POPUP" \
  "PROJECTIZER_HISTORY_SIZE" "$PROJECTIZER_HISTORY_SIZE" \
  "PROJECTIZER_HISTORY_FILE" "$PROJECTIZER_HISTORY_FILE")"

SWITCH_SESSION_COMMAND="$(build_run_shell_command \
  "${CURRENT_DIR}/scripts/switch-session.sh" \
  "PROJECTIZER_FZF_HEIGHT" "$PROJECTIZER_FZF_HEIGHT" \
  "PROJECTIZER_POPUP" "$PROJECTIZER_POPUP" \
  "PROJECTIZER_HISTORY_SIZE" "$PROJECTIZER_HISTORY_SIZE" \
  "PROJECTIZER_HISTORY_FILE" "$PROJECTIZER_HISTORY_FILE")"

KILL_SESSION_COMMAND="$(build_run_shell_command \
  "${CURRENT_DIR}/scripts/kill-session.sh" \
  "PROJECTIZER_FZF_HEIGHT" "$PROJECTIZER_FZF_HEIGHT" \
  "PROJECTIZER_POPUP" "$PROJECTIZER_POPUP" \
  "PROJECTIZER_HISTORY_SIZE" "$PROJECTIZER_HISTORY_SIZE" \
  "PROJECTIZER_HISTORY_FILE" "$PROJECTIZER_HISTORY_FILE")"

tmux bind-key "$PROJECTIZER_NEW_SESSION_KEY" run-shell "$NEW_SESSION_COMMAND" >/dev/null 2>&1 || true
tmux bind-key "$PROJECTIZER_SWITCH_SESSION_KEY" run-shell "$SWITCH_SESSION_COMMAND" >/dev/null 2>&1 || true
tmux bind-key "$PROJECTIZER_KILL_SESSION_KEY" run-shell "$KILL_SESSION_COMMAND" >/dev/null 2>&1 || true

if [[ "$PROJECTIZER_QUICK_SWITCH" != "off" ]]; then
  for i in 1 2 3 4 5 6 7 8 9; do
    tmux bind-key "$i" run-shell "${CURRENT_DIR}/scripts/quick-switch.sh $i" >/dev/null 2>&1 || true
  done
fi
