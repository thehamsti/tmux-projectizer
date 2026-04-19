#!/usr/bin/env bash

if [[ -n "${PROJECTIZER_HELPERS_SOURCED:-}" ]]; then
  return 0
fi
PROJECTIZER_HELPERS_SOURCED=1

trim_whitespace() {
  local value="$1"

  value="$(printf '%s' "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  printf '%s' "$value"
}

strip_matching_quotes() {
  local value="$1"

  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
    value="${value:1:${#value}-2}"
  fi

  printf '%s' "$value"
}

window_command_var_name() {
  local window_name="$1"
  local normalized_name

  normalized_name="$(printf '%s' "$window_name" | tr '[:lower:]' '[:upper:]')"
  normalized_name="$(printf '%s' "$normalized_name" | sed -E 's/[^A-Z0-9]+/_/g; s/^_+//; s/_+$//; s/__+/_/g')"

  if [[ -z "$normalized_name" ]]; then
    normalized_name="WINDOW"
  fi

  printf 'PROJECTIZER_WINDOW_%s_COMMAND' "$normalized_name"
}

get_option() {
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

get_history_file() {
  printf '%s' "${PROJECTIZER_HISTORY_FILE:-$(get_option "@projectizer-history-file" "$HOME/.tmux/projectizer-recent")}"
}

get_history_size() {
  local history_size

  history_size="${PROJECTIZER_HISTORY_SIZE:-$(get_option "@projectizer-history-size" "50")}"
  history_size="${history_size//[^0-9]/}"

  if [[ -z "$history_size" ]]; then
    history_size="50"
  fi

  printf '%s' "$history_size"
}

sanitize_session_name() {
  local raw_name="$1"
  local session_name

  session_name="$(printf '%s' "$raw_name" | tr '[:upper:]' '[:lower:]')"
  session_name="${session_name// /-}"
  session_name="${session_name//\//-}"
  session_name="${session_name//:/-}"
  session_name="$(printf '%s' "$session_name" | sed -E 's/[^a-z0-9._-]+/-/g; s/[-_]+/-/g; s/^[-.]+//; s/[-.]+$//')"

  if [[ -z "$session_name" ]]; then
    session_name="project"
  fi

  printf '%s' "$session_name"
}

has_popup() {
  tmux list-commands 2>/dev/null | grep -q '^display-popup'
}

has_fzf() {
  command -v fzf >/dev/null 2>&1
}

read_recent_sessions() {
  local history_file

  history_file="$(get_history_file)"
  if [[ ! -f "$history_file" ]]; then
    return 0
  fi

  awk 'NF && !seen[$0]++ { print }' "$history_file"
}

remove_from_recent_sessions() {
  local session_name="$1"
  local history_file
  local temp_file

  if [[ -z "$session_name" ]]; then
    return 0
  fi

  history_file="$(get_history_file)"
  if [[ ! -f "$history_file" ]]; then
    return 0
  fi

  temp_file="$(mktemp "${history_file}.XXXXXX")"
  awk -v current="$session_name" 'NF && $0 != current && !seen[$0]++ { print }' "$history_file" >"$temp_file"
  mv "$temp_file" "$history_file"
}

record_recent_session() {
  local session_name="$1"
  local history_file
  local history_dir
  local history_size
  local temp_file

  if [[ -z "$session_name" ]]; then
    return 0
  fi

  history_file="$(get_history_file)"
  history_size="$(get_history_size)"
  history_dir="$(dirname "$history_file")"

  mkdir -p "$history_dir"
  temp_file="$(mktemp "${history_file}.XXXXXX")"

  {
    printf '%s\n' "$session_name"
    if [[ -f "$history_file" ]]; then
      awk -v current="$session_name" 'NF && $0 != current && !seen[$0]++ { print }' "$history_file"
    fi
  } | head -n "$history_size" >"$temp_file"

  mv "$temp_file" "$history_file"
}

write_ordered_sessions() {
  local output_file="$1"
  local exclude_session="${2:-}"
  local session_file
  local remaining_file
  local ordered_file
  local recent_session

  session_file="$(mktemp -t tmux-projectizer-sessions-all.XXXXXX)"
  remaining_file="$(mktemp -t tmux-projectizer-sessions-remaining.XXXXXX)"
  ordered_file="$(mktemp -t tmux-projectizer-sessions-ordered.XXXXXX)"

  tmux list-sessions -F "#S" | awk 'NF && !seen[$0]++ { print }' | sort >"$session_file"
  : >"$output_file"

  while IFS= read -r recent_session; do
    [[ -n "$recent_session" ]] || continue
    [[ -z "$exclude_session" || "$recent_session" != "$exclude_session" ]] || continue

    if grep -Fxq "$recent_session" "$session_file"; then
      printf '%s\n' "$recent_session" >>"$output_file"
    fi
  done < <(read_recent_sessions)

  if [[ -n "$exclude_session" ]]; then
    grep -Fxv "$exclude_session" "$session_file" >"$remaining_file" || true
  else
    cp "$session_file" "$remaining_file"
  fi

  if [[ -s "$output_file" ]]; then
    cat "$output_file" >"$ordered_file"
    grep -Fvx -f "$output_file" "$remaining_file" >>"$ordered_file" || true
    mv "$ordered_file" "$output_file"
  else
    cat "$remaining_file" >"$output_file"
  fi

  rm -f "$session_file" "$remaining_file" "$ordered_file"
}

load_project_config() {
  local project_dir="$1"
  local config_path="${project_dir}/.tmux-projectizer.yml"
  local -a project_windows=()
  local -a project_window_commands=()
  local line=""
  local raw_line=""
  local trimmed_line=""
  local key=""
  local value=""
  local in_windows=0
  local current_window_index=-1
  local command_var_name=""

  if [[ ! -f "$config_path" ]]; then
    return 0
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    raw_line="${line%%#*}"
    trimmed_line="$(trim_whitespace "$raw_line")"

    if [[ -z "$trimmed_line" ]]; then
      continue
    fi

    if ((in_windows)); then
      if [[ ! "$raw_line" =~ ^[[:space:]] ]]; then
        in_windows=0
        current_window_index=-1
      fi
    fi

    if ((in_windows)); then
      if [[ "$trimmed_line" == "- name:"* ]]; then
        value="$(trim_whitespace "${trimmed_line#- name:}")"
        value="$(strip_matching_quotes "$value")"
        if [[ -n "$value" ]]; then
          project_windows+=("$value")
          project_window_commands+=("")
          current_window_index=$((${#project_windows[@]} - 1))
        fi
        continue
      fi

      if ((current_window_index >= 0 )) &&
        { [[ "$trimmed_line" == "command:"* ]] || [[ "$trimmed_line" == "- command:"* ]]; }; then
        if [[ "$trimmed_line" == "- command:"* ]]; then
          value="$(trim_whitespace "${trimmed_line#- command:}")"
        else
          value="$(trim_whitespace "${trimmed_line#command:}")"
        fi
        value="$(strip_matching_quotes "$value")"
        project_window_commands[current_window_index]="$value"
        continue
      fi

      continue
    fi

    if [[ "$trimmed_line" == windows: ]]; then
      in_windows=1
      current_window_index=-1
      continue
    fi

    if [[ "$trimmed_line" != *:* ]]; then
      continue
    fi

    key="$(trim_whitespace "${trimmed_line%%:*}")"
    value="$(trim_whitespace "${trimmed_line#*:}")"
    value="$(strip_matching_quotes "$value")"

    if [[ -z "$value" ]]; then
      continue
    fi

    case "$key" in
      layout)
        printf 'PROJECTIZER_LAYOUT=%s\n' "$value"
        ;;
      main_pane_width)
        printf 'PROJECTIZER_MAIN_PANE_WIDTH=%s\n' "$value"
        ;;
      initial_window)
        printf 'PROJECTIZER_INITIAL_WINDOW=%s\n' "$value"
        ;;
      search_depth)
        printf 'PROJECTIZER_SEARCH_DEPTH=%s\n' "$value"
        ;;
    esac
  done <"$config_path"

  if ((${#project_windows[@]} > 0)); then
    printf 'PROJECTIZER_WINDOWS=%s\n' "${project_windows[*]}"

    for current_window_index in "${!project_windows[@]}"; do
      value="${project_window_commands[$current_window_index]}"
      if [[ -z "$value" ]]; then
        continue
      fi

      command_var_name="$(window_command_var_name "${project_windows[$current_window_index]}")"
      printf '%s=%s\n' "$command_var_name" "$value"
    done
  fi
}
