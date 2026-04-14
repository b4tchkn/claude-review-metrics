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

# Horizontal bar graph: █ filled, ░ empty
# Usage: graph_bar <value> <max_value> [width]
graph_bar() {
  local value=$1 max_value=$2 width=${3:-$GRAPH_BAR_WIDTH}
  local filled=0

  if [[ $max_value -gt 0 && $value -gt 0 ]]; then
    filled=$((value * width / max_value))
    [[ $filled -eq 0 ]] && filled=1
    [[ $filled -gt $width ]] && filled=$width
  fi

  local empty=$((width - filled))
  local bar=""
  local i
  for ((i = 0; i < filled; i++)); do bar+="█"; done
  for ((i = 0; i < empty; i++)); do bar+="░"; done
  printf '%s' "$bar"
}

# Stacked bar graph: █ phase1, ▓ phase2, ░ phase3
# Usage: graph_stacked_bar <val1> <val2> <val3> [width]
graph_stacked_bar() {
  local val1=$1 val2=$2 val3=$3 width=${4:-$GRAPH_BAR_WIDTH}
  local total=$((val1 + val2 + val3))

  if [[ $total -le 0 ]]; then
    local bar=""
    local i
    for ((i = 0; i < width; i++)); do bar+="░"; done
    printf '%s' "$bar"
    return
  fi

  local seg1=$((val1 * width / total))
  local seg2=$((val2 * width / total))
  local seg3=$((width - seg1 - seg2))

  # Ensure non-zero values get at least 1 character
  if [[ $val1 -gt 0 && $seg1 -eq 0 ]]; then
    seg1=1
    if [[ $seg3 -gt 1 ]]; then seg3=$((seg3 - 1))
    elif [[ $seg2 -gt 1 ]]; then seg2=$((seg2 - 1))
    fi
  fi
  if [[ $val2 -gt 0 && $seg2 -eq 0 ]]; then
    seg2=1
    if [[ $seg3 -gt 1 ]]; then seg3=$((seg3 - 1))
    elif [[ $seg1 -gt 1 ]]; then seg1=$((seg1 - 1))
    fi
  fi
  if [[ $val3 -gt 0 && $seg3 -eq 0 ]]; then
    seg3=1
    if [[ $seg1 -gt 1 ]]; then seg1=$((seg1 - 1))
    elif [[ $seg2 -gt 1 ]]; then seg2=$((seg2 - 1))
    fi
  fi

  local bar=""
  local i
  for ((i = 0; i < seg1; i++)); do bar+="█"; done
  for ((i = 0; i < seg2; i++)); do bar+="▓"; done
  for ((i = 0; i < seg3; i++)); do bar+="░"; done
  printf '%s' "$bar"
}

# Sparkline percentage bar: ▰ filled, ▱ empty
# Usage: graph_sparkline <percentage> [width]
graph_sparkline() {
  local pct=$1 width=${2:-10}
  local filled=0

  if [[ $pct -gt 0 ]]; then
    filled=$((pct * width / 100))
    [[ $filled -eq 0 ]] && filled=1
    [[ $filled -gt $width ]] && filled=$width
  fi

  local empty=$((width - filled))
  local bar=""
  local i
  for ((i = 0; i < filled; i++)); do bar+="▰"; done
  for ((i = 0; i < empty; i++)); do bar+="▱"; done
  printf '%s' "$bar"
}
