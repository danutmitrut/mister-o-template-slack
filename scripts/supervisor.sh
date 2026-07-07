#!/usr/bin/env bash
# Independent watchdog. Runs once per tick (launchd StartInterval), then exits.
# Deliberately does NOT 'set -e': an internal error must never propagate in a
# way that could harm the agent. We log and exit 0.
set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "${LIB_DIR}/.." && pwd)}"
# shellcheck disable=SC1091
source "${LIB_DIR}/lib/supervisor-lib.sh"

CONFIG_FILE="${CONFIG_FILE:-${PROJECT_DIR}/config.json}"
ENV_FILE="${ENV_FILE:-${PROJECT_DIR}/.env}"
STATE_DIR="${STATE_DIR:-${HOME}/.agent-logs}"
LOG_FILE="${LOG_FILE:-${STATE_DIR}/supervisor.log}"
ALIVE_FILE="${ALIVE_FILE:-${STATE_DIR}/alive}"
TMUX_BIN="${TMUX_BIN:-tmux}"
LAUNCHCTL_BIN="${LAUNCHCTL_BIN:-launchctl}"
NOTIFY_BIN="${NOTIFY_BIN:-${LIB_DIR}/notify.sh}"
UID_VAL="${UID_VAL:-$(id -u)}"
AGENT_LABEL="com.my-agent"
TMUX_SESSION="my-agent"
LOG_MAX_BYTES=1048576

mkdir -p "$STATE_DIR"
LAST_TICK_F="${STATE_DIR}/.supervisor_last_tick"
RESTARTS_F="${STATE_DIR}/.supervisor_restarts"
GRACE_F="${STATE_DIR}/.supervisor_grace_until"
LAST_ALERT_F="${STATE_DIR}/.supervisor_last_alert"
SESS_F="${STATE_DIR}/.supervisor_sess_created"

now="${NOW_EPOCH:-$(date -u +%s)}"

cfg() { jq -r ".supervisor.$1 // empty" "$CONFIG_FILE" 2>/dev/null || true; }
TICK="$(cfg tick_seconds)";            TICK="${TICK:-240}"
STALE="$(cfg liveness_stale_seconds)"; STALE="${STALE:-2700}"
FC="$(cfg flap_count)";                FC="${FC:-3}"
FW="$(cfg flap_window_seconds)";       FW="${FW:-1800}"
PC="$(cfg pathological_count)";        PC="${PC:-6}"
PW="$(cfg pathological_window_seconds)"; PW="${PW:-7200}"
DRY="$(cfg dry_run)";                  DRY="${DRY:-false}"
AR="$(cfg auto_restart)";             AR="${AR:-false}"
BACKOFF_CSV="$(jq -r '(.supervisor.backoff_schedule // [600,1200,1800]) | map(tostring) | join(",")' "$CONFIG_FILE" 2>/dev/null || echo "600,1200,1800")"

rotate_if_needed() {
  [[ -f "$LOG_FILE" ]] || return 0
  local size; size="$(stat -f %z "$LOG_FILE" 2>/dev/null || echo 0)"
  if [[ "$(should_rotate "$size" "$LOG_MAX_BYTES")" == "1" ]]; then
    mv -f "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null || true
  fi
}
log() { rotate_if_needed; printf '%s %s\n' "$(date -u -r "$now" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "$now")" "$*" >> "$LOG_FILE"; }

read_int() { local f="$1" d="$2"; if [[ -f "$f" ]]; then cat "$f"; else echo "$d"; fi; }

