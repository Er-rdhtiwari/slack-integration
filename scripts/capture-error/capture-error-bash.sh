#!/usr/bin/env bash

# scripts/capture-error/capture-error-bash.sh
# No-Python Bash fallback for capture-error.sh when python3 is unavailable.

set -uo pipefail
set -m

STRICT_LOG_ERRORS=true
TIMEOUT_SECONDS=3600
MAX_OUTPUT_BYTES="${CAPTURE_ERROR_MAX_OUTPUT_BYTES:-65536}"
MAX_CAPTURE_BYTES="${CAPTURE_ERROR_MAX_CAPTURE_BYTES:-10485760}"
REDACTION_REGEX_FILE="${CAPTURE_ERROR_REDACTION_REGEX_FILE:-}"

json_string() {
  local value="$1"
  local escaped=""
  local i
  local char

  for ((i = 0; i < ${#value}; i++)); do
    char="${value:i:1}"
    case "$char" in
      '"')
        escaped="${escaped}\\\""
        ;;
      "\\")
        escaped="${escaped}\\\\"
        ;;
      $'\b')
        escaped="${escaped}\\b"
        ;;
      $'\f')
        escaped="${escaped}\\f"
        ;;
      $'\n')
        escaped="${escaped}\\n"
        ;;
      $'\r')
        escaped="${escaped}\\r"
        ;;
      $'\t')
        escaped="${escaped}\\t"
        ;;
      *)
        escaped="${escaped}${char}"
        ;;
    esac
  done

  printf '"%s"' "$escaped"
}

show_help() {
  cat <<'EOF'
Usage:
  ./scripts/capture-error/capture-error-bash.sh [wrapper-options] -- <command> [args...]
  ./scripts/capture-error/capture-error-bash.sh <command> [args...]

Wrapper options:
  --strict-log-errors      Mark result as failed if error-like logs are detected. Default.
  --exit-code-only         Mark failed only when command exits non-zero.
  --timeout SECONDS        Stop the command after this many seconds. Default: 3600.
  --max-output-bytes BYTES Maximum bytes returned per stream in JSON. Default: 65536.
  --max-capture-bytes BYTES Maximum combined temp log bytes before terminating. Default: 10485760.
  --redaction-regex-file PATH
                            File with extra sed extended regex patterns to redact, one per line.
  -h, --help               Show help.
EOF
}

redact_text() {
  local text="$1"
  local pattern

  text="$(printf '%s' "$text" | sed -E \
    -e 's#https://hooks\.slack\.com/services/[A-Za-z0-9_/-]+#[REDACTED_SLACK_WEBHOOK]#g' \
    -e 's#([Aa]uthorization[[:space:]]*:[[:space:]]*[Bb]earer[[:space:]]+)[A-Za-z0-9._~+/-]+=*#\1[REDACTED]#g' \
    -e 's#((slack_)?webhook(_url)?|token|access_token|refresh_token|api_key|apikey|secret|password|passwd|pwd)([[:space:]]*[:=][[:space:]]*)[^[:space:],'\''"]+#\1\4[REDACTED]#Ig')"

  if [ -n "$REDACTION_REGEX_FILE" ] && [ -r "$REDACTION_REGEX_FILE" ]; then
    while IFS= read -r pattern || [ -n "$pattern" ]; do
      case "$pattern" in
        ""|\#*)
          continue
          ;;
      esac

      text="$(printf '%s' "$text" | sed -E "s#${pattern}#[REDACTED]#g")"
    done < "$REDACTION_REGEX_FILE"
  fi

  printf '%s' "$text"
}

read_limited_text() {
  local file="$1"
  local max_bytes="$2"

  if [ ! -f "$file" ]; then
    return 0
  fi

  dd if="$file" bs=1 count="$max_bytes" 2>/dev/null || true
}

file_size() {
  local file="$1"

  if [ ! -f "$file" ]; then
    printf '0'
    return
  fi

  wc -c < "$file" 2>/dev/null | tr -d '[:space:]'
}

count_lines() {
  local text="$1"

  if [ -z "$text" ]; then
    printf '0'
    return
  fi

  printf '%s' "$text" | awk 'END { print NR }'
}

detect_error_lines() {
  local text="$1"

  if [ -z "$text" ]; then
    printf '0'
    return
  fi

  printf '%s\n' "$text" | grep -Eic '^[[:space:]]*(\[[^]]+\][[:space:]]*)?(error|err|failed|failure|fatal|panic|exception)([[:space:]]*[:=-]|[[:space:]]+|$)|traceback \(most recent call last\)|unhandled(promise)?rejection|panic:|fatal:' || true
}

