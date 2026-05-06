#!/usr/bin/env bash

# scripts/capture-error/capture-error.sh
# Public entrypoint. Delegates all runtime selection to runner.sh.

set -uo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"

case "$SCRIPT_PATH" in
  */*)
    SCRIPT_DIR="${SCRIPT_PATH%/*}"
    ;;
  *)
    SCRIPT_DIR="."
    ;;
esac

RUNNER="$SCRIPT_DIR/runner.sh"

json_string() {
  local value="$1"
  local escaped=""
  local i
  local char

  for ((i = 0; i < ${#value}; i++)); do
    char="${value:i:1}"
    case "$char" in
      '"') escaped="${escaped}\\\"" ;;
      "\\") escaped="${escaped}\\\\" ;;
      $'\b') escaped="${escaped}\\b" ;;
      $'\f') escaped="${escaped}\\f" ;;
      $'\n') escaped="${escaped}\\n" ;;
      $'\r') escaped="${escaped}\\r" ;;
      $'\t') escaped="${escaped}\\t" ;;
      *) escaped="${escaped}${char}" ;;
    esac
  done

  printf '"%s"' "$escaped"
}

emit_wrapper_error() {
  local failure_reason="$1"
  local error_message="$2"

  printf '{"success":false,"status":"failed","exit_code":70,"wrapper_exit_code":70,"failure_reason":'
  json_string "$failure_reason"
  printf ',"error_message":'
  json_string "$error_message"
  printf '}\n'
}

if [ ! -x "$RUNNER" ]; then
  emit_wrapper_error "capture_error_runner_missing" "Capture-error runner is missing or not executable: $RUNNER"
  exit 70
fi

exec "$RUNNER" "$@"
