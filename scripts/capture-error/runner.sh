#!/usr/bin/env bash

# scripts/capture-error/runner.sh
# Runs capture-error from a prebuilt binary, or from Go source during development.

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

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BIN_PATH="${CAPTURE_ERROR_BIN:-$REPO_ROOT/bin/capture-error}"

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

if [ -x "$BIN_PATH" ]; then
  exec "$BIN_PATH" "$@"
fi

if ! command -v go >/dev/null 2>&1; then
  emit_wrapper_error "capture_error_runtime_unavailable" "Go runtime is unavailable and no executable was found at $BIN_PATH"
  exit 70
fi

cd "$REPO_ROOT" || exit 70

TMP_DIR="$(mktemp -d 2>/dev/null)"
if [ -z "${TMP_DIR:-}" ] || [ ! -d "$TMP_DIR" ]; then
  emit_wrapper_error "capture_error_build_workspace_unavailable" "Could not create a temporary build directory."
  exit 70
fi

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

TMP_BIN="$TMP_DIR/capture-error"
BUILD_LOG="$TMP_DIR/build.log"

if ! go build -o "$TMP_BIN" ./cmd/capture-error > "$BUILD_LOG" 2>&1; then
  build_output="$(cat "$BUILD_LOG" 2>/dev/null || true)"
  emit_wrapper_error "capture_error_build_failed" "Could not build capture-error from ./cmd/capture-error. $build_output"
  exit 70
fi

"$TMP_BIN" "$@"
exit "$?"
