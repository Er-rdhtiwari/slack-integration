package formatter

import (
	"fmt"

	"github.com/Er-rdhtiwari/slack-integration/pkg/notify/model"
)

func FormatSlackText(event model.PipelineEvent) string {
	return fmt.Sprintf(
		"Pipeline event: %s\nStatus: %s\nRepo: %s\nBranch: %s\nCommit: %s\nSender: %s",
		event.EventType,
		event.Status,
		event.RepoURL,
		event.Branch,
		event.CommitSHA,
		event.Author,
	)
}
