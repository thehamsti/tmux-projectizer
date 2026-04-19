#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d -t tmux-projectizer-tests.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT

test_count=0

assert_eq() {
  local actual="$1"
  local expected="$2"
  local message="$3"

  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: %s\nExpected: %s\nActual:   %s\n' "$message" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_contains() {
  local file_path="$1"
  local expected="$2"
  local message="$3"

  if ! grep -Fq "$expected" "$file_path"; then
    printf 'FAIL: %s\nMissing: %s\n' "$message" "$expected" >&2
    printf 'Log contents:\n' >&2
    cat "$file_path" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file_path="$1"
  local unexpected="$2"
  local message="$3"

  if grep -Fq "$unexpected" "$file_path"; then
    printf 'FAIL: %s\nUnexpected: %s\n' "$message" "$unexpected" >&2
    printf 'Log contents:\n' >&2
    cat "$file_path" >&2
    exit 1
  fi
}

run_test() {
  local name="$1"
  shift

  printf 'test: %s\n' "$name"
  test_count=$((test_count + 1))
  "$@"
}

new_stub_dir() {
  local stub_dir="$TEST_ROOT/stub-$RANDOM"
  mkdir -p "$stub_dir"
  printf '%s' "$stub_dir"
}

prepare_path() {
  local stub_dir="$1"
  ln -sf "$REPO_ROOT/tests/fake_tmux.sh" "$stub_dir/tmux"
  PATH="$stub_dir:$REPO_ROOT/tests:$PATH"
  export TMUX_STUB_DIR="$stub_dir"
  export PROJECTIZER_HISTORY_FILE="$stub_dir/projectizer-recent"
  export PROJECTIZER_HISTORY_SIZE="50"
  export PATH
  unset TMUX_STUB_HAS_POPUP TMUX_STUB_POPUP_SELECTION TMUX_STUB_POPUP_STATUS FZF_STUB_SELECTION FZF_STUB_EXIT_STATUS
}

test_sanitize_session_name() {
  local result

  result="$(
    bash -lc '
      source "'"$REPO_ROOT"'/scripts/helpers.sh"
      sanitize_session_name "Hello: World/Now"
    '
  )"
  assert_eq "$result" "hello-world-now" "sanitize_session_name normalizes mixed characters"
}

test_new_project_session_uses_project_config_windows() {
  local stub_dir log_file project_dir

  stub_dir="$(new_stub_dir)"
  prepare_path "$stub_dir"
  log_file="${stub_dir}/commands.log"
  project_dir="$TEST_ROOT/configured-project"
  mkdir -p "$project_dir"
  cat >"$project_dir/.tmux-projectizer.yml" <<'EOF'
# Project-local overrides
windows:
  - name: editor
  - name: server
  - name: tests
initial_window: 2
EOF

  PROJECTIZER_WINDOWS="main bg logs" \
    PROJECTIZER_INITIAL_WINDOW="1" \
    bash "$REPO_ROOT/scripts/new-project-session.sh" --dir "$project_dir"

  assert_contains "$log_file" "new-session -d -s configured-project -c $project_dir -n editor" "project config overrides the first window name"
  assert_contains "$log_file" "new-window -t configured-project -n server -c $project_dir" "project config creates the second configured window"
  assert_contains "$log_file" "new-window -t configured-project -n tests -c $project_dir" "project config creates the third configured window"
  assert_contains "$log_file" "select-window -t configured-project:2" "project config can override the initial window"
}

