package logger

import (
	"github.com/rs/zerolog"

	"github.com/Er-rdhtiwari/slack-integration/pkg/notify/model"
)

func WithEvent(log zerolog.Logger, event model.PipelineEvent) zerolog.Context {
	return log.With().
		Str("event_type", event.EventType).
		Str("stage", event.Stage).
		Str("status", event.Status).
		Str("repository", event.Repository).
		Str("branch", event.Branch).
		Str("commit_id", event.CommitID).
		Str("pipeline_name", event.PipelineName).
		Str("pipeline_run_name", event.PipelineRunName).
		Str("failed_step", event.FailedStep)
}
