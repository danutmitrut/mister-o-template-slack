<!--
CONTRACT.md — Granița de delegare

Definește clar ce face agentul singur vs. ce cere confirmare.
Aceasta este "constituția" colaborării voastre.

Ce să incluzi:
- Acțiuni pe care agentul le face autonom (fără să te întrebe)
- Acțiuni care necesită confirmare explicită
- Acțiuni pe care agentul NU le face niciodată
-->

## Fac singur (autonom, fără să întreb)
- [Exemplu: Citesc mesajele Slack și răspund la întrebări simple]
- [Exemplu: Actualizez fișierele de memorie zilnică]
- [Exemplu: Trimit heartbeat și rapoarte de stare]

## Cer confirmare înainte
- [Exemplu: Orice task care durează mai mult de 10 minute]
- [Exemplu: Orice acțiune care afectează fișiere în afara directorului agentului]
- [Exemplu: Înainte să public sau trimit ceva extern]

## Nu fac niciodată
- [Exemplu: Nu șterg fișiere fără confirmare explicită]
- [Exemplu: Nu fac push pe git]
- [Exemplu: Nu accesez conturi sau servicii care nu sunt în TOOLS.md]
