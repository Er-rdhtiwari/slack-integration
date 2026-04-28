package slack

import (
	"fmt"

	"github.com/Er-rdhtiwari/slack-integration/pkg/notify/model"
)

type Message struct {
	Text        string       `json:"text"`
	Attachments []Attachment `json:"attachments,omitempty"`
}

type Attachment struct {
	Title  string  `json:"title"`
	Color  string  `json:"color"`
	Fields []Field `json:"fields"`
}

type Field struct {
	Title string `json:"title"`
	Value string `json:"value"`
	Short bool   `json:"short"`
}

func BuildMessage(event model.PipelineEvent) Message {
	color := "good"

	if event.Status == "failed" {
		color = "danger"
	}

	fields := []Field{
		{
			Title: "Event Type",
			Value: event.EventType,
			Short: true,
		},
		{
			Title: "Stage",
			Value: event.Stage,
			Short: true,
		},
		{
			Title: "Status",
			Value: event.Status,
			Short: true,
		},
		{
			Title: "Pipeline",
			Value: event.PipelineName,
			Short: true,
		},
	}

	if event.FailedStep != "" {
		fields = append(fields, Field{
			Title: "Failed Step",
			Value: event.FailedStep,
			Short: true,
		})
	}

	if event.ErrorMessage != "" {
		fields = append(fields, Field{
			Title: "Error Message",
			Value: event.ErrorMessage,
			Short: false,
		})
	}

	return Message{
		Text: fmt.Sprintf("Pipeline %s: %s", event.Status, event.PipelineName),
		Attachments: []Attachment{
			{
				Title:  "Pipeline Notification",
				Color:  color,
				Fields: fields,
			},
		},
	}
}
