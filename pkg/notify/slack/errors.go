package slack

import "errors"

var (
	ErrEmptyWebhookURL = errors.New("webhook URL is empty")
	ErrNilHTTPClient   = errors.New("http client is nil")
)
