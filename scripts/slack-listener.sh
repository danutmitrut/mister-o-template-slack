#!/bin/bash
# Slack listener. Runs as a launchd daemon and costs zero model tokens.
#
# Why this exists: the agent used to check Slack itself, on a 1-minute cron.
# Every one of those wake-ups reloaded the agent's whole context just to find an
# empty inbox. The check itself is free; the language model started to run it is
# not. On the Telegram side of this template family the same pattern was measured
# at 528 wake-ups a day.
#
# This listener does the checking in shell and only wakes the agent when a real
# message arrives. It owns the Slack connection and the timestamp file;
# check-slack.sh reads what this writes into the inbox instead of polling.
#
# Ordering guarantee: the inbox is written and flushed BEFORE the timestamp
# advances. A crash in between re-delivers a message (duplicate) rather than
# dropping it.
#
# Rate limits: conversations.history is 1 request/minute for apps distributed
# commercially outside the Slack Marketplace. An app you create in your own
# workspace from the bundled manifest is an internal app and keeps the old
# 50+/minute allowance, which is what POLL_INTERVAL assumes. If Slack does answer
# with 429 anyway, the listener backs off and widens its own interval instead of
# hammering a closed door. See docs/SLACK-LISTENER.md.

set -uo pipefail

AGENT_DIR="${AGENT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TMUX_SESSION="${TMUX_SESSION:-my-agent}"
TMUX_BIN="${TMUX_BIN:-tmux}"

TS_FILE="${TS_FILE:-$HOME/.claude-slack-ts}"
INBOX_FILE="${INBOX_FILE:-$HOME/.claude-slack-inbox.jsonl}"
ALIVE_FILE="${LISTENER_ALIVE_FILE:-$HOME/.agent-logs/slack-listener-alive}"
LOG_FILE="${LISTENER_LOG_FILE:-$HOME/.agent-logs/slack-listener.log}"

POLL_INTERVAL="${POLL_INTERVAL:-10}"      # seconds between checks when all is well
CURL_MAX_TIME="${CURL_MAX_TIME:-15}"      # client cap, so a stalled TCP call cannot hang the loop
ERROR_SLEEP="${ERROR_SLEEP:-15}"          # backoff after an API or network error
MAX_INTERVAL="${MAX_INTERVAL:-60}"        # ceiling the rate-limit backoff may widen to
ONE_SHOT="${ONE_SHOT:-0}"                 # 1 = single check then exit (for tests)

mkdir -p "$(dirname "$ALIVE_FILE")" "$(dirname "$LOG_FILE")"

log() { printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >> "$LOG_FILE"; }

# Credentials live in .env next to the agent, not in launchd's environment.
if [ -z "${SLACK_BOT_TOKEN:-}" ] || [ -z "${SLACK_CHANNEL_ID:-}" ] || [ -z "${SLACK_ALLOWED_USER:-}" ]; then
  # shellcheck disable=SC1090
  [ -f "$AGENT_DIR/.env" ] && set -a && source "$AGENT_DIR/.env" && set +a
fi

BOT_TOKEN="${SLACK_BOT_TOKEN:-}"
CHANNEL_ID="${SLACK_CHANNEL_ID:-}"
ALLOWED_USER="${SLACK_ALLOWED_USER:-}"

# The interval actually in use. Rate-limit backoff widens it; a clean poll resets it.
CURRENT_INTERVAL="$POLL_INTERVAL"

# The prompt injected into the agent's session. Deliberately short: the agent
# already knows how to handle Slack from its cron prompt, and every extra word
# here is paid on a real wake-up.
WAKE_PROMPT="${WAKE_PROMPT:-Ai mesaj nou pe Slack. Ruleaza bash .claude/skills/slack-bot/check-slack.sh si raspunde in caracter, dupa protocolul din cronul de comunicare.}"

wake_agent() {
  if ! "$TMUX_BIN" has-session -t "$TMUX_SESSION" 2>/dev/null; then
    log "WAKE skipped: tmux session '$TMUX_SESSION' not present (supervisor will restart it)"
    return 1
  fi
  # -l sends the text literally, so shell metacharacters in the prompt are safe.
  # Enter goes as a separate call: Claude Code's input needs the newline as its
  # own key event, not appended to the pasted string.
  "$TMUX_BIN" send-keys -t "$TMUX_SESSION" -l "$WAKE_PROMPT" 2>/dev/null || return 1
  sleep 0.3
  "$TMUX_BIN" send-keys -t "$TMUX_SESSION" Enter 2>/dev/null || return 1
  return 0
}

# Widen the poll interval after a rate-limit rejection, up to MAX_INTERVAL.
widen_interval() {
  local next=$(( CURRENT_INTERVAL * 2 ))
  [ "$next" -gt "$MAX_INTERVAL" ] && next="$MAX_INTERVAL"
  if [ "$next" != "$CURRENT_INTERVAL" ]; then
    CURRENT_INTERVAL="$next"
    log "RATELIMIT poll interval widened to ${CURRENT_INTERVAL}s"
  fi
}

