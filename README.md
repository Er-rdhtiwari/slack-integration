# slack-integration

`slack-integration` is a Go-based Slack notification utility plus Kubernetes/Tekton manifests and helper scripts for testing PR-triggered pipelines and reporting failures.

The repository currently supports two related workflows:

- A Tekton Trigger flow that accepts a GitHub-style pull request webhook and starts a sample `PipelineRun`.
- A `slack-notifier` CLI that sends Slack webhook messages for normal pipeline events or rich Tekton failure contexts.

Important current boundary: the sample Tekton pipeline prints PR details only. It does not yet run the Go notifier automatically. Slack delivery works through the CLI today, and the pipeline can be extended later to call that CLI or a containerized notifier step.

## Repository Layout

```text
.
  cmd/slack-notifier/          CLI entrypoint for Slack notifications.
  internal/failure/            Tekton failure context parsing, redaction, trace trimming.
  internal/notify/slack/       Slack Block Kit formatting for rich failure messages.
  pkg/config/                  Environment-based application configuration.
  pkg/logger/                  zerolog logger setup and event fields.
  pkg/notify/model/            Pipeline event model and validation.
  pkg/notify/router/           Event-type to Slack webhook routing.
  pkg/notify/slack/            Reusable Slack webhook client and pipeline message builder.
  pkg/status/                  Small pipeline status tracker.
  scripts/collect-failure.sh   Collect a failed Tekton TaskRun into JSON.
  scripts/capture-error/       Generic command wrapper for structured error capture.
  scripts/test-all.sh          Local validation runner for Go, scripts, YAML, and smoke tests.
  k8s/                         Namespace, service account, RBAC, and secret manifests.
  .tekton/                     PR TriggerBinding, TriggerTemplate, EventListener, and Pipeline.
```

## How The Pieces Fit Together

For pull request testing:

```text
GitHub-style PR JSON
  -> Tekton EventListener
  -> TriggerBinding extracts fields
  -> TriggerTemplate creates PipelineRun
  -> Pipeline prints PR metadata
```

For Slack notification:

```text
normal event flags
  -> slack-notifier
  -> pkg/notify/router selects webhook
  -> pkg/notify/slack sends Slack attachment payload
```

For Tekton failure notification:

```text
failed TaskRun
  -> scripts/collect-failure.sh emits JSON
  -> slack-notifier --failure-context-file -
  -> internal/failure masks and trims details
  -> internal/notify/slack builds Slack blocks
  -> pkg/notify/slack sends webhook payload
```

## Requirements

For Go development:

- Go `1.25.7` or compatible with `go.mod`
- Bash
- jq
- Ruby, used by `scripts/test-all.sh` for YAML syntax parsing

For Kubernetes/Tekton testing:

- kubectl
- A Kubernetes cluster
- Tekton Pipelines installed
- Tekton Triggers installed
- Permissions to create namespaces, RBAC, EventListeners, TriggerBindings, TriggerTemplates, and PipelineRuns

For Slack delivery:

- Slack incoming webhook URL for PR notifications
- Slack incoming webhook URL for CD/job/failure notifications

## Configuration

The Go notifier reads configuration from environment variables:

```text
APP_ENV               Runtime environment label. Default: dev.
LOG_LEVEL             zerolog level. Default: info.
RETRY_COUNT           Integer config value. Default: 3.
SLACK_WEBHOOK_URL_PR  Slack webhook for event-type pr.
SLACK_WEBHOOK_URL_CD  Slack webhook for event-type cd and job.
```

Logs are written to stderr. Payload output from `--dry-run` is written to stdout so it can be piped into `jq`.

## Slack Notifier CLI

Show flags:

```bash
go run ./cmd/slack-notifier --help
```

### Normal Pipeline Notification

Use this for PR/CD/job status messages built from CLI flags:

```bash
SLACK_WEBHOOK_URL_PR="https://hooks.slack.com/services/..." \
go run ./cmd/slack-notifier \
  --event-type pr \
  --stage validation \
  --status failed \
  --pipeline-name pr-validation \
  --failed-step go-test \
  --error-message "unit tests failed"
```

Supported event routing:

```text
pr   -> SLACK_WEBHOOK_URL_PR
cd   -> SLACK_WEBHOOK_URL_CD
job  -> SLACK_WEBHOOK_URL_CD
```

