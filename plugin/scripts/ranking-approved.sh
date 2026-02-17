#!/usr/bin/env bash
# Approved PRs Ranking
# Usage: ./ranking-approved.sh [-p period] [repo]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/ranking-runner.sh"

render_approved() {
  echo "[Approved PRs] (most approvals)"
  echo "$METRICS" | jq -r 'to_entries | sort_by(-(.value.approvedPRs | length)) | .[0:3] | to_entries | .[] | "  \(.key + 1). \(.value.key): \(.value.value.approvedPRs | length)"'
}

run_ranking "Approved PRs Ranking" render_approved "$@"
