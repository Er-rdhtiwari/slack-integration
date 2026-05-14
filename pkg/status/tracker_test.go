package status

import "testing"

func TestPipelineTrackerMarkFailed(t *testing.T) {
	tracker := NewPipelineTracker("pr-validation", "pr", "validation")

	tracker.MarkFailed("go-test", "unit test failed")

	if !tracker.IsFailed() {
		t.Fatal("expected tracker to be failed")
	}

	if tracker.FailedStep != "go-test" {
		t.Fatalf("expected failed step go-test, got %s", tracker.FailedStep)
	}
}

func TestPipelineTrackerMarkSucceeded(t *testing.T) {
	tracker := NewPipelineTracker("cd-pipeline", "cd", "build")

	tracker.MarkSucceeded()

	if tracker.Status != StatusSucceeded {
		t.Fatalf("expected status succeeded, got %s", tracker.Status)
	}
}