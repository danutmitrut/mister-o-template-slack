#!/usr/bin/env bash
set -Eeuo pipefail
trap 't_summary; exit 1' ERR
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR}/../scripts/lib/test-helpers.sh"
SH="${DIR}/../scripts/mark-alive.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
ALIVE="${tmp}/alive"

ALIVE_FILE="$ALIVE" NOW_EPOCH=1700000000 bash "$SH"
assert_eq "1700000000" "$(cat "$ALIVE")" "writes given epoch as content"

# No leftover temp files in the alive dir (atomic mv, not partial write).
leftovers="$(find "$tmp" -name 'alive.tmp*' | wc -l | tr -d ' ')"
assert_eq "0" "$leftovers" "no .tmp leftovers (atomic write)"

# Real run (no NOW_EPOCH) writes a plausible recent epoch.
ALIVE_FILE="$ALIVE" bash "$SH"
now="$(date -u +%s)"; got="$(cat "$ALIVE")"
diff=$(( now - got )); [[ $diff -lt 0 ]] && diff=$(( -diff ))
assert_rc 0 "real epoch within 5s of now" test "$diff" -le 5

t_summary
