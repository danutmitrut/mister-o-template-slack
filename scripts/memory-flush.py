#!/usr/bin/env python3
"""
Memory flush - triggered by PreCompact hook.
Reads recent assistant messages from session JSONL,
writes a compact summary to today's daily memory file.
Runs at most once every 10 minutes to avoid duplicate entries.
"""

import json
import os
import shutil
import sys
import time
from datetime import datetime
from pathlib import Path

AGENT_DIR = Path(__file__).parent.parent.resolve()
_agent_slug = str(AGENT_DIR).replace("/", "-").lstrip("-")
PROJECTS_DIR = Path.home() / f".claude/projects/{_agent_slug}"
BM = Path(shutil.which("basic-memory") or Path.home() / ".local/share/uv/tools/basic-memory/bin/basic-memory")

TODAY = datetime.now().strftime("%Y-%m-%d")
NOW = datetime.now().strftime("%H:%M")
DAILY_FILE = AGENT_DIR / f"memory/{TODAY}.md"
LOCK_FILE = Path(f"/tmp/agent-flush-{os.getuid()}-{datetime.now().strftime('%Y%m%d-%H%M')[:-1]}.lock")


def throttle_check():
    """Allow flush at most once per 10 minutes."""
    if LOCK_FILE.exists():
        return False
    LOCK_FILE.touch()
    return True


def get_latest_session():
    """Find most recently modified session JSONL for this project."""
    if not PROJECTS_DIR.exists():
        return None
    sessions = sorted(
        PROJECTS_DIR.glob("*.jsonl"),
        key=lambda f: f.stat().st_mtime,
        reverse=True,
    )
    return sessions[0] if sessions else None


def extract_key_messages(jsonl_path, max_messages=8):
    """Extract recent meaningful assistant text blocks from session JSONL."""
    messages = []
    skip_patterns = [
        "Niciun mesaj nou",
        "Check Slack",
        "Bash completed with no output",
    ]
    with open(jsonl_path, encoding="utf-8") as f:
        for line in f:
            try:
                obj = json.loads(line)
                if obj.get("type") != "assistant":
                    continue
                for block in obj.get("message", {}).get("content", []):
                    if not isinstance(block, dict) or block.get("type") != "text":
                        continue
                    text = block.get("text", "").strip()
                    if len(text) < 80:
                        continue
                    if any(p in text for p in skip_patterns):
                        continue
                    messages.append(text[:400].replace("\n", " "))
            except Exception:
                pass
    return messages[-max_messages:]


def flush():
    if not throttle_check():
        return

    session = get_latest_session()
    if not session:
        return

    msgs = extract_key_messages(session)
    if not msgs:
        return

    lines = [f"\n## Memory Flush {NOW} (PreCompact)\n"]
    for m in msgs[-5:]:
        lines.append(f"- {m}")

    with open(DAILY_FILE, "a", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    # Optionally write a note to basic-memory (if installed).
    # Change "agent-memory" to your basic-memory project name.
    note_content = "\n".join(f"- {m}" for m in msgs[-5:])
    note_title = f"Session Notes {TODAY} {NOW}"
    try:
        import subprocess
        subprocess.run(
            [str(BM), "tool", "write-note",
             "--title", note_title,
             "--folder", "session-notes",
             "--project", "agent-memory",
             "--content", note_content],
            capture_output=True,
            timeout=15,
        )
    except Exception:
        pass  # basic-memory write is best-effort


if __name__ == "__main__":
    flush()
