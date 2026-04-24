package slack

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

type Message struct {
	Text string `json:"text"`
}

type Client struct {
	HTTPClient *http.Client
}

func NewClient() Client {
	return Client{
		HTTPClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

func (c Client) Send(webhookURL string, message Message) error {
	if webhookURL == "" {
		return fmt.Errorf("webhook URL is empty")
	}
	body, err := json.Marshal(message)
	if err != nil {
		return fmt.Errorf("failed to encode Slack message: %w", err)
	}

	req, err := http.NewRequest(http.MethodPost, webhookURL, bytes.NewBuffer(body))
	if err != nil {
		return fmt.Errorf("failed to create Slack request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send Slack request: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("Slack returned non-success status: %d", resp.StatusCode)
	}

	return nil
}
