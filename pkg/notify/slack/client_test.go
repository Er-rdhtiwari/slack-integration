package slack

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestClientSendSuccess(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Fatalf("expected POST request, got %s", r.Method)
		}

		if r.Header.Get("Content-Type") != "application/json" {
			t.Fatalf("expected application/json content type")
		}

		var msg Message
		err := json.NewDecoder(r.Body).Decode(&msg)
		if err != nil {
			t.Fatalf("failed to decode request body: %v", err)
		}

		if msg.Text != "hello from test" {
			t.Fatalf("unexpected message text: %s", msg.Text)
		}

		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	client := NewClient(server.Client())

	err := client.Send(server.URL, Message{
		Text: "hello from test",
	})

	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
}