test_new_project_session_runs_project_window_commands() {
  local stub_dir log_file project_dir

  stub_dir="$(new_stub_dir)"
  prepare_path "$stub_dir"
  log_file="${stub_dir}/commands.log"
  project_dir="$TEST_ROOT/commands-project"
  mkdir -p "$project_dir"
  cat >"$project_dir/.tmux-projectizer.yml" <<'EOF'
windows:
  - name: editor
  - name: dev
    command: npm run dev
  - name: logs
    command: docker compose logs -f
  - name: tests
EOF

  PROJECTIZER_WINDOWS="main bg logs" \
    bash "$REPO_ROOT/scripts/new-project-session.sh" --dir "$project_dir"

  assert_contains "$log_file" "send-keys -t commands-project:2.1 npm run dev Enter" "startup command runs in the configured dev window"
  assert_contains "$log_file" "send-keys -t commands-project:3.1 docker compose logs -f Enter" "startup command runs in the configured logs window"

  if grep -Fq "send-keys -t commands-project:1.1" "$log_file" ||
    grep -Fq "send-keys -t commands-project:4.1" "$log_file"; then
    printf 'FAIL: plain windows should not receive startup commands\n' >&2
    printf 'Log contents:\n' >&2
    cat "$log_file" >&2
    exit 1
  fi
}

test_new_project_session_global_windows_do_not_run_commands() {
  local stub_dir log_file project_dir

  stub_dir="$(new_stub_dir)"
  prepare_path "$stub_dir"
  log_file="${stub_dir}/commands.log"
  project_dir="$TEST_ROOT/global-only-project"
  mkdir -p "$project_dir"

  PROJECTIZER_WINDOWS="main dev logs" \
    bash "$REPO_ROOT/scripts/new-project-session.sh" --dir "$project_dir"

  if grep -Fq "send-keys" "$log_file"; then
    printf 'FAIL: global tmux windows should not get startup commands\n' >&2
    printf 'Log contents:\n' >&2
    cat "$log_file" >&2
    exit 1
  fi
}

test_new_project_session_reuses_existing_session() {
  local stub_dir log_file project_dir

  stub_dir="$(new_stub_dir)"
  prepare_path "$stub_dir"
  touch "${stub_dir}/session_existing-project"
  log_file="${stub_dir}/commands.log"
  project_dir="$TEST_ROOT/existing-project"
  mkdir -p "$project_dir"

  PROJECTIZER_PATHS="$TEST_ROOT" \
    bash "$REPO_ROOT/scripts/new-project-session.sh" --dir "$project_dir"

  assert_contains "$log_file" "has-session -t existing-project" "existing sessions are checked before creation"
  assert_contains "$log_file" "switch-client -t existing-project" "existing sessions are reused"
}

test_new_project_session_creates_windows_and_layout() {
  local stub_dir log_file project_dir

  stub_dir="$(new_stub_dir)"
  prepare_path "$stub_dir"
  log_file="${stub_dir}/commands.log"
  project_dir="$TEST_ROOT/my-app"
  mkdir -p "$project_dir"

  PROJECTIZER_LAYOUT="main-vertical" \
    PROJECTIZER_MAIN_PANE_WIDTH="70%" \
    PROJECTIZER_WINDOWS="main bg logs shell" \
    PROJECTIZER_INITIAL_WINDOW="3" \
    bash "$REPO_ROOT/scripts/new-project-session.sh" --dir "$project_dir"

  assert_contains "$log_file" "new-session -d -s my-app -c $project_dir -n main" "session is created in the selected directory"
  assert_contains "$log_file" "split-window -h -t my-app:1 -c $project_dir" "first window gets the horizontal split"
  assert_contains "$log_file" "split-window -v -t my-app:1.2 -c $project_dir" "first window gets the stacked side pane"
  assert_contains "$log_file" "set-window-option -t my-app:1 main-pane-width 70%" "main pane width is applied for main layouts"
  assert_contains "$log_file" "new-window -t my-app -n bg -c $project_dir" "second window is created"
  assert_contains "$log_file" "new-window -t my-app -n logs -c $project_dir" "third window is created"
  assert_contains "$log_file" "new-window -t my-app -n shell -c $project_dir" "fourth window is created"
  assert_contains "$log_file" "select-window -t my-app:3" "configured initial window is selected by ordinal"
}

