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
  local data max_val
  data=$(echo "$RESPONSE_TIMES" | jq -r '
    to_entries |
    map(select(.value.count > 0)) |
    map({
      key: .key,
      avgSeconds: ((.value.totalSeconds / .value.count) | floor),
      count: .value.count
    }) |
    sort_by(.avgSeconds) |
    .[0:3] |
    to_entries |
    .[] |
    "\(.key + 1)\t\(.value.key)\t\(.value.avgSeconds)\t\(.value.count)"')
  max_val=$(echo "$data" | tail -1 | cut -f3)
  while IFS=$'\t' read -r rank name seconds count; do
    [[ -z "$rank" ]] && continue
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    printf "  %s. %-12s %s %dh %dm (%s reviews)\n" "$rank" "$name" "$(graph_bar "$seconds" "$max_val")" "$hours" "$minutes" "$count"
  done <<< "$data"
}

run_ranking "Response Time Ranking" render_response_time "$@"
