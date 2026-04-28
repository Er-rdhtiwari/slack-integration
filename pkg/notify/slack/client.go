package slack

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

type Client struct {
	httpClient *http.Client
}

func NewClient(httpClient ...*http.Client) Client {
	client := &http.Client{
		Timeout: 10 * time.Second,
	}
	if len(httpClient) > 0 && httpClient[0] != nil {
		client = httpClient[0]
	}
	return Client{
		httpClient: client,
	}
}

func (c Client) SendMessage(webhookURL string, message Message) error {
	if webhookURL == "" {
		return ErrEmptyWebhookURL
	}
	if c.httpClient == nil {
		return ErrNilHTTPClient
	}

	body, err := json.Marshal(message)
	if err != nil {
		return fmt.Errorf("marshal slack message: %w", err)
	}

	req, err := http.NewRequest(http.MethodPost, webhookURL, bytes.NewBuffer(body))
	if err != nil {
		return fmt.Errorf("create slack request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("send slack request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("slack returned non-success status code: %d", resp.StatusCode)
	}

	return nil
}

func (c Client) Send(webhookURL string, message Message) error {
	return c.SendMessage(webhookURL, message)
}
