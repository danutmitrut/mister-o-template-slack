# slack-socket-bridge (opțional, real-time)

Alternativă la polling: în loc ca agentul să verifice Slack o dată pe minut, un mic proces Node ține o conexiune Socket Mode deschisă și îi trimite mesajele **instant**.

Folosește-l doar dacă vrei răspuns sub o secundă. Costul e o a doua componentă de rulat și supravegheat. Pentru majoritatea asistenților personali, polling-ul la 1 minut (varianta implicită) e suficient.

---

## Cum funcționează

- **Inbound (Slack -> agent):** bridge-ul primește mesajul prin WebSocket și îl injectează în sesiunea tmux a agentului cu `tmux send-keys`. Agentul se trezește imediat, cu tot contextul sesiunii live.
- **Outbound (agent -> Slack):** neschimbat. Agentul răspunde cu `.claude/skills/slack-bot/send-slack.sh`, exact ca în modul polling.

Deci bridge-ul înlocuiește doar recepția. Trimiterea rămâne prin skill-ul existent.

---

## Setup

### 1. Instalează dependențele

```bash
cd slack-socket-bridge
npm install
```

### 2. Activează Socket Mode pe aplicația Slack

Ai două variante:

- **App nou:** creează o aplicație din `slack-app-manifest-socket.json` (Create New App -> From an app manifest). Acest manifest are deja Socket Mode și event subscriptions pornite.
- **App existent (cel de la polling):** în pagina aplicației, mergi la **Socket Mode** și activează-l, apoi la **Event Subscriptions** adaugă bot events: `app_mention`, `message.channels`, `message.groups`, `message.im`.

### 3. Generează App-Level Token (xapp-)

1. În pagina aplicației -> **Basic Information** -> **App-Level Tokens** -> **Generate Token and Scopes**
2. Nume: `agent-socket`, scope: `connections:write`
3. **Generate** și copiază tokenul `xapp-...`

### 4. Adaugă tokenul în `.env`

Adaugă o singură linie în `.env`-ul din rădăcina proiectului (unde ai deja `SLACK_BOT_TOKEN`, `SLACK_CHANNEL_ID`, `SLACK_ALLOWED_USER`):

```
SLACK_APP_TOKEN=xapp-...
```

### 5. Oprește polling-ul

Ca să nu ai și push, și polling în paralel (mesaje procesate de două ori), scoate cronul de comunicare din `config.json`. Șterge din array-ul `crons` intrarea cu `check-slack.sh` (cea cu `"interval": "1m"`). Lasă doar heartbeat-ul de 30m. Repornește agentul ca să preia noua configurație.

### 6. Pornește bridge-ul

Cel mai simplu, cu PM2 (dacă îl ai):

```bash
pm2 start index.js --name slack-bridge --cwd "$(pwd)"
pm2 save
```

Sau, pentru pornire automată la login fără PM2, cu launchd, creează `~/Library/LaunchAgents/com.my-agent-slack-bridge.plist` (înlocuiește CALEA):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.my-agent-slack-bridge</string>
  <key>ProgramArguments</key>
  <array>
    <string>/opt/homebrew/bin/node</string>
    <string>CALEA/slack-socket-bridge/index.js</string>
  </array>
  <key>WorkingDirectory</key><string>CALEA/slack-socket-bridge</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/slack-bridge.log</string>
  <key>StandardErrorPath</key><string>/tmp/slack-bridge.err</string>
</dict>
</plist>
```

apoi `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.my-agent-slack-bridge.plist`.

### 7. Testează

Scrie în canal. Ar trebui să vezi în logul bridge-ului `forwarded message ...` și agentul să răspundă în câteva secunde.

---

## Variabile de mediu

| Variabilă | Necesară | Rol |
|---|---|---|
| `SLACK_BOT_TOKEN` | da | Bot token `xoxb-` (comun cu agentul) |
| `SLACK_APP_TOKEN` | da | App-level token `xapp-` pentru Socket Mode |
| `SLACK_CHANNEL_ID` | da | Canalul ascultat (`C...`) |
| `SLACK_ALLOWED_USER` | recomandat | Doar mesajele acestui user sunt trimise |
| `TMUX_SESSION` | nu | Numele sesiunii tmux (default `my-agent`) |
| `AGENT_DIR` | nu | Rădăcina proiectului agentului (default: folderul părinte) |

---

## Limitări

- Bridge-ul injectează în sesiunea tmux `my-agent`. Dacă agentul nu rulează (sesiune inexistentă), mesajul e ignorat cu un mesaj în log, nu pus în coadă.
- Dacă agentul se repornește (la 71h), primele mesaje din fereastra de repornire se pot pierde. Polling-ul nu are această problemă (reia din offset).
- Pentru fiabilitate maximă fără real-time, rămâi pe polling.
