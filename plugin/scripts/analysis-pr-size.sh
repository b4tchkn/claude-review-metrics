#!/usr/bin/env bash
# Analysis: PR Size vs Review Speed Correlation
# Determines if large PRs cause review delays
# Usage: ./analysis-pr-size.sh [OPTIONS] [REPO]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/analysis-runner.sh"

analyze_pr_size() {
  XS_FILE=$(make_tmpfile)
  S_FILE=$(make_tmpfile)
  M_FILE=$(make_tmpfile)
  L_FILE=$(make_tmpfile)
  XL_FILE=$(make_tmpfile)

  analyzed_count=0

  while IFS= read -r pr; do
    [[ -z "$pr" ]] && continue

    state=$(echo "$pr" | jq -r '.state')
    [[ "$state" != "MERGED" ]] && continue

    additions=$(echo "$pr" | jq -r '.additions // 0')
    deletions=$(echo "$pr" | jq -r '.deletions // 0')
    total_lines=$((additions + deletions))
    size=$(classify_pr_size $total_lines)

    created_at=$(echo "$pr" | jq -r '.createdAt')
    merged_at=$(echo "$pr" | jq -r '.mergedAt')
    created_ts=$(iso_to_ts "$created_at")
    merged_ts=$(iso_to_ts "$merged_at")
    [[ "$created_ts" -eq 0 || "$merged_ts" -eq 0 ]] && continue

    cycle_seconds=$((merged_ts - created_ts))
    [[ $cycle_seconds -le 0 ]] && continue

    changes_requested=$(echo "$pr" | jq '[.timelineItems[] | select(.__typename == "PullRequestReview" and .state == "CHANGES_REQUESTED")] | length')
    approved=$(echo "$pr" | jq '[.timelineItems[] | select(.__typename == "PullRequestReview" and .state == "APPROVED")] | length')
    if [[ $approved -gt 0 ]]; then
      rounds=$((changes_requested + 1))
    else
      rounds=$((changes_requested > 0 ? changes_requested : 1))
    fi

    line="$cycle_seconds $rounds $total_lines"

    case $size in
      XS) echo "$line" >> "$XS_FILE" ;;
      S)  echo "$line" >> "$S_FILE" ;;
      M)  echo "$line" >> "$M_FILE" ;;
      L)  echo "$line" >> "$L_FILE" ;;
      XL) echo "$line" >> "$XL_FILE" ;;
    esac

    ((analyzed_count++)) || true
  done < "$PR_LIFECYCLE_FILE"

  if [[ $analyzed_count -eq 0 ]]; then
    echo "No merged PRs found in this period."
    return
  fi

  echo "[PR Size Distribution] ($analyzed_count merged PRs)"
  echo ""
  printf "  %-6s %8s %6s %15s %-20s %12s %12s\n" "Size" "Lines" "Count" "Avg Cycle Time" "" "Avg Rounds" "Slow cases"
  printf "  %-6s %8s %6s %15s %-20s %12s %12s\n" "----" "-----" "-----" "--------------" "--------------------" "----------" "----------"

  calc_bucket_avg() {
    local file=$1
    if [[ ! -s "$file" ]]; then
      echo "0"
      return
    fi
    awk '{ sum += $1; n++ } END { if(n>0) print int(sum/n); else print 0 }' "$file"
  }

  display_bucket() {
    local label=$1
    local range=$2
    local file=$3
    local max_cycle=${4:-0}

    if [[ ! -s "$file" ]]; then
      printf "  %-6s %8s %6d %15s %-20s %12s %12s\n" "$label" "$range" "0" "-" "" "-" "-"
      return
    fi

    local count
    count=$(wc -l < "$file" | tr -d ' ')

    local avg_cycle
    avg_cycle=$(calc_bucket_avg "$file")

    local avg_rounds
    avg_rounds=$(awk '{ sum += $2; n++ } END { if(n>0) printf "%.1f", sum/n; else print 0 }' "$file")

    local p90_cycle
    p90_cycle=$(awk '{print $1}' "$file" | sort -n | percentile 90)

    local bar=""
    if [[ $max_cycle -gt 0 ]]; then
      bar=$(graph_bar "$avg_cycle" "$max_cycle" 20)
    fi

    printf "  %-6s %8s %6d %15s %s %12s %12s\n" "$label" "$range" "$count" "$(format_duration $avg_cycle)" "$bar" "$avg_rounds" "$(format_duration $p90_cycle)"
  }

  # Capture avg cycle times for insight
  xs_avg=$(calc_bucket_avg "$XS_FILE")
  s_avg=$(calc_bucket_avg "$S_FILE")
  m_avg=$(calc_bucket_avg "$M_FILE")
  l_avg=$(calc_bucket_avg "$L_FILE")
  xl_avg=$(calc_bucket_avg "$XL_FILE")

  # Find max avg cycle time for bar scaling
  local max_cycle_avg=0
  for avg in $xs_avg $s_avg $m_avg $l_avg $xl_avg; do
    [[ $avg -gt $max_cycle_avg ]] && max_cycle_avg=$avg
  done

  display_bucket "XS" "1-10" "$XS_FILE" "$max_cycle_avg"
  display_bucket "S" "11-50" "$S_FILE" "$max_cycle_avg"
  display_bucket "M" "51-200" "$M_FILE" "$max_cycle_avg"
  display_bucket "L" "201-500" "$L_FILE" "$max_cycle_avg"
  display_bucket "XL" "500+" "$XL_FILE" "$max_cycle_avg"

  echo ""

  echo "[Insight]"
  echo ""

  small_avg=0
  large_avg=0
  small_label=""
  large_label=""

  for label_avg in "XS:$xs_avg" "S:$s_avg" "M:$m_avg" "L:$l_avg" "XL:$xl_avg"; do
    label="${label_avg%%:*}"
    avg="${label_avg##*:}"
    avg=${avg:-0}
    [[ $avg -eq 0 ]] && continue

    if [[ $small_avg -eq 0 ]]; then
      small_avg=$avg
      small_label=$label
    fi
    large_avg=$avg
    large_label=$label
  done

  if [[ $small_avg -gt 0 && $large_avg -gt 0 && "$small_label" != "$large_label" ]]; then
    if [[ $small_avg -gt 0 ]]; then
      ratio=$((large_avg / small_avg))
      if [[ $ratio -ge 2 ]]; then
        echo "  $large_label PRs take ${ratio}x longer than $small_label PRs to merge."
        echo "  Consider breaking large PRs into smaller, focused changes."
      else
        echo "  PR size has moderate impact on cycle time (${ratio}x difference)."
      fi
    fi
  else
    echo "  Insufficient data to compare PR size impact."
  fi

  xl_count=0
  [[ -s "$XL_FILE" ]] && xl_count=$(wc -l < "$XL_FILE" | tr -d ' ')
  l_count=0
  [[ -s "$L_FILE" ]] && l_count=$(wc -l < "$L_FILE" | tr -d ' ')

  large_total=$((xl_count + l_count))
  if [[ $analyzed_count -gt 0 ]]; then
    large_pct=$((large_total * 100 / analyzed_count))
    if [[ $large_pct -ge 30 ]]; then
      echo "  ${large_pct}% of PRs are L or XL. Aim to keep PRs under 200 lines for faster reviews."
    fi
  fi
}

run_analysis "PR Size Analysis" analyze_pr_size "$@"
