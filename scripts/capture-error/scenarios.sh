#!/usr/bin/env bash

# scripts/capture-error/scenarios.sh
# Scenario generator used for local testing of capture-error.sh.

set -uo pipefail

DEFAULT_SLEEP_SECONDS=5

SCENARIOS=(
  success
  stderr-info
  warning
  multi-warning
  error-log-zero
  stderr-error-zero
  fatal-text-zero
  json-info
  json-warning
  json-error
  json-fatal
  json-nested-secret
  json-array
  invalid-json
  traceback
  multiline-stack
  secret
  command-not-found-text
  large-output
  interleaved-output
  progress
  carriage-return
  no-newline
  empty-output
  mixed
  nonzero
  nonzero-no-output
  signal-term
  slow
)

SUCCESS_SCENARIOS=(
  success
  stderr-info
  warning
  multi-warning
  json-info
  json-warning
  json-array
  invalid-json
  large-output
  interleaved-output
  progress
  carriage-return
  no-newline
  empty-output
  slow
)

ERROR_SCENARIOS=(
  error-log-zero
  stderr-error-zero
  fatal-text-zero
  json-error
  json-fatal
  json-nested-secret
  traceback
  multiline-stack
  secret
  command-not-found-text
  mixed
  nonzero
  nonzero-no-output
  signal-term
)

show_help() {
  cat <<'EOF'
Usage:
  ./scripts/capture-error/scenarios.sh [options]

Scenario options:
  --scenario NAME       Run one scenario. Use --list-scenarios to see names.
  --random              Run one random scenario.
  --all                 Run every non-slow scenario.
  --all-success         Run every expected-success scenario except slow.
  --all-failure         Run every expected-failure scenario.
  --include-slow        Include slow when running --all or --all-success.
  --sleep SECONDS       Duration for the slow scenario. Default: 5.
  --list-scenarios      Print available scenario names grouped by expected wrapper result.
  -h, --help            Show this help message.

Default:
  Prompt for a scenario when running in a terminal. Choose a suite option to run grouped scenarios.
  Print the grouped scenario list in non-interactive runs.

Examples:
  ./scripts/capture-error/capture-error.sh -- ./scripts/capture-error/scenarios.sh --list-scenarios
  ./scripts/capture-error/capture-error.sh -- ./scripts/capture-error/scenarios.sh --scenario success
  ./scripts/capture-error/capture-error.sh -- ./scripts/capture-error/scenarios.sh --scenario error-log-zero
  ./scripts/capture-error/capture-error.sh --exit-code-only -- ./scripts/capture-error/scenarios.sh --all
  ./scripts/capture-error/capture-error.sh --timeout 1 -- ./scripts/capture-error/scenarios.sh --scenario slow --sleep 10
EOF
}

list_scenarios() {
  local scenario

  echo "Expected success scenarios:"
  for scenario in "${SUCCESS_SCENARIOS[@]}"; do
    printf '  - %s\n' "$scenario"
  done

  echo
  echo "Expected failure scenarios:"
  for scenario in "${ERROR_SCENARIOS[@]}"; do
    printf '  - %s\n' "$scenario"
  done

  cat <<'EOF'

Run one scenario by name, for example:
  scripts/capture-error/capture-error.sh scripts/capture-error/scenarios.sh --scenario success
  scripts/capture-error/capture-error.sh scripts/capture-error/scenarios.sh --scenario json-error

Suite modes:
  --all          Run every non-slow scenario.
  --all-success  Run expected-success scenarios except slow.
  --all-failure  Run expected-failure scenarios.

Use --random only when you intentionally want a random scenario.
EOF
}