### Tekton Failure Notification

Collect failure data from a TaskRun and send a rich Slack message:

```bash
scripts/collect-failure.sh <taskrun-name> <namespace> \
  | SLACK_WEBHOOK_URL_CD="https://hooks.slack.com/services/..." \
    go run ./cmd/slack-notifier --failure-context-file -
```

`--failure-context-file` accepts a JSON file path. Use `-` to read JSON from stdin.

Inline JSON is also supported:

```bash
go run ./cmd/slack-notifier \
  --failure-context-json '{"namespace":"ci","task_run":"build-task","failed_step":"test","error_message":"tests failed","trace":"fatal: failed"}'
```

When failure context is supplied, missing event flags default to:

```text
--event-type job
--stage tekton
--status failed
--pipeline-name <pipeline_run>, <task_run>, or tekton-task
```

### Dry Run

Use `--dry-run` to validate inputs and print the exact Slack JSON payload without sending anything:

```bash
go run ./cmd/slack-notifier \
  --dry-run \
  --event-type pr \
  --stage validation \
  --status failed \
  --pipeline-name pr-validation \
  --failed-step go-test \
  --error-message token=secret |
  jq .
```

Dry-run is also useful for Tekton failure JSON:

```bash
go run ./cmd/slack-notifier \
  --dry-run \
  --failure-context-json '{"namespace":"ci","pipeline_run":"pr-run","task_run":"task-run","failed_step":"build","exit_code":"1","reason":"Failed","error_message":"password=secret","trace":"line1\nfatal: failed with token=abc"}' |
  jq .
```

The notifier masks common secret patterns before building Slack payloads, including `password=...`, `token=...`, `secret=...`, `api_key=...`, bearer tokens, and PEM private keys.

## Go Packages

### `cmd/slack-notifier`

The CLI entrypoint. It:

- Parses flags.
- Loads configuration.
- Reads optional failure-context JSON.
- Applies defaults for Tekton failure events.
- Validates the pipeline event.
- Builds a normal Slack attachment payload or rich failure block payload.
- Sends the payload, or prints it in dry-run mode.

### `internal/failure`

Private failure-processing package. It:

- Defines the `failure.Context` JSON shape used by `scripts/collect-failure.sh`.
- Parses failure context JSON.
- Masks common secret values.
- Finds a likely error line from logs when no explicit error message exists.
- Trims traces to a bounded line and byte count.

### `internal/notify/slack`

Private formatter for failure notifications. It creates Slack Block Kit payloads with:

- TaskRun title.
- Namespace, PipelineRun, failed step, exit code, reason, and error.
- Short redacted trace.
- Trimmed-trace marker when the trace was shortened.

### `pkg/config`

Loads environment variables into a typed config struct. Tests cover defaults, env overrides, and invalid integer handling.

### `pkg/logger`

Creates a zerolog logger with service and environment fields. Logs go to stderr.

### `pkg/notify/model`

Defines `PipelineEvent` and validates required event fields:

- `EventType`
- `Stage`
- `Status`

### `pkg/notify/router`

Maps event types to Slack webhook URLs:

- `pr` uses PR webhook.
- `cd` uses CD webhook.
- `job` falls back to CD webhook.
- Unknown event types return an explicit route error.

### `pkg/notify/slack`

Reusable Slack client package. It:

- Builds normal pipeline notification attachments.
- Sends arbitrary Slack-compatible JSON payloads.
- Uses an HTTP client timeout by default.
- Preserves the existing `SendMessage` and `Send` APIs.

### `pkg/status`

Small pipeline status tracker used by tests and earlier notification flows. It records started/finished times and builds status summaries.

## Scripts

### `scripts/test-all.sh`

Runs the local validation suite:

```bash
./scripts/test-all.sh
```

It checks:

- `go test ./...`
- `go test -race ./...`
- `go vet ./...`
- Bash syntax for shell scripts
- YAML syntax for `k8s/` and `.tekton/`
- capture-error dependency check
- capture-error success and failure smoke tests
- slack-notifier normal dry-run payload
- slack-notifier Tekton failure dry-run payload

### `scripts/collect-failure.sh`

