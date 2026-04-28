#!/usr/bin/env bash
#!/usr/bin/env bash
set -euo pipefail

echo "Running gofmt check..."
gofmt -w .

echo "Running Go tests..."
go test ./...

echo "All checks completed successfully"
