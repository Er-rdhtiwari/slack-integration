package model

type NotificationRequest struct {
	Channel string
	Text    string
	Event   PipelineEvent
}