Collects a Tekton TaskRun failure into JSON:

```bash
scripts/collect-failure.sh <taskrun-name> [namespace]
```

It reads the TaskRun, finds the backing pod, identifies the failed step, pulls recent step logs, applies basic shell-side redaction, and emits JSON compatible with `slack-notifier --failure-context-file`.

This script requires:

- kubectl
- jq
- access to the target namespace

### `scripts/capture-error/`

Generic command wrapper for structured error capture. See [scripts/capture-error/README.md](scripts/capture-error/README.md).

Typical use:

```bash
./scripts/capture-error/capture-error.sh -- ./your-command --flag value
```

It captures stdout/stderr, detects error-like output, applies redaction, enforces time and output limits, and prints structured JSON.

## Kubernetes Manifests

### `k8s/namespace.yaml`

Creates namespace:

```text
slack-integration-dev
```

### `k8s/serviceaccount.yaml`

Creates service account:

```text
slack-notifier-sa
```

The Tekton EventListener uses this service account.

### `k8s/eventlistener-rbac.yaml`

Binds Tekton Triggers EventListener roles to `slack-notifier-sa`:

- `tekton-triggers-eventlistener-roles`
- `tekton-triggers-eventlistener-clusterroles`

### `k8s/secret.yaml`

Contains placeholder secrets:

```text
SLACK_WEBHOOK_URL_PR
SLACK_WEBHOOK_URL_CD
GIT_TOKEN
```

Replace placeholders before real Slack or Git usage. Do not commit real webhook URLs or tokens.

## Tekton Manifests

### `.tekton/pr-binding.yaml`

Maps GitHub pull request JSON fields into Tekton trigger params:

- repository clone URL
- repository full name
- PR number
- commit SHA
- source branch
- target branch
- sender
- action

### `.tekton/pr-trigger-template.yaml`

Creates a `PipelineRun` for `pr-validation-pipeline` and passes the trigger params into the run.

### `.tekton/pr-listener.yaml`

Creates an EventListener named `pr-listener` that wires:

- `pr-binding`
- `pr-trigger-template`
- `slack-notifier-sa`

### `.tekton/pr-pipeline.yaml`

Defines `pr-validation-pipeline`. The current task uses `alpine:3.19` and prints PR metadata. It does not call Slack by itself.

## Install Tekton

Install Tekton Pipelines:

```bash
kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
```

Verify:

```bash
kubectl get pods --namespace tekton-pipelines
kubectl api-resources --api-group=tekton.dev
```

Install Tekton Triggers:

```bash
kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
kubectl apply --filename https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml
```

Verify:

```bash
kubectl get pods --namespace tekton-pipelines
kubectl api-resources --api-group=triggers.tekton.dev
```

## Apply This Project

Apply base resources:

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/serviceaccount.yaml
kubectl apply -f k8s/eventlistener-rbac.yaml
kubectl apply -f k8s/secret.yaml
```

Apply Tekton resources:

```bash
kubectl apply -f .tekton/pr-pipeline.yaml
kubectl apply -f .tekton/pr-binding.yaml
kubectl apply -f .tekton/pr-trigger-template.yaml
kubectl apply -f .tekton/pr-listener.yaml
```

Verify:

```bash
kubectl get pipeline -n slack-integration-dev
kubectl get triggerbinding -n slack-integration-dev
kubectl get triggertemplate -n slack-integration-dev
kubectl get eventlistener -n slack-integration-dev
kubectl get all -n slack-integration-dev
```

## Test The PR Webhook Flow

Port-forward the EventListener:

```bash
kubectl port-forward svc/el-pr-listener 8080:8080 -n slack-integration-dev
```

Send a test PR payload:

```bash
curl -i -X POST http://127.0.0.1:8080/ \
  -H 'Content-Type: application/json' \
  -H 'X-GitHub-Event: pull_request' \
  -d '{
    "action": "opened",
    "repository": {
      "clone_url": "https://github.com/example/slack-integration.git",
      "full_name": "example/slack-integration"
    },
    "pull_request": {
      "number": 42,
      "head": {
        "sha": "abc123def456",
        "ref": "feature/test-pr"
      },
      "base": {
        "ref": "main"
      }
    },
    "sender": {
      "login": "rdh-tiwari"
    }
  }'
