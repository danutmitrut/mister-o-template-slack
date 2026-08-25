# Listenerul de Slack

## Ce problemă rezolvă

Fără listener, agentul își verifică singur mesajele, pe un cron. Verificarea în sine e gratuită, e un simplu apel HTTP. Scump e altceva: ca să ruleze acel apel, agentul trebuie trezit, iar la fiecare trezire își reîncarcă tot contextul, indiferent dacă a găsit ceva sau nu. Un cron la un minut înseamnă peste 500 de treziri pe zi, aproape toate degeaba, pe un inbox gol.

Listenerul mută verificarea în shell, unde nu costă nimic, și trezește agentul doar când chiar există un mesaj. Într-o zi liniștită agentul nu se trezește deloc pentru comunicare.

## Cum funcționează

```
Slack  ->  slack-listener.sh  ->  ~/.claude-slack-inbox.jsonl  ->  agentul, trezit prin tmux
              (daemon launchd)         (mesaje brute)                 check-slack.sh golește inboxul
```

1. `scripts/slack-listener.sh` rulează permanent sub launchd (`com.my-agent-slack`) și interoghează `conversations.history` la fiecare 10 secunde.
2. Când găsește mesaje de la `SLACK_ALLOWED_USER`, le scrie brute în inbox, apoi avansează marcajul de timp din `~/.claude-slack-ts`. Ordinea contează: dacă procesul moare între cele două, mesajul se livrează de două ori, ceea ce e recuperabil, în loc să se piardă, ceea ce nu e.
3. Trezește agentul cu `tmux send-keys`, cu un prompt scurt.
4. `check-slack.sh` golește inboxul printr-o redenumire atomică, descarcă fișierele atașate și emite mesajele în formatul cunoscut de agent.

Dacă listenerul moare, `check-slack.sh` observă (semnalul de viață din `~/.agent-logs/slack-listener-alive` e mai vechi de 180 de secunde) și revine singur la interogare directă. Comunicarea nu se rupe, doar devine mai lentă și mai scumpă până repornești daemonul.

## Rate limits, partea importantă

Din 29 mai 2025, Slack limitează `conversations.history` la **un request pe minut și maximum 15 mesaje** pentru aplicațiile distribuite comercial în afara Slack Marketplace. Din 3 martie 2026 regula se aplică și instalărilor existente ale acestor aplicații.

**Aplicațiile interne nu sunt afectate.** O aplicație pe care ți-o creezi singur în workspace-ul tău, din manifestul livrat cu acest template, și pe care nu o distribui altcuiva, rămâne la 50+ requesturi pe minut. Pe asta se bazează intervalul implicit de 10 secunde (6 requesturi pe minut, confortabil sub limită).

Dacă totuși primești `429` sau `ratelimited`, listenerul nu insistă: își dublează intervalul, până la maximum 60 de secunde, și revine la normal după primul răspuns curat. Un `RATELIMIT` în `~/.agent-logs/slack-listener.log` înseamnă că aplicația ta e tratată ca fiind distribuită, iar atunci alternativa corectă e Socket Mode (vezi mai jos).

Referință: [Rate limit changes for non-Marketplace apps](https://docs.slack.dev/changelog/2025/05/29/rate-limit-changes-for-non-marketplace-apps/)

## Comenzi

```bash
# Instalare (o singură dată)
bash scripts/generate-slack-listener-launchd.sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.my-agent-slack.plist

# Stare
bash scripts/slack-listener-status.sh

# Repornire
launchctl kickstart -k gui/$(id -u)/com.my-agent-slack

# Log
tail -f ~/.agent-logs/slack-listener.log

# Oprire completă
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.my-agent-slack.plist
```

## Reglaje

Se dau ca variabile de mediu în plist, dacă e nevoie. Implicit nu trebuie atinse.

| Variabilă | Implicit | Ce face |
|---|---|---|
| `POLL_INTERVAL` | 10 | secunde între verificări |
| `MAX_INTERVAL` | 60 | plafonul la care urcă backoff-ul după rate limit |
| `ERROR_SLEEP` | 15 | pauză după o eroare de API sau de rețea |
| `CURL_MAX_TIME` | 15 | plafon per request, ca o conexiune blocată să nu înghețe bucla |
| `TMUX_SESSION` | my-agent | sesiunea în care se injectează promptul de trezire |

## Listener sau Socket Mode

Amândouă rezolvă aceeași problemă, dar nu le rula simultan: ar injecta fiecare câte un prompt pentru același mesaj, iar agentul ar răspunde de două ori.

**Listenerul** (implicit) e bash curat, fără dependințe, fără proces Node, fără token în plus. Latență de până la 10 secunde. Potrivit pentru aplicații interne.

**Socket Mode** (`slack-socket-bridge/`) e push real prin WebSocket, latență instantanee, nesupus limitelor pe `conversations.history`. Cere Node, un `SLACK_APP_TOKEN` (`xapp-...`) și manifestul cu socket mode activat. Alege-l dacă vrei răspuns instantaneu sau dacă logul îți arată `RATELIMIT`.

Dacă treci pe Socket Mode, scoate listenerul din launchd:
```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.my-agent-slack.plist
```

## Cronul de comunicare

După instalarea listenerului, cronul de comunicare din `config.json` nu mai e calea prin care ajung mesajele, ci plasa de siguranță. Rulează o dată pe oră, verifică dacă listenerul e viu și te anunță pe Slack dacă a căzut. Nu-l pune înapoi la un minut: ai anula exact economia pentru care există listenerul.
