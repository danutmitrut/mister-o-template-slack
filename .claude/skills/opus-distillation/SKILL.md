---
name: opus-distillation
description: "Escaladează un task greu de sinteză sau distilare către un subagent pe model puternic (Opus), rămânând tu coordonator. Folosește când: un transcript sau un set de fișiere depășește pragurile de mai jos, sau când userul cere explicit calitate maximă."
---

# /opus-distillation, distilare cu subagent pe model puternic

Un agent care rulează 24/7 stă pe un model ieftin, ca să fie sustenabil. Asta e corect pentru munca de rutină și insuficient pentru sinteza grea. Skill-ul rezolvă tensiunea: rămâi tu coordonator pe modelul ieftin și dai doar bucata grea unui subagent pe Opus.

## Când se aplică

Lansează subagent Opus dacă ORICARE din condițiile de mai jos e adevărată:

| Condiție | Prag |
|----------|------|
| Fișier transcript sau document | > 400 linii |
| Task de sinteză multi-fișier | > 3 fișiere simultan |
| Analiză tematică profundă | nuanțe dense, unde parafraza superficială strică rezultatul |
| Userul cere explicit calitate maximă | oricând |

Sub prag (task mecanic, inventar, redenumiri, extras de linkuri) rămâi pe modelul curent. Escaladarea costă, folosește-o unde se vede diferența.

## Protocol de lansare

1. **Citește sursa tu** cu Read tool, ca să verifici lungimea și tipul conținutului. Nu escalada pe presupuneri.
2. **Dacă pragul e atins**, lansează subagentul:

```
Agent(
  description: "Distilare: [titlu scurt]",
  subagent_type: "general-purpose",
  model: "opus",
  prompt: <vezi structura mai jos>
)
```

3. **Primești rezultatul** de la subagent, ca text structurat.
4. **Verifici și salvezi tu**: subagentul produce conținut, tu decizi unde ajunge și confirmi că a ajuns.

## Structura promptului pentru subagent

Subagentul pornește fără contextul tău, deci promptul trebuie să fie autonom. Include:

- **Rolul**: ce fel de specialist e nevoie (ex: "distilezi transcripturi de întâlniri în note acționabile")
- **Task-ul**: ce anume trebuie produs, într-o singură propoziție
- **Formatul de ieșire**: exact, cu titluri și secțiuni. Un format vag întoarce text vag.
- **Regulile**: constrângeri care contează (lungime, ce să evite, ce e obligatoriu)
- **Conținutul sursă**: textul integral, nu un rezumat al lui

Exemplu de format cerut, adaptabil:

```
## Despre ce e
[2-3 propoziții: ce problemă sau întrebare adresează sursa]

## Idei-cheie
- [5-10 idei, specifice și dense, nu parafrazări vagi]

## Legături
[Ce teme din alte materiale ating subiectul]

## Sursă
Fișier: [nume] ([N] linii)
```

## Regulă critică post-creare

**Obligatoriu după orice scriere de fișier:** listează folderul destinație și verifică faptic numele fișierului de pe disc. macOS rescrie unele caractere în numele de fișier (`:` devine `-`), iar o referință construită din titlul intenționat, nu din numele real, duce la o legătură moartă.

## Logging

După finalizare, loghează în `memory/{azi}.md`:
```
- Distilare via Opus: "[titlu]" ([N] linii sursă)
```
