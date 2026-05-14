package model

import "errors"

var (
	ErrMisssingEventType = errors.New("missing event type")
	ErrMissingStage      = errors.New("missing stage")
	ErrMissingStatus     = errors.New("missing sattus")
	ErrInvalidEvent      = errors.New("invalid pipeline event")
)
