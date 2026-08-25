#!/usr/bin/env bash
set -Eeuo pipefail
trap 't_summary; exit 1' ERR

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR}/../scripts/lib/test-helpers.sh"
CFG="${DIR}/../config.json"

assert_rc 0 "config.json is valid json" jq -e . "$CFG"
assert_eq "240"  "$(jq -r '.supervisor.tick_seconds // empty' "$CFG")"            "tick_seconds default"
assert_eq "2700" "$(jq -r '.supervisor.liveness_stale_seconds // empty' "$CFG")"  "liveness_stale default"
assert_eq "3"    "$(jq -r '.supervisor.flap_count // empty' "$CFG")"              "flap_count default"
assert_eq "1800" "$(jq -r '.supervisor.flap_window_seconds // empty' "$CFG")"     "flap_window default"
assert_eq "6"    "$(jq -r '.supervisor.pathological_count // empty' "$CFG")"      "pathological_count default"
assert_eq "7200" "$(jq -r '.supervisor.pathological_window_seconds // empty' "$CFG")" "pathological_window default"
assert_eq "false" "$(jq -r '.supervisor.dry_run' "$CFG")"                          "dry_run default false"
assert_eq "boolean" "$(jq -r '.supervisor.dry_run | type' "$CFG")" "dry_run is boolean not string"
assert_eq "false" "$(jq -r '.supervisor.auto_restart' "$CFG")" "auto_restart default false"
assert_eq "boolean" "$(jq -r '.supervisor.auto_restart | type' "$CFG")" "auto_restart is boolean not string"
assert_eq "600,1200,1800" "$(jq -r '.supervisor.backoff_schedule | map(tostring) | join(",")' "$CFG")" "backoff schedule"
hb="$(jq -r '.crons[] | select(.interval=="30m") | .prompt' "$CFG")"
assert_contains "$hb" "bash scripts/mark-alive.sh" "heartbeat cron runs mark-alive first"

# The comms cron is a safety net, not the delivery path: the listener wakes the agent.
# A 1m interval here would put the per-minute context reload back and undo the savings.
comms="$(jq -r '.crons[] | select(.prompt | contains("check-slack.sh")) | .interval' "$CFG")"
assert_eq "1h" "$comms" "comms cron is the hourly safety net, not a 1m poll"
comms_prompt="$(jq -r '.crons[] | select(.prompt | contains("check-slack.sh")) | .prompt' "$CFG")"
assert_contains "$comms_prompt" "slack-listener-status.sh" "comms cron checks whether the listener is alive"
assert_contains "$comms_prompt" "bash scripts/mark-alive.sh" "comms cron runs mark-alive first"

t_summary
