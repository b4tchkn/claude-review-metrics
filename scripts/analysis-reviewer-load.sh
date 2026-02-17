#!/usr/bin/env bash
# Analysis: Reviewer Load Distribution
# Shows full team review workload and identifies imbalances
# Usage: ./analysis-reviewer-load.sh [OPTIONS] [REPO]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/analysis-runner.sh"

analyze_reviewer_load() {
  # Temp files for per-reviewer metrics
  REQUESTED_FILE=$(make_tmpfile)
  COMPLETED_FILE=$(make_tmpfile)
  RESPONSE_FILE=$(make_tmpfile)
  PENDING_FILE=$(make_tmpfile)

  while IFS= read -r pr; do
    [[ -z "$pr" ]] && continue

    # Count review requests per reviewer
    echo "$pr" | jq -r '.timelineItems[] | select(.__typename == "ReviewRequestedEvent") | .requestedReviewer.login // empty' | while IFS= read -r reviewer; do
      [[ -z "$reviewer" ]] && continue
      is_bot "$reviewer" && continue
      echo "$reviewer" >> "$REQUESTED_FILE"
    done

    # Count completed reviews per reviewer and track response times
    echo "$pr" | jq -c '.timelineItems[] | select(.__typename == "PullRequestReview")' | while IFS= read -r review; do
      [[ -z "$review" ]] && continue

      reviewer=$(echo "$review" | jq -r '.author.login // empty')
      [[ -z "$reviewer" ]] && continue
      is_bot "$reviewer" && continue

      review_date=$(echo "$review" | jq -r '.createdAt')
      [[ "$review_date" < "$START_DATE" || "$review_date" > "$END_DATE" ]] && continue

      echo "$reviewer" >> "$COMPLETED_FILE"

      request_time=$(echo "$pr" | jq -r --arg r "$reviewer" '[.timelineItems[] | select(.__typename == "ReviewRequestedEvent" and .requestedReviewer.login == $r) | .createdAt] | sort | first // empty')
      if [[ -n "$request_time" ]]; then
        request_ts=$(iso_to_ts "$request_time")
        review_ts=$(iso_to_ts "$review_date")
        if [[ "$review_ts" -ge "$request_ts" && "$request_ts" -gt 0 ]]; then
          response_seconds=$((review_ts - request_ts))
          echo "$reviewer $response_seconds" >> "$RESPONSE_FILE"
        fi
      fi
    done

    # Track pending reviews
    state=$(echo "$pr" | jq -r '.state')
    if [[ "$state" == "OPEN" ]]; then
      requested_reviewers=$(echo "$pr" | jq -r '[.timelineItems[] | select(.__typename == "ReviewRequestedEvent") | .requestedReviewer.login // empty] | unique | .[]')
      completed_reviewers=$(echo "$pr" | jq -r '[.timelineItems[] | select(.__typename == "PullRequestReview") | .author.login // empty] | unique | .[]')

      while IFS= read -r reviewer; do
        [[ -z "$reviewer" ]] && continue
        is_bot "$reviewer" && continue
        if ! echo "$completed_reviewers" | grep -q "^${reviewer}$"; then
          echo "$reviewer" >> "$PENDING_FILE"
        fi
      done <<< "$requested_reviewers"
    fi

  done < "$PR_LIFECYCLE_FILE"

  # Aggregate all unique reviewers
  ALL_REVIEWERS_FILE=$(make_tmpfile)
  cat "$REQUESTED_FILE" "$COMPLETED_FILE" 2>/dev/null | sort -u > "$ALL_REVIEWERS_FILE"

  if [[ ! -s "$ALL_REVIEWERS_FILE" ]]; then
    echo "No review activity found in this period."
    return
  fi

  echo "[Team Review Load]"
  echo ""
  printf "  %-20s %10s %10s %8s %14s %8s\n" "Reviewer" "Requested" "Completed" "Rate" "Avg Response" "Pending"
  printf "  %-20s %10s %10s %8s %14s %8s\n" "--------" "---------" "---------" "----" "------------" "-------"

  total_completed=0
  REVIEWER_COMPLETED_FILE=$(make_tmpfile)

  while IFS= read -r reviewer; do
    [[ -z "$reviewer" ]] && continue

    requested=$(grep -c "^${reviewer}$" "$REQUESTED_FILE" 2>/dev/null || true)
    requested=${requested:-0}; requested=$((requested + 0))
    completed=$(grep -c "^${reviewer}$" "$COMPLETED_FILE" 2>/dev/null || true)
    completed=${completed:-0}; completed=$((completed + 0))
    pending=$(grep -c "^${reviewer}$" "$PENDING_FILE" 2>/dev/null || true)
    pending=${pending:-0}; pending=$((pending + 0))

    rate="-"
    if [[ $requested -gt 0 ]]; then
      rate="$((completed * 100 / requested))%"
    fi

    avg_response="-"
    response_data=$(grep "^${reviewer} " "$RESPONSE_FILE" 2>/dev/null)
    if [[ -n "$response_data" ]]; then
      avg_seconds=$(echo "$response_data" | awk '{ sum += $2; n++ } END { if(n>0) print int(sum/n); else print 0 }')
      if [[ $avg_seconds -gt 0 ]]; then
        avg_response=$(format_duration $avg_seconds)
      fi
    fi

    printf "  %-20s %10d %10d %8s %14s %8d\n" "$reviewer" "$requested" "$completed" "$rate" "$avg_response" "$pending"

    total_completed=$((total_completed + completed))
    echo "$completed $reviewer" >> "$REVIEWER_COMPLETED_FILE"
  done < "$ALL_REVIEWERS_FILE"

  echo ""

  # Load balance analysis
  if [[ $total_completed -gt 0 && -s "$REVIEWER_COMPLETED_FILE" ]]; then
    echo "[Load Balance]"
    echo ""

    top_reviewer=$(sort -rn "$REVIEWER_COMPLETED_FILE" | head -1)
    top_count=$(echo "$top_reviewer" | awk '{print $1}')
    top_name=$(echo "$top_reviewer" | awk '{print $2}')
    top_pct=$((top_count * 100 / total_completed))

    reviewer_count=$(wc -l < "$ALL_REVIEWERS_FILE" | tr -d ' ')

    echo "  Total completed reviews: $total_completed"
    echo "  Active reviewers: $reviewer_count"
    echo "  Top reviewer: $top_name ($top_count reviews, ${top_pct}% of total)"

    if [[ $top_pct -ge 50 ]]; then
      echo "  Warning: Review load is heavily concentrated. Consider redistributing."
    elif [[ $top_pct -ge 35 ]]; then
      echo "  Note: Top reviewer handles a significant portion. Monitor for burnout."
    else
      echo "  Load distribution looks healthy."
    fi

    overloaded=$(awk '$1 > 3' "$PENDING_FILE" 2>/dev/null | sort | uniq -c | sort -rn | head -3)
    if [[ -n "$overloaded" ]]; then
      echo ""
      echo "  Overloaded reviewers (>3 pending reviews):"
      while read -r count name; do
        [[ -z "$name" ]] && continue
        echo "    $name: $count pending"
      done <<< "$overloaded"
    fi
  fi
}

run_analysis "Reviewer Load Distribution" analyze_reviewer_load "$@"
