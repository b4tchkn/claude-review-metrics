#!/usr/bin/env bash
# Review Metrics Collection Script - All Rankings
# Usage: ./collect-metrics.sh [OPTIONS] [REPO]
# Options:
#   --period=<week|last-week|month>  Analysis period (default: week)
#   -p <period>                       Short form of --period
#
# Examples:
#   ./collect-metrics.sh                           # Current week, auto-detect repo
#   ./collect-metrics.sh --period=last-week        # Last week
#   ./collect-metrics.sh -p month                  # Last 30 days
#   ./collect-metrics.sh -p week owner/repo          # Current week, specific repo
#
# Individual ranking scripts:
#   ./ranking-comments.sh       # Review comments ranking only
#   ./ranking-reviewed.sh       # Reviewed PRs ranking only
#   ./ranking-approved.sh       # Approved PRs ranking only
#   ./ranking-response-time.sh  # Response time ranking only

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/collect-data.sh"

parse_args "$@"
calculate_dates "$PERIOD"
print_header "Review Metrics"

collect_data

echo "Processed $PR_COUNT PRs"
echo ""

METRICS=$(cat "$METRICS_FILE")
RESPONSE_TIMES=$(cat "$RESPONSE_TIMES_FILE")

if [[ "$METRICS" == "{}" ]]; then
  echo "No review activity this period."
  exit 0
fi

echo "========== Rankings =========="

echo ""
echo "[Review Comments] (top contributors)"
echo "$METRICS" | jq -r 'to_entries | sort_by(-.value.comments) | .[0:3] | to_entries | .[] | "  \(.key + 1). \(.value.key): \(.value.value.comments)"'

echo ""
echo "[Reviewed PRs] (most active)"
echo "$METRICS" | jq -r 'to_entries | sort_by(-(.value.reviewedPRs | length)) | .[0:3] | to_entries | .[] | "  \(.key + 1). \(.value.key): \(.value.value.reviewedPRs | length)"'

echo ""
echo "[Approved PRs] (most approvals)"
echo "$METRICS" | jq -r 'to_entries | sort_by(-(.value.approvedPRs | length)) | .[0:3] | to_entries | .[] | "  \(.key + 1). \(.value.key): \(.value.value.approvedPRs | length)"'

if [[ "$RESPONSE_TIMES" != "{}" ]]; then
  echo ""
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
fi

# Note: For fix time ranking, run: ./ranking-fix-time.sh -p $PERIOD
