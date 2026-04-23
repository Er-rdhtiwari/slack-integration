package main

import (
	"flag"
	"fmt"

	"github.com/Er-rdhtiwari/slack-integration/internal/model"
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

	
}
