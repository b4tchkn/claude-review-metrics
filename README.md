<div align="center">
  <a href="https://github.com/b4tchkn/claude-review-metrics">
    <img src="https://github.com/b4tchkn/claude-review-metrics/raw/main/art/logo.png" width="720px" alt="claude_review_metrics" />
  </a>
</div>

A Claude Code plugin that analyzes GitHub PR review activity, team performance rankings, and review bottlenecks.

## Installation

```bash
claude plugin add b4tchkn/claude-review-metrics
```

## Usage

```
/review-metrics                              # All rankings (current week)
/review-metrics last-week                    # All rankings (previous week)
/review-metrics month comments               # Comment ranking (last 30 days)
/review-metrics last-week response-time      # Response time ranking
/review-metrics bottleneck                   # PR lifecycle bottleneck analysis
/review-metrics stuck                        # Currently stuck PRs
/review-metrics last-week reviewer-load      # Team review workload
/review-metrics last-week cycles             # Review round patterns
/review-metrics month pr-size                # PR size vs review speed
```

## Features

### Rankings (Top 3)

| Command         | Description                                                     |
| --------------- | --------------------------------------------------------------- |
| `comments`      | Review comment count                                            |
| `reviewed`      | Reviewed PR count                                               |
| `approved`      | Approval count                                                  |
| `response-time` | Avg time from review request to first review                    |
| `fix-time`      | Avg time from review comment to next commit (capped at 2 weeks) |

### Analysis (Team-wide)

| Command         | Description                                                                                    |
| --------------- | ---------------------------------------------------------------------------------------------- |
| `bottleneck`    | PR lifecycle phase breakdown (wait/review/merge) with Avg, p50, p90 and actionable suggestions |
| `stuck`         | Open PRs needing immediate attention (ignores period, always shows current state)              |
| `reviewer-load` | Team review workload distribution with load balance warnings                                   |
| `cycles`        | Review round counts, change-request patterns, and high-cycle PR detection                      |
| `pr-size`       | PR size (XS/S/M/L/XL) vs review speed correlation                                              |

### Period Options

| Period      | Description                      |
| ----------- | -------------------------------- |
| `week`      | Current week (Mon-Fri) - default |
| `last-week` | Previous week (Mon-Fri)          |
| `month`     | Last 30 days                     |

## How It Works

### Data Collection

- **Rankings** use GitHub GraphQL API to fetch merged PR review data with automatic pagination
- **Analysis** scripts use an extended GraphQL query for full PR lifecycle data (timeline events, review requests, commits)
- **Fix Time** ranking uses GitHub REST API (2-3 calls per PR) to correlate review comments with subsequent commits
- **Stuck PRs** queries only open PRs, independent of period

### Metrics Definitions

| Metric          | Definition                                                                     |
| --------------- | ------------------------------------------------------------------------------ |
| Response Time   | Time from `ReviewRequestedEvent` to first `PullRequestReview` by that reviewer |
| Fix Time        | Time from review comment to next commit (capped at 336 hours / 2 weeks)        |
| Wait for Review | Time from PR creation (or `ReadyForReviewEvent`) to first review               |
| Review Cycles   | Time from first review to last approval                                        |
| Merge Delay     | Time from last approval to merge                                               |
| Review Rounds   | `changes_requested_count + 1` (if approved)                                    |
| PR Size         | Total changed lines: XS (1-10), S (11-50), M (51-200), L (201-500), XL (500+)  |

### Bot Filtering

Bot accounts listed in `plugin/excluded-accounts.txt` are automatically excluded from all metrics. Currently excludes `github-actions`. Add one account name per line to customize.

## Requirements

- GitHub CLI (`gh`) installed and authenticated
- `jq` for JSON processing
- `bash`, `awk` (standard Unix tools)
- macOS and Linux supported

## Development

### Project Structure

```
plugin/
├── scripts/
│   ├── dispatch.sh              # Command router (entry point)
│   ├── collect-metrics.sh       # Aggregates all rankings
│   ├── ranking-comments.sh      # Review comment count ranking
│   ├── ranking-reviewed.sh      # Reviewed PR count ranking
│   ├── ranking-approved.sh      # Approval count ranking
│   ├── ranking-response-time.sh # Response time ranking
│   ├── ranking-fix-time.sh      # Fix time ranking (REST API)
│   ├── analysis-bottleneck.sh   # PR lifecycle phase analysis
│   ├── analysis-stuck-prs.sh    # Stuck PR detection
│   ├── analysis-reviewer-load.sh # Reviewer workload analysis
│   ├── analysis-review-cycles.sh # Review round analysis
│   ├── analysis-pr-size.sh      # PR size correlation analysis
│   └── lib/                     # Shared library modules
│       ├── common.sh            # Facade (loads all modules)
│       ├── constants.sh         # Thresholds and time values
│       ├── tmpfile.sh           # Temp file management with auto-cleanup
│       ├── args.sh              # Argument parsing and bot exclusion
│       ├── datetime.sh          # Date calculation and timezone handling
│       ├── format.sh            # Output formatting utilities
│       ├── graphql.sh           # GraphQL queries and pagination
│       ├── collect-data.sh      # Basic PR review data collection
│       ├── collect-data-extended.sh # Extended PR lifecycle data
│       ├── ranking-runner.sh    # Shared ranking script boilerplate
│       └── analysis-runner.sh   # Shared analysis script boilerplate
├── skills/review-metrics/
│   └── SKILL.md                 # Skill definition for Claude
├── tests/
│   ├── test-runner.sh           # Test framework
│   ├── test-lib-functions.sh    # Unit tests for library functions
│   ├── test-dispatch.sh         # Dispatch routing tests
│   └── test-tmpfile.sh          # Temp file management tests
├── excluded-accounts.txt        # Bot account exclusions
└── CLAUDE.md                    # Detailed architecture guide
```

### Architecture

The plugin uses a modular architecture with a facade pattern. All scripts source `lib/common.sh`, which loads all sub-modules. Ranking and analysis scripts follow a runner pattern (`ranking-runner.sh` / `analysis-runner.sh`) that handles shared boilerplate (argument parsing, date calculation, data collection), letting each script focus on domain logic only.

### Running Tests

```bash
bash plugin/tests/test-runner.sh
```

Tests cover library functions (`format_duration`, `classify_pr_size`, `percentile`, `is_bot`, constants), dispatch routing for all commands, and temp file lifecycle management.

### Release Process

Releases are managed via GitHub Actions:

1. **Create Release PR** (`create-release-pr.yml`) - Trigger manually with a version bump type (patch/minor/major). Calculates the new version, updates `plugin.json` and `marketplace.json`, generates a changelog, and creates a release PR.
2. **Publish Release** (`publish-release.yml`) - Automatically triggers when a release PR is merged. Creates a git tag and GitHub release with auto-generated notes.

## License

Apache License 2.0
