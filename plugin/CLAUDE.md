# Review Metrics Plugin

Analyze GitHub PR review activity, team performance rankings, and review bottlenecks.

## Overview

- Invoked via `/review-metrics`
- Uses GitHub GraphQL API + REST API to collect review data
- **Rankings** (Top 3): comments, reviewed PRs, approved PRs, response time, fix time
- **Analysis** (Team-wide): bottleneck detection, stuck PRs, reviewer load, review cycles, PR size correlation
- Bot accounts automatically excluded (configure via `excluded-accounts.txt`)

## Directory Structure

```
claude-review-metrics/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest
├── skills/
│   └── review-metrics/
│       └── SKILL.md             # Skill definition (arguments, invocation rules)
├── scripts/
│   ├── dispatch.sh              # Unified entry point (routes commands to scripts)
│   ├── collect-metrics.sh       # Combined output of all rankings
│   ├── ranking-comments.sh      # Review comment count ranking
│   ├── ranking-reviewed.sh      # Reviewed PR count ranking
│   ├── ranking-approved.sh      # Approval count ranking
│   ├── ranking-response-time.sh # Response time ranking
│   ├── ranking-fix-time.sh      # Fix time ranking (standalone, uses REST API)
│   ├── analysis-bottleneck.sh   # PR lifecycle phase breakdown
│   ├── analysis-stuck-prs.sh    # Currently stuck PRs
│   ├── analysis-reviewer-load.sh# Team review workload distribution
│   ├── analysis-review-cycles.sh# Review round patterns
│   ├── analysis-pr-size.sh      # PR size vs speed correlation
│   └── lib/
│       ├── common.sh            # Facade: sources all sub-modules below
│       ├── constants.sh         # Named constants (thresholds, time values)
│       ├── tmpfile.sh           # make_tmpfile(), cleanup_tmpfiles(), EXIT trap
│       ├── args.sh              # parse_args(), is_bot(), EXCLUDED_BOTS
│       ├── datetime.sh          # calculate_dates(), iso_to_ts(), timezone detection
│       ├── format.sh            # print_header(), format_duration(), percentile(), classify_pr_size()
│       ├── graphql.sh           # GraphQL queries + graphql_paginate()
│       ├── collect-data.sh      # collect_data() for ranking scripts
│       ├── collect-data-extended.sh # collect_extended_data(), collect_open_prs()
│       ├── ranking-runner.sh    # run_ranking() shared boilerplate
│       └── analysis-runner.sh   # run_analysis() shared boilerplate
├── tests/
│   ├── test-runner.sh           # Test framework (assert_eq, assert_contains, run_tests)
│   ├── test-lib-functions.sh    # Unit tests for format, classify, percentile, is_bot, constants
│   ├── test-tmpfile.sh          # Unit tests for tmpfile management
│   └── test-dispatch.sh         # Unit tests for dispatch.sh routing
├── excluded-accounts.txt        # Bot accounts to exclude
├── CLAUDE.md                    # This file (development guide)
├── README.md                    # Plugin documentation
└── LICENSE                      # Apache 2.0
```

## Architecture

### Module System (`lib/`)

`common.sh` is a facade that sources all sub-modules. Scripts only need `source lib/common.sh`.

| Module | Responsibility |
|--------|---------------|
| `constants.sh` | Named constants: `SECONDS_PER_DAY`, `FIX_TIME_CAP_HOURS`, `STUCK_*_THRESHOLD`, `SENTINEL_EPOCH`, `INSTANT_APPROVAL_THRESHOLD` |
| `tmpfile.sh` | `make_tmpfile()` creates tracked temp files, `cleanup_tmpfiles()` removes them on EXIT via trap |
| `args.sh` | `parse_args()` parses `-p <period>` and repo argument, `is_bot()` checks `EXCLUDED_BOTS` array |
| `datetime.sh` | `calculate_dates()` computes date ranges, `iso_to_ts()` / `iso_to_utc_ts()` convert ISO8601 to timestamps, timezone detection |
| `format.sh` | `print_header()`, `format_duration()`, `percentile()`, `classify_pr_size()` |
| `graphql.sh` | Three GraphQL queries + `graphql_paginate()` generic pagination with callback |

### Runners (`lib/ranking-runner.sh`, `lib/analysis-runner.sh`)

Shared boilerplate for ranking and analysis scripts:

