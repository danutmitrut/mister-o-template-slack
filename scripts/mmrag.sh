#!/usr/bin/env bash
# Wrapper mmrag pentru Mister O.
# Seteaza automat GEMINI_API_KEY din Keychain si foloseste venv-ul corect

export GEMINI_API_KEY=$(security find-generic-password -a "gemini" -s "GEMINI_API_KEY" -w 2>/dev/null)

AGENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MMRAG="$AGENT_DIR/.claude/skills/multimodal-rag/scripts/mmrag.py"
PYTHON="$HOME/.mmrag/venv/bin/python3"

"$PYTHON" "$MMRAG" "$@"
