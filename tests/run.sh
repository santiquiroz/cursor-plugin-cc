#!/usr/bin/env bash
set -u

TEST_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TEST_DIR/.." && pwd)
FIXTURES="$TEST_DIR/fixtures"
FORWARDER="$ROOT/scripts/cursor-forward.sh"
FILTER=${1:-}
REAL_GIT=$(command -v git 2>/dev/null || :)
REAL_NODE=$(command -v node 2>/dev/null || :)
REAL_GIT_DIR=${REAL_GIT%/*}
REAL_NODE_DIR=${REAL_NODE%/*}
TOTAL=0
FAILED=0
RUN_COUNT=0
TEST_FAILED=0
CALL_ARGS=()

fail() {
  printf '  FAIL: %s\n' "$1"
  TEST_FAILED=1
}

assert_status() {
  [ "$1" = "$2" ] || fail "$3 (expected exit $1, got $2)"
}

assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *) fail "$3 (missing: $2)" ;;
  esac
}

assert_not_contains() {
  case "$1" in
    *"$2"*) fail "$3 (unexpected: $2)" ;;
    *) ;;
  esac
}

assert_equal() {
  [ "$1" = "$2" ] || fail "$3 (expected '$1', got '$2')"
}

isolate_git() {
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  git config --global user.name "Cursor Rescue Test"
  git config --global user.email "cursor-rescue-test@example.com"
}

new_sandbox() {
  SANDBOX=$(mktemp -d)
  export HOME="$SANDBOX"
  export CURSOR_RESCUE_HOME="$HOME/.cursor-rescue"
  export LOCALAPPDATA="$HOME/AppData/Local"
  export FAKE_CURSOR_CALLS="$HOME/calls"
  export FAKE_CURSOR_ABOUT="$FIXTURES/about-free.txt"
  mkdir -p "$HOME/bin" "$CURSOR_RESCUE_HOME" "$LOCALAPPDATA" "$FAKE_CURSOR_CALLS"
  cp "$ROOT/docs/cli-config.json" "$CURSOR_RESCUE_HOME/cli-config.json"
  cp "$TEST_DIR/fake-cursor-agent.sh" "$HOME/bin/cursor-agent"
  chmod +x "$HOME/bin/cursor-agent"
  export CURSOR_AGENT_BIN="$HOME/bin/cursor-agent"
  unset CURSOR_API_KEY CURSOR_AUTH_TOKEN CURSOR_AGENT_NODE CURSOR_AGENT_INDEX
  unset CURSOR_RESCUE_TIMEOUT MSYS_NO_PATHCONV MSYS2_ARG_CONV_EXCL GIT_TERMINAL_PROMPT GIT_SSH_COMMAND
  unset NO_OPEN_BROWSER CURSOR_RESCUE_FAKE_HOME FAKE_CURSOR_MODE
  PATH="$HOME/bin:/usr/bin:/bin"
  [ -n "$REAL_GIT_DIR" ] && PATH="$PATH:$REAL_GIT_DIR"
  [ -n "$REAL_NODE_DIR" ] && PATH="$PATH:$REAL_NODE_DIR"
  export PATH
  isolate_git
  mkdir -p "$HOME/repo"
  (
    cd "$HOME/repo" || exit 1
    git init -q &&
      printf '%s\n' 'sandbox' >README.md &&
      git add README.md &&
      git commit -q -m initial
  )
  : >"$HOME/task.txt"
}

invoke_args() {
  LAST_OUTPUT=$(cd "$HOME/repo" && bash "$FORWARDER" "$@" 2>&1)
  LAST_STATUS=$?
}

invoke_file() {
  input_file=$1
  shift
  LAST_OUTPUT=$(cd "$HOME/repo" && bash "$FORWARDER" "$@" <"$input_file" 2>&1)
  LAST_STATUS=$?
}

load_call_args() {
  call_number=$1
  CALL_ARGS=()
  while IFS= read -r -d '' arg; do
    CALL_ARGS[${#CALL_ARGS[@]}]=$arg
  done <"$FAKE_CURSOR_CALLS/$call_number.args"
}

has_arg() {
  wanted=$1
  for arg in "${CALL_ARGS[@]}"; do
    [ "$arg" = "$wanted" ] && return 0
  done
  return 1
}

arg_value() {
  wanted=$1
  index=0
  while [ "$index" -lt "${#CALL_ARGS[@]}" ]; do
    if [ "${CALL_ARGS[$index]}" = "$wanted" ]; then
      next=$((index + 1))
      [ "$next" -lt "${#CALL_ARGS[@]}" ] && printf '%s' "${CALL_ARGS[$next]}"
      return 0
    fi
    index=$((index + 1))
  done
  return 1
}

assert_arg() {
  has_arg "$1" || fail "$2 (missing argument: $1)"
}

assert_no_arg() {
  if has_arg "$1"; then
    fail "$2 (unexpected argument: $1)"
  fi
}

extract_constraint() {
  constraint_name=$1
  ai_clis=$(sed -n '/^readonly AI_CLIS="/{s/^readonly AI_CLIS="//; s/"$//; p;}' "$FORWARDER")
  template=$(sed -n "/^readonly $constraint_name=\"/{s/^readonly $constraint_name=\"//; s/\"\$//; p;}" "$FORWARDER")
  template=${template//\$AI_CLIS/$ai_clis}
  printf '%s' "$template"
}

normalize_path() {
  if command -v cygpath >/dev/null 2>&1; then
    NORMALIZED_PATH=$(cygpath -m "$1")
  else
    NORMALIZED_PATH=$1
  fi
}

assert_env_value() {
  env_file=$1
  env_key=$2
  expected_value=$3
  actual_value=$(sed -n "s/^$env_key=//p" "$env_file")
  assert_equal "$expected_value" "$actual_value" "$env_key environment"
}

test_preflight_free() {
  invoke_args preflight --model claude-opus-5-5-high
  assert_status 0 "$LAST_STATUS" "Free-plan preflight"
  assert_contains "$LAST_OUTPUT" '[cursor-rescue] Free plan only runs auto; running on auto instead of claude-opus-5-5-high' "Free-plan model switch"
  assert_contains "$LAST_OUTPUT" 'model: auto' "Free-plan selected model"
}

test_deny_gate() {
  sed '/"Shell(git -C)"/d' "$CURSOR_RESCUE_HOME/cli-config.json" >"$HOME/config.tmp"
  mv "$HOME/config.tmp" "$CURSOR_RESCUE_HOME/cli-config.json"
  invoke_args preflight
  assert_status 78 "$LAST_STATUS" "Deny-gate preflight"
  assert_contains "$LAST_OUTPUT" 'Shell(git -C)' "Deny-gate missing rule"
  printf '%s\n' 'task' >"$HOME/task.txt"
  invoke_file "$HOME/task.txt" run
  assert_status 78 "$LAST_STATUS" "Deny-gate run"
  assert_contains "$LAST_OUTPUT" 'Shell(git -C)' "Deny-gate run missing rule"
  [ ! -e "$FAKE_CURSOR_CALLS/1.args" ] || fail "Deny-gate run invoked the fake launcher"
}

test_preflight_pro() {
  export FAKE_CURSOR_ABOUT="$FIXTURES/about-pro.txt"
  invoke_args preflight --model gpt-5.5-high
  assert_status 0 "$LAST_STATUS" "Pro-plan preflight"
  assert_contains "$LAST_OUTPUT" 'model: gpt-5.5-high' "Pro-plan selected model"
  assert_not_contains "$LAST_OUTPUT" 'Free plan only runs auto' "Pro-plan model switch"
}

test_logged_out() {
  export FAKE_CURSOR_ABOUT="$FIXTURES/about-logged-out.txt"
  invoke_args preflight
  assert_status 70 "$LAST_STATUS" "Logged-out preflight"
  assert_contains "$LAST_OUTPUT" 'not signed in' "Logged-out message"
  export CURSOR_API_KEY=x
  invoke_args preflight
  assert_status 0 "$LAST_STATUS" "API-key preflight"
}

test_launcher_missing() {
  unset CURSOR_AGENT_BIN
  rm "$HOME/bin/cursor-agent"
  invoke_args preflight
  assert_status 127 "$LAST_STATUS" "Missing-launcher preflight"
  assert_contains "$LAST_OUTPUT" 'cursor-agent not found' "Missing-launcher message"
}

test_tricky_task() {
  task=$(cat "$FIXTURES/tricky-task.txt")
  constraints=$(extract_constraint CONSTRAINTS)
  expected_prompt=$(printf '%s\n\n%s' "$task" "$constraints")
  invoke_file "$FIXTURES/tricky-task.txt" run
  assert_status 0 "$LAST_STATUS" "Tricky-task run"
  load_call_args 1
  actual_prompt=$(arg_value -p)
  assert_equal "$expected_prompt" "$actual_prompt" "Forwarded tricky task prompt"
}

test_run_flags() {
  printf '%s\n' 'flags' >"$HOME/task.txt"
  invoke_file "$HOME/task.txt" run
  assert_status 0 "$LAST_STATUS" "Default run"
  load_call_args 1
  assert_arg --output-format "Output format flag"
  assert_equal stream-json "$(arg_value --output-format)" "Output format value"
  assert_arg --trust "Trust flag"
  assert_arg --workspace "Workspace flag"
  [ -n "$(arg_value --workspace)" ] || fail "Workspace path value is empty"
  assert_arg --force "Force flag"
  assert_equal auto "$(arg_value --model)" "Default model"
  assert_no_arg --mode "Default mode flag"

  invoke_file "$HOME/task.txt" run --read-only
  assert_status 0 "$LAST_STATUS" "Read-only run"
  load_call_args 2
  assert_equal ask "$(arg_value --mode)" "Read-only mode"
  read_only_constraints=$(extract_constraint READ_ONLY_CONSTRAINTS)
  expected_prompt=$(printf '%s\n\n%s' 'flags' "$read_only_constraints")
  assert_equal "$expected_prompt" "$(arg_value -p)" "Read-only prompt constraints"

  invoke_file "$HOME/task.txt" run --continue
  assert_status 0 "$LAST_STATUS" "Continue run"
  load_call_args 3
  assert_arg --continue "Continue flag"
}

test_run_env() {
  printf '%s\n' 'env' >"$HOME/task.txt"
  invoke_file "$HOME/task.txt" run
  assert_status 0 "$LAST_STATUS" "Environment run"
  env_file="$FAKE_CURSOR_CALLS/1.env"
  normalize_path "$CURSOR_RESCUE_HOME"
  expected_config=$NORMALIZED_PATH
  actual_config=$(sed -n 's/^CURSOR_CONFIG_DIR=//p' "$env_file")
  normalize_path "$actual_config"
  assert_equal "$expected_config" "$NORMALIZED_PATH" "CURSOR_CONFIG_DIR environment"
  assert_env_value "$env_file" MSYS2_ARG_CONV_EXCL '*'
  assert_env_value "$env_file" MSYS_NO_PATHCONV ''
  assert_env_value "$env_file" GIT_TERMINAL_PROMPT 0
  assert_env_value "$env_file" GIT_SSH_COMMAND 'ssh -o BatchMode=yes'
  assert_env_value "$env_file" NO_OPEN_BROWSER 1
}

test_filter_output() {
  printf '%s\n' 'filter' >"$HOME/task.txt"
  invoke_file "$HOME/task.txt" run
  assert_status 0 "$LAST_STATUS" "Filter run"
  assert_contains "$LAST_OUTPUT" 'Working on it.' "Assistant text"
  assert_contains "$LAST_OUTPUT" '  > shell git status --short' "Started tool call"
  assert_contains "$LAST_OUTPUT" '  x edit: Hook blocked with message: boom' "Failed tool call"
  assert_not_contains "$LAST_OUTPUT" 'second line' "Failed tool call first-line truncation"
  assert_contains "$LAST_OUTPUT" '[cursor-rescue] done in 2s, session s1' "Completion event"
  assert_contains "$LAST_OUTPUT" 'plain stderr line' "Plain stderr passthrough"
  assert_contains "$LAST_OUTPUT" '[cursor-rescue] exit 0' "Run exit status"
  assert_not_contains "$LAST_OUTPUT" 'Connection lost' "Transient connection message filtering"
}

test_manifests() {
  plugin_version=$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$ROOT/.claude-plugin/plugin.json" | head -n 1)
  marketplace_versions=$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$ROOT/.claude-plugin/marketplace.json")
  changelog_version=$(sed -n 's/^## \([^ ]*\).*/\1/p' "$ROOT/CHANGELOG.md" | head -n 1)
  assert_equal "$plugin_version" "$changelog_version" "Plugin and changelog versions"
  assert_equal "$plugin_version" "$(printf '%s\n' "$marketplace_versions" | sed -n '1p')" "Marketplace metadata version"
  assert_equal "$plugin_version" "$(printf '%s\n' "$marketplace_versions" | sed -n '2p')" "Marketplace plugin version"
}

