# Gmail pentru agent

Cinci scripturi care dau agentului acces la Gmail: citire, etichetare, filtre native, mutare în coș. Sunt opționale, nimic din agent nu depinde de ele. Dacă nu le configurezi, pur și simplu nu există.

Nu au dependințe npm, folosesc doar Node standard. Ai nevoie de `node` instalat.

## Modelul de siguranță

Toate operațiile care schimbă ceva sunt **dry-run implicit**. Fără `--apply` sau `--delete` nu se întâmplă nimic, doar vezi ce s-ar întâmpla. Ștergerea e mutare în coș, reversibilă, nu ștergere permanentă.

Asta contează mai mult decât pare: un agent care rulează singur va greși într-o zi o interogare, iar diferența dintre "am mutat 400 de mailuri în coș" și "am șters definitiv 400 de mailuri" e diferența dintre o seară proastă și o pierdere.

## Setup, o singură dată

### 1. Credențiale Google Cloud

1. Intră pe [console.cloud.google.com](https://console.cloud.google.com), creează un proiect (sau folosește unul existent)
2. **APIs & Services -> Library**, caută **Gmail API**, apasă Enable
3. **APIs & Services -> OAuth consent screen**: tip **External**, completează numele appului și emailul, iar la **Test users** adaugă adresa ta de Gmail. Nu e nevoie de verificare, appul rămâne în modul Testing și îl folosești doar tu.
4. **APIs & Services -> Credentials -> Create Credentials -> OAuth client ID**, tip **Desktop app**
5. Descarcă JSON-ul și pune-l aici:

```bash
mkdir -p ~/.gmail-mcp
mv ~/Downloads/client_secret_*.json ~/.gmail-mcp/gcp-oauth.keys.json
```

### 2. Autorizare

```bash
node scripts/gmail-auth.mjs
```

Se deschide browserul, aprobi accesul, iar tokenul se salvează în `~/.gmail-mcp/credentials.json`. Scopurile cerute: `gmail.modify`, `gmail.compose`, `gmail.send`, `gmail.settings.basic`.

Tokenul se reîmprospătează singur după aceea. Refaci pasul doar dacă revoci accesul sau schimbi scopurile.

**Fișierele din `~/.gmail-mcp/` sunt secrete.** Stau în afara repo-ului, nu le comite și nu le pune într-un folder sincronizat public.

## Comenzi

```bash
# Citește un mesaj (headere + corp text)
node scripts/gmail-read.mjs --id <messageId>
node scripts/gmail-read.mjs --id <messageId> --links     # doar linkurile din corp

# Etichetează mesaje care se potrivesc unei interogări Gmail
node scripts/gmail-label.mjs --label "Nume" --query "from:cineva@exemplu.ro"           # dry-run
node scripts/gmail-label.mjs --label "Nume" --query "from:cineva@exemplu.ro" --apply   # creează eticheta și o aplică

# Filtre native Gmail (etichetează automat ce vine de acum înainte)
node scripts/gmail-filter.mjs --list
node scripts/gmail-filter.mjs --from "cineva@exemplu.ro" --label "Nume"           # dry-run
node scripts/gmail-filter.mjs --from "cineva@exemplu.ro" --label "Nume" --apply
node scripts/gmail-filter.mjs --delete <filterId>

# Coș (reversibil)
node scripts/gmail-trash.mjs --id <messageId>
node scripts/gmail-trash.mjs --query "older_than:1y from:newsletter@x.com"            # dry-run
node scripts/gmail-trash.mjs --query "older_than:1y from:newsletter@x.com" --delete
```

Interogările folosesc sintaxa de căutare Gmail: `from:`, `subject:`, `older_than:`, `has:attachment`, `-label:ceva` pentru excludere.

## Etichetare vs filtru

`gmail-label.mjs` lucrează pe mailurile care **există deja**. `gmail-filter.mjs` creează o regulă nativă Gmail care se aplică mailurilor **care vin de acum înainte**, fără ca agentul să fie pornit.

Combinația uzuală: filtru pentru viitor, etichetare o dată pentru arhiva existentă.

## Folosire de către agent

Adaugă în `TOOLS.md` ce ai configurat, ca agentul să știe că are Gmail. Un exemplu de task recurent, în `HEARTBEAT.md`:

```
- [ ] Verifică inboxul pentru ceva urgent: node scripts/gmail-read.mjs pe mesajele noi importante
```

Ține minte că fiecare astfel de linie costă la fiecare heartbeat. Pune în heartbeat doar ce chiar vrei verificat des.
