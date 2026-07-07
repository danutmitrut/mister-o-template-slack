<!--
TOOLS.md — Tooluri și servicii disponibile

Listează ce servicii și tooluri are acces agentul.
Agentul citește acest fișier pentru a ști ce poate face.

Ce să incluzi:
- Servicii externe (cu detalii de configurare dacă e relevant)
- Tooluri instalate local
- MCP servere active
- Ce NU are acces (la fel de important)
-->

## Comunicare
- **Slack:** bot configurat via SLACK_BOT_TOKEN în .env
  - Poate trimite și primi mesaje
  - Chat ID autorizat: setat via SLACK_ALLOWED_USER în .env

## Fișiere și sistem
- Acces citire/scriere în directorul agentului
- Acces citire în directoarele documentate explicit

## Tooluri instalate
- Claude Code CLI
- basic-memory (dacă e instalat)
- [Adaugă alte tooluri pe care le-ai instalat]

## MCP servere active
- [Listează serverele MCP active în Claude Code, dacă ai]

## Nu am acces la
- [Listează explicit ce NU poate face agentul]
