# slack-integration
slack-integration

## Local testing

Set the Slack webhooks before running the notifier locally:

```bash
export SLACK_PR_WEBHOOK='https://hooks.slack.com/services/xxx/yyy/zzz'
export SLACK_CD_WEBHOOK='https://hooks.slack.com/services/xxx/yyy/zzz'
export SLACK_JOB_WEBHOOK='https://hooks.slack.com/services/xxx/yyy/zzz'
export SLACK_DEFAULT_WEBHOOK='https://hooks.slack.com/services/xxx/yyy/zzz'
```

Then run:

```bash
go run cmd/slack-notifier/main.go \
  --event-type pr \
  --status failed \
  --repository cloud-resource-onboarding \
  --branch feature/pr-check \
  --sender radheshyam
```

## Runbook

Use `pr`, `cd`, or `job` for `--event-type`.

Use `started`, `success`, or `failed` for `--status`.

Routing behavior:

- `pr` sends to `SLACK_PR_WEBHOOK`
- `cd` sends to `SLACK_CD_WEBHOOK`
- `job` sends to `SLACK_JOB_WEBHOOK`
- `job` falls back to `SLACK_CD_WEBHOOK` if `SLACK_JOB_WEBHOOK` is missing
- unknown event types fall back to `SLACK_DEFAULT_WEBHOOK` if configured

Quick verification:

- export the required webhook env vars
- run the `go run cmd/slack-notifier/main.go ...` command
- confirm the Slack message appears in the routed channel
