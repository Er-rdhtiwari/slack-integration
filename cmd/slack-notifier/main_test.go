package main

import (
	"bytes"
	"encoding/json"
	"testing"

	"github.com/Er-rdhtiwari/slack-integration/internal/failure"
	notifyslack "github.com/Er-rdhtiwari/slack-integration/pkg/notify/slack"
)

func TestApplyFailureDefaults(t *testing.T) {
	ctx := failure.Context{
		PipelineRun:  "pipeline-run",
		TaskRun:      "task-run",
		FailedStep:   "build",
		ErrorMessage: "build failed",
	}

	eventType := ""
	stage := ""
	status := ""
	pipelineName := ""
	failedStep := ""
	errorMessage := ""

	applyFailureDefaults(ctx, &eventType, &stage, &status, &pipelineName, &failedStep, &errorMessage)

	if eventType != "job" {
		t.Fatalf("expected job event type, got %q", eventType)
	}
	if stage != "tekton" {
		t.Fatalf("expected tekton stage, got %q", stage)
	}
	if status != "failed" {
		t.Fatalf("expected failed status, got %q", status)
	}
	if pipelineName != "pipeline-run" {
		t.Fatalf("expected pipeline run as pipeline name, got %q", pipelineName)
	}
	if failedStep != "build" {
		t.Fatalf("expected failed step from context, got %q", failedStep)
	}
	if errorMessage != "build failed" {
		t.Fatalf("expected error message from context, got %q", errorMessage)
	}
}

func TestWriteDryRunPayload(t *testing.T) {
	var out bytes.Buffer
	payload := notifyslack.Message{
		Text: "Pipeline failed: pr-validation",
	}

	if err := writeDryRunPayload(&out, payload); err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	var decoded notifyslack.Message
	if err := json.Unmarshal(out.Bytes(), &decoded); err != nil {
		t.Fatalf("expected valid JSON, got %v", err)
	}
	if decoded.Text != payload.Text {
		t.Fatalf("expected payload text %q, got %q", payload.Text, decoded.Text)
	}
}