test_timeout() {
  if ! command -v timeout >/dev/null 2>&1 &&
    ! command -v gtimeout >/dev/null 2>&1 &&
    ! command -v perl >/dev/null 2>&1; then
    printf 'SKIP timeout (no timeout, gtimeout, or perl)\n'
    return
  fi
  printf '%s\n' 'sleep' >"$HOME/task.txt"
  export CURSOR_RESCUE_TIMEOUT=2 FAKE_CURSOR_MODE=sleep
  invoke_file "$HOME/task.txt" run
  case "$LAST_STATUS" in
    124 | 137 | 142) ;;
    *) fail "Timeout run returned unexpected exit $LAST_STATUS" ;;
  esac
  assert_contains "$LAST_OUTPUT" 'timed out after' "Timeout message"
}

test_git_warning() {
  printf '%s\n' 'commit' >"$HOME/task.txt"
  export FAKE_CURSOR_MODE=commit
  invoke_file "$HOME/task.txt" run
  assert_status 0 "$LAST_STATUS" "Commit-mode run"
  assert_contains "$LAST_OUTPUT" '[cursor-rescue] WARNING: HEAD moved' "Git HEAD warning"
}

test_stdin_closed() {
  printf '%s\n' 'stdin' >"$HOME/task.txt"
  export FAKE_CURSOR_MODE=stdin
  invoke_file "$HOME/task.txt" run
  assert_status 0 "$LAST_STATUS" "Stdin-mode run"
  assert_contains "$LAST_OUTPUT" 'STDIN CLOSED' "Closed launcher stdin"
}

