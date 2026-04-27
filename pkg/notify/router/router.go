package router

import (
	"fmt"

	"github.com/Er-rdhtiwari/slack-integration/pkg/notify/model"
)

type Config struct {
	PRWebhookURL string
	CDWebhookURL string
}

type Router struct {
	config Config
}

func NewRouter(config Config) Router {
	return Router{
		config: config,
	}
}

func (r Router) ResolveWebhook(event model.PipelineEvent) (string, error) {
	switch event.EventType {
	case "pr":
		if r.config.PRWebhookURL == "" {
			return "", fmt.Errorf("resolve pr webhook : %w", ErrMissingWebhook)
		}
		return r.config.PRWebhookURL, nil

	case "cd":
		if r.config.CDWebhookURL == "" {
			return "", fmt.Errorf("resolve cd webhook : %w", ErrMissingWebhook)
		}
		return r.config.CDWebhookURL, nil

	case "job":
		if r.config.CDWebhookURL == "" {
			return "", fmt.Errorf("resolve job fallback webhook : %w", ErrMissingWebhook)
		}
		return r.config.CDWebhookURL, nil

	default:
		return "", fmt.Errorf("event type %q: %w", event.EventType, ErrMissingWebhook)
	}
}
