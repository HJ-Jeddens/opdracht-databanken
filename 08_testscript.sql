/* =====================================================================
   08_testscript.sql

   Dit script test de volledige databank. Voer het uit in de Query Tool
   van pgAdmin. Elke SELECT levert een apart resultaattabblad op; de
   meldingen van de procedures verschijnen in het tabblad "Messages".

   Tip: je kan ook een enkel blok testen. Selecteer de regels die je wil
   uitvoeren en druk op F5. pgAdmin voert dan enkel de selectie uit.

   Onderdeel 4 (de stored procedures) staat in een transactie met een
   ROLLBACK op het einde. De testdata blijft daardoor ongewijzigd.
   ===================================================================== */


/* =====================================================================
   1. DE PUBLIEKE VIEWS - wat de website ziet
   ===================================================================== */

-- 1.1 De themapagina: 16 categorieen, met tellingen
SELECT naam, aantal_subcategorieen, aantal_opleidingen, url
FROM   vw_pub_categorie;

-- 1.2 De subcategorieen van Grafisch, IT en media
SELECT naam, aantal_opleidingen, url
FROM   vw_pub_subcategorie
WHERE  categorie_slug = 'grafisch-it-en-media';

-- 1.3 Het aanbod van Data & software development
SELECT naam, opleidingsvorm, niveau, eerstvolgende_start, prijs_vanaf, locaties
FROM   vw_pub_opleiding
WHERE  subcategorie_slug = 'data-software-development';

-- 1.4 Het programma van de opleiding uit de opdracht
SELECT module_code, module, aantal_sessies, vrijstelbaar, eindproef
FROM   vw_pub_programma
WHERE  opleiding_slug = 'python-data-developer';

-- 1.5 De twee opleidingsperiodes, met de vrije plaatsen
SELECT periode_code, academiejaar, campus, startdatum, einddatum,
       prijs, status, vrije_plaatsen, inschrijven_mogelijk
FROM   vw_pub_startmoment
WHERE  opleiding_slug = 'python-data-developer';

-- 1.6 De publieke docentenprofielen.
--     Merk op: geen e-mail, geen telefoon, geen tarief.
SELECT naam, publieke_bio
FROM   vw_pub_lesgever;


/* =====================================================================
   2. DE INTERNE VIEWS - wat de administratie ziet
   ===================================================================== */

-- 2.1 Klaslijst van het eerste academiejaar
SELECT cursistnummer, voornaam, familienaam, email, status, te_betalen, openstaand
FROM   vw_int_klaslijst
WHERE  periode_code = 'PDD-2026-GENT';

-- 2.2 Bezetting en verwachte omzet per periode
SELECT periode_code, opleiding, ingeschreven, vrije_plaatsen,
       bezetting_pct, aantal_modules, verwachte_omzet
FROM   vw_int_bezetting;

-- 2.3 Wie geeft welke module in academiejaar 2026-2027
SELECT module_code, module, lesgever, rol, startdatum, einddatum, aantal_cursisten
FROM   vw_int_lesopdracht
WHERE  periode_code = 'PDD-2026-GENT';

-- 2.4 De resultaten van de module Leren programmeren in Python.
--     Jonas De Clercq staat er twee keer in: eerste poging niet geslaagd,
--     tweede poging wel.
SELECT cursist, module_code, poging, score, geslaagd, evaluatiedatum
FROM   vw_int_resultaat
WHERE  module_code = 'PY-BASIS'
  AND  score IS NOT NULL
ORDER  BY cursist, poging;

-- 2.5 Slaagpercentage per module
SELECT module_code
     , module
     , COUNT(*) FILTER (WHERE geslaagd)       AS geslaagd
     , COUNT(*) FILTER (WHERE NOT geslaagd)   AS niet_geslaagd
     , ROUND(AVG(score), 1)                   AS gemiddelde
FROM   vw_int_resultaat
WHERE  score IS NOT NULL
GROUP  BY module_code, module
ORDER  BY module_code;

-- 2.6 Wie moet er nog betalen?
SELECT cursist, opleiding, te_betalen, betaald, openstaand
FROM   vw_int_openstaand;

-- 2.7 De vrijstellingen
SELECT cursist, module_code, module, vrijstelling, module_afgerond
FROM   vw_int_resultaat
WHERE  vrijstelling;


/* =====================================================================
   3. DE FUNCTIES
   ===================================================================== */

SELECT p.code                             AS periode
     , p.max_cursisten
     , fn_aantal_ingeschreven(p.periode_id) AS ingeschreven
     , fn_vrije_plaatsen(p.periode_id)      AS vrij
FROM   opleidingsperiode p
ORDER  BY p.code;

-- Openstaand saldo van elke inschrijving
SELECT i.inschrijving_id
     , per.familienaam
     , i.te_betalen
     , fn_openstaand_saldo(i.inschrijving_id) AS openstaand
