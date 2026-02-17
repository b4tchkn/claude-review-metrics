#!/usr/bin/env bash
# Reviewed PRs Ranking
# Usage: ./ranking-reviewed.sh [-p period] [repo]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/ranking-runner.sh"

render_reviewed() {
  echo "[Reviewed PRs] (most active)"
  echo "$METRICS" | jq -r 'to_entries | sort_by(-(.value.reviewedPRs | length)) | .[0:3] | to_entries | .[] | "  \(.key + 1). \(.value.key): \(.value.value.reviewedPRs | length)"'
}

run_ranking "Reviewed PRs Ranking" render_reviewed "$@"
