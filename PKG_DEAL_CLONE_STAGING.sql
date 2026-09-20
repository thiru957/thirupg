/*==============================================================================
  PKG_DEAL_CLONE_STAGING
  Built fresh from: the BRD (AWG_Deals_Cloning_script_requirements_3.docx),
  its reviewer comments on psifa42p/TAREMISE/TARRIST/TARGRAR/TARGRUL, and the
  eligibility query supplied directly.

  REVISION NOTE (this version)
  ----------------------------------------------------------------------------
  - No longer creates its own sequence. REFCEXREM (and the new item-group
    code, REFCEXGAT) are now generated from whatever sequence psifa42p
    itself uses, so both stay aligned and never collide.
  - psifa42p is a Pro*C program (per the BRD), not a PL/SQL stored
    procedure - its source is not visible from inside the database (it
    won't show up in ALL_SOURCE/USER_SOURCE), so this package cannot look
    the sequence name up on its own. CLONE_ELIGIBLE_SCAN_DEALS now takes
    P_REFCEXREM_SEQUENCE as a REQUIRED parameter (no default) rather than
    hardcoding a guessed name - confirm the real name with your DBA or the
    psifa42p documentation/config before running this for real. The
    diagnostic query at the bottom of this header lists sequences in the
    schema as a starting point for finding it.
  - CLONE_ELIGIBLE_SCAN_DEALS now runs everything in one call: it validates
    the Scan deal-type list against TRA_PARPOSTES, then prints each
    candidate record it evaluates via DBMS_OUTPUT as it processes it, then
    stages it into INTREM, then prints a final summary. One EXEC is enough
    to see exactly what was tested and what happened to each record.

  FINDING THE REAL SEQUENCE NAME (run as a DBA or schema owner):
    SELECT sequence_owner, sequence_name, last_number
      FROM all_sequences
     WHERE sequence_name LIKE '%REM%' OR sequence_name LIKE '%DEAL%'
        OR sequence_name LIKE '%INT%' OR sequence_name LIKE '%TAR%'
     ORDER BY sequence_name;
  If psifa42p's config/parameter files are accessible on the application
  server's filesystem, they may also name the sequence directly - that's a
  more reliable source than guessing from naming conventions alone.

  TABLES USED (only ones confirmed by supplied DDL or by explicit use in
  your eligibility query - unchanged from the prior revision)
  ----------------------------------------------------------------------------
    TAREMISE, FOUDGENE, TARRIST, TARGRAR, TARGRUL, ARTUC, TARPRIX,
    TRA_PARPOSTES, INTREM

  OPEN ITEMS (unchanged - still not resolved by anything supplied so far):
  ----------------------------------------------------------------------------
    - REFCNUM (commercial contract EXTERNAL code): no source table
      confirmed. GET_CONTRACT_EXT_CODE returns TO_CHAR(internal id) as a
      placeholder - replace once the real source is identified.
    - REFCEXR (item root EXTERNAL code): nullable, left NULL - no source
      confirmed.
    - REFFLAG: NOT NULL, defaulted to 1 - Table 1265's real value domain
      has not been supplied.
    - No re-clone/duplicate-prevention key exists (BRD: no persisted link
      between an MFG deal and its AWG clone). Re-running against the same
      source data will stage duplicates - there is no dedup guard.
==============================================================================*/


