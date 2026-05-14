#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export GOCACHE="${GOCACHE:-/private/tmp/slack-integration-go-build}"

echo "==> Go tests"
go test ./...

echo "==> Go race tests"
go test -race ./...

echo "==> Go vet"
go vet ./...

echo "==> Shell syntax"
while IFS= read -r script; do
  bash -n "$script"
done < <(find scripts -type f -name "*.sh" | sort)
bash -n setup.sh

echo "==> YAML syntax"
ruby -e 'require "yaml"; ARGV.each { |f| YAML.load_stream(File.read(f)); puts "ok #{f}" }' \
  k8s/*.yaml \
  .tekton/*.yaml

echo "==> capture-error dependency check"
./scripts/capture-error/check-deps.sh >/dev/null

echo "==> capture-error success smoke test"
CAPTURE_ERROR_SKIP_DEPS_CHECK=true \
  ./scripts/capture-error/capture-error.sh --no-stream-output -- \
  ./scripts/capture-error/capture-error-scenarios.sh --scenario success |
  jq -e '.success == true and .status == "success"' >/dev/null

echo "==> capture-error failure smoke test"
failure_output="$(
  set +e
  CAPTURE_ERROR_SKIP_DEPS_CHECK=true \
    ./scripts/capture-error/capture-error.sh --no-stream-output -- \
    ./scripts/capture-error/capture-error-scenarios.sh --scenario nonzero
  true
)"
printf '%s\n' "$failure_output" |
  jq -e '.success == false and .status == "failed" and .exit_code == 42' >/dev/null

echo "==> slack-notifier pipeline dry run"
go run ./cmd/slack-notifier \
  --dry-run \
  --event-type pr \
  --stage validation \
  --status failed \
  --pipeline-name pr-validation \
  --failed-step go-test \
  --error-message token=secret |
  jq -e '.text == "Pipeline failed: pr-validation" and any(.attachments[0].fields[]; .title == "Error Message" and .value == "token=****")' >/dev/null

echo "==> slack-notifier Tekton failure dry run"
go run ./cmd/slack-notifier \
  --dry-run \
  --failure-context-json '{"namespace":"ci","pipeline_run":"pr-run","task_run":"task-run","failed_step":"build","exit_code":"1","reason":"Failed","error_message":"password=secret","trace":"line1\nfatal: failed with token=abc"}' |
  jq -e '.text == "Tekton task failed: task-run" and (.blocks | tostring | contains("password=****") and contains("token=****"))' >/dev/null

echo "All checks passed."
