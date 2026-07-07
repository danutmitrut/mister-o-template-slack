#!/usr/bin/env bash
set -Eeuo pipefail
trap 't_summary; exit 1' ERR
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR}/../scripts/lib/test-helpers.sh"
HB="${DIR}/../HEARTBEAT.md"

assert_file_contains "$HB" "bash scripts/mark-alive.sh" "HEARTBEAT.md references the beacon"
head -12 "$HB" > /tmp/_hb_head.$$ || true
assert_file_contains /tmp/_hb_head.$$ "bash scripts/mark-alive.sh" "beacon is an early/first step"
rm -f /tmp/_hb_head.$$

t_summary
