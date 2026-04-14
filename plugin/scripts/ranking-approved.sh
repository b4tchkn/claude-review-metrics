#!/usr/bin/env bash
# Approved PRs Ranking
# Usage: ./ranking-approved.sh [-p period] [repo]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/ranking-runner.sh"

render_approved() {
  echo "[Approved PRs] (most approvals)"
  local data max_val
  data=$(echo "$METRICS" | jq -r '
    to_entries | sort_by(-(.value.approvedPRs | length)) | .[0:3] |
    to_entries | .[] |
    "\(.key + 1)\t\(.value.key)\t\(.value.value.approvedPRs | length)"')
  max_val=$(echo "$data" | head -1 | cut -f3)
  while IFS=$'\t' read -r rank name value; do
    [[ -z "$rank" ]] && continue
    printf "  %s. %-12s %s %s\n" "$rank" "$name" "$(graph_bar "$value" "$max_val")" "$value"
  done <<< "$data"
}

run_ranking "Approved PRs Ranking" render_approved "$@"
