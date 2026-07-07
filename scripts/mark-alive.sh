#!/usr/bin/env bash
# Deterministic liveness beacon. Run as the FIRST action of the 30m heartbeat
# cron. If claude is healthy the loop executes this and the beacon stays fresh;
# if claude is wedged this never runs and the beacon goes stale (detected).
set -euo pipefail

ALIVE_FILE="${ALIVE_FILE:-${HOME}/.agent-logs/alive}"
now="${NOW_EPOCH:-$(date -u +%s)}"

mkdir -p "$(dirname "$ALIVE_FILE")"
tmp="$(mktemp "${ALIVE_FILE}.tmp.XXXXXX")"
printf '%s' "$now" > "$tmp"
mv -f "$tmp" "$ALIVE_FILE"
