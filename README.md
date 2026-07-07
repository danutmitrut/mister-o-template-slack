# mister-o-template-slack

Un agent Claude Code personal, 24/7, care rulează pe Mac și comunică prin Slack.

Bazat pe [OpenClawdCode](https://skool.com/openclawdcode) (Lesson 3), extins cu supervisor de uptime, memory consolidation (dream), multimodal knowledge base și feedback loop automat. Aceasta este varianta Slack a template-ului (comunicarea se face printr-un canal Slack dedicat, nu prin Telegram).

---

## Ce face acest agent

- Primește și răspunde la mesaje într-un canal Slack dedicat
- Rulează task-uri periodice (heartbeat la 30 de minute)
- Rămâne activ permanent via launchd + tmux + caffeinate
- Se repornește automat după 71 ore pentru context fresh
- Consolidează memoria zilnic (skill-ul dream)
- Monitorizează propria stare (supervisor cu alerte pe Slack)

---

## Prerequisite

- macOS (launchd este macOS-only)
- [Claude Code CLI](https://claude.ai/code) instalat și autentificat
- `tmux` instalat: `brew install tmux`
- `jq` instalat: `brew install jq`
- Un workspace Slack unde ai drept să instalezi o aplicație
- O aplicație Slack creată din `slack-app-manifest.json` (vezi `docs/SLACK-SETUP.md`)

---

## Instalare

### 1. Clonează repo-ul

```bash
git clone https://github.com/danutmitrut/mister-o-template-slack
cd mister-o-template-slack
```

### 2. Creează aplicația Slack

Urmează ghidul pas cu pas din [`docs/SLACK-SETUP.md`](docs/SLACK-SETUP.md). Pe scurt:
1. Creezi o aplicație Slack din `slack-app-manifest.json` (Create New App -> From an app manifest)
2. O instalezi în workspace și copiezi **Bot User OAuth Token** (`xoxb-...`)
3. Creezi un canal privat dedicat (ex. `#asistent`) și inviți botul
4. Iei **Channel ID** și **User ID**

### 3. Configurează `.env`

```bash
cp .env.example .env
```

Editează `.env` și completează:
- `SLACK_BOT_TOKEN` — tokenul `xoxb-...` al aplicației
- `SLACK_CHANNEL_ID` — ID-ul canalului dedicat (`C...`)
- `SLACK_ALLOWED_USER` — ID-ul tău de utilizator Slack (`U...`)

### 4. Completează fișierele de identitate

Editează fiecare fișier stub și înlocuiește placeholder-urile cu datele tale:

| Fișier | Ce completezi |
|--------|--------------|
| `IDENTITY.md` | Numele și personalitatea agentului |
| `SOUL.md` | Regulile de comportament |
| `USER.md` | Informații despre tine |
| `CONTRACT.md` | Granița de delegare |
| `TOOLS.md` | Toolurile disponibile |

`MEMORY.md`, `DECISIONS.md`, `GROUND-TRUTH.md` pot rămâne goale la start — agentul le populează singur.

### 5. Pornește Claude Code și rulează onboarding

```bash
claude
```

În Claude Code, rulează:
```
/onboarding
```

Skill-ul de onboarding detectează ce ai deja configurat și te ghidează prin pașii rămași, inclusiv setarea aplicației Slack și configurarea launchd pentru persistență permanentă.

### 6. Verifică că agentul rulează

```bash
tmux ls
```

Expected: `my-agent: 1 windows ...`

Scrie un mesaj în canalul dedicat. Ar trebui să primești răspuns în cel mult 1 minut.

---

## Structura repo-ului

```
mister-o-template-slack/
├── CLAUDE.md              # Instrucțiuni pentru agent (citit la fiecare sesiune)
├── IDENTITY.md            # Cine ești tu (agentul) — completează
├── SOUL.md                # Cum te comporți — completează
├── USER.md                # Despre utilizator — completează
├── CONTRACT.md            # Granița de delegare — completează
├── TOOLS.md               # Tooluri disponibile — completează
├── MEMORY.md              # Memorie pe termen lung — agentul completează
├── DECISIONS.md           # Decizii permanente — agentul completează
├── GROUND-TRUTH.md        # Starea sistemelor — agentul completează
├── HEARTBEAT.md           # Checklist heartbeat — personalizează
├── config.json            # Configurație cron-uri și supervisor
├── slack-app-manifest.json # Manifest pentru crearea aplicației Slack
├── .env.example           # Template pentru variabile de mediu
├── docs/
│   └── SLACK-SETUP.md     # Ghid pas cu pas pentru aplicația Slack
├── scripts/               # Scripturi de infrastructură
├── tests/                 # Suite de teste bash
└── .claude/
    └── skills/            # Skills pentru agent
        ├── onboarding/      # Wizard de setup
        ├── slack-bot/       # Integrare Slack
        ├── dream/           # Consolidare memorie
        ├── skill-optimizer/ # Audit rulare skills
        └── multimodal-rag/  # Knowledge base local
```

---

## Cum comunică agentul (pe scurt)

Agentul folosește **polling**, nu un server. La fiecare minut, un cron rulează `check-slack.sh`, care citește mesajele noi din canal via `conversations.history` și răspunde cu `chat.postMessage`. De aceea manifestul nu are nevoie de Socket Mode, URL public sau event subscriptions - doar de permisiunile de bot. Botul vede doar canalul în care a fost invitat, și doar mesajele utilizatorului permis.

Dacă vrei răspuns instant în loc de până la un minut, există o variantă opțională **Socket Mode** în [`slack-socket-bridge/`](slack-socket-bridge/): real-time, cu costul unei a doua componente de rulat. Rămâi pe polling dacă latența de un minut e acceptabilă (pentru un asistent personal, de regulă este).

---

## Adăugarea de skills personalizate

Creează un director în `.claude/skills/` cu un fișier `SKILL.md`:

```
.claude/skills/
└── my-skill/
    └── SKILL.md    # Instrucțiunile skill-ului
```

Invocă din Claude Code cu `/my-skill`.

---

## Comenzi utile

```bash
# Atașare la sesiunea live a agentului
tmux attach -t my-agent

# Detașare fără să oprești (Ctrl+B, apoi D)

# Verificare stare
tmux ls

# Restart manual
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.my-agent.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.my-agent.plist

# Vizualizare loguri
cat ~/.agent-logs/activity.log
cat ~/.agent-logs/crashes.log
```

---

## Credits

Infrastructura de bază: [OpenClawdCode](https://skool.com/openclawdcode) de grandamenium.
Extensii: supervisor uptime, dream memory consolidation, multimodal-rag, feedback loop, integrare Slack.
