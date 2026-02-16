# Review Metrics Skill

Analyze GitHub PR review activity, team performance rankings, and review bottlenecks.

## Overview

- Invoked via `/review-metrics`
- Uses GitHub GraphQL API + REST API to collect review data
- **Rankings** (Top 3): comments, reviewed PRs, approved PRs, response time, fix time
- **Analysis** (Team-wide): bottleneck detection, stuck PRs, reviewer load, review cycles, PR size correlation
- Bot accounts automatically excluded (copilot, devin-ai, github-actions, renovate-approve)

## Directory Structure

```
.claude/skills/review-metrics/
├── CLAUDE.md          # This file (development guide)
├── SKILL.md           # Skill definition (arguments, invocation rules)
└── scripts/
    ├── collect-metrics.sh           # Combined output of all rankings
    ├── ranking-comments.sh          # Review comment count ranking
    ├── ranking-reviewed.sh          # Reviewed PR count ranking
    ├── ranking-approved.sh          # Approval count ranking
    ├── ranking-response-time.sh     # Response time ranking
    ├── ranking-fix-time.sh          # Fix time ranking (standalone)
    ├── analysis-bottleneck.sh       # PR lifecycle phase breakdown
    ├── analysis-stuck-prs.sh        # Currently stuck PRs
    ├── analysis-reviewer-load.sh    # Team review workload distribution
    ├── analysis-review-cycles.sh    # Review round patterns
    ├── analysis-pr-size.sh          # PR size vs speed correlation
    └── lib/
        ├── common.sh                # Shared functions, constants, GraphQL queries
        ├── collect-data.sh          # Data collection for ranking scripts
        └── collect-data-extended.sh # Extended data collection for analysis scripts
```

## Architecture

### Shared Library (`lib/common.sh`)

Sourced by all scripts. Provides:

- `parse_args()` - Parses `-p <period>` / `--period=<period>` and repository argument
- `calculate_dates()` - Computes `START_DATE` / `END_DATE` from period (week=Mon-Fri this week, last-week=Mon-Fri previous week, month=last 30 days)
- `is_bot()` - Checks against `EXCLUDED_BOTS` array
- `iso_to_ts()` - ISO8601 to Unix timestamp (supports both macOS `date -j` and Linux `date -d`)
- `print_header()` - Standardized header output
- `format_duration()` - Seconds to human-readable `Xd Xh Xm` format
- `percentile()` - Calculate p50/p90/p95 from sorted values (awk)
- `classify_pr_size()` - Classify line changes into XS/S/M/L/XL buckets
- `GRAPHQL_QUERY` - GraphQL query for fetching PR review timeline and review data (used by ranking scripts)
- `GRAPHQL_QUERY_EXTENDED` - Extended GraphQL query with full PR lifecycle data (createdAt, mergedAt, additions, deletions, changedFiles, isDraft, timeline events)
- `GRAPHQL_QUERY_OPEN_PRS` - Open PR-only GraphQL query with `states: OPEN` filter

### Data Collection (`lib/collect-data.sh`)

Used by ranking scripts. `collect_data()` calls GraphQL API with pagination:

- `METRICS_FILE` - Per-reviewer JSON: `{reviewedPRs, approvedPRs, comments}`
- `RESPONSE_TIMES_FILE` - Per-reviewer JSON: `{totalSeconds, count}`
- `PR_COUNT` - Total PRs processed

### Extended Data Collection (`lib/collect-data-extended.sh`)

Used by analysis scripts. Separate from `collect-data.sh` to avoid impacting existing ranking scripts.

- `collect_extended_data()` - Fetches full PR lifecycle data as JSONL to `PR_LIFECYCLE_FILE`
- `collect_open_prs()` - Fetches open PRs only to `OPEN_PRS_FILE` (used by stuck-prs)

### Ranking Scripts (`ranking-*.sh`)

Top 3 rankings. Flow: source `lib/common.sh` → `parse_args` → `calculate_dates` → data collection → ranking output.

- `ranking-fix-time.sh` uses REST API (`pulls/{n}/comments`, `pulls/{n}/commits`), making 2-3 API calls per PR

### Analysis Scripts (`analysis-*.sh`)

Team-wide analysis. Flow: source `lib/common.sh` + `lib/collect-data-extended.sh` → `parse_args` → `calculate_dates` → extended data collection → analysis output.

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

## Notes for Modification

- All scripts use `set -euo pipefail` strict mode
- Tmpfiles are cleaned up via `trap` on EXIT
- macOS/Linux `date` command differences are handled by `iso_to_ts()`
- GitHub API rate limits apply. `collect-data.sh` uses pagination (1 call per 100 PRs); `ranking-fix-time.sh` makes 2-3 API calls per PR; analysis scripts use `collect-data-extended.sh` (1 call per 100 PRs with richer fields)
- To add a new ranking: create `ranking-*.sh`, add argument mapping in SKILL.md
- To add a new analysis: create `analysis-*.sh`, add argument mapping in SKILL.md
- To add bot exclusions: edit `EXCLUDED_BOTS` in `lib/common.sh`

## Dependencies

- `gh` (GitHub CLI) - must be authenticated
- `jq` - JSON processing
- `awk` - aggregation and percentile calculations