poll_once() {
  local last_ts body status response new_ts mine_count

  # First run: no timestamp yet. Bootstrap to "now" so the channel's whole
  # backlog is never replayed as unread.
  if [ ! -f "$TS_FILE" ]; then
    date +%s > "$TS_FILE"
    log "BOOTSTRAP timestamp set to now, backlog ignored"
    return 0
  fi

  last_ts=$(cat "$TS_FILE" 2>/dev/null || echo "0")

  # Status code is appended on its own line so a 429 can be told apart from a
  # plain error payload.
  response=$(curl -s --max-time "$CURL_MAX_TIME" -w '\n%{http_code}' \
    -H "Authorization: Bearer ${BOT_TOKEN}" \
    --get "https://slack.com/api/conversations.history" \
    --data-urlencode "channel=${CHANNEL_ID}" \
    --data-urlencode "oldest=${last_ts}" \
    --data-urlencode "inclusive=false" \
    --data-urlencode "limit=50")

  status="${response##*$'\n'}"
  body="${response%$'\n'*}"

  # Empty body: timeout or transient network failure. Timestamp untouched, retry.
  [ -z "$body" ] && return 0

  if [ "$status" = "429" ]; then
    log "RATELIMIT HTTP 429 from Slack"
    widen_interval
    sleep "$ERROR_SLEEP"
    return 0
  fi

  if ! echo "$body" | jq -e . >/dev/null 2>&1; then
    log "ERROR non-JSON response from Slack (http ${status})"
    sleep "$ERROR_SLEEP"
    return 0
  fi

  if echo "$body" | jq -e '.ok == false' >/dev/null 2>&1; then
    local err_desc
    err_desc=$(echo "$body" | jq -r '.error // "unknown"')
    if [ "$err_desc" = "ratelimited" ]; then
      log "RATELIMIT Slack API said ratelimited"
      widen_interval
    else
      log "ERROR Slack API: $err_desc"
    fi
    sleep "$ERROR_SLEEP"
    return 0
  fi

  # A clean answer means the current interval is acceptable to Slack.
  CURRENT_INTERVAL="$POLL_INTERVAL"

  # Slack returns newest-first. The newest ts in the raw batch (before filtering)
  # is the new watermark, so a message from someone else still moves us forward
  # and the same window is never re-fetched.
  new_ts=$(echo "$body" | jq -r '.messages[0].ts // empty')
  [ -z "$new_ts" ] && return 0   # nothing new since last check

  # Only real messages from the allowed user are worth a wake-up: drop bot echoes
  # and system subtypes, but keep file shares.
  mine_count=$(echo "$body" | jq --arg uid "$ALLOWED_USER" \
    '[.messages[] | select(.user == $uid and (.bot_id == null) and ((has("subtype") | not) or .subtype == "file_share"))] | length')

  if [ "$mine_count" -gt 0 ]; then
    # Inbox first, timestamp second: a crash here duplicates, never drops.
    # Reversed to chronological order, and stored raw so check-slack.sh keeps
    # ownership of file downloads and output shaping.
    echo "$body" | jq -c --arg uid "$ALLOWED_USER" \
      '[.messages[] | select(.user == $uid and (.bot_id == null) and ((has("subtype") | not) or .subtype == "file_share"))] | reverse | .[]' \
      >> "$INBOX_FILE"
    sync 2>/dev/null || true
  fi

  echo "$new_ts" > "$TS_FILE"

  if [ "$mine_count" -gt 0 ]; then
    log "MESSAGE ${mine_count} from allowed user, waking agent"
    wake_agent && log "WAKE sent" || log "WAKE failed"
  else
    log "SKIP $(echo "$body" | jq '.messages | length') message(s), none from allowed user"
  fi
  return 0
}

# Sourced instead of executed (the test suite does this): hand over the functions
# and stop here, or the caller inherits the poll loop below and never returns.
if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  return 0 2>/dev/null || true
fi

if [ -z "$BOT_TOKEN" ] || [ -z "$CHANNEL_ID" ] || [ -z "$ALLOWED_USER" ]; then
  log "FATAL missing SLACK_BOT_TOKEN, SLACK_CHANNEL_ID or SLACK_ALLOWED_USER"
  exit 1
fi

for bin in curl jq "$TMUX_BIN"; do
  command -v "$bin" >/dev/null 2>&1 || { log "FATAL missing dependency: $bin"; exit 1; }
done

log "START listener pid=$$ session=$TMUX_SESSION interval=${POLL_INTERVAL}s"
trap 'log "STOP listener pid=$$"; exit 0' TERM INT

while true; do
  date -u +%s > "$ALIVE_FILE"
  poll_once
  [ "$ONE_SHOT" = "1" ] && break
  sleep "$CURRENT_INTERVAL"
done