- `run_ranking(title, render_fn, "$@")` — parse args, collect data, call render function
- `run_analysis(title, analyze_fn, "$@")` — parse args, collect extended data, call analyze function

### Data Collection

| Module | Used By | Function |
|--------|---------|----------|
| `collect-data.sh` | Ranking scripts | `collect_data()` → `METRICS_FILE`, `RESPONSE_TIMES_FILE` |
| `collect-data-extended.sh` | Analysis scripts | `collect_extended_data()` → `PR_LIFECYCLE_FILE`, `collect_open_prs()` → `OPEN_PRS_FILE` |

Both use `graphql_paginate()` for pagination and `make_tmpfile()` for temp file management.

### Dispatch (`dispatch.sh`)

Unified entry point that routes `[period] [command] [repo]` to the appropriate script.

### Ranking Scripts (`ranking-*.sh`)

Top 3 rankings. Each defines a `render_*()` function and calls `run_ranking()`.

- Exception: `ranking-fix-time.sh` uses REST API directly (2-3 API calls per PR)

### Analysis Scripts (`analysis-*.sh`)

Team-wide analysis. Each defines an `analyze_*()` function and calls `run_analysis()`.

- Exception: `analysis-stuck-prs.sh` uses `collect_open_prs()` directly (no period)

| Script                      | Purpose                                                           | Uses Period?       |
| --------------------------- | ----------------------------------------------------------------- | ------------------ |
| `analysis-bottleneck.sh`    | Decompose PR lifecycle into Wait/Review/Merge phases with p50/p90 | Yes                |
| `analysis-stuck-prs.sh`     | Detect PRs needing immediate attention                            | No (current state) |
| `analysis-reviewer-load.sh` | Full team review workload and balance                             | Yes                |
| `analysis-review-cycles.sh` | Review round distribution and change-request patterns             | Yes                |
| `analysis-pr-size.sh`       | PR size bucket correlation with cycle time                        | Yes                |

## Metric Definitions

### Rankings

| Metric            | Calculation                                                            |
| ----------------- | ---------------------------------------------------------------------- |
| Review Comments   | Total review comments left during period                               |
| Reviewed PRs      | Unique PRs reviewed during period                                      |
| Approved PRs      | Unique PRs approved during period                                      |
| Avg Response Time | Time from review request to first review submission (average)          |
| Avg Fix Time      | Time from review comment to next commit (average, capped at 336 hours) |

### Analysis

| Metric          | Calculation                                                                   |
| --------------- | ----------------------------------------------------------------------------- |
| Wait for Review | Time from PR creation (or ready-for-review) to first review                   |
| Review Cycles   | Time from first review to last approval                                       |
| Merge Delay     | Time from last approval to merge                                              |
| Stuck PRs       | Open PRs with >24h no review, unaddressed changes, or >5 day age              |
| Reviewer Load   | Requested / completed / completion rate / avg response / pending per reviewer |
| Review Rounds   | Count of changes-requested + 1 per merged PR                                  |
| PR Size Buckets | XS (1-10), S (11-50), M (51-200), L (201-500), XL (500+) lines changed        |

## Testing

Run the test suite:

```bash
bash tests/test-runner.sh
```

Tests cover: `format_duration`, `classify_pr_size`, `percentile`, `is_bot`, constants, tmpfile management, and dispatch routing.

## Notes for Modification

- All scripts use `set -euo pipefail` strict mode
- All shebangs use `#!/usr/bin/env bash` for portability
- Tmpfiles are managed via `make_tmpfile()` and automatically cleaned up on EXIT
- macOS/Linux `date` command differences are handled by `iso_to_ts()`
- GitHub API rate limits apply. Ranking scripts use 1 call per 100 PRs; `ranking-fix-time.sh` makes 2-3 API calls per PR; analysis scripts use 1 call per 100 PRs with richer fields
- To add a new ranking: create `ranking-*.sh` with `run_ranking()`, add to `dispatch.sh` and SKILL.md
- To add a new analysis: create `analysis-*.sh` with `run_analysis()`, add to `dispatch.sh` and SKILL.md
- To add bot exclusions: edit `excluded-accounts.txt` in the plugin directory

## Dependencies

- `gh` (GitHub CLI) - must be authenticated
- `jq` - JSON processing
- `awk` - aggregation and percentile calculations


<claude-mem-context>
# Recent Activity

<!-- This section is auto-generated by claude-mem. Edit content outside the tags. -->

*No recent activity*
</claude-mem-context>