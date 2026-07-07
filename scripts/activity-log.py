#!/usr/bin/env python3
# Stop hook — append-only NDJSON activity log.
# One line per turn: timestamp, session, last user prompt, assistant summary (truncated).

import json, sys, os, datetime

AGENT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG_FILE = os.path.join(AGENT_DIR, "data", "activity-log.ndjson")

try:
    data = json.load(sys.stdin)
except Exception:
    data = {}

session_id = data.get("session_id", "")
transcript_path = data.get("transcript_path", "")

user_prompt = ""
assistant_summary = ""

if transcript_path and os.path.exists(transcript_path):
    try:
        lines = open(transcript_path).readlines()
        messages = [json.loads(l) for l in lines if l.strip()]
        # Find last user and last assistant messages
        for msg in reversed(messages):
            role = msg.get("role", "")
            content = msg.get("content", "")
            if isinstance(content, list):
                content = " ".join(
                    p.get("text", "") for p in content if isinstance(p, dict) and p.get("type") == "text"
                )
            if role == "user" and not user_prompt:
                user_prompt = str(content)[:200]
            elif role == "assistant" and not assistant_summary:
                assistant_summary = str(content)[:300]
            if user_prompt and assistant_summary:
                break
    except Exception:
        pass

entry = {
    "ts": datetime.datetime.now(datetime.timezone.utc).isoformat() + "Z",
    "session": session_id,
    "user_prompt": user_prompt,
    "assistant_summary": assistant_summary,
}

os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
with open(LOG_FILE, "a", encoding="utf-8") as f:
    f.write(json.dumps(entry, ensure_ascii=False) + "\n")
