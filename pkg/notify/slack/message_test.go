package slack

import (
	"testing"

	"github.com/Er-rdhtiwari/slack-integration/pkg/notify/model"
)

func TestBuildMessageForFailedEvent(t *testing.T) {
	event := model.PipelineEvent{
		EventType:    "pr",
		Stage:        "validation",
		Status:       "failed",
		PipelineName: "pr-check",
		FailedStep:   "go-test",
		ErrorMessage: "unit tests failed",
	}

	msg := BuildMessage(event)

	if msg.Text != "Pipeline failed: pr-check" {
		t.Fatalf("unexpected text: %s", msg.Text)
	}

	if len(msg.Attachments) != 1 {
		t.Fatalf("expected 1 attachment, got %d", len(msg.Attachments))
	}

	attachment := msg.Attachments[0]

	if attachment.Color != "danger" {
		t.Fatalf("expected color danger, got %s", attachment.Color)
	}

	if len(attachment.Fields) < 6 {
		t.Fatalf("expected failure fields, got %d fields", len(attachment.Fields))
	}
}