FROM   inschrijving i
JOIN   persoon per ON per.persoon_id = i.cursist_id
ORDER  BY i.inschrijving_id;

-- Leeftijd van de cursisten
SELECT voornaam, familienaam, geboortedatum, fn_leeftijd(geboortedatum) AS leeftijd
FROM   vw_int_cursist
ORDER  BY leeftijd;


/* =====================================================================
   4. DE STORED PROCEDURES
   Alles in dit blok wordt op het einde teruggedraaid met ROLLBACK,
   zodat de testdata onaangeroerd blijft.
   Kijk in het tabblad "Messages" voor de meldingen.
   ===================================================================== */

BEGIN;

-- 4.1 Een categorie en een subcategorie toevoegen
CALL sp_categorie_toevoegen('Testcategorie', 'testcategorie',
                            'Categorie die enkel voor deze test bestaat.', NULL, 99);

CALL sp_subcategorie_toevoegen('testcategorie', 'Testsubcategorie', 'testsubcategorie');

-- 4.2 Een opleiding met twee modules
CALL sp_opleiding_toevoegen('testsubcategorie', 'Testopleiding', 'testopleiding',
                            'avond', 'beginner', 'Een opleiding om de procedures te testen.');

CALL sp_module_toevoegen('testopleiding', 'T-01', 'Eerste testmodule', NULL, 10, TRUE);
CALL sp_module_toevoegen('testopleiding', 'T-02', 'Tweede testmodule', NULL,  8, FALSE, TRUE);

-- 4.3 Een opleidingsperiode. De procedure plant meteen beide modules in.
CALL sp_periode_toevoegen('testopleiding', 'TEST-2026', '2026-2027', 'Campus Gent',
                          DATE '2026-10-01', DATE '2027-05-31', 750.00, 2);

-- Controle: de modules zijn automatisch ingepland
SELECT m.code, m.naam, pm.startdatum, pm.einddatum
FROM   periode_module    pm
JOIN   module            m ON m.module_id  = pm.module_id
JOIN   opleidingsperiode p ON p.periode_id = pm.periode_id
WHERE  p.code = 'TEST-2026';

-- 4.4 De datums verfijnen en een lesgever toewijzen
CALL sp_module_plannen('TEST-2026', 'T-01', DATE '2026-10-01', DATE '2026-12-20');
CALL sp_module_plannen('TEST-2026', 'T-02', DATE '2027-01-10', DATE '2027-05-31');
CALL sp_lesgever_toewijzen('TEST-2026', 'T-01', 'wim.segers@syntra-mvl.be');

-- 4.5 Een cursist toevoegen en inschrijven
CALL sp_cursist_toevoegen('Test', 'Cursist', 'test.cursist@example.be',
                          '+32 400 00 00 00', DATE '1990-01-01', NULL,
                          'Teststraat 1', '9000', 'Gent', 'Secundair onderwijs',
                          'GeheimWachtwoord123');

CALL sp_inschrijven('test.cursist@example.be', 'TEST-2026');

-- 4.6 Het capaciteitsslot testen.
--     De periode heeft maar 2 plaatsen. Na de tweede inschrijving springt
--     de status op 'volzet', de derde wordt geweigerd.
CALL sp_inschrijven('bram.coppens@example.be', 'TEST-2026');

SELECT code, status, max_cursisten, fn_vrije_plaatsen(periode_id) AS vrij
FROM   opleidingsperiode
WHERE  code = 'TEST-2026';

DO $$
BEGIN
    CALL sp_inschrijven('iris.lemmens@example.be', 'TEST-2026');
    RAISE NOTICE 'FOUT: de derde inschrijving had geweigerd moeten worden!';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Correct geweigerd: %', SQLERRM;
END;
$$;

-- 4.7 Bevestigen, vrijstelling, evaluatie en betaling
DO $$
DECLARE
    v_id INT;
BEGIN
    SELECT i.inschrijving_id
    INTO   v_id
    FROM   inschrijving      i
    JOIN   persoon           p ON p.persoon_id = i.cursist_id
    JOIN   opleidingsperiode o ON o.periode_id = i.periode_id
    WHERE  p.email = 'test.cursist@example.be'
      AND  o.code  = 'TEST-2026';

    CALL sp_inschrijving_bevestigen(v_id);
    CALL sp_vrijstelling_toekennen(v_id, 'T-01', 'Vrijstelling op basis van eerdere ervaring.');
    CALL sp_evaluatie_registreren(v_id, 'T-02', 45, 'wim.segers@syntra-mvl.be', 'Onvoldoende.');
    CALL sp_evaluatie_registreren(v_id, 'T-02', 68, 'wim.segers@syntra-mvl.be', 'Geslaagd na herkansing.');
    CALL sp_betaling_registreren(v_id, 300.00, 'bancontact', 'TEST-BET-001');

    -- Een betaling boven het openstaande saldo moet geweigerd worden.
    BEGIN
        CALL sp_betaling_registreren(v_id, 9999.00, 'overschrijving', 'TEST-BET-002');
        RAISE NOTICE 'FOUT: te hoge betaling werd aanvaard!';
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'Correct geweigerd: %', SQLERRM;
    END;
