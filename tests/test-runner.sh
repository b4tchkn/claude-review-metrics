#!/usr/bin/env bash
# Minimal test framework for review metrics
# Usage: bash tests/test-runner.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

_test_count=0
_test_passed=0
_test_failed=0
_failures=()

assert_eq() {
  local expected="$1" actual="$2" label="${3:-}"
  ((_test_count++)) || true
  if [[ "$expected" == "$actual" ]]; then
    ((_test_passed++)) || true
  else
    ((_test_failed++)) || true
    _failures+=("FAIL: ${label:-assertion} — expected '$expected', got '$actual'")
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" label="${3:-}"
  ((_test_count++)) || true
  if [[ "$haystack" == *"$needle"* ]]; then
    ((_test_passed++)) || true
  else
    ((_test_failed++)) || true
    _failures+=("FAIL: ${label:-assertion} — '$haystack' does not contain '$needle'")
  fi
}

assert_not_empty() {
  local value="$1" label="${2:-}"
  ((_test_count++)) || true
  if [[ -n "$value" ]]; then
    ((_test_passed++)) || true
  else
    ((_test_failed++)) || true
    _failures+=("FAIL: ${label:-assertion} — value is empty")
  fi
}

run_tests() {
  echo "Running tests..."
  echo ""

  for test_file in "$TESTS_DIR"/test-*.sh; do
    [[ "$test_file" == "$TESTS_DIR/test-runner.sh" ]] && continue
    [[ ! -f "$test_file" ]] && continue

    local name
    name=$(basename "$test_file" .sh)
    echo "  $name"

    # Source test file (it uses assert_* functions)
    source "$test_file"
  done

  echo ""
  echo "=========================================="
  echo "  Results: $_test_passed/$_test_count passed"
  if [[ $_test_failed -gt 0 ]]; then
    echo "  FAILURES: $_test_failed"
    for f in "${_failures[@]}"; do
      echo "    $f"
    done
    echo "=========================================="
    exit 1
  else
    echo "  All tests passed!"
    echo "=========================================="
  fi
}

# Auto-run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_tests
fi
