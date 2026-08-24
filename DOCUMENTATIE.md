# Ontwikkelaarsdocumentatie

Databank voor het opleidingsbeheer van Syntra MVL. PostgreSQL 16,
getest in pgAdmin 4.

- [1. Opbouw van de databank](#1-opbouw-van-de-databank)
- [2. Het datamodel](#2-het-datamodel)
- [3. Publiek versus afgeschermd](#3-publiek-versus-afgeschermd)
- [4. Views](#4-views)
- [5. Functies](#5-functies)
- [6. Triggers](#6-triggers)
- [7. Stored procedures](#7-stored-procedures)
- [8. Indexen](#8-indexen)
- [9. Referentiële integriteit](#9-referentiële-integriteit)
- [10. Backup en herstel](#10-backup-en-herstel)
- [11. Testen](#11-testen)
- [12. Mogelijke uitbreidingen](#12-mogelijke-uitbreidingen)

---

## 1. Opbouw van de databank

De scripts staan in `sql/` en moeten in volgorde draaien:

| Bestand | Inhoud |
|---|---|
| `00_start_hier.sql` | maakt de database aan (uitvoeren vanuit `postgres`) |
| `01_tabellen.sql` | 18 tabellen, sleutels, foreign keys, check-constraints |
| `02_indexen.sql` | indexen |
| `03_functies_en_triggers.sql` | 5 functies, 2 triggerfuncties, 6 triggers |
| `04_views.sql` | 6 publieke + 7 interne views |
| `05_stored_procedures.sql` | 15 stored procedures |
| `06_testdata.sql` | testdata |
| `07_rollen_en_rechten.sql` | rollen, rechten, kolombeveiliging |
| `08_testscript.sql` | test alles |

Voor de praktische kant in pgAdmin: zie [PGADMIN.md](PGADMIN.md).

Elk script begint met `DROP` of `TRUNCATE` en is dus herhaalbaar. Dat
betekent ook dat `01_tabellen.sql` bestaande data wist — niet zomaar op
productie draaien.

Alles staat in het schema `public`. Één schema houdt het overzichtelijk
in de Browser van pgAdmin en in de ERD-tool; het onderscheid tussen
publiek en afgeschermd wordt gemaakt met views en rechten (zie §3).

---

## 2. Het datamodel

Het diagram en de uitleg bij de modelleringskeuzes staan in
[ERD.md](ERD.md). De kern in het kort:

- **Catalogus**: `categorie` → `subcategorie` → `opleiding` → `module`,
  met `opleidingsvorm`, `niveau` en `campus` als referentietabellen.
- **Uitvoering**: `opleidingsperiode` is een concreet startmoment;
  `periode_module` plant de modules daarbinnen in;
  `periode_module_lesgever` koppelt de docenten.
- **Personen**: `persoon` met `cursist` en `lesgever` als rollen die
  dezelfde primaire sleutel delen.
- **Inschrijvingen**: `inschrijving` → `inschrijving_module` →
  `evaluatie`, plus `betaling` en `inschrijving_log`.

---

## 3. Publiek versus afgeschermd

Het onderscheid wordt in de databank zelf afgedwongen, niet in de
applicatie. Een fout in de website kan zo geen persoonsgegevens lekken.

### 3.1 Views als enige toegangspoort

Alles wat de website mag zien, zit in de views met prefix `vw_pub_`.
Alles wat intern is, zit in `vw_int_`.

Een view draait met de rechten van zijn eigenaar. De rol `syntra_web`
heeft daarom `SELECT` op de zes publieke views en op geen enkele tabel.
Dat is te controleren:

```sql
SET ROLE syntra_web;
SELECT COUNT(*) FROM vw_pub_opleiding;   -- 17
SELECT * FROM persoon;                   -- ERROR: permission denied for table persoon
SELECT * FROM vw_int_klaslijst;          -- ERROR: permission denied for view vw_int_klaslijst
RESET ROLE;
```

`vw_pub_lesgever` toont enkel de publieke bio, de foto en de
LinkedIn-link. Geen e-mail, geen telefoon, geen tarief, geen IBAN.

### 3.2 Kolombeveiliging

PostgreSQL laat toe rechten per kolom te geven. `syntra_medewerker`
krijgt de contactgegevens uit `persoon`, maar bewust **niet**
`rijksregisternr`. Van `lesgever` krijgt die rol de publieke kolommen,
maar niet `uurtarief`, `iban` of `ondernemingsnummer`. Die blijven
voorbehouden aan `syntra_admin`.

```sql
SET ROLE syntra_medewerker;
SELECT email FROM persoon LIMIT 1;             -- werkt
SELECT rijksregisternr FROM persoon LIMIT 1;   -- ERROR: permission denied
RESET ROLE;
```

Let op de volgorde in `07_rollen_en_rechten.sql`: een `GRANT SELECT ON
ALL TABLES` zet ook de gevoelige kolommen weer open. Daarom wordt dat
recht op `persoon` en `lesgever` daarna expliciet ingetrokken en
vervangen door een kolomrecht.

### 3.3 Versleutelde wachtwoorden

Wachtwoorden van cursisten staan versleuteld in
`cursist.wachtwoord_hash`, met `crypt()` en `gen_salt('bf')` uit
pgcrypto. Het wachtwoord zelf staat nergens in de databank. Controleren
bij het aanmelden gebeurt door het ingegeven wachtwoord met dezelfde
salt te versleutelen en te vergelijken:

```sql
SELECT wachtwoord_hash = crypt('Test1234!', wachtwoord_hash) AS juist
FROM   cursist WHERE cursist_id = 6;
```

### 3.4 De rollen

| Rol | Mag |
|---|---|
| `syntra_web` | `SELECT` op de zes `vw_pub_`-views. Verder niets. |
| `syntra_lesgever` | lesopdrachten, klaslijsten en resultaten lezen; evaluaties registreren. |
| `syntra_medewerker` | catalogus en inschrijvingen beheren; contactgegevens lezen; geen rijksregisternummers of IBAN's. |
| `syntra_admin` | alles. Erft `syntra_medewerker`. |

Het zijn groepsrollen zonder login. Per applicatie maak je een loginrol
aan:

```sql
CREATE ROLE web_app LOGIN PASSWORD '<geheim>';
GRANT syntra_web TO web_app;
```

`07_rollen_en_rechten.sql` maakt zelf al de loginrol
`website_gebruiker` aan om te kunnen testen.

---

## 4. Views

### Publiek (`vw_pub_`)

| View | Pagina op de site |
|---|---|
| `vw_pub_categorie` | `/nl/opleidingen` — de themakaarten met tellingen |
| `vw_pub_subcategorie` | `/nl/opleidingen/{categorie}` |
| `vw_pub_opleiding` | de opleidingskaartjes, met eerstvolgende start, prijs vanaf en locaties |
| `vw_pub_programma` | het blok "Programma" op een opleidingspagina |
| `vw_pub_startmoment` | het blok "Waar en wanneer?", met vrije plaatsen |
| `vw_pub_lesgever` | het publieke docentenprofiel |

Elke view geeft ook een kolom `url` terug die het paginapad opbouwt uit
de slugs, in hetzelfde formaat als de bestaande website.

### Intern (`vw_int_`)

| View | Gebruik |
|---|---|
| `vw_int_cursist` | cursistenfiche met contactgegevens en leeftijd |
| `vw_int_lesgever` | docentenfiche inclusief facturatiegegevens |
| `vw_int_klaslijst` | deelnemers per periode, met openstaand saldo |
| `vw_int_lesopdracht` | wie geeft welke module, waar, wanneer, voor hoeveel cursisten |
| `vw_int_resultaat` | resultaten per cursist en module, inclusief pogingen |
| `vw_int_bezetting` | bezettingsgraad en verwachte omzet per periode |
| `vw_int_openstaand` | openstaande betalingen |

---

## 5. Functies

| Functie | Geeft terug |
|---|---|
| `fn_aantal_ingeschreven(periode_id)` | aantal actieve inschrijvingen |
| `fn_vrije_plaatsen(periode_id)` | resterende plaatsen, nooit negatief |
| `fn_openstaand_saldo(inschrijving_id)` | te betalen min al betaald |
| `fn_module_geslaagd(inschrijving_module_id)` | `TRUE` bij vrijstelling of een geslaagde poging |
| `fn_leeftijd(geboortedatum)` | leeftijd in jaren |

```sql
SELECT code, fn_vrije_plaatsen(periode_id) AS vrij
FROM   opleidingsperiode;
```

---

## 6. Triggers

**`fn_zet_gewijzigd_op()`** — hangt als `BEFORE UPDATE` aan
`categorie`, `subcategorie`, `opleiding`, `opleidingsperiode` en
`persoon`. Zet `gewijzigd_op` op `now()`. Een trigger is hier
betrouwbaarder dan applicatiecode: ook een handmatige `UPDATE` in
pgAdmin wordt correct bijgehouden.

**`fn_log_inschrijving_status()`** — hangt als `AFTER INSERT OR UPDATE`
aan `inschrijving`. Schrijft elke statuswijziging naar
`inschrijving_log`, met de gebruiker die de wijziging deed. Zo is
achteraf aantoonbaar wanneer iemand geannuleerd heeft.

```sql
SELECT * FROM inschrijving_log ORDER BY log_id;
```

---

## 7. Stored procedures

Procedures roep je op met `CALL`. Ze werken met namen, codes en slugs in
plaats van met id's, en melden via `RAISE NOTICE` wat er gebeurd is —
in pgAdmin verschijnt dat in het tabblad **Messages**.

### Catalogus

```sql
CALL sp_categorie_toevoegen('Grafisch, IT en media', 'grafisch-it-en-media',
                            'Omschrijving...', 'https://.../beeld.jpg', 6);

CALL sp_subcategorie_toevoegen('grafisch-it-en-media',
                               'Data & software development',
                               'data-software-development');

CALL sp_opleiding_toevoegen('data-software-development', 'Python data developer',
                            'python-data-developer', 'avond', 'beginner');

CALL sp_module_toevoegen('python-data-developer', 'PY-DB', 'Databanken',
                         'Omschrijving...', 12, TRUE);

CALL sp_periode_toevoegen('python-data-developer', 'PDD-2028-GENT', '2028-2029',
                          'Campus Gent', DATE '2028-09-11', DATE '2029-06-22',
                          1075.00, 18);

CALL sp_module_plannen('PDD-2028-GENT', 'PY-DB', DATE '2029-01-24', DATE '2029-03-06');
CALL sp_lesgever_toewijzen('PDD-2028-GENT', 'PY-DB', 'wim.segers@syntra-mvl.be');
```

`sp_periode_toevoegen` plant meteen **alle** modules van de opleiding
in, over de volledige looptijd. Met `sp_module_plannen` verfijn je die
datums daarna per module.

`sp_module_toevoegen` bepaalt zelf de volgende `volgorde` als je er geen
meegeeft.

### Personen

```sql
CALL sp_cursist_toevoegen('Ella', 'Janssens', 'ella.janssens@example.be',
                          '+32 470 10 20 30', DATE '1995-03-12', '95031212345',
                          'Kerkstraat 12', '9000', 'Gent',
                          'Bachelor communicatiewetenschappen', 'Test1234!');

CALL sp_lesgever_toevoegen('Sofie', 'Maes', 'sofie.maes@syntra-mvl.be');
```

Beide hergebruiken een bestaande `persoon` als het e-mailadres al bekend
is. Iemand kan dus cursist én lesgever zijn zonder dubbele gegevens. Het
cursist- of lesgeversnummer wordt afgeleid uit het `persoon_id`
(`C00006`, `L0001`).

Het wachtwoord wordt versleuteld met `crypt()` voor het opgeslagen wordt.

### Inschrijvingen

```sql
CALL sp_inschrijven('ella.janssens@example.be', 'PDD-2026-GENT');
CALL sp_inschrijving_bevestigen(1);
CALL sp_vrijstelling_toekennen(1, 'PY-DB', 'Moduleattest 2024.');
CALL sp_evaluatie_registreren(1, 'PY-BASIS', 78, 'sofie.maes@syntra-mvl.be', 'Sterk werk.');
CALL sp_betaling_registreren(1, 1010.00, 'overschrijving', 'OVS-2026-0001');
CALL sp_inschrijving_annuleren(1, 'Cursist heeft afgezegd.');
```

`sp_inschrijven` is de meest inhoudelijke procedure. Ze:

1. vergrendelt de periode met `SELECT ... FOR UPDATE`, zodat twee
   gelijktijdige inschrijvingen de capaciteit niet kunnen overschrijden;
2. weigert een periode die niet op `gepland` of `open` staat;
3. weigert wanneer er geen vrije plaats meer is;
4. koppelt automatisch alle modules van de periode aan de inschrijving;
5. zet de periode op `volzet` zodra de laatste plaats bezet is.

`sp_inschrijving_annuleren` zet een volzette periode weer op `open`.

`sp_evaluatie_registreren` telt de poging zelf op: een tweede evaluatie
voor dezelfde module is automatisch poging 2.

`sp_betaling_registreren` weigert bedragen boven het openstaande saldo.

`sp_vrijstelling_toekennen` weigert modules die niet als vrijstelbaar
gemarkeerd zijn.

---

## 8. Indexen

`PRIMARY KEY` en `UNIQUE` krijgen automatisch een index. Een `FOREIGN
KEY` niet, terwijl elke join en elke `DELETE` op de oudertabel er wel
over loopt. Daarom staat er een index op elke foreign-keykolom, vaak
samengesteld met de kolom waarop gesorteerd wordt:

```sql
CREATE INDEX idx_subcategorie_categorie ON subcategorie (categorie_id, volgorde);
```

**Partiële indexen** voor de query's die de website het vaakst doet:

```sql
CREATE INDEX idx_periode_startdatum ON opleidingsperiode (startdatum)
    WHERE status IN ('gepland', 'open');
```

De index bevat dan alleen de rijen die er toe doen en blijft klein.

**Functionele indexen** voor hoofdletterongevoelig zoeken:
`idx_opleiding_naam` op `LOWER(naam)` en `uq_persoon_email_lower` op
`LOWER(email)`. Die laatste maakt e-mailadressen meteen uniek ongeacht
hoofdletters.

Met `EXPLAIN ANALYZE` bekijk je welk plan de planner kiest. Op deze
testset zal hij vaak nog een sequential scan kiezen — bij een paar
tientallen rijen is dat sneller dan een index. Dat is normaal en geen
teken dat de index verkeerd is.

---

## 9. Referentiële integriteit

### Delete-gedrag

| Relatie | `ON DELETE` | Waarom |
|---|---|---|
| `subcategorie → categorie` | `RESTRICT` | een categorie met inhoud mag niet verdwijnen |
| `opleiding → subcategorie` | `RESTRICT` | idem |
| `module → opleiding` | `CASCADE` | modules bestaan niet los van hun opleiding |
| `periode_module → opleidingsperiode` | `CASCADE` | de planning verdwijnt met de periode |
| `periode_module → module` | `RESTRICT` | een ingeplande module verwijderen is een fout |
| `cursist → persoon` | `CASCADE` | GDPR: één `DELETE` wist het volledige dossier |
| `inschrijving → cursist` | `RESTRICT` | een cursist met inschrijvingen wordt niet stil gewist |
| `evaluatie → inschrijving_module` | `CASCADE` | resultaten horen bij de inschrijving |
| `evaluatie → lesgever` | `SET NULL` | het resultaat blijft geldig als de docent vertrekt |

Alle foreign keys staan op `ON UPDATE CASCADE`.

### Check-constraints

- `opleidingsperiode`: `einddatum > startdatum`, `prijs >= 0`,
  `max_cursisten > 0`, `dagdeel` en `status` binnen een vaste lijst,
  `academiejaar` in het formaat `JJJJ-JJJJ`
- `evaluatie`: `score` tussen 0 en 100, `poging` tussen 1 en 3
- `persoon`: rijksregisternummer exact 11 cijfers, geboortedatum in het
  verleden, e-mailadres met een apenstaartje en een punt
- `lesgever`: `uit_dienst_op >= in_dienst_sinds`, `uurtarief >= 0`
- `campus`: Belgische postcode
- `betaling`: `bedrag > 0`, `methode` binnen een vaste lijst

### Unique-constraints

Slugs zijn uniek per niveau, `periode_module` kan een module maar één
keer in dezelfde periode plannen, en een cursist kan zich maar één keer
inschrijven voor dezelfde periode (`uq_inschrijving`).

Onderdeel 6 van `08_testscript.sql` test elk van deze constraints door
ze bewust te schenden en de fout op te vangen.

---

## 10. Backup en herstel

In `backup/` staan drie bestanden:

| Bestand | Wat |
|---|---|
| `syntra_opleidingen.dump` | pg_dump custom format — dit is de op te leveren backup |
| `syntra_opleidingen.sql` | dezelfde inhoud als leesbare SQL |
| `rollen.sql` | de rollen (die zitten niet in een database-backup) |

**Herstellen in pgAdmin**: maak een lege database aan, rechtsklik erop
en kies **Restore...**. Zie [PGADMIN.md](PGADMIN.md), §5.

**Herstellen op de commandoregel**:

```bash
createdb syntra_opleidingen
pg_restore -d syntra_opleidingen --no-owner backup/syntra_opleidingen.dump
psql -d syntra_opleidingen -f backup/rollen.sql
```

Rollen zijn objecten van de server, niet van de database. Ze zitten dus
niet in een `pg_dump` van één database. Draai op een nieuwe server eerst
`rollen.sql` of `07_rollen_en_rechten.sql`.

---

## 11. Testen

`08_testscript.sql` overloopt de volledige databank in negen delen:

1. de publieke views — wat de website ziet
2. de interne views — klaslijsten, bezetting, resultaten, saldo's
3. de functies
4. de stored procedures, van categorie tot betaling
5. de triggers
6. de constraints — elke test moet mislukken
7. de rechten — wat elke rol wel en niet mag
8. de versleutelde wachtwoorden
9. `EXPLAIN ANALYZE` op twee query's

Deel 4 draait in een transactie met een `ROLLBACK` op het einde, zodat de
testdata onaangeroerd blijft. Deel 6 vangt elke fout op in een DO-blok en
schrijft `OK - ...` of `FOUT: ...` naar het tabblad **Messages**.

Na afloop mag er in Messages geen enkele regel staan die met `FOUT:`
begint.

---

## 12. Mogelijke uitbreidingen

**Lessen en aanwezigheden.** De planning zit nu op moduleniveau
(`periode_module` met een start- en einddatum), niet op lesniveau. Voor
een echt lessenrooster voeg je een tabel `les` toe onder
`periode_module` (datum, beginuur, einduur, lokaal) en een tabel
`aanwezigheid` die naar `inschrijving_module` verwijst.

**Lokalen.** `campus` volstaat nu. Een tabel `lokaal` met capaciteit en
een `is_hybride`-vlag laat toe te controleren of een groep in het
toegewezen lokaal past.

**Facturatie.** `betaling` volstaat voor deze opdracht. Een echte
boekhoudkoppeling heeft facturen, creditnota's en btw-regimes nodig; je
houdt `betaling` dan als afletteringstabel en zet er een tabel `factuur`
boven.

**Meertaligheid.** Naam en omschrijving staan nu rechtstreeks in de
tabellen. Voor een Franstalige site is een tabel
`categorie_vertaling(categorie_id, taal, naam, omschrijving)` per
entiteit de minst ingrijpende uitbreiding.

**Zoekfunctie.** Voor het zoekveld op de website kan je een `tsvector`
en een GIN-index toevoegen op `opleiding`. Met de huidige aantallen is
`LOWER(naam) LIKE '%...%'` op de bestaande functionele index ruim
voldoende.
