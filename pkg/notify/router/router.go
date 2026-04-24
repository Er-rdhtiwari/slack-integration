package router

import (
	"fmt"

	"github.com/Er-rdhtiwari/slack-integration/pkg/notify/model"
)

type Config struct {
	PRWebhook      string
	CDWebhook      string
	JobWebhook     string
	DefaultWebhook string
}

type RouteResult struct {
	RouteName    string
	WebhookURL   string
	UsedFallback bool
	Reason       string
}

type Router struct {
	config Config
}

func NewRouter(config Config) Router {
	return Router{
		config: config,
	}
}

func (r Router) Resolve(event model.PipelineEvent) (RouteResult, error) {
	switch event.EventType {

	case model.EventTypePR:
		if r.config.PRWebhook == "" {
			return RouteResult{}, fmt.Errorf("PR webhook is missing")
		}
		return RouteResult{
			RouteName:  "pr",
			WebhookURL: r.config.PRWebhook,
			Reason:     "PR event routed to PR webhook",
		}, nil
	case model.EventTypeCD:
		if r.config.CDWebhook == "" {
			return RouteResult{}, fmt.Errorf("CD webhook is missing")
		}

		return RouteResult{
			RouteName:  "cd",
			WebhookURL: r.config.CDWebhook,
			Reason:     "CD event routed to CD webhook",
		}, nil
	case model.EventTypeJob:
		if r.config.JobWebhook != "" {
			return RouteResult{
				RouteName:  "job",
				WebhookURL: r.config.JobWebhook,
				Reason:     "Job event routed to Job webhook",
			}, nil
		}

		if r.config.CDWebhook != "" {
			return RouteResult{
				RouteName:    "cd",
				WebhookURL:   r.config.CDWebhook,
				UsedFallback: true,
				Reason:       "Job webhook missing, fallback to CD webhook",
			}, nil
		}
		return RouteResult{}, fmt.Errorf("job webhook missing and CD fallback webhook also missing")

	default:
		if r.config.DefaultWebhook != "" {
			return RouteResult{
				RouteName:    "default",
				WebhookURL:   r.config.DefaultWebhook,
				UsedFallback: true,
				Reason:       "Unknown event routed to default webhook",
			}, nil
		}
		return RouteResult{}, fmt.Errorf("unsupported event type: %s", event.EventType)
	}

}
