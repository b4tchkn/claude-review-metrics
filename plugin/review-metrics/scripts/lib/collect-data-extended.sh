#!/bin/bash
# Collect extended PR lifecycle data from GitHub API
# Outputs JSONL to PR_LIFECYCLE_FILE for analysis scripts
# Note: Caller is responsible for cleaning up PR_LIFECYCLE_FILE and OPEN_PRS_FILE

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Collect extended PR lifecycle data
# Sets: PR_LIFECYCLE_FILE (path to JSONL file), EXTENDED_PR_COUNT
collect_extended_data() {
  PR_LIFECYCLE_FILE=$(mktemp)
  EXTENDED_PR_COUNT=0

  local cursor=""
  local has_next="true"

  while [[ "$has_next" == "true" ]]; do
    local result
    result=$(gh api graphql -f query="$GRAPHQL_QUERY_EXTENDED" \
      -F owner="$OWNER" -F repo="$REPO_NAME" \
      ${cursor:+-F cursor="$cursor"} 2>/dev/null) || true

    has_next=$(echo "$result" | jq -r '.data.repository.pullRequests.pageInfo.hasNextPage // "false"' 2>/dev/null)
    cursor=$(echo "$result" | jq -r '.data.repository.pullRequests.pageInfo.endCursor // empty' 2>/dev/null)

    [[ "$has_next" == "null" || -z "$has_next" ]] && has_next="false"

    local pr_data
    pr_data=$(echo "$result" | jq -c '.data.repository.pullRequests.nodes[]?' 2>/dev/null)
    [[ -z "$pr_data" ]] && break

    while IFS= read -r pr; do
      [[ -z "$pr" ]] && continue

      local updated_at
      updated_at=$(echo "$pr" | jq -r '.updatedAt')

      # Stop pagination if PR is older than our window
      if [[ "$updated_at" < "$START_DATE" ]]; then
        has_next="false"
        break
      fi

      local created_at
      created_at=$(echo "$pr" | jq -r '.createdAt')

      # Skip PRs created after our window
      [[ "$created_at" > "$END_DATE" ]] && continue

      local author
      author=$(echo "$pr" | jq -r '.author.login // empty')
      [[ -z "$author" ]] && continue
      is_bot "$author" && continue

      # Output one JSONL line per PR with lifecycle data
      echo "$pr" | jq -c '{
        number: .number,
        title: .title,
        state: .state,
        isDraft: .isDraft,
        createdAt: .createdAt,
        mergedAt: .mergedAt,
        closedAt: .closedAt,
        updatedAt: .updatedAt,
        additions: .additions,
        deletions: .deletions,
        changedFiles: .changedFiles,
        author: .author.login,
        timelineItems: .timelineItems.nodes
      }' >> "$PR_LIFECYCLE_FILE"

      ((EXTENDED_PR_COUNT++)) || true
    done <<< "$pr_data"
  done
}

# Collect open PRs only (for stuck-prs analysis)
# Sets: OPEN_PRS_FILE (path to JSONL file), OPEN_PR_COUNT
collect_open_prs() {
  OPEN_PRS_FILE=$(mktemp)
  OPEN_PR_COUNT=0

  local cursor=""
  local has_next="true"

  while [[ "$has_next" == "true" ]]; do
    local result
    result=$(gh api graphql -f query="$GRAPHQL_QUERY_OPEN_PRS" \
      -F owner="$OWNER" -F repo="$REPO_NAME" \
      ${cursor:+-F cursor="$cursor"} 2>/dev/null) || true

    has_next=$(echo "$result" | jq -r '.data.repository.pullRequests.pageInfo.hasNextPage // "false"' 2>/dev/null)
    cursor=$(echo "$result" | jq -r '.data.repository.pullRequests.pageInfo.endCursor // empty' 2>/dev/null)

    [[ "$has_next" == "null" || -z "$has_next" ]] && has_next="false"

    local pr_data
    pr_data=$(echo "$result" | jq -c '.data.repository.pullRequests.nodes[]?' 2>/dev/null)
    [[ -z "$pr_data" ]] && break

    while IFS= read -r pr; do
      [[ -z "$pr" ]] && continue

      local author
      author=$(echo "$pr" | jq -r '.author.login // empty')
      [[ -z "$author" ]] && continue

      local is_draft
      is_draft=$(echo "$pr" | jq -r '.isDraft')
      [[ "$is_draft" == "true" ]] && continue

      echo "$pr" | jq -c '{
        number: .number,
        title: .title,
        createdAt: .createdAt,
        updatedAt: .updatedAt,
        additions: .additions,
        deletions: .deletions,
        changedFiles: .changedFiles,
        author: .author.login,
        reviewRequests: [.reviewRequests.nodes[]?.requestedReviewer.login // empty],
        timelineItems: .timelineItems.nodes
      }' >> "$OPEN_PRS_FILE"

      ((OPEN_PR_COUNT++)) || true
    done <<< "$pr_data"
  done
}
