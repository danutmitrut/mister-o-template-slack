# Upgrade pe un agent deja instalat

Dacă ai instalat agentul înainte de acest update, îl aduci la zi fără să reiei instalarea și fără să pierzi nimic din ce ai personalizat. Fișierele tale (`IDENTITY.md`, `SOUL.md`, `USER.md`, `CONTRACT.md`, `TOOLS.md`, memoria din `memory/`, `.env`) rămân neatinse.

Ca la instalare, lucrezi prin Claude Code. Deschide folderul agentului în VS Code, pornește Claude Code și dă-i prompturile de mai jos, pe rând.

## Ce aduce update-ul

**Listenerul de Slack.** Asta e motivul principal. Până acum agentul se trezea o dată pe minut ca să se uite dacă ai scris ceva, și la fiecare trezire își reîncărca tot contextul, chiar dacă nu găsea nimic. Peste 500 de treziri pe zi, aproape toate degeaba. De acum verificarea se face în fundal, gratuit, iar agentul e trezit doar când chiar îi scrii.

**Trei skills opționale:** rezumat de seară, curățenie desktop, escaladare pe model puternic pentru taskuri grele de sinteză.

**Acces Gmail opțional:** citire, etichetare, filtre, coș. Cere o configurare Google separată, vezi `docs/GMAIL.md`.

---

## Pasul 1: adu codul nou

Lipește în Claude Code:

```
Adu la zi codul agentului din repo-ul de origine, fără să-mi pierzi fișierele personalizate.

Fă exact așa:
1. Verifică dacă am modificări nesalvate (git status). Dacă am, salvează-le într-un commit local înainte de orice, ca să nu se piardă.
2. Adu ultima versiune: git pull origin main
3. Dacă apar conflicte, rezolvă-le păstrând conținutul MEU în IDENTITY.md, SOUL.md, USER.md, CONTRACT.md, TOOLS.md, MEMORY.md, HEARTBEAT.md și memory/, și luând versiunea nouă în scripts/, tests/, .claude/skills/ și docs/.
4. La final spune-mi ce s-a schimbat și dacă a fost vreun conflict.
```

Dacă nu ai folosit git la instalare, spune-i în schimb: *"Am instalat agentul copiind fișierele, nu prin git. Ajută-mă să aduc doar fișierele noi din repo, fără să atingi personalizările mele."*

## Pasul 2: pornește listenerul

```
Pornește listenerul de Slack al agentului:

1. Rulează: bash scripts/generate-slack-listener-launchd.sh
2. Încarcă-l: launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.my-agent-slack.plist
3. Așteaptă 15 secunde și verifică: bash scripts/slack-listener-status.sh
4. Trebuie să scrie VIU. Dacă scrie MORT, uită-te în ~/.agent-logs/slack-listener.log și spune-mi ce găsești acolo.
```

Cauzele obișnuite pentru MORT sunt o valoare lipsă în `.env` sau botul care nu e membru în canal.

## Pasul 3: treci cronul de comunicare pe plasă de siguranță

Aici se face economia. Dacă sari peste pasul ăsta, agentul continuă să se trezească la fiecare minut și listenerul nu-ți folosește la nimic.

```
Actualizează cronul de comunicare din config.json ca să nu mai fie calea principală de mesaje, ci plasa de siguranță de o dată pe oră, exact ca în versiunea nouă din repo. Păstrează celelalte cronuri ale mele așa cum sunt. Apoi repornește agentul ca să încarce configurația nouă și confirmă-mi că a pornit.
```

## Pasul 4: verifică

Scrie-i agentului un mesaj pe Slack. Trebuie să răspundă în câteva secunde, nu într-un minut.

Apoi, ca să fii sigur că totul e în regulă:

```
Rulează suita de teste (bash tests/run.sh) și spune-mi dacă e totul verde.
```

---

## Skills opționale

Nu se activează singure. Cere-i-le doar dacă le vrei.

**Rezumat de seară pe Slack:**
```
Activează-mi skill-ul reflectie-zilnica: adaugă cronul de seară în config.json conform instrucțiunilor din .claude/skills/reflectie-zilnica/SKILL.md, la ora 19:00, și repornește agentul.
```

**Curățenie desktop:**
```
Explică-mi ce face skill-ul desktop-cleanup, apoi rulează-l o dată în dry-run (python3 scripts/desktop-cleanup.py --dry-run) și arată-mi raportul. Nu muta nimic până nu-ți spun eu.
```
Rămâne pe `dry-run` până îi spui explicit să treacă pe `apply`. Regulile sunt în `desktop-cleanup-rules.json` și le poți edita.

**Gmail:** citește întâi `docs/GMAIL.md`, cere o configurare Google separată.

---

## Dacă vrei să dai înapoi

Listenerul se oprește fără să strice nimic altceva:

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.my-agent-slack.plist
```

Agentul revine automat la verificare directă, iar dacă vrei și viteza de dinainte, pune cronul de comunicare înapoi la `1m` în `config.json` și repornește-l.
