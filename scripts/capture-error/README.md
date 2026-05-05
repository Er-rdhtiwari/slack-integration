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
  capture-error.sh             Main wrapper. Uses Python mode when available.
  capture-error-bash.sh        No-Python fallback, used automatically.
  check-deps.sh                Dependency check.
  capture-error-scenarios.sh   Scenario generator for local testing.
  README.md
```

## Script Details

### `capture-error.sh`

Main entrypoint for normal use.

Responsibilities:

- Parses wrapper flags.
- Runs `check-deps.sh` unless `CAPTURE_ERROR_SKIP_DEPS_CHECK=true`.
- Uses Python mode when `python3` and required standard-library modules are available.
- Automatically delegates to `capture-error-bash.sh` when Python mode is unavailable.
- Captures stdout/stderr into temporary files.
- Enforces timeout and capture-size limits.
- Redacts command arguments and captured output.
- Emits the final JSON result.

Use this script from CI, Kubernetes jobs, and support automation:

```bash
./scripts/capture-error/capture-error.sh -- ./my-command --flag value
```

### `capture-error-bash.sh`

Fallback implementation for images without Python.

Responsibilities:

- Supports the same core wrapper flags as `capture-error.sh`.
- Captures bounded stdout/stderr.
- Performs text-pattern error and warning detection.
- Applies built-in and custom redaction patterns.
- Emits JSON with `"fallback_mode": "bash"`.

Limitations:

- Does not parse structured JSON logs as deeply as Python mode.
- Uses `sed -E` for custom redaction patterns, so regex syntax should stay portable.
- Produces a smaller JSON shape than Python mode.

Call it directly only when testing fallback behavior:

```bash
./scripts/capture-error/capture-error-bash.sh -- ./my-command
```

### `check-deps.sh`

Dependency checker for the wrapper package.

Responsibilities:

- Verifies common shell dependencies.
- Reports whether Python mode is available.
- Reports whether Bash fallback dependencies are available.
- Emits JSON with `success`, `missing`, `failed_checks`, `python_available`, and `fallback_available`.

Example:

```bash
./scripts/capture-error/check-deps.sh
```

### `capture-error-scenarios.sh`

Scenario generator for local validation and future automated tests.

Responsibilities:

- Produces known stdout/stderr patterns.
- Produces warning and error-like logs.
- Produces JSON log examples.
- Produces secret-redaction examples.
- Produces timeout and non-zero-exit scenarios.
- Produces large-output and no-newline scenarios.

Examples:

```bash
./scripts/capture-error/capture-error-scenarios.sh --list-scenarios
./scripts/capture-error/capture-error-scenarios.sh --scenario success
./scripts/capture-error/capture-error-scenarios.sh --all
```

## Requirements

Common requirements:

- `bash`
- `date`
- `mktemp`
- `rm`
- `kill`
- `sleep`
- `wc`
- writable temp directory, normally `/tmp`

Python mode additionally requires `python3`. It uses only Python standard library modules.

Bash fallback mode additionally uses common shell utilities: `awk`, `dd`, `grep`, `sed`, and `tr`.

Check dependencies:

```bash
./scripts/capture-error/check-deps.sh
```

## Quick Start

```bash
./scripts/capture-error/capture-error.sh -- echo "hello"
```

Use `--` when the wrapped command has flags:

```bash
./scripts/capture-error/capture-error.sh -- ./my-command --flag value
```

Skip the automatic dependency check:

```bash
CAPTURE_ERROR_SKIP_DEPS_CHECK=true ./scripts/capture-error/capture-error.sh -- echo "hello"
```

## Wrapper Flags

```text
--strict-log-errors       Fail when error-like logs are detected. Default.
--exit-code-only          Fail only when the command exits non-zero.
--timeout SECONDS         Stop the command after this many seconds. Default: 3600.
--max-output-bytes BYTES  Max bytes returned per stream in JSON. Default: 65536.
--max-capture-bytes BYTES Max combined stdout/stderr temp bytes before terminating. Default: 10485760.
--redaction-regex-file PATH
                           Extra redaction regex patterns, one per line.
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

Important fields:

