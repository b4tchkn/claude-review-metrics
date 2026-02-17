#!/usr/bin/env bash
# GraphQL queries and pagination

# GraphQL query for fetching PR review data
GRAPHQL_QUERY='
query($owner: String!, $repo: String!, $cursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequests(
      first: 100
      after: $cursor
      orderBy: { field: UPDATED_AT, direction: DESC }
    ) {
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
        number
        updatedAt
        timelineItems(first: 100, itemTypes: [REVIEW_REQUESTED_EVENT, PULL_REQUEST_REVIEW]) {
          nodes {
            __typename
            ... on ReviewRequestedEvent {
              createdAt
              requestedReviewer {
                ... on User { login }
              }
            }
            ... on PullRequestReview {
              author { login }
              state
              createdAt
              comments { totalCount }
            }
          }
        }
        reviews(first: 100) {
          nodes {
            author { login }
            state
            createdAt
            comments { totalCount }
          }
        }
      }
    }
  }
}
'

export GRAPHQL_QUERY

# GraphQL query for extended PR lifecycle data (used by analysis scripts)
GRAPHQL_QUERY_EXTENDED='
query($owner: String!, $repo: String!, $cursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequests(
      first: 100
      after: $cursor
      orderBy: { field: UPDATED_AT, direction: DESC }
    ) {
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
        number
        title
        state
        isDraft
        createdAt
        mergedAt
        closedAt
        updatedAt
        additions
        deletions
        changedFiles
        author { login }
        timelineItems(first: 100, itemTypes: [REVIEW_REQUESTED_EVENT, READY_FOR_REVIEW_EVENT, PULL_REQUEST_REVIEW, CONVERT_TO_DRAFT_EVENT]) {
          nodes {
            __typename
            ... on ReviewRequestedEvent {
              createdAt
              requestedReviewer {
                ... on User { login }
              }
            }
            ... on ReadyForReviewEvent {
              createdAt
            }
            ... on PullRequestReview {
              author { login }
              state
              createdAt
              comments { totalCount }
            }
            ... on ConvertToDraftEvent {
              createdAt
            }
          }
        }
      }
    }
  }
}
'

# GraphQL query for open PRs only (used by stuck-prs analysis)
GRAPHQL_QUERY_OPEN_PRS='
query($owner: String!, $repo: String!, $cursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequests(
      first: 100
      after: $cursor
      states: OPEN
      orderBy: { field: UPDATED_AT, direction: DESC }
    ) {
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
        number
        title
        isDraft
        createdAt
        updatedAt
        additions
        deletions
        changedFiles
        author { login }
        reviewRequests(first: 20) {
          nodes {
            requestedReviewer {
              ... on User { login }
            }
          }
        }
        timelineItems(first: 100, itemTypes: [REVIEW_REQUESTED_EVENT, PULL_REQUEST_REVIEW, PULL_REQUEST_COMMIT]) {
          nodes {
            __typename
            ... on ReviewRequestedEvent {
              createdAt
              requestedReviewer {
                ... on User { login }
              }
            }
            ... on PullRequestReview {
              author { login }
              state
              createdAt
            }
            ... on PullRequestCommit {
              commit {
                committedDate
              }
            }
          }
        }
      }
    }
  }
}
'

export GRAPHQL_QUERY_EXTENDED GRAPHQL_QUERY_OPEN_PRS

# Generic GraphQL pagination
# Usage: graphql_paginate "$query" "$owner" "$repo" callback_fn
# callback_fn receives the full API result JSON on stdin.
# If callback_fn returns non-zero, pagination stops (early exit).
graphql_paginate() {
  local query="$1" owner="$2" repo="$3" callback="$4"

  local cursor=""
  local has_next="true"

  while [[ "$has_next" == "true" ]]; do
    local result
    result=$(gh api graphql -f query="$query" \
      -F owner="$owner" -F repo="$repo" \
      ${cursor:+-F cursor="$cursor"} 2>/dev/null) || true

    has_next=$(echo "$result" | jq -r '.data.repository.pullRequests.pageInfo.hasNextPage // "false"' 2>/dev/null)
    cursor=$(echo "$result" | jq -r '.data.repository.pullRequests.pageInfo.endCursor // empty' 2>/dev/null)

    [[ "$has_next" == "null" || -z "$has_next" ]] && has_next="false"

    # Invoke callback with result; stop if callback signals early exit
    if ! echo "$result" | "$callback"; then
      break
    fi
  done
}
