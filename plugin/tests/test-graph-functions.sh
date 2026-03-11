#!/usr/bin/env bash
# Unit tests for graph functions: graph_bar, graph_stacked_bar, graph_sparkline

source "$PROJECT_DIR/scripts/lib/constants.sh"
source "$PROJECT_DIR/scripts/lib/format.sh"

# --- graph_bar ---

_bar=$(graph_bar 10 10 10)
assert_eq "██████████" "$_bar" "graph_bar: full bar"

_bar=$(graph_bar 5 10 10)
assert_eq "█████░░░░░" "$_bar" "graph_bar: half bar"

_bar=$(graph_bar 0 10 10)
assert_eq "░░░░░░░░░░" "$_bar" "graph_bar: empty bar"

_bar=$(graph_bar 1 100 10)
assert_eq "█░░░░░░░░░" "$_bar" "graph_bar: minimum 1 char for positive value"

_bar=$(graph_bar 20 10 10)
assert_eq "██████████" "$_bar" "graph_bar: value exceeds max capped"

_bar=$(graph_bar 5 0 10)
assert_eq "░░░░░░░░░░" "$_bar" "graph_bar: max_value 0 returns empty"

_bar=$(graph_bar 0 0 10)
assert_eq "░░░░░░░░░░" "$_bar" "graph_bar: both zero returns empty"

_bar=$(graph_bar 7 10 40)
_len=${#_bar}
assert_eq "40" "$_len" "graph_bar: output width matches specified width"

# --- graph_stacked_bar ---

_bar=$(graph_stacked_bar 10 0 0 10)
assert_eq "██████████" "$_bar" "graph_stacked_bar: all phase1"

_bar=$(graph_stacked_bar 0 10 0 10)
assert_eq "▓▓▓▓▓▓▓▓▓▓" "$_bar" "graph_stacked_bar: all phase2"

_bar=$(graph_stacked_bar 0 0 10 10)
assert_eq "░░░░░░░░░░" "$_bar" "graph_stacked_bar: all phase3"

_bar=$(graph_stacked_bar 0 0 0 10)
assert_eq "░░░░░░░░░░" "$_bar" "graph_stacked_bar: all zeros"

_bar=$(graph_stacked_bar 5 3 2 10)
_len=${#_bar}
assert_eq "10" "$_len" "graph_stacked_bar: output width matches"
assert_contains "$_bar" "█" "graph_stacked_bar: contains phase1 chars"
assert_contains "$_bar" "▓" "graph_stacked_bar: contains phase2 chars"
assert_contains "$_bar" "░" "graph_stacked_bar: contains phase3 chars"

# Ensure non-zero values get at least 1 character
_bar=$(graph_stacked_bar 1 1 100 10)
assert_contains "$_bar" "█" "graph_stacked_bar: small val1 gets at least 1 char"
assert_contains "$_bar" "▓" "graph_stacked_bar: small val2 gets at least 1 char"

# --- graph_sparkline ---

_bar=$(graph_sparkline 100 10)
assert_eq "▰▰▰▰▰▰▰▰▰▰" "$_bar" "graph_sparkline: 100%"

_bar=$(graph_sparkline 50 10)
assert_eq "▰▰▰▰▰▱▱▱▱▱" "$_bar" "graph_sparkline: 50%"

_bar=$(graph_sparkline 0 10)
assert_eq "▱▱▱▱▱▱▱▱▱▱" "$_bar" "graph_sparkline: 0%"

_bar=$(graph_sparkline 1 10)
assert_eq "▰▱▱▱▱▱▱▱▱▱" "$_bar" "graph_sparkline: 1% gets minimum 1 char"

_bar=$(graph_sparkline 75 10)
_len=${#_bar}
assert_eq "10" "$_len" "graph_sparkline: output width matches"