main() {
  local last_tick alive grace_until tmux_present slept state sess_created prev_sess
  last_tick="$(read_int "$LAST_TICK_F" 0)"
  alive="$(read_int "$ALIVE_FILE" 0)"
  grace_until="$(read_int "$GRACE_F" 0)"

  if "$TMUX_BIN" has-session -t "$TMUX_SESSION" 2>/dev/null; then tmux_present=1; else tmux_present=0; fi

  # Cold-start grace: a NEW agent tmux session means the agent just (re)started
  # and has not written its first heartbeat beacon yet. Grant a grace window so a
  # healthy, freshly started agent is not classified DOWN by a stale beacon. A
  # genuine wedge keeps the same session and is still caught; tmux absent is still DOWN.
  sess_created=""
  if [[ "$tmux_present" -eq 1 ]]; then
    # (test harnesses inject the fake tmux which honors a TMUX_CREATED env override)
    sess_created="$("$TMUX_BIN" display-message -p -t "$TMUX_SESSION" '#{session_created}' 2>/dev/null || true)"
  fi
  prev_sess="$(read_int "$SESS_F" "")"
  if [[ "$tmux_present" -eq 1 && -n "$sess_created" && "$sess_created" =~ ^[0-9]+$ && "$sess_created" != "$prev_sess" ]]; then
    grace_until=$(( now + STALE ))
    echo "$grace_until" > "$GRACE_F"
    echo "$sess_created" > "$SESS_F"
    log "STARTUP detected (agent session ${sess_created}) grace_until=${grace_until}"
  fi

  slept="$(compute_slept "$now" "$last_tick" "$TICK")"
  if [[ "$slept" == "1" ]]; then
    grace_until=$(( now + STALE ))
    echo "$grace_until" > "$GRACE_F"
    log "SLEEP detected (gap $(( now - last_tick ))s) grace_until=${grace_until}"
  fi

  state="$(classify_state "$tmux_present" "$alive" "$now" "$STALE" "$grace_until")"

  case "$state" in
    HEALTHY|GRACE)
      log "${state} tmux=${tmux_present} alive_age=$(( now - alive ))s"
      ;;
    DOWN)
      local restarts decision
      restarts="$(read_int "$RESTARTS_F" "")"
      decision="$(flap_decision "$restarts" "$now" "$FC" "$FW" "$PC" "$PW" "$BACKOFF_CSV")"
      if [[ "$DRY" == "true" ]]; then
        log "DRY DOWN -> would act decision=${decision} tmux=${tmux_present} alive_age=$(( now - alive ))s"
      else
        case "$decision" in
          OK)
            if [[ "$AR" == "true" ]]; then
              "$LAUNCHCTL_BIN" kickstart -k "gui/${UID_VAL}/${AGENT_LABEL}" >/dev/null 2>&1 || true
              restarts="${restarts:+${restarts},}${now}"
              echo "$restarts" > "$RESTARTS_F"
              log "DOWN -> RESTART (kickstart) restarts=[${restarts}]"
              "$NOTIFY_BIN" info "Mister O. era jos, l-am repornit la $(date -u -r "$now" +%H:%MZ 2>/dev/null || echo "$now"). Sunt iar online." || true
            else
              local last_alert; last_alert="$(read_int "$LAST_ALERT_F" 0)"
              log "DOWN -> ALERT-ONLY (auto_restart off) no restart"
              if [[ $(( now - last_alert )) -ge "$STALE" ]]; then
                echo "$now" > "$LAST_ALERT_F"
                "$NOTIFY_BIN" warning "Mister O. e jos. auto_restart e oprit, nu repornesc automat. Reporneste manual: launchctl kickstart -k gui/${UID_VAL}/${AGENT_LABEL}" || true
              fi
            fi
            ;;
          BACKOFF:*)
            local secs="${decision#BACKOFF:}" last_alert
            last_alert="$(read_int "$LAST_ALERT_F" 0)"
            log "DOWN -> BACKOFF ${secs}s (flapping) no restart"
            if [[ $(( now - last_alert )) -ge "$secs" ]]; then
              echo "$now" > "$LAST_ALERT_F"
              "$NOTIFY_BIN" warning "Mister O. se tot reporneste, intru in backoff ${secs}s." || true
            fi
            ;;
          PATHOLOGICAL)
            local last_alert; last_alert="$(read_int "$LAST_ALERT_F" 0)"
            log "DOWN -> PATHOLOGICAL auto-restart oprit"
            if [[ $(( now - last_alert )) -ge "$PW" ]]; then
              echo "$now" > "$LAST_ALERT_F"
              local tail_err; tail_err="$(tail -3 "${STATE_DIR}/stderr.log" 2>/dev/null | tr '\n' ' ' | cut -c1-300)"
              "$NOTIFY_BIN" red "Mister O. e jos si nu se stabilizeaza singur. Ai nevoie sa intervii. Ultima eroare: ${tail_err}" || true
            fi
            ;;
        esac
      fi
      ;;
  esac

  echo "$now" > "$LAST_TICK_F"
}

# Defensive wrapper: any failure is logged, never propagated.
if ! main 2>>"${LOG_FILE}"; then
  log "ERROR supervisor main failed (handled, exiting 0)"
fi
exit 0
