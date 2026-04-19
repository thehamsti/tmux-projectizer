#!/usr/bin/env bash

if [[ -n "${PROJECTIZER_HELPERS_SOURCED:-}" ]]; then
  return 0
fi
PROJECTIZER_HELPERS_SOURCED=1

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
