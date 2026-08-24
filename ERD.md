# ERD — Syntra opleidingsbeheer

Dit diagram staat in Mermaid, zodat GitHub het rendert zonder dat je
iets moet openen. In pgAdmin haal je hetzelfde diagram op met
**rechtsklik op de database → ERD For Database** (zie
[PGADMIN.md](PGADMIN.md), §3).

---

## Overzicht

```mermaid
erDiagram
    CATEGORIE ||--o{ SUBCATEGORIE : bevat
    SUBCATEGORIE ||--o{ OPLEIDING : bevat
    OPLEIDINGSVORM ||--o{ OPLEIDING : typeert
    NIVEAU ||--o{ OPLEIDING : typeert
    OPLEIDING ||--o{ MODULE : "bestaat uit"
    OPLEIDING ||--o{ OPLEIDINGSPERIODE : "loopt in"
    CAMPUS ||--o{ OPLEIDINGSPERIODE : "gaat door op"
    OPLEIDINGSPERIODE ||--o{ PERIODE_MODULE : plant
    MODULE ||--o{ PERIODE_MODULE : "wordt gepland als"
    PERIODE_MODULE ||--o{ PERIODE_MODULE_LESGEVER : "gegeven door"
    LESGEVER ||--o{ PERIODE_MODULE_LESGEVER : geeft

    PERSOON ||--o| CURSIST : is
    PERSOON ||--o| LESGEVER : is

    CURSIST ||--o{ INSCHRIJVING : "schrijft in"
    OPLEIDINGSPERIODE ||--o{ INSCHRIJVING : ontvangt
    INSCHRIJVING ||--o{ INSCHRIJVING_MODULE : omvat
    PERIODE_MODULE ||--o{ INSCHRIJVING_MODULE : "gevolgd in"
    INSCHRIJVING_MODULE ||--o{ EVALUATIE : "beoordeeld in"
    LESGEVER ||--o{ EVALUATIE : registreert
    INSCHRIJVING ||--o{ BETALING : "betaald met"
    INSCHRIJVING ||--o{ INSCHRIJVING_LOG : logt

    CATEGORIE {
        int categorie_id PK
        varchar naam UK
        varchar slug UK
        varchar omschrijving
        varchar afbeelding_url
        smallint volgorde
        boolean gepubliceerd
        timestamp aangemaakt_op
        timestamp gewijzigd_op
    }
    SUBCATEGORIE {
        int subcategorie_id PK
        int categorie_id FK
        varchar naam
        varchar slug UK
        varchar omschrijving
        smallint volgorde
        boolean gepubliceerd
    }
    OPLEIDINGSVORM {
        varchar vorm_code PK
        varchar omschrijving UK
        smallint volgorde
    }
    NIVEAU {
        varchar niveau_code PK
        varchar omschrijving UK
        smallint volgorde
    }
    OPLEIDING {
        int opleiding_id PK
        int subcategorie_id FK
        varchar vorm_code FK
        varchar niveau_code FK
        varchar naam
        varchar slug UK
        varchar korte_omschrijving
        varchar lange_omschrijving
        varchar doelgroep
        decimal duur_in_jaren
        boolean ai_geintegreerd
        boolean nieuw
        boolean gepubliceerd
    }
    MODULE {
        int module_id PK
        int opleiding_id FK
        varchar code UK
        varchar naam
        varchar omschrijving
        smallint aantal_sessies
        boolean vrijstelbaar
        boolean eindproef
        smallint volgorde
    }
    CAMPUS {
        int campus_id PK
        varchar naam UK
        varchar adres
        char postcode
        varchar gemeente
        varchar telefoon
        varchar email
    }
    OPLEIDINGSPERIODE {
        int periode_id PK
        int opleiding_id FK
        int campus_id FK
        varchar code UK
        char academiejaar
        date startdatum
        date einddatum
        varchar dagdeel
        decimal prijs
        smallint max_cursisten
        date inschrijven_tot
        varchar status
        varchar lessenrooster_url
    }
    PERIODE_MODULE {
        int periode_module_id PK
        int periode_id FK
        int module_id FK
        smallint volgorde
        date startdatum
        date einddatum
    }
    PERIODE_MODULE_LESGEVER {
        int periode_module_id PK_FK
        int lesgever_id PK_FK
        varchar rol
        timestamp toegewezen_op
    }
    PERSOON {
        int persoon_id PK
        varchar voornaam
        varchar familienaam
        varchar email UK
        varchar telefoon
        char rijksregisternr "afgeschermd"
        date geboortedatum
        varchar adres
        varchar postcode
        varchar gemeente
        char land
    }
    CURSIST {
        int cursist_id PK_FK
        varchar cursistnummer UK
        varchar wachtwoord_hash "versleuteld"
        date dossier_sinds
        varchar hoogste_diploma
        boolean opleidingscheques
        boolean kmo_portefeuille
        varchar interne_notitie "afgeschermd"
        boolean actief
    }
    LESGEVER {
        int lesgever_id PK_FK
        varchar lesgevernummer UK
        varchar publieke_bio "publiek"
        varchar foto_url "publiek"
        varchar linkedin_url "publiek"
        boolean zichtbaar_op_web
        varchar ondernemingsnummer "afgeschermd"
        decimal uurtarief "afgeschermd"
        varchar iban "afgeschermd"
        date in_dienst_sinds
        date uit_dienst_op
    }
    INSCHRIJVING {
        int inschrijving_id PK
        int cursist_id FK
        int periode_id FK
        varchar status
        timestamp ingeschreven_op
        decimal te_betalen
        varchar korting
        varchar opmerking
    }
    INSCHRIJVING_MODULE {
        int inschrijving_module_id PK
        int inschrijving_id FK
        int periode_module_id FK
        boolean vrijstelling
        varchar vrijstelling_motivatie
    }
    EVALUATIE {
        int evaluatie_id PK
        int inschrijving_module_id FK
        date evaluatiedatum
        decimal score
        smallint poging
        varchar feedback
        int lesgever_id FK
    }
    BETALING {
        int betaling_id PK
        int inschrijving_id FK
        decimal bedrag
        date betaaldatum
        varchar methode
        varchar referentie UK
    }
    INSCHRIJVING_LOG {
        int log_id PK
        int inschrijving_id
        varchar oude_status
        varchar nieuwe_status
        timestamp gewijzigd_op
        varchar gewijzigd_door
    }
```

