#!/usr/bin/env bash
# Common runner for analysis scripts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/collect-data-extended.sh"

# Run an analysis script with standard boilerplate
# Usage: run_analysis "Title" analyze_fn "$@"
run_analysis() {
  local title="$1" analyze_fn="$2"
  shift 2

  parse_args "$@"
  calculate_dates "$PERIOD"
  print_header "$title"

  echo "Collecting PR lifecycle data..."
  collect_extended_data
  echo "Processed $EXTENDED_PR_COUNT PRs"
  echo ""

  if [[ ! -s "$PR_LIFECYCLE_FILE" ]]; then
    echo "No PR data found in this period."
    return
  fi

  "$analyze_fn"
}