test_new_project_session_without_project_config_uses_defaults() {
  local stub_dir log_file project_dir

  stub_dir="$(new_stub_dir)"
  prepare_path "$stub_dir"
  log_file="${stub_dir}/commands.log"
  project_dir="$TEST_ROOT/default-project"
  mkdir -p "$project_dir"

  PROJECTIZER_WINDOWS="main bg logs" \
    PROJECTIZER_INITIAL_WINDOW="1" \
    bash "$REPO_ROOT/scripts/new-project-session.sh" --dir "$project_dir"

  assert_contains "$log_file" "new-session -d -s default-project -c $project_dir -n main" "defaults create the first window when no project config exists"
  assert_contains "$log_file" "new-window -t default-project -n bg -c $project_dir" "defaults create the second window when no project config exists"
  assert_contains "$log_file" "new-window -t default-project -n logs -c $project_dir" "defaults create the third window when no project config exists"
}

test_new_project_session_project_config_overrides_layout_and_width() {
  local stub_dir log_file project_dir

  stub_dir="$(new_stub_dir)"
  prepare_path "$stub_dir"
  log_file="${stub_dir}/commands.log"
  project_dir="$TEST_ROOT/layout-project"
  mkdir -p "$project_dir"
  cat >"$project_dir/.tmux-projectizer.yml" <<'EOF'
layout: main-horizontal
main_pane_width: 70%
EOF

  PROJECTIZER_LAYOUT="even-horizontal" \
    PROJECTIZER_MAIN_PANE_WIDTH="55%" \
    bash "$REPO_ROOT/scripts/new-project-session.sh" --dir "$project_dir"

  assert_contains "$log_file" "set-window-option -t layout-project:1 main-pane-width 70%" "project config overrides the main pane width"
  assert_contains "$log_file" "select-layout -t layout-project:1 main-horizontal" "project config overrides the layout"
}

test_switch_session_uses_choose_tree_without_popup() {
  local stub_dir log_file

  stub_dir="$(new_stub_dir)"
  prepare_path "$stub_dir"
  log_file="${stub_dir}/commands.log"
  export TMUX_STUB_HAS_POPUP=0

  bash "$REPO_ROOT/scripts/switch-session.sh"

  assert_contains "$log_file" "choose-tree -s" "choose-tree is used when popup selection is unavailable"
}

test_switch_session_uses_popup_and_switches() {
  local stub_dir log_file

  stub_dir="$(new_stub_dir)"
  prepare_path "$stub_dir"
  log_file="${stub_dir}/commands.log"
  export TMUX_STUB_HAS_POPUP=1
  export TMUX_STUB_POPUP_SELECTION="workspace"
  : > "${stub_dir}/session_workspace"

  bash "$REPO_ROOT/scripts/switch-session.sh"

  assert_contains "$log_file" "display-popup -E" "popup session picker is opened"
  assert_contains "$log_file" "switch-client -t workspace" "selected session becomes active"
}

test_record_recent_session_creates_history_file() {
  local history_dir history_file history_contents

  history_dir="$TEST_ROOT/history-create"
  history_file="$history_dir/recent"

  PROJECTIZER_HISTORY_FILE="$history_file" \
    PROJECTIZER_HISTORY_SIZE="5" \
    bash -lc '
      source "'"$REPO_ROOT"'/scripts/helpers.sh"
      record_recent_session "workspace"
    '

  history_contents="$(cat "$history_file")"
  assert_eq "$history_contents" "workspace" "record_recent_session creates a new history file"
}

test_record_recent_session_moves_existing_session_to_top() {
  local history_dir history_file history_contents

  history_dir="$TEST_ROOT/history-move"
  history_file="$history_dir/recent"
  mkdir -p "$history_dir"
  cat >"$history_file" <<'EOF'
blog
workspace
notes
EOF

  PROJECTIZER_HISTORY_FILE="$history_file" \
    PROJECTIZER_HISTORY_SIZE="5" \
    bash -lc '
      source "'"$REPO_ROOT"'/scripts/helpers.sh"
      record_recent_session "workspace"
    '

  history_contents="$(cat "$history_file")"
  assert_eq "$history_contents" $'workspace\nblog\nnotes' "record_recent_session moves existing sessions to the top"
}

