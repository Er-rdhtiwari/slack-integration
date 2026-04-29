package config

import "testing"

func TestLoadUsesDefaults(t *testing.T) {
	t.Setenv("APP_ENV", "")
	t.Setenv("LOG_LEVEL", "")
	t.Setenv("RETRY_COUNT", "")
	t.Setenv("SLACK_WEBHOOK_URL_PR", "")
	t.Setenv("SLACK_WEBHOOK_URL_CD", "")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	if cfg.AppEnv != "dev" {
		t.Fatalf("expected default app env dev, got %q", cfg.AppEnv)
	}
	if cfg.LogLevel != "info" {
		t.Fatalf("expected default log level info, got %q", cfg.LogLevel)
	}
	if cfg.RetryCount != 3 {
		t.Fatalf("expected default retry count 3, got %d", cfg.RetryCount)
	}
}

func TestLoadReadsEnvironment(t *testing.T) {
	t.Setenv("APP_ENV", "prod")
	t.Setenv("LOG_LEVEL", "warn")
	t.Setenv("RETRY_COUNT", "5")
	t.Setenv("SLACK_WEBHOOK_URL_PR", "https://example.com/pr")
	t.Setenv("SLACK_WEBHOOK_URL_CD", "https://example.com/cd")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	if cfg.AppEnv != "prod" {
		t.Fatalf("expected app env prod, got %q", cfg.AppEnv)
	}
	if cfg.LogLevel != "warn" {
		t.Fatalf("expected log level warn, got %q", cfg.LogLevel)
	}
	if cfg.RetryCount != 5 {
		t.Fatalf("expected retry count 5, got %d", cfg.RetryCount)
	}
	if cfg.PRWebhookURL != "https://example.com/pr" {
		t.Fatalf("expected PR webhook to be loaded")
	}
	if cfg.CDWebhookURL != "https://example.com/cd" {
		t.Fatalf("expected CD webhook to be loaded")
	}
}

func TestLoadRejectsInvalidRetryCount(t *testing.T) {
	t.Setenv("RETRY_COUNT", "abc")

	_, err := Load()
	if err == nil {
		t.Fatal("expected error, got nil")
	}
}
