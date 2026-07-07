#!/usr/bin/env bash
set -Eeuo pipefail
trap 't_summary; exit 1' ERR
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR}/../scripts/lib/test-helpers.sh"
GEN="${DIR}/../scripts/generate-supervisor-launchd.sh"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cfg="${tmp}/config.json"; printf '{"supervisor":{"tick_seconds":240}}' > "$cfg"
out="${tmp}/com.my-agent-supervisor.plist"

CONFIG_FILE="$cfg" PROJECT_DIR="/proj/path" OUT_FILE="$out" bash "$GEN"

p="$(cat "$out")"
assert_contains "$p" "<string>com.my-agent-supervisor</string>" "label set"
assert_contains "$p" "<string>/proj/path/scripts/supervisor.sh</string>" "program arg = supervisor.sh"
assert_contains "$p" "<string>/proj/path</string>" "project dir passed"
assert_contains "$p" "<key>StartInterval</key>" "StartInterval present"
assert_contains "$p" "<integer>240</integer>" "StartInterval value from config"
assert_contains "$p" "<key>RunAtLoad</key>" "RunAtLoad present"
assert_not_contains "$p" "<key>KeepAlive</key>" "NO KeepAlive (would tight-loop)"
assert_not_contains "$p" "<key>ThrottleInterval</key>" "NO ThrottleInterval (periodic one-shot, not throttled long-runner)"
assert_rc 0 "plist is well-formed xml" plutil -lint "$out"

t_summary
