# Review Metrics

A Claude Code plugin that analyzes GitHub PR review activity, team performance rankings, and review bottlenecks.

## Project Structure

```
claude-review-metrics/
├── .claude-plugin/
│   ├── plugin.json              # Root plugin manifest
│   └── marketplace.json         # Marketplace metadata
├── plugin/                      # Plugin source
│   ├── .claude-plugin/
│   │   └── plugin.json          # Plugin manifest
│   ├── scripts/                 # Shell scripts
│   ├── skills/                  # Skill definitions
│   ├── tests/                   # Test suite
│   ├── excluded-accounts.txt    # Bot account exclusions
│   └── CLAUDE.md                # Full architecture guide
├── README.md
└── LICENSE
```

See [plugin/CLAUDE.md](plugin/CLAUDE.md) for the full architecture guide, module system, metric definitions, and development instructions.

## Quick Reference

- Run tests: `bash plugin/tests/test-runner.sh`
- Plugin entry point: `plugin/scripts/dispatch.sh`
- Bot exclusions: `plugin/excluded-accounts.txt`
