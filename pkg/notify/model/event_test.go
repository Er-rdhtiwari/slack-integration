package model

import (
	"testing"
)

func TestPipelineEventValidate(t *testing.T) {
	tests := []struct {
		name    string
		event   PipelineEvent
		wantErr bool
	}{
		{
			name: "valid pr event",
		    event: PipelineEvent{
				EventType:    "pr",
				Stage:        "validation",
				Status:       "succeeded",
				PipelineName: "pr-check",
				},
			wantErr: false,
		},
		{
			name: "missing status",
			event: PipelineEvent{
				EventType:    "pr",
				Stage:        "validation",
				PipelineName: "pr-check",
			},
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.event.Validate()

			if tt.wantErr && err == nil {
				t.Fatalf("expected error, got nil")
			}
			if !tt.wantErr && err != nil {
				t.Fatalf("expected no error, got %v", err)
			}
		})
	}
}
