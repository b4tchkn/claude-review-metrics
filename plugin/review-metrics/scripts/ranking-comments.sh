#!/bin/bash
# Review Comments Ranking
# Usage: ./ranking-comments.sh [-p period] [repo]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/collect-data.sh"

parse_args "$@"
calculate_dates "$PERIOD"
print_header "Review Comments Ranking"

collect_data

echo "Processed $PR_COUNT PRs"
echo ""

METRICS=$(cat "$METRICS_FILE")

if [[ "$METRICS" == "{}" ]]; then
  echo "No review activity this period."
  rm -f "$METRICS_FILE" "$RESPONSE_TIMES_FILE"
  exit 0
fi

echo "[Review Comments] (top contributors)"
echo "$METRICS" | jq -r 'to_entries | sort_by(-.value.comments) | .[0:3] | to_entries | .[] | "  \(.key + 1). \(.value.key): \(.value.value.comments)"'

rm -f "$METRICS_FILE" "$RESPONSE_TIMES_FILE"
