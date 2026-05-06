#!/usr/bin/env bash

# scripts/capture-error/capture-error.sh
# Executes a command/script, captures stdout/stderr, detects errors,
# parses JSON logs such as zerolog, and returns a clean JSON result.

set -uo pipefail
set -m

STRICT_LOG_ERRORS=true
STREAM_OUTPUT=true
INCLUDE_STDOUT=false
INCLUDE_STDERR=true
TIMEOUT_SECONDS=3600
MAX_OUTPUT_BYTES="${CAPTURE_ERROR_MAX_OUTPUT_BYTES:-65536}"
MAX_CAPTURE_BYTES="${CAPTURE_ERROR_MAX_CAPTURE_BYTES:-10485760}"
REDACTION_REGEX_FILE="${CAPTURE_ERROR_REDACTION_REGEX_FILE:-}"
SCRIPT_PATH="${BASH_SOURCE[0]}"
ORIGINAL_ARGS=("$@")

case "$SCRIPT_PATH" in
  */*)
    SCRIPT_DIR="${SCRIPT_PATH%/*}"
    ;;
  *)
    SCRIPT_DIR="."
    ;;
esac

DEPS_CHECK_SCRIPT="$SCRIPT_DIR/check-deps.sh"
FALLBACK_SCRIPT="$SCRIPT_DIR/capture-error-bash.sh"

python_runtime_ok() {
  command -v python3 >/dev/null 2>&1 && python3 - <<'PY' >/dev/null 2>&1
import json
import pathlib
import re
import shlex
import sys
import time
PY
}

json_escape_string() {
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

parse_bool_option() {
  local option_name="$1"
  local option_value="$2"

  case "$option_value" in
    true|false)
      printf '%s' "$option_value"
      ;;
    *)
      echo "Error: $option_name requires true or false." >&2
      exit 64
      ;;
  esac
}

emit_wrapper_error() {
  local exit_code="$1"
  local failure_reason="$2"
  local error_message="$3"

  printf '{\n'
  printf '  "success": false,\n'
  printf '  "status": "failed",\n'
  printf '  "exit_code": %s,\n' "$exit_code"
  printf '  "wrapper_exit_code": %s,\n' "$exit_code"
  printf '  "failure_reason": '
  json_escape_string "$failure_reason"
  printf ',\n'
  printf '  "error_message": '
  json_escape_string "$error_message"
  printf '\n}\n'
}

run_dependency_check() {
  local deps_result
  local deps_status

  if [ "${CAPTURE_ERROR_SKIP_DEPS_CHECK:-false}" = "true" ]; then
    return 0
  fi

  if [ ! -x "$DEPS_CHECK_SCRIPT" ]; then
    emit_wrapper_error 70 "dependency_checker_missing" "Dependency checker is missing or not executable: $DEPS_CHECK_SCRIPT"
    exit 70
  fi

  deps_result="$("$DEPS_CHECK_SCRIPT")"
  deps_status=$?

  if [ "$deps_status" -ne 0 ]; then
    printf '%s\n' "$deps_result"
    exit 70
  fi
}

show_help() {
  cat <<'EOF'
Usage:
  ./scripts/capture-error/capture-error.sh [wrapper-options] -- <command> [args...]
  ./scripts/capture-error/capture-error.sh <command> [args...]

Wrapper options:
  --strict-log-errors      Mark result as failed if error-like logs are detected. Default.
  --exit-code-only         Mark failed only when command exits non-zero.
  --stream-output          Mirror raw command stdout/stderr live to stderr, then print final JSON to stdout. Default.
  --no-stream-output       Capture command output silently, then print only final JSON.
  --stdout true|false      Include captured stdout text in final JSON output. Default: false.
  --stderr true|false      Include captured stderr text in final JSON output. Default: true.
  --timeout SECONDS        Stop the command after this many seconds. Default: 3600.
  --max-output-bytes BYTES  Maximum bytes returned per stream in JSON. Default: 65536.
  --max-capture-bytes BYTES Maximum combined temp log bytes before terminating. Default: 10485760.
  --redaction-regex-file PATH
                            File with extra Python regex patterns to redact, one per line.
  -h, --help               Show help.

Examples:
  ./scripts/capture-error/capture-error.sh ls -la scripts

  ./scripts/capture-error/capture-error.sh --strict-log-errors -- sh -c 'printf "%s\n" "Error: demo failure"'

  ./scripts/capture-error/capture-error.sh --exit-code-only -- sh -c 'printf "%s\n" "Error: ignored log"; exit 0'
EOF
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
    --stream-output)
      STREAM_OUTPUT=true
      shift
      ;;
    --no-stream-output)
      STREAM_OUTPUT=false
      shift
      ;;
    --stdout)
      if [ "$#" -lt 2 ]; then
        echo "Error: --stdout requires true or false." >&2
        exit 64
      fi

      parse_bool_option --stdout "$2" >/dev/null
      INCLUDE_STDOUT="$2"
      shift 2
      ;;
    --stderr)
      if [ "$#" -lt 2 ]; then
        echo "Error: --stderr requires true or false." >&2
        exit 64
      fi

      parse_bool_option --stderr "$2" >/dev/null
      INCLUDE_STDERR="$2"
      shift 2
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

if ! python_runtime_ok; then
  if [ -x "$FALLBACK_SCRIPT" ]; then
    exec "$FALLBACK_SCRIPT" "${ORIGINAL_ARGS[@]}"
  fi

  emit_wrapper_error 70 "python_runtime_unavailable" "python3 or required Python standard-library modules are unavailable, and fallback script is missing or not executable: $FALLBACK_SCRIPT"
  exit 70
fi

run_dependency_check

if [ "$#" -eq 0 ]; then
  python3 - "$INCLUDE_STDOUT" "$INCLUDE_STDERR" <<'PY'
import json
import sys

include_stdout = sys.argv[1].lower() == "true"
include_stderr = sys.argv[2].lower() == "true"

result = {
    "success": False,
    "status": "failed",
    "exit_code": 64,
    "wrapper_exit_code": 64,
    "failure_reason": "missing_command",
    "success_message": None,
    "error_message": "No command provided. Usage: ./scripts/capture-error.sh <command> [args...]",
    "command": {
        "display": "",
        "args": []
    },
    "summary": {
        "total_log_lines": 0,
        "stdout_lines": 0,
        "stderr_lines": 0,
        "error_lines": 0,
        "warning_lines": 0
    },
    "logs": [],
    "output": {}
}

if include_stdout:
    result["output"]["stdout"] = ""
if include_stderr:
    result["output"]["stderr"] = ""

print(json.dumps(result, indent=2))
PY
  exit 64
fi

command=("$@")

if ! tmpdir="$(mktemp -d 2>/dev/null)" || [ -z "${tmpdir:-}" ] || [ ! -d "$tmpdir" ]; then
  emit_wrapper_error 70 "temp_directory_creation_failed" "Could not create a temporary directory."
  exit 70
fi

stdout_file="$tmpdir/stdout.log"
stderr_file="$tmpdir/stderr.log"
stdout_pipe="$tmpdir/stdout.pipe"
stderr_pipe="$tmpdir/stderr.pipe"
timeout_file="$tmpdir/timed-out"
capture_limit_file="$tmpdir/capture-limit-exceeded"

trap 'rm -rf "$tmpdir"' EXIT

if ! : > "$stdout_file" || ! : > "$stderr_file"; then
  emit_wrapper_error 70 "temp_file_creation_failed" "Could not create temporary output files in $tmpdir."
  exit 70
fi

foreground_job_number_for_pid() {
  local pid="$1"

  jobs -l | awk -v pid="$pid" '$2 == pid {gsub(/[^0-9]/, "", $1); print $1; exit}'
}

start_time="$(date +"%Y-%m-%dT%H:%M:%S%z")"
start_ms="$(python3 -c 'import time; print(int(time.time() * 1000))')"
timed_out=false

if [ "$STREAM_OUTPUT" = true ]; then
  if ! mkfifo "$stdout_pipe" "$stderr_pipe"; then
    emit_wrapper_error 70 "stream_pipe_creation_failed" "Could not create stream output pipes in $tmpdir."
    exit 70
  fi

  tee -a "$stdout_file" < "$stdout_pipe" >&2 &
  stdout_tee_pid=$!
  tee -a "$stderr_file" < "$stderr_pipe" >&2 &
  stderr_tee_pid=$!

  (
    "${command[@]}" > "$stdout_pipe" 2> "$stderr_pipe"
  ) &
else
  (
    "${command[@]}" > "$stdout_file" 2> "$stderr_file"
  ) &
fi
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
    stdout_size="$(wc -c < "$stdout_file" 2>/dev/null || printf '0')"
    stderr_size="$(wc -c < "$stderr_file" 2>/dev/null || printf '0')"
    stdout_size="${stdout_size//[[:space:]]/}"
    stderr_size="${stderr_size//[[:space:]]/}"

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

if [ -t 0 ]; then
  target_job_number="$(foreground_job_number_for_pid "$target_pid")"

  if [ -n "$target_job_number" ]; then
    fg "%$target_job_number" >/dev/null
    target_exit_code=$?

    if [ "$target_exit_code" -ne 0 ]; then
      wait "$target_pid" 2>/dev/null
      target_exit_code=$?
    fi
  else
    wait "$target_pid"
    target_exit_code=$?
  fi
else
  wait "$target_pid"
  target_exit_code=$?
fi

if [ "$STREAM_OUTPUT" = true ]; then
  wait "$stdout_tee_pid" 2>/dev/null || true
  wait "$stderr_tee_pid" 2>/dev/null || true
fi

if [ -f "$timeout_file" ]; then
  timed_out=true
else
  kill "$timeout_watcher_pid" >/dev/null 2>&1 || true
  wait "$timeout_watcher_pid" 2>/dev/null || true
fi

if [ -f "$capture_limit_file" ]; then
  capture_limit_exceeded=true
else
  capture_limit_exceeded=false
fi

kill "$capture_watcher_pid" >/dev/null 2>&1 || true
wait "$capture_watcher_pid" 2>/dev/null || true

end_time="$(date +"%Y-%m-%dT%H:%M:%S%z")"
end_ms="$(python3 -c 'import time; print(int(time.time() * 1000))')"
duration_ms=$((end_ms - start_ms))

python3 - \
  "$target_exit_code" \
  "$STRICT_LOG_ERRORS" \
	  "$timed_out" \
  "$capture_limit_exceeded" \
	  "$TIMEOUT_SECONDS" \
  "$MAX_OUTPUT_BYTES" \
  "$MAX_CAPTURE_BYTES" \
  "$REDACTION_REGEX_FILE" \
  "$INCLUDE_STDOUT" \
  "$INCLUDE_STDERR" \
	  "$start_time" \
	  "$end_time" \
  "$duration_ms" \
  "$stdout_file" \
  "$stderr_file" \
  "${command[@]}" <<'PY'

import json
import re
import shlex
import sys
from pathlib import Path

target_exit_code = int(sys.argv[1])
strict_log_errors = sys.argv[2].lower() == "true"
timed_out = sys.argv[3].lower() == "true"
capture_limit_exceeded = sys.argv[4].lower() == "true"
timeout_seconds = int(sys.argv[5])
max_output_bytes = int(sys.argv[6])
max_capture_bytes = int(sys.argv[7])
redaction_regex_file = sys.argv[8]
include_stdout = sys.argv[9].lower() == "true"
include_stderr = sys.argv[10].lower() == "true"
start_time = sys.argv[11]
end_time = sys.argv[12]
duration_ms = int(sys.argv[13])

stdout_path = Path(sys.argv[14])
stderr_path = Path(sys.argv[15])

command = sys.argv[16:]

def read_limited_text(path, max_bytes):
    if not path.exists():
        return "", 0, False

    raw_size = path.stat().st_size
    with path.open("rb") as handle:
        data = handle.read(max_bytes + 1)

    truncated = len(data) > max_bytes or raw_size > max_bytes
    if truncated:
        data = data[:max_bytes]

    return data.decode(errors="replace"), raw_size, truncated

stdout_text, stdout_raw_bytes, stdout_truncated = read_limited_text(stdout_path, max_output_bytes)
stderr_text, stderr_raw_bytes, stderr_truncated = read_limited_text(stderr_path, max_output_bytes)

ERROR_PREFIX_PATTERN = re.compile(
    r"^\s*(?:\[[^\]]+\]\s*)?(?:error|err|failed|failure|fatal|panic|exception)\b(?:\s*[:=-]|\s+|$)",
    re.IGNORECASE,
)

ERROR_LEVEL_PATTERN = re.compile(
    r"^\s*(?:level|severity|log_level)\s*[:=]\s*['\"]?(?:error|err|fatal|panic)['\"]?\b",
    re.IGNORECASE,
)

STDERR_ERROR_PATTERN = re.compile(
    r"\b(command not found|no such file or directory|permission denied|not found|cannot|can't|invalid)\b",
    re.IGNORECASE,
)

WARNING_PREFIX_PATTERN = re.compile(
    r"^\s*(?:\[[^\]]+\]\s*)?(?:warn|warning|deprecationwarning)\b(?:\s*[:=-]|\s+|$)",
    re.IGNORECASE,
)

WARNING_LEVEL_PATTERN = re.compile(
    r"^\s*(?:level|severity|log_level)\s*[:=]\s*['\"]?(?:warn|warning)['\"]?\b",
    re.IGNORECASE,
)

TRACEBACK_PATTERN = re.compile(
    r"^\s*(?:traceback \(most recent call last\)|unhandled(?:promise)?rejection|panic:|fatal:)",
    re.IGNORECASE,
)

SECRET_REPLACEMENTS = [
    (
        re.compile(r"https://hooks\.slack\.com/services/[A-Za-z0-9_/\-]+"),
        "[REDACTED_SLACK_WEBHOOK]",
    ),
    (
        re.compile(r"(?i)\b(authorization\s*:\s*bearer\s+)[A-Za-z0-9._~+/\-]+=*"),
        r"\1[REDACTED]",
    ),
    (
        re.compile(r"(?i)(['\"]authorization['\"]\s*:\s*['\"]bearer\s+)[^'\"]+"),
        r"\1[REDACTED]",
    ),
    (
        re.compile(r"(?i)(\\['\"]authorization\\['\"]\s*:\s*\\['\"]bearer\s+)[^\\'\"]+"),
        r"\1[REDACTED]",
    ),
    (
        re.compile(
            r"(?i)\b((?:slack_)?webhook(?:_url)?|token|access_token|refresh_token|api_key|apikey|secret|password|passwd|pwd|authorization)\b(\s*[:=]\s*)(['\"]?)[^\s,'\"]+"
        ),
        r"\1\2\3[REDACTED]",
    ),
    (
        re.compile(
            r"(?i)(['\"](?:slack_)?(?:webhook(?:_url)?|token|access_token|refresh_token|api_key|apikey|secret|password|passwd|pwd|authorization)['\"]\s*:\s*['\"])[^'\"]+"
        ),
        r"\1[REDACTED]",
    ),
    (
        re.compile(
            r"(?i)(\\['\"](?:slack_)?(?:webhook(?:_url)?|token|access_token|refresh_token|api_key|apikey|secret|password|passwd|pwd|authorization)\\['\"]\s*:\s*\\['\"])[^\\'\"]+"
        ),
        r"\1[REDACTED]",
    ),
]

if redaction_regex_file:
    try:
        for raw_pattern in Path(redaction_regex_file).read_text(errors="replace").splitlines():
            pattern = raw_pattern.strip()
            if pattern and not pattern.startswith("#"):
                SECRET_REPLACEMENTS.append((re.compile(pattern), "[REDACTED]"))
    except Exception as exc:
        SECRET_REPLACEMENTS.append((re.compile(re.escape(str(exc))), "[REDACTED]"))

SENSITIVE_FIELD_PATTERN = re.compile(
    r"(?i)(webhook|token|api[_-]?key|secret|password|passwd|pwd|authorization)"
)

SENSITIVE_ARG_PATTERN = re.compile(
    r"(?i)^-{1,2}(?:slack-)?(?:webhook(?:-url)?|token|access-token|refresh-token|api-key|apikey|secret|password|passwd|pwd|authorization)$"
)

def redact_text(value):
    if value is None:
        return None

    redacted = str(value)
    for pattern, replacement in SECRET_REPLACEMENTS:
        redacted = pattern.sub(replacement, redacted)
    return redacted

def redact_value(value):
    if isinstance(value, dict):
        return {
            key: "[REDACTED]" if SENSITIVE_FIELD_PATTERN.search(str(key)) else redact_value(item)
            for key, item in value.items()
        }

    if isinstance(value, list):
        return [redact_value(item) for item in value]

    if isinstance(value, str):
        return redact_text(value)

    return value

def redact_command_args(args):
    redacted = []
    redact_next = False

    for arg in args:
        if redact_next:
            redacted.append("[REDACTED]")
            redact_next = False
            continue

        if "=" in arg:
            name, value = arg.split("=", 1)
            if SENSITIVE_ARG_PATTERN.match(name):
                redacted.append(f"{name}=[REDACTED]")
                continue

        if SENSITIVE_ARG_PATTERN.match(arg):
            redacted.append(arg)
            redact_next = True
            continue

        redacted.append(redact_text(arg))

    return redacted

def normalize_level(level):
    if not level:
        return "info"

    level = str(level).lower().strip()

    if level in {"fatal", "panic", "error", "err"}:
        return "error"

    if level in {"warn", "warning"}:
        return "warning"

    if level in {"debug", "trace"}:
        return level

    if level in {"info", "information"}:
        return "info"

    return level

def parse_log_line(stream, line, index):
    stripped = line.strip()

    entry = {
        "index": index,
        "stream": stream,
        "level": "info",
        "message": line,
        "format": "text"
    }

    if stripped.startswith("{") and stripped.endswith("}"):
        try:
            data = json.loads(stripped)

            if isinstance(data, dict):
                raw_level = (
                    data.get("level")
                    or data.get("severity")
                    or data.get("log_level")
                    or "info"
                )

                message = (
                    data.get("message")
                    or data.get("msg")
                    or data.get("error")
                    or data.get("err")
                    or stripped
                )

                entry["level"] = normalize_level(raw_level)
                entry["message"] = redact_text(message)
                entry["format"] = "json"
                entry["fields"] = redact_value(data)
                return entry
        except Exception:
            pass

    if (
        ERROR_PREFIX_PATTERN.search(line)
        or ERROR_LEVEL_PATTERN.search(line)
        or (stream == "stderr" and STDERR_ERROR_PATTERN.search(line))
        or TRACEBACK_PATTERN.search(line)
    ):
        entry["level"] = "error"
    elif (
        WARNING_PREFIX_PATTERN.search(line)
        or WARNING_LEVEL_PATTERN.search(line)
    ):
        entry["level"] = "warning"

    entry["message"] = redact_text(entry["message"])
    return entry

logs = []

for stream, text in (("stdout", stdout_text), ("stderr", stderr_text)):
    for line in text.splitlines():
        logs.append(parse_log_line(stream, line, len(logs) + 1))

stdout_lines = stdout_text.splitlines()
stderr_lines = stderr_text.splitlines()

error_logs = [log for log in logs if log.get("level") == "error"]
warning_logs = [log for log in logs if log.get("level") == "warning"]
redacted_command = redact_command_args(command)

detected_log_error = len(error_logs) > 0

process_success = target_exit_code == 0 and not timed_out and not capture_limit_exceeded
success = process_success and not (strict_log_errors and detected_log_error)

if timed_out:
    failure_reason = "timeout"
elif capture_limit_exceeded:
    failure_reason = "capture_limit_exceeded"
elif not process_success:
    failure_reason = "non_zero_exit_code"
elif strict_log_errors and detected_log_error:
    failure_reason = "error_log_detected"
else:
    failure_reason = None

if success:
    status = "success"
    success_message = f"Command completed successfully in {duration_ms} ms."
    error_message = None
    wrapper_exit_code = 0
else:
    status = "failed"
    success_message = None

    if failure_reason == "timeout":
        error_message = f"Command timed out after {timeout_seconds} seconds."
        wrapper_exit_code = 124
    elif failure_reason == "capture_limit_exceeded":
        error_message = f"Command exceeded max capture size of {max_capture_bytes} bytes."
        wrapper_exit_code = 125
    elif failure_reason == "non_zero_exit_code":
        error_message = f"Command failed with exit code {target_exit_code}."
        wrapper_exit_code = target_exit_code
    elif failure_reason == "error_log_detected":
        first_error = error_logs[0]["message"] if error_logs else "Error log detected."
        error_message = f"Command exited with code 0, but error logs were detected: {first_error}"
        wrapper_exit_code = 1
    else:
        error_message = "Command failed."
        wrapper_exit_code = 1

result = {
    "success": success,
    "status": status,
    "exit_code": target_exit_code,
    "wrapper_exit_code": wrapper_exit_code,
    "failure_reason": failure_reason,
    "strict_log_errors": strict_log_errors,
    "detected_log_error": detected_log_error,
	    "timed_out": timed_out,
    "capture_limit_exceeded": capture_limit_exceeded,
	    "timeout_seconds": timeout_seconds,
    "max_output_bytes": max_output_bytes,
    "max_capture_bytes": max_capture_bytes,
    "success_message": success_message,
    "error_message": redact_text(error_message),
    "command": {
        "display": " ".join(shlex.quote(part) for part in redacted_command),
        "args": redacted_command
    },
    "timing": {
        "started_at": start_time,
        "finished_at": end_time,
        "duration_ms": duration_ms
    },
	    "summary": {
	        "total_log_lines": len(logs),
	        "stdout_lines": len(stdout_lines),
	        "stderr_lines": len(stderr_lines),
	        "error_lines": len(error_logs),
	        "warning_lines": len(warning_logs),
	        "first_error": redact_text(error_logs[0]["message"]) if error_logs else None,
        "stdout_raw_bytes": stdout_raw_bytes,
        "stderr_raw_bytes": stderr_raw_bytes,
        "stdout_truncated": stdout_truncated,
        "stderr_truncated": stderr_truncated,
        "output_truncated": stdout_truncated or stderr_truncated
    },
    # Keep disabled to avoid sending very large log payloads; uncomment when full per-line logs are needed.
    # "logs": logs,
    "output": {}
}

if include_stdout:
    result["output"]["stdout"] = redact_text(stdout_text)
if include_stderr:
    result["output"]["stderr"] = redact_text(stderr_text)

print(json.dumps(result, indent=2))

sys.exit(wrapper_exit_code)
PY
