/* =====================================================================
   01_tabellen.sql
   Tabellen, primaire sleutels, foreign keys en check-constraints.

   Verbind met de database "syntra_opleidingen" voor je dit uitvoert.

   Volgorde van de tabellen:
     1. catalogus     - wat op de website getoond wordt
     2. personen      - cursisten en lesgevers
     3. inschrijvingen- inschrijvingen, resultaten en betalingen
   ===================================================================== */

-- pgcrypto gebruiken we later om wachtwoorden versleuteld te bewaren.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Alles opkuisen zodat dit script herhaalbaar is.
-- CASCADE ruimt meteen de views en foreign keys op die eraan hangen.
DROP TABLE IF EXISTS inschrijving_log          CASCADE;
DROP TABLE IF EXISTS betaling                  CASCADE;
DROP TABLE IF EXISTS evaluatie                 CASCADE;
DROP TABLE IF EXISTS inschrijving_module       CASCADE;
DROP TABLE IF EXISTS inschrijving              CASCADE;
DROP TABLE IF EXISTS periode_module_lesgever   CASCADE;
DROP TABLE IF EXISTS periode_module            CASCADE;
DROP TABLE IF EXISTS opleidingsperiode         CASCADE;
DROP TABLE IF EXISTS module                    CASCADE;
DROP TABLE IF EXISTS opleiding                 CASCADE;
DROP TABLE IF EXISTS niveau                    CASCADE;
DROP TABLE IF EXISTS opleidingsvorm            CASCADE;
DROP TABLE IF EXISTS subcategorie              CASCADE;
DROP TABLE IF EXISTS categorie                 CASCADE;
DROP TABLE IF EXISTS campus                    CASCADE;
DROP TABLE IF EXISTS lesgever                  CASCADE;
DROP TABLE IF EXISTS cursist                   CASCADE;
DROP TABLE IF EXISTS persoon                   CASCADE;


/* ---------------------------------------------------------------------
   1. CATALOGUS
   Deze gegevens zijn publiek: ze mogen allemaal op de website.
   --------------------------------------------------------------------- */

