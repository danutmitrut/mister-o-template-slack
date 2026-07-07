#!/usr/bin/env bash
# Dream hook pentru Mister O. - Stop hook adapter
# Verifica daca trebuie consolidare memorie (24h), daca da lanseaza dream ca subagent background

AGENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_DIR="$AGENT_DIR/.claude/skills/dream"

if bash "$SKILL_DIR/should-dream.sh" 2>/dev/null; then
    nohup claude -p \
        "Run the Dream memory consolidation skill. Read '${SKILL_DIR}/SKILL.md' and execute all 4 phases for the project at '${AGENT_DIR}'. Memory type: project-root. Memory path: '${AGENT_DIR}'." \
        --allowedTools "Read,Write,Edit,Bash,Glob,Grep" \
        > "/tmp/agent-dream-$(date +%Y%m%d-%H%M%S).log" 2>&1 &
    echo "Dream consolidation pornit in background (PID: $!)"
fi

exit 0
