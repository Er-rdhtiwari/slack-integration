#!/usr/bin/env bash
set -euo pipefail

EVENT_TYPE="${1:-pr}"
STAGE="${2:-failure}"
STATUS="${3:-failed}"

PIPELINE_NAME="${PIPELINE_NAME:-pr-validation-pipeline}"
FAILED_STEP="${FAILED_STEP:-unit-tests}"
ERROR_MESSAGE="${ERROR_MESSAGE:-unit tests failed in local run}"
ENVIRONMENT="${ENVIRONMENT:-dev}"

case "$EVENT_TYPE" in
  pr)
    REQUIRED_WEBHOOK_VAR="SLACK_WEBHOOK_URL_PR"
    ;;
  cd|job)
    REQUIRED_WEBHOOK_VAR="SLACK_WEBHOOK_URL_CD"
    ;;
  *)
    echo "Error: unsupported event type '$EVENT_TYPE'"
    echo "Supported values: pr, cd, job"
    exit 1
    ;;
esac

if [[ -z "${!REQUIRED_WEBHOOK_VAR:-}" ]]; then
  echo "Error: $REQUIRED_WEBHOOK_VAR environment variable is not set"
  echo "Example:"
  echo "  export $REQUIRED_WEBHOOK_VAR='https://hooks.slack.com/services/xxx'"
  exit 1
fi

echo "Running local Slack notifier..."
echo "Event Type : $EVENT_TYPE"
echo "Stage      : $STAGE"
echo "Status     : $STATUS"
echo "Pipeline   : $PIPELINE_NAME"
echo "Env        : $ENVIRONMENT"

go run cmd/slack-notifier/main.go \
  --event-type "$EVENT_TYPE" \
  --stage "$STAGE" \
  --status "$STATUS" \
  --pipeline-name "$PIPELINE_NAME" \
  --failed-step "$FAILED_STEP" \
  --error-message "$ERROR_MESSAGE" \
  --env "$ENVIRONMENT"

echo "Local Slack notifier completed successfully"
