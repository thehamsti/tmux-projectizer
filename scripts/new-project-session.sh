#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./helpers.sh disable=SC1091
source "${SCRIPT_DIR}/helpers.sh"

PROJECTIZER_PATHS="${PROJECTIZER_PATHS:-$(get_option "@projectizer-paths" "$HOME/projects")}"
PROJECTIZER_SEARCH_DEPTH="${PROJECTIZER_SEARCH_DEPTH:-$(get_option "@projectizer-search-depth" "2")}"
PROJECTIZER_LAYOUT="${PROJECTIZER_LAYOUT:-$(get_option "@projectizer-layout" "main-vertical")}"
PROJECTIZER_MAIN_PANE_WIDTH="${PROJECTIZER_MAIN_PANE_WIDTH:-$(get_option "@projectizer-main-pane-width" "66%")}"
PROJECTIZER_WINDOWS="${PROJECTIZER_WINDOWS:-$(get_option "@projectizer-windows" "main bg logs")}"
PROJECTIZER_INITIAL_WINDOW="${PROJECTIZER_INITIAL_WINDOW:-$(get_option "@projectizer-initial-window" "1")}"
PROJECTIZER_FZF_HEIGHT="${PROJECTIZER_FZF_HEIGHT:-$(get_option "@projectizer-fzf-height" "40%")}"
PROJECTIZER_POPUP="${PROJECTIZER_POPUP:-$(get_option "@projectizer-popup" "auto")}"

PROJECTIZER_SEARCH_DEPTH="${PROJECTIZER_SEARCH_DEPTH//[^0-9]/}"
if [[ -z "$PROJECTIZER_SEARCH_DEPTH" ]]; then
  PROJECTIZER_SEARCH_DEPTH="2"
fi

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

show_project_prompt() {
  local prompt_command

  printf -v prompt_command 'run-shell "bash %q --dir \\"%%1\\""' "${SCRIPT_DIR}/new-project-session.sh"
  tmux command-prompt -I "#{pane_current_path}" -p "Project dir:" "$prompt_command"
}

collect_projects() {
  local output_file="$1"
  local project_root

  : >"$output_file"
  for project_root in $PROJECTIZER_PATHS; do
    [[ -d "$project_root" ]] || continue
    printf '%s\n' "$project_root" >>"$output_file"
    find "$project_root" -mindepth 1 -maxdepth "$PROJECTIZER_SEARCH_DEPTH" -type d 2>/dev/null >>"$output_file"
  done
  awk 'NF && !seen[$0]++' "$output_file" > "${output_file}.dedupe"
  mv "${output_file}.dedupe" "$output_file"
}

choose_project_with_popup() {
  local project_file="$1"
  local selection_file="$2"
  local selected_project
  local popup_status
  local popup_command

  popup_command="bash -lc 'cat $(shell_quote "$project_file") | fzf --prompt=\"Project> \" --height=$(shell_quote "$PROJECTIZER_FZF_HEIGHT") > $(shell_quote "$selection_file")'"

  set +e
  tmux display-popup -E "$popup_command"
  popup_status=$?
  set -e

  case "$popup_status" in
    0)
      selected_project="$(cat "$selection_file" 2>/dev/null || true)"
      ;;
    1|130)
      return 130
      ;;
    *)
      tmux display-message "projectizer popup failed (status ${popup_status})"
      return "$popup_status"
      ;;
  esac

  if [[ -z "$selected_project" ]]; then
    return 130
  fi

  printf '%s' "$selected_project"
}

