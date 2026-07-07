#!/usr/bin/env bash
set -Eeuo pipefail
trap 't_summary; exit 1' ERR
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR}/../scripts/lib/test-helpers.sh"
W="${DIR}/../scripts/agent-wrapper.sh"

assert_not_contains "$(cat "$W")" "sleep 86400" "no 24h silent halt remains"
assert_contains "$(cat "$W")" "MAX_CRASHES_PER_DAY" "crash cap logic retained"
assert_contains "$(cat "$W")" "HALTED" "HALTED telemetry log retained"

t_summary
