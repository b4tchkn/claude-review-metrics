#!/usr/bin/env bash
# Review Comments Ranking
# Usage: ./ranking-comments.sh [-p period] [repo]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/ranking-runner.sh"

render_comments() {
  echo "[Review Comments] (top contributors)"
  echo "$METRICS" | jq -r 'to_entries | sort_by(-.value.comments) | .[0:3] | to_entries | .[] | "  \(.key + 1). \(.value.key): \(.value.value.comments)"'
}

run_ranking "Review Comments Ranking" render_comments "$@"