```

Successful EventListener response means the event was accepted. Always verify the generated PipelineRun:

```bash
kubectl get pipelinerun -n slack-integration-dev --sort-by=.metadata.creationTimestamp
kubectl get taskrun -n slack-integration-dev --sort-by=.metadata.creationTimestamp
```

Inspect logs:

```bash
kubectl get pods -n slack-integration-dev
kubectl logs -n slack-integration-dev <taskrun-pod-name> --all-containers=true
```

Expected pipeline log content:

```text
PR Event Received
Repo URL: https://github.com/example/slack-integration.git
PR Number: 42
Commit ID: abc123def456
Source Branch: feature/test-pr
Target Branch: main
Sender: rdh-tiwari
Action: opened
```

## Failure Collection Flow

After a failed Tekton TaskRun:

```bash
scripts/collect-failure.sh <taskrun-name> slack-integration-dev > failure.json
```

Preview Slack payload:

```bash
go run ./cmd/slack-notifier --dry-run --failure-context-file failure.json | jq .
```

Send to Slack:

```bash
SLACK_WEBHOOK_URL_CD="https://hooks.slack.com/services/..." \
go run ./cmd/slack-notifier --failure-context-file failure.json
```

## Local Validation

Run everything:

```bash
./scripts/test-all.sh
```

Individual checks:

```bash
go test ./...
go test -race ./...
go vet ./...
bash -n scripts/collect-failure.sh
```

YAML syntax check without cluster access:

```bash
ruby -e 'require "yaml"; ARGV.each { |f| YAML.load_stream(File.read(f)); puts "ok #{f}" }' k8s/*.yaml .tekton/*.yaml
```

`kubectl apply --dry-run=client` may still contact a Kubernetes API server for discovery, depending on local kubectl configuration. Use the Ruby YAML check for offline syntax validation.

## Troubleshooting

### No Slack Message After Postman Or curl

The current Tekton pipeline only prints PR details. It does not call `slack-notifier`. Use the CLI directly, or add a Tekton task/step that invokes the notifier.

### Missing Webhook Configuration

Error:

```text
missing webhook configuration
```

Fix:

```bash
export SLACK_WEBHOOK_URL_PR="https://hooks.slack.com/services/..."
export SLACK_WEBHOOK_URL_CD="https://hooks.slack.com/services/..."
```

Use `SLACK_WEBHOOK_URL_CD` for `job` failure notifications.

### Unknown Event Type

Valid event types are:

```text
pr
cd
job
```

### Pipeline Kind Not Recognized

Error:

```text
no matches for kind "Pipeline" in version "tekton.dev/v1"
```

Install or fix Tekton Pipelines CRDs.

### EventListener Kind Not Recognized

Check the API group. This repo uses:

```text
triggers.tekton.dev/v1beta1
```

Install Tekton Triggers if the resource is missing.

### collect-failure Cannot Find Pod

Confirm the TaskRun exists and has started:

```bash
kubectl get taskrun -n <namespace>
kubectl describe taskrun <taskrun-name> -n <namespace>
```

### Dry Run Output Is Not JSON

Application logs should go to stderr and payload JSON should go to stdout. If a wrapper combines stderr and stdout, pipe stdout only into `jq`.

## Security Notes

- Do not commit real Slack webhook URLs.
- Do not commit real Git tokens.
- `scripts/collect-failure.sh` and `internal/failure` perform best-effort redaction, not compliance-grade data loss prevention.
- Keep traces bounded before posting to Slack.
- Prefer Kubernetes Secrets or CI secret stores for webhook injection.

## Current Production Readiness

Implemented:

- Typed config loading.
- Event validation.
- Webhook routing.
- HTTP timeout for Slack sends.
- Rich failure payload formatting.
- Secret masking for common patterns.
- Trace trimming.
- Dry-run payload preview.
- Go unit tests, race tests, vet, script syntax checks, YAML syntax checks, and smoke tests through `scripts/test-all.sh`.

Still needed for a fully automated cluster deployment:

- Container image build/publish for `slack-notifier`.
- Tekton task/step that invokes the notifier.
- Deployment or CronJob manifests if this should run as a service.
- CI workflow to run `scripts/test-all.sh`.
