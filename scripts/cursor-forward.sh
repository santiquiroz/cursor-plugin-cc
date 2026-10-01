#!/usr/bin/env bash
# Usage:
#   cursor-forward.sh preflight [--model <slug>] [--isolate|--no-isolate]
#   cursor-forward.sh run [--model <slug>] [--read-only] [--continue] [--isolate|--no-isolate] <task on stdin>
#   cursor-forward.sh models
set -u

readonly USAGE_EXIT=64
readonly PREFLIGHT_FAILED_EXIT=70
readonly UNSAFE_EXIT=78
readonly NOT_FOUND_EXIT=127
readonly MAX_TASK_CHARS=30000
readonly SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
readonly CONFIG_DIR=${CURSOR_RESCUE_HOME:-$HOME/.cursor-rescue}
readonly AI_CLIS="claude, codex, copilot, agy, gemini, ollama, cursor-agent"
readonly CONSTRAINTS="Constraints: work directly in this workspace following the instructions above. Do not invoke other AI CLIs ($AI_CLIS). Do not commit, push, switch branches or delete files. If a command is denied by policy, stop and report it — do not look for another way to run it. Leave your changes in the working tree and end with a short list of the files you touched."
readonly READ_ONLY_CONSTRAINTS="Constraints: this is a read-only run: do not edit files; report findings and proposed changes as text. Do not invoke other AI CLIs ($AI_CLIS). If a command is denied by policy, stop and report it — do not look for another way to run it."
# Exact entries of docs/cli-config.json that the gate requires before running with --force.
readonly CRITICAL_DENY_RULES=(
  'Shell(git push)' 'Shell(git reset)' 'Shell(git checkout)' 'Shell(git commit)' 'Shell(git -C)'
  'Shell(rm)' 'Shell(del)' 'Shell(Remove-Item)' 'Shell(bash)' 'Shell(powershell)' 'Shell(cmd)'
  'Write(**/.git/**)'
)
LAUNCH_MODE=""
NODE_BIN=""
INDEX_JS=""
AGENT_BIN=""
OPT_MODEL=""
OPT_ISOLATE=""
OPT_READ_ONLY=0
OPT_CONTINUE=0

usage_error() {
  printf 'cursor-forward.sh: %s\n' "$1" >&2
  exit "$USAGE_EXIT"
}

parse_options() {
  while [ $# -gt 0 ]; do
    case $1 in
      --model)
        [ $# -ge 2 ] || usage_error "--model needs a value"
        OPT_MODEL=$2
        shift 2
        ;;
      --isolate) OPT_ISOLATE=on; shift ;;
      --no-isolate) OPT_ISOLATE=off; shift ;;
      --read-only) OPT_READ_ONLY=1; shift ;;
      --continue) OPT_CONTINUE=1; shift ;;
      *) usage_error "unknown option: $1" ;;
    esac
  done
}

# Git Bash leaves arguments unconverted here (MSYS2_ARG_CONV_EXCL), so every path passed must already be native.
native_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

