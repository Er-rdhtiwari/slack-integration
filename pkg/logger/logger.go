package logger

import (
	"os"
	"strings"
	"time"

	"github.com/rs/zerolog"
)

func New(env string) zerolog.Logger {
	zerolog.TimeFieldFormat = time.RFC3339

	level := zerolog.InfoLevel

	if strings.EqualFold(env, "dev") {
		level = zerolog.DebugLevel
	}

	zerolog.SetGlobalLevel(level)
	return zerolog.New(os.Stdout).
		With().
		Timestamp().
		Str("service", "slack-notifier").
		Str("env", env).
		Logger()
}
