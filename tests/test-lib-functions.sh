#!/usr/bin/env bash
# Unit tests for lib functions: format_duration, classify_pr_size, percentile, is_bot, parse_args

# Source the library (sets strict mode and loads all modules)
source "$PROJECT_DIR/scripts/lib/constants.sh"
source "$PROJECT_DIR/scripts/lib/format.sh"
source "$PROJECT_DIR/scripts/lib/args.sh"

# --- format_duration ---

assert_eq "0m" "$(format_duration 0)" "format_duration: 0 seconds"
assert_eq "1m" "$(format_duration 60)" "format_duration: 1 minute"
assert_eq "5m" "$(format_duration 300)" "format_duration: 5 minutes"
assert_eq "1h 0m" "$(format_duration 3600)" "format_duration: 1 hour"
assert_eq "1h 30m" "$(format_duration 5400)" "format_duration: 1.5 hours"
assert_eq "1d 0h 0m" "$(format_duration 86400)" "format_duration: 1 day"
assert_eq "2d 3h 15m" "$(format_duration $((2*86400 + 3*3600 + 15*60)))" "format_duration: 2d 3h 15m"

# --- classify_pr_size ---

assert_eq "XS" "$(classify_pr_size 1)" "classify_pr_size: 1 line"
assert_eq "XS" "$(classify_pr_size 10)" "classify_pr_size: 10 lines"
assert_eq "S" "$(classify_pr_size 11)" "classify_pr_size: 11 lines"
assert_eq "S" "$(classify_pr_size 50)" "classify_pr_size: 50 lines"
assert_eq "M" "$(classify_pr_size 51)" "classify_pr_size: 51 lines"
assert_eq "M" "$(classify_pr_size 200)" "classify_pr_size: 200 lines"
assert_eq "L" "$(classify_pr_size 201)" "classify_pr_size: 201 lines"
assert_eq "L" "$(classify_pr_size 500)" "classify_pr_size: 500 lines"
assert_eq "XL" "$(classify_pr_size 501)" "classify_pr_size: 501 lines"
assert_eq "XL" "$(classify_pr_size 10000)" "classify_pr_size: 10000 lines"

# --- percentile ---

_p50=$(printf "%s\n" 1 2 3 4 5 | percentile 50)
assert_eq "3" "$_p50" "percentile: p50 of 1-5"

_p90=$(printf "%s\n" 1 2 3 4 5 6 7 8 9 10 | percentile 90)
assert_eq "9" "$_p90" "percentile: p90 of 1-10"

_p0=$(printf "" | percentile 50)
assert_eq "0" "$_p0" "percentile: empty input"

_p_single=$(echo "42" | percentile 50)
assert_eq "42" "$_p_single" "percentile: single value"

# --- is_bot ---

# Reset and test with known bots
EXCLUDED_BOTS=("dependabot[bot]" "renovate[bot]")

is_bot "dependabot[bot]" && _is_bot_result="yes" || _is_bot_result="no"
assert_eq "yes" "$_is_bot_result" "is_bot: dependabot is bot"

is_bot "renovate[bot]" && _is_bot_result="yes" || _is_bot_result="no"
assert_eq "yes" "$_is_bot_result" "is_bot: renovate is bot"

is_bot "realuser" && _is_bot_result="yes" || _is_bot_result="no"
assert_eq "no" "$_is_bot_result" "is_bot: realuser is not bot"

# Reset bots
EXCLUDED_BOTS=()
is_bot "anyone" && _is_bot_result="yes" || _is_bot_result="no"
assert_eq "no" "$_is_bot_result" "is_bot: empty list means no bots"

# --- constants ---

assert_eq "86400" "$SECONDS_PER_DAY" "constant: SECONDS_PER_DAY"
assert_eq "3600" "$SECONDS_PER_HOUR" "constant: SECONDS_PER_HOUR"
assert_eq "336" "$FIX_TIME_CAP_HOURS" "constant: FIX_TIME_CAP_HOURS"
assert_eq "99999999999" "$SENTINEL_EPOCH" "constant: SENTINEL_EPOCH"
assert_eq "300" "$INSTANT_APPROVAL_THRESHOLD" "constant: INSTANT_APPROVAL_THRESHOLD"
