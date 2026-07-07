#!/usr/bin/env bash
set -Eeuo pipefail
trap 't_summary; exit 1' ERR
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR}/../scripts/lib/test-helpers.sh"
SS="${DIR}/../scripts/supervisor-selftest.sh"
out="$(bash "$SS" 2>&1)" || { echo "$out"; t_fail "selftest exited non-zero"; t_summary; exit 1; }
assert_contains "$out" "SELFTEST GREEN" "selftest reports green"
t_summary
