#!/usr/bin/env bash
# Response Time Ranking
# Usage: ./ranking-response-time.sh [-p period] [repo]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/ranking-runner.sh"

render_response_time() {
  if [[ "$RESPONSE_TIMES" == "{}" ]]; then
    echo "No response time data this period."
    return
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
}

run_ranking "Response Time Ranking" render_response_time "$@"