END;
$$;

-- Resultaat van het testtraject
SELECT cursist, module_code, vrijstelling, poging, score, geslaagd, module_afgerond
FROM   vw_int_resultaat
WHERE  periode_code = 'TEST-2026'
ORDER  BY module_code, poging;

-- 4.8 Annuleren geeft de plaats terug vrij en zet de periode weer open
DO $$
DECLARE
    v_id INT;
BEGIN
    SELECT i.inschrijving_id
    INTO   v_id
    FROM   inschrijving      i
    JOIN   persoon           p ON p.persoon_id = i.cursist_id
    JOIN   opleidingsperiode o ON o.periode_id = i.periode_id
    WHERE  p.email = 'bram.coppens@example.be'
      AND  o.code  = 'TEST-2026';

    CALL sp_inschrijving_annuleren(v_id, 'Geannuleerd tijdens de test.');
END;
$$;

SELECT code, status, fn_vrije_plaatsen(periode_id) AS vrij
FROM   opleidingsperiode
WHERE  code = 'TEST-2026';

-- Alles van deze test terugdraaien.
ROLLBACK;

-- Controle: de testcategorie bestaat niet meer.
SELECT COUNT(*) AS testcategorieen_over
FROM   categorie
WHERE  slug = 'testcategorie';


/* =====================================================================
   5. DE TRIGGERS
   ===================================================================== */

-- 5.1 gewijzigd_op wordt automatisch bijgewerkt
BEGIN;

SELECT naam, aangemaakt_op, gewijzigd_op
FROM   categorie
WHERE  slug = 'grafisch-it-en-media';

UPDATE categorie
SET    omschrijving = omschrijving || ' (aangepast tijdens de test)'
WHERE  slug = 'grafisch-it-en-media';

SELECT naam, aangemaakt_op, gewijzigd_op
FROM   categorie
WHERE  slug = 'grafisch-it-en-media';

ROLLBACK;

-- 5.2 Statuswijzigingen worden gelogd
SELECT l.log_id, l.inschrijving_id, l.oude_status, l.nieuwe_status,
       p.familienaam
FROM   inschrijving_log l
JOIN   inschrijving     i ON i.inschrijving_id = l.inschrijving_id
JOIN   persoon          p ON p.persoon_id = i.cursist_id
ORDER  BY l.log_id;


/* =====================================================================
   6. DE CONSTRAINTS
   Elke test hieronder MOET mislukken. Het DO-blok vangt de fout op en
   toont de melding in het tabblad "Messages".
   ===================================================================== */

DO $$
BEGIN
    -- 6.1 Een opleiding in een onbestaande subcategorie (foreign key)
    BEGIN
        INSERT INTO opleiding (subcategorie_id, vorm_code, niveau_code, naam, slug)
        VALUES (9999, 'avond', 'beginner', 'Onbestaand', 'onbestaand');
        RAISE NOTICE 'FOUT: onbestaande subcategorie werd aanvaard!';
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE 'OK - foreign key: %', SQLERRM;
    END;

    -- 6.2 Een periode die eindigt voor ze begint (check constraint)
    BEGIN
        INSERT INTO opleidingsperiode (opleiding_id, campus_id, code, academiejaar,
                                       startdatum, einddatum, prijs, max_cursisten)
        SELECT o.opleiding_id, 1, 'FOUT-01', '2026-2027',
               DATE '2027-01-01', DATE '2026-01-01', 100, 10
        FROM   opleiding o WHERE o.slug = 'python-data-developer';
        RAISE NOTICE 'FOUT: einddatum voor startdatum werd aanvaard!';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK - check constraint: %', SQLERRM;
    END;

    -- 6.3 Een score van 150 (check constraint)
    BEGIN
        INSERT INTO evaluatie (inschrijving_module_id, score)
        VALUES ((SELECT MIN(inschrijving_module_id) FROM inschrijving_module), 150);
        RAISE NOTICE 'FOUT: score 150 werd aanvaard!';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK - check constraint: %', SQLERRM;
    END;

    -- 6.4 Twee keer dezelfde cursist in dezelfde periode (unique)
    BEGIN
        INSERT INTO inschrijving (cursist_id, periode_id, te_betalen)
        SELECT i.cursist_id, i.periode_id, 100
        FROM   inschrijving i
        ORDER  BY i.inschrijving_id
        LIMIT  1;
        RAISE NOTICE 'FOUT: dubbele inschrijving werd aanvaard!';
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE 'OK - unique constraint: %', SQLERRM;
    END;

    -- 6.5 Een categorie verwijderen die nog subcategorieen heeft (restrict)
    BEGIN
        DELETE FROM categorie WHERE slug = 'grafisch-it-en-media';
        RAISE NOTICE 'FOUT: categorie met inhoud werd verwijderd!';
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE 'OK - ON DELETE RESTRICT: %', SQLERRM;
    END;

    -- 6.6 Een ongeldig e-mailadres (check constraint)
    BEGIN
        INSERT INTO persoon (voornaam, familienaam, email)
        VALUES ('Foute', 'Mail', 'geen-echt-adres');
        RAISE NOTICE 'FOUT: ongeldig e-mailadres werd aanvaard!';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK - check constraint: %', SQLERRM;
    END;
