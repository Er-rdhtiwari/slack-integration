#!/usr/bin/env bash

# scripts/capture-error/check-deps.sh
# Validates runtime dependencies needed by scripts/capture-error/capture-error.sh.

set -u

missing=()
failed=()
fallback_missing=()

require_command() {
  local name="$1"

  if ! command -v "$name" >/dev/null 2>&1; then
    missing+=("$name")
  fi
}

require_fallback_command() {
  local name="$1"

  if ! command -v "$name" >/dev/null 2>&1; then
    fallback_missing+=("$name")
  fi
}

require_command bash
require_command date
require_command mktemp
require_command rm
require_command kill
require_command sleep
require_command wc

require_fallback_command awk
require_fallback_command dd
require_fallback_command grep
require_fallback_command sed
require_fallback_command tr

python_available=false

if command -v python3 >/dev/null 2>&1; then
  python_available=true
fi

if command -v python3 >/dev/null 2>&1; then
  if ! python3 - <<'PY' >/dev/null 2>&1
import json
import pathlib
import re
import shlex
import sys
import time
PY
  then
    failed+=("python3 standard-library modules: json pathlib re shlex sys time")
    python_available=false
  fi
fi

if command -v mktemp >/dev/null 2>&1; then
  tmpdir="$(mktemp -d 2>/dev/null)"

  if [ -z "${tmpdir:-}" ] || [ ! -d "$tmpdir" ]; then
    failed+=("mktemp could not create a temporary directory")
  else
    rm -rf "$tmpdir"
  fi
fi

json_array() {
  local first=true
  local item

  printf '['
  for item in "$@"; do
    if [ "$first" = true ]; then
      first=false
    else
      printf ', '
    fi

    json_string "$item"
  done
  printf ']'
}

json_string() {
  local value="$1"
  local escaped=""
  local i
  local char

  for ((i = 0; i < ${#value}; i++)); do
    char="${value:i:1}"
    case "$char" in
      '"')
        escaped="${escaped}\\\""
        ;;
      "\\")
        escaped="${escaped}\\\\"
        ;;
      $'\b')
        escaped="${escaped}\\b"
        ;;
      $'\f')
        escaped="${escaped}\\f"
        ;;
      $'\n')
        escaped="${escaped}\\n"
        ;;
      $'\r')
        escaped="${escaped}\\r"
        ;;
      $'\t')
        escaped="${escaped}\\t"
        ;;
      *)
        escaped="${escaped}${char}"
        ;;
    esac
  done

  printf '"%s"' "$escaped"
}

json_install_hints() {
  local first=true
  local item
  local hint

  printf '{'
  for item in "$@"; do
    case "$item" in
      bash)
        hint="Install bash with your OS package manager."
        ;;
      awk|date|dd|grep|kill|mktemp|rm|sed|sleep|tr|wc)
        hint="Install coreutils or your OS base utilities."
        ;;
      python3)
        hint="Install Python 3."
        ;;
      *)
        hint="Install this dependency."
        ;;
    esac

    if [ "$first" = true ]; then
      first=false
    else
      printf ', '
    fi

    json_string "$item"
    printf ': '
    json_string "$hint"
  done
  printf '}'
}

if [ "${#missing[@]}" -eq 0 ] && [ "${#failed[@]}" -eq 0 ]; then
  if [ "$python_available" = false ] && [ "${#fallback_missing[@]}" -gt 0 ]; then
    success=false
    status="failed"
    exit_code=1
  else
    success=true
    status="success"
    exit_code=0
  fi
else
  success=false
  status="failed"
  exit_code=1
fi

if [ "$python_available" = false ] && [ "${#fallback_missing[@]}" -gt 0 ]; then
  missing+=("${fallback_missing[@]}")
fi

printf '{\n'
printf '  "success": %s,\n' "$success"
printf '  "status": "%s",\n' "$status"
printf '  "missing": '
if [ "${#missing[@]}" -eq 0 ]; then
  json_array
else
  json_array "${missing[@]}"
fi
printf ',\n'
printf '  "failed_checks": '
if [ "${#failed[@]}" -eq 0 ]; then
  json_array
else
  json_array "${failed[@]}"
fi
printf ',\n'
printf '  "python_available": %s,\n' "$python_available"
printf '  "fallback_missing": '
if [ "${#fallback_missing[@]}" -eq 0 ]; then
  json_array
else
  json_array "${fallback_missing[@]}"
fi
printf ',\n'
if [ "${#fallback_missing[@]}" -eq 0 ]; then
  printf '  "fallback_available": true,\n'
else
  printf '  "fallback_available": false,\n'
fi
printf '  "install_hints": '
if [ "${#missing[@]}" -eq 0 ]; then
  json_install_hints
else
  json_install_hints "${missing[@]}"
fi
printf '\n}\n'

exit "$exit_code"