---

## Waarom het model er zo uitziet

### Categorie → subcategorie → opleiding

Drie aparte tabellen in plaats van één tabel die naar zichzelf verwijst.
De website heeft precies drie niveaus, elk met een eigen pagina-indeling
en een eigen URL-deel. Met drie tabellen blijven de foreign keys en de
query's eenvoudig, en kan je per niveau eigen kolommen bijhouden
(bijvoorbeeld een afbeelding per thema).

### Module en periode_module

Dit is de belangrijkste keuze in het model.

`module` beschrijft de **inhoud**: "Databanken, 12 sessies,
vrijstelbaar". Die hangt aan de opleiding en verandert niet per
academiejaar.

`periode_module` beschrijft de **uitvoering**: wanneer die module loopt
binnen één opleidingsperiode, en wie ze geeft.

Daardoor kunnen de twee opleidingsperiodes van Python data developer
(2026-2027 en 2027-2028) allebei dezelfde zeven modules bevatten, elk
met een eigen planning en eigen docenten, zonder dat de beschrijvingen
gedupliceerd worden. Zou je de datums rechtstreeks in `module` zetten,
dan moest je alle modules kopiëren per jaar — en dan loop je bij elke
tekstwijziging het risico dat de twee versies uit elkaar groeien.

### Persoon, cursist en lesgever

`cursist` en `lesgever` zijn geen aparte personen: het zijn **rollen**
die een persoon kan hebben. Ze delen daarom dezelfde primaire sleutel
als `persoon`. Iemand die eerst cursist was en later lesgever wordt,
heeft één rij in `persoon` en dus één set contactgegevens.

Dat is ook de plek waar het onderscheid publiek/afgeschermd gemaakt
wordt: alle direct identificerende gegevens staan in `persoon`, een
tabel waar de website geen enkel recht op heeft.

### inschrijving_module

Een inschrijving loopt niet automatisch over alle modules: er zijn
vrijstellingen. Door de koppeling expliciet te maken kan per cursist en
per module een vrijstelling of een resultaat bijgehouden worden.

### Evaluatie met poging

Een herkansing is een tweede rij, geen overschreven score. Zo blijft de
geschiedenis zichtbaar. Een `UNIQUE (inschrijving_module_id, poging)`
voorkomt dat dezelfde poging twee keer geregistreerd wordt, en een
`CHECK` beperkt het tot maximaal drie pogingen.

### inschrijving_log

Deze tabel heeft bewust **geen** foreign key naar `inschrijving`. Een
logboek moet blijven bestaan, ook als de rij waarover het gaat ooit
verdwijnt. De trigger `trg_inschrijving_log` vult hem automatisch bij
elke statuswijziging.
