#!/usr/bin/env bash
# Ranking: Average Fix Time (Comment to Commit)
# Measures time from review comment to next commit (fix response time)
# Usage: ./ranking-fix-time.sh [OPTIONS] [REPO]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

parse_args "$@"
calculate_dates "$PERIOD"
print_header "Fix Time Ranking"

# Fetch PRs updated in the period
echo "Fetching PRs..."

START_DATE_SHORT="${START_DATE_DISPLAY}"
END_DATE_SHORT="${END_DATE_DISPLAY}"

# Temp files for accumulating data
AUTHOR_DATA_FILE=$(mktemp)
PR_DATA_FILE=$(mktemp)
trap "rm -f $AUTHOR_DATA_FILE $PR_DATA_FILE" EXIT

# Get PRs with review comments in the period
prs=$(gh pr list --repo "$REPO" --state all --search "updated:${START_DATE_SHORT}..${END_DATE_SHORT}" --limit 200 --json number,title,author 2>/dev/null | \
  jq -r '.[] | select(.author.is_bot == false) | .number')

pr_count=0
total_comments=0
total_fixes=0

for pr_number in $prs; do
  # Get review comments in the period
  comments=$(gh api "repos/${OWNER}/${REPO_NAME}/pulls/$pr_number/comments" \
    --jq "[.[] | select(.user.type != \"Bot\") | select(.created_at >= \"${START_DATE}\" and .created_at <= \"${END_DATE}\") | {created_at, path, user: .user.login}]" 2>/dev/null)

  comment_count=$(echo "$comments" | jq 'length' 2>/dev/null)
  [[ "$comment_count" -eq 0 ]] || [[ "$comment_count" == "null" ]] || [[ -z "$comment_count" ]] && continue

  # Get PR author
  pr_author=$(gh pr view "$pr_number" --repo "$REPO" --json author --jq '.author.login' 2>/dev/null)
  [[ -z "$pr_author" ]] && continue

  # Get commits
  commits=$(gh api "repos/${OWNER}/${REPO_NAME}/pulls/$pr_number/commits" \
    --jq '[.[] | {sha: .sha[0:7], date: .commit.committer.date}]' 2>/dev/null)

  pr_fixes=0
  pr_total_seconds=0

  while read -r comment; do
    [[ -z "$comment" ]] || [[ "$comment" == "null" ]] && continue

    created_at=$(echo "$comment" | jq -r '.created_at')
    comment_epoch=$(iso_to_ts "$created_at")
    [[ "$comment_epoch" -eq 0 ]] && continue

    # Find next commit after comment
    next_commit_epoch=99999999999

    while read -r commit_line; do
      [[ -z "$commit_line" ]] || [[ "$commit_line" == "null" ]] && continue
      commit_date=$(echo "$commit_line" | jq -r '.date')
      commit_epoch=$(iso_to_ts "$commit_date")

      if [[ "$commit_epoch" -gt "$comment_epoch" ]] && [[ "$commit_epoch" -lt "$next_commit_epoch" ]]; then
        next_commit_epoch=$commit_epoch
      fi
    done <<< "$(echo "$commits" | jq -c '.[]')"

    if [[ "$next_commit_epoch" -lt 99999999999 ]]; then
      diff_seconds=$((next_commit_epoch - comment_epoch))
      diff_hours=$((diff_seconds / 3600))

      # Only count if fix is within 2 weeks (336 hours)
      if [[ $diff_hours -lt 336 ]]; then
        pr_fixes=$((pr_fixes + 1))
        pr_total_seconds=$((pr_total_seconds + diff_seconds))

        # Accumulate per author (append to file)
        echo "$pr_author $diff_seconds" >> "$AUTHOR_DATA_FILE"

        total_fixes=$((total_fixes + 1))
      fi
    fi

    total_comments=$((total_comments + 1))
  done <<< "$(echo "$comments" | jq -c '.[]')"

  if [[ $pr_fixes -gt 0 ]]; then
    pr_count=$((pr_count + 1))
    avg_seconds=$((pr_total_seconds / pr_fixes))
    echo "$pr_number|$pr_author|$comment_count|$pr_fixes|$avg_seconds" >> "$PR_DATA_FILE"
  fi
done

echo "Processed: $pr_count PRs with fixes"
echo "Total comments: $total_comments"
echo "Total fixes: $total_fixes"
echo ""

if [[ $total_fixes -eq 0 ]]; then
  echo "No fix data found in this period."
  exit 0
fi

# Display per-author ranking (aggregate from file)
echo "========== Avg Fix Time by Author (top 3) =========="
echo ""

awk '
{
  author[$1] += $2
  count[$1]++
}
END {
  for (a in author) {
    avg = author[a] / count[a]
    avg_hours = int(avg / 3600)
    avg_minutes = int((avg % 3600) / 60)
    printf "%d|%s|%d|%dh %dm\n", avg, a, count[a], avg_hours, avg_minutes
  }
}
' "$AUTHOR_DATA_FILE" | sort -t'|' -k1 -n | head -3 | while IFS='|' read -r avg author count time; do
  echo "  👤 $author: $time (${count} fixes)"
done

echo ""
echo "========== Per-PR Details =========="
echo ""
echo "| PR# | Author | Comments | Fixes | Avg Fix Time |"
echo "|-----|--------|----------|-------|--------------|"

while IFS='|' read -r pr_number author comments fixes avg_seconds; do
  avg_hours=$((avg_seconds / 3600))
  avg_minutes=$(((avg_seconds % 3600) / 60))
  echo "| #$pr_number | $author | $comments | $fixes | ${avg_hours}h ${avg_minutes}m |"
done < "$PR_DATA_FILE" | sort -t'|' -k5 -n
