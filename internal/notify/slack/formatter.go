package slack

import (
	"fmt"
	"strings"

	"github.com/Er-rdhtiwari/slack-integration/internal/failure"
)

type Payload struct {
	Text   string  `json:"text"`
	Blocks []Block `json:"blocks"`
}

type Block struct {
	Type string `json:"type"`
	Text *Text  `json:"text,omitempty"`
}

type Text struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

func FormatFailureMessage(f failure.Context) Payload {
	title := fmt.Sprintf(":x: Tekton task failed: `%s`", f.TaskRun)

	summary := fmt.Sprintf(
		"*Namespace:* `%s`\n*TaskRun:* `%s`\n*Failed step:* `%s`\n*Exit code:* `%s`\n*Reason:* `%s`\n*Error:* `%s`",
		emptyAsUnknown(f.Namespace),
		emptyAsUnknown(f.TaskRun),
		emptyAsUnknown(f.FailedStep),
		emptyAsUnknown(f.ExitCode),
		emptyAsUnknown(f.Reason),
		emptyAsUnknown(f.ErrorMessage),
	)

	if f.PipelineRun != "" {
		summary = fmt.Sprintf("*PipelineRun:* `%s`\n%s", f.PipelineRun, summary)
	}

	trace := strings.TrimSpace(f.Trace)
	if trace == "" {
		trace = "No trace available"
	}

	traceBlock := fmt.Sprintf("*Short trace:*\n```%s```", trace)

	if f.TraceTrimmed {
		traceBlock += "\n_Trace was trimmed to keep this Slack message readable._"
	}

	return Payload{
		Text: fmt.Sprintf("Tekton task failed: %s", f.TaskRun),
		Blocks: []Block{
			{
				Type: "section",
				Text: &Text{
					Type: "mrkdwn",
					Text: title,
				},
			},
			{
				Type: "section",
				Text: &Text{
					Type: "mrkdwn",
					Text: summary,
				},
			},
			{
				Type: "section",
				Text: &Text{
					Type: "mrkdwn",
					Text: traceBlock,
				},
			},
		},
	}
}

func emptyAsUnknown(value string) string {
	if strings.TrimSpace(value) == "" {
		return "unknown"
	}
	return value
}
