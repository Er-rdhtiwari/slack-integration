package main

import (
	"flag"
	"fmt"
	"log"
	"os"

	"github.com/Er-rdhtiwari/slack-integration/pkg/notify/model"
	"github.com/Er-rdhtiwari/slack-integration/pkg/notify/router"
	"github.com/Er-rdhtiwari/slack-integration/pkg/notify/slack"
)

func main() {
	eventType := flag.String("event", "", "event type like pipeline or pr")
	eventTypeAlt := flag.String("event-type", "", "event type like pr, cd, job")
	status := flag.String("status", "", "status like started, success, failed")
	repoURL := flag.String("repo", "", "repository URL")
	repoURLAlt := flag.String("repository", "", "repository name or URL")
	branch := flag.String("branch", "", "branch name")
	commitSHA := flag.String("sha", "", "commit sha")
	author := flag.String("author", "", "author name")
	authorAlt := flag.String("sender", "", "sender name")
	customMessage := flag.String("message", "", "custom message")
	flag.Parse()

	resolvedEventType := firstNonEmpty(*eventType, *eventTypeAlt)
	resolvedRepoURL := firstNonEmpty(*repoURL, *repoURLAlt)
	resolvedAuthor := firstNonEmpty(*author, *authorAlt)

	event := model.PipelineEvent{
		EventType: resolvedEventType,
		Status:    *status,
		RepoURL:   resolvedRepoURL,
		Branch:    *branch,
		CommitSHA: *commitSHA,
		Author:    resolvedAuthor,
		Message:   *customMessage,
	}
	event.Normalize()

	if err := event.Validate(); err != nil {
		log.Fatalf("invalid event: %v", err)
	}

	routeConfig := router.Config{
		PRWebhook:      os.Getenv("SLACK_PR_WEBHOOK"),
		CDWebhook:      os.Getenv("SLACK_CD_WEBHOOK"),
		JobWebhook:     os.Getenv("SLACK_JOB_WEBHOOK"),
		DefaultWebhook: os.Getenv("SLACK_DEFAULT_WEBHOOK"),
	}

	eventRouter := router.NewRouter(routeConfig)

	route, err := eventRouter.Resolve(event)
	if err != nil {
		log.Fatalf("failed to resolve route: %v", err)
	}

	slackMessage := slack.Message{
		Text: fmt.Sprintf(
			"Event: %s\nStatus: %s\nRepo: %s\nBranch: %s\nAuthor: %s\nRoute: %s\nFallback: %t\nReason: %s",
			event.EventType,
			event.Status,
			event.RepoURL,
			event.Branch,
			event.Author,
			route.RouteName,
			route.UsedFallback,
			route.Reason,
		),
	}

	client := slack.NewClient()

	if err := client.Send(route.WebhookURL, slackMessage); err != nil {
		log.Fatalf("failed to send Slack message: %v", err)
	}

	log.Println("Slack notification sent successfully")
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}