END;
$$;


/* =====================================================================
   7. DE RECHTEN
   ===================================================================== */

-- 7.1 Als de website: de publieke views werken
SET ROLE syntra_web;

SELECT current_user AS ik_ben_nu;

SELECT COUNT(*) AS opleidingen_zichtbaar FROM vw_pub_opleiding;
SELECT naam, publieke_bio FROM vw_pub_lesgever LIMIT 3;

RESET ROLE;

-- 7.2 Als de website: persoonsgegevens zijn NIET bereikbaar
DO $$
BEGIN
    SET LOCAL ROLE syntra_web;

    BEGIN
        PERFORM COUNT(*) FROM persoon;
        RAISE NOTICE 'FOUT: de website kon de tabel persoon lezen!';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK - website kan persoon niet lezen: %', SQLERRM;
    END;

    BEGIN
        PERFORM COUNT(*) FROM vw_int_klaslijst;
        RAISE NOTICE 'FOUT: de website kon de klaslijst lezen!';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK - website kan de klaslijst niet lezen: %', SQLERRM;
    END;
END;
$$;

-- 7.3 Als medewerker: contactgegevens mogen, het rijksregisternummer niet
DO $$
DECLARE
    v_dummy TEXT;
BEGIN
    SET LOCAL ROLE syntra_medewerker;

    BEGIN
        SELECT email INTO v_dummy FROM persoon LIMIT 1;
        RAISE NOTICE 'OK - medewerker mag het e-mailadres lezen.';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'FOUT: medewerker kan het e-mailadres niet lezen.';
    END;

    BEGIN
        SELECT rijksregisternr INTO v_dummy FROM persoon LIMIT 1;
        RAISE NOTICE 'FOUT: medewerker kon het rijksregisternummer lezen!';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK - rijksregisternummer is afgeschermd: %', SQLERRM;
    END;

    BEGIN
        SELECT iban INTO v_dummy FROM lesgever LIMIT 1;
        RAISE NOTICE 'FOUT: medewerker kon de IBAN lezen!';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK - IBAN is afgeschermd: %', SQLERRM;
    END;
END;
$$;

RESET ROLE;


/* =====================================================================
   8. WACHTWOORDEN
   Wachtwoorden staan versleuteld in de databank (pgcrypto).
   ===================================================================== */

-- Zo ziet een opgeslagen wachtwoord eruit: onleesbaar.
SELECT p.email, LEFT(c.wachtwoord_hash, 35) || '...' AS opgeslagen_hash
FROM   cursist c
JOIN   persoon p ON p.persoon_id = c.cursist_id
LIMIT  3;

-- Zo controleer je een wachtwoord bij het aanmelden: het ingegeven
-- wachtwoord wordt met dezelfde salt versleuteld en vergeleken.
SELECT p.email
     , (c.wachtwoord_hash = crypt('Test1234!',  c.wachtwoord_hash)) AS juist_wachtwoord
     , (c.wachtwoord_hash = crypt('FoutWachtw', c.wachtwoord_hash)) AS fout_wachtwoord
FROM   cursist c
JOIN   persoon p ON p.persoon_id = c.cursist_id
WHERE  p.email = 'ella.janssens@example.be';


/* =====================================================================
   9. INDEXGEBRUIK CONTROLEREN
   EXPLAIN toont welk plan PostgreSQL kiest. Op deze kleine testset kiest
   de planner vaak nog een sequential scan: dat is normaal, een index
   loont pas bij grotere tabellen.
   ===================================================================== */

EXPLAIN ANALYZE
SELECT * FROM opleiding WHERE LOWER(naam) = 'python data developer';

EXPLAIN ANALYZE
SELECT * FROM inschrijving WHERE periode_id = 1;


/* =====================================================================
   KLAAR
   ===================================================================== */
SELECT 'Alle tests uitgevoerd. Kijk het tabblad Messages na voor de '
    || 'meldingen van de procedures en de constraint-tests.' AS resultaat;
