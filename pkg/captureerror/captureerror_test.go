package captureerror

import (
	"strings"
	"testing"
)

func TestParseOptionsDefaultsAndCommand(t *testing.T) {
	opts, err := parseOptions([]string{"--stdout", "true", "--timeout", "2", "--", "echo", "hello"})
	if err != nil {
		t.Fatalf("parseOptions returned error: %v", err)
	}

	if !opts.strictLogErrors {
		t.Fatal("strict log errors should be enabled by default")
	}
	if !opts.streamOutput {
		t.Fatal("stream output should be enabled by default")
	}
	if !opts.includeStdout {
		t.Fatal("stdout should be included when --stdout true is set")
	}
	if opts.timeoutSeconds != 2 {
		t.Fatalf("timeoutSeconds = %d, want 2", opts.timeoutSeconds)
	}
	if got := strings.Join(opts.command, " "); got != "echo hello" {
		t.Fatalf("command = %q, want echo hello", got)
	}
}

func TestRunCommandSuccessIncludesStdout(t *testing.T) {
	opts := testOptions("printf", "hello")
	opts.includeStdout = true

	result, exitCode := runCommand(opts, defaultReplacements())
	if exitCode != 0 {
		t.Fatalf("exitCode = %d, want 0; result=%v", exitCode, result)
	}
	if result["success"] != true {
		t.Fatalf("success = %v, want true", result["success"])
	}

	output := result["output"].(map[string]interface{})
	if output["stdout"] != "hello" {
		t.Fatalf("stdout = %q, want hello", output["stdout"])
	}
}

func TestRunCommandDetectsErrorLog(t *testing.T) {
	opts := testOptions("printf", "Error: synthetic failure\n")

	result, exitCode := runCommand(opts, defaultReplacements())
	if exitCode != 1 {
		t.Fatalf("exitCode = %d, want 1; result=%v", exitCode, result)
	}
	if result["failure_reason"] != "error_log_detected" {
		t.Fatalf("failure_reason = %v, want error_log_detected", result["failure_reason"])
	}
}

func TestRunCommandExitCodeOnlyIgnoresErrorLog(t *testing.T) {
	opts := testOptions("printf", "Error: synthetic failure\n")
	opts.strictLogErrors = false

	result, exitCode := runCommand(opts, defaultReplacements())
	if exitCode != 0 {
		t.Fatalf("exitCode = %d, want 0; result=%v", exitCode, result)
	}
	if result["detected_log_error"] != true {
		t.Fatalf("detected_log_error = %v, want true", result["detected_log_error"])
	}
}

func TestRunCommandRedactsSecrets(t *testing.T) {
	opts := testOptions("printf", "token=secret-value\n")
	opts.includeStdout = true

	result, exitCode := runCommand(opts, defaultReplacements())
	if exitCode != 0 {
		t.Fatalf("exitCode = %d, want 0; result=%v", exitCode, result)
	}

	output := result["output"].(map[string]interface{})
	stdout := output["stdout"].(string)
	if strings.Contains(stdout, "secret-value") {
		t.Fatalf("stdout was not redacted: %q", stdout)
	}
	if !strings.Contains(stdout, "[REDACTED]") {
		t.Fatalf("stdout = %q, want redacted marker", stdout)
	}
}

func TestRunCommandTimeout(t *testing.T) {
	opts := testOptions("sleep", "2")
	opts.timeoutSeconds = 1
	opts.streamOutput = false

	result, exitCode := runCommand(opts, defaultReplacements())
	if exitCode != 124 {
		t.Fatalf("exitCode = %d, want 124; result=%v", exitCode, result)
	}
	if result["failure_reason"] != "timeout" {
		t.Fatalf("failure_reason = %v, want timeout", result["failure_reason"])
	}
}

func TestSetVersion(t *testing.T) {
	original := buildInfo
	t.Cleanup(func() {
		buildInfo = original
	})

	SetVersion("1.2.3", "abc123", "2026-05-06")

	if buildInfo.Version != "1.2.3" || buildInfo.Commit != "abc123" || buildInfo.Date != "2026-05-06" {
		t.Fatalf("buildInfo = %+v", buildInfo)
	}
}

func testOptions(command ...string) options {
	return options{
		strictLogErrors: true,
		streamOutput:    false,
		includeStdout:   false,
		includeStderr:   true,
		timeoutSeconds:  defaultTimeoutSeconds,
		maxOutputBytes:  defaultMaxOutputBytes,
		maxCaptureBytes: defaultMaxCaptureBytes,
		command:         command,
	}
}
