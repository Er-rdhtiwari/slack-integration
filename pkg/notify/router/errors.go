package router

import "errors"

var (
	ErrMissingWebhook = errors.New("missing webhook configuration")
	ErrUnknownRoute   = errors.New("unknown notofication route")
)