select_scenario() {
  local choices=("${SUCCESS_SCENARIOS[@]}" "${ERROR_SCENARIOS[@]}")
  local choice
  local index
  local scenario
  local suite_start_index

  echo "Expected success scenarios:"
  index=0
  for scenario in "${SUCCESS_SCENARIOS[@]}"; do
    index=$((index + 1))
    printf '  %2d. %s\n' "$index" "$scenario"
  done

  echo
  echo "Expected failure scenarios:"
  for scenario in "${ERROR_SCENARIOS[@]}"; do
    index=$((index + 1))
    printf '  %2d. %s\n' "$index" "$scenario"
  done

  echo
  suite_start_index=$((${#choices[@]} + 1))
  printf '  %2d. all\n' "$suite_start_index"
  printf '  %2d. all-success\n' "$((suite_start_index + 1))"
  printf '  %2d. all-failure\n' "$((suite_start_index + 2))"
  echo
  printf 'Select scenario number or name: '

  if ! IFS= read -r choice; then
    echo
    echo "No selection received. Use --scenario NAME to run one scenario."
    return 64
  fi

  choice="${choice#"${choice%%[![:space:]]*}"}"
  choice="${choice%"${choice##*[![:space:]]}"}"

  if [ -z "$choice" ]; then
    echo "No selection received. Use --scenario NAME to run one scenario."
    return 64
  fi

  case "$choice" in
    all|--all|all-success|--all-success|all-failure|--all-failure)
      selected_scenario="${choice#--}"
      return 0
      ;;
  esac

  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge "$suite_start_index" ] && [ "$choice" -le "$((suite_start_index + 2))" ]; then
    case "$choice" in
      "$suite_start_index")
        selected_scenario="all"
        ;;
      "$((suite_start_index + 1))")
        selected_scenario="all-success"
        ;;
      "$((suite_start_index + 2))")
        selected_scenario="all-failure"
        ;;
    esac
    return 0
  fi

  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#choices[@]}" ]; then
    selected_scenario="${choices[$((choice - 1))]}"
    return 0
  fi

  for scenario in "${choices[@]}"; do
    if [ "$choice" = "$scenario" ]; then
      selected_scenario="$scenario"
      return 0
    fi
  done

  echo "Invalid selection '$choice'. Use --list-scenarios to see available names." >&2
  return 64
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

scenario_multi_warning() {
  echo "Warning: primary cache miss."
  echo "warn: fallback cache miss." >&2
  echo '{"level":"warning","message":"optional dependency unavailable","component":"scenario"}'
  echo "Continuing with default values."
}

scenario_error_log_zero() {
  echo "Error: simulated application error log with zero exit code."
  echo "The process still exits 0 so strict log detection can be tested."
}

scenario_stderr_error_zero() {
  echo "stdout: command completed but stderr reports an error."
  echo "Error: stderr application error with zero exit code." >&2
}

scenario_fatal_text_zero() {
  echo "fatal: simulated fatal text log with zero exit code."
  echo "This checks fatal text detection without relying on JSON."
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

scenario_json_fatal() {
  echo '{"severity":"fatal","msg":"JSON fatal log","err":"worker crashed","component":"scenario"}' >&2
}

scenario_json_nested_secret() {
  echo '{"level":"error","message":"nested secret redaction check","context":{"authorization":"bearer xoxb-nested-secret","token":"nested-token","api_key":"nested-api-key"},"items":[{"password":"nested-password"}]}'
}

scenario_json_array() {
  echo '[{"level":"info","message":"array log should be treated as text"}]'
  echo "JSON arrays are not parsed as structured log entries."
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

scenario_multiline_stack() {
  echo "UnhandledPromiseRejection: simulated async failure" >&2
  echo "    at runScenario (/app/scenario.js:12:7)" >&2
  echo "    at main (/app/index.js:4:3)" >&2
}

scenario_secret() {
  echo "Calling Slack webhook https://hooks.slack.com/services/T000/B000/SECRET"
  echo 'authorization: bearer xoxb-secret-token-value' >&2
  echo '{"level":"error","message":"secret redaction check","api_key":"plain-secret","password":"hunter2"}'
}

scenario_command_not_found_text() {
  echo "bash: missing-tool: command not found" >&2
  echo "This checks common shell diagnostic detection on stderr."
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

scenario_interleaved_output() {
  local i

  for ((i = 1; i <= 5; i++)); do
    printf 'stdout step %02d\n' "$i"
    printf 'stderr diagnostic %02d\n' "$i" >&2
  done
}

scenario_progress() {
  local i

  for ((i = 0; i <= 100; i += 25)); do
    printf 'progress=%s%%\n' "$i"
    sleep 0.1
  done
  echo "Progress scenario completed."
}

scenario_carriage_return() {
  local i

  for ((i = 0; i <= 100; i += 50)); do
    printf '\rprogress %s%%' "$i"
    sleep 0.1
  done
  printf '\ncarriage return progress completed.\n'
}

scenario_no_newline() {
  printf 'stdout-without-trailing-newline'
}

scenario_empty_output() {
  :
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

scenario_nonzero_no_output() {
  return 7
}

scenario_signal_term() {
  echo "Sending SIGTERM to self."
  bash -c 'kill -TERM "$$"'
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
    multi-warning)
      scenario_multi_warning
      ;;
    error-log-zero)
      scenario_error_log_zero
      ;;
    stderr-error-zero)
      scenario_stderr_error_zero
      ;;
    fatal-text-zero)
      scenario_fatal_text_zero
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
    json-fatal)
      scenario_json_fatal
      ;;
    json-nested-secret)
      scenario_json_nested_secret
      ;;
    json-array)
      scenario_json_array
      ;;
    invalid-json)
      scenario_invalid_json
      ;;
    traceback)
      scenario_traceback
      ;;
    multiline-stack)
      scenario_multiline_stack
      ;;
    secret)
      scenario_secret
      ;;
    command-not-found-text)
      scenario_command_not_found_text
      ;;
    large-output)
      scenario_large_output
      ;;
    interleaved-output)
      scenario_interleaved_output
      ;;
    progress)
      scenario_progress
      ;;
    carriage-return)
      scenario_carriage_return
      ;;
    no-newline)
      scenario_no_newline
      ;;
    empty-output)
      scenario_empty_output
      ;;
    mixed)
      scenario_mixed
      ;;
    nonzero)
      scenario_nonzero
      ;;
    nonzero-no-output)
      scenario_nonzero_no_output
      ;;
    signal-term)
      scenario_signal_term
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

