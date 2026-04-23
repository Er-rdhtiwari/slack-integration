package parser

import (
	"errors"

	"github.com/Er-rdhtiwari/slack-integration/internal/cli"
)

type Event struct {
	User      string
	EventType string
	Repo      string
}

func BuildEvent(input cli.InputFlags) (Event, error) {
	if input.User == "" {
		return Event{}, errors.New("User is Required")
	}
	if input.Event == "" {
		return Event{}, errors.New("Event is required")
	}
	event := Event{
		User:      input.User,
		EventType: input.Event,
		Repo:      input.Repo,
	}
	return event, nil
}
