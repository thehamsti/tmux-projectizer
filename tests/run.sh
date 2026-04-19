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

run_test "sanitize session name" test_sanitize_session_name
run_test "reuse existing session" test_new_project_session_reuses_existing_session
run_test "create session layout and windows" test_new_project_session_creates_windows_and_layout
run_test "switch-session fallback" test_switch_session_uses_choose_tree_without_popup
run_test "switch-session popup flow" test_switch_session_uses_popup_and_switches

printf 'ok: %s tests\n' "$test_count"
