# Syntra MVL — databank opleidingsbeheer

PostgreSQL-databank voor het beheren van het opleidingsaanbod van Syntra
MVL: categorieën, opleidingen, modules, opleidingsperiodes, cursisten,
lesgevers, inschrijvingen, resultaten en betalingen.

Opdracht module Databanken. Gebouwd en getest met PostgreSQL 16 en
pgAdmin 4.

---

## Aan de slag

In pgAdmin 4, in deze volgorde:

1. Open **Databases → postgres → Query Tool** en voer
   `sql/00_start_hier.sql` uit. Dat maakt de database aan.
2. Rechtsklik op **Databases → Refresh**, klik `syntra_opleidingen` aan
   en open een nieuwe Query Tool.
3. Voer daarin `01` tot en met `08` uit, één voor één. Elk script
   eindigt met een controlequery, zodat je meteen ziet dat het gelukt is.

De volledige uitleg — inclusief het ERD in pgAdmin openen, backups maken
en git gebruiken naast pgAdmin — staat in
**[docs/PGADMIN.md](docs/PGADMIN.md)**.

Liever herstellen uit de backup dan alles opnieuw opbouwen:

```bash
createdb syntra_opleidingen
pg_restore -d syntra_opleidingen --no-owner backup/syntra_opleidingen.dump
psql -d syntra_opleidingen -f backup/rollen.sql
```

---

## Inhoud

```
sql/
  00_start_hier.sql            maakt de database aan
  01_tabellen.sql              18 tabellen, sleutels en constraints
  02_indexen.sql               indexen
  03_functies_en_triggers.sql  5 functies, 6 triggers
  04_views.sql                 6 publieke + 7 interne views
  05_stored_procedures.sql     15 stored procedures
  06_testdata.sql              testdata
  07_rollen_en_rechten.sql     rollen, rechten, kolombeveiliging
  08_testscript.sql            test alles

docs/
  DOCUMENTATIE.md              ontwikkelaarsdocumentatie
  ERD.md                       diagram + uitleg bij de keuzes
  PGADMIN.md                   praktische gids voor pgAdmin 4

backup/
  syntra_opleidingen.dump      pg_dump custom format
  syntra_opleidingen.sql       dezelfde backup als leesbare SQL
  rollen.sql                   de rollen (zitten niet in een db-backup)
```

---

## Wat er in zit

| Vereiste uit de opdracht | Waar |
|---|---|
| Categorieën van `/nl/opleidingen` | 16 categorieën, `06_testdata.sql` §2 |
| Subcategorieën van *Grafisch, IT en media* | 7 subcategorieën, §3 |
| Opleidingen in *Data & software development* | 17 opleidingen, §4 |
| 2 opleidingsperiodes van *python-developer* met alle modules | `PDD-2026-GENT` en `PDD-2027-GENT`, elk met de 7 modules, §5–7 |
| Cursisten, lesgevers en contactgegevens | `persoon` met `cursist` en `lesgever` als rollen, §8–9 |
| Onderscheid publiek / afgeschermd | views, rollen en kolomrechten — `07_rollen_en_rechten.sql` |
| Views voor de website | 6 views met prefix `vw_pub_` |
| Testdata | `06_testdata.sql` |
| Indexen en referentiële integriteit | `02_indexen.sql`, `01_tabellen.sql` |
| Stored procedures | 15 procedures in `05_stored_procedures.sql` |

Daarbovenop: 5 functies, 6 triggers (waaronder een logboek van
statuswijzigingen), versleutelde wachtwoorden met pgcrypto, en een
testscript dat de constraints en de rechten controleert.

---

## Publiek versus afgeschermd

Het onderscheid zit in de databank zelf, niet in de applicatie:

- **Views.** De website leest alleen de zes `vw_pub_`-views. Die
  bevatten geen enkel persoonsgegeven van een cursist.
- **Rollen.** `syntra_web` heeft `SELECT` op die zes views en op geen
  enkele tabel. Een view draait met de rechten van zijn eigenaar, dus dat
  volstaat.
- **Kolomrechten.** `syntra_medewerker` mag contactgegevens lezen, maar
  niet `rijksregisternr`, `iban`, `ondernemingsnummer` of `uurtarief`.
- **Versleuteling.** Wachtwoorden staan gehasht met `crypt()` uit
  pgcrypto.

Te controleren in `08_testscript.sql`, deel 7:

```sql
SET ROLE syntra_web;
SELECT COUNT(*) FROM vw_pub_opleiding;   -- 17
SELECT * FROM persoon;                   -- ERROR: permission denied for table persoon
RESET ROLE;
```

---

## Over de gegevens

De catalogusgegevens komen van syntra-mvl.be, geraadpleegd in augustus
2026. De opleiding "python-developer" uit de opdracht staat op de site
als **Python data developer**; de zeven modules en hun beschrijvingen
komen van die pagina.

De overzichtspagina van *Data & software development* toont ook
opleidingen die volgens hun eigen URL elders thuishoren: UX Designer
onder *Grafische vormgeving*, Netwerkbeheerder onder *Hardware &
telecom*, en de cybersecurity-opleidingen deels onder *Veiligheid &
preventie → Security*. In de databank staan die bij hun eigen
subcategorie, zodat de navigatie klopt.

**Alle personen, inschrijvingen, resultaten en betalingen zijn
verzonnen.** Ook de rijksregisternummers, IBAN's en wachtwoorden in de
testdata zijn fictief en horen bij niemand.
