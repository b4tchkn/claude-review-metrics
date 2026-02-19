#!/usr/bin/env bash
# Unit tests for datetime functions: iso_to_ts, iso_to_utc_ts, iso_to_local_hour,
# iso_to_local_dow, calculate_dates, detect_timezone

source "$PROJECT_DIR/scripts/lib/constants.sh"
source "$PROJECT_DIR/scripts/lib/datetime.sh"

# --- iso_to_ts ---

_ts=$(iso_to_ts "2025-01-15T12:30:00Z")
[[ "$_ts" -gt 0 ]] && _valid="yes" || _valid="no"
assert_eq "yes" "$_valid" "iso_to_ts: returns positive timestamp"

# Known epoch: 2025-01-01T00:00:00Z = 1735689600
_ts_known=$(TZ=UTC iso_to_ts "2025-01-01T00:00:00Z")
assert_eq "1735689600" "$_ts_known" "iso_to_ts: 2025-01-01 epoch"

# --- iso_to_utc_ts ---

_utc_ts=$(iso_to_utc_ts "2025-06-15T10:30:00Z")
[[ "$_utc_ts" -gt 0 ]] && _valid="yes" || _valid="no"
assert_eq "yes" "$_valid" "iso_to_utc_ts: returns positive timestamp"

# Same input should give same result regardless of local timezone
_utc1=$(TZ=UTC iso_to_utc_ts "2025-03-01T00:00:00Z")
_utc2=$(TZ=Asia/Tokyo iso_to_utc_ts "2025-03-01T00:00:00Z")
assert_eq "$_utc1" "$_utc2" "iso_to_utc_ts: consistent across timezones"

# Known epoch
_utc_known=$(iso_to_utc_ts "2025-01-01T00:00:00Z")
assert_eq "1735689600" "$_utc_known" "iso_to_utc_ts: 2025-01-01 epoch"

# --- iso_to_local_hour ---

# Force timezone to UTC so we can predict the hour
LOCAL_TZ="UTC"
_hour=$(iso_to_local_hour "2025-06-15T14:30:00Z")
assert_eq "14" "$_hour" "iso_to_local_hour: 14:30 UTC → hour 14"

_hour_midnight=$(iso_to_local_hour "2025-06-15T00:00:00Z")
assert_eq "00" "$_hour_midnight" "iso_to_local_hour: midnight UTC → hour 00"

_hour_23=$(iso_to_local_hour "2025-06-15T23:45:00Z")
assert_eq "23" "$_hour_23" "iso_to_local_hour: 23:45 UTC → hour 23"

# With timezone offset: UTC 15:00 = JST 00:00 (next day)
LOCAL_TZ="Asia/Tokyo"
_hour_jst=$(iso_to_local_hour "2025-06-15T15:00:00Z")
assert_eq "00" "$_hour_jst" "iso_to_local_hour: UTC 15:00 → JST 00:00"

# Reset
LOCAL_TZ="UTC"

# --- iso_to_local_dow ---

# 2025-01-06 is Monday (dow=1)
_dow_mon=$(iso_to_local_dow "2025-01-06T12:00:00Z")
assert_eq "1" "$_dow_mon" "iso_to_local_dow: 2025-01-06 is Monday"

# 2025-01-10 is Friday (dow=5)
_dow_fri=$(iso_to_local_dow "2025-01-10T12:00:00Z")
assert_eq "5" "$_dow_fri" "iso_to_local_dow: 2025-01-10 is Friday"

# 2025-01-12 is Sunday (dow=7)
_dow_sun=$(iso_to_local_dow "2025-01-12T12:00:00Z")
assert_eq "7" "$_dow_sun" "iso_to_local_dow: 2025-01-12 is Sunday"

# Timezone can shift the day: UTC 2025-01-06 23:00 → JST 2025-01-07 08:00 (Tuesday)
LOCAL_TZ="Asia/Tokyo"
_dow_shifted=$(iso_to_local_dow "2025-01-06T23:00:00Z")
assert_eq "2" "$_dow_shifted" "iso_to_local_dow: UTC Mon 23:00 → JST Tue"

# Reset
LOCAL_TZ="UTC"

# --- calculate_dates ---

# week: START_TS ≤ END_TS, label is "This Week"
calculate_dates "week"
assert_eq "This Week" "$PERIOD_LABEL" "calculate_dates: week label"
[[ "$START_TS" -le "$END_TS" ]] && _order="yes" || _order="no"
assert_eq "yes" "$_order" "calculate_dates: week START_TS ≤ END_TS"

# The range should be 4 days (Mon→Fri)
_diff=$(( END_TS - START_TS ))
assert_eq "$((4 * SECONDS_PER_DAY))" "$_diff" "calculate_dates: week spans 4 days"

# START_DATE_DISPLAY should be YYYY-MM-DD format
[[ "$START_DATE_DISPLAY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && _fmt="yes" || _fmt="no"
assert_eq "yes" "$_fmt" "calculate_dates: week date display format"

# START_DATE should have T00:00:00Z suffix
[[ "$START_DATE" == *"T00:00:00Z" ]] && _suffix="yes" || _suffix="no"
assert_eq "yes" "$_suffix" "calculate_dates: week START_DATE has T00:00:00Z"

# END_DATE should have T23:59:59Z suffix
[[ "$END_DATE" == *"T23:59:59Z" ]] && _suffix="yes" || _suffix="no"
assert_eq "yes" "$_suffix" "calculate_dates: week END_DATE has T23:59:59Z"

# last-week: should be 7 days before current week
calculate_dates "last-week"
assert_eq "Last Week" "$PERIOD_LABEL" "calculate_dates: last-week label"
_diff_lw=$(( END_TS - START_TS ))
assert_eq "$((4 * SECONDS_PER_DAY))" "$_diff_lw" "calculate_dates: last-week spans 4 days"

# last-week END_TS should be before this week's START_TS
calculate_dates "week"
_this_week_start=$START_TS
calculate_dates "last-week"
[[ "$END_TS" -lt "$_this_week_start" ]] && _before="yes" || _before="no"
assert_eq "yes" "$_before" "calculate_dates: last-week ends before this week starts"

# month: label and 30 day range
calculate_dates "month"
assert_eq "Last 30 Days" "$PERIOD_LABEL" "calculate_dates: month label"
_diff_month=$(( END_TS - START_TS ))
assert_eq "$((30 * SECONDS_PER_DAY))" "$_diff_month" "calculate_dates: month spans 30 days"

# --- detect_timezone ---

# When REVIEW_METRICS_TZ is set, it takes priority
REVIEW_METRICS_TZ="America/New_York"
_tz=$(detect_timezone)
assert_eq "America/New_York" "$_tz" "detect_timezone: REVIEW_METRICS_TZ override"
unset REVIEW_METRICS_TZ

# Default detection should return a non-empty string
_tz_default=$(detect_timezone)
[[ -n "$_tz_default" ]] && _nonempty="yes" || _nonempty="no"
assert_eq "yes" "$_nonempty" "detect_timezone: returns non-empty value"
