# Instalare prin Claude Code (fără terminal)

Acest ghid e pentru tine, clientul. Nu scrii comenzi și nu atingi terminalul. Îi dai lui Claude Code din VS Code instrucțiuni în limbaj normal, iar el face treaba. Singurele lucruri pe care le faci cu mâna sunt câteva click-uri în Slack (în browser) și în VS Code.

Prompturile de mai jos le copiezi și le lipești în panoul de chat Claude Code, unul câte unul.

---

## De ce ai nevoie

- Un Mac (rularea permanentă 24/7 folosește launchd, care există doar pe macOS)
- VS Code cu Claude Code, autentificat (îl folosești deja)
- Un cont Slack unde ai voie să instalezi o aplicație

Nu ai nevoie de altceva. Dacă lipsește ceva mărunt pe calculator (de exemplu tmux sau jq), Claude Code îl instalează singur când ajunge acolo, întrebându-te întâi.

---

## Pasul 1: adu proiectul pe calculator

Deschide Claude Code în VS Code (poate fi orice folder deocamdată, de exemplu Documents) și lipește:

```
Clonează repository-ul https://github.com/danutmitrut/mister-o-template-slack în folderul acesta și spune-mi când e gata.
```

După ce Claude Code termină, deschizi folderul nou în VS Code: meniul File, apoi Open Folder, alegi `mister-o-template-slack`. Pornești o conversație nouă cu Claude Code în folderul ăsta (așa are acces la instrucțiunile proiectului).

---

## Pasul 2: fă aplicația Slack

Asta e singura parte pe care Claude Code nu o poate face în locul tău, pentru că sunt click-uri într-un site (Slack). Dar te ghidează pas cu pas. Lipește:

```
Ghidează-mă pas cu pas să creez aplicația Slack pentru acest agent, pe baza fișierului slack-app-manifest.json. Spune-mi exact ce click-uri să fac și ce să copiez.
```

La final vei avea trei valori, pe care i le dai lui Claude Code în chat când ți le cere:

- tokenul botului (începe cu `xoxb-`)
- Channel ID-ul canalului dedicat (începe cu `C`)
- User ID-ul tău din Slack (începe cu `U`)

Pașii compleți, cu poze de unde se apasă, sunt în `docs/SLACK-SETUP.md`.

---

## Pasul 3: pornește instalarea automată

Acum Claude Code face restul singur. Lipește:

```
/onboarding
```

De aici te întreabă lucruri simple, pe rând: cum vrei să se numească agentul, ce personalitate să aibă, câteva date despre tine, ce vrei să verifice periodic. Din răspunsurile tale scrie singur toate fișierele agentului.

Tot el pune tokenurile Slack în fișierul de configurare, setează pornirea automată (ca agentul să ruleze 24/7 și să se repornească singur) și face un test scurt ca să confirme că totul merge. Tu doar răspunzi la întrebări.

---

## Pasul 4: verifică

Când Claude Code spune că a terminat, lipește:

```
Verifică dacă agentul rulează și trimite-mi un mesaj de test pe Slack.
```

Apoi scrie-i tu înapoi ceva în canalul Slack dedicat. Ar trebui să primești răspuns în cel mult un minut.

---

## Ce ai obținut

Un asistent personal care rulează permanent pe Mac-ul tău, cu care vorbești dintr-un canal Slack. Se repornește singur din timp în timp ca să rămână proaspăt, supraviețuiește închiderii ferestrei VS Code și pornește din nou după ce repornești Mac-ul.

Un singur lucru de reținut: la sfârșit Claude Code îți va recomanda să treci agentul pe modelul `sonnet`. Pentru un asistent care verifică Slack în fiecare minut, e alegerea corectă (e rapid și nu consumă credite degeaba). Acceptă recomandarea.

Dacă vrei răspuns instantaneu în loc de până la un minut, există o variantă avansată în `slack-socket-bridge/`, dar nu e necesară pentru început.
