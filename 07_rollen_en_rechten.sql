/* =====================================================================
   07_rollen_en_rechten.sql

   Hier wordt het onderscheid tussen publieke en afgeschermde gegevens
   afgedwongen. Niet in de applicatie, maar in de databank zelf: een
   fout in de website kan dan geen persoonsgegevens lekken.

   Vier rollen:
     syntra_web        de website. Ziet ALLEEN de vw_pub-views.
     syntra_lesgever   lesgever. Ziet lesopdrachten en resultaten.
     syntra_medewerker administratie. Ziet contactgegevens en
                       inschrijvingen, maar geen rijksregisternummers,
                       IBAN's of uurtarieven.
     syntra_admin      functioneel beheerder. Ziet alles.

   Het zijn groepsrollen zonder login. Per applicatie maak je een
   loginrol aan en geef je die de juiste groep (zie onderaan).
   ===================================================================== */


/* ---------------------------------------------------------------------
   1. ROLLEN AANMAKEN
   Een DO-blok laat toe eerst te controleren of de rol al bestaat.
   Rollen bestaan op serverniveau, niet per database, dus ze blijven
   staan als je de database opnieuw aanmaakt.
   --------------------------------------------------------------------- */

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'syntra_web') THEN
        CREATE ROLE syntra_web NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'syntra_lesgever') THEN
        CREATE ROLE syntra_lesgever NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'syntra_medewerker') THEN
        CREATE ROLE syntra_medewerker NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'syntra_admin') THEN
        CREATE ROLE syntra_admin NOLOGIN;
    END IF;
END;
$$;


/* ---------------------------------------------------------------------
   2. ALLES EERST DICHTZETTEN
   --------------------------------------------------------------------- */

REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM syntra_web, syntra_lesgever, syntra_medewerker;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM syntra_web, syntra_lesgever, syntra_medewerker;


/* ---------------------------------------------------------------------
   3. SYNTRA_WEB - alleen de publieke views
   Een view draait met de rechten van de eigenaar. De website kan de
   views dus lezen zonder ook maar een recht op de tabel persoon.
   --------------------------------------------------------------------- */

GRANT USAGE ON SCHEMA public TO syntra_web;

GRANT SELECT ON vw_pub_categorie
                , vw_pub_subcategorie
                , vw_pub_opleiding
                , vw_pub_programma
                , vw_pub_startmoment
                , vw_pub_lesgever
    TO syntra_web;

-- De view vw_pub_startmoment gebruikt fn_vrije_plaatsen.
GRANT EXECUTE ON FUNCTION fn_vrije_plaatsen(INT)      TO syntra_web;
GRANT EXECUTE ON FUNCTION fn_aantal_ingeschreven(INT) TO syntra_web;


/* ---------------------------------------------------------------------
   4. SYNTRA_MEDEWERKER - de administratie
   --------------------------------------------------------------------- */

GRANT USAGE ON SCHEMA public TO syntra_medewerker;

-- Catalogus mag beheerd worden.
GRANT SELECT, INSERT, UPDATE ON categorie, subcategorie, opleiding, module,
                                campus, opleidingsperiode, periode_module,
                                periode_module_lesgever
    TO syntra_medewerker;

-- Inschrijvingen, resultaten en betalingen ook.
GRANT SELECT, INSERT, UPDATE ON inschrijving, inschrijving_module,
                                evaluatie, betaling
    TO syntra_medewerker;
GRANT SELECT ON inschrijving_log TO syntra_medewerker;

-- KOLOMRECHTEN: contactgegevens mogen, identificatiegegevens niet.
-- Merk op dat rijksregisternr hier bewust ontbreekt.
GRANT SELECT (persoon_id, voornaam, familienaam, email, telefoon,
              geboortedatum, adres, postcode, gemeente, land)
    ON persoon TO syntra_medewerker;
GRANT INSERT, UPDATE (voornaam, familienaam, email, telefoon,
                      adres, postcode, gemeente, land)
    ON persoon TO syntra_medewerker;

GRANT SELECT, INSERT, UPDATE ON cursist TO syntra_medewerker;

-- Van een lesgever mag de administratie de publieke gegevens zien,
-- maar niet het uurtarief, de IBAN of het ondernemingsnummer.
GRANT SELECT (lesgever_id, lesgevernummer, publieke_bio, foto_url,
              linkedin_url, zichtbaar_op_web, in_dienst_sinds, uit_dienst_op)
    ON lesgever TO syntra_medewerker;

