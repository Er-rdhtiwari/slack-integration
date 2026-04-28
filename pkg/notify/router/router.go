package router

import (
	"fmt"

	"github.com/Er-rdhtiwari/slack-integration/pkg/notify/model"
)

type Config struct {
	PRWebhookURL string
	CDWebhookURL string
	PRWebhook    string
	CDWebhook    string
}

type Router struct {
	config Config
}

func NewRouter(config Config) Router {
	return Router{
		config: config,
	}
}

func (r Router) prWebhook() string {
	if r.config.PRWebhookURL != "" {
		return r.config.PRWebhookURL
	}
	return r.config.PRWebhook
}

func (r Router) cdWebhook() string {
	if r.config.CDWebhookURL != "" {
		return r.config.CDWebhookURL
	}
	return r.config.CDWebhook
}

func (r Router) ResolveWebhook(event model.PipelineEvent) (string, error) {
	switch event.EventType {
	case "pr":
		webhook := r.prWebhook()
		if webhook == "" {
			return "", fmt.Errorf("resolve pr webhook : %w", ErrMissingWebhook)
		}
		return webhook, nil

	case "cd":
		webhook := r.cdWebhook()
		if webhook == "" {
			return "", fmt.Errorf("resolve cd webhook : %w", ErrMissingWebhook)
		}
		return webhook, nil

	case "job":
		webhook := r.cdWebhook()
		if webhook == "" {
			return "", fmt.Errorf("resolve job fallback webhook : %w", ErrMissingWebhook)
		}
		return webhook, nil

	default:
		return "", fmt.Errorf("event type %q: %w", event.EventType, ErrUnknownRoute)
	}
}

func (r Router) WebhookFor(event model.PipelineEvent) (string, error) {
	return r.ResolveWebhook(event)
}
