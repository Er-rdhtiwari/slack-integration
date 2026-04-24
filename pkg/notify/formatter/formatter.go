package formatter

import (
	"fmt"

	"github.com/Er-rdhtiwari/slack-integration/pkg/notify/model"
)

func FormatSlackText(event model.PipelineEvent) string {
	statusEmoji := map[string]string{
		"success": "✅",
		"fail":    "❌",
		"running":   "⏳",
	}
	emoji, ok := statusEmoji[event.Status]
	if !ok {
		emoji = "ℹ️"
	}
	return fmt.Sprintf(
		"%s Pipeline event: %s\nStatus: %s\nRepo: %s\nBranch: %s\nCommit: %s\nSender: %s",
		emoji,
		event.EventType,
		event.Status,
		event.RepoURL,
		event.Branch,
		event.CommitSHA,
		event.Author,
	)
}
