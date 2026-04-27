package main

import (
	"errors"
	"flag"
	"os"

	applogger "github.com/Er-rdhtiwari/slack-integration/pkg/logger"
	"github.com/Er-rdhtiwari/slack-integration/pkg/notify/model"
	"github.com/Er-rdhtiwari/slack-integration/pkg/notify/router"
	"github.com/Er-rdhtiwari/slack-integration/pkg/notify/slack"
)

func main() {
	eventType := flag.String("event-type", "", "event type: pr, cd, job")
	stage := flag.String("stage", "", "pipeline stage")
	status := flag.String("status", "", "pipeline status")
	pipelineName := flag.String("pipeline-name", "", "pipeline name")
	failedStep := flag.String("failed-step", "", "failed step")
	errorMessage := flag.String("error-message", "", "error message")
	env := flag.String("env", "dev", "environment")

	flag.Parse()

	log := applogger.New(*env)

	event := model.PipelineEvent{
		EventType:    *eventType,
		Stage:        *stage,
		Status:       *status,
		PipelineName: *pipelineName,
		FailedStep:   *failedStep,
		ErrorMessage: *errorMessage,
	}

	eventLogger := applogger.WithEvent(log, event).Logger()

	eventLogger.Info().Msg("notification processing started")

	if err := event.Validate(); err != nil {
		eventLogger.Error().
			Err(err).
			Msg("pipeline event validation failed")

		os.Exit(1)
	}

	rt := router.NewRouter(router.Config{
		PRWebhookURL: os.Getenv("SLACK_WEBHOOK_URL_PR"),
		CDWebhookURL: os.Getenv("SLACK_WEBHOOK_URL_CD"),
	})

	webhookURL, err := rt.ResolveWebhook(event)
	if err != nil {
		if errors.Is(err, router.ErrMissingWebhook) {
			eventLogger.Error().
				Err(err).
				Msg("webhook configuration missing")
		} else {
			eventLogger.Error().
				Err(err).
				Msg("failed to resolve webhook")
		}

		os.Exit(1)
	}

	client := slack.NewClient()

	message := slack.Message{
		Text: "Pipeline event: " + event.EventType + " | Status: " + event.Status,
	}

	if err := client.SendMessage(webhookURL, message); err != nil {
		eventLogger.Error().
			Err(err).
			Msg("failed to send slack notification")

		os.Exit(1)
	}

	eventLogger.Info().Msg("slack notification sent successfully")

}
