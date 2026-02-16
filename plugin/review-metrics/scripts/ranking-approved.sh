#!/bin/bash
# Approved PRs Ranking
# Usage: ./ranking-approved.sh [-p period] [repo]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/collect-data.sh"

parse_args "$@"
calculate_dates "$PERIOD"
print_header "Approved PRs Ranking"

collect_data

echo "Processed $PR_COUNT PRs"
echo ""

METRICS=$(cat "$METRICS_FILE")

if [[ "$METRICS" == "{}" ]]; then
  echo "No review activity this period."
  rm -f "$METRICS_FILE" "$RESPONSE_TIMES_FILE"
  exit 0
fi

echo "[Approved PRs] (most approvals)"
echo "$METRICS" | jq -r 'to_entries | sort_by(-(.value.approvedPRs | length)) | .[0:3] | to_entries | .[] | "  \(.key + 1). \(.value.key): \(.value.value.approvedPRs | length)"'

rm -f "$METRICS_FILE" "$RESPONSE_TIMES_FILE"