- `success` - final boolean result.
- `status` - `success` or `failed`.
- `exit_code` - exit code from the wrapped command.
- `wrapper_exit_code` - exit code from `capture-error.sh`.
- `failure_reason` - failure category, for example `timeout`, `non_zero_exit_code`, `error_log_detected`, or `capture_limit_exceeded`.
- `summary.stdout_raw_bytes` and `summary.stderr_raw_bytes` - raw captured byte counts.
- `summary.output_truncated` - whether JSON output was truncated.
- `output.stdout` and `output.stderr` - captured, redacted output.
- `fallback_mode` - present as `"bash"` when Python mode is unavailable.

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

- `--max-output-bytes` limits how many bytes per stream are returned in JSON.
- `--max-capture-bytes` limits combined raw stdout/stderr captured in temp files. When exceeded, the command is terminated and the wrapper exits `125`.

Examples:

```bash
./scripts/capture-error/capture-error.sh --max-output-bytes 32768 -- \
  ./scripts/capture-error/capture-error-scenarios.sh --scenario large-output
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
  ./scripts/capture-error/capture-error-scenarios.sh --scenario error-log-zero
```

Use exit-code-only mode to ignore error-like logs:

```bash
./scripts/capture-error/capture-error.sh --exit-code-only -- \
  ./scripts/capture-error/capture-error-scenarios.sh --scenario error-log-zero
```

## Timeout

```bash
./scripts/capture-error/capture-error.sh --timeout 1 -- \
  ./scripts/capture-error/capture-error-scenarios.sh --scenario slow --sleep 10
```

Timeout failures exit `124`.

## Scenario Testing

List scenarios:

```bash
./scripts/capture-error/capture-error-scenarios.sh --list-scenarios
```

Run one scenario:

```bash
./scripts/capture-error/capture-error.sh -- \
  ./scripts/capture-error/capture-error-scenarios.sh --scenario success
```

Run broad coverage:

```bash
./scripts/capture-error/capture-error.sh --exit-code-only -- \
  ./scripts/capture-error/capture-error-scenarios.sh --all
```

Available scenarios:

```text
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
```

## Kubernetes Notes

`capture-error.sh` works in Kubernetes when the image includes the common requirements. If `python3` is missing, it automatically switches to `capture-error-bash.sh`.

Images that usually need extra care:

- `scratch`
- `distroless`
- Alpine images without Bash installed

Container checks:

```bash
command -v bash
command -v mktemp
test -w /tmp
command -v python3  # optional, enables Python mode
```

For production support usage, prefer a dedicated utility/debug image instead of adding Bash/Python to a minimal application image.

## Future Development

Recommended follow-up tasks are listed below. These are future hardening items, not current blockers for controlled CI/Kubernetes/support usage.

### 1. Automated Test Suite

Task: add `test-capture-error.sh` for repeatable local and CI validation.

Subtasks:

- Assert success-path JSON fields.
- Assert non-zero command exit handling.
- Assert strict text-log error detection.
- Assert strict JSON-log error detection in Python mode.
- Assert `--exit-code-only` behavior.
- Assert timeout behavior and exit code `124`.
- Assert capture-limit behavior and exit code `125`.
- Assert `--max-output-bytes` truncation metadata.
- Assert default redaction for Slack webhooks, bearer tokens, API keys, and passwords.
- Assert custom redaction with `--redaction-regex-file`.
- Assert automatic Bash fallback when `python3` is unavailable.

### 2. Kubernetes Runtime Validation

Task: validate behavior in the exact container image and cluster runtime used by CI/support jobs.

Subtasks:

- Run `check-deps.sh` in the target image.
- Run `capture-error-scenarios.sh --all` through `capture-error.sh`.
- Validate timeout behavior for commands that spawn child processes.
- Validate capture-limit behavior under expected ephemeral-storage limits.
- Validate `/tmp` write permissions.
- Validate behavior under restricted security contexts.
- Document the recommended utility/debug image.

### 3. CI Integration

Task: make script health part of the repository checks.

Subtasks:

- Run `bash -n` for every script in `scripts/capture-error/`.
- Run automated tests in Python mode.
- Run automated tests in Bash fallback mode.
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

- Add a `--version` flag.
- Add a changelog.
- Document stable top-level JSON fields.
- Document stable exit codes.
- Document differences between Python mode and Bash fallback mode.
- Add migration notes when JSON fields or exit-code behavior changes.
