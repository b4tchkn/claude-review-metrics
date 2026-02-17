#!/usr/bin/env bash
# Analysis: Review Cycle Patterns
# Tracks review rounds per PR and identifies re-review patterns
# Usage: ./analysis-review-cycles.sh [OPTIONS] [REPO]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/collect-data-extended.sh"

parse_args "$@"
calculate_dates "$PERIOD"
print_header "Review Cycle Analysis"

echo "Collecting PR lifecycle data..."
collect_extended_data
echo "Processed $EXTENDED_PR_COUNT PRs"
echo ""

if [[ ! -s "$PR_LIFECYCLE_FILE" ]]; then
  echo "No PR data found in this period."
  exit 0
fi

# Temp files
CYCLES_FILE=$(mktemp)
CR_REVIEWER_FILE=$(mktemp)
CR_AUTHOR_FILE=$(mktemp)
PR_DETAIL_FILE=$(mktemp)
trap "rm -f $CYCLES_FILE $CR_REVIEWER_FILE $CR_AUTHOR_FILE $PR_DETAIL_FILE $PR_LIFECYCLE_FILE" EXIT

analyzed_count=0

while IFS= read -r pr; do
  [[ -z "$pr" ]] && continue

  state=$(echo "$pr" | jq -r '.state')
  [[ "$state" != "MERGED" ]] && continue

  number=$(echo "$pr" | jq -r '.number')
  author=$(echo "$pr" | jq -r '.author')
  title=$(echo "$pr" | jq -r '.title')

  # Count distinct review rounds
  # A "round" = a set of reviews before the next CHANGES_REQUESTED or APPROVED
  # Simplified: count the number of CHANGES_REQUESTED events as cycle count
  changes_requested_count=$(echo "$pr" | jq '[.timelineItems[] | select(.__typename == "PullRequestReview" and .state == "CHANGES_REQUESTED")] | length')
  approved_count=$(echo "$pr" | jq '[.timelineItems[] | select(.__typename == "PullRequestReview" and .state == "APPROVED")] | length')

  # Total cycles = changes_requested + 1 (the final approval round)
  if [[ $approved_count -gt 0 ]]; then
    cycles=$((changes_requested_count + 1))
  else
    cycles=$changes_requested_count
  fi

  [[ $cycles -eq 0 ]] && continue

  echo "$cycles" >> "$CYCLES_FILE"
  ((analyzed_count++)) || true

  # Track which reviewers request changes most
  echo "$pr" | jq -r '.timelineItems[] | select(.__typename == "PullRequestReview" and .state == "CHANGES_REQUESTED") | .author.login // empty' | while IFS= read -r reviewer; do
    [[ -z "$reviewer" ]] && continue
    is_bot "$reviewer" && continue
    echo "$reviewer" >> "$CR_REVIEWER_FILE"
  done

  # Track which authors get most change requests
  if [[ $changes_requested_count -gt 0 ]]; then
    for _ in $(seq 1 "$changes_requested_count"); do
      echo "$author" >> "$CR_AUTHOR_FILE"
    done
  fi

  # Track high-cycle PRs
  if [[ $cycles -ge 3 ]]; then
    display_title="$title"
    if [[ ${#display_title} -gt 45 ]]; then
      display_title="${display_title:0:42}..."
    fi
    echo "$cycles|#$number|$author|$display_title" >> "$PR_DETAIL_FILE"
  fi

done < "$PR_LIFECYCLE_FILE"

if [[ $analyzed_count -eq 0 ]]; then
  echo "No merged PRs with review data found."
  exit 0
fi

echo "[Cycle Distribution] ($analyzed_count merged PRs)"
echo ""

# Count distribution
one_cycle=$(grep -c "^1$" "$CYCLES_FILE" 2>/dev/null || true)
one_cycle=${one_cycle:-0}
two_cycles=$(grep -c "^2$" "$CYCLES_FILE" 2>/dev/null || true)
two_cycles=${two_cycles:-0}
three_cycles=$(grep -c "^3$" "$CYCLES_FILE" 2>/dev/null || true)
three_cycles=${three_cycles:-0}
four_plus=$(awk '$1 >= 4' "$CYCLES_FILE" 2>/dev/null | wc -l | tr -d ' ')
four_plus=${four_plus:-0}

one_pct=$((one_cycle * 100 / analyzed_count))
two_pct=$((two_cycles * 100 / analyzed_count))
three_pct=$((three_cycles * 100 / analyzed_count))
four_pct=$((four_plus * 100 / analyzed_count))

avg_cycles=$(awk '{ sum += $1; n++ } END { if(n>0) printf "%.1f", sum/n; else print 0 }' "$CYCLES_FILE")

echo "  1 round (approved directly): $one_cycle PRs (${one_pct}%)"
echo "  2 rounds: $two_cycles PRs (${two_pct}%)"
echo "  3 rounds: $three_cycles PRs (${three_pct}%)"
echo "  4+ rounds: $four_plus PRs (${four_pct}%)"
echo ""
echo "  Average cycles per PR: $avg_cycles"
echo ""

# Top reviewers who request changes
if [[ -s "$CR_REVIEWER_FILE" ]]; then
  echo "[Most Changes Requested By] (top reviewers)"
  echo ""
  sort "$CR_REVIEWER_FILE" | uniq -c | sort -rn | head -5 | while read -r count reviewer; do
    [[ -z "$reviewer" ]] && continue
    echo "  $reviewer: $count change requests"
  done
  echo ""
fi

# Authors who receive most change requests
if [[ -s "$CR_AUTHOR_FILE" ]]; then
  echo "[Most Changes Requested For] (authors with most re-reviews)"
  echo ""
  sort "$CR_AUTHOR_FILE" | uniq -c | sort -rn | head -5 | while read -r count author; do
    [[ -z "$author" ]] && continue
    echo "  $author: $count change requests received"
  done
  echo ""
fi

# High-cycle PRs
if [[ -s "$PR_DETAIL_FILE" ]]; then
  echo "[High-Cycle PRs] (3+ rounds)"
  echo ""
  sort -t'|' -k1 -rn "$PR_DETAIL_FILE" | head -5 | while IFS='|' read -r cycles number author title; do
    echo "  $number ($author): $cycles rounds - $title"
  done
fi