detect_warning_lines() {
  local text="$1"

  if [ -z "$text" ]; then
    printf '0'
    return
  fi

  printf '%s\n' "$text" | grep -Eic '^[[:space:]]*(\[[^]]+\][[:space:]]*)?(warn|warning|deprecationwarning)([[:space:]]*[:=-]|[[:space:]]+|$)' || true
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --strict-log-errors)
      STRICT_LOG_ERRORS=true
      shift
      ;;
    --exit-code-only)
      STRICT_LOG_ERRORS=false
      shift
      ;;
    --timeout)
      if [ "$#" -lt 2 ] || ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: --timeout requires a positive integer number of seconds." >&2
        exit 64
      fi
      TIMEOUT_SECONDS="$2"
      shift 2
      ;;
    --max-output-bytes)
      if [ "$#" -lt 2 ] || ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: --max-output-bytes requires a positive integer number of bytes." >&2
        exit 64
      fi
      MAX_OUTPUT_BYTES="$2"
      shift 2
      ;;
    --max-capture-bytes)
      if [ "$#" -lt 2 ] || ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: --max-capture-bytes requires a positive integer number of bytes." >&2
        exit 64
      fi
      MAX_CAPTURE_BYTES="$2"
      shift 2
      ;;
    --redaction-regex-file)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then
        echo "Error: --redaction-regex-file requires a file path." >&2
        exit 64
      fi
      REDACTION_REGEX_FILE="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

if [ "$#" -eq 0 ]; then
  printf '{\n'
  printf '  "success": false,\n'
  printf '  "status": "failed",\n'
  printf '  "exit_code": 64,\n'
  printf '  "wrapper_exit_code": 64,\n'
  printf '  "failure_reason": "missing_command",\n'
  printf '  "fallback_mode": "bash",\n'
  printf '  "error_message": "No command provided."\n'
  printf '}\n'
  exit 64
fi

command=("$@")

if ! tmpdir="$(mktemp -d 2>/dev/null)" || [ -z "${tmpdir:-}" ] || [ ! -d "$tmpdir" ]; then
  printf '{"success": false, "status": "failed", "exit_code": 70, "wrapper_exit_code": 70, "failure_reason": "temp_directory_creation_failed", "fallback_mode": "bash"}\n'
  exit 70
fi

stdout_file="$tmpdir/stdout.log"
stderr_file="$tmpdir/stderr.log"
timeout_file="$tmpdir/timed-out"
capture_limit_file="$tmpdir/capture-limit-exceeded"

trap 'rm -rf "$tmpdir"' EXIT

: > "$stdout_file"
: > "$stderr_file"

start_time="$(date +"%Y-%m-%dT%H:%M:%S%z")"
start_seconds="$(date +%s)"

(
  "${command[@]}" > "$stdout_file" 2> "$stderr_file"
) &
target_pid=$!

(
  sleep "$TIMEOUT_SECONDS"
  if kill -0 "$target_pid" >/dev/null 2>&1; then
    : > "$timeout_file"
    printf 'Command timed out after %s seconds.\n' "$TIMEOUT_SECONDS" >> "$stderr_file"
    kill -TERM "-$target_pid" >/dev/null 2>&1 || kill -TERM "$target_pid" >/dev/null 2>&1 || true
    sleep 2
    kill -KILL "-$target_pid" >/dev/null 2>&1 || kill -KILL "$target_pid" >/dev/null 2>&1 || true
  fi
) &
timeout_watcher_pid=$!

(
  while kill -0 "$target_pid" >/dev/null 2>&1; do
    stdout_size="$(file_size "$stdout_file")"
    stderr_size="$(file_size "$stderr_file")"

    if [ $((stdout_size + stderr_size)) -gt "$MAX_CAPTURE_BYTES" ]; then
      : > "$capture_limit_file"
      printf 'Command exceeded max capture size of %s bytes.\n' "$MAX_CAPTURE_BYTES" >> "$stderr_file"
      kill -TERM "-$target_pid" >/dev/null 2>&1 || kill -TERM "$target_pid" >/dev/null 2>&1 || true
      sleep 2
      kill -KILL "-$target_pid" >/dev/null 2>&1 || kill -KILL "$target_pid" >/dev/null 2>&1 || true
      break
    fi

    sleep 1
  done
) &
capture_watcher_pid=$!

wait "$target_pid"
target_exit_code=$?

kill "$timeout_watcher_pid" >/dev/null 2>&1 || true
wait "$timeout_watcher_pid" 2>/dev/null || true
kill "$capture_watcher_pid" >/dev/null 2>&1 || true
wait "$capture_watcher_pid" 2>/dev/null || true

end_time="$(date +"%Y-%m-%dT%H:%M:%S%z")"
end_seconds="$(date +%s)"
duration_ms=$(((end_seconds - start_seconds) * 1000))

timed_out=false
capture_limit_exceeded=false

if [ -f "$timeout_file" ]; then
  timed_out=true
fi

if [ -f "$capture_limit_file" ]; then
  capture_limit_exceeded=true
fi

stdout_raw_bytes="$(file_size "$stdout_file")"
stderr_raw_bytes="$(file_size "$stderr_file")"
stdout_truncated=false
stderr_truncated=false
output_truncated=false

if [ "$stdout_raw_bytes" -gt "$MAX_OUTPUT_BYTES" ]; then
  stdout_truncated=true
fi

if [ "$stderr_raw_bytes" -gt "$MAX_OUTPUT_BYTES" ]; then
  stderr_truncated=true
