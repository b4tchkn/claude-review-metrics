#!/usr/bin/env bash
# Unified dispatch script for review metrics
# Usage: ./dispatch.sh [period] [command] [repo]
#
# Period: week (default) | last-week | month
# Command: (empty)=all rankings | comments | reviewed | approved |
#          response-time | fix-time | bottleneck | stuck |
#          reviewer-load | cycles | pr-size

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

period="week"
command=""
repo=""

# Parse arguments: [period] [command] [repo]
for arg in "$@"; do
  case "$arg" in
    week|last-week|month)
      period="$arg"
      ;;
    comments|reviewed|approved|response-time|fix-time|\
    bottleneck|stuck|reviewer-load|cycles|pr-size)
      command="$arg"
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    *)
      repo="$arg"
      ;;
  esac
done

# Build args for the target script
args=(-p "$period")
[[ -n "$repo" ]] && args+=("$repo")

# Resolve script path
case "${command:-all}" in
  all)           script="$SCRIPT_DIR/collect-metrics.sh" ;;
  comments)      script="$SCRIPT_DIR/ranking-comments.sh" ;;
  reviewed)      script="$SCRIPT_DIR/ranking-reviewed.sh" ;;
  approved)      script="$SCRIPT_DIR/ranking-approved.sh" ;;
  response-time) script="$SCRIPT_DIR/ranking-response-time.sh" ;;
  fix-time)      script="$SCRIPT_DIR/ranking-fix-time.sh" ;;
  bottleneck)    script="$SCRIPT_DIR/analysis-bottleneck.sh" ;;
  stuck)         script="$SCRIPT_DIR/analysis-stuck-prs.sh"; args=(); [[ -n "$repo" ]] && args=("$repo") ;;
  reviewer-load) script="$SCRIPT_DIR/analysis-reviewer-load.sh" ;;
  cycles)        script="$SCRIPT_DIR/analysis-review-cycles.sh" ;;
  pr-size)       script="$SCRIPT_DIR/analysis-pr-size.sh" ;;
  *)
    echo "Unknown command: $command"
    echo "Available: comments, reviewed, approved, response-time, fix-time,"
    echo "           bottleneck, stuck, reviewer-load, cycles, pr-size"
    exit 1
    ;;
esac

if [[ "${DRY_RUN:-}" == "true" ]]; then
  echo "$script ${args[*]+"${args[*]}"}"
  exit 0
fi

exec bash "$script" ${args[@]+"${args[@]}"}
