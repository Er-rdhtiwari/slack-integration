#!/usr/bin/env bash
status="$(./scripts/capture-error/capture-error.sh -- ./scripts/capture-error/capture-error-scenarios.sh test=17)"
echo "$status"
