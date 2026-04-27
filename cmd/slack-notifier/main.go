package main

import (
	"os"

	"github.com/rs/zerolog"
)

func main() {
	logger := zerolog.New(os.Stdout).With().Timestamp().Logger()

	logger.Info().
		Str("event-type", "pr").
		Str("stage", "started").
		Str("status", "running").
		Msg("pipeline notification started")
}
