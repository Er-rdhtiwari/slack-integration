package router

import (
	"errors"
	"testing"

	"github.com/Er-rdhtiwari/slack-integration/pkg/notify/model"
)

func TestWebhookFor(t *testing.T) {
	r := NewRouter(Config{
		PRWebhook: "https://example.com/pr",
		CDWebhook: "https://example.com/cd",
		// JobWebhook intentionally empty to test fallback
	})

	tests := []struct {
		name        string
		event       model.PipelineEvent
		wantWebhook string
		wantErr     bool
		wantIs      error
	}{
		{
			name: "pr event goes to pr webhook",
			event: model.PipelineEvent{
				EventType: "pr",
			},
			wantWebhook: "https://example.com/pr",
			wantErr:     false,
		},
		{
			name: "cd event goes to cd webhook",
			event: model.PipelineEvent{
				EventType: "cd",
			},
			wantWebhook: "https://example.com/cd",
			wantErr:     false,
		},
		{
			name: "job event falls back to cd webhook",
			event: model.PipelineEvent{
				EventType: "job",
			},
			wantWebhook: "https://example.com/cd",
			wantErr:     false,
		},
		{
			name: "unknown event returns error",
			event: model.PipelineEvent{
				EventType: "unknown",
			},
			wantWebhook: "",
			wantErr:     true,
			wantIs:      ErrUnknownRoute,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gotWebhook, err := r.WebhookFor(tt.event)

			if tt.wantErr && err == nil {
				t.Fatalf("expected error, got nil")
			}

			if !tt.wantErr && err != nil {
				t.Fatalf("expected no error, got %v", err)
			}
			if tt.wantIs != nil && !errors.Is(err, tt.wantIs) {
				t.Fatalf("expected error to wrap %v, got %v", tt.wantIs, err)
			}

			if gotWebhook != tt.wantWebhook {
				t.Fatalf("expected webhook %q, got %q", tt.wantWebhook, gotWebhook)
			}
		})
	}
}
