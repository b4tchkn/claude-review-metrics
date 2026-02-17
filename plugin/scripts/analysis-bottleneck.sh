#!/usr/bin/env bash
# Analysis: PR Lifecycle Bottleneck Detection
# Decomposes PR lifecycle into phases and identifies where time is lost
# Usage: ./analysis-bottleneck.sh [OPTIONS] [REPO]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/analysis-runner.sh"

analyze_bottleneck() {
  # Temp files for phase durations
  WAIT_FILE=$(make_tmpfile)
  REVIEW_FILE=$(make_tmpfile)
  MERGE_FILE=$(make_tmpfile)
  TOTAL_FILE=$(make_tmpfile)
  SLOWEST_FILE=$(make_tmpfile)
  RC_INSTANT_FILE=$(make_tmpfile)
  RC_SECOND_WAIT_FILE=$(make_tmpfile)
  RC_OTHER_FILE=$(make_tmpfile)
  RT_FIRST_FILE=$(make_tmpfile)
  RT_REREVIEW_FILE=$(make_tmpfile)

  merged_count=0

  while IFS= read -r pr; do
    [[ -z "$pr" ]] && continue

    state=$(echo "$pr" | jq -r '.state')
    [[ "$state" != "MERGED" ]] && continue

    created_at=$(echo "$pr" | jq -r '.createdAt')
    merged_at=$(echo "$pr" | jq -r '.mergedAt')
    number=$(echo "$pr" | jq -r '.number')
    title=$(echo "$pr" | jq -r '.title')
    author=$(echo "$pr" | jq -r '.author')

    created_ts=$(iso_to_ts "$created_at")
    merged_ts=$(iso_to_ts "$merged_at")
    [[ "$created_ts" -eq 0 || "$merged_ts" -eq 0 ]] && continue

    total_seconds=$((merged_ts - created_ts))
    [[ $total_seconds -le 0 ]] && continue

    first_review_request=$(echo "$pr" | jq -r '[.timelineItems[] | select(.__typename == "ReviewRequestedEvent") | .createdAt] | sort | first // empty')
    ready_for_review=$(echo "$pr" | jq -r '[.timelineItems[] | select(.__typename == "ReadyForReviewEvent") | .createdAt] | sort | first // empty')

    review_ready_at="$created_at"
    if [[ -n "$ready_for_review" ]]; then
      review_ready_at="$ready_for_review"
    fi

    first_review=$(echo "$pr" | jq -r '[.timelineItems[] | select(.__typename == "PullRequestReview") | .createdAt] | sort | first // empty')
    last_approval=$(echo "$pr" | jq -r '[.timelineItems[] | select(.__typename == "PullRequestReview" and .state == "APPROVED") | .createdAt] | sort | last // empty')

    if [[ -n "$first_review" ]]; then
      review_ready_ts=$(iso_to_ts "$review_ready_at")
      first_review_ts=$(iso_to_ts "$first_review")

      if [[ "$first_review_ts" -ge "$review_ready_ts" ]]; then
        wait_seconds=$((first_review_ts - review_ready_ts))
        echo "$wait_seconds" >> "$WAIT_FILE"
      fi

      if [[ -n "$last_approval" ]]; then
        last_approval_ts=$(iso_to_ts "$last_approval")
        if [[ "$last_approval_ts" -ge "$first_review_ts" ]]; then
          review_seconds=$((last_approval_ts - first_review_ts))
          echo "$review_seconds" >> "$REVIEW_FILE"

          approver_count=$(echo "$pr" | jq '[.timelineItems[] | select(.__typename == "PullRequestReview" and .state == "APPROVED") | .author.login] | unique | length')
          if [[ $review_seconds -lt $INSTANT_APPROVAL_THRESHOLD ]]; then
            echo "$review_seconds" >> "$RC_INSTANT_FILE"
          elif [[ $approver_count -gt 1 ]]; then
            echo "$review_seconds" >> "$RC_SECOND_WAIT_FILE"
          else
            echo "$review_seconds" >> "$RC_OTHER_FILE"
          fi
        fi

        if [[ "$merged_ts" -ge "$last_approval_ts" ]]; then
          merge_seconds=$((merged_ts - last_approval_ts))
          echo "$merge_seconds" >> "$MERGE_FILE"
        fi
      fi
    fi

    # Classify response times by review round
    review_requests_json=$(echo "$pr" | jq -c '[.timelineItems[] | select(.__typename == "ReviewRequestedEvent" and .requestedReviewer.login != null) | {reviewer: .requestedReviewer.login, time: .createdAt}] | sort_by(.time)')
    reviews_json=$(echo "$pr" | jq -c '[.timelineItems[] | select(.__typename == "PullRequestReview" and .author.login != null) | {reviewer: .author.login, time: .createdAt}] | sort_by(.time)')

    echo "$pr" | jq -r '[.timelineItems[] | select(.__typename == "ReviewRequestedEvent") | .requestedReviewer.login // empty] | unique | .[]' | while IFS= read -r reviewer; do
      [[ -z "$reviewer" ]] && continue
      is_bot "$reviewer" && continue

      req_times=$(echo "$review_requests_json" | jq -r --arg r "$reviewer" '[.[] | select(.reviewer == $r) | .time] | .[]')
      rev_times=$(echo "$reviews_json" | jq -r --arg r "$reviewer" '[.[] | select(.reviewer == $r) | .time] | .[]')

      req_index=0
      while IFS= read -r req_time; do
        [[ -z "$req_time" ]] && continue
        req_ts=$(iso_to_ts "$req_time")
        [[ "$req_ts" -eq 0 ]] && continue

        matched_rev_ts=0
        while IFS= read -r rev_time; do
          [[ -z "$rev_time" ]] && continue
          rev_ts=$(iso_to_ts "$rev_time")
          if [[ "$rev_ts" -ge "$req_ts" ]]; then
            matched_rev_ts=$rev_ts
            break
          fi
        done <<< "$rev_times"

        if [[ $matched_rev_ts -gt 0 ]]; then
          response_seconds=$((matched_rev_ts - req_ts))
          if [[ $req_index -eq 0 ]]; then
            echo "$response_seconds" >> "$RT_FIRST_FILE"
          else
            echo "$response_seconds" >> "$RT_REREVIEW_FILE"
          fi
        fi

        ((req_index++)) || true
      done <<< "$req_times"
    done

    echo "$total_seconds" >> "$TOTAL_FILE"
    echo "$total_seconds|#$number|$author|$title" >> "$SLOWEST_FILE"

    ((merged_count++)) || true
  done < "$PR_LIFECYCLE_FILE"

  if [[ $merged_count -eq 0 ]]; then
    echo "No merged PRs found in this period."
    return
  fi

  echo "========== PR Lifecycle Phases =========="
  echo "Merged PRs analyzed: $merged_count"
  echo ""

  calc_avg() {
    local file=$1
    if [[ ! -s "$file" ]]; then
      echo "0"
      return
    fi
    awk '{ sum += $1; n++ } END { if(n>0) print int(sum/n); else print 0 }' "$file"
  }

  display_phase_stats() {
    local label=$1
    local file=$2

    if [[ ! -s "$file" ]]; then
      echo "  $label: No data"
      return
    fi

    local count
    count=$(wc -l < "$file" | tr -d ' ')
    local avg
    avg=$(calc_avg "$file")
    local p50
    p50=$(sort -n "$file" | percentile 50)
    local p90
    p90=$(sort -n "$file" | percentile 90)

    echo "  $label:"
    echo "    Typical: $(format_duration $p50) | Slow cases: $(format_duration $p90) | Avg: $(format_duration $avg) (n=$count)"
  }

  echo "[Phase Breakdown]"
  echo ""

  display_phase_stats "Wait for Review" "$WAIT_FILE"
  wait_avg_val=$(calc_avg "$WAIT_FILE")

  display_phase_stats "Review Cycles" "$REVIEW_FILE"
  review_avg_val=$(calc_avg "$REVIEW_FILE")

  display_phase_stats "Merge Delay" "$MERGE_FILE"
  merge_avg_val=$(calc_avg "$MERGE_FILE")

  display_phase_stats "Total Cycle Time" "$TOTAL_FILE"
  total_avg_val=$(calc_avg "$TOTAL_FILE")

  echo ""

  if [[ -n "$total_avg_val" && "$total_avg_val" -gt 0 ]]; then
    echo "[Bottleneck Identification]"
    echo ""

    max_phase="Unknown"
    max_val=0
    max_pct=0

    for phase_name in "Wait for Review" "Review Cycles" "Merge Delay"; do
      case "$phase_name" in
        "Wait for Review") val="${wait_avg_val:-0}" ;;
        "Review Cycles") val="${review_avg_val:-0}" ;;
        "Merge Delay") val="${merge_avg_val:-0}" ;;
      esac
      val=${val:-0}
      if [[ $val -gt $max_val ]]; then
        max_val=$val
        max_phase="$phase_name"
      fi
    done

    if [[ $total_avg_val -gt 0 ]]; then
      max_pct=$((max_val * 100 / total_avg_val))
    fi

    echo "  Biggest bottleneck: $max_phase ($(format_duration $max_val), ~${max_pct}% of total)"

    case "$max_phase" in
      "Wait for Review")
        echo "  Suggestion: Consider a review SLA (e.g., respond within 4 hours)"
        ;;
      "Review Cycles")
        echo "  Suggestion: Improve PR descriptions and pre-review checklist to reduce back-and-forth"
        ;;
      "Merge Delay")
        echo "  Suggestion: Merge promptly after approval; consider auto-merge for approved PRs"
        ;;
    esac

    rc_total=0
    [[ -s "$RC_INSTANT_FILE" ]] && rc_total=$((rc_total + $(wc -l < "$RC_INSTANT_FILE" | tr -d ' ')))
    [[ -s "$RC_SECOND_WAIT_FILE" ]] && rc_total=$((rc_total + $(wc -l < "$RC_SECOND_WAIT_FILE" | tr -d ' ')))
    [[ -s "$RC_OTHER_FILE" ]] && rc_total=$((rc_total + $(wc -l < "$RC_OTHER_FILE" | tr -d ' ')))

    if [[ $rc_total -gt 0 ]]; then
      echo ""
      echo "[Review Cycles Breakdown]"
      echo ""

      rc_instant=0; [[ -s "$RC_INSTANT_FILE" ]] && rc_instant=$(wc -l < "$RC_INSTANT_FILE" | tr -d ' ')
      rc_second=0; [[ -s "$RC_SECOND_WAIT_FILE" ]] && rc_second=$(wc -l < "$RC_SECOND_WAIT_FILE" | tr -d ' ')
      rc_other=0; [[ -s "$RC_OTHER_FILE" ]] && rc_other=$(wc -l < "$RC_OTHER_FILE" | tr -d ' ')

      echo "  Approved quickly (<5min):          $rc_instant PRs ($((rc_instant * 100 / rc_total))%)"
      echo "  Waiting for 2nd approver:          $rc_second PRs ($((rc_second * 100 / rc_total))%)"
      echo "  Other (changes requested / rework): $rc_other PRs ($((rc_other * 100 / rc_total))%)"

      if [[ $rc_second -gt 0 ]]; then
        second_avg=$(calc_avg "$RC_SECOND_WAIT_FILE")
        echo "  Avg wait for 2nd approver: $(format_duration $second_avg)"
      fi

      if [[ $rc_total -gt 0 && $((rc_second * 100 / rc_total)) -ge 50 ]]; then
        echo ""
        echo "  Root cause: Waiting for 2nd approver is the main delay."
        echo "  Suggestions:"
        echo "    - Reduce required approvers for low-risk PRs (e.g., docs, deps, small fixes)"
        echo "    - Set up automated reminders for pending 2nd reviews"
        echo "    - Optimize reviewer assignment to available team members"
      elif [[ $rc_total -gt 0 && $((rc_other * 100 / rc_total)) -ge 50 ]]; then
        echo ""
        echo "  Root cause: Rework and change requests are the main delay."
        echo "  Suggestions:"
        echo "    - Improve PR descriptions and pre-review checklists"
        echo "    - Consider pair programming for complex changes"
      fi
    fi
  fi

  echo ""

  # Response time comparison
  rt_first_count=0; [[ -s "$RT_FIRST_FILE" ]] && rt_first_count=$(wc -l < "$RT_FIRST_FILE" | tr -d ' ')
  rt_rereview_count=0; [[ -s "$RT_REREVIEW_FILE" ]] && rt_rereview_count=$(wc -l < "$RT_REREVIEW_FILE" | tr -d ' ')

  if [[ $rt_first_count -gt 0 || $rt_rereview_count -gt 0 ]]; then
    echo "[Response Time: First Review vs Re-review]"
    echo ""

    if [[ $rt_first_count -gt 0 ]]; then
      first_avg=$(calc_avg "$RT_FIRST_FILE")
      first_p50=$(sort -n "$RT_FIRST_FILE" | percentile 50)
      echo "  First review:  Typical: $(format_duration $first_p50) | Avg: $(format_duration $first_avg) (n=$rt_first_count)"
    fi

    if [[ $rt_rereview_count -gt 0 ]]; then
      rereview_avg=$(calc_avg "$RT_REREVIEW_FILE")
      rereview_p50=$(sort -n "$RT_REREVIEW_FILE" | percentile 50)
      echo "  Re-review:     Typical: $(format_duration $rereview_p50) | Avg: $(format_duration $rereview_avg) (n=$rt_rereview_count)"
    fi

    if [[ $rt_first_count -gt 0 && $rt_rereview_count -gt 0 ]]; then
      first_avg=$(calc_avg "$RT_FIRST_FILE")
      rereview_avg=$(calc_avg "$RT_REREVIEW_FILE")
      if [[ $first_avg -gt 0 && $rereview_avg -gt 0 ]]; then
        if [[ $rereview_avg -gt $first_avg ]]; then
          ratio=$(( rereview_avg / first_avg ))
          if [[ $ratio -ge 2 ]]; then
            echo ""
            echo "  Re-reviews take ${ratio}x longer than first reviews."
            echo "  Suggestion: Set up notifications for re-review requests to prioritize them."
          fi
        elif [[ $first_avg -gt $rereview_avg ]]; then
          ratio=$(( first_avg / rereview_avg ))
          if [[ $ratio -ge 2 ]]; then
            echo ""
            echo "  First reviews take ${ratio}x longer than re-reviews."
            echo "  Suggestion: Improve review request routing; assign reviewers who are available."
          fi
        fi
      fi
    fi

    echo ""
  fi

  # Show slowest PRs
  if [[ -s "$SLOWEST_FILE" ]]; then
    echo "[Slowest PRs]"
    echo ""
    sort -t'|' -k1 -rn "$SLOWEST_FILE" | head -5 | while IFS='|' read -r seconds number author title; do
      if [[ ${#title} -gt 50 ]]; then
        title="${title:0:47}..."
      fi
      echo "  $number ($author): $(format_duration $seconds) - $title"
    done
  fi
}

run_analysis "Bottleneck Analysis" analyze_bottleneck "$@"
