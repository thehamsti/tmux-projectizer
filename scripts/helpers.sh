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

load_project_config() {
  local project_dir="$1"
  local config_path="${project_dir}/.tmux-projectizer.yml"
  local -a project_windows=()
  local line=""
  local trimmed_line=""
  local key=""
  local value=""
  local in_windows=0

  if [[ ! -f "$config_path" ]]; then
    return 0
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    trimmed_line="$(trim_whitespace "$line")"

    if [[ -z "$trimmed_line" ]]; then
      continue
    fi

    if ((in_windows)); then
      if [[ "$trimmed_line" == "- name:"* ]]; then
        value="$(trim_whitespace "${trimmed_line#- name:}")"
        value="$(strip_matching_quotes "$value")"
        if [[ -n "$value" ]]; then
          project_windows+=("$value")
        fi
        continue
      fi

      if [[ "$trimmed_line" == -* ]]; then
        continue
      fi

      in_windows=0
    fi

    if [[ "$trimmed_line" == windows: ]]; then
      in_windows=1
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
  fi
}