-- 1.1 Categorie (de thema's op /nl/opleidingen)
CREATE TABLE categorie (
    categorie_id    INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    naam            VARCHAR(100) NOT NULL,
    slug            VARCHAR(100) NOT NULL,
    omschrijving    VARCHAR(1000),
    afbeelding_url  VARCHAR(255),
    volgorde        SMALLINT     NOT NULL DEFAULT 0,
    gepubliceerd    BOOLEAN      NOT NULL DEFAULT TRUE,
    aangemaakt_op   TIMESTAMP    NOT NULL DEFAULT now(),
    gewijzigd_op    TIMESTAMP    NOT NULL DEFAULT now(),

    CONSTRAINT uq_categorie_naam UNIQUE (naam),
    CONSTRAINT uq_categorie_slug UNIQUE (slug)
);

COMMENT ON TABLE  categorie      IS 'Thema''s zoals op https://syntra-mvl.be/nl/opleidingen';
COMMENT ON COLUMN categorie.slug IS 'Deel van de URL, bv. grafisch-it-en-media';

-- 1.2 Subcategorie
CREATE TABLE subcategorie (
    subcategorie_id INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    categorie_id    INT          NOT NULL,
    naam            VARCHAR(100) NOT NULL,
    slug            VARCHAR(100) NOT NULL,
    omschrijving    VARCHAR(1000),
    afbeelding_url  VARCHAR(255),
    volgorde        SMALLINT     NOT NULL DEFAULT 0,
    gepubliceerd    BOOLEAN      NOT NULL DEFAULT TRUE,
    aangemaakt_op   TIMESTAMP    NOT NULL DEFAULT now(),
    gewijzigd_op    TIMESTAMP    NOT NULL DEFAULT now(),

    CONSTRAINT fk_subcategorie_categorie
        FOREIGN KEY (categorie_id) REFERENCES categorie(categorie_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT uq_subcategorie_naam UNIQUE (categorie_id, naam),
    CONSTRAINT uq_subcategorie_slug UNIQUE (slug)
);

-- 1.3 Opleidingsvorm en niveau
-- Kleine referentietabellen. De website toont de omschrijving, en dankzij
-- de foreign key kan er nooit een onbestaande vorm of niveau ingevuld worden.
CREATE TABLE opleidingsvorm (
    vorm_code    VARCHAR(20) PRIMARY KEY,
    omschrijving VARCHAR(50) NOT NULL,
    volgorde     SMALLINT    NOT NULL DEFAULT 0,

    CONSTRAINT uq_opleidingsvorm_omschrijving UNIQUE (omschrijving)
);

CREATE TABLE niveau (
    niveau_code  VARCHAR(20) PRIMARY KEY,
    omschrijving VARCHAR(50) NOT NULL,
    volgorde     SMALLINT    NOT NULL DEFAULT 0,

    CONSTRAINT uq_niveau_omschrijving UNIQUE (omschrijving)
);

-- 1.4 Opleiding
CREATE TABLE opleiding (
    opleiding_id       INT           GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    subcategorie_id    INT           NOT NULL,
    vorm_code          VARCHAR(20)   NOT NULL,
    niveau_code        VARCHAR(20)   NOT NULL,
    naam               VARCHAR(150)  NOT NULL,
    slug               VARCHAR(150)  NOT NULL,
    korte_omschrijving VARCHAR(500),
    lange_omschrijving VARCHAR(2000),
    doelgroep          VARCHAR(1000),
    duur_in_jaren      DECIMAL(3,1),
    ai_geintegreerd    BOOLEAN       NOT NULL DEFAULT FALSE,
    nieuw              BOOLEAN       NOT NULL DEFAULT FALSE,
    gepubliceerd       BOOLEAN       NOT NULL DEFAULT TRUE,
    aangemaakt_op      TIMESTAMP     NOT NULL DEFAULT now(),
    gewijzigd_op       TIMESTAMP     NOT NULL DEFAULT now(),

    CONSTRAINT fk_opleiding_subcategorie
        FOREIGN KEY (subcategorie_id) REFERENCES subcategorie(subcategorie_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_opleiding_vorm
        FOREIGN KEY (vorm_code) REFERENCES opleidingsvorm(vorm_code)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_opleiding_niveau
        FOREIGN KEY (niveau_code) REFERENCES niveau(niveau_code)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT uq_opleiding_slug UNIQUE (slug),
    CONSTRAINT uq_opleiding_naam UNIQUE (subcategorie_id, naam),
    CONSTRAINT ck_opleiding_duur CHECK (duur_in_jaren IS NULL OR duur_in_jaren > 0)
);

-- 1.5 Module
-- Een module beschrijft de INHOUD en hangt aan de opleiding.
-- ON DELETE CASCADE: modules bestaan niet los van hun opleiding.
CREATE TABLE module (
    module_id      INT           GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    opleiding_id   INT           NOT NULL,
    code           VARCHAR(20)   NOT NULL,
    naam           VARCHAR(150)  NOT NULL,
    omschrijving   VARCHAR(1000),
    aantal_sessies SMALLINT,
    vrijstelbaar   BOOLEAN       NOT NULL DEFAULT FALSE,
    eindproef      BOOLEAN       NOT NULL DEFAULT FALSE,
    volgorde       SMALLINT      NOT NULL DEFAULT 0,

    CONSTRAINT fk_module_opleiding
        FOREIGN KEY (opleiding_id) REFERENCES opleiding(opleiding_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT uq_module_code UNIQUE (opleiding_id, code),
    CONSTRAINT ck_module_sessies CHECK (aantal_sessies IS NULL OR aantal_sessies > 0)
);

-- 1.6 Campus
CREATE TABLE campus (
    campus_id INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    naam      VARCHAR(50)  NOT NULL,
    adres     VARCHAR(100) NOT NULL,
    postcode  CHAR(4)      NOT NULL,
    gemeente  VARCHAR(50)  NOT NULL,
    telefoon  VARCHAR(20),
    email     VARCHAR(254),

    CONSTRAINT uq_campus_naam UNIQUE (naam),
    CONSTRAINT ck_campus_postcode CHECK (postcode ~ '^[1-9][0-9]{3}$')
);

-- 1.7 Opleidingsperiode
-- Een concrete uitvoering van een opleiding: startmoment, campus,
-- prijs en capaciteit. Dit is wat de website toont onder
-- "Waar en wanneer?".
CREATE TABLE opleidingsperiode (
    periode_id        INT           GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    opleiding_id      INT           NOT NULL,
    campus_id         INT           NOT NULL,
    code              VARCHAR(30)   NOT NULL,
    academiejaar      CHAR(9)       NOT NULL,
    startdatum        DATE          NOT NULL,
    einddatum         DATE          NOT NULL,
    dagdeel           VARCHAR(10)   NOT NULL DEFAULT 'avond',
    prijs             DECIMAL(8,2)  NOT NULL,
    max_cursisten     SMALLINT      NOT NULL,
    inschrijven_tot   DATE,
    status            VARCHAR(15)   NOT NULL DEFAULT 'gepland',
    lessenrooster_url VARCHAR(255),
    aangemaakt_op     TIMESTAMP     NOT NULL DEFAULT now(),
    gewijzigd_op      TIMESTAMP     NOT NULL DEFAULT now(),

    CONSTRAINT fk_periode_opleiding
        FOREIGN KEY (opleiding_id) REFERENCES opleiding(opleiding_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_periode_campus
        FOREIGN KEY (campus_id) REFERENCES campus(campus_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT uq_periode_code    UNIQUE (code),
    CONSTRAINT ck_periode_datums  CHECK (einddatum > startdatum),
    CONSTRAINT ck_periode_prijs   CHECK (prijs >= 0),
    CONSTRAINT ck_periode_max     CHECK (max_cursisten > 0),
    CONSTRAINT ck_periode_dagdeel CHECK (dagdeel IN ('dag', 'avond', 'weekend', 'online')),
    CONSTRAINT ck_periode_status  CHECK (status IN ('gepland', 'open', 'volzet',
                                                    'gestart', 'afgelopen', 'geannuleerd')),
    CONSTRAINT ck_periode_jaar    CHECK (academiejaar ~ '^[0-9]{4}-[0-9]{4}$')
);

-- 1.8 Periode_module
-- Koppeltabel: welke module loopt wanneer binnen welke periode.
-- Hierdoor kan dezelfde moduledefinitie in meerdere academiejaren
-- gebruikt worden, telkens met een eigen planning en eigen lesgever.
CREATE TABLE periode_module (
    periode_module_id INT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    periode_id        INT      NOT NULL,
    module_id         INT      NOT NULL,
    volgorde          SMALLINT NOT NULL DEFAULT 0,
    startdatum        DATE     NOT NULL,
    einddatum         DATE     NOT NULL,

    CONSTRAINT fk_periode_module_periode
        FOREIGN KEY (periode_id) REFERENCES opleidingsperiode(periode_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_periode_module_module
        FOREIGN KEY (module_id) REFERENCES module(module_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT uq_periode_module UNIQUE (periode_id, module_id),
    CONSTRAINT ck_periode_module_datums CHECK (einddatum >= startdatum)
);


/* ---------------------------------------------------------------------
   2. PERSONEN
   Deze gegevens zijn afgeschermd. De website krijgt hier geen toegang
   toe; ze werkt uitsluitend met de views uit 03_views.sql.
   --------------------------------------------------------------------- */

-- 2.1 Persoon
-- Cursist en lesgever zijn allebei een persoon. Door dat apart te houden
-- kan iemand tegelijk cursist en lesgever zijn zonder dat zijn
-- contactgegevens twee keer bewaard worden.
CREATE TABLE persoon (
    persoon_id      INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    voornaam        VARCHAR(50)  NOT NULL,
    familienaam     VARCHAR(100) NOT NULL,
    email           VARCHAR(254) NOT NULL,
    telefoon        VARCHAR(20),
    rijksregisternr CHAR(11),
    geboortedatum   DATE,
    adres           VARCHAR(100),
    postcode        VARCHAR(10),
    gemeente        VARCHAR(50),
    land            CHAR(2)      NOT NULL DEFAULT 'BE',
    aangemaakt_op   TIMESTAMP    NOT NULL DEFAULT now(),
    gewijzigd_op    TIMESTAMP    NOT NULL DEFAULT now(),

    CONSTRAINT ck_persoon_email  CHECK (email LIKE '%_@_%._%'),
    CONSTRAINT ck_persoon_rrn    CHECK (rijksregisternr IS NULL
                                        OR rijksregisternr ~ '^[0-9]{11}$'),
    CONSTRAINT ck_persoon_gebdat CHECK (geboortedatum IS NULL
                                        OR geboortedatum < CURRENT_DATE)
);

COMMENT ON TABLE  persoon                 IS 'Persoonsgegevens - AFGESCHERMD, nooit rechtstreeks naar de website.';
COMMENT ON COLUMN persoon.rijksregisternr IS 'Gevoelig gegeven: enkel zichtbaar voor de rol syntra_admin.';

-- E-mail uniek maken, ongeacht hoofdletters.
CREATE UNIQUE INDEX uq_persoon_email_lower ON persoon (LOWER(email));

-- 2.2 Cursist
CREATE TABLE cursist (
    cursist_id        INT          PRIMARY KEY,
    cursistnummer     VARCHAR(15)  NOT NULL,
    wachtwoord_hash   VARCHAR(100),
    dossier_sinds     DATE         NOT NULL DEFAULT CURRENT_DATE,
    hoogste_diploma   VARCHAR(100),
    opleidingscheques BOOLEAN      NOT NULL DEFAULT FALSE,
    kmo_portefeuille  BOOLEAN      NOT NULL DEFAULT FALSE,
    interne_notitie   VARCHAR(1000),
    actief            BOOLEAN      NOT NULL DEFAULT TRUE,

    CONSTRAINT fk_cursist_persoon
        FOREIGN KEY (cursist_id) REFERENCES persoon(persoon_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT uq_cursist_nummer UNIQUE (cursistnummer)
);

COMMENT ON COLUMN cursist.wachtwoord_hash IS 'Versleuteld met pgcrypto crypt(). Nooit het wachtwoord zelf bewaren.';
COMMENT ON COLUMN cursist.interne_notitie IS 'Notities van de administratie - strikt intern.';

-- 2.3 Lesgever
-- Let op het onderscheid binnen deze tabel:
--   publiek     : publieke_bio, foto_url, linkedin_url
--   afgeschermd : ondernemingsnummer, uurtarief, iban
CREATE TABLE lesgever (
    lesgever_id        INT           PRIMARY KEY,
    lesgevernummer     VARCHAR(15)   NOT NULL,
    publieke_bio       VARCHAR(1000),
    foto_url           VARCHAR(255),
    linkedin_url       VARCHAR(255),
    zichtbaar_op_web   BOOLEAN       NOT NULL DEFAULT TRUE,
    ondernemingsnummer VARCHAR(15),
    uurtarief          DECIMAL(6,2),
    iban               VARCHAR(34),
    in_dienst_sinds    DATE,
    uit_dienst_op      DATE,

    CONSTRAINT fk_lesgever_persoon
        FOREIGN KEY (lesgever_id) REFERENCES persoon(persoon_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT uq_lesgever_nummer UNIQUE (lesgevernummer),
    CONSTRAINT ck_lesgever_tarief CHECK (uurtarief IS NULL OR uurtarief >= 0),
    CONSTRAINT ck_lesgever_dienst CHECK (uit_dienst_op IS NULL
                                         OR in_dienst_sinds IS NULL
                                         OR uit_dienst_op >= in_dienst_sinds)
);

-- 2.4 Wie geeft welke module in welke periode
CREATE TABLE periode_module_lesgever (
    periode_module_id INT         NOT NULL,
    lesgever_id       INT         NOT NULL,
    rol               VARCHAR(15) NOT NULL DEFAULT 'hoofddocent',
    toegewezen_op     TIMESTAMP   NOT NULL DEFAULT now(),

    CONSTRAINT pk_periode_module_lesgever
        PRIMARY KEY (periode_module_id, lesgever_id),
    CONSTRAINT fk_pml_periode_module
        FOREIGN KEY (periode_module_id) REFERENCES periode_module(periode_module_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_pml_lesgever
        FOREIGN KEY (lesgever_id) REFERENCES lesgever(lesgever_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_pml_rol CHECK (rol IN ('hoofddocent', 'co-docent', 'gastdocent'))
);


/* ---------------------------------------------------------------------
   3. INSCHRIJVINGEN
   Ook deze gegevens zijn afgeschermd.
   --------------------------------------------------------------------- */

-- 3.1 Inschrijving
CREATE TABLE inschrijving (
    inschrijving_id INT           GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cursist_id      INT           NOT NULL,
    periode_id      INT           NOT NULL,
    status          VARCHAR(15)   NOT NULL DEFAULT 'aangevraagd',
    ingeschreven_op TIMESTAMP     NOT NULL DEFAULT now(),
    te_betalen      DECIMAL(8,2)  NOT NULL,
    korting         VARCHAR(100),
    opmerking       VARCHAR(500),

    CONSTRAINT fk_inschrijving_cursist
        FOREIGN KEY (cursist_id) REFERENCES cursist(cursist_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_inschrijving_periode
        FOREIGN KEY (periode_id) REFERENCES opleidingsperiode(periode_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    -- Een cursist kan zich maar een keer inschrijven voor dezelfde periode.
    CONSTRAINT uq_inschrijving UNIQUE (cursist_id, periode_id),
    CONSTRAINT ck_inschrijving_bedrag CHECK (te_betalen >= 0),
    CONSTRAINT ck_inschrijving_status CHECK (status IN ('aangevraagd', 'bevestigd',
                                                        'geannuleerd', 'afgewerkt'))
);

-- 3.2 Welke modules volgt de cursist, en waarvoor is hij vrijgesteld
CREATE TABLE inschrijving_module (
    inschrijving_module_id INT     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    inschrijving_id        INT     NOT NULL,
    periode_module_id      INT     NOT NULL,
    vrijstelling           BOOLEAN NOT NULL DEFAULT FALSE,
    vrijstelling_motivatie VARCHAR(500),

    CONSTRAINT fk_im_inschrijving
        FOREIGN KEY (inschrijving_id) REFERENCES inschrijving(inschrijving_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_im_periode_module
        FOREIGN KEY (periode_module_id) REFERENCES periode_module(periode_module_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT uq_inschrijving_module UNIQUE (inschrijving_id, periode_module_id)
);

-- 3.3 Evaluatie
-- Meerdere pogingen per module zijn mogelijk (herkansing).
CREATE TABLE evaluatie (
    evaluatie_id           INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    inschrijving_module_id INT          NOT NULL,
    evaluatiedatum         DATE         NOT NULL DEFAULT CURRENT_DATE,
    score                  DECIMAL(5,2) NOT NULL,
    poging                 SMALLINT     NOT NULL DEFAULT 1,
    feedback               VARCHAR(500),
    lesgever_id            INT,

    CONSTRAINT fk_evaluatie_im
        FOREIGN KEY (inschrijving_module_id) REFERENCES inschrijving_module(inschrijving_module_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    -- SET NULL: het resultaat blijft geldig als de lesgever vertrekt.
    CONSTRAINT fk_evaluatie_lesgever
        FOREIGN KEY (lesgever_id) REFERENCES lesgever(lesgever_id)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT uq_evaluatie_poging UNIQUE (inschrijving_module_id, poging),
    CONSTRAINT ck_evaluatie_score  CHECK (score >= 0 AND score <= 100),
    CONSTRAINT ck_evaluatie_poging CHECK (poging BETWEEN 1 AND 3)
);

-- 3.4 Betaling
CREATE TABLE betaling (
    betaling_id     INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    inschrijving_id INT          NOT NULL,
    bedrag          DECIMAL(8,2) NOT NULL,
    betaaldatum     DATE         NOT NULL DEFAULT CURRENT_DATE,
    methode         VARCHAR(25)  NOT NULL,
    referentie      VARCHAR(50),

    CONSTRAINT fk_betaling_inschrijving
        FOREIGN KEY (inschrijving_id) REFERENCES inschrijving(inschrijving_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT uq_betaling_referentie UNIQUE (referentie),
    CONSTRAINT ck_betaling_bedrag  CHECK (bedrag > 0),
    CONSTRAINT ck_betaling_methode CHECK (methode IN ('overschrijving', 'bancontact',
                                                      'kredietkaart', 'opleidingscheque',
                                                      'kmo_portefeuille', 'factuur'))
);

-- 3.5 Logtabel voor statuswijzigingen van inschrijvingen
-- Wordt gevuld door een trigger (zie 04_functies_en_triggers.sql).
CREATE TABLE inschrijving_log (
    log_id          INT         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    inschrijving_id INT         NOT NULL,
    oude_status     VARCHAR(15),
    nieuwe_status   VARCHAR(15) NOT NULL,
    gewijzigd_op    TIMESTAMP   NOT NULL DEFAULT now(),
    gewijzigd_door  VARCHAR(63) NOT NULL DEFAULT CURRENT_USER
);


/* ---------------------------------------------------------------------
   CONTROLE
   --------------------------------------------------------------------- */
SELECT table_name AS tabel
FROM   information_schema.tables
WHERE  table_schema = 'public'
  AND  table_type   = 'BASE TABLE'
ORDER  BY table_name;
