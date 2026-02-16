#!/usr/bin/env bash
# Analysis: Stuck PR Detection
# Identifies open PRs that need immediate attention
# Usage: ./analysis-stuck-prs.sh [REPO]
# Note: Does not accept --period; always shows current state

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/collect-data-extended.sh"

# Parse args but override period (stuck-prs always shows current state)
parse_args "$@"
PERIOD_LABEL="Current State"

NOW_TS=$(date +%s)
THRESHOLD_24H=$((24 * 3600))
THRESHOLD_5D=$((5 * 86400))

echo "=========================================="
echo "  Stuck PR Detection - Current State"
echo "=========================================="
echo "Repository: $REPO"
echo ""

echo "Collecting open PRs..."
collect_open_prs
echo "Open PRs found: $OPEN_PR_COUNT (excluding drafts)"
echo ""

if [[ ! -s "$OPEN_PRS_FILE" ]]; then
  echo "No open PRs found."
  exit 0
fi

# Temp files for categorization
WAITING_FILE=$(mktemp)
CHANGES_REQ_FILE=$(mktemp)
LONG_RUNNING_FILE=$(mktemp)
trap "rm -f $WAITING_FILE $CHANGES_REQ_FILE $LONG_RUNNING_FILE $OPEN_PRS_FILE" EXIT

while IFS= read -r pr; do
  [[ -z "$pr" ]] && continue

  number=$(echo "$pr" | jq -r '.number')
  title=$(echo "$pr" | jq -r '.title')
  author=$(echo "$pr" | jq -r '.author')
  created_at=$(echo "$pr" | jq -r '.createdAt')
  updated_at=$(echo "$pr" | jq -r '.updatedAt')

  created_ts=$(iso_to_ts "$created_at")
  updated_ts=$(iso_to_ts "$updated_at")
  age_seconds=$((NOW_TS - created_ts))
  idle_seconds=$((NOW_TS - updated_ts))

  # Truncate title for display
  display_title="$title"
  if [[ ${#display_title} -gt 50 ]]; then
    display_title="${display_title:0:47}..."
  fi

  # Get timeline events
  reviews=$(echo "$pr" | jq -c '[.timelineItems[] | select(.__typename == "PullRequestReview")]')
  review_requests=$(echo "$pr" | jq -c '[.timelineItems[] | select(.__typename == "ReviewRequestedEvent")]')
  commits=$(echo "$pr" | jq -c '[.timelineItems[] | select(.__typename == "PullRequestCommit")]')

  # Check: Has review requests but no reviews yet (waiting for review > 24h)
  request_count=$(echo "$review_requests" | jq 'length')
  review_count=$(echo "$reviews" | jq 'length')

  if [[ $request_count -gt 0 && $review_count -eq 0 ]]; then
    # Find earliest review request
    earliest_request=$(echo "$review_requests" | jq -r '[.[].createdAt] | sort | first')
    request_ts=$(iso_to_ts "$earliest_request")
    wait_seconds=$((NOW_TS - request_ts))

    if [[ $wait_seconds -ge $THRESHOLD_24H ]]; then
      pending_reviewers=$(echo "$pr" | jq -r '[.reviewRequests[] // empty] | join(", ")')
      echo "$wait_seconds|#$number|$author|$(format_duration $wait_seconds)|$pending_reviewers|$display_title" >> "$WAITING_FILE"
    fi
  fi

  # Check: Changes Requested with no subsequent commit
  last_changes_requested=$(echo "$reviews" | jq -r '[.[] | select(.state == "CHANGES_REQUESTED") | .createdAt] | sort | last // empty')
  if [[ -n "$last_changes_requested" ]]; then
    cr_ts=$(iso_to_ts "$last_changes_requested")
    last_commit=$(echo "$commits" | jq -r '[.[].commit.committedDate] | sort | last // empty')

    needs_fix=false
    if [[ -z "$last_commit" ]]; then
      needs_fix=true
    else
      last_commit_ts=$(iso_to_ts "$last_commit")
      if [[ $last_commit_ts -le $cr_ts ]]; then
        needs_fix=true
      fi
    fi

    if [[ "$needs_fix" == "true" ]]; then
      wait_since=$((NOW_TS - cr_ts))
      reviewer=$(echo "$reviews" | jq -r '[.[] | select(.state == "CHANGES_REQUESTED")] | last | .author.login // "unknown"')
      echo "$wait_since|#$number|$author|$(format_duration $wait_since)|$reviewer|$display_title" >> "$CHANGES_REQ_FILE"
    fi
  fi

  # Check: Long running PRs (> 5 days old)
  if [[ $age_seconds -ge $THRESHOLD_5D ]]; then
    additions=$(echo "$pr" | jq -r '.additions // 0')
    deletions=$(echo "$pr" | jq -r '.deletions // 0')
    total_lines=$((additions + deletions))
    size=$(classify_pr_size $total_lines)
    echo "$age_seconds|#$number|$author|$(format_duration $age_seconds)|$size (+$additions/-$deletions)|$display_title" >> "$LONG_RUNNING_FILE"
  fi

done < "$OPEN_PRS_FILE"

# Display results
found_issues=false

if [[ -s "$WAITING_FILE" ]]; then
  found_issues=true
  count=$(wc -l < "$WAITING_FILE" | tr -d ' ')
  echo "[Waiting for Review > 24h] ($count PRs)"
  echo ""
  sort -t'|' -k1 -rn "$WAITING_FILE" | while IFS='|' read -r _ number author wait_time reviewers title; do
    echo "  $number ($author): waiting $wait_time"
    [[ -n "$reviewers" ]] && echo "    Pending reviewers: $reviewers"
    echo "    $title"
  done
  echo ""
fi

if [[ -s "$CHANGES_REQ_FILE" ]]; then
  found_issues=true
  count=$(wc -l < "$CHANGES_REQ_FILE" | tr -d ' ')
  echo "[Changes Requested - No Fix Commit] ($count PRs)"
  echo ""
  sort -t'|' -k1 -rn "$CHANGES_REQ_FILE" | while IFS='|' read -r _ number author wait_time reviewer title; do
    echo "  $number ($author): waiting $wait_time since changes requested by $reviewer"
    echo "    $title"
  done
  echo ""
fi

if [[ -s "$LONG_RUNNING_FILE" ]]; then
  found_issues=true
  count=$(wc -l < "$LONG_RUNNING_FILE" | tr -d ' ')
  echo "[Long Running PRs > 5 days] ($count PRs)"
  echo ""
  sort -t'|' -k1 -rn "$LONG_RUNNING_FILE" | while IFS='|' read -r _ number author age size title; do
    echo "  $number ($author): open for $age [$size]"
    echo "    $title"
  done
  echo ""
fi

if [[ "$found_issues" == "false" ]]; then
  echo "No stuck PRs detected. All PRs are moving well!"
fi
