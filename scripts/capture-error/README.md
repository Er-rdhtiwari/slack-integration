# capture-error

`capture-error` wraps a command, captures stdout/stderr, detects common error logs, redacts common secrets, and prints a bounded JSON result. It is designed for CI, Kubernetes jobs, internal automation, and controlled production support diagnostics.

## Production Status

Acceptable for:

- CI and Tekton-style jobs
- Kubernetes debug/support jobs
- short-lived operational diagnostics
- controlled production support tasks with explicit limits

Not intended as:

- a general production logging pipeline
- a compliance-grade DLP or secret-scanning control
- the only failure detector for critical workflows
- a long-running daemon or sidecar

Recommended production-support defaults:

```bash
CAPTURE_ERROR_MAX_OUTPUT_BYTES=65536
CAPTURE_ERROR_MAX_CAPTURE_BYTES=10485760
CAPTURE_ERROR_REDACTION_REGEX_FILE=/path/to/redaction-patterns.txt
```

## Files

```text
scripts/capture-error/
  capture-error.sh             Main shell entrypoint. Delegates to the Go runtime.
  runner.sh                    Runtime launcher for binary or local Go source.
  scenarios.sh                 Scenario generator for local testing.
  README.md

cmd/capture-error/
  main.go                      Thin Go CLI entrypoint.

pkg/captureerror/
  captureerror.go              Go capture-error implementation.
```

## Script Details

### `capture-error.sh`

Main entrypoint for normal use.

Responsibilities:

- Delegates to `runner.sh`.
- Emits a JSON wrapper error if the runner script is missing.

Use this script from CI, Kubernetes jobs, and support automation:

```bash
./scripts/capture-error/capture-error.sh -- ./my-command --flag value
```

### `runner.sh`

Shell wrapper for the Go implementation in `pkg/captureerror`.

Responsibilities:

- Uses `CAPTURE_ERROR_BIN` when it points at an executable prebuilt binary.
- Otherwise builds a temporary binary from `./cmd/capture-error` and runs it.
- Emits a JSON wrapper error when neither a prebuilt binary nor Go is available.
- Keeps Go source out of `scripts/capture-error/`.

Call it directly only when testing runtime selection behavior:

```bash
./scripts/capture-error/runner.sh -- ./my-command
```

### `scenarios.sh`

Scenario generator for local validation and future automated tests.

Responsibilities:

- Produces known stdout/stderr patterns.
- Produces warning and error-like logs.
- Produces JSON log examples.
- Produces secret-redaction examples.
- Produces timeout and non-zero-exit scenarios.
- Produces large-output and no-newline scenarios.
- Supports focused suites for expected-success, expected-failure, and full non-slow coverage.

Examples:

```bash
./scripts/capture-error/scenarios.sh --list-scenarios
./scripts/capture-error/scenarios.sh --scenario success
./scripts/capture-error/scenarios.sh --all-success
./scripts/capture-error/scenarios.sh --all-failure
./scripts/capture-error/scenarios.sh --all
```

When no scenario is provided, the script prompts for a scenario in a terminal. In non-interactive runs, it lists grouped success/error choices instead of choosing randomly.
For CI and repeatable local checks, prefer explicit flags such as `--scenario success`, `--all-success`, or `--all` instead of the interactive selector.

Requirements:

- `bash`
- `date`
- `mktemp`
- `rm`
- `kill`
- `sleep`
- `wc`
- writable temp directory, normally `/tmp`

The wrapper uses the Go implementation. In production or CI images, prefer a prebuilt executable at `bin/capture-error` or set `CAPTURE_ERROR_BIN` to the executable path. For local development, `runner.sh` can build and run `./cmd/capture-error` from a temporary directory when `go` is available.

Build a production binary with release metadata:

```bash
go build \
  -ldflags "-X main.version=0.1.0 -X main.commit=$(git rev-parse --short HEAD) -X main.date=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -o bin/capture-error \
  ./cmd/capture-error
```

## Quick Start

```bash
./scripts/capture-error/capture-error.sh -- echo "hello"
```

Use `--` when the wrapped command has flags:

```bash
./scripts/capture-error/capture-error.sh -- ./my-command --flag value
```

## Wrapper Flags

