/* =====================================================================
   05_stored_procedures.sql

   Stored procedures roep je op met CALL. Ze wijzigen gegevens en geven
   niets terug; wat er gebeurd is, verschijnt via RAISE NOTICE in het
   tabblad "Messages" van de Query Tool.

   De procedures werken met namen, codes en slugs in plaats van met
   id's. Zo hoef je geen sleutelwaarden op te zoeken voor je iets kan
   toevoegen, en worden fouten meteen opgevangen met een duidelijke
   melding in plaats van een technische foutcode.

   Voorbeelden van elk van deze procedures staan in 08_testscript.sql.
   ===================================================================== */


/* =====================================================================
   1. CATALOGUS
   ===================================================================== */

-- 1.1 Categorie toevoegen
CREATE OR REPLACE PROCEDURE sp_categorie_toevoegen(
    p_naam           VARCHAR,
    p_slug           VARCHAR,
    p_omschrijving   VARCHAR DEFAULT NULL,
    p_afbeelding_url VARCHAR DEFAULT NULL,
    p_volgorde       INT     DEFAULT 0
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_id INT;
BEGIN
    IF p_naam IS NULL OR TRIM(p_naam) = '' THEN
        RAISE EXCEPTION 'De naam van de categorie is verplicht.';
    END IF;

    IF EXISTS (SELECT 1 FROM categorie WHERE slug = p_slug) THEN
        RAISE EXCEPTION 'Er bestaat al een categorie met slug "%".', p_slug;
    END IF;

    INSERT INTO categorie (naam, slug, omschrijving, afbeelding_url, volgorde)
    VALUES (TRIM(p_naam), p_slug, p_omschrijving, p_afbeelding_url, p_volgorde)
    RETURNING categorie_id INTO v_id;

    RAISE NOTICE 'Categorie "%" toegevoegd met id %.', p_naam, v_id;
END;
$$;


-- 1.2 Subcategorie toevoegen
CREATE OR REPLACE PROCEDURE sp_subcategorie_toevoegen(
    p_categorie_slug VARCHAR,
    p_naam           VARCHAR,
    p_slug           VARCHAR,
    p_omschrijving   VARCHAR DEFAULT NULL,
    p_afbeelding_url VARCHAR DEFAULT NULL,
    p_volgorde       INT     DEFAULT 0
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_categorie_id INT;
    v_id           INT;
BEGIN
    SELECT categorie_id
    INTO   v_categorie_id
    FROM   categorie
    WHERE  slug = p_categorie_slug;

    IF v_categorie_id IS NULL THEN
        RAISE EXCEPTION 'Onbekende categorie met slug "%".', p_categorie_slug;
    END IF;

    INSERT INTO subcategorie (categorie_id, naam, slug, omschrijving, afbeelding_url, volgorde)
    VALUES (v_categorie_id, TRIM(p_naam), p_slug, p_omschrijving, p_afbeelding_url, p_volgorde)
    RETURNING subcategorie_id INTO v_id;

    RAISE NOTICE 'Subcategorie "%" toegevoegd onder "%" met id %.',
                 p_naam, p_categorie_slug, v_id;
END;
$$;


-- 1.3 Opleiding toevoegen
CREATE OR REPLACE PROCEDURE sp_opleiding_toevoegen(
    p_subcategorie_slug  VARCHAR,
    p_naam               VARCHAR,
    p_slug               VARCHAR,
    p_vorm_code          VARCHAR,
    p_niveau_code        VARCHAR DEFAULT 'beginner',
    p_korte_omschrijving VARCHAR DEFAULT NULL,
    p_lange_omschrijving VARCHAR DEFAULT NULL,
    p_doelgroep          VARCHAR DEFAULT NULL,
    p_duur_in_jaren      DECIMAL DEFAULT 1,
    p_ai_geintegreerd    BOOLEAN DEFAULT FALSE,
    p_nieuw              BOOLEAN DEFAULT FALSE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_subcategorie_id INT;
    v_id              INT;
BEGIN
    SELECT subcategorie_id
    INTO   v_subcategorie_id
    FROM   subcategorie
    WHERE  slug = p_subcategorie_slug;

    IF v_subcategorie_id IS NULL THEN
        RAISE EXCEPTION 'Onbekende subcategorie met slug "%".', p_subcategorie_slug;
    END IF;

    INSERT INTO opleiding (subcategorie_id, vorm_code, niveau_code, naam, slug,
                           korte_omschrijving, lange_omschrijving, doelgroep,
                           duur_in_jaren, ai_geintegreerd, nieuw)
    VALUES (v_subcategorie_id, p_vorm_code, p_niveau_code, TRIM(p_naam), p_slug,
            p_korte_omschrijving, p_lange_omschrijving, p_doelgroep,
            p_duur_in_jaren, p_ai_geintegreerd, p_nieuw)
    RETURNING opleiding_id INTO v_id;

    RAISE NOTICE 'Opleiding "%" toegevoegd met id %.', p_naam, v_id;
END;
$$;


-- 1.4 Module toevoegen aan een opleiding
CREATE OR REPLACE PROCEDURE sp_module_toevoegen(
    p_opleiding_slug VARCHAR,
    p_code           VARCHAR,
    p_naam           VARCHAR,
    p_omschrijving   VARCHAR DEFAULT NULL,
    p_aantal_sessies INT     DEFAULT NULL,
    p_vrijstelbaar   BOOLEAN DEFAULT FALSE,
    p_eindproef      BOOLEAN DEFAULT FALSE,
    p_volgorde       INT     DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_opleiding_id INT;
    v_volgorde     INT;
BEGIN
    SELECT opleiding_id
    INTO   v_opleiding_id
    FROM   opleiding
    WHERE  slug = p_opleiding_slug;

    IF v_opleiding_id IS NULL THEN
        RAISE EXCEPTION 'Onbekende opleiding met slug "%".', p_opleiding_slug;
    END IF;

    -- Geen volgorde meegegeven? Dan achteraan toevoegen.
    IF p_volgorde IS NULL THEN
        SELECT COALESCE(MAX(volgorde), 0) + 1
        INTO   v_volgorde
        FROM   module
        WHERE  opleiding_id = v_opleiding_id;
    ELSE
        v_volgorde := p_volgorde;
    END IF;

    INSERT INTO module (opleiding_id, code, naam, omschrijving,
                        aantal_sessies, vrijstelbaar, eindproef, volgorde)
    VALUES (v_opleiding_id, p_code, p_naam, p_omschrijving,
            p_aantal_sessies, p_vrijstelbaar, p_eindproef, v_volgorde);

    RAISE NOTICE 'Module "%" (%) toegevoegd aan "%".', p_naam, p_code, p_opleiding_slug;
END;
$$;


-- 1.5 Opleidingsperiode toevoegen
-- Plant meteen alle modules van de opleiding in over de looptijd van de
-- periode. Met sp_module_plannen kan je die datums nadien verfijnen.
CREATE OR REPLACE PROCEDURE sp_periode_toevoegen(
    p_opleiding_slug    VARCHAR,
    p_code              VARCHAR,
    p_academiejaar      VARCHAR,
    p_campus            VARCHAR,
    p_startdatum        DATE,
    p_einddatum         DATE,
    p_prijs             DECIMAL,
    p_max_cursisten     INT     DEFAULT 18,
    p_dagdeel           VARCHAR DEFAULT 'avond',
    p_lessenrooster_url VARCHAR DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_opleiding_id INT;
    v_campus_id    INT;
    v_periode_id   INT;
    v_aantal       INT;
BEGIN
    SELECT opleiding_id INTO v_opleiding_id FROM opleiding WHERE slug = p_opleiding_slug;
    IF v_opleiding_id IS NULL THEN
        RAISE EXCEPTION 'Onbekende opleiding met slug "%".', p_opleiding_slug;
    END IF;

    SELECT campus_id INTO v_campus_id FROM campus WHERE naam = p_campus;
    IF v_campus_id IS NULL THEN
        RAISE EXCEPTION 'Onbekende campus "%".', p_campus;
    END IF;

    INSERT INTO opleidingsperiode (opleiding_id, campus_id, code, academiejaar,
                                   startdatum, einddatum, dagdeel, prijs,
                                   max_cursisten, inschrijven_tot, status,
                                   lessenrooster_url)
    VALUES (v_opleiding_id, v_campus_id, p_code, p_academiejaar,
            p_startdatum, p_einddatum, p_dagdeel, p_prijs,
            p_max_cursisten, p_startdatum - 1, 'open', p_lessenrooster_url)
    RETURNING periode_id INTO v_periode_id;

    -- Alle modules van de opleiding meteen inplannen.
    INSERT INTO periode_module (periode_id, module_id, volgorde, startdatum, einddatum)
    SELECT v_periode_id, m.module_id, m.volgorde, p_startdatum, p_einddatum
    FROM   module m
    WHERE  m.opleiding_id = v_opleiding_id;

    GET DIAGNOSTICS v_aantal = ROW_COUNT;

    RAISE NOTICE 'Periode "%" aangemaakt (id %) met % ingeplande modules.',
                 p_code, v_periode_id, v_aantal;
END;
$$;


-- 1.6 De datums van een module binnen een periode verfijnen
CREATE OR REPLACE PROCEDURE sp_module_plannen(
    p_periode_code VARCHAR,
    p_module_code  VARCHAR,
    p_startdatum   DATE,
    p_einddatum    DATE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_periode_id   INT;
    v_opleiding_id INT;
    v_module_id    INT;
BEGIN
    SELECT periode_id, opleiding_id
    INTO   v_periode_id, v_opleiding_id
    FROM   opleidingsperiode
    WHERE  code = p_periode_code;

    IF v_periode_id IS NULL THEN
        RAISE EXCEPTION 'Onbekende opleidingsperiode "%".', p_periode_code;
    END IF;

    SELECT module_id
    INTO   v_module_id
    FROM   module
    WHERE  opleiding_id = v_opleiding_id
      AND  code = p_module_code;

    IF v_module_id IS NULL THEN
        RAISE EXCEPTION 'Module "%" hoort niet bij de opleiding van periode "%".',
                        p_module_code, p_periode_code;
    END IF;

    UPDATE periode_module
    SET    startdatum = p_startdatum,
           einddatum  = p_einddatum
    WHERE  periode_id = v_periode_id
      AND  module_id  = v_module_id;

    -- Stond de module nog niet ingepland? Dan alsnog toevoegen.
    IF NOT FOUND THEN
        INSERT INTO periode_module (periode_id, module_id, volgorde, startdatum, einddatum)
        SELECT v_periode_id, v_module_id, m.volgorde, p_startdatum, p_einddatum
        FROM   module m
        WHERE  m.module_id = v_module_id;
    END IF;

    RAISE NOTICE 'Module % in periode % gepland van % tot %.',
                 p_module_code, p_periode_code, p_startdatum, p_einddatum;
END;
$$;


-- 1.7 Een lesgever toewijzen aan een module binnen een periode
CREATE OR REPLACE PROCEDURE sp_lesgever_toewijzen(
    p_periode_code VARCHAR,
    p_module_code  VARCHAR,
    p_email        VARCHAR,
    p_rol          VARCHAR DEFAULT 'hoofddocent'
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_pm_id       INT;
    v_lesgever_id INT;
BEGIN
    SELECT pm.periode_module_id
    INTO   v_pm_id
    FROM   periode_module      pm
    JOIN   opleidingsperiode   p ON p.periode_id = pm.periode_id
    JOIN   module              m ON m.module_id  = pm.module_id
    WHERE  p.code = p_periode_code
      AND  m.code = p_module_code;

    IF v_pm_id IS NULL THEN
        RAISE EXCEPTION 'Module "%" is niet ingepland in periode "%".',
                        p_module_code, p_periode_code;
    END IF;

    SELECT l.lesgever_id
    INTO   v_lesgever_id
    FROM   lesgever l
    JOIN   persoon  p ON p.persoon_id = l.lesgever_id
    WHERE  LOWER(p.email) = LOWER(p_email);

    IF v_lesgever_id IS NULL THEN
        RAISE EXCEPTION 'Geen lesgever gevonden met e-mailadres "%".', p_email;
    END IF;

    INSERT INTO periode_module_lesgever (periode_module_id, lesgever_id, rol)
    VALUES (v_pm_id, v_lesgever_id, p_rol)
    ON CONFLICT (periode_module_id, lesgever_id)
    DO UPDATE SET rol = EXCLUDED.rol;

    RAISE NOTICE 'Lesgever % toegewezen aan module % in periode % als %.',
                 p_email, p_module_code, p_periode_code, p_rol;
END;
$$;


/* =====================================================================
   2. PERSONEN
   ===================================================================== */

-- 2.1 Cursist toevoegen
-- Bestaat de persoon al (bv. omdat hij ook lesgever is)? Dan wordt die
-- rij hergebruikt in plaats van de gegevens dubbel te bewaren.
-- Het wachtwoord wordt versleuteld bewaard met crypt() uit pgcrypto.
CREATE OR REPLACE PROCEDURE sp_cursist_toevoegen(
    p_voornaam        VARCHAR,
    p_familienaam     VARCHAR,
    p_email           VARCHAR,
    p_telefoon        VARCHAR DEFAULT NULL,
    p_geboortedatum   DATE    DEFAULT NULL,
    p_rijksregisternr CHAR    DEFAULT NULL,
    p_adres           VARCHAR DEFAULT NULL,
    p_postcode        VARCHAR DEFAULT NULL,
    p_gemeente        VARCHAR DEFAULT NULL,
    p_hoogste_diploma VARCHAR DEFAULT NULL,
    p_wachtwoord      VARCHAR DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_persoon_id INT;
BEGIN
    SELECT persoon_id
    INTO   v_persoon_id
    FROM   persoon
    WHERE  LOWER(email) = LOWER(p_email);

    IF v_persoon_id IS NULL THEN
        INSERT INTO persoon (voornaam, familienaam, email, telefoon, geboortedatum,
                             rijksregisternr, adres, postcode, gemeente)
        VALUES (TRIM(p_voornaam), TRIM(p_familienaam), p_email, p_telefoon,
                p_geboortedatum, p_rijksregisternr, p_adres, p_postcode, p_gemeente)
        RETURNING persoon_id INTO v_persoon_id;
    END IF;

    IF EXISTS (SELECT 1 FROM cursist WHERE cursist_id = v_persoon_id) THEN
        RAISE EXCEPTION 'Deze persoon (%) is al geregistreerd als cursist.', p_email;
    END IF;

    INSERT INTO cursist (cursist_id, cursistnummer, hoogste_diploma, wachtwoord_hash)
    VALUES (v_persoon_id,
            'C' || LPAD(v_persoon_id::TEXT, 5, '0'),
            p_hoogste_diploma,
            CASE WHEN p_wachtwoord IS NULL
                 THEN NULL
                 ELSE crypt(p_wachtwoord, gen_salt('bf'))
            END);

    RAISE NOTICE 'Cursist % % toegevoegd met nummer C%.',
                 p_voornaam, p_familienaam, LPAD(v_persoon_id::TEXT, 5, '0');
END;
$$;


-- 2.2 Lesgever toevoegen
CREATE OR REPLACE PROCEDURE sp_lesgever_toevoegen(
    p_voornaam           VARCHAR,
    p_familienaam        VARCHAR,
    p_email              VARCHAR,
    p_telefoon           VARCHAR DEFAULT NULL,
    p_publieke_bio       VARCHAR DEFAULT NULL,
    p_ondernemingsnummer VARCHAR DEFAULT NULL,
    p_uurtarief          DECIMAL DEFAULT NULL,
    p_iban               VARCHAR DEFAULT NULL,
    p_in_dienst_sinds    DATE    DEFAULT CURRENT_DATE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_persoon_id INT;
BEGIN
    SELECT persoon_id
    INTO   v_persoon_id
    FROM   persoon
    WHERE  LOWER(email) = LOWER(p_email);

    IF v_persoon_id IS NULL THEN
        INSERT INTO persoon (voornaam, familienaam, email, telefoon)
        VALUES (TRIM(p_voornaam), TRIM(p_familienaam), p_email, p_telefoon)
        RETURNING persoon_id INTO v_persoon_id;
    END IF;

    IF EXISTS (SELECT 1 FROM lesgever WHERE lesgever_id = v_persoon_id) THEN
        RAISE EXCEPTION 'Deze persoon (%) is al geregistreerd als lesgever.', p_email;
    END IF;

    INSERT INTO lesgever (lesgever_id, lesgevernummer, publieke_bio,
                          ondernemingsnummer, uurtarief, iban, in_dienst_sinds)
    VALUES (v_persoon_id,
            'L' || LPAD(v_persoon_id::TEXT, 4, '0'),
            p_publieke_bio, p_ondernemingsnummer, p_uurtarief, p_iban, p_in_dienst_sinds);

    RAISE NOTICE 'Lesgever % % toegevoegd met nummer L%.',
                 p_voornaam, p_familienaam, LPAD(v_persoon_id::TEXT, 4, '0');
END;
$$;


/* =====================================================================
   3. INSCHRIJVINGEN
   ===================================================================== */

-- 3.1 Een cursist inschrijven voor een opleidingsperiode
-- Deze procedure doet meer dan een INSERT:
--   - ze vergrendelt de periode zodat twee gelijktijdige inschrijvingen
--     de capaciteit niet kunnen overschrijden;
--   - ze weigert een periode die niet open staat of die volzet is;
--   - ze koppelt automatisch alle modules van de periode;
--   - ze zet de periode op 'volzet' bij de laatste plaats.
CREATE OR REPLACE PROCEDURE sp_inschrijven(
    p_email        VARCHAR,
    p_periode_code VARCHAR,
    p_korting      DECIMAL DEFAULT 0,
    p_korting_tekst VARCHAR DEFAULT NULL,
    p_opmerking    VARCHAR DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_cursist_id     INT;
    v_periode_id     INT;
    v_status         VARCHAR(15);
    v_prijs          DECIMAL(8,2);
    v_vrij           INT;
    v_inschrijving_id INT;
BEGIN
    SELECT c.cursist_id
    INTO   v_cursist_id
    FROM   cursist c
    JOIN   persoon p ON p.persoon_id = c.cursist_id
    WHERE  LOWER(p.email) = LOWER(p_email)
      AND  c.actief;

    IF v_cursist_id IS NULL THEN
        RAISE EXCEPTION 'Geen actieve cursist gevonden met e-mailadres "%".', p_email;
    END IF;

    -- FOR UPDATE vergrendelt de rij tot het einde van de transactie.
    SELECT periode_id, status, prijs
    INTO   v_periode_id, v_status, v_prijs
    FROM   opleidingsperiode
    WHERE  code = p_periode_code
    FOR UPDATE;

    IF v_periode_id IS NULL THEN
        RAISE EXCEPTION 'Onbekende opleidingsperiode "%".', p_periode_code;
    END IF;

    IF v_status NOT IN ('gepland', 'open') THEN
        RAISE EXCEPTION 'Periode "%" staat op status "%" en is niet open voor inschrijvingen.',
                        p_periode_code, v_status;
    END IF;

    v_vrij := fn_vrije_plaatsen(v_periode_id);
    IF v_vrij <= 0 THEN
        RAISE EXCEPTION 'Periode "%" is volzet.', p_periode_code;
    END IF;

    IF EXISTS (SELECT 1 FROM inschrijving
               WHERE cursist_id = v_cursist_id AND periode_id = v_periode_id) THEN
        RAISE EXCEPTION 'Cursist % is al ingeschreven voor periode "%".',
                        p_email, p_periode_code;
    END IF;

    INSERT INTO inschrijving (cursist_id, periode_id, te_betalen, korting, opmerking)
    VALUES (v_cursist_id, v_periode_id,
            GREATEST(v_prijs - COALESCE(p_korting, 0), 0),
            p_korting_tekst, p_opmerking)
    RETURNING inschrijving_id INTO v_inschrijving_id;

    -- De cursist volgt standaard alle modules van de periode.
    INSERT INTO inschrijving_module (inschrijving_id, periode_module_id)
    SELECT v_inschrijving_id, pm.periode_module_id
    FROM   periode_module pm
    WHERE  pm.periode_id = v_periode_id;

    IF fn_vrije_plaatsen(v_periode_id) = 0 THEN
        UPDATE opleidingsperiode SET status = 'volzet' WHERE periode_id = v_periode_id;
        RAISE NOTICE 'Periode "%" is nu volzet.', p_periode_code;
    END IF;

    RAISE NOTICE 'Inschrijving % aangemaakt voor % in periode %. Nog % plaatsen vrij.',
                 v_inschrijving_id, p_email, p_periode_code, fn_vrije_plaatsen(v_periode_id);
END;
$$;


-- 3.2 Een inschrijving bevestigen
CREATE OR REPLACE PROCEDURE sp_inschrijving_bevestigen(p_inschrijving_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE inschrijving
    SET    status = 'bevestigd'
    WHERE  inschrijving_id = p_inschrijving_id
      AND  status = 'aangevraagd';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Inschrijving % bestaat niet of staat niet op "aangevraagd".',
                        p_inschrijving_id;
    END IF;

    RAISE NOTICE 'Inschrijving % is bevestigd.', p_inschrijving_id;
END;
$$;


-- 3.3 Een inschrijving annuleren
-- De vrijgekomen plaats zet een volzette periode weer open.
CREATE OR REPLACE PROCEDURE sp_inschrijving_annuleren(
    p_inschrijving_id INT,
    p_reden           VARCHAR DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_periode_id INT;
BEGIN
    UPDATE inschrijving
    SET    status    = 'geannuleerd',
           opmerking = COALESCE(opmerking || ' | ', '') || COALESCE(p_reden, 'Geannuleerd')
    WHERE  inschrijving_id = p_inschrijving_id
      AND  status <> 'geannuleerd'
    RETURNING periode_id INTO v_periode_id;

    IF v_periode_id IS NULL THEN
        RAISE EXCEPTION 'Inschrijving % bestaat niet of was al geannuleerd.',
                        p_inschrijving_id;
    END IF;

    UPDATE opleidingsperiode
    SET    status = 'open'
    WHERE  periode_id = v_periode_id
      AND  status = 'volzet'
      AND  fn_vrije_plaatsen(v_periode_id) > 0;

    RAISE NOTICE 'Inschrijving % geannuleerd.', p_inschrijving_id;
END;
$$;


-- 3.4 Een vrijstelling toekennen
CREATE OR REPLACE PROCEDURE sp_vrijstelling_toekennen(
    p_inschrijving_id INT,
    p_module_code     VARCHAR,
    p_motivatie       VARCHAR
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_im_id        INT;
    v_vrijstelbaar BOOLEAN;
BEGIN
    SELECT im.inschrijving_module_id, m.vrijstelbaar
    INTO   v_im_id, v_vrijstelbaar
    FROM   inschrijving_module im
    JOIN   periode_module      pm ON pm.periode_module_id = im.periode_module_id
    JOIN   module              m  ON m.module_id = pm.module_id
    WHERE  im.inschrijving_id = p_inschrijving_id
      AND  m.code = p_module_code;

    IF v_im_id IS NULL THEN
        RAISE EXCEPTION 'Module "%" hoort niet bij inschrijving %.',
                        p_module_code, p_inschrijving_id;
    END IF;

    IF NOT v_vrijstelbaar THEN
        RAISE EXCEPTION 'Voor module "%" kan geen vrijstelling toegekend worden.',
                        p_module_code;
    END IF;

    UPDATE inschrijving_module
    SET    vrijstelling           = TRUE,
           vrijstelling_motivatie = p_motivatie
    WHERE  inschrijving_module_id = v_im_id;

    RAISE NOTICE 'Vrijstelling toegekend voor module % bij inschrijving %.',
                 p_module_code, p_inschrijving_id;
END;
$$;


-- 3.5 Een evaluatie registreren
-- De procedure telt zelf de poging op: een tweede evaluatie voor
-- dezelfde module is automatisch poging 2.
CREATE OR REPLACE PROCEDURE sp_evaluatie_registreren(
    p_inschrijving_id INT,
    p_module_code     VARCHAR,
    p_score           DECIMAL,
    p_lesgever_email  VARCHAR DEFAULT NULL,
    p_feedback        VARCHAR DEFAULT NULL,
    p_datum           DATE    DEFAULT CURRENT_DATE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_im_id       INT;
    v_lesgever_id INT;
    v_poging      INT;
BEGIN
    SELECT im.inschrijving_module_id
    INTO   v_im_id
    FROM   inschrijving_module im
    JOIN   periode_module      pm ON pm.periode_module_id = im.periode_module_id
    JOIN   module              m  ON m.module_id = pm.module_id
    WHERE  im.inschrijving_id = p_inschrijving_id
      AND  m.code = p_module_code;

    IF v_im_id IS NULL THEN
        RAISE EXCEPTION 'Module "%" hoort niet bij inschrijving %.',
                        p_module_code, p_inschrijving_id;
    END IF;

    IF p_lesgever_email IS NOT NULL THEN
        SELECT l.lesgever_id
        INTO   v_lesgever_id
        FROM   lesgever l
        JOIN   persoon  p ON p.persoon_id = l.lesgever_id
        WHERE  LOWER(p.email) = LOWER(p_lesgever_email);
    END IF;

    SELECT COALESCE(MAX(poging), 0) + 1
    INTO   v_poging
    FROM   evaluatie
    WHERE  inschrijving_module_id = v_im_id;

    INSERT INTO evaluatie (inschrijving_module_id, evaluatiedatum, score,
                           poging, feedback, lesgever_id)
    VALUES (v_im_id, p_datum, p_score, v_poging, p_feedback, v_lesgever_id);

    RAISE NOTICE 'Evaluatie geregistreerd: module %, poging %, score % (%).',
                 p_module_code, v_poging, p_score,
                 CASE WHEN p_score >= 50 THEN 'geslaagd' ELSE 'niet geslaagd' END;
END;
$$;


-- 3.6 Een betaling registreren
CREATE OR REPLACE PROCEDURE sp_betaling_registreren(
    p_inschrijving_id INT,
    p_bedrag          DECIMAL,
    p_methode         VARCHAR,
    p_referentie      VARCHAR DEFAULT NULL,
    p_datum           DATE    DEFAULT CURRENT_DATE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_saldo DECIMAL(8,2);
BEGIN
    v_saldo := fn_openstaand_saldo(p_inschrijving_id);

    IF v_saldo IS NULL THEN
        RAISE EXCEPTION 'Onbekende inschrijving %.', p_inschrijving_id;
    END IF;

    IF p_bedrag > v_saldo THEN
        RAISE EXCEPTION 'Bedrag % is hoger dan het openstaande saldo van %.',
                        p_bedrag, v_saldo;
    END IF;

    INSERT INTO betaling (inschrijving_id, bedrag, betaaldatum, methode, referentie)
    VALUES (p_inschrijving_id, p_bedrag, p_datum, p_methode,
            COALESCE(p_referentie,
                     'BET-' || p_inschrijving_id || '-' || TO_CHAR(now(), 'YYYYMMDDHH24MISS')));

    RAISE NOTICE 'Betaling van % geregistreerd. Nog openstaand: %.',
                 p_bedrag, fn_openstaand_saldo(p_inschrijving_id);
END;
$$;


/* ---------------------------------------------------------------------
   CONTROLE
   --------------------------------------------------------------------- */
SELECT routine_name AS procedure
FROM   information_schema.routines
WHERE  routine_schema = 'public'
  AND  routine_type   = 'PROCEDURE'
ORDER  BY routine_name;
