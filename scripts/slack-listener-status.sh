#!/bin/bash
# One-line health verdict for the Slack listener.
# Called by the hourly safety-net cron, and useful by hand.

ALIVE_FILE="${LISTENER_ALIVE_FILE:-$HOME/.agent-logs/slack-listener-alive}"
STALE="${LISTENER_STALE_SECONDS:-180}"
LABEL="com.my-agent-slack"

pid=$(launchctl list 2>/dev/null | awk -v l="$LABEL" '$3==l && $1 ~ /^[0-9]+$/ {print $1}')
beat=$(cat "$ALIVE_FILE" 2>/dev/null)
now=$(date -u +%s)

case "$beat" in ''|*[!0-9]*) age="" ;; *) age=$(( now - beat )) ;; esac

if [ -n "$pid" ] && [ -n "$age" ] && [ "$age" -le "$STALE" ]; then
  echo "VIU  pid=${pid}  ultima bataie acum ${age}s  (prag ${STALE}s)"
  exit 0
fi

if [ -z "$pid" ]; then
  echo "MORT  procesul nu ruleaza sub launchd (${LABEL})"
elif [ -z "$age" ]; then
  echo "MORT  proces pid=${pid} dar fara semnal de viata in ${ALIVE_FILE}"
else
  echo "MORT  proces pid=${pid} dar ultima bataie acum ${age}s, peste pragul de ${STALE}s"
fi
echo "Repornire: launchctl kickstart -k gui/$(id -u)/${LABEL}"
exit 1
