# Setup Slack - ghid pas cu pas

Acest ghid te duce de la zero la un bot Slack care vorbește cu agentul tău, într-un singur canal dedicat. Durează ~10 minute. Nu ai nevoie de cunoștințe tehnice.

Agentul folosește **polling**: citește periodic mesajele din canal și răspunde. Nu e un server, deci nu ai nevoie de Socket Mode, de un URL public sau de event subscriptions. Trebuie doar să creezi aplicația, s-o instalezi și să copiezi trei valori.

La final vei avea trei valori pe care le pui în fișierul `.env`:
- `SLACK_BOT_TOKEN` (începe cu `xoxb-`)
- `SLACK_CHANNEL_ID` (începe cu `C`)
- `SLACK_ALLOWED_USER` (începe cu `U`)

---

## Pasul 1: Creează aplicația din manifest

1. Intră pe https://api.slack.com/apps
2. Apasă **Create New App**
3. Alege **From an app manifest**
4. Selectează workspace-ul tău și apasă **Next**
5. Șterge conținutul din caseta care apare și lipește tot conținutul fișierului `slack-app-manifest.json` din proiect
6. **Next**, apoi **Create**

Manifestul setează deja numele botului și permisiunile corecte. Nu trebuie să bifezi nimic manual.

> Poți schimba numele: în `slack-app-manifest.json`, câmpul `display_information.name` (numele aplicației) și `features.bot_user.display_name` (numele botului în canal). Dacă le schimbi, recreează aplicația din manifestul modificat.

---

## Pasul 2: Instalează aplicația și copiază tokenul

1. În meniul din stânga, deschide **OAuth & Permissions**
2. Apasă **Install to Workspace**
3. Confirmă cu **Allow**
4. Sus vei vedea **Bot User OAuth Token**, o valoare care începe cu `xoxb-`
5. Apasă **Copy** și pune valoarea în `.env` la `SLACK_BOT_TOKEN`

---

## Pasul 3: Creează canalul dedicat și invită botul

1. În Slack, creează un canal nou privat, de exemplu `#asistent` (recomandat privat, ca să fie doar al tău)
2. Deschide canalul și scrie mesajul: `/invite @numele-botului`
   (începe să tastezi `@` și numele botului apare în listă)
3. Botul apare acum ca membru al canalului

Botul vede **doar** canalul în care l-ai invitat. Nu are acces la restul workspace-ului.

---

## Pasul 4: Ia Channel ID

1. În canal, apasă pe numele canalului din partea de sus (bara cu titlul)
2. Se deschide o fereastră cu detalii; derulează până jos de tot
3. Vei vedea **Channel ID**, o valoare care începe cu `C` (ex. `C08AB12CD34`)
4. Apasă pe ea ca s-o copiezi și pune-o în `.env` la `SLACK_CHANNEL_ID`

---

## Pasul 5: Ia User ID (al tău)

1. Apasă pe avatarul tău (dreapta sus) și alege **Profile**
2. În panoul de profil, apasă pe cele trei puncte (**...**)
3. Alege **Copy member ID**, o valoare care începe cu `U`
4. Pune-o în `.env` la `SLACK_ALLOWED_USER`

Aceasta e valoarea care spune agentului că doar mesajele TALE trebuie procesate. Mesajele altcuiva din canal sunt ignorate.

---

## Pasul 6: Verifică

Fișierul `.env` ar trebui să arate așa (cu valorile tale reale):

```
SLACK_BOT_TOKEN=xoxb-1234567890-...
SLACK_CHANNEL_ID=C08AB12CD34
SLACK_ALLOWED_USER=U07ZZ99YY88
```

Încarcă valorile în shell și testează manual:

```bash
set -a; source .env; set +a
```

Scrie un mesaj în canal (ex. "salut"), apoi rulează:

```bash
bash .claude/skills/slack-bot/check-slack.sh
```

Ar trebui să vezi un rând JSON cu mesajul tău. Trimite un răspuns de test:

```bash
bash .claude/skills/slack-bot/send-slack.sh "$SLACK_CHANNEL_ID" "Merge!"
```

Dacă mesajul apare în canal, comunicarea funcționează.

---

## Probleme frecvente

| Simptom | Cauză probabilă | Rezolvare |
|---|---|---|
| `check-slack.sh` nu întoarce nimic | Prima rulare setează doar punctul de pornire | Trimite un mesaj NOU după prima rulare și încearcă din nou |
| Eroare `not_in_channel` | Botul nu e în canal | `/invite @numele-botului` în canal |
| Eroare `invalid_auth` | Token greșit sau incomplet | Recopiază `SLACK_BOT_TOKEN` (`xoxb-...`) din OAuth & Permissions |
| Eroare `channel_not_found` | Channel ID greșit | Recopiază Channel ID din detaliile canalului (Pasul 4) |
| Agentul răspunde la mesajele altcuiva | `SLACK_ALLOWED_USER` greșit | Verifică că e ID-ul tău (Pasul 5) |

---

## De ce polling și nu Socket Mode

Agentul rulează în tmux pe Mac-ul tău și verifică Slack la fiecare minut printr-un cron. Nu are nevoie să primească evenimente în timp real, deci nu folosește Socket Mode și nu deschide niciun port. Asta înseamnă:
- setup mai simplu (fără app-level token, fără event subscriptions)
- nimic expus în rețea
- funcționează în spatele oricărui firewall
