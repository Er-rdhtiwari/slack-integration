package config

import (
	"fmt"
	"os"
	"strconv"
)

type Config struct {
	AppEnv       string
	LogLevel     string
	RetryCount   int
	PRWebhookURL string
	CDWebhookURL string
}

func Load() (*Config, error) {
	cfg := &Config{
		AppEnv:       getEnv("APP_ENV", "dev"),
		LogLevel:     getEnv("LOG_LEVEL", "info"),
		PRWebhookURL: getEnv("SLACK_WEBHOOK_URL_PR", ""),
		CDWebhookURL: getEnv("SLACK_WEBHOOK_URL_CD", ""),
	}

	retryCount, err := getEnvAsInt("RETRY_COUNT", 3)
	if err != nil {
		return nil, err
	}
	cfg.RetryCount = retryCount

	return cfg, nil
}

func getEnv(key string, defaultValue string) string {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	return value
}

func getEnvAsInt(key string, defaultValue int) (int, error) {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue, nil
	}
	intValue, err := strconv.Atoi(value)
	if err != nil {
		return 0, fmt.Errorf("%s must be a valid integer: %w", key, err)
	}
	return intValue, nil
}
