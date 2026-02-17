#!/usr/bin/env bash
# Argument parsing and bot exclusion

# Excluded bot accounts
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
