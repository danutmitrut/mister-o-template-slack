---
name: desktop-cleanup
description: "Curățenie automată desktop după criterii editabile. Folosește când: rularea programată de seară, sau când userul cere /desktop-cleanup. Sortează fișierele loose în foldere (Documente zilnice/Sheets/Docx/PDF/IMAGINE/AUDIO/ARCHIVE), mută video în iCloud, soft-delete screenshots."
---

# /desktop-cleanup, curățenie desktop

Face ordine pe desktopul userului după regulile din `desktop-cleanup-rules.json`.

## Model de siguranță (NON-NEGOCIABIL)

- Acționează DOAR pe fișiere loose top-level din desktop. **Folderele nu se ating niciodată** (se trec într-o evidență, decizie task-cu-task).
- Screenshots = **soft-delete**: mutate într-un coș datat (`~/.desktop-cleanup-trash/YYYY-MM-DD/`), golit automat abia după `trash_retention_days` (implicit 30, sursa de adevăr e `desktop-cleanup-rules.json`, nu acest text). Niciodată hard-delete.
- Tipuri necunoscute = neatinse.
- `mode` în rules: `dry-run` raportează fără să mute; `apply` mută efectiv. **Implicit e `dry-run`.** Treci pe `apply` DOAR după ce userul validează un raport dry-run.

## Pași

1. Rulează: `python3 scripts/desktop-cleanup.py`
   - Respectă `mode` din `desktop-cleanup-rules.json`.
   - Forțare: `--dry-run` sau `--apply`.
2. Citește summary-ul din stdout (acțiuni pe categorii, foldere neatinse, skip, coș golit).
3. Dacă `mode=dry-run`: trimite raportul pe Slack userului și cere validare înainte de a trece pe `apply`.
4. Dacă `mode=apply`: scriptul face auto-verificare post-rulare și emite în stdout/log un verdict **VERIFICARE: CURAT** sau **ANOMALII** (cu lista). Trimite pe Slack un raport care include OBLIGATORIU verdictul de verificare + rezumatul pe categorii + ce s-a golit din coș. Dacă sunt ANOMALII, listează-le clar și nu declara succes. Logul detaliat e în `~/.desktop-cleanup-logs/`.
5. Loghează în `memory/{azi}.md` (ce s-a rulat, mode, verdict verificare, rezumat).

## Reguli (editabile de user)

Toate criteriile sunt în `desktop-cleanup-rules.json` (root repo): buckets pe extensie, pattern-uri screenshot, căi, retenție coș, mode. Se pot schimba oricând fără să atingi codul. Căile acceptă `~`.

## Programare (opțional)

Nu e activ implicit. Dacă userul îl vrea automat seara, adaugă în `config.json`:

```json
{
  "cron": "45 19 * * *",
  "prompt": "Rulează skill-ul desktop-cleanup: execută python3 scripts/desktop-cleanup.py, citește summary-ul din stdout (inclusiv verdictul VERIFICARE) și acționează conform .claude/skills/desktop-cleanup/SKILL.md. Trimite pe Slack un raport care include OBLIGATORIU verdictul de verificare + rezumatul pe categorii; dacă sunt ANOMALII listează-le și nu declara succes. Loghează în memory/{azi}.md."
}
```

## Note

- Coliziuni de nume la destinație: se adaugă " (2)", " (3)" etc.
- Video → `~/Library/Mobile Documents/com~apple~CloudDocs/FROM DESKTOP/VIDEOS` (iCloud), configurabil în reguli.
- Evidența folderelor de lucru: `~/.desktop-cleanup-folders.md` (regenerată la fiecare apply).
