package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/Er-rdhtiwari/slack-integration/pkg/notify/formatter"
	"github.com/Er-rdhtiwari/slack-integration/pkg/notify/model"
	"github.com/Er-rdhtiwari/slack-integration/pkg/notify/slack"
)

func main() {
	eventType := flag.String("event", "", "event type like pipeline or pr")
	status := flag.String("status", "", "status like started, success, failed")
	repoURL := flag.String("repo", "", "repository URL")
	branch := flag.String("branch", "", "branch name")
	commitSHA := flag.String("sha", "", "commit sha")
	author := flag.String("author", "", "author name")
	message := flag.String("message", "", "custom message")

	flag.Parse()

	event := model.PipelineEvent{
		EventType: *eventType,
		Status:    *status,
		RepoURL:   *repoURL,
		Branch:    *branch,
		CommitSHA: *commitSHA,
		Author:    *author,
		Message:   *message,
	}

	event.Normalize()

	err := event.Validate()
	if err != nil {
		fmt.Println("validation error:", err)
		return
	}

	fmt.Println("event created successfully")
	fmt.Printf("%+v\n", event)

	webhookURL := os.Getenv("SLACK_WEBHOOK_URL")

	if webhookURL == "" {
		fmt.Fprintln(os.Stderr, "SLACK_WEBHOOK_URL is required")
    	os.Exit(1)
	}

	text := formatter.FormatSlackText(event)

	client, err := slack.NewClient(webhookURL)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}

	err = client.SendMessage(slack.Message{
		Text: text,
	})
	if err != nil {
		fmt.Println("Error:", err)
		return
	}

	fmt.Println("Slack notification sent successfully")

}
