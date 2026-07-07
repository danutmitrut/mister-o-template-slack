#!/usr/bin/env bash
set -Eeuo pipefail
trap 't_summary; exit 1' ERR
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR}/../scripts/lib/test-helpers.sh"
SH="${DIR}/../scripts/notify.sh"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
envf="${tmp}/.env"; printf 'SLACK_BOT_TOKEN="TOK123"\nSLACK_CHANNEL_ID="555"\n' > "$envf"
cfg="${tmp}/config.json"

# Fake curl records its args.
fakecurl="${tmp}/curl"; cap="${tmp}/curl_args"
cat > "$fakecurl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "${cap}"
EOF
chmod +x "$fakecurl"

# Case A: no test channel id -> uses SLACK_CHANNEL_ID 555, info prefix.
printf '{}' > "$cfg"
CURL_BIN="$fakecurl" ENV_FILE="$envf" CONFIG_FILE="$cfg" bash "$SH" info "hello"
args="$(cat "$cap")"
assert_contains "$args" "https://slack.com/api/chat.postMessage" "posts to slack chat.postMessage"
assert_contains "$args" "Authorization: Bearer TOK123" "auth header carries token"
assert_contains "$args" '"channel":"555"' "uses channel from env when no test channel"
assert_contains "$args" "ℹ️ hello" "info prefix applied"

# Case B: test channel id set -> overrides recipient, red prefix.
printf '{"supervisor":{"test_slack_channel_id":"999"}}' > "$cfg"
CURL_BIN="$fakecurl" ENV_FILE="$envf" CONFIG_FILE="$cfg" bash "$SH" red "down"
args="$(cat "$cap")"
assert_contains "$args" '"channel":"999"' "test channel id overrides recipient"
assert_contains "$args" "🔴 down" "red prefix applied"

# Case D: warning prefix.
CURL_BIN="$fakecurl" ENV_FILE="$envf" CONFIG_FILE="$cfg" bash "$SH" warning "degraded"
args="$(cat "$cap")"
assert_contains "$args" "⚠️ degraded" "warning prefix applied"

# Case C: missing token -> exits 0, does not call curl (no crash on the agent).
: > "$cap"
printf 'SLACK_CHANNEL_ID="555"\n' > "${tmp}/.env2"
assert_rc 0 "missing token is non-fatal" env CURL_BIN="$fakecurl" ENV_FILE="${tmp}/.env2" CONFIG_FILE="$cfg" bash "$SH" info "x"
assert_eq "" "$(cat "$cap")" "curl not called when token missing"

t_summary