newest_bundle_dir() {
  local root=${LOCALAPPDATA:-} dir
  root=${root//\\//}
  [ -n "$root" ] || return 1
  dir=$(ls -d "$root"/cursor-agent/versions/*/ 2>/dev/null | sort -V | tail -n 1)
  [ -n "$dir" ] && [ -f "${dir}node.exe" ] && [ -f "${dir}index.js" ] || return 1
  printf '%s' "$dir"
}

use_bundle() {
  LAUNCH_MODE=bundle
  NODE_BIN=$1
  INDEX_JS=$2
}

use_bin() {
  LAUNCH_MODE=bin
  AGENT_BIN=$1
  NODE_BIN=$(command -v node 2>/dev/null)
}

# The Windows .cmd shim goes through cmd.exe, which cuts a multi-line prompt at its first line break.
find_launcher() {
  local dir
  if [ -n "${CURSOR_AGENT_NODE:-}" ] && [ -n "${CURSOR_AGENT_INDEX:-}" ]; then use_bundle "$CURSOR_AGENT_NODE" "$CURSOR_AGENT_INDEX"; return 0; fi
  if dir=$(newest_bundle_dir); then use_bundle "${dir}node.exe" "${dir}index.js"; return 0; fi
  if [ -n "${CURSOR_AGENT_BIN:-}" ]; then use_bin "$CURSOR_AGENT_BIN"; return 0; fi
  if command -v cursor-agent >/dev/null 2>&1; then use_bin "$(command -v cursor-agent)"; return 0; fi
  if [ -x "$HOME/.local/bin/cursor-agent" ]; then use_bin "$HOME/.local/bin/cursor-agent"; return 0; fi
  return 1
}

require_launcher() {
  find_launcher && return 0
  echo "cursor-rescue: cursor-agent not found — run /cursor:setup"
  return "$NOT_FOUND_EXIT"
}

missing_deny_rules() {
  local config="" rule missing=""
  [ -r "$CONFIG_DIR/cli-config.json" ] && IFS= read -r -d '' config <"$CONFIG_DIR/cli-config.json"
  for rule in "${CRITICAL_DENY_RULES[@]}"; do
    [[ $config == *"\"$rule\""* ]] || missing="${missing:+$missing, }$rule"
  done
  printf '%s' "$missing"
}

# --force auto-approves every tool call; the deny rules in the plugin's own config dir are what still wins.
require_deny_rules() {
  local missing
  missing=$(missing_deny_rules)
  [ -z "$missing" ] && return 0
  echo "cursor-rescue: missing deny rules in $CONFIG_DIR/cli-config.json: $missing — run /cursor:setup"
  return "$UNSAFE_EXIT"
}

isolation_wanted() {
  local saved=""
  [ -n "$OPT_ISOLATE" ] && { [ "$OPT_ISOLATE" = on ]; return; }
  [ -r "$CONFIG_DIR/isolate" ] && IFS= read -r saved <"$CONFIG_DIR/isolate"
  [ "$saved" = on ]
}

isolation_active() {
  [ "$LAUNCH_MODE" = bundle ] && isolation_wanted
}

launcher_argv() {
  if [ "$LAUNCH_MODE" != bundle ]; then
    printf '%s\0' "$AGENT_BIN"
    return 0
  fi
  printf '%s\0' "$NODE_BIN" --require "$(native_path "$SCRIPT_DIR/cursor-preload.js")" "$INDEX_JS"
}

# CURSOR_CONFIG_DIR keeps the deny rules and any --model out of the user's own ~/.cursor/cli-config.json.
# MSYS2_ARG_CONV_EXCL stops Git Bash from rewriting a task that starts with "/" into a Windows path;
# unlike MSYS_NO_PATHCONV it keeps converting path-like environment variables (GIT_CONFIG_GLOBAL...).
cursor_env() {
  unset MSYS_NO_PATHCONV
  export CURSOR_CONFIG_DIR=$CONFIG_DIR MSYS2_ARG_CONV_EXCL='*'
  isolation_active || return 0
  mkdir -p "$CONFIG_DIR/home"
  export CURSOR_RESCUE_FAKE_HOME
  CURSOR_RESCUE_FAKE_HOME=$(native_path "$CONFIG_DIR/home")
}

run_cursor() {
  local launcher=() item
  while IFS= read -r -d '' item; do launcher+=("$item"); done < <(launcher_argv)
  ( cursor_env; "${launcher[@]}" "$@" </dev/null )
}

about_field() {
  printf '%s\n' "$1" | sed -n "s/^$2[[:space:]]\{2,\}//p" | head -n 1 | tr -d '\r'
}

is_signed_in() {
  local email=$1
  [ -n "${CURSOR_API_KEY:-}" ] || [ -n "${CURSOR_AUTH_TOKEN:-}" ] && return 0
  [ -n "$email" ] && [ "$email" != "Not logged in" ]
}

print_isolation() {
  if isolation_active; then echo "isolate: on"
  elif isolation_wanted; then echo "isolate: off (needs the Windows node.exe bundle)"
  else echo "isolate: off"; fi
}

preflight() {
  local about version tier email model
  require_launcher || return
  require_deny_rules || return
  about=$(run_cursor about 2>&1)
  version=$(about_field "$about" "CLI Version")
  tier=$(about_field "$about" "Subscription Tier")
  email=$(about_field "$about" "User Email")
  if ! is_signed_in "$email"; then
    printf '[cursor-rescue] preflight failed: not signed in — run cursor-agent login once (or set CURSOR_API_KEY), then /cursor:setup\n%s\n' "$about"
    return "$PREFLIGHT_FAILED_EXIT"
  fi
  printf '[cursor-rescue] preflight: CLI %s, plan %s\n' "${version:-unknown}" "${tier:-unknown}"
  model=${OPT_MODEL:-auto}
  if [ "$tier" = Free ] && [ "$model" != auto ]; then
    printf '[cursor-rescue] Free plan only runs auto; running on auto instead of %s\n' "$model"
    model=auto
  fi
  printf 'model: %s\n' "$model"
  print_isolation
}

list_models() {
  require_launcher || return
  run_cursor models 2>&1
}

timeout_argv() {
  local seconds=${CURSOR_RESCUE_TIMEOUT:-540} bin
  if bin=$(command -v timeout || command -v gtimeout); then printf '%s\0' "$bin" -k 10 "$seconds"; return 0; fi
  command -v perl >/dev/null 2>&1 && printf '%s\0' perl -e 'alarm shift; exec @ARGV' "$seconds"
}

filter_output() {
  if [ -n "$NODE_BIN" ]; then
    "$NODE_BIN" "$(native_path "$SCRIPT_DIR/stream-filter.js")"
  else
    cat
  fi
}

build_prompt() {
  local constraints=$CONSTRAINTS
  [ "$OPT_READ_ONLY" = 1 ] && constraints=$READ_ONLY_CONSTRAINTS
  printf '%s\n\n%s' "$1" "$constraints"
}

cursor_args() {
  local format=text
  [ -n "$NODE_BIN" ] && format=stream-json
  printf '%s\0' -p "$1" --output-format "$format" --trust --workspace "$(native_path "$PWD")" --force --model "${OPT_MODEL:-auto}"
  [ "$OPT_READ_ONLY" = 1 ] && printf '%s\0' --mode ask
  [ "$OPT_CONTINUE" = 1 ] && printf '%s\0' --continue
  return 0
}

report_exit() {
  case $1 in
    124 | 137 | 142) echo "[cursor-rescue] timed out after ${CURSOR_RESCUE_TIMEOUT:-540}s — edits made until then are in the working tree" ;;
  esac
  echo "[cursor-rescue] exit $1"
}

read_task() {
  local task
  task=$(cat)
  [ -n "${task//[[:space:]]/}" ] || usage_error "no task on stdin"
  printf '%s' "$task"
}

# The task travels as one argv entry; Windows caps a whole command line at 32767 characters.
check_task_length() {
  local length=${#1}
  [ "$length" -le "$MAX_TASK_CHARS" ] && return 0
  printf '[cursor-rescue] task is %s characters, over the %s limit — reference files by path instead of pasting them, or split the task\n' "$length" "$MAX_TASK_CHARS"
  return "$USAGE_EXIT"
}

run_task() {
  local task launcher=() limiter=() args=() item before rc
  task=$(read_task) || return
  check_task_length "$task" || return
  require_launcher || return
  require_deny_rules || return
  while IFS= read -r -d '' item; do launcher+=("$item"); done < <(launcher_argv)
  while IFS= read -r -d '' item; do limiter+=("$item"); done < <(timeout_argv)
  while IFS= read -r -d '' item; do args+=("$item"); done < <(cursor_args "$(build_prompt "$task")")
  export GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" NO_OPEN_BROWSER=1
  before=$(git_state) || before=""
  ( cursor_env; "${limiter[@]}" "${launcher[@]}" "${args[@]}" </dev/null 2>&1 ) | filter_output
  rc=${PIPESTATUS[0]}
  warn_git_changes "$before"
  report_exit "$rc"
  return "$rc"
}

git_paths() {
  git rev-parse --path-format=absolute --git-dir --git-common-dir --git-path hooks 2>/dev/null
}

files_fingerprint() {
  local files=("$@") existing=() file
  for file in "${files[@]}"; do
    [ -f "$file" ] && existing+=("$file")
  done
  [ ${#existing[@]} -gt 0 ] || { printf 'none'; return 0; }
  cksum "${existing[@]}" | cksum
}

hooks_fingerprint() {
  local hooks=("$1"/*)
  files_fingerprint "${hooks[@]}"
}

stash_count() {
  git rev-list --walk-reflogs --count refs/stash -- 2>/dev/null || printf '0'
}

# Read-only: no command here touches the index, runs hooks or starts a pager.
git_state() {
  local git_dir common hooks
  { IFS= read -r git_dir && IFS= read -r common && IFS= read -r hooks; } < <(git_paths) || return 1
  printf 'HEAD\t%s\n' "$(git rev-parse -q --verify HEAD || printf 'none')"
  printf 'branch\t%s\n' "$(git symbolic-ref -q --short HEAD || printf 'detached')"
  printf 'stash\t%s\n' "$(stash_count)"
  printf 'config\t%s\n' "$(files_fingerprint "$common/config" "$git_dir/config.worktree")"
  printf 'hooks\t%s\n' "$(hooks_fingerprint "$hooks")"
}

state_field() {
  local key=$1 line
  while IFS= read -r line; do
    [ "${line%%$'\t'*}" = "$key" ] && { printf '%s' "${line#*$'\t'}"; return 0; }
  done <<<"$2"
  return 1
}

describe_git_change() {
  local key=$1 before=$2 after=$3
  case $key in
    HEAD) printf 'HEAD moved from %s to %s' "${before:0:12}" "${after:0:12}" ;;
    branch) printf 'branch changed from %s to %s' "$before" "$after" ;;
    stash) printf 'stash list changed from %s to %s entries' "$before" "$after" ;;
    config) printf 'git config changed (.git/config)' ;;
    hooks) printf 'git hooks changed (.git/hooks or core.hooksPath)' ;;
  esac
}

git_warning() {
  printf '[cursor-rescue] WARNING: %s — review before your next git command\n' "$1"
}

# Reports what the delegate changed in git metadata; never reverts it.
warn_git_changes() {
  local before=$1 after key old new
  [ -n "$before" ] || return 0
  after=$(git_state) || { git_warning "the git repository is no longer readable"; return 0; }
  while IFS=$'\t' read -r key old; do
    new=$(state_field "$key" "$after")
    [ "$old" = "$new" ] || git_warning "$(describe_git_change "$key" "$old" "$new")"
  done <<<"$before"
}

main() {
  local command=${1:-}
  [ $# -gt 0 ] && shift
  case $command in
    preflight) parse_options "$@"; preflight ;;
    run) parse_options "$@"; run_task ;;
    models) list_models ;;
    *) usage_error "usage: cursor-forward.sh preflight|run|models [options]" ;;
  esac
}

main "$@"