test_long_task() {
  awk 'BEGIN { for (i = 0; i < 30001; i++) printf "x" }' >"$HOME/task.txt"
  invoke_file "$HOME/task.txt" run
  assert_status 64 "$LAST_STATUS" "Long-task run"
  assert_contains "$LAST_OUTPUT" 'over the 30000 limit' "Long-task limit message"
  [ ! -e "$FAKE_CURSOR_CALLS/1.args" ] || fail "Long task invoked the fake launcher"
}

test_empty_task() {
  printf ' \n\t\n' >"$HOME/task.txt"
  invoke_file "$HOME/task.txt" run
  assert_status 64 "$LAST_STATUS" "Empty-task run"
  [ ! -e "$FAKE_CURSOR_CALLS/1.args" ] || fail "Empty task invoked the fake launcher"
}

test_named_model() {
  printf '%s\n' 'model' >"$HOME/task.txt"
  export FAKE_CURSOR_MODE=named-model
  invoke_file "$HOME/task.txt" run --model claude-opus-5-5-high
  assert_status 1 "$LAST_STATUS" "Named-model run"
  assert_contains "$LAST_OUTPUT" 'ActionRequiredError' "Named-model error"
}

test_bundle_isolation() {
  export CURSOR_AGENT_NODE="$HOME/bin/cursor-agent"
  export CURSOR_AGENT_INDEX=/x/index.js
  printf '%s\n' on >"$CURSOR_RESCUE_HOME/isolate"
  invoke_args preflight
  assert_status 0 "$LAST_STATUS" "Isolated bundle preflight"
  assert_contains "$LAST_OUTPUT" 'isolate: on' "Bundle isolation status"
  printf '%s\n' 'bundle' >"$HOME/task.txt"
  invoke_file "$HOME/task.txt" run
  assert_status 0 "$LAST_STATUS" "Isolated bundle run"
  [ -f "$FAKE_CURSOR_CALLS/2.require" ] || fail "Bundle run did not record --require"
  require_path=$(cat "$FAKE_CURSOR_CALLS/2.require")
  case "$require_path" in
    *cursor-preload.js) ;;
    *) fail "Bundle --require path did not end in cursor-preload.js" ;;
  esac
  fake_home=$(sed -n 's/^CURSOR_RESCUE_FAKE_HOME=//p' "$FAKE_CURSOR_CALLS/2.env")
  [ -n "$fake_home" ] || fail "Bundle isolation did not set CURSOR_RESCUE_FAKE_HOME"
  invoke_args preflight --no-isolate
  assert_status 0 "$LAST_STATUS" "No-isolation bundle preflight"
  assert_contains "$LAST_OUTPUT" 'isolate: off' "No-isolation bundle status"
  invoke_file "$HOME/task.txt" run --no-isolate
  assert_status 0 "$LAST_STATUS" "No-isolation bundle run"
  [ -f "$FAKE_CURSOR_CALLS/4.require" ] || fail "Bundle run without isolation dropped the env-cleanup preload"
  fake_home=$(sed -n 's/^CURSOR_RESCUE_FAKE_HOME=//p' "$FAKE_CURSOR_CALLS/4.env")
  [ -z "$fake_home" ] || fail "--no-isolate still set CURSOR_RESCUE_FAKE_HOME"
}

