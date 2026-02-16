#!/bin/bash
# Collect review data from GitHub API
# Outputs JSON data to METRICS_FILE and RESPONSE_TIMES_FILE

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

collect_data() {
  METRICS_FILE=$(mktemp)
  RESPONSE_TIMES_FILE=$(mktemp)
  echo "{}" > "$METRICS_FILE"
  echo "{}" > "$RESPONSE_TIMES_FILE"

  CURSOR=""
  HAS_NEXT="true"
  PR_COUNT=0

  while [[ "$HAS_NEXT" == "true" ]]; do
    RESULT=$(gh api graphql -f query="$GRAPHQL_QUERY" -F owner="$OWNER" -F repo="$REPO_NAME" ${CURSOR:+-F cursor="$CURSOR"} 2>/dev/null)

    HAS_NEXT=$(echo "$RESULT" | jq -r '.data.repository.pullRequests.pageInfo.hasNextPage')
    CURSOR=$(echo "$RESULT" | jq -r '.data.repository.pullRequests.pageInfo.endCursor')

    PR_DATA=$(echo "$RESULT" | jq -c '.data.repository.pullRequests.nodes[]')

    while IFS= read -r pr; do
      [[ -z "$pr" ]] && continue

      PR_UPDATED=$(echo "$pr" | jq -r '.updatedAt')
      PR_NUM=$(echo "$pr" | jq -r '.number')

      if [[ "$PR_UPDATED" < "$START_DATE" ]]; then
        HAS_NEXT="false"
        break
      fi

      ((PR_COUNT++)) || true

      REVIEW_REQUESTS=$(echo "$pr" | jq -c '[.timelineItems.nodes[]? | select(.__typename == "ReviewRequestedEvent") | {reviewer: .requestedReviewer.login, requestedAt: .createdAt}]')

      echo "$pr" | jq -c '.reviews.nodes[]?' | while IFS= read -r review; do
        [[ -z "$review" ]] && continue

        REVIEWER=$(echo "$review" | jq -r '.author.login // empty')
        REVIEW_DATE=$(echo "$review" | jq -r '.createdAt')
        STATE=$(echo "$review" | jq -r '.state')
        COMMENTS=$(echo "$review" | jq -r '.comments.totalCount // 0')

        [[ -z "$REVIEWER" ]] && continue
        is_bot "$REVIEWER" && continue
        [[ "$REVIEW_DATE" < "$START_DATE" || "$REVIEW_DATE" > "$END_DATE" ]] && continue

        # Calculate response time
        REQUEST_TIME=$(echo "$REVIEW_REQUESTS" | jq -r --arg reviewer "$REVIEWER" '[.[] | select(.reviewer == $reviewer) | .requestedAt] | first // empty')
        if [[ -n "$REQUEST_TIME" ]]; then
          REQUEST_TS=$(iso_to_ts "$REQUEST_TIME")
          REVIEW_TS=$(iso_to_ts "$REVIEW_DATE")
          if [[ "$REQUEST_TS" -gt 0 && "$REVIEW_TS" -gt 0 && "$REVIEW_TS" -ge "$REQUEST_TS" ]]; then
            RESPONSE_SECONDS=$((REVIEW_TS - REQUEST_TS))
            CURRENT_RT=$(cat "$RESPONSE_TIMES_FILE")
            UPDATED_RT=$(echo "$CURRENT_RT" | jq --arg login "$REVIEWER" --argjson seconds "$RESPONSE_SECONDS" '
              .[$login] //= {"totalSeconds": 0, "count": 0} |
              .[$login].totalSeconds += $seconds |
              .[$login].count += 1
            ')
            echo "$UPDATED_RT" > "$RESPONSE_TIMES_FILE"
          fi
        fi

        # Update metrics
        CURRENT=$(cat "$METRICS_FILE")
        UPDATED=$(echo "$CURRENT" | jq --arg login "$REVIEWER" --argjson pr "$PR_NUM" --arg state "$STATE" --argjson comments "$COMMENTS" '
          .[$login] //= {"reviewedPRs": [], "approvedPRs": [], "comments": 0} |
          .[$login].reviewedPRs += [$pr] |
          .[$login].reviewedPRs |= unique |
          if $state == "APPROVED" then .[$login].approvedPRs += [$pr] | .[$login].approvedPRs |= unique else . end |
          .[$login].comments += $comments
        ')
        echo "$UPDATED" > "$METRICS_FILE"
      done
    done <<< "$PR_DATA"
  done

  export METRICS_FILE RESPONSE_TIMES_FILE PR_COUNT
}