fi

if [ "$stdout_truncated" = true ] || [ "$stderr_truncated" = true ]; then
  output_truncated=true
fi

stdout_text="$(read_limited_text "$stdout_file" "$MAX_OUTPUT_BYTES")"
stderr_text="$(read_limited_text "$stderr_file" "$MAX_OUTPUT_BYTES")"
stdout_text="$(redact_text "$stdout_text")"
stderr_text="$(redact_text "$stderr_text")"

stdout_lines="$(count_lines "$stdout_text")"
stderr_lines="$(count_lines "$stderr_text")"
error_lines=$(( $(detect_error_lines "$stdout_text") + $(detect_error_lines "$stderr_text") ))
warning_lines=$(( $(detect_warning_lines "$stdout_text") + $(detect_warning_lines "$stderr_text") ))
detected_log_error=false

if [ "$error_lines" -gt 0 ]; then
  detected_log_error=true
fi

process_success=false
if [ "$target_exit_code" -eq 0 ] && [ "$timed_out" = false ] && [ "$capture_limit_exceeded" = false ]; then
  process_success=true
fi

success=false
failure_reason=null
wrapper_exit_code=1
error_message=null

if [ "$process_success" = true ] && { [ "$STRICT_LOG_ERRORS" = false ] || [ "$detected_log_error" = false ]; }; then
  success=true
  status=success
  wrapper_exit_code=0
elif [ "$timed_out" = true ]; then
  status=failed
  failure_reason=timeout
  wrapper_exit_code=124
  error_message="Command timed out after $TIMEOUT_SECONDS seconds."
elif [ "$capture_limit_exceeded" = true ]; then
  status=failed
  failure_reason=capture_limit_exceeded
  wrapper_exit_code=125
  error_message="Command exceeded max capture size of $MAX_CAPTURE_BYTES bytes."
elif [ "$target_exit_code" -ne 0 ]; then
  status=failed
  failure_reason=non_zero_exit_code
  wrapper_exit_code="$target_exit_code"
  error_message="Command failed with exit code $target_exit_code."
elif [ "$STRICT_LOG_ERRORS" = true ] && [ "$detected_log_error" = true ]; then
  status=failed
  failure_reason=error_log_detected
  wrapper_exit_code=1
  error_message="Command exited with code 0, but error logs were detected."
else
  status=failed
  failure_reason=unknown
  wrapper_exit_code=1
  error_message="Command failed."
fi

printf '{\n'
printf '  "success": %s,\n' "$success"
printf '  "status": '
json_string "$status"
printf ',\n'
printf '  "exit_code": %s,\n' "$target_exit_code"
printf '  "wrapper_exit_code": %s,\n' "$wrapper_exit_code"
printf '  "failure_reason": '
if [ "$failure_reason" = null ]; then
  printf 'null'
else
  json_string "$failure_reason"
fi
printf ',\n'
printf '  "fallback_mode": "bash",\n'
printf '  "strict_log_errors": %s,\n' "$STRICT_LOG_ERRORS"
printf '  "detected_log_error": %s,\n' "$detected_log_error"
printf '  "timed_out": %s,\n' "$timed_out"
printf '  "capture_limit_exceeded": %s,\n' "$capture_limit_exceeded"
printf '  "timeout_seconds": %s,\n' "$TIMEOUT_SECONDS"
printf '  "max_output_bytes": %s,\n' "$MAX_OUTPUT_BYTES"
printf '  "max_capture_bytes": %s,\n' "$MAX_CAPTURE_BYTES"
printf '  "error_message": '
if [ "$error_message" = null ]; then
  printf 'null'
else
  json_string "$error_message"
fi
printf ',\n'
printf '  "timing": {\n'
printf '    "started_at": '
json_string "$start_time"
printf ',\n'
printf '    "finished_at": '
json_string "$end_time"
printf ',\n'
printf '    "duration_ms": %s\n' "$duration_ms"
printf '  },\n'
printf '  "summary": {\n'
printf '    "total_log_lines": %s,\n' "$((stdout_lines + stderr_lines))"
printf '    "stdout_lines": %s,\n' "$stdout_lines"
printf '    "stderr_lines": %s,\n' "$stderr_lines"
printf '    "error_lines": %s,\n' "$error_lines"
printf '    "warning_lines": %s,\n' "$warning_lines"
printf '    "stdout_raw_bytes": %s,\n' "$stdout_raw_bytes"
printf '    "stderr_raw_bytes": %s,\n' "$stderr_raw_bytes"
printf '    "stdout_truncated": %s,\n' "$stdout_truncated"
printf '    "stderr_truncated": %s,\n' "$stderr_truncated"
printf '    "output_truncated": %s\n' "$output_truncated"
printf '  },\n'
printf '  "output": {\n'
printf '    "stdout": '
json_string "$stdout_text"
printf ',\n'
printf '    "stderr": '
json_string "$stderr_text"
printf '\n'
printf '  }\n'
printf '}\n'

exit "$wrapper_exit_code"
