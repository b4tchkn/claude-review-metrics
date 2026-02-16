#!/bin/bash
# Response Time Ranking
# Usage: ./ranking-response-time.sh [-p period] [repo]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/collect-data.sh"

parse_args "$@"
calculate_dates "$PERIOD"
print_header "Response Time Ranking"

collect_data

echo "Processed $PR_COUNT PRs"
echo ""

RESPONSE_TIMES=$(cat "$RESPONSE_TIMES_FILE")

if [[ "$RESPONSE_TIMES" == "{}" ]]; then
  echo "No response time data this period."
  rm -f "$METRICS_FILE" "$RESPONSE_TIMES_FILE"
  exit 0
fi

echo "[Avg Response Time] (fastest)"
echo "$RESPONSE_TIMES" | jq -r '
  to_entries |
  map(select(.value.count > 0)) |
  map({
    key: .key,
    avgSeconds: (.value.totalSeconds / .value.count),
    count: .value.count
  }) |
  sort_by(.avgSeconds) |
  .[0:3] |
  to_entries |
  .[] |
  "  \(.key + 1). \(.value.key): \((.value.avgSeconds / 3600) | floor)h \(((.value.avgSeconds % 3600) / 60) | floor)m (\(.value.count) reviews)"
'

rm -f "$METRICS_FILE" "$RESPONSE_TIMES_FILE"
