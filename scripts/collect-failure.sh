#!/usr/bin/env bash
set -euo pipefail

TASKRUN_NAME="${1:?Usage: collect-failure.sh <taskrun-name> [namespace]}"
NAMESPACE="${2:-default}"

taskrun_json="$(kubectl -n "$NAMESPACE" get taskrun "$TASKRUN_NAME" -o json)"

pod_name="$(echo "$taskrun_json" | jq -r '.status.podName // empty')"

failed_step="$(
  echo "$taskrun_json" |
    jq -r '
      .status.steps[]?
      | select((.terminated.exitCode // 0) != 0)
      | .name
    ' |
    head -n 1
)"

exit_code="$(
  echo "$taskrun_json" |
    jq -r '
      .status.steps[]?
      | select((.terminated.exitCode // 0) != 0)
      | .terminated.exitCode
    ' |
    head -n 1
)"

reason="$(
  echo "$taskrun_json" |
    jq -r '
      .status.conditions[]?
      | select(.type == "Succeeded")
      | .reason // "Unknown"
    ' |
    head -n 1
)"

message="$(
  echo "$taskrun_json" |
    jq -r '
      .status.conditions[]?
      | select(.type == "Succeeded")
      | .message // "No condition message"
    ' |
    head -n 1
)"

if [[ -z "$failed_step" ]]; then
  failed_step="unknown"
fi

if [[ -z "$exit_code" ]]; then
  exit_code="unknown"
fi

if [[ -z "$pod_name" ]]; then
  echo "Could not find pod name for TaskRun: $TASKRUN_NAME" >&2
  exit 1
fi

# Tekton step containers are usually named step-<stepName>.
container_name="step-${failed_step}"

raw_logs="$(
  kubectl -n "$NAMESPACE" logs "$pod_name" -c "$container_name" --tail=120 2>/dev/null || true
)"

# Basic secret masking.
safe_logs="$(
  printf "%s\n" "$raw_logs" |
    sed -E 's/(password|passwd|token|secret|api[_-]?key)=([^ ]+)/\1=****/Ig' |
    sed -E 's/(Authorization: Bearer )[A-Za-z0-9._~+\/=-]+/\1****/Ig'
)"

error_line="$(
  printf "%s\n" "$safe_logs" |
    grep -Ei 'error|failed|fatal|exception|panic|denied|timeout|exit status' |
    tail -n 1 ||
    true
)"

if [[ -z "$error_line" ]]; then
  error_line="$message"
fi

trace="$(
  printf "%s\n" "$safe_logs" |
    tail -n 30
)"

jq -n \
  --arg namespace "$NAMESPACE" \
  --arg task_run "$TASKRUN_NAME" \
  --arg pod "$pod_name" \
  --arg failed_step "$failed_step" \
  --arg exit_code "$exit_code" \
  --arg reason "$reason" \
  --arg error_message "$error_line" \
  --arg trace "$trace" \
  '{
    namespace: $namespace,
    task_run: $task_run,
    pod: $pod,
    failed_step: $failed_step,
    exit_code: $exit_code,
    reason: $reason,
    error_message: $error_message,
    trace: $trace
  }'