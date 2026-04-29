package logger

import (
	"os"
	"strings"
	"time"

	"github.com/rs/zerolog"
)

func New(env string, logLevel ...string) zerolog.Logger {
	zerolog.TimeFieldFormat = time.RFC3339

	level := zerolog.InfoLevel

	if strings.EqualFold(env, "dev") {
		level = zerolog.DebugLevel
	}
	if len(logLevel) > 0 && logLevel[0] != "" {
		if parsedLevel, err := zerolog.ParseLevel(strings.ToLower(logLevel[0])); err == nil {
			level = parsedLevel
		}
	}

	zerolog.SetGlobalLevel(level)
	return zerolog.New(os.Stdout).
		With().
		Timestamp().
		Str("service", "slack-notifier").
		Str("env", env).
		Logger()
}
