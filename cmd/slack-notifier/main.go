package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/Er-rdhtiwari/slack-integration/internal/failure"
	failureslack "github.com/Er-rdhtiwari/slack-integration/internal/notify/slack"
	"github.com/Er-rdhtiwari/slack-integration/pkg/config"
	applogger "github.com/Er-rdhtiwari/slack-integration/pkg/logger"
	notifymodel "github.com/Er-rdhtiwari/slack-integration/pkg/notify/model"
	"github.com/Er-rdhtiwari/slack-integration/pkg/notify/router"
	notifyslack "github.com/Er-rdhtiwari/slack-integration/pkg/notify/slack"
	pipelinestatus "github.com/Er-rdhtiwari/slack-integration/pkg/status"
)

func main() {
	eventType := flag.String("event-type", "", "event type: pr, cd, job")
	stage := flag.String("stage", "", "pipeline stage")
	status := flag.String("status", "", "pipeline status")
	pipelineName := flag.String("pipeline-name", "", "pipeline name")
	failedStep := flag.String("failed-step", "", "failed step")
	errorMessage := flag.String("error-message", "", "error message")
	env := flag.String("env", "", "environment")
	failureContextFile := flag.String("failure-context-file", "", "path to Tekton failure context JSON, or - for stdin")
	failureContextJSON := flag.String("failure-context-json", "", "Tekton failure context JSON string")
	dryRun := flag.Bool("dry-run", false, "print the Slack payload without sending it")

	flag.Parse()

	cfg, configErr := config.Load()
	logEnv := "dev"
	logLevel := ""
	if cfg != nil {
		logEnv = cfg.AppEnv
		logLevel = cfg.LogLevel
	}
	if *env != "" {
		logEnv = *env
	}

	log := applogger.New(logEnv, logLevel)

	failureContext, hasFailureContext, err := loadFailureContext(*failureContextFile, *failureContextJSON)
	if err != nil {
		log.Error().
			Err(err).
			Msg("failure context loading failed")

		os.Exit(1)
	}

	if hasFailureContext {
		applyFailureDefaults(failureContext, eventType, stage, status, pipelineName, failedStep, errorMessage)
	}
	*errorMessage = failure.MaskSecrets(strings.TrimSpace(*errorMessage))

	event := notifymodel.PipelineEvent{
		EventType:    *eventType,
		Stage:        *stage,
		Status:       *status,
		PipelineName: *pipelineName,
		FailedStep:   *failedStep,
		ErrorMessage: *errorMessage,
	}
	if hasFailureContext {
		event.PipelineRunName = failureContext.PipelineRun
	}

	eventLogger := applogger.WithEvent(log, event).Logger()

	eventLogger.Info().Msg("notification processing started")

	if configErr != nil {
		eventLogger.Error().
			Err(configErr).
			Msg("configuration loading failed")

		os.Exit(1)
	}

	if err := event.Validate(); err != nil {
		eventLogger.Error().
			Err(err).
			Msg("pipeline event validation failed")

		os.Exit(1)
	}

	var payload any
	if hasFailureContext {
		payload = failureslack.FormatFailureMessage(failureContext)
	} else {
		payload = notifyslack.BuildMessage(event)
	}

	if *dryRun {
		if err := writeDryRunPayload(os.Stdout, payload); err != nil {
			eventLogger.Error().
				Err(err).
				Msg("failed to write dry-run payload")

			os.Exit(1)
		}

		eventLogger.Info().Msg("dry run completed")
		return
	}

	rt := router.NewRouter(router.Config{
		PRWebhookURL: cfg.PRWebhookURL,
		CDWebhookURL: cfg.CDWebhookURL,
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

	client := notifyslack.NewClient()

	if err := client.SendPayload(webhookURL, payload); err != nil {
		eventLogger.Error().
			Err(err).
			Msg("failed to send slack notification")

		os.Exit(1)
	}

	eventLogger.Info().Msg("slack notification sent successfully")
}

func writeDryRunPayload(w io.Writer, payload any) error {
	encoder := json.NewEncoder(w)
	encoder.SetIndent("", "  ")
	return encoder.Encode(payload)
}

func loadFailureContext(filePath, rawJSON string) (failure.Context, bool, error) {
	if strings.TrimSpace(filePath) == "" && strings.TrimSpace(rawJSON) == "" {
		return failure.Context{}, false, nil
	}
	if strings.TrimSpace(filePath) != "" && strings.TrimSpace(rawJSON) != "" {
		return failure.Context{}, false, fmt.Errorf("use only one of --failure-context-file or --failure-context-json")
	}

	var raw []byte
	var err error
	if strings.TrimSpace(rawJSON) != "" {
		raw = []byte(rawJSON)
	} else if filePath == "-" {
		raw, err = io.ReadAll(os.Stdin)
	} else {
		raw, err = os.ReadFile(filePath)
	}
	if err != nil {
		return failure.Context{}, false, fmt.Errorf("read failure context: %w", err)
	}

	ctx, err := failure.ParseContext(raw)
	if err != nil {
		return failure.Context{}, false, err
	}

	return ctx, true, nil
}

func applyFailureDefaults(
	ctx failure.Context,
	eventType *string,
	stage *string,
	status *string,
	pipelineName *string,
	failedStep *string,
	errorMessage *string,
) {
	if strings.TrimSpace(*eventType) == "" {
		*eventType = "job"
	}
	if strings.TrimSpace(*stage) == "" {
		*stage = "tekton"
	}
	if strings.TrimSpace(*status) == "" {
		*status = string(pipelinestatus.StatusFailed)
	}
	if strings.TrimSpace(*pipelineName) == "" {
		*pipelineName = firstNonEmpty(ctx.PipelineRun, ctx.TaskRun, "tekton-task")
	}
	if strings.TrimSpace(*failedStep) == "" {
		*failedStep = ctx.FailedStep
	}
	if strings.TrimSpace(*errorMessage) == "" {
		*errorMessage = ctx.ErrorMessage
	}
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}