-- Alle views en functies mogen gebruikt worden.
GRANT SELECT   ON ALL TABLES    IN SCHEMA public TO syntra_medewerker;
GRANT EXECUTE  ON ALL FUNCTIONS IN SCHEMA public TO syntra_medewerker;
GRANT EXECUTE  ON ALL PROCEDURES IN SCHEMA public TO syntra_medewerker;
GRANT USAGE    ON ALL SEQUENCES IN SCHEMA public TO syntra_medewerker;

-- De GRANT SELECT ON ALL TABLES hierboven zou ook de gevoelige kolommen
-- terug openzetten. Die halen we er dus weer af.
REVOKE SELECT ON persoon  FROM syntra_medewerker;
REVOKE SELECT ON lesgever FROM syntra_medewerker;
GRANT  SELECT (persoon_id, voornaam, familienaam, email, telefoon,
               geboortedatum, adres, postcode, gemeente, land)
    ON persoon TO syntra_medewerker;
GRANT  SELECT (lesgever_id, lesgevernummer, publieke_bio, foto_url,
               linkedin_url, zichtbaar_op_web, in_dienst_sinds, uit_dienst_op)
    ON lesgever TO syntra_medewerker;


/* ---------------------------------------------------------------------
   5. SYNTRA_LESGEVER - lesopdrachten en resultaten
   --------------------------------------------------------------------- */

GRANT USAGE ON SCHEMA public TO syntra_lesgever;

GRANT SELECT ON vw_pub_categorie, vw_pub_subcategorie, vw_pub_opleiding,
                vw_pub_programma, vw_pub_startmoment, vw_pub_lesgever,
                vw_int_lesopdracht, vw_int_klaslijst, vw_int_resultaat
    TO syntra_lesgever;

-- Een lesgever mag punten ingeven, maar niets aan de catalogus wijzigen.
GRANT EXECUTE ON PROCEDURE sp_evaluatie_registreren(INT, VARCHAR, DECIMAL, VARCHAR, VARCHAR, DATE)
    TO syntra_lesgever;
GRANT SELECT, INSERT ON evaluatie TO syntra_lesgever;
GRANT SELECT ON inschrijving, inschrijving_module, periode_module, module,
                opleidingsperiode, opleiding, campus
    TO syntra_lesgever;
GRANT EXECUTE ON FUNCTION fn_module_geslaagd(INT), fn_openstaand_saldo(INT),
                          fn_vrije_plaatsen(INT), fn_aantal_ingeschreven(INT),
                          fn_leeftijd(DATE)
    TO syntra_lesgever;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO syntra_lesgever;


/* ---------------------------------------------------------------------
   6. SYNTRA_ADMIN - volledige toegang
   --------------------------------------------------------------------- */

GRANT USAGE ON SCHEMA public TO syntra_admin;
GRANT ALL     ON ALL TABLES     IN SCHEMA public TO syntra_admin;
GRANT ALL     ON ALL SEQUENCES  IN SCHEMA public TO syntra_admin;
GRANT EXECUTE ON ALL FUNCTIONS  IN SCHEMA public TO syntra_admin;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA public TO syntra_admin;

-- Een admin kan alles wat een medewerker kan.
GRANT syntra_medewerker TO syntra_admin;


/* ---------------------------------------------------------------------
   7. LOGINROLLEN
   Voor de test in 08_testscript.sql maken we een gebruiker aan die de
   website voorstelt. In productie geef je die uiteraard een echt
   wachtwoord en zet je hem in een aparte connectiestring.
   --------------------------------------------------------------------- */

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'website_gebruiker') THEN
        CREATE ROLE website_gebruiker LOGIN PASSWORD 'website';
    END IF;
END;
$$;

GRANT syntra_web TO website_gebruiker;


/* ---------------------------------------------------------------------
   CONTROLE
   Welke rol mag wat op de tabel persoon en op de publieke views?
   --------------------------------------------------------------------- */

SELECT grantee AS rol, table_name AS object, privilege_type AS recht
FROM   information_schema.role_table_grants
WHERE  table_schema = 'public'
  AND  grantee LIKE 'syntra%'
  AND  table_name IN ('persoon', 'lesgever', 'vw_pub_opleiding', 'vw_int_klaslijst')
ORDER  BY grantee, table_name, privilege_type;

-- Welke kolommen van persoon mag de medewerker zien?
SELECT grantee AS rol, column_name AS kolom, privilege_type AS recht
FROM   information_schema.column_privileges
WHERE  table_name = 'persoon'
  AND  grantee = 'syntra_medewerker'
ORDER  BY column_name, privilege_type;
