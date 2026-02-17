#!/usr/bin/env bash
# Collect extended PR lifecycle data from GitHub API
# Outputs JSONL to PR_LIFECYCLE_FILE for analysis scripts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Collect extended PR lifecycle data
# Sets: PR_LIFECYCLE_FILE (path to JSONL file), EXTENDED_PR_COUNT
collect_extended_data() {
  PR_LIFECYCLE_FILE=$(make_tmpfile)
  EXTENDED_PR_COUNT=0

  _collect_extended_page() {
    local result
    result=$(cat)

    local pr_data
    pr_data=$(echo "$result" | jq -c '.data.repository.pullRequests.nodes[]?' 2>/dev/null)
    [[ -z "$pr_data" ]] && return 1

    while IFS= read -r pr; do
      [[ -z "$pr" ]] && continue

      local updated_at
      updated_at=$(echo "$pr" | jq -r '.updatedAt')

      if [[ "$updated_at" < "$START_DATE" ]]; then
        return 1  # Signal early exit
      fi

      local created_at
      created_at=$(echo "$pr" | jq -r '.createdAt')
      [[ "$created_at" > "$END_DATE" ]] && continue

      local author
      author=$(echo "$pr" | jq -r '.author.login // empty')
      [[ -z "$author" ]] && continue
      is_bot "$author" && continue

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
  }

  graphql_paginate "$GRAPHQL_QUERY_EXTENDED" "$OWNER" "$REPO_NAME" _collect_extended_page
}

# Collect open PRs only (for stuck-prs analysis)
# Sets: OPEN_PRS_FILE (path to JSONL file), OPEN_PR_COUNT
collect_open_prs() {
  OPEN_PRS_FILE=$(make_tmpfile)
  OPEN_PR_COUNT=0

  _collect_open_page() {
    local result
    result=$(cat)

    local pr_data
    pr_data=$(echo "$result" | jq -c '.data.repository.pullRequests.nodes[]?' 2>/dev/null)
    [[ -z "$pr_data" ]] && return 1

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
  }

  graphql_paginate "$GRAPHQL_QUERY_OPEN_PRS" "$OWNER" "$REPO_NAME" _collect_open_page
}
