#!/bin/bash
# Heartbeat memory enrichment
# 1. Recent activity in the agent's basic-memory project (what changed)
# 2. Connected context from the most recent non-session note (what it links to)
# Called from HEARTBEAT.md checklist at each 30m heartbeat.
#
# Optional: this only does something if you use basic-memory. Set BM_PROJECT to
# your project name (in .env or the environment); the default matches the name
# suggested during onboarding.

BM="$(which basic-memory 2>/dev/null || echo "$HOME/.local/share/uv/tools/basic-memory/bin/basic-memory")"
BM_PROJECT="${BM_PROJECT:-agent-memory}"

# No basic-memory installed: stay silent instead of printing errors into every heartbeat.
if [ ! -x "$BM" ] && ! command -v basic-memory >/dev/null 2>&1; then
  exit 0
fi

echo ""
echo "=== Recent Activity (${BM_PROJECT}) ==="

RECENT_JSON=$("$BM" tool recent-activity \
  --project "$BM_PROJECT" \
  --timeframe 1d \
  --page-size 8 2>/dev/null)

echo "$RECENT_JSON" | python3 -c "
import sys, json
try:
    items = json.load(sys.stdin)
    if not items:
        print('Nimic nou in ultimele 24h.')
    else:
        for item in items[:5]:
            title = item.get('title') or item.get('entity', '-')
            ts = str(item.get('created_at', ''))[:10]
            print('- [' + ts + '] ' + title)
except Exception as e:
    print('(eroare: ' + str(e) + ')')
"

# Gaseste prima nota care nu e session-notes pentru build-context
CONTEXT_PERMALINK=$(echo "$RECENT_JSON" | python3 -c "
import sys, json
try:
    items = json.load(sys.stdin)
    for item in items:
        p = item.get('permalink', '')
        if p and 'session-notes' not in p:
            print(p)
            break
except:
    pass
" 2>/dev/null)

if [ -n "$CONTEXT_PERMALINK" ]; then
  NOTE_NAME="${CONTEXT_PERMALINK##*/}"
  echo ""
  echo "=== Context Conectat ($NOTE_NAME) ==="
  "$BM" tool build-context "$CONTEXT_PERMALINK" \
    --project "$BM_PROJECT" \
    --depth 1 \
    --timeframe 30d \
    --page-size 5 2>/dev/null \
  | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    primary = data.get('primary_note', {})
    if primary.get('title'):
        print('Nota: ' + primary['title'])
    related = data.get('related_notes', [])
    if related:
        print('Legate de ea:')
        for r in related[:4]:
            print('  - ' + r.get('title', '-'))
    else:
        print('(nicio nota legata gasita)')
except Exception as e:
    print('(eroare build-context: ' + str(e) + ')')
"
fi
