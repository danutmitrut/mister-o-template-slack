---
name: reflectie-zilnica
description: "Reflecție zilnică: sintetizează ziua din memoria zilnică și trimite un rezumat pe Slack. Folosește când: rularea programată de seară, sau când userul cere /reflectie."
---

# /reflectie, reflecție zilnică

Rulează seara (programat sau la cerere) pentru a sintetiza ziua și a trimite un raport pe Slack.

## Pași

1. **Citește memoria zilei**
   - Deschide `memory/{azi}.md` (ex: `memory/2026-05-11.md`)
   - Dacă nu există, menționează că ziua a fost fără activitate înregistrată

2. **Sintetizează**
   Din ce ai citit, extrage:
   - **Ce s-a realizat azi**, taskuri completate, decizii luate, livrabile
   - **Ce a fost notabil**, mesaje importante, conversații, surprize
   - **Ce rămâne deschis**, taskuri pending, așteptări, decizii neluate
   - **Reminder mâine**, events din calendar sau follow-up-uri urgente

3. **Formatează mesajul**
   ```
   Reflecție zilnică {data}

   Realizat:
   • [bullet 1]
   • [bullet 2]

   Notabil:
   • [bullet]

   Deschis:
   • [bullet]

   Mâine:
   • [reminder calendar sau follow-up]
   ```
   - Scurt și dens, maxim 15 bullets total
   - Onest: dacă ziua a fost liniștită, spune asta, nu umfla raportul

4. **Trimite pe Slack**
   ```bash
   bash .claude/skills/slack-bot/send-slack.sh "$SLACK_CHANNEL_ID" "<mesaj>"
   ```

5. **Salvează reflecția în memoria zilei**
   Adaugă o secțiune `## Reflecție zilnică` la sfârșitul fișierului `memory/{azi}.md` cu un rezumat de 2-3 rânduri.

## Programare (opțional)

Nu e activ implicit. Dacă userul îl vrea automat, adaugă în `config.json`:

```json
{
  "cron": "0 19 * * *",
  "prompt": "Rulează skill-ul reflectie-zilnica: citește memory/{azi}.md, sintetizează ziua (realizări, notabil, pending, mâine) și trimite rezumatul pe Slack."
}
```