```text
--strict-log-errors       Fail when error-like logs are detected. Default.
--exit-code-only          Fail only when the command exits non-zero.
--stream-output           Mirror raw command stdout/stderr live to stderr, then print final JSON to stdout. Default.
--no-stream-output        Capture command output silently, then print only final JSON.
--stdout true|false       Include captured stdout text in final JSON output. Default: false.
--stderr true|false       Include captured stderr text in final JSON output. Default: true.
--timeout SECONDS         Stop the command after this many seconds. Default: 3600.
--max-output-bytes BYTES  Max bytes returned per stream in JSON. Default: 65536.
--max-capture-bytes BYTES Max combined stdout/stderr temp bytes before terminating. Default: 10485760.
--redaction-regex-file PATH
                           Extra redaction regex patterns, one per line.
--version                  Print capture-error build metadata as JSON.
-h, --help                Show help.
```

Environment defaults:

```bash
CAPTURE_ERROR_MAX_OUTPUT_BYTES=65536
CAPTURE_ERROR_MAX_CAPTURE_BYTES=10485760
CAPTURE_ERROR_REDACTION_REGEX_FILE=/path/to/redaction-patterns.txt
```

## JSON Result

The wrapper prints JSON to stdout and exits with `wrapper_exit_code`.

Command logs are streamed while the process is still running:

```bash
./scripts/capture-error/capture-error.sh -- \
  ./scripts/capture-error/scenarios.sh --scenario slow
```

Live command output is mirrored to stderr so stdout can still be parsed as the final JSON result. Streamed output is raw terminal output; redaction still applies to the final JSON. Use `--no-stream-output` to restore the old silent capture behavior.

Important fields:

- `success` - final boolean result.
- `status` - `success` or `failed`.
- `exit_code` - exit code from the wrapped command.
- `wrapper_exit_code` - exit code from `capture-error.sh`.
- `failure_reason` - failure category, for example `timeout`, `non_zero_exit_code`, `error_log_detected`, or `capture_limit_exceeded`.
- `summary.stdout_raw_bytes` and `summary.stderr_raw_bytes` - raw captured byte counts.
- `summary.output_truncated` - whether captured stdout or stderr exceeded `--max-output-bytes`.
- `output.stdout` - captured, redacted stdout, present only with `--stdout true`.
- `output.stderr` - captured, redacted stderr, present by default and removed with `--stderr false`.
- `version` - Go build metadata with `version`, `commit`, and `date`.

## Exit Codes

```text
0     Success.
1     Strict log detection failed while command exited 0.
64    Wrapper usage error.
70    Wrapper setup or dependency failure.
124   Timeout.
125   Capture limit exceeded.
other Wrapped command exit code.
```

## Output Limits

There are two separate limits:

- `--max-output-bytes` limits how many bytes per stream can be returned in JSON when that stream is included.
- `--max-capture-bytes` limits combined raw stdout/stderr captured in temp files. When exceeded, the command is terminated and the wrapper exits `125`.

Examples:

```bash
./scripts/capture-error/capture-error.sh --max-output-bytes 32768 -- \
  ./scripts/capture-error/scenarios.sh --scenario large-output
```

```bash
./scripts/capture-error/capture-error.sh --max-capture-bytes 1048576 -- \
  ./some-noisy-command
```

The capture-size watcher checks periodically, so raw files can exceed the limit slightly before termination.

## Redaction

Built-in redaction covers common sensitive values:

- Slack webhook URLs
- bearer tokens
- API keys
- access and refresh tokens
- passwords
- fields named `secret`, `token`, `api_key`, `password`, and similar names

Add project-specific patterns:

```bash
cat > /tmp/capture-redaction-patterns.txt <<'EOF'
customer_id=[A-Za-z0-9_-]+
internal_ticket=[A-Z]+-[0-9]+
EOF

./scripts/capture-error/capture-error.sh \
  --redaction-regex-file /tmp/capture-redaction-patterns.txt \
  -- ./some-command
```

Redaction is best-effort. Treat captured JSON as sensitive data.

## Strict Log Detection

Default behavior fails the wrapper if the command exits `0` but emits error-like logs:

```bash
./scripts/capture-error/capture-error.sh -- \
  ./scripts/capture-error/scenarios.sh --scenario error-log-zero
```

Use exit-code-only mode to ignore error-like logs:

```bash
./scripts/capture-error/capture-error.sh --exit-code-only -- \
  ./scripts/capture-error/scenarios.sh --scenario error-log-zero
```

## Timeout

```bash
./scripts/capture-error/capture-error.sh --timeout 1 -- \
  ./scripts/capture-error/scenarios.sh --scenario slow --sleep 10
```

Timeout failures exit `124`.

## Scenario Testing

List grouped scenarios:

```bash
./scripts/capture-error/scenarios.sh --list-scenarios
```

Run one scenario:

