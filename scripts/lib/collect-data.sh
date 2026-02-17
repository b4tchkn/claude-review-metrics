#!/usr/bin/env bash
# Collect review data from GitHub API
# Outputs JSON data to METRICS_FILE and RESPONSE_TIMES_FILE

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

collect_data() {
  METRICS_FILE=$(make_tmpfile)
  RESPONSE_TIMES_FILE=$(make_tmpfile)
  echo "{}" > "$METRICS_FILE"
  echo "{}" > "$RESPONSE_TIMES_FILE"

  PR_COUNT=0

  _collect_data_page() {
    local RESULT
    RESULT=$(cat)

    local PR_DATA
    PR_DATA=$(echo "$RESULT" | jq -c '.data.repository.pullRequests.nodes[]')

    while IFS= read -r pr; do
      [[ -z "$pr" ]] && continue

      PR_UPDATED=$(echo "$pr" | jq -r '.updatedAt')
      PR_NUM=$(echo "$pr" | jq -r '.number')

      if [[ "$PR_UPDATED" < "$START_DATE" ]]; then
        return 1  # Signal early exit to graphql_paginate
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
  }

  graphql_paginate "$GRAPHQL_QUERY" "$OWNER" "$REPO_NAME" _collect_data_page

  export METRICS_FILE RESPONSE_TIMES_FILE PR_COUNT
}
