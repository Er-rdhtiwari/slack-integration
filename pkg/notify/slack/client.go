package slack

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"time"
)

type Message struct {
	Text string `json:"text"`
}

type Client struct {
	WebhookURL string
	HTTPClient *http.Client
}

func NewClient(WebhookURL string) (*Client, error) {
	if WebhookURL == "" {
		return nil, errors.New("Slack webhook URL required")
	}
	return &Client{
		WebhookURL: WebhookURL,
		HTTPClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}, nil
}

func (c *Client) SendMessage(message Message) error {
	payload, err := json.Marshal(message)
	if err != nil {
		return fmt.Errorf("fsiled to covert slack message to JSON: %w", err)
	}
	req, err := http.NewRequest(
		http.MethodPost,
		c.WebhookURL,
		bytes.NewBuffer(payload),
	)
	if err != nil {
		return fmt.Errorf("failed to create HTTP request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send request to Slack: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("slack returned non-success status code: %d", resp.StatusCode)
	}

	return nil
}