--------------------------------------------------------------------------------
-- PACKAGE SPEC
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE PKG_DEAL_CLONE_STAGING AUTHID CURRENT_USER IS

  C_AWG_VENDOR_INTERNAL CONSTANT NUMBER  := 6514;      -- FOUDGENE.FOUCFIN for AWG, confirmed by your query
  C_AWG_VENDOR_EXTERNAL CONSTANT VARCHAR2(10) := '124230';  -- FOUDGENE.FOUCNUF for AWG, confirmed by your query
  C_AWG_DEFAULT_NETWORK CONSTANT NUMBER  := 10001;     -- BRD reviewer comments: MFG node 16000 / AWG node 10001

  C_PARTABL_DEALTYPE CONSTANT NUMBER := 101;
  C_LANGUE_KV        CONSTANT VARCHAR2(5) := 'KV';

  -- One-call entry point: validates deal types, evaluates every eligible
  -- candidate (printing each one via DBMS_OUTPUT as it's tested), stages it
  -- into INTREM using P_REFCEXREM_SEQUENCE for the new codes, and prints a
  -- final summary. P_REFCEXREM_SEQUENCE has no default on purpose - see
  -- the package header on why this can't be safely guessed.
  PROCEDURE CLONE_ELIGIBLE_SCAN_DEALS(
    P_REFCEXREM_SEQUENCE IN VARCHAR2,
    P_RUN_TAG             IN VARCHAR2 DEFAULT TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS')
  );

  -- Cross-checks the hardcoded Scan deal-type list (140/141/142/280/281/282)
  -- against a live TRA_PARPOSTES '%SCAN%' lookup. Called automatically at
  -- the start of CLONE_ELIGIBLE_SCAN_DEALS; also callable standalone.
  PROCEDURE VALIDATE_SCAN_DEALTYPES;

  -- Placeholder for the commercial contract external code lookup - see
  -- "OPEN ITEMS" in the package header.
  FUNCTION GET_CONTRACT_EXT_CODE(P_CONTRACT_INTERNAL IN NUMBER) RETURN VARCHAR2;

  -- Fetches NEXTVAL from the caller-named sequence via dynamic SQL (a
  -- sequence name can't be bound as a regular PL/SQL variable in static
  -- SQL, hence EXECUTE IMMEDIATE here). Exposed publicly so it can be
  -- tested in isolation before running the full clone.
  FUNCTION GET_NEXT_EXTERNAL_CODE(P_SEQUENCE_NAME IN VARCHAR2) RETURN VARCHAR2;

END PKG_DEAL_CLONE_STAGING;
/


--------------------------------------------------------------------------------
-- PACKAGE BODY
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY PKG_DEAL_CLONE_STAGING IS

  ------------------------------------------------------------------------------
  -- GET_CONTRACT_EXT_CODE - see OPEN ITEMS at the top of this file.
  ------------------------------------------------------------------------------
  FUNCTION GET_CONTRACT_EXT_CODE(P_CONTRACT_INTERNAL IN NUMBER) RETURN VARCHAR2 IS
  BEGIN
    RETURN TO_CHAR(P_CONTRACT_INTERNAL);  -- TODO: replace with real external-code lookup once confirmed
  END GET_CONTRACT_EXT_CODE;


  ------------------------------------------------------------------------------
  -- GET_NEXT_EXTERNAL_CODE - dynamic SQL wrapper so the sequence name can
  -- be supplied at runtime rather than hardcoded. DBMS_ASSERT guards
  -- against SQL injection through the sequence-name parameter. Fails
  -- loudly (not silently returning NULL) if the named sequence doesn't
  -- exist or isn't accessible, since a bad sequence name here means every
  -- downstream INTREM row would get a wrong/colliding code.
  ------------------------------------------------------------------------------
  FUNCTION GET_NEXT_EXTERNAL_CODE(P_SEQUENCE_NAME IN VARCHAR2) RETURN VARCHAR2 IS
    L_VAL NUMBER;
  BEGIN
    EXECUTE IMMEDIATE 'SELECT ' || DBMS_ASSERT.SQL_OBJECT_NAME(P_SEQUENCE_NAME) || '.NEXTVAL FROM DUAL'
      INTO L_VAL;
    RETURN TO_CHAR(L_VAL);
  EXCEPTION
    WHEN OTHERS THEN
      RAISE_APPLICATION_ERROR(-20001,
        'Could not fetch NEXTVAL from sequence "' || P_SEQUENCE_NAME || '" - confirm this is the ' ||
        'real sequence psifa42p uses (see the diagnostic query in this package''s header comment ' ||
        'if you need help finding it). Original error: ' || SQLERRM);
  END GET_NEXT_EXTERNAL_CODE;


  ------------------------------------------------------------------------------
  -- VALIDATE_SCAN_DEALTYPES - runs the BRD reviewer comment's literal query
  -- and compares it to the hardcoded list used in CLONE_ELIGIBLE_SCAN_DEALS.
  ------------------------------------------------------------------------------
  PROCEDURE VALIDATE_SCAN_DEALTYPES IS
    L_MISMATCH_COUNT PLS_INTEGER := 0;
  BEGIN
    FOR R IN (
      SELECT T.TPARPOST, T.TPARLIBC, T.TPARLIBL
        FROM TRA_PARPOSTES T
       WHERE T.TPARCMAG = 0
         AND T.TPARTABL = C_PARTABL_DEALTYPE
         AND T.LANGUE   = C_LANGUE_KV
         AND UPPER(T.TPARLIBL) LIKE '%SCAN%'
    ) LOOP
      IF R.TPARPOST NOT IN (140, 141, 142, 280, 281, 282) THEN
        L_MISMATCH_COUNT := L_MISMATCH_COUNT + 1;
        DBMS_OUTPUT.PUT_LINE('WARNING: TRA_PARPOSTES has a ''SCAN'' entry (' ||
                              R.TPARPOST || ' - ' || R.TPARLIBL ||
                              ') not in the hardcoded Scan deal-type list used by CLONE_ELIGIBLE_SCAN_DEALS.');
      END IF;
    END LOOP;

    IF L_MISMATCH_COUNT = 0 THEN
      DBMS_OUTPUT.PUT_LINE('  [validate] OK: TRA_PARPOSTES ''%SCAN%'' entries match the hardcoded deal-type list.');
    END IF;
  END VALIDATE_SCAN_DEALTYPES;


  ------------------------------------------------------------------------------
  -- CLONE_ELIGIBLE_SCAN_DEALS
  -- The cursor below is your supplied eligibility query, unchanged in its
  -- join and filter logic, extended only with the additional columns
  -- needed to populate INTREM.
  ------------------------------------------------------------------------------
  PROCEDURE CLONE_ELIGIBLE_SCAN_DEALS(
    P_REFCEXREM_SEQUENCE IN VARCHAR2,
    P_RUN_TAG             IN VARCHAR2 DEFAULT TO_CHAR(SYSDATE, 'YYYYMMDDHH24MISS')
  ) IS

    CURSOR C_ELIGIBLE IS
      SELECT
          a.trecinrem,
          a.trecexrem,
          a.trecfin,
          a.treccin,
          a.trecomm,
          a.treddeb,
          a.tredfin,
          a.tretrem,
          a.treregl,
          a.treglob,
          a.treordc,
          a.treorda,
          a.trebase,
          a.tretva,
          a.trevalphom,
          a.treproach,
          c.trisite,
          c.triurem,
          c.triuapp,
          c.trirepf,
          d.tgacingat AS item_group_internal,
          e.tgucinr   AS item_root_internal,
          e.tguseqvl  AS item_lv_internal
      FROM
          taremise a,
          foudgene b,
          tarrist  c,
          targrar  d,
          targrul  e
      WHERE
              a.trecfin = b.foucfin
          AND b.foucnuf <> C_AWG_VENDOR_EXTERNAL
          AND b.foutype = 1 -- only consider external vendor (MFG)
          AND a.tretrem IN ( 281, 282, 280, 141, 142, 140 )
          AND trunc(sysdate) BETWEEN a.treddeb AND a.tredfin
          AND a.trecinrem = c.tricinrem
          AND trunc(sysdate) BETWEEN c.triddeb AND c.tridfin
          AND d.tgacingat = a.trecingat
          AND d.tgacingat = e.tgucingat
          AND trunc(sysdate) BETWEEN d.tgaddeb AND d.tgadfin
          AND trunc(sysdate) BETWEEN e.tguddeb AND e.tgudfin
          AND EXISTS (SELECT 1 FROM artuc h WHERE
                      h.aracfin = C_AWG_VENDOR_INTERNAL
                  AND h.aracinr = e.tgucinr
                  AND trunc(sysdate) BETWEEN h.araddeb AND h.aradfin
          ) --matching at cinr level assume 1 root - 1 sv structure
          AND EXISTS (SELECT 1
              FROM
                  tarprix i
              WHERE
                      i.tapcfin = C_AWG_VENDOR_INTERNAL
                  AND i.tapcinr = e.tgucinr
                  AND trunc(sysdate) BETWEEN i.tapddeb AND i.tapdfin
          ) --matching at cinr level assume 1 root - 1 sv structure
      ORDER BY
          a.trecexrem ASC;

    L_NEW_DEAL_CODE  VARCHAR2(13);
    L_NEW_GROUP_CODE VARCHAR2(13);
    L_CONTRACT_EXT   VARCHAR2(10);
    L_LINE_NO        NUMBER := 0;
    L_ROW_COUNT      PLS_INTEGER := 0;
    L_CANDIDATE_COUNT PLS_INTEGER := 0;

  BEGIN
    DBMS_OUTPUT.PUT_LINE('=== PKG_DEAL_CLONE_STAGING.CLONE_ELIGIBLE_SCAN_DEALS - run tag ' || P_RUN_TAG || ' ===');
    DBMS_OUTPUT.PUT_LINE('Using REFCEXREM sequence: ' || P_REFCEXREM_SEQUENCE);

    VALIDATE_SCAN_DEALTYPES;

    DBMS_OUTPUT.PUT_LINE('--- Evaluating candidates ---');

    FOR R IN C_ELIGIBLE LOOP

      L_CANDIDATE_COUNT := L_CANDIDATE_COUNT + 1;
      DBMS_OUTPUT.PUT_LINE('  [testing] deal=' || R.TRECINREM || ' (' || R.TRECEXREM || ')' ||
                            ' mfg_vendor=' || R.TRECFIN ||
                            ' type=' || R.TRETREM ||
                            ' item_root=' || R.ITEM_ROOT_INTERNAL || '/LV=' || R.ITEM_LV_INTERNAL ||
                            ' site=' || R.TRISITE ||
                            ' window=' || TO_CHAR(R.TREDDEB, 'YYYY-MM-DD') || '..' || TO_CHAR(R.TREDFIN, 'YYYY-MM-DD') ||
                            ' amount=' || R.TRIREPF);

      L_LINE_NO := L_LINE_NO + 1;
      L_NEW_DEAL_CODE  := GET_NEXT_EXTERNAL_CODE(P_REFCEXREM_SEQUENCE);
      L_NEW_GROUP_CODE := GET_NEXT_EXTERNAL_CODE(P_REFCEXREM_SEQUENCE);
      L_CONTRACT_EXT   := GET_CONTRACT_EXT_CODE(R.TRECCIN);

      INSERT INTO INTREM (
        REFCEXREM, REFCNUF, REFCNUM, REFCEXGAT, REFCEXR, REFCEXVL,
        REFTREM, REFREGL, REFGLOB, REFORDC, REFORDA, REFBASE,
        REFREDEB, REFREFIN, REFDDEB, REFDFIN,
        REFUREM, REFUAPP, REFVUP,
        REFSITE, REFGSITE, REFCOMM,
        REFCTVA, REFPROACH, REFPALHOM,
        REFACT, REFFLAG, REFLGFI, REFTRT, REFDTRT, REFDCRE, REFUTIL, REFFICH, REFNLIG
      ) VALUES (
        L_NEW_DEAL_CODE, C_AWG_VENDOR_EXTERNAL, L_CONTRACT_EXT, L_NEW_GROUP_CODE,
        NULL,                                    -- REFCEXR: item root external code - no source confirmed, left NULL (nullable column)
        R.ITEM_LV_INTERNAL,                       -- REFCEXVL: no external-code source confirmed either; internal LV passed through as the closest available value
        R.TRETREM, R.TREREGL, R.TREGLOB, R.TREORDC, R.TREORDA, R.TREBASE,
        R.TREDDEB, R.TREDFIN, R.TREDDEB, R.TREDFIN,
        R.TRIUREM, R.TRIUAPP, R.TRIREPF,          -- NOTE: TARRIST.TRIREPF is NUMBER(15,5) but INTREM.REFVUP is
                                                    -- NUMBER(8,3) - a value with >5 integer digits or needing >3
                                                    -- decimal places will raise ORA-01438 here. Not rounded/
                                                    -- truncated automatically since that would silently change
                                                    -- the deal amount; if this fires, decide with the business
                                                    -- whether to round (and to how many places) before staging.
        R.TRISITE, C_AWG_DEFAULT_NETWORK, R.TRECOMM,
        R.TRETVA, R.TREPROACH, R.TREVALPHOM,
        1,                                        -- REFACT = 1 (create)
        1,                                        -- REFFLAG - TODO: confirm real value against Table 1265; defaulted to 1
        L_LINE_NO,
        0,                                        -- REFTRT = 0 (untreated, pending psifa42p pickup)
        SYSDATE,                                  -- REFDTRT - TODO: confirm whether psifa42p expects this pre-populated or defaulted; SYSDATE used as a placeholder, not a claim the record is already processed
        SYSDATE,                                  -- REFDCRE
        USER,                                     -- REFUTIL
        'CLONE_STAGING_' || P_RUN_TAG,             -- REFFICH
        L_LINE_NO                                  -- REFNLIG
      );

      L_ROW_COUNT := L_ROW_COUNT + 1;
      DBMS_OUTPUT.PUT_LINE('    [staged] -> REFCEXREM=' || L_NEW_DEAL_CODE || ', REFCEXGAT=' || L_NEW_GROUP_CODE);

    END LOOP;

    IF L_CANDIDATE_COUNT = 0 THEN
      DBMS_OUTPUT.PUT_LINE('  (no candidates matched the eligibility query - nothing to stage)');
    END IF;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('=== Complete: ' || L_CANDIDATE_COUNT || ' candidate(s) evaluated, ' ||
                          L_ROW_COUNT || ' INTREM row(s) staged, run tag ' || P_RUN_TAG || ' ===');

  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('CLONE_ELIGIBLE_SCAN_DEALS failed: ' || SQLERRM);
      RAISE;
  END CLONE_ELIGIBLE_SCAN_DEALS;

END PKG_DEAL_CLONE_STAGING;
/
