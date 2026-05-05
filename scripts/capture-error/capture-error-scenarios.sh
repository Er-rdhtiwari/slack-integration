#!/usr/bin/env bash

# scripts/capture-error/capture-error-scenarios.sh
# Scenario generator used for local testing of capture-error.sh.

set -uo pipefail

DEFAULT_SLEEP_SECONDS=5

SCENARIOS=(
  success
  stderr-info
  warning
  error-log-zero
  json-info
  json-warning
  json-error
  invalid-json
  traceback
  secret
  large-output
  no-newline
  mixed
  nonzero
  slow
)

show_help() {
  cat <<'EOF'
Usage:
  ./scripts/capture-error/capture-error-scenarios.sh [options]

Scenario options:
  --scenario NAME       Run one scenario. Use --list-scenarios to see names.
  --random              Run one random scenario. Default when no options are provided.
  --all                 Run broad success-path coverage scenarios.
  --sleep SECONDS       Duration for the slow scenario. Default: 5.
  --list-scenarios      Print available scenario names.
  -h, --help            Show this help message.

Examples:
  ./scripts/capture-error/capture-error.sh -- ./scripts/capture-error/capture-error-scenarios.sh --scenario success
  ./scripts/capture-error/capture-error.sh -- ./scripts/capture-error/capture-error-scenarios.sh --scenario error-log-zero
  ./scripts/capture-error/capture-error.sh --timeout 1 -- ./scripts/capture-error/capture-error-scenarios.sh --scenario slow --sleep 10
EOF
}

list_scenarios() {
  local scenario

  for scenario in "${SCENARIOS[@]}"; do
    printf '%s\n' "$scenario"
  done
}

scenario_success() {
  echo "Starting successful sample work."
  echo "Processed 3 records."
  echo "Completed successfully."
}

scenario_stderr_info() {
  echo "stdout: work completed with informational stderr."
  echo "stderr: informational diagnostic message." >&2
}

scenario_warning() {
  echo "Warning: cache was empty, rebuilding."
  echo '{"level":"warn","message":"retrying optional operation","attempt":1}' >&2
  echo "Recovered after warning."
}

scenario_error_log_zero() {
  echo "Error: simulated application error log with zero exit code."
  echo "The process still exits 0 so strict log detection can be tested."
}

scenario_json_info() {
  echo '{"level":"info","message":"JSON log parsed successfully","component":"sample-random-work"}'
  echo '{"severity":"debug","msg":"debug detail should not fail","count":2}'
}

scenario_json_warning() {
  echo '{"severity":"warning","message":"JSON warning log","component":"sample-random-work"}'
}

scenario_json_error() {
  echo '{"level":"error","message":"JSON error log","error":"database unavailable","token":"secret-token-value"}'
}

scenario_invalid_json() {
  echo '{level: error, message: this is intentionally invalid JSON}'
  echo "The invalid JSON-looking line should be treated as plain text."
}

scenario_traceback() {
  echo "Traceback (most recent call last):" >&2
  echo "  File \"sample.py\", line 1, in <module>" >&2
  echo "Exception: simulated traceback" >&2
}

scenario_secret() {
  echo "Calling Slack webhook https://hooks.slack.com/services/T000/B000/SECRET"
  echo 'authorization: bearer xoxb-secret-token-value' >&2
  echo '{"level":"error","message":"secret redaction check","api_key":"plain-secret","password":"hunter2"}'
}

scenario_large_output() {
  local i

  for ((i = 1; i <= 50; i++)); do
    printf 'bulk stdout line %02d\n' "$i"
  done

  for ((i = 1; i <= 10; i++)); do
    printf 'bulk stderr line %02d\n' "$i" >&2
  done
}

scenario_no_newline() {
  printf 'stdout-without-trailing-newline'
}

scenario_mixed() {
  echo '{"level":"info","message":"mixed scenario started"}'
  echo "Warning: fallback path selected."
  echo "stderr: still running" >&2
  echo '{"level":"error","message":"mixed scenario synthetic error"}' >&2
  echo "mixed scenario finished with exit 0"
}

scenario_nonzero() {
  echo "Error: simulated non-zero failure." >&2
  return 42
}

scenario_slow() {
  local seconds="$1"

  echo "Sleeping for $seconds seconds..."
  sleep "$seconds"
  echo "Slow scenario finished."
}

run_scenario() {
  local scenario="$1"
  local sleep_seconds="$2"

  case "$scenario" in
    success)
      scenario_success
      ;;
    stderr-info)
      scenario_stderr_info
      ;;
    warning)
      scenario_warning
      ;;
    error-log-zero)
      scenario_error_log_zero
      ;;
    json-info)
      scenario_json_info
      ;;
    json-warning)
      scenario_json_warning
      ;;
    json-error)
      scenario_json_error
      ;;
    invalid-json)
      scenario_invalid_json
      ;;
    traceback)
      scenario_traceback
      ;;
    secret)
      scenario_secret
      ;;
    large-output)
      scenario_large_output
      ;;
    no-newline)
      scenario_no_newline
      ;;
    mixed)
      scenario_mixed
      ;;
    nonzero)
      scenario_nonzero
      ;;
    slow)
      scenario_slow "$sleep_seconds"
      ;;
    *)
      echo "Error: Unknown scenario '$scenario'." >&2
      echo "Use --list-scenarios to see available scenarios." >&2
      return 64
      ;;
  esac
}

run_all() {
  local sleep_seconds="$1"
  local scenario
  local status
  local failures=0

  for scenario in success stderr-info warning error-log-zero json-info json-warning json-error invalid-json traceback secret large-output no-newline mixed; do
    printf '\n--- scenario: %s ---\n' "$scenario"
    run_scenario "$scenario" "$sleep_seconds"
    status=$?

    if [ "$status" -ne 0 ]; then
      echo "Error: scenario '$scenario' failed with exit code $status." >&2
      failures=$((failures + 1))
    fi
  done

  if [ "$failures" -gt 0 ]; then
    return 1
  fi

  echo
  echo "All broad coverage scenarios completed."
}

pick_random_scenario() {
  local index

  index=$((RANDOM % ${#SCENARIOS[@]}))
  printf '%s\n' "${SCENARIOS[$index]}"
}

scenario=""
mode="random"
sleep_seconds="$DEFAULT_SLEEP_SECONDS"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario)
      if [ "$#" -lt 2 ]; then
        echo "Error: Missing scenario name for $1" >&2
        exit 64
      fi
      scenario="$2"
      mode="scenario"
      shift 2
      ;;
    --random)
      mode="random"
      shift
      ;;
    --all)
      mode="all"
      shift
      ;;
    --sleep)
      if [ "$#" -lt 2 ] || ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: --sleep requires a positive integer number of seconds." >&2
        exit 64
      fi
      sleep_seconds="$2"
      shift 2
      ;;
    --list-scenarios)
      list_scenarios
      exit 0
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Error: Unknown option '$1'" >&2
      echo "Use '$0 --help' to see available options." >&2
      exit 64
      ;;
  esac
done

case "$mode" in
  all)
    run_all "$sleep_seconds"
    exit $?
    ;;
  random)
    scenario="$(pick_random_scenario)"
    echo "Selected random scenario: $scenario"
    run_scenario "$scenario" "$sleep_seconds"
    exit $?
    ;;
  scenario)
    run_scenario "$scenario" "$sleep_seconds"
    exit $?
    ;;
esac
