#!/usr/bin/env bash
# End-to-end supervisor simulation with shortened timings and fake binaries.
# Proves the mechanism without waiting for real wedges.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUP="${ROOT}/scripts/supervisor.sh"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
state="${work}/state"; mkdir -p "$state"
log="${state}/supervisor.log"
envf="${work}/.env"; printf 'SLACK_BOT_TOKEN="T"\nSLACK_CHANNEL_ID="9"\n' > "$envf"
cfg="${work}/config.json"
cat > "$cfg" <<'EOF'
{"supervisor":{"tick_seconds":10,"liveness_stale_seconds":60,"flap_count":3,"flap_window_seconds":120,"backoff_schedule":[5,10,15],"pathological_count":6,"pathological_window_seconds":600,"dry_run":false,"auto_restart":true}}
EOF
lc="${work}/lc"; nf="${work}/nf"
cat > "${work}/tmux" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "display-message" ]]; then
  [[ "\$TMUX_PRESENT" == "1" ]] || exit 1
  echo "\${TMUX_CREATED:-7000}"
  exit 0
fi
[[ "\$TMUX_PRESENT" == "1" ]] && exit 0 || exit 1
EOF
cat > "${work}/launchctl" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "${lc}"
EOF
cat > "${work}/notify" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "${nf}"
EOF
chmod +x "${work}/tmux" "${work}/launchctl" "${work}/notify"

run() { # now tmux_present [tmux_created]
  TMUX_CREATED="${3:-7000}"
  CONFIG_FILE="$cfg" ENV_FILE="$envf" STATE_DIR="$state" LOG_FILE="$log" \
  TMUX_BIN="${work}/tmux" LAUNCHCTL_BIN="${work}/launchctl" NOTIFY_BIN="${work}/notify" \
  NOW_EPOCH="$1" TMUX_PRESENT="$2" TMUX_CREATED="$TMUX_CREATED" UID_VAL="501" bash "$SUP"
}
fail() { echo "SELFTEST RED: $1"; exit 1; }

# 1. Healthy: fresh beacon, tmux up -> no restart.
echo "7000" > "${state}/.supervisor_sess_created"
echo "1000" > "${state}/alive"; echo "995" > "${state}/.supervisor_last_tick"
run 1005 1
[[ -f "$lc" ]] && fail "healthy caused a restart"

# 2. Wedge: beacon frozen, tmux up, awake -> restart + info.
echo "7000" > "${state}/.supervisor_sess_created"
echo "1000" > "${state}/alive"; echo "1100" > "${state}/.supervisor_last_tick"
run 1105 1
grep -q kickstart "$lc" || fail "wedge did not restart"
grep -q info "$nf" || fail "wedge did not notify info"

# 3. Crash: tmux gone -> restart.
echo "7000" > "${state}/.supervisor_sess_created"
: > "$lc"
echo "2000" > "${state}/alive"; echo "1995" > "${state}/.supervisor_last_tick"
run 2005 0
grep -q kickstart "$lc" || fail "crash did not restart"

# 4. Sleep tolerance: huge tick gap -> GRACE, no restart even though beacon stale.
echo "7000" > "${state}/.supervisor_sess_created"
: > "$lc"
echo "1000" > "${state}/alive"; echo "1000" > "${state}/.supervisor_last_tick"
run 9000 1
[[ -f "$lc" && -s "$lc" ]] && fail "slept tick caused a restart"
grep -q GRACE "$log" || fail "sleep not classified as GRACE"

# 5. Flapping: many recent restarts -> BACKOFF, no restart, warning.
echo "7000" > "${state}/.supervisor_sess_created"
: > "$lc"; : > "$nf"
rm -f "${state}/.supervisor_grace_until"
echo "1000" > "${state}/alive"; echo "9995" > "${state}/.supervisor_last_tick"
echo "9960,9970,9980" > "${state}/.supervisor_restarts"
run 10000 1
[[ -s "$lc" ]] && fail "flapping caused a restart"
grep -q warning "$nf" || fail "flapping did not warn"

# 6. Cold start: NEW agent session, beacon stale, tmux up -> GRACE, no restart.
: > "$lc"; : > "$nf"
rm -f "${state}/.supervisor_sess_created" "${state}/.supervisor_grace_until" "${state}/.supervisor_restarts"
echo "1000" > "${state}/alive"; echo "12995" > "${state}/.supervisor_last_tick"
run 13000 1
[[ -s "$lc" ]] && fail "cold-start caused a restart"
grep -q "STARTUP detected" "$log" || fail "cold-start not detected"

# 7. Alert-only (auto_restart=false): wedge -> notify, NO restart.
sed 's/"auto_restart":true/"auto_restart":false/' "$cfg" > "${cfg}.ar0"; cfg="${cfg}.ar0"
: > "$lc"; : > "$nf"; rm -f "${state}/.supervisor_restarts" "${state}/.supervisor_grace_until"
echo "7000" > "${state}/.supervisor_sess_created"
echo "1000" > "${state}/alive"; echo "13995" > "${state}/.supervisor_last_tick"
run 14000 1
[[ -s "$lc" ]] && fail "alert-only caused a restart"
grep -q warning "$nf" || fail "alert-only did not warn"
grep -q "ALERT-ONLY" "$log" || fail "alert-only not logged"

# 8. dry_run: wedge but no action.
# reset cfg to base (auto_restart:true) so dry_run test does not inherit the prior scenario's ar0 cfg
cfg="${work}/config.json"
sed 's/"dry_run":false/"dry_run":true/' "$cfg" > "${cfg}.dry"; cfg="${cfg}.dry"
: > "$lc"; : > "$nf"; rm -f "${state}/.supervisor_restarts" "${state}/.supervisor_grace_until"
echo "1000" > "${state}/alive"; echo "11995" > "${state}/.supervisor_last_tick"
run 12000 1
[[ -s "$lc" ]] && fail "dry_run caused a restart"
[[ -s "$nf" ]] && fail "dry_run caused a notify"
grep -q DRY "$log" || fail "dry_run not logged"

echo "SELFTEST GREEN"
