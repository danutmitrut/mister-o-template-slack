#!/usr/bin/env bash
set -Eeuo pipefail
trap 't_summary; exit 1' ERR
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR}/../scripts/lib/test-helpers.sh"

assert_eq "abc" "abc" "equal strings pass"
assert_contains "hello world" "lo wo" "substring found"
assert_rc 0 "true returns 0" true
assert_rc 1 "false returns 1" false

# Negative control: prove a failing assertion is detected by running it in a subshell.
if ( assert_eq "x" "y" "should fail" ) 2>/dev/null; then
  echo "META FAIL: assert_eq did not detect inequality"; exit 1
fi

t_summary