```bash
./scripts/capture-error/capture-error.sh -- \
  ./scripts/capture-error/scenarios.sh --scenario success
```

Run expected-success coverage:

```bash
./scripts/capture-error/capture-error.sh -- \
  ./scripts/capture-error/scenarios.sh --all-success
```

Run expected-failure coverage:

```bash
./scripts/capture-error/capture-error.sh --exit-code-only -- \
  ./scripts/capture-error/scenarios.sh --all-failure
```

Run broad coverage:

```bash
./scripts/capture-error/capture-error.sh --exit-code-only -- \
  ./scripts/capture-error/scenarios.sh --all
```

Add `--include-slow --sleep SECONDS` to include the slow scenario in `--all` or `--all-success`.

Available scenarios:

```text
Expected success scenarios:
  - success
  - stderr-info
  - warning
  - multi-warning
  - json-info
  - json-warning
  - json-array
  - invalid-json
  - large-output
  - interleaved-output
  - progress
  - carriage-return
  - no-newline
  - empty-output
  - slow

Expected failure scenarios:
  - error-log-zero
  - stderr-error-zero
  - fatal-text-zero
  - json-error
  - json-fatal
  - json-nested-secret
  - traceback
  - multiline-stack
  - secret
  - command-not-found-text
  - mixed
  - nonzero
  - nonzero-no-output
  - signal-term
```

## Kubernetes Notes

`capture-error.sh` works in Kubernetes when the image includes the shell requirements and either a prebuilt `capture-error` binary or Go itself.

Images that usually need extra care:

- `scratch`
- `distroless`
- Alpine images without Bash installed

Container checks:

```bash
command -v bash
command -v mktemp
test -w /tmp
test -x ./bin/capture-error || command -v go
```

For production support usage, prefer a dedicated utility/debug image instead of adding Bash or Go to a minimal application image.

## Future Development

Recommended follow-up tasks are listed below. These are future hardening items, not current blockers for controlled CI/Kubernetes/support usage.

### 1. Automated Test Coverage

Task: keep Go unit tests and scenario coverage running in CI.

Subtasks:

- Assert success-path JSON fields.
- Assert non-zero command exit handling.
- Assert strict text-log error detection.
- Assert strict JSON-log error detection in Go mode.
- Assert `--exit-code-only` behavior.
- Assert timeout behavior and exit code `124`.
- Assert capture-limit behavior and exit code `125`.
- Assert `--max-output-bytes` truncation metadata.
- Assert default redaction for Slack webhooks, bearer tokens, API keys, and passwords.
- Assert custom redaction with `--redaction-regex-file`.

### 2. Kubernetes Runtime Validation

Task: validate behavior in the exact container image and cluster runtime used by CI/support jobs.

Subtasks:

- Run `scenarios.sh --all` through `capture-error.sh`.
- Validate timeout behavior for commands that spawn child processes.
- Validate capture-limit behavior under expected ephemeral-storage limits.
- Validate `/tmp` write permissions.
- Validate that `bin/capture-error` is present in runtime images, or that Go is intentionally available.
- Validate behavior under restricted security contexts.
- Document the recommended utility/debug image.

### 3. CI Integration

Task: make script health part of the repository checks.

Subtasks:

- Run `bash -n` for every script in `scripts/capture-error/`.
- Run automated tests in Go mode.
- Validate that wrapper output is parseable JSON.
- Fail CI on changed exit-code behavior unless intentionally updated.
- Publish scenario output as a CI artifact only when it is safe to retain.

### 4. Redaction Hardening

Task: make redaction policy explicit and testable for this repository.

Subtasks:

- Add a repo-owned redaction pattern file.
- Add company/project-specific token and identifier formats.
- Add tests for every supported redaction pattern.
- Decide whether invalid custom regex patterns should fail closed.
- Consider a `--no-output` or `--summary-only` mode for sensitive workflows.

### 5. Output and Storage Policy

Task: define where captured JSON can safely go.

Subtasks:

- Define default `CAPTURE_ERROR_MAX_OUTPUT_BYTES` per environment.
- Define default `CAPTURE_ERROR_MAX_CAPTURE_BYTES` per environment.
- Document approved storage locations for captured JSON.
- Document retention expectations.
- Add examples for storing only summary fields in sensitive pipelines.

### 6. Release and Compatibility

Task: treat the wrapper interface as a small compatibility contract.

Subtasks:

- Add a changelog.
- Document stable top-level JSON fields.
- Document stable exit codes.
- Add migration notes when JSON fields or exit-code behavior changes.
