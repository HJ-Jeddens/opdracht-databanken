# Werken met dit project in pgAdmin 4

Alles in deze repo is geschreven om rechtstreeks in de Query Tool van
pgAdmin 4 te draaien. Er staan geen psql-commando's in de scripts (geen
`\i`, `\echo` of `\set`), dus je kan elk bestand gewoon openen en
uitvoeren met **F5**.

---

## 1. De databank opbouwen

**Stap 1 — de database aanmaken.**
Klap in de Browser links je server open, klik op **Databases → postgres**
en open **Tools → Query Tool**. Open daar `sql/00_start_hier.sql` en voer
het uit. Dit moet vanuit `postgres` gebeuren: je kan geen database
aanmaken vanuit de database waarin je op dat moment zit.

Rechtsklik daarna op **Databases → Refresh**. `syntra_opleidingen`
verschijnt in de lijst.

**Stap 2 — de rest.**
Klik `syntra_opleidingen` aan en open een **nieuwe** Query Tool. Let op
de titelbalk van het tabblad: daar staat op welke database je verbonden
bent. Voer nu in volgorde uit:

| Bestand | Wat het doet | Duurt |
|---|---|---|
| `01_tabellen.sql` | 18 tabellen met sleutels en constraints | < 1 s |
| `02_indexen.sql` | de indexen | < 1 s |
| `03_functies_en_triggers.sql` | 5 functies, 6 triggers | < 1 s |
| `04_views.sql` | 6 publieke + 7 interne views | < 1 s |
| `05_stored_procedures.sql` | 15 stored procedures | < 1 s |
| `06_testdata.sql` | de testdata | ± 1 s |
| `07_rollen_en_rechten.sql` | rollen en rechten | < 1 s |
| `08_testscript.sql` | test alles | ± 2 s |

Elk script eindigt met een controlequery, zodat je meteen ziet dat het
gelukt is.

Alle scripts zijn herhaalbaar: ze beginnen met `DROP` of `TRUNCATE`. Je
kan dus opnieuw beginnen zonder de database te hoeven verwijderen.

---

## 2. De bestanden vlot openen

pgAdmin heeft standaard een eigen opslagmap. Om de bestanden uit deze
repo te zien, wijs je die map aan:

**File → Preferences → Paths → Binary paths / Storage** — bij
*Storage → Storage Directory* vul je het pad naar de repo in,
bijvoorbeeld `C:\projecten\syntra-db`. Herstart pgAdmin.

Daarna opent het mapicoontje in de Query Tool meteen in je projectmap.

Twee dingen die veel tijd besparen:

- **Meerdere Query Tool-tabbladen tegelijk.** Open er een per script en
  wissel ertussen. Handig om `08_testscript.sql` open te houden terwijl
  je iets aanpast in `04_views.sql`.
- **Een selectie uitvoeren.** Selecteer een paar regels en druk op F5.
  pgAdmin voert dan alleen die selectie uit, niet het hele bestand. Zo
  test je één query of één `CALL` zonder de rest opnieuw te draaien.

---

## 3. Het ERD in pgAdmin bekijken

pgAdmin 4 heeft sinds versie 6 een ingebouwde ERD-tool.

1. Rechtsklik op de database **syntra_opleidingen**.
2. Kies **ERD For Database**.
3. pgAdmin leest de foreign keys uit en tekent het diagram.

Daarna:

- **Auto-align** (het icoontje met de vier pijltjes) legt de tabellen
  netjes uit. Handmatig verschuiven kan ook.
- **Download image** exporteert het diagram als PNG.
- **Save** bewaart het als `.pgerd`-bestand. Zet dat in `docs/` en je
  collega kan later exact dezelfde lay-out openen.

In `docs/ERD.md` staat hetzelfde diagram in tekstvorm, met uitleg bij de
keuzes. Dat rendert vanzelf op GitHub, zodat de docent het diagram ziet
zonder pgAdmin te moeten openen.

Werkt de ERD-tool niet, dan is de meest voorkomende oorzaak een oude
pgAdmin-versie. Controleer via **Help → About**; versie 6 of hoger is
nodig.

---

## 4. Git en pgAdmin

**pgAdmin 4 heeft geen git-integratie.** Er is geen commit- of
push-knop, en die komt er ook niet: pgAdmin is een databankbeheerder,
geen editor met versiebeheer.

De praktische aanpak is de mappen te laten overlappen:

1. Zet je git-repo lokaal, bijvoorbeeld `C:\projecten\syntra-db`.
2. Wijs de *Storage Directory* van pgAdmin naar diezelfde map (zie §2).
3. Bewerk en voer de scripts uit in pgAdmin.
4. Commit en push met een van deze:
   - **GitHub Desktop** — grafisch, zonder commandoregel;
   - **VS Code** — heeft git ingebouwd, en met de extensie
     *PostgreSQL* kan je er ook query's mee uitvoeren;
   - de **commandoregel**: `git add . && git commit -m "..." && git push`.

pgAdmin schrijft naar dezelfde bestanden, dus je wijzigingen staan
meteen klaar om te committen.

Twee kleine aandachtspunten:

- pgAdmin maakt soms back-upbestanden met een tilde. Die staan in
  `.gitignore`.
- Commit geen `.dump`-bestanden die je zelf lokaal maakt met andere
  data. De backup in `backup/` hoort er wel bij: dat is de op te leveren
  versie.

---

## 5. Backup maken vanuit pgAdmin

Rechtsklik op de database → **Backup...**

- *Filename*: `backup/syntra_opleidingen.dump`
- *Format*: **Custom** (gecomprimeerd, en je kan er selectief uit
  herstellen)
- Tabblad *Data Options*: laat **Blobs** en **Pre-data / Data /
  Post-data** aanstaan

Voor een leesbare versie die je in git kan vergelijken, maak je
daarnaast een export met *Format: Plain*.

**Werkt de knop niet?** Dan kent pgAdmin het pad naar `pg_dump` niet:
**File → Preferences → Paths → Binary paths**, en vul daar de `bin`-map
van je PostgreSQL-installatie in, bijvoorbeeld
`C:\Program Files\PostgreSQL\16\bin`.

**Herstellen** gaat omgekeerd: maak een lege database aan, rechtsklik
erop, kies **Restore...** en wijs het `.dump`-bestand aan.

Let op: rollen bestaan op serverniveau, niet in de database. Ze zitten
dus **niet** in de backup. Draai op een nieuwe server eerst
`07_rollen_en_rechten.sql`, of gebruik `backup/rollen.sql`.

---

## 6. Als iets misloopt

| Melding | Oorzaak |
|---|---|
| `CREATE DATABASE cannot run inside a transaction block` | Je voert `00_start_hier.sql` uit in een Query Tool waar een transactie openstaat. Klik op het icoontje **Commit**, of open een nieuw tabblad. |
| `database "syntra_opleidingen" is being accessed by other users` | Er staat nog een Query Tool open op die database. Sluit die tabbladen en probeer opnieuw. |
| `relation "categorie" does not exist` | Je bent verbonden met de verkeerde database. Kijk in de titelbalk van het tabblad. |
| `permission denied for table persoon` | Je zit nog in een `SET ROLE` uit `08_testscript.sql`. Voer `RESET ROLE;` uit. |
| `extension "pgcrypto" is not available` | De contrib-pakketten ontbreken. Op Windows en macOS zitten die standaard in de installer; op Linux installeer je `postgresql-contrib`. |