test_record_recent_session_respects_history_size() {
  local history_dir history_file history_contents

  history_dir="$TEST_ROOT/history-size"
  history_file="$history_dir/recent"
  mkdir -p "$history_dir"
  cat >"$history_file" <<'EOF'
blog
notes
infra
docs
EOF

  PROJECTIZER_HISTORY_FILE="$history_file" \
    PROJECTIZER_HISTORY_SIZE="3" \
    bash -lc '
      source "'"$REPO_ROOT"'/scripts/helpers.sh"
      record_recent_session "workspace"
    '

  history_contents="$(cat "$history_file")"
  assert_eq "$history_contents" $'workspace\nblog\nnotes' "record_recent_session truncates the history list to the configured size"
}

test_record_recent_session_removes_duplicates() {
  local history_dir history_file history_contents

  history_dir="$TEST_ROOT/history-dedup"
  history_file="$history_dir/recent"
  mkdir -p "$history_dir"
  cat >"$history_file" <<'EOF'
blog
workspace
notes
workspace
blog
EOF

  PROJECTIZER_HISTORY_FILE="$history_file" \
    PROJECTIZER_HISTORY_SIZE="10" \
    bash -lc '
      source "'"$REPO_ROOT"'/scripts/helpers.sh"
      record_recent_session "workspace"
    '

  history_contents="$(cat "$history_file")"
  assert_eq "$history_contents" $'workspace\nblog\nnotes' "record_recent_session removes duplicate entries"
}

test_switch_session_orders_by_recency() {
  local stub_dir log_file history_dir history_file capture_file

  stub_dir="$(new_stub_dir)"
  prepare_path "$stub_dir"
  log_file="${stub_dir}/commands.log"
  history_dir="$TEST_ROOT/history-switch-order"
  history_file="$history_dir/recent"
  capture_file="$history_dir/fzf-input"
  mkdir -p "$history_dir"
  export TMUX_STUB_HAS_POPUP=1
  export TMUX_STUB_POPUP_SELECTION="blog"
  export TMUX_STUB_POPUP_CAPTURE_FILE="$capture_file"
  : > "${stub_dir}/session_blog"
  : > "${stub_dir}/session_docs"
  : > "${stub_dir}/session_workspace"
  cat >"$history_file" <<'EOF'
workspace
blog
unknown
EOF

  PROJECTIZER_HISTORY_FILE="$history_file" \
    PROJECTIZER_HISTORY_SIZE="10" \
    bash "$REPO_ROOT/scripts/switch-session.sh"

  assert_eq "$(cat "$capture_file")" $'workspace\nblog\ndocs' "switch-session sorts sessions by recency before fzf"
  assert_contains "$log_file" "switch-client -t blog" "switch-session still switches to the selected session"
}

test_kill_session_removes_target_and_history() {
  local stub_dir log_file history_file

  stub_dir="$(new_stub_dir)"
  prepare_path "$stub_dir"
  log_file="${stub_dir}/commands.log"
  history_file="${stub_dir}/projectizer-recent"
  export TMUX_STUB_HAS_POPUP=1
  export TMUX_STUB_CURRENT_SESSION="workspace"
  export TMUX_STUB_POPUP_SELECTION="blog"
  : >"${stub_dir}/session_workspace"
  : >"${stub_dir}/session_blog"
  : >"${stub_dir}/session_docs"
  cat >"$history_file" <<'EOF'
blog
workspace
docs
EOF

  bash "$REPO_ROOT/scripts/kill-session.sh"

  if [[ -e "${stub_dir}/session_blog" ]]; then
    printf 'FAIL: killed session should be removed from the tmux stub\n' >&2
    exit 1
  fi

  assert_contains "$log_file" "kill-session -t blog" "kill-session calls tmux kill-session on the selected session"
  assert_contains "$log_file" "display-message Killed session: blog" "kill-session confirms the killed session"
  assert_eq "$(cat "$history_file")" $'workspace\ndocs' "kill-session removes the killed session from the recent history file"
}

