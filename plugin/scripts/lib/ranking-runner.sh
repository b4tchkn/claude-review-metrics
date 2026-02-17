#!/usr/bin/env bash
# Common runner for ranking scripts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/collect-data.sh"

# Run a ranking script with standard boilerplate
# Usage: run_ranking "Title" render_fn "$@"
run_ranking() {
  local title="$1" render_fn="$2"
  shift 2

  parse_args "$@"
  calculate_dates "$PERIOD"
  print_header "$title"

  collect_data

  echo "Processed $PR_COUNT PRs"
  echo ""

  METRICS=$(cat "$METRICS_FILE")
  RESPONSE_TIMES=$(cat "$RESPONSE_TIMES_FILE")

  if [[ "$METRICS" == "{}" && "$RESPONSE_TIMES" == "{}" ]]; then
    echo "No review activity this period."
    return
  fi

  "$render_fn"
}
