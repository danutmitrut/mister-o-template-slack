#!/usr/bin/env python3
# PreToolUse hook — block infinite loops.
# Tracks identical tool calls per session-hour. Blocks at THRESHOLD repeats.

import json, sys, os, hashlib, datetime

THRESHOLD = 150  # cron tasks repeat legitimately (30s interval = 120x/hour); block only true runaway loops

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

tool_name = data.get("tool_name", "")
tool_input = json.dumps(data.get("tool_input", {}), sort_keys=True)
call_hash = hashlib.md5(f"{tool_name}:{tool_input}".encode()).hexdigest()[:10]

# State file keyed by session-hour so it resets naturally
session_key = data.get("session_id", "nosession")[:8]
hour_key = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H")
state_file = f"/tmp/agent-loop-{session_key}-{hour_key}.json"

try:
    state = json.load(open(state_file))
except Exception:
    state = {}

count = state.get(call_hash, 0) + 1
state[call_hash] = count

try:
    with open(state_file, "w") as f:
        json.dump(state, f)
except Exception:
    pass

if count >= THRESHOLD:
    print(f"[LOOP DETECTED] Tool '{tool_name}' called {count} times with identical input. "
          f"Blocking execution to prevent infinite loop. "
          f"Review what is causing the repetition and take a different approach.")
    sys.exit(2)  # exit 2 = block tool call in Claude Code

sys.exit(0)