test_kill_session_excludes_current_session_from_picker() {
  local stub_dir capture_file history_file

  stub_dir="$(new_stub_dir)"
  prepare_path "$stub_dir"
  capture_file="${stub_dir}/kill-picker-input"
  history_file="${stub_dir}/projectizer-recent"
  export TMUX_STUB_HAS_POPUP=1
  export TMUX_STUB_CURRENT_SESSION="workspace"
  export TMUX_STUB_POPUP_SELECTION="blog"
  export TMUX_STUB_POPUP_CAPTURE_FILE="$capture_file"
  : >"${stub_dir}/session_workspace"
  : >"${stub_dir}/session_blog"
  : >"${stub_dir}/session_docs"
  cat >"$history_file" <<'EOF'
workspace
blog
docs
EOF

  bash "$REPO_ROOT/scripts/kill-session.sh"

  assert_eq "$(cat "$capture_file")" $'blog\ndocs' "kill-session omits the current session from the picker input while preserving recency"
}

test_kill_session_fallback_shows_message() {
  local stub_dir log_file

  stub_dir="$(new_stub_dir)"
  prepare_path "$stub_dir"
  log_file="${stub_dir}/commands.log"
  export TMUX_STUB_HAS_POPUP=0

  bash "$REPO_ROOT/scripts/kill-session.sh"

  assert_contains "$log_file" "choose-tree -s" "kill-session falls back to choose-tree when popup selection is unavailable"
  assert_contains "$log_file" "display-message projectizer kill-session requires popup + fzf; use tmux kill-session manually" "kill-session explains that fallback mode cannot delete sessions"
}

test_quick_switch_switches_to_requested_recent_session() {
  local stub_dir log_file history_file history_contents

  stub_dir="$(new_stub_dir)"
  prepare_path "$stub_dir"
  log_file="${stub_dir}/commands.log"
  history_file="${stub_dir}/projectizer-recent"
  : >"${stub_dir}/session_workspace"
  : >"${stub_dir}/session_blog"
  cat >"$history_file" <<'EOF'
workspace
blog
EOF

  bash "$REPO_ROOT/scripts/quick-switch.sh" 1

  assert_contains "$log_file" "switch-client -t workspace" "quick-switch activates the requested recent session"
  history_contents="$(cat "$history_file")"
  assert_eq "$history_contents" $'workspace\nblog' "quick-switch refreshes recency after a successful switch"
}

test_quick_switch_out_of_range_shows_message() {
  local stub_dir log_file history_file

  stub_dir="$(new_stub_dir)"
  prepare_path "$stub_dir"
  log_file="${stub_dir}/commands.log"
  history_file="${stub_dir}/projectizer-recent"
  cat >"$history_file" <<'EOF'
workspace
EOF

  bash "$REPO_ROOT/scripts/quick-switch.sh" 2

  assert_contains "$log_file" "display-message projectizer: no session at position 2" "quick-switch reports missing history positions"
  assert_not_contains "$log_file" "switch-client -t" "quick-switch does not switch when the requested position is missing"
}

test_quick_switch_missing_session_shows_message() {
  local stub_dir log_file history_file

  stub_dir="$(new_stub_dir)"
  prepare_path "$stub_dir"
  log_file="${stub_dir}/commands.log"
  history_file="${stub_dir}/projectizer-recent"
  cat >"$history_file" <<'EOF'
workspace
EOF

  bash "$REPO_ROOT/scripts/quick-switch.sh" 1

  assert_contains "$log_file" "display-message projectizer: session 'workspace' no longer exists" "quick-switch reports stale history entries"
  assert_not_contains "$log_file" "switch-client -t" "quick-switch does not switch to missing sessions"
}

