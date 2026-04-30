package status

import (
	"fmt"
	"time"
)

type PipelineStatus string

const (
	StatusRunning   PipelineStatus = "running"
	StatusSucceeded PipelineStatus = "succeeded"
	StatusFailed    PipelineStatus = "failed"
)

type PipelineTracker struct {
	PipelineName string
	EventType    string
	Stage        string
	Status       PipelineStatus
	FailedStep   string
	ErrorMessage string
	StartedAt    time.Time
	FinishedAt   time.Time
}

func NewPipelineTracker(pipelineName, eventType, stage string) PipelineTracker {
	return PipelineTracker{
		PipelineName: pipelineName,
		EventType:    eventType,
		Stage:        stage,
		Status:       StatusRunning,
		StartedAt:    time.Now(),
	}
}

func (p *PipelineTracker) MarkSucceeded() {
	p.Status = StatusSucceeded
	p.FinishedAt = time.Now()
}

func (p *PipelineTracker) MarkFailed(FailedStep, errorMessage string) {
	p.Status = StatusFailed
	p.FailedStep = FailedStep
	p.ErrorMessage = errorMessage
	p.FinishedAt = time.Now()
}

func (p PipelineTracker) IsFailed() bool {
	return p.Status == StatusFailed
}

func (p PipelineTracker) Summary() string {
	if p.IsFailed() {
		return fmt.Sprintf(
			"Pipeline %s failed at step %s: %s",
			p.PipelineName,
			p.FailedStep,
			p.ErrorMessage,
		)
	}

	return fmt.Sprintf(
		"Pipeline %s completed with status %s",
		p.PipelineName,
		p.Status,
	)
}
