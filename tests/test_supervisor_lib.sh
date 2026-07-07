#!/usr/bin/env bash
set -Eeuo pipefail
trap 't_summary; exit 1' ERR
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR}/../scripts/lib/test-helpers.sh"
source "${DIR}/../scripts/lib/supervisor-lib.sh"

# compute_slept
assert_eq "0" "$(compute_slept 1000 0 240)"     "no last_tick -> not slept"
assert_eq "0" "$(compute_slept 1000 900 240)"   "gap 100 <= 480 -> not slept"
assert_eq "1" "$(compute_slept 1000 400 240)"   "gap 600 > 480 -> slept"
assert_eq "0" "$(compute_slept 1000 520 240)"   "gap == tick*2 exactly -> not slept (strict boundary)"

# classify_state: args = tmux_present alive_epoch now liveness_stale grace_until
assert_eq "DOWN"    "$(classify_state 0 1000 1000 2700 0)"     "no tmux -> DOWN"
assert_eq "GRACE"   "$(classify_state 1 0    5000 2700 6000)"  "within grace window -> GRACE"
assert_eq "DOWN"    "$(classify_state 1 1000 4000 2700 0)"     "stale 3000>2700 -> DOWN"
assert_eq "HEALTHY" "$(classify_state 1 1000 2000 2700 0)"     "fresh 1000<2700 -> HEALTHY"
assert_eq "DOWN"    "$(classify_state 0 9999 9999 2700 999999)" "no tmux beats grace -> DOWN"
assert_eq "DOWN"    "$(classify_state 1 0 6000 2700 6000)"     "now == grace_until -> not GRACE (strict boundary)"
assert_eq "HEALTHY" "$(classify_state 1 1000 3700 2700 0)"     "now-alive == stale exactly -> HEALTHY (strict boundary)"

# flap_decision: restarts now flap_count flap_window path_count path_window backoff_csv
assert_eq "OK"           "$(flap_decision "" 1000 3 1800 6 7200 600,1200,1800)" "no restarts -> OK"
assert_eq "OK"           "$(flap_decision "100,200" 5000 3 1800 6 7200 600,1200,1800)" "old restarts out of window -> OK"
assert_eq "BACKOFF:600"  "$(flap_decision "1000,1100,1200" 1300 3 1800 6 7200 600,1200,1800)" "3 in window -> first backoff"
assert_eq "BACKOFF:1200" "$(flap_decision "1000,1100,1200,1250" 1300 3 1800 6 7200 600,1200,1800)" "4 in window -> second backoff"
assert_eq "BACKOFF:1800" "$(flap_decision "1000,1100,1200,1250,1280" 1300 3 1800 6 7200 600,1200,1800)" "5 -> capped backoff"
assert_eq "PATHOLOGICAL" "$(flap_decision "1,2,3,4,5,6" 100 3 1800 6 7200 600,1200,1800)" "6 in path window -> PATHOLOGICAL"

# should_rotate
assert_eq "0" "$(should_rotate 100 1048576)"  "small -> no rotate"
assert_eq "1" "$(should_rotate 2000000 1048576)" "big -> rotate"
assert_eq "0" "$(should_rotate 1048576 1048576)"  "size == max_bytes exactly -> no rotate (strict boundary)"

t_summary