test_isolation_without_bundle() {
  printf '%s\n' on >"$CURSOR_RESCUE_HOME/isolate"
  invoke_args preflight
  assert_status 0 "$LAST_STATUS" "Isolation request without bundle"
  assert_contains "$LAST_OUTPUT" 'isolate: off (needs the Windows node.exe bundle)' "Isolation bundle requirement"
}

run_case() {
  test_name=$1
  test_function=$2
  if [ -n "$FILTER" ] && [ "$FILTER" != "$test_name" ] && [ "$FILTER" != "$test_function" ]; then
    return
  fi
  RUN_COUNT=$((RUN_COUNT + 1))
  TOTAL=$((TOTAL + 1))
  TEST_FAILED=0
  new_sandbox
  "$test_function"
  if [ "$TEST_FAILED" -eq 0 ]; then
    printf 'PASS %s\n' "$test_name"
  else
    printf 'FAIL %s\n' "$test_name"
    FAILED=$((FAILED + 1))
  fi
}

run_case preflight-free test_preflight_free
run_case deny-gate test_deny_gate
run_case preflight-pro test_preflight_pro
run_case logged-out test_logged_out
run_case launcher-missing test_launcher_missing
run_case tricky-task test_tricky_task
run_case run-flags test_run_flags
run_case run-env test_run_env
run_case filter-output test_filter_output
run_case manifests test_manifests
run_case timeout test_timeout
run_case git-warning test_git_warning
run_case stdin-closed test_stdin_closed
run_case long-task test_long_task
run_case empty-task test_empty_task
run_case named-model test_named_model
run_case bundle-isolation test_bundle_isolation
run_case isolation-without-bundle test_isolation_without_bundle

if [ "$RUN_COUNT" -eq 0 ]; then
  printf 'FAIL no test matched filter: %s\n' "$FILTER"
  exit 1
fi
printf '%s/%s tests passed\n' "$((TOTAL - FAILED))" "$TOTAL"
[ "$FAILED" -eq 0 ]
