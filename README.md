# Review Metrics

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
/review-metrics stuck                        # Currently stuck PRs
```

## Features

### Rankings (Top 3)

| Command | Description |
|---------|-------------|
| `comments` | Review comment count |
| `reviewed` | Reviewed PR count |
| `approved` | Approval count |
| `response-time` | Avg time from review request to first review |
| `fix-time` | Avg time from review comment to next commit |

### Analysis (Team-wide)

| Command | Description |
|---------|-------------|
| `bottleneck` | PR lifecycle phase breakdown (wait/review/merge) with p50/p90 |
| `stuck` | Open PRs needing immediate attention |
| `reviewer-load` | Team review workload distribution |
| `cycles` | Review round counts and change-request patterns |
| `pr-size` | PR size vs review speed correlation |

### Period Options

| Period | Description |
|--------|-------------|
| `week` | Current week (Mon-Fri) - default |
| `last-week` | Previous week (Mon-Fri) |
| `month` | Last 30 days |

## Requirements

- GitHub CLI (`gh`) installed and authenticated
- `jq` for JSON processing

## Development

### Running Tests

```bash
bash plugin/tests/test-runner.sh
```

### Project Structure

Plugin source lives under `plugin/`. Scripts are organized into modular libraries under `plugin/scripts/lib/`. See [plugin/CLAUDE.md](plugin/CLAUDE.md) for the full architecture guide.

## License

Apache License 2.0
