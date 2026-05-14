package failure

import "testing"

func TestParseContextSanitizesAndTruncates(t *testing.T) {
	raw := []byte(`{
		"namespace": "ci",
		"pipeline_run": "pr-run-abc",
		"task_run": "unit-tests",
		"pod": "unit-tests-pod",
		"failed_step": "go-test",
		"exit_code": "1",
		"reason": "Failed",
		"error_message": "token=super-secret",
		"trace": "line 1\npassword=hunter2\nfatal: tests failed"
	}`)

	ctx, err := ParseContext(raw)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if ctx.ErrorMessage != "token=****" {
		t.Fatalf("expected masked error message, got %q", ctx.ErrorMessage)
	}
	if ctx.Trace != "line 1\npassword=****\nfatal: tests failed" {
		t.Fatalf("expected masked trace, got %q", ctx.Trace)
	}
}

func TestSanitizeContextFindsErrorMessage(t *testing.T) {
	ctx := SanitizeContext(Context{
		Trace: "starting\nfatal: tests failed\ncleanup",
	})

	if ctx.ErrorMessage != "fatal: tests failed" {
		t.Fatalf("expected inferred error message, got %q", ctx.ErrorMessage)
	}
}
