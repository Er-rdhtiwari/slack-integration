#!/usr/bin/env bash
# Advanced example showing the optimized pattern for CI/Tekton integration
# Demonstrates:
# - Reusable test function
# - Status checking
# - Base64 encoding for safe transmission
# - Stop on first failure
# - Separate error message and detailed JSON trace

set -eo pipefail

# Function to run a test and check its status
# Takes test number and scenario arguments
run_test() {
  local test_number="$1"
  local scenario_args="$2"
  
  # Build the full command with the capture-error wrapper
  local full_command="./scripts/capture-error/capture-error.sh --stdout true -- ./scripts/capture-error/capture-error-scenarios.sh ${scenario_args}"
  
  echo "Running: Test:${test_number}  ${full_command}"
  local test_status
  test_status="$(eval "${full_command}" || true)"
  echo "$test_status"
  
  # Check test status
  if echo "$test_status" | grep -q '"status": "success"'; then
    echo "✓ Test ${test_number}: SUCCESS"
    return 0
  else
    echo "✗ Test ${test_number}: FAILED"
    
    # Extract simple error message
    local error_message="Script execution failed: ${full_command}"
    echo "Error Message: ${error_message}"
    
    # Base64 encode the full JSON for safe transmission
    local encoded_json
    encoded_json=$(echo "$test_status" | base64 -w 0 2>/dev/null || echo "$test_status" | base64)
    
    echo "Base64 Encoded JSON: BASE64:${encoded_json}"
    
    # In a real CI/Tekton scenario, you would write these to result files:
    # echo -n "${error_message}" > /path/to/error-message.txt
    # echo -n "BASE64:${encoded_json}" > /path/to/error-trace.txt
    
    return 1
  fi
}

# Example: Run multiple tests, stop on first failure
echo "======================================"
echo "Running validation tests"
echo "======================================"

exit_code=0

# Run tests - will stop on first failure due to set -e
run_test "5" "test=5" || exit_code=$?
run_test "20" "test=20" || exit_code=$?
run_test "6" "test=6" || exit_code=$?

if [ "$exit_code" -eq 0 ]; then
  echo ""
  echo "======================================"
  echo "✓ All tests passed successfully"
  echo "======================================"
else
  echo ""
  echo "======================================"
  echo "✗ Tests failed with exit code: ${exit_code}"
  echo "======================================"
fi

exit "$exit_code"
