#!/bin/bash
# Tests for the Slack listener and the inbox path in check-slack.sh.
# Nothing here touches the real agent session; the only network calls are the
# deliberate fallback checks, made with a bogus token.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LISTENER="$DIR/scripts/slack-listener.sh"
STATUS="$DIR/scripts/slack-listener-status.sh"
GENERATOR="$DIR/scripts/generate-slack-listener-launchd.sh"
CHECKER="$DIR/.claude/skills/slack-bot/check-slack.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0
ok()   { printf '  ok    %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  FAIL  %s\n     %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }

# A message shaped exactly like Slack's, from the allowed user.
mk_msg() {
  local ts="$1" text="$2"
  printf '{"user":"U0TEST123","type":"message","text":"%s","ts":"%s.000100"}\n' "$text" "$ts"
}

echo "== sintaxa =="
bash -n "$LISTENER"  2>/dev/null && ok "slack-listener.sh se parsează"        || bad "slack-listener.sh nu se parsează"
bash -n "$STATUS"    2>/dev/null && ok "slack-listener-status.sh se parsează" || bad "slack-listener-status.sh nu se parsează"
bash -n "$GENERATOR" 2>/dev/null && ok "generatorul de plist se parsează"     || bad "generatorul de plist nu se parsează"
bash -n "$CHECKER"   2>/dev/null && ok "check-slack.sh se parsează"           || bad "check-slack.sh nu se parsează"

echo
echo "== check-slack.sh: citește din inbox =="

export SLACK_BOT_TOKEN="xoxb-test-token"
export SLACK_CHANNEL_ID="C0TEST123"
export SLACK_ALLOWED_USER="U0TEST123"
export TS_FILE="$WORK/ts"
export INBOX_FILE="$WORK/inbox.jsonl"
export LISTENER_ALIVE_FILE="$WORK/alive"

mk_msg 1780000001 "salut" > "$INBOX_FILE"
OUT=$(bash "$CHECKER" 2>&1)
echo "$OUT" | jq -e '.text == "salut"' >/dev/null 2>&1 \
  && ok "mesajul din inbox e emis în formatul așteptat" \
  || bad "mesajul din inbox nu a ieșit corect" "$OUT"

echo "$OUT" | jq -e '.chat_id == "C0TEST123"' >/dev/null 2>&1 \
  && ok "chat_id e channel-ul configurat, gata de pasat la send-slack.sh" \
  || bad "chat_id lipsește sau e greșit" "$OUT"

[ ! -s "$INBOX_FILE" ] && ok "inboxul e golit după procesare" || bad "inboxul a rămas plin"

# Two messages arriving together must both come out, in order.
mk_msg 1780000002 "unu" >  "$INBOX_FILE"
mk_msg 1780000003 "doi" >> "$INBOX_FILE"
OUT=$(bash "$CHECKER" 2>&1)
[ "$(echo "$OUT" | jq -s 'length')" = "2" ] \
  && ok "două mesaje în lot ies amândouă" \
  || bad "lotul de două nu a ieșit întreg" "$OUT"
[ "$(echo "$OUT" | jq -rs '.[0].text')" = "unu" ] \
  && ok "ordinea mesajelor se păstrează" \
  || bad "ordinea s-a pierdut"

echo
echo "== check-slack.sh: nu fură conexiunea listenerului =="

rm -f "$INBOX_FILE"
date -u +%s > "$LISTENER_ALIVE_FILE"          # listener viu, acum
OUT=$(bash "$CHECKER" 2>&1); RC=$?
[ $RC -eq 0 ] && [ -z "$OUT" ] \
  && ok "inbox gol + listener viu: iese curat, fără să consume din rate limit" \
  || bad "ar fi trebuit să iasă tăcut (rc=$RC)" "$OUT"

# Listener dead. A timestamp must already exist, or the checker bootstraps and exits
# before it ever reaches the API.
echo "1780000000.000100" > "$TS_FILE"
echo $(( $(date -u +%s) - 600 )) > "$LISTENER_ALIVE_FILE"   # bătaie veche de 10 min
OUT=$(bash "$CHECKER" 2>&1)
echo "$OUT" | grep -qi "error\|invalid_auth\|^$" \
  && ok "listener mort: cade înapoi pe polling direct (a chemat API-ul)" \
  || bad "nu a încercat pollingul direct" "$OUT"

rm -f "$LISTENER_ALIVE_FILE"
OUT=$(bash "$CHECKER" 2>&1)
echo "$OUT" | grep -qi "error\|invalid_auth\|^$" \
  && ok "fără fișier de viață: tot pe polling direct" \
  || bad "nu a încercat pollingul direct" "$OUT"

echo
echo "== check-slack.sh: prima rulare nu inundă cu backlog =="

rm -f "$TS_FILE" "$LISTENER_ALIVE_FILE" "$INBOX_FILE"
OUT=$(bash "$CHECKER" 2>&1); RC=$?
[ $RC -eq 0 ] && [ -z "$OUT" ] && [ -s "$TS_FILE" ] \
  && ok "fără timestamp: se ancorează la acum și tace" \
  || bad "prima rulare nu s-a ancorat curat (rc=$RC)" "$OUT"

echo
echo "== listener: bootstrap și backoff =="

rm -f "$WORK/ts2"
TS_FILE="$WORK/ts2" LISTENER_ALIVE_FILE="$WORK/alive2" LISTENER_LOG_FILE="$WORK/log2" \
  bash -c 'source "'"$LISTENER"'" 2>/dev/null || true; poll_once' >/dev/null 2>&1
[ -s "$WORK/ts2" ] \
  && ok "listenerul se ancorează la acum la prima rulare, fără să cheme API-ul" \
  || bad "listenerul nu a scris timestampul de bootstrap"

# The rate-limit backoff must double, then stop at the ceiling.
OUT=$(POLL_INTERVAL=10 MAX_INTERVAL=40 LISTENER_LOG_FILE="$WORK/log3" \
  bash -c 'source "'"$LISTENER"'" 2>/dev/null || true
           widen_interval; widen_interval; widen_interval; echo "$CURRENT_INTERVAL"' 2>/dev/null | tail -1)
[ "$OUT" = "40" ] \
  && ok "backoff-ul la rate limit se dublează și se oprește la plafon" \
  || bad "backoff-ul nu s-a plafonat corect (a dat '$OUT', aștept 40)"

echo
echo "== listener: trezirea agentului =="

# Fake tmux that records what it was asked to do.
cat > "$WORK/tmux" <<'FAKE'
#!/bin/bash
echo "$@" >> "$TMUX_CALLS"
case "$1" in
  has-session) [ "${TMUX_HAS_SESSION:-1}" = "1" ] && exit 0 || exit 1 ;;
esac
exit 0
FAKE
chmod +x "$WORK/tmux"
export TMUX_CALLS="$WORK/tmux-calls"

: > "$TMUX_CALLS"
TMUX_BIN="$WORK/tmux" TMUX_HAS_SESSION=1 \
LISTENER_ALIVE_FILE="$WORK/alive3" LISTENER_LOG_FILE="$WORK/log4" \
bash -c 'source "'"$LISTENER"'" 2>/dev/null || true; wake_agent' >/dev/null 2>&1

if grep -q "send-keys" "$TMUX_CALLS" 2>/dev/null && grep -q "Enter" "$TMUX_CALLS" 2>/dev/null; then
  ok "trimite promptul și Enter separat"
else
  bad "nu a trimis send-keys + Enter" "$(cat "$TMUX_CALLS" 2>/dev/null)"
fi

: > "$TMUX_CALLS"
TMUX_BIN="$WORK/tmux" TMUX_HAS_SESSION=0 \
LISTENER_ALIVE_FILE="$WORK/alive4" LISTENER_LOG_FILE="$WORK/log5" \
bash -c 'source "'"$LISTENER"'" 2>/dev/null || true; wake_agent' >/dev/null 2>&1
if grep -q "send-keys" "$TMUX_CALLS" 2>/dev/null; then
  bad "a trimis taste într-o sesiune inexistentă"
else
  ok "sesiune lipsă: nu trimite nimic, nu crapă"
fi

echo
echo "== status: verdict citibil =="

OUT=$(LISTENER_ALIVE_FILE="$WORK/nonexistent" bash "$STATUS" 2>&1); RC=$?
[ $RC -ne 0 ] && echo "$OUT" | grep -q "MORT" \
  && ok "fără proces și fără bătaie: raportează MORT cu cod de eroare" \
  || bad "verdictul MORT lipsește (rc=$RC)" "$OUT"

echo "$OUT" | grep -q "launchctl kickstart" \
  && ok "verdictul include comanda de repornire" \
  || bad "lipsește comanda de repornire" "$OUT"

echo
echo "== plist: se generează valid =="

PLIST="$WORK/com.my-agent-slack.plist"
OUT_FILE="$PLIST" PROJECT_DIR="$DIR" bash "$GENERATOR" >/dev/null 2>&1
if [ -f "$PLIST" ]; then
  ok "plist-ul se scrie"
  if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$PLIST" >/dev/null 2>&1 \
      && ok "plist-ul trece plutil -lint" \
      || bad "plist invalid" "$(plutil -lint "$PLIST" 2>&1)"
  fi
  grep -q "KeepAlive" "$PLIST" \
    && ok "plist-ul cere KeepAlive (listenerul trebuie să fie mereu viu)" \
    || bad "lipsește KeepAlive din plist"
  grep -q "${DIR}/scripts/slack-listener.sh" "$PLIST" \
    && ok "plist-ul arată spre listenerul din instalarea curentă" \
    || bad "calea din plist nu e cea a proiectului"
else
  bad "plist-ul nu s-a scris"
fi

echo
echo "---------------------------------------------"
if [ "$FAIL" -eq 0 ]; then
  echo "Toate cele $PASS verificări trec."
  exit 0
else
  echo "$FAIL din $((PASS+FAIL)) verificări au picat."
  exit 1
fi
