package slack

import (
	"strings"
	"testing"

	"github.com/Er-rdhtiwari/slack-integration/internal/failure"
)

func TestFormatFailureMessageIncludesFailureDetails(t *testing.T) {
	failureContext := failure.Context{
		Namespace:    "default",
		PipelineRun:  "user-service-pr-142",
		TaskRun:      "user-service-pr-142-build-image",
		FailedStep:   "docker-build",
		ExitCode:     "1",
		Reason:       "Failed",
		ErrorMessage: "go test failed",
		Trace:        "FAIL github.com/example/user-service\nexit status 1",
		TraceTrimmed: true,
	}

	payload := FormatFailureMessage(failureContext)

	combined := payload.Text
	for _, block := range payload.Blocks {
		if block.Text != nil {
			combined += "\n" + block.Text.Text
		}
	}

	expectedParts := []string{
		"user-service-pr-142",
		"user-service-pr-142-build-image",
		"docker-build",
		"go test failed",
		"exit status 1",
		"Trace was trimmed",
	}

	for _, part := range expectedParts {
		if !strings.Contains(combined, part) {
			t.Fatalf("expected formatted message to contain %q, got:\n%s", part, combined)
		}
	}
}
