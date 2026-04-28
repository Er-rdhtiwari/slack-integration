#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${1:-failure-traces}"
LOG_FILE="$OUTPUT_DIR/failure.log"

mkdir -p "$OUTPUT_DIR"

echo "Collecting failure trace..."
echo "Timestamp: $(date)" > "$LOG_FILE"
echo "Project: slack-integration" >> "$LOG_FILE"
echo "Status: failed" >> "$LOG_FILE"
echo "Failed Step: unit-tests" >> "$LOG_FILE"
echo "Error: sample failure for local debugging" >> "$LOG_FILE"

echo "Failure trace saved at: $LOG_FILE"