parse_window_names() {
  local raw_windows="$1"
  local window_name

  WINDOW_NAMES_PARSED=()
  for window_name in $raw_windows; do
    WINDOW_NAMES_PARSED+=("$window_name")
  done

  if ((${#WINDOW_NAMES_PARSED[@]} == 0)); then
    WINDOW_NAMES_PARSED=("main")
  fi
}

get_window_command() {
  local window_name="$1"
  local command_var_name

  command_var_name="$(window_command_var_name "$window_name")"
  printf '%s' "${!command_var_name-}"
}

run_window_startup_command() {
  local target="$1"
  local window_name="$2"
  local command

  command="$(get_window_command "$window_name")"
  if [[ -z "$command" ]]; then
    return 0
  fi

  tmux send-keys -t "$target" "$command" Enter
}

create_session() {
  local session_name="$1"
  local project_dir="$2"
  local -a window_names
  local -a created_windows
  local first_window_index
  local window_target
  local current_window_index
  local requested_initial_window
  local i

  parse_window_names "$PROJECTIZER_WINDOWS"
  window_names=("${WINDOW_NAMES_PARSED[@]}")

  tmux new-session -d -s "$session_name" -c "$project_dir" -n "${window_names[0]}"
  first_window_index="$(tmux display-message -p -t "$session_name" '#{window_index}')"
  created_windows=("${session_name}:${first_window_index}")

  # Preserve the original "workspace plus stacked side panes" layout on the first window.
  tmux split-window -h -t "${session_name}:${first_window_index}" -c "$project_dir"
  tmux split-window -v -t "${session_name}:${first_window_index}.2" -c "$project_dir"
  if [[ "$PROJECTIZER_LAYOUT" == main-* ]]; then
    tmux set-window-option -t "${session_name}:${first_window_index}" main-pane-width "$PROJECTIZER_MAIN_PANE_WIDTH"
  fi
  tmux select-layout -t "${session_name}:${first_window_index}" "$PROJECTIZER_LAYOUT"
  tmux select-pane -t "${session_name}:${first_window_index}.1"
  run_window_startup_command "${session_name}:${first_window_index}.1" "${window_names[0]}"

  for ((i = 1; i < ${#window_names[@]}; i += 1)); do
    tmux new-window -t "$session_name" -n "${window_names[$i]}" -c "$project_dir"
    current_window_index="$(tmux display-message -p -t "$session_name" '#{window_index}')"
    created_windows+=("${session_name}:${current_window_index}")
    run_window_startup_command "${session_name}:${current_window_index}.1" "${window_names[$i]}"
  done

  requested_initial_window="$PROJECTIZER_INITIAL_WINDOW"
  if [[ "$requested_initial_window" =~ ^[0-9]+$ ]] &&
    ((requested_initial_window >= 1 && requested_initial_window <= ${#created_windows[@]})); then
    window_target="${created_windows[$((requested_initial_window - 1))]}"
  else
    window_target="${created_windows[0]}"
  fi

  tmux select-window -t "$window_target"
  tmux switch-client -t "$session_name"
  record_recent_session "$session_name"
}

project_dir=""
if [[ "${1-}" == "--dir" ]]; then
  project_dir="${2-}"
else
  project_file="$(mktemp -t tmux-projectizer-projects.XXXXXX)"
  selection_file="$(mktemp -t tmux-projectizer-projects-selection.XXXXXX)"
  register_temp_file "$project_file"
  register_temp_file "$selection_file"

  collect_projects "$project_file"
  if [[ ! -s "$project_file" ]]; then
    tmux display-message "No projects found in: $PROJECTIZER_PATHS"
    exit 0
  fi

  if has_fzf && should_use_popup; then
    if ! project_dir="$(choose_project_with_popup "$project_file" "$selection_file")"; then
      exit 0
    fi
  else
    if should_require_popup && ! has_popup; then
      tmux display-message "projectizer popup mode requires tmux >= 3.2"
      exit 1
    fi
    show_project_prompt
    exit 0
  fi
fi

if [[ -z "$project_dir" ]]; then
  exit 0
fi

if [[ ! -d "$project_dir" ]]; then
  tmux display-message "Project path does not exist: $project_dir"
  exit 1
fi

while IFS= read -r config_line; do
  [[ -n "$config_line" ]] || continue

  case "${config_line%%=*}" in
    PROJECTIZER_WINDOWS)
      PROJECTIZER_WINDOWS="${config_line#*=}"
      ;;
    PROJECTIZER_LAYOUT)
      PROJECTIZER_LAYOUT="${config_line#*=}"
      ;;
    PROJECTIZER_MAIN_PANE_WIDTH)
      PROJECTIZER_MAIN_PANE_WIDTH="${config_line#*=}"
      ;;
    PROJECTIZER_INITIAL_WINDOW)
      PROJECTIZER_INITIAL_WINDOW="${config_line#*=}"
      ;;
    PROJECTIZER_SEARCH_DEPTH)
      PROJECTIZER_SEARCH_DEPTH="${config_line#*=}"
      ;;
    PROJECTIZER_WINDOW_*_COMMAND)
      printf -v "${config_line%%=*}" '%s' "${config_line#*=}"
      ;;
  esac
done < <(load_project_config "$project_dir")

PROJECTIZER_SEARCH_DEPTH="${PROJECTIZER_SEARCH_DEPTH//[^0-9]/}"
if [[ -z "$PROJECTIZER_SEARCH_DEPTH" ]]; then
  PROJECTIZER_SEARCH_DEPTH="2"
fi

session_name="$(sanitize_session_name "$(basename "$project_dir")")"
if tmux has-session -t "$session_name" 2>/dev/null; then
  tmux switch-client -t "$session_name"
  record_recent_session "$session_name"
  exit 0
fi

create_session "$session_name" "$project_dir"
