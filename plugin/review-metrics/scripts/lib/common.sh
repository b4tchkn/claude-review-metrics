#!/bin/bash
# Common functions and variables for review metrics scripts

set -euo pipefail

# Excluded bot accounts
# Configure by editing excluded-accounts.txt (one account per line) in the skill directory.
# If the file does not exist, no accounts are excluded.
EXCLUDED_BOTS=()

_load_excluded_bots() {
  local _common_dir
  _common_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local config_file="$_common_dir/../../excluded-accounts.txt"
  [[ ! -f "$config_file" ]] && return

  while IFS= read -r line; do
    line="${line%%#*}"   # strip comments
    line="${line// /}"   # strip spaces
    [[ -n "$line" ]] && EXCLUDED_BOTS+=("$line")
  done < "$config_file"
}

_load_excluded_bots

# Check if reviewer is a bot
is_bot() {
  local reviewer="$1"
  if [[ ${#EXCLUDED_BOTS[@]} -gt 0 ]]; then
    for bot in "${EXCLUDED_BOTS[@]}"; do
      [[ "$reviewer" == "$bot" ]] && return 0
    done
  fi
  return 1
}

# Parse common arguments
parse_args() {
  PERIOD="week"
  REPO=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      --period=*)
        PERIOD="${1#*=}"
        shift
        ;;
      -p)
        PERIOD="$2"
        shift 2
        ;;
      -*)
        echo "Unknown option: $1"
        echo "Usage: $0 [--period=<week|last-week|month>] [REPO]"
        exit 1
        ;;
      *)
        REPO="$1"
        shift
        ;;
    esac
  done

  # Auto-detect repo if not specified
  if [[ -z "$REPO" ]]; then
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo '')
  fi

  if [[ -z "$REPO" ]]; then
    echo "Error: Repository not specified and not in a git repository"
    echo "Usage: $0 [--period=<week|last-week|month>] <owner/repo>"
    exit 1
  fi

  OWNER="${REPO%%/*}"
  REPO_NAME="${REPO##*/}"

  export PERIOD REPO OWNER REPO_NAME
}

# Calculate date range based on period
calculate_dates() {
  local period=$1
  local now_ts=$(date +%s)
  local day_of_week=$(date +%u) # 1=Mon, 7=Sun

  case $period in
    week)
      local days_to_monday=$((day_of_week - 1))
      local monday_ts=$((now_ts - days_to_monday * 86400))
      local friday_ts=$((monday_ts + 4 * 86400))
      START_TS=$monday_ts
      END_TS=$friday_ts
      PERIOD_LABEL="This Week"
      ;;
    last-week)
      local days_to_monday=$((day_of_week - 1 + 7))
      local monday_ts=$((now_ts - days_to_monday * 86400))
      local friday_ts=$((monday_ts + 4 * 86400))
      START_TS=$monday_ts
      END_TS=$friday_ts
      PERIOD_LABEL="Last Week"
      ;;
    month)
      START_TS=$((now_ts - 30 * 86400))
      END_TS=$now_ts
      PERIOD_LABEL="Last 30 Days"
      ;;
    *)
      echo "Error: Invalid period '$period'"
      echo "Valid periods: week, last-week, month"
      exit 1
      ;;
  esac

  START_DATE_DISPLAY=$(date -r $START_TS +%Y-%m-%d 2>/dev/null || date -d "@$START_TS" +%Y-%m-%d)
  END_DATE_DISPLAY=$(date -r $END_TS +%Y-%m-%d 2>/dev/null || date -d "@$END_TS" +%Y-%m-%d)
  START_DATE="${START_DATE_DISPLAY}T00:00:00Z"
  END_DATE="${END_DATE_DISPLAY}T23:59:59Z"

  export START_TS END_TS PERIOD_LABEL START_DATE_DISPLAY END_DATE_DISPLAY START_DATE END_DATE
}

