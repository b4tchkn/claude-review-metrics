#!/usr/bin/env bash
# Unit tests for dispatch.sh --dry-run mode

_dispatch() {
  bash "$PROJECT_DIR/scripts/dispatch.sh" --dry-run "$@" 2>/dev/null
}

# --- Default: all rankings with week period ---
_out=$(_dispatch)
assert_contains "$_out" "collect-metrics.sh" "dispatch: default runs collect-metrics"
assert_contains "$_out" "-p week" "dispatch: default period is week"

# --- Period parsing ---
_out=$(_dispatch last-week)
assert_contains "$_out" "-p last-week" "dispatch: last-week period"

_out=$(_dispatch month)
assert_contains "$_out" "-p month" "dispatch: month period"

# --- Command routing ---
_out=$(_dispatch week comments)
assert_contains "$_out" "ranking-comments.sh" "dispatch: comments → ranking-comments"

_out=$(_dispatch week reviewed)
assert_contains "$_out" "ranking-reviewed.sh" "dispatch: reviewed → ranking-reviewed"

_out=$(_dispatch week approved)
assert_contains "$_out" "ranking-approved.sh" "dispatch: approved → ranking-approved"

_out=$(_dispatch week response-time)
assert_contains "$_out" "ranking-response-time.sh" "dispatch: response-time → ranking-response-time"

_out=$(_dispatch week fix-time)
assert_contains "$_out" "ranking-fix-time.sh" "dispatch: fix-time → ranking-fix-time"

_out=$(_dispatch week bottleneck)
assert_contains "$_out" "analysis-bottleneck.sh" "dispatch: bottleneck → analysis-bottleneck"

_out=$(_dispatch week stuck)
assert_contains "$_out" "analysis-stuck-prs.sh" "dispatch: stuck → analysis-stuck-prs"

_out=$(_dispatch week reviewer-load)
assert_contains "$_out" "analysis-reviewer-load.sh" "dispatch: reviewer-load → analysis-reviewer-load"

_out=$(_dispatch week cycles)
assert_contains "$_out" "analysis-review-cycles.sh" "dispatch: cycles → analysis-review-cycles"

_out=$(_dispatch week pr-size)
assert_contains "$_out" "analysis-pr-size.sh" "dispatch: pr-size → analysis-pr-size"

# --- Stuck omits -p flag ---
_out=$(_dispatch last-week stuck)
# stuck should not have "-p last-week" in its args
[[ "$_out" != *"-p last-week"* ]] && _no_p="yes" || _no_p="no"
assert_eq "yes" "$_no_p" "dispatch: stuck omits -p flag"

# --- Repo passthrough ---
_out=$(_dispatch week comments owner/repo)
assert_contains "$_out" "owner/repo" "dispatch: repo is passed through"
