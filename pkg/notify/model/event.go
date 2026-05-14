package model

import "fmt"

type PipelineEvent struct {
	EventType       string
	Stage           string
	Status          string
	Repository      string
	Branch          string
	CommitID        string
	PipelineName    string
	PipelineRunName string
	FailedStep      string
	ErrorMessage    string
}

func (e PipelineEvent) Validate() error {
	if e.EventType == "" {
		return fmt.Errorf("validate pipline event: %w", ErrMisssingEventType)
	}
	if e.Stage == "" {
		return fmt.Errorf("validate pipeline event: %w", ErrMissingStage)
	}

	if e.Status == "" {
		return fmt.Errorf("validate pipeline event: %w", ErrMissingStatus)
	}
	return nil
}
