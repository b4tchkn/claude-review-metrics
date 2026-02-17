#!/usr/bin/env bash
# Output formatting functions

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

# Format duration from seconds to human-readable "Xd Xh Xm" format
format_duration() {
  local seconds=$1
  local days=$((seconds / SECONDS_PER_DAY))
  local hours=$(((seconds % SECONDS_PER_DAY) / SECONDS_PER_HOUR))
  local minutes=$(((seconds % SECONDS_PER_HOUR) / SECONDS_PER_MINUTE))

  if [[ $days -gt 0 ]]; then
    echo "${days}d ${hours}h ${minutes}m"
  elif [[ $hours -gt 0 ]]; then
    echo "${hours}h ${minutes}m"
  else
    echo "${minutes}m"
  fi
}

# Calculate percentile from sorted values on stdin
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
