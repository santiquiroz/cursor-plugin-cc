#!/usr/bin/env bash
set -u

require_value=""
case "${1:-}" in
  *stream-filter.js) exec node "$@" ;;
esac
if [ "${1:-}" = --require ]; then
  require_value=${2:-}
  shift 2
fi
case "${1:-}" in
  *index.js) shift ;;
esac

if [ -n "${FAKE_CURSOR_CALLS:-}" ]; then
  mkdir -p "$FAKE_CURSOR_CALLS"
  call_number=1
  while [ -e "$FAKE_CURSOR_CALLS/$call_number.args" ]; do
    call_number=$((call_number + 1))
  done
  printf '%s\0' "$@" >"$FAKE_CURSOR_CALLS/$call_number.args"
  if [ -n "$require_value" ]; then
    printf '%s' "$require_value" >"$FAKE_CURSOR_CALLS/$call_number.require"
  fi
  {
    printf 'CURSOR_CONFIG_DIR=%s\n' "${CURSOR_CONFIG_DIR-}"
    printf 'MSYS_NO_PATHCONV=%s\n' "${MSYS_NO_PATHCONV-}"
    printf 'MSYS2_ARG_CONV_EXCL=%s\n' "${MSYS2_ARG_CONV_EXCL-}"
    printf 'GIT_TERMINAL_PROMPT=%s\n' "${GIT_TERMINAL_PROMPT-}"
    printf 'GIT_SSH_COMMAND=%s\n' "${GIT_SSH_COMMAND-}"
    printf 'NO_OPEN_BROWSER=%s\n' "${NO_OPEN_BROWSER-}"
    printf 'CURSOR_RESCUE_FAKE_HOME=%s\n' "${CURSOR_RESCUE_FAKE_HOME-}"
  } >"$FAKE_CURSOR_CALLS/$call_number.env"
fi

if [ "${1:-}" = about ]; then
  cat "${FAKE_CURSOR_ABOUT:?}"
  exit 0
fi

case "${FAKE_CURSOR_MODE:-ok}" in
  named-model)
    printf '%s\n' 'ActionRequiredError: Named models unavailable Free plans can only use Auto.' >&2
    exit 1
    ;;
  sleep)
    sleep 30
    exit 0
    ;;
  stdin)
    if IFS= read -r -t 1 line; then
      printf '%s\n' 'STDIN OPEN'
    else
      printf '%s\n' 'STDIN CLOSED'
    fi
    exit 0
    ;;
  commit)
    git commit --allow-empty -q -m fake || exit $?
    ;;
esac

printf '%s\n' \
  '{"type":"system","subtype":"init","session_id":"s1"}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"Working on it."}]}}' \
  '{"type":"tool_call","subtype":"started","tool_call":{"shellToolCall":{"args":{"command":"git status --short"}}}}' \
  '{"type":"tool_call","subtype":"completed","tool_call":{"editToolCall":{"result":{"rejected":{"reason":"Hook blocked with message: boom\nsecond line"}}}}}' \
  '{"type":"tool_call","subtype":"started","tool_call":null}' \
  'Connection lost, reconnecting'
printf '%s\n' 'plain stderr line' >&2
printf '%s\n' \
  '{"type":"result","subtype":"success","is_error":false,"duration_ms":2000,"session_id":"s1","result":"Working on it."}'
exit 0
