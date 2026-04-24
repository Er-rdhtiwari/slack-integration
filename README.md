# slack-integration
slack-integration

## Local testing

Set the Slack webhook before running the notifier locally:

```bash
export SLACK_WEBHOOK_URL='https://hooks.slack.com/services/xxx/yyy/zzz'
```

Then run:

```bash
go run cmd/slack-notifier/main.go \
  --event pipeline \
  --status success \
  --repo https://github.com/example/repo \
  --branch main \
  --sha abc123 \
  --author radhe \
  --message "build passed"
```
