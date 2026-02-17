#!/usr/bin/env bash
# Date/time calculation and conversion functions

# Calculate date range based on period
calculate_dates() {
  local period=$1
  local now_ts=$(date +%s)
  local day_of_week=$(date +%u) # 1=Mon, 7=Sun

  case $period in
    week)
      local days_to_monday=$((day_of_week - 1))
      local monday_ts=$((now_ts - days_to_monday * SECONDS_PER_DAY))
      local friday_ts=$((monday_ts + 4 * SECONDS_PER_DAY))
      START_TS=$monday_ts
      END_TS=$friday_ts
      PERIOD_LABEL="This Week"
      ;;
    last-week)
      local days_to_monday=$((day_of_week - 1 + 7))
      local monday_ts=$((now_ts - days_to_monday * SECONDS_PER_DAY))
      local friday_ts=$((monday_ts + 4 * SECONDS_PER_DAY))
      START_TS=$monday_ts
      END_TS=$friday_ts
      PERIOD_LABEL="Last Week"
      ;;
    month)
      START_TS=$((now_ts - 30 * SECONDS_PER_DAY))
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
detect_timezone() {
  if [[ -n "${REVIEW_METRICS_TZ:-}" ]]; then
    echo "$REVIEW_METRICS_TZ"
    return
  fi
  if [[ -f /etc/localtime ]]; then
    local tz
    tz=$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||' || true)
    if [[ -n "$tz" ]]; then
      echo "$tz"
      return
    fi
  fi
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
  echo "${TZ:-UTC}"
}

# Cache timezone at source time
LOCAL_TZ=$(detect_timezone)
export LOCAL_TZ

# Convert ISO date to timestamp
iso_to_ts() {
  local iso_date="$1"
  if date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso_date" +%s 2>/dev/null; then
    return
  fi
  date -d "$iso_date" +%s 2>/dev/null || echo "0"
}

# Convert ISO date (UTC) to Unix timestamp correctly
iso_to_utc_ts() {
  local iso_date="$1"
  local stripped="${iso_date%Z}"
  TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" "+%s" 2>/dev/null \
    || date -d "$iso_date" "+%s" 2>/dev/null \
    || echo "0"
}

# Convert ISO date (UTC) to local hour (0-23)
iso_to_local_hour() {
  local iso_date="$1"
  local ts
  ts=$(iso_to_utc_ts "$iso_date")
  [[ "$ts" -eq 0 ]] && echo "0" && return
  TZ="$LOCAL_TZ" date -r "$ts" "+%H" 2>/dev/null \
    || TZ="$LOCAL_TZ" date -d "@$ts" "+%H" 2>/dev/null \
    || echo "0"
}

# Convert ISO date (UTC) to local day of week (1=Mon, 7=Sun)
iso_to_local_dow() {
  local iso_date="$1"
  local ts
  ts=$(iso_to_utc_ts "$iso_date")
  [[ "$ts" -eq 0 ]] && echo "0" && return
  TZ="$LOCAL_TZ" date -r "$ts" "+%u" 2>/dev/null \
    || TZ="$LOCAL_TZ" date -d "@$ts" "+%u" 2>/dev/null \
    || echo "0"
}
