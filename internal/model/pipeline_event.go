package model

import (
	"errors"
	"fmt"
	"strings"
)

type PipelineEvent struct {
	EventType string
	Status    string
	RepoURL   string
	Branch    string
	CommitSHA string
	Author    string
	Message   string
}

// Normalize: changes the original struct.
func (e *PipelineEvent) Normalize() {
	e.EventType = strings.TrimSpace(strings.ToLower(e.EventType))
	e.Status = strings.TrimSpace(strings.ToLower(e.Status))
	e.RepoURL = strings.TrimSpace(e.RepoURL)
	e.Branch = strings.TrimSpace(e.Branch)
	e.CommitSHA = strings.TrimSpace(e.CommitSHA)
	e.Author = strings.TrimSpace(strings.ToLower(e.Author))
	e.Message = strings.TrimSpace(e.Message)
}

// # Validation only reads values, it does not change them.
func (e PipelineEvent) Validate() error {
	if e.EventType == "" {
		return errors.New("event type is required")
	}
	if e.Status == "" {
		return errors.New("Status is required")
	}
	if e.RepoURL == "" {
		return errors.New("RepoURL is required")
	}

	allowedSatus := map[string]bool{
		"started": true,
		"success": true,
		"failed":  true,
	}

	if !allowedSatus[e.Status] {
		return fmt.Errorf("invalid status: %s", e.Status)
	}

	return nil
}
