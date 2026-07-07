#!/bin/bash
# Session memory injection hook
# Fires once per hour via UserPromptSubmit hook
# Injects SOUL.md + USER.md + MEMORY.md + today's daily log as context

LOCK_FILE="/tmp/agent-session-$(id -u)-$(date +%Y%m%d-%H).lock"

# Already injected this hour — exit silently
if [ -f "$LOCK_FILE" ]; then
  exit 0
fi

touch "$LOCK_FILE"

AGENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TODAY=$(date +%Y-%m-%d)
DAILY_FILE="$AGENT_DIR/memory/$TODAY.md"

printf "\n[MEMORY CONTEXT — injected at session start]\n"

if [ -f "$AGENT_DIR/SOUL.md" ]; then
  printf "\n--- Who You Are and How You Behave (SOUL.md) ---\n"
  cat "$AGENT_DIR/SOUL.md"
fi

if [ -f "$AGENT_DIR/USER.md" ]; then
  printf "\n--- About Your Human (USER.md) ---\n"
  cat "$AGENT_DIR/USER.md"
fi

if [ -f "$DAILY_FILE" ]; then
  printf "\n--- Activity Today (%s) ---\n" "$TODAY"
  cat "$DAILY_FILE"
fi

if [ -f "$AGENT_DIR/MEMORY.md" ]; then
  printf "\n--- Long-term Memory ---\n"
  cat "$AGENT_DIR/MEMORY.md"
fi

printf "\n[END MEMORY CONTEXT]\n\n"
