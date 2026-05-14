package failure

import (
	"encoding/json"
	"fmt"
	"strings"
)

const (
	DefaultTraceMaxLines = 30
	DefaultTraceMaxChars = 2400
)

type Context struct {
	Namespace    string `json:"namespace"`
	PipelineRun  string `json:"pipeline_run,omitempty"`
	TaskRun      string `json:"task_run"`
	Pod          string `json:"pod"`
	FailedStep   string `json:"failed_step"`
	ExitCode     string `json:"exit_code"`
	Reason       string `json:"reason"`
	ErrorMessage string `json:"error_message"`
	Trace        string `json:"trace"`
	TraceTrimmed bool   `json:"trace_trimmed"`
}

func ParseContext(raw []byte) (Context, error) {
	var ctx Context
	if err := json.Unmarshal(raw, &ctx); err != nil {
		return Context{}, fmt.Errorf("decode failure context: %w", err)
	}

	return SanitizeContext(ctx), nil
}

func SanitizeContext(ctx Context) Context {
	ctx.ErrorMessage = MaskSecrets(strings.TrimSpace(ctx.ErrorMessage))
	ctx.Trace = MaskSecrets(ctx.Trace)
	if ctx.ErrorMessage == "" {
		ctx.ErrorMessage = FindErrorMessage(ctx.Trace)
	}

	trace, trimmed := TruncateTrace(ctx.Trace, DefaultTraceMaxLines, DefaultTraceMaxChars)
	ctx.Trace = trace
	ctx.TraceTrimmed = ctx.TraceTrimmed || trimmed

	return ctx
}