# Detect local timezone for display purposes
# Returns IANA timezone (e.g., Asia/Tokyo, America/New_York)
detect_timezone() {
  # 1. Use explicit override if set
  if [[ -n "${REVIEW_METRICS_TZ:-}" ]]; then
    echo "$REVIEW_METRICS_TZ"
    return
  fi
  # 2. macOS: read system timezone
  if [[ -f /etc/localtime ]]; then
    local tz
    tz=$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||' || true)
    if [[ -n "$tz" ]]; then
      echo "$tz"
      return
    fi
  fi
  # 3. Linux: timedatectl or /etc/timezone
  if command -v timedatectl &>/dev/null; then
    local tz
    tz=$(timedatectl show -p Timezone --value 2>/dev/null || true)
    if [[ -n "$tz" ]]; then
      echo "$tz"
      return
    fi
  fi
  if [[ -f /etc/timezone ]]; then
    cat /etc/timezone
    return
  fi
  # 4. Fallback to TZ env or UTC
  echo "${TZ:-UTC}"
}

# Cache timezone at source time
LOCAL_TZ=$(detect_timezone)
export LOCAL_TZ

# Helper function to convert ISO date to timestamp
iso_to_ts() {
  local iso_date="$1"
  if date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso_date" +%s 2>/dev/null; then
    return
  fi
  date -d "$iso_date" +%s 2>/dev/null || echo "0"
}

# Convert ISO date (UTC) to Unix timestamp correctly
# macOS date -j -f interprets input in local TZ, so we force TZ=UTC for parsing
iso_to_utc_ts() {
  local iso_date="$1"
  local stripped="${iso_date%Z}"  # Remove trailing Z
  TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" "+%s" 2>/dev/null \
    || date -d "$iso_date" "+%s" 2>/dev/null \
    || echo "0"
}

# Convert ISO date (UTC) to local hour (0-23) using detected timezone
iso_to_local_hour() {
  local iso_date="$1"
  local ts
  ts=$(iso_to_utc_ts "$iso_date")
  [[ "$ts" -eq 0 ]] && echo "0" && return
  # macOS: date -r <ts>, Linux: date -d @<ts>
  TZ="$LOCAL_TZ" date -r "$ts" "+%H" 2>/dev/null \
    || TZ="$LOCAL_TZ" date -d "@$ts" "+%H" 2>/dev/null \
    || echo "0"
}

# Convert ISO date (UTC) to local day of week (1=Mon, 7=Sun) using detected timezone
iso_to_local_dow() {
  local iso_date="$1"
  local ts
  ts=$(iso_to_utc_ts "$iso_date")
  [[ "$ts" -eq 0 ]] && echo "0" && return
  TZ="$LOCAL_TZ" date -r "$ts" "+%u" 2>/dev/null \
    || TZ="$LOCAL_TZ" date -d "@$ts" "+%u" 2>/dev/null \
    || echo "0"
}

# Print header
print_header() {
  local title="$1"
  echo "=========================================="
  echo "  $title - $PERIOD_LABEL"
  echo "=========================================="
  echo "Repository: $REPO"
  echo "Period: $START_DATE_DISPLAY ~ $END_DATE_DISPLAY"
  echo ""
}

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

# Format duration from seconds to human-readable "Xd Xh Xm" format
format_duration() {
  local seconds=$1
  local days=$((seconds / 86400))
  local hours=$(((seconds % 86400) / 3600))
  local minutes=$(((seconds % 3600) / 60))

  if [[ $days -gt 0 ]]; then
    echo "${days}d ${hours}h ${minutes}m"
  elif [[ $hours -gt 0 ]]; then
    echo "${hours}h ${minutes}m"
  else
    echo "${minutes}m"
  fi
}

# Calculate percentile from sorted values on stdin
# Usage: echo -e "1\n2\n3\n4\n5" | percentile 50
percentile() {
  local p=$1
  awk -v p="$p" '
    { vals[NR] = $1; n = NR }
    END {
      if (n == 0) { print 0; exit }
      idx = (p / 100.0) * (n - 1) + 1
      if (idx <= 1) { print vals[1]; exit }
      if (idx >= n) { print vals[n]; exit }
      lo = int(idx)
      frac = idx - lo
      print int(vals[lo] + frac * (vals[lo+1] - vals[lo]))
    }
  '
}

# Classify PR size by total line changes
# Usage: classify_pr_size 150  → "M"
classify_pr_size() {
  local lines=$1
  if [[ $lines -le 10 ]]; then
    echo "XS"
  elif [[ $lines -le 50 ]]; then
    echo "S"
  elif [[ $lines -le 200 ]]; then
    echo "M"
  elif [[ $lines -le 500 ]]; then
    echo "L"
  else
    echo "XL"
  fi
}