is_expected_nonzero_scenario() {
  case "$1" in
    nonzero|nonzero-no-output|signal-term)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

run_suite() {
  local suite="$1"
  local sleep_seconds="$2"
  local include_slow="$3"
  local suite_label
  local suite_scenarios=()
  local scenario
  local status
  local failures=0

  case "$suite" in
    all)
      suite_label="all scenarios"
      suite_scenarios=("${SCENARIOS[@]}")
      ;;
    all-success)
      suite_label="expected-success scenarios"
      suite_scenarios=("${SUCCESS_SCENARIOS[@]}")
      ;;
    all-failure)
      suite_label="expected-failure scenarios"
      suite_scenarios=("${ERROR_SCENARIOS[@]}")
      ;;
    *)
      echo "Error: Unknown suite '$suite'." >&2
      return 64
      ;;
  esac

  if [ "$include_slow" = true ]; then
    echo "Running $suite_label, including slow scenarios."
  else
    echo "Running $suite_label, excluding slow scenarios."
  fi

  if [ "$suite" != "all-success" ]; then
    echo "This suite includes expected failure logs. Use capture-error.sh --exit-code-only when you want the wrapper result to stay successful."
  fi

  for scenario in "${suite_scenarios[@]}"; do
    if [ "$scenario" = "slow" ] && [ "$include_slow" != true ]; then
      continue
    fi

    printf '\n--- scenario: %s ---\n' "$scenario"
    run_scenario "$scenario" "$sleep_seconds"
    status=$?

    if [ "$status" -ne 0 ] && ! is_expected_nonzero_scenario "$scenario"; then
      echo "Error: scenario '$scenario' failed with exit code $status." >&2
      failures=$((failures + 1))
    fi
  done

  if [ "$failures" -gt 0 ]; then
    return 1
  fi

  echo
  echo "Scenario suite completed: $suite"
}

pick_random_scenario() {
  local index

  index=$((RANDOM % ${#SCENARIOS[@]}))
  printf '%s\n' "${SCENARIOS[$index]}"
}

scenario=""
selected_scenario=""
mode="select"
include_slow=false
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
    --all-success)
      mode="all-success"
      shift
      ;;
    --all-failure)
      mode="all-failure"
      shift
      ;;
    --include-slow)
      include_slow=true
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
      mode="list"
      shift
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
  select)
    if [ -t 0 ]; then
      select_scenario
      status=$?

      if [ "$status" -ne 0 ]; then
        exit "$status"
      fi

      scenario="$selected_scenario"
      echo
      echo "Selected scenario: $scenario"

      case "$scenario" in
        all|all-success|all-failure)
          run_suite "$scenario" "$sleep_seconds" "$include_slow"
          exit $?
          ;;
      esac

      run_scenario "$scenario" "$sleep_seconds"
      exit $?
    fi

    list_scenarios
    exit 0
    ;;
  list)
    list_scenarios
    exit 0
    ;;
  all)
    run_suite all "$sleep_seconds" "$include_slow"
    exit $?
    ;;
  all-success)
    run_suite all-success "$sleep_seconds" "$include_slow"
    exit $?
    ;;
  all-failure)
    run_suite all-failure "$sleep_seconds" "$include_slow"
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
