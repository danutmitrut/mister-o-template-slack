#!/usr/bin/env bash
set -Eeuo pipefail
trap 't_summary; exit 1' ERR
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR}/../scripts/lib/test-helpers.sh"
SH="${DIR}/../scripts/supervisor.sh"

setup() {
  tmp="$(mktemp -d)"
  state="${tmp}/state"; mkdir -p "$state"
  cfg="${tmp}/config.json"
  envf="${tmp}/.env"; printf 'SLACK_BOT_TOKEN="T"\nSLACK_CHANNEL_ID="9"\n' > "$envf"
  log="${state}/supervisor.log"
  tcap="${tmp}/tmux_args"; lcap="${tmp}/lc_args"; ncap="${tmp}/notify_args"
  cat > "${tmp}/tmux" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "${tcap}"
if [[ "\$1" == "display-message" ]]; then
  [[ "\$TMUX_PRESENT" == "1" ]] || exit 1
  echo "\${TMUX_CREATED:-5000}"
  exit 0
fi
[[ "\$TMUX_PRESENT" == "1" ]] && exit 0 || exit 1
EOF
  cat > "${tmp}/launchctl" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "${lcap}"
exit 0
EOF
  cat > "${tmp}/notify" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "${ncap}"
exit 0
EOF
  chmod +x "${tmp}/tmux" "${tmp}/launchctl" "${tmp}/notify"
  cat > "$cfg" <<'EOF'
{"supervisor":{"tick_seconds":240,"liveness_stale_seconds":2700,"flap_count":3,"flap_window_seconds":1800,"backoff_schedule":[600,1200,1800],"pathological_count":6,"pathological_window_seconds":7200,"dry_run":false,"auto_restart":true}}
EOF
}
run() { # NOW TMUX_PRESENT [TMUX_CREATED]
  TMUX_CREATED="${3:-5000}"
  CONFIG_FILE="$cfg" ENV_FILE="$envf" STATE_DIR="$state" LOG_FILE="$log" \
  TMUX_BIN="${tmp}/tmux" LAUNCHCTL_BIN="${tmp}/launchctl" NOTIFY_BIN="${tmp}/notify" \
  NOW_EPOCH="$1" TMUX_PRESENT="$2" TMUX_CREATED="$TMUX_CREATED" UID_VAL="501" bash "$SH"
}

# Scenario healthy: tmux up, alive fresh -> no restart, no notify.
setup
echo "10000" > "${state}/alive"
echo "5000" > "${state}/.supervisor_sess_created"
run 10100 1
assert_rc 1 "healthy: no restart" test -f "$lcap"
assert_rc 1 "healthy: no notify"  test -f "$ncap"
assert_file_contains "$log" "HEALTHY" "healthy logged"
rm -rf "$tmp"

# Scenario cold-start: tmux up, beacon stale, NEW agent session -> GRACE, no restart, no notify.
setup
echo "1000" > "${state}/alive"
echo "59900" > "${state}/.supervisor_last_tick"   # recent tick, not slept
# no .supervisor_sess_created seeded => fake session 5000 is "new" => startup grace
run 60000 1
assert_rc 1 "cold-start: no restart" test -f "$lcap"
assert_rc 1 "cold-start: no notify"  test -f "$ncap"
assert_file_contains "$log" "STARTUP detected" "cold-start STARTUP logged"
assert_file_contains "$log" "GRACE" "cold-start classified GRACE"
rm -rf "$tmp"

# Scenario born-wedge after grace expiry: same session, grace window expired, beacon still stale -> DOWN -> restart.
setup
echo "5000" > "${state}/.supervisor_sess_created"     # same session as fake TMUX_CREATED -> no NEW startup grace
echo "1000" > "${state}/.supervisor_grace_until"      # a startup grace that has already expired (now >> 1000)
echo "1000" > "${state}/alive"                        # beacon never refreshed (born wedged)
echo "59900" > "${state}/.supervisor_last_tick"       # recent tick (supervisor kept ticking) -> not slept
run 60000 1
assert_file_contains "$lcap" "kickstart" "born-wedge after grace: kickstart called"
assert_file_contains "$log" "DOWN -> RESTART" "born-wedge after grace: DOWN RESTART logged"
rm -rf "$tmp"

# Scenario down (stale) -> restart + info notify.
setup
echo "5000" > "${state}/.supervisor_sess_created"
echo "1000" > "${state}/alive"
echo "59900" > "${state}/.supervisor_last_tick"   # recent tick, not slept
run 60000 1
assert_file_contains "$lcap" "kickstart" "down: kickstart called"
assert_file_contains "$ncap" "info" "down: info notify"
rm -rf "$tmp"

# Scenario no tmux -> restart even if alive fresh.
setup
echo "59990" > "${state}/alive"
echo "59900" > "${state}/.supervisor_last_tick"
run 60000 0
assert_file_contains "$lcap" "kickstart" "no-tmux: kickstart called"
rm -rf "$tmp"

# Scenario slept -> GRACE, no restart even though alive very stale.
setup
echo "5000" > "${state}/.supervisor_sess_created"
echo "1000" > "${state}/alive"
echo "1000" > "${state}/.supervisor_last_tick"     # huge gap => slept
run 60000 1
assert_rc 1 "slept: no restart" test -f "$lcap"
assert_file_contains "$log" "GRACE" "slept -> GRACE logged"
rm -rf "$tmp"

# Scenario dry_run -> down but NO restart, NO notify, logged as DRY.
setup
sed -i.bak 's/"dry_run":false/"dry_run":true/' "$cfg"
echo "5000" > "${state}/.supervisor_sess_created"
echo "1000" > "${state}/alive"
echo "59900" > "${state}/.supervisor_last_tick"
run 60000 1
assert_rc 1 "dry_run: no restart" test -f "$lcap"
assert_rc 1 "dry_run: no notify"  test -f "$ncap"
assert_file_contains "$log" "DRY" "dry_run logged"
rm -rf "$tmp"

# Scenario pathological -> no restart, red notify.
setup
echo "5000" > "${state}/.supervisor_sess_created"
echo "1000" > "${state}/alive"
echo "59900" > "${state}/.supervisor_last_tick"
echo "59000,59100,59200,59300,59400,59500" > "${state}/.supervisor_restarts"
run 60000 1
assert_rc 1 "pathological: no restart" test -f "$lcap"
assert_file_contains "$ncap" "red" "pathological: red notify"
rm -rf "$tmp"

# Scenario alert-only (auto_restart=false): DOWN -> notify warning, NO restart.
setup
sed -i.bak 's/"auto_restart":true/"auto_restart":false/' "$cfg"
echo "5000" > "${state}/.supervisor_sess_created"   # established session, not cold-start
echo "1000" > "${state}/alive"
echo "59900" > "${state}/.supervisor_last_tick"
run 60000 1
assert_rc 1 "alert-only: no restart" test -f "$lcap"
assert_file_contains "$ncap" "warning" "alert-only: warning notify"
assert_file_contains "$log" "ALERT-ONLY" "alert-only logged"
# second DOWN tick within STALE -> rate-limited: no new notify line, still no restart
prev_n="$(wc -l < "$ncap" | tr -d ' ')"
run 60050 1
assert_eq "$prev_n" "$(wc -l < "$ncap" | tr -d ' ')" "alert-only: 2nd tick within STALE is rate-limited (no extra notify)"
assert_rc 1 "alert-only: 2nd tick still no restart" test -f "$lcap"
rm -rf "$tmp"

t_summary