test_tmux_entrypoint_binds_quick_switch_keys_by_default() {
  local stub_dir log_file

  stub_dir="$(new_stub_dir)"
  prepare_path "$stub_dir"
  log_file="${stub_dir}/commands.log"

  bash "$REPO_ROOT/tmux-projectizer.tmux"

  assert_contains "$log_file" "bind-key 1 run-shell" "quick-switch binds prefix plus 1 by default"
  assert_contains "$log_file" "bind-key 9 run-shell" "quick-switch binds prefix plus 9 by default"
  assert_contains "$log_file" "scripts/quick-switch.sh 1" "quick-switch binding targets the dedicated script"
}

test_tmux_entrypoint_skips_quick_switch_when_disabled() {
  local stub_dir log_file

  stub_dir="$(new_stub_dir)"
  prepare_path "$stub_dir"
  log_file="${stub_dir}/commands.log"
  export TMUX_OPTION_PROJECTIZER_QUICK_SWITCH="off"

  bash "$REPO_ROOT/tmux-projectizer.tmux"

  assert_not_contains "$log_file" "scripts/quick-switch.sh 1" "quick-switch bindings are skipped when disabled"
  unset TMUX_OPTION_PROJECTIZER_QUICK_SWITCH
}

test_tmux_entrypoint_binds_kill_session_key_by_default() {
  local stub_dir log_file

  stub_dir="$(new_stub_dir)"
  prepare_path "$stub_dir"
  log_file="${stub_dir}/commands.log"

  bash "$REPO_ROOT/tmux-projectizer.tmux"

  assert_contains "$log_file" "set-option -gq @projectizer-kill-session-key X" "entrypoint sets the default kill-session key"
  assert_contains "$log_file" "bind-key X run-shell" "entrypoint binds the default kill-session key"
  assert_contains "$log_file" "scripts/kill-session.sh" "kill-session binding targets the dedicated script"
}

run_test "sanitize session name" test_sanitize_session_name
run_test "project config windows" test_new_project_session_uses_project_config_windows
run_test "project config startup commands" test_new_project_session_runs_project_window_commands
run_test "global windows stay plain" test_new_project_session_global_windows_do_not_run_commands
run_test "reuse existing session" test_new_project_session_reuses_existing_session
run_test "create session layout and windows" test_new_project_session_creates_windows_and_layout
run_test "project config fallback defaults" test_new_project_session_without_project_config_uses_defaults
run_test "project config layout override" test_new_project_session_project_config_overrides_layout_and_width
run_test "switch-session fallback" test_switch_session_uses_choose_tree_without_popup
run_test "switch-session popup flow" test_switch_session_uses_popup_and_switches
run_test "recent session history file creation" test_record_recent_session_creates_history_file
run_test "recent session history reorder" test_record_recent_session_moves_existing_session_to_top
run_test "recent session history max size" test_record_recent_session_respects_history_size
run_test "recent session history dedupe" test_record_recent_session_removes_duplicates
run_test "switch-session recency ordering" test_switch_session_orders_by_recency
run_test "kill-session removes target and history" test_kill_session_removes_target_and_history
run_test "kill-session excludes current session" test_kill_session_excludes_current_session_from_picker
run_test "kill-session fallback" test_kill_session_fallback_shows_message
run_test "quick-switch success" test_quick_switch_switches_to_requested_recent_session
run_test "quick-switch out of range" test_quick_switch_out_of_range_shows_message
run_test "quick-switch missing session" test_quick_switch_missing_session_shows_message
run_test "entrypoint binds quick-switch keys" test_tmux_entrypoint_binds_quick_switch_keys_by_default
run_test "entrypoint skips quick-switch keys when disabled" test_tmux_entrypoint_skips_quick_switch_when_disabled
run_test "entrypoint binds kill-session key" test_tmux_entrypoint_binds_kill_session_key_by_default

printf 'ok: %s tests\n' "$test_count"
