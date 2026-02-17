#!/usr/bin/env bash
# Named constants for review metrics scripts

# Time constants
SECONDS_PER_MINUTE=60
SECONDS_PER_HOUR=3600
SECONDS_PER_DAY=86400

# Fix time ranking: cap at 2 weeks
FIX_TIME_CAP_HOURS=336

# Sentinel value for epoch comparisons
SENTINEL_EPOCH=99999999999

# Stuck PR thresholds
STUCK_REVIEW_THRESHOLD=$((24 * SECONDS_PER_HOUR))   # 24 hours
STUCK_AGE_THRESHOLD=$((5 * SECONDS_PER_DAY))         # 5 days

# Bottleneck: instant approval threshold (seconds)
INSTANT_APPROVAL_THRESHOLD=300  # 5 minutes
