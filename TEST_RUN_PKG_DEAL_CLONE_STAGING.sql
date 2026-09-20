/*==============================================================================
  TEST RUN SCRIPT - PKG_DEAL_CLONE_STAGING
  Run PKG_DEAL_CLONE_STAGING.sql first (no sequence is created by that
  script anymore - you must supply the real REFCEXREM sequence name below).
==============================================================================*/

SET SERVEROUTPUT ON SIZE UNLIMITED


--------------------------------------------------------------------------------
-- STEP 0: If you don't already know the sequence psifa42p uses for
-- REFCEXREM, this lists candidates by name as a starting point (not a
-- guaranteed answer - confirm with your DBA or psifa42p's config/docs).
--------------------------------------------------------------------------------
SELECT sequence_owner, sequence_name, last_number
  FROM all_sequences
 WHERE sequence_name LIKE '%REM%' OR sequence_name LIKE '%DEAL%'
    OR sequence_name LIKE '%INT%' OR sequence_name LIKE '%TAR%'
 ORDER BY sequence_name;


--------------------------------------------------------------------------------
-- STEP 1: Set the real sequence name once you've confirmed it, then run
-- everything in one call. This single EXEC does all of the following, in
-- order, printing each step to DBMS_OUTPUT:
--   1. Validates the hardcoded Scan deal-type list against TRA_PARPOSTES
--   2. Evaluates every eligible candidate deal/item and prints it as it's tested
--   3. Stages each one into INTREM using the sequence you supply
--   4. Prints a final summary (candidates evaluated vs. rows staged)
--------------------------------------------------------------------------------
DEFINE refcexrem_sequence = 'REPLACE_WITH_REAL_SEQUENCE_NAME'
DEFINE test_run_tag       = 'TEST_RUN_001'

BEGIN
  PKG_DEAL_CLONE_STAGING.CLONE_ELIGIBLE_SCAN_DEALS(
    P_REFCEXREM_SEQUENCE => '&refcexrem_sequence',
    P_RUN_TAG             => '&test_run_tag'
  );
END;
/

-- Expected output shape:
--   === PKG_DEAL_CLONE_STAGING.CLONE_ELIGIBLE_SCAN_DEALS - run tag TEST_RUN_001 ===
--   Using REFCEXREM sequence: <your sequence name>
--     [validate] OK: TRA_PARPOSTES '%SCAN%' entries match the hardcoded deal-type list.
--   --- Evaluating candidates ---
--     [testing] deal=... (...) mfg_vendor=... type=... item_root=.../LV=... site=... window=...  amount=...
--       [staged] -> REFCEXREM=..., REFCEXGAT=...
--     ... (one pair of lines per eligible deal/item) ...
--   === Complete: N candidate(s) evaluated, N INTREM row(s) staged, run tag TEST_RUN_001 ===
--
-- If STEP 0 didn't return an obviously correct sequence, running this with
-- a wrong name will fail loudly with ORA-20001 (not silently insert bad
-- data) - that's intentional, see GET_NEXT_EXTERNAL_CODE in the package.


--------------------------------------------------------------------------------
-- STEP 2: Verify the staged rows.
--------------------------------------------------------------------------------
SELECT REFCEXREM, REFCNUF, REFCNUM, REFCEXGAT, REFTREM, REFVUP,
       REFDDEB, REFDFIN, REFSITE, REFGSITE, REFCOMM, REFNLIG
  FROM INTREM
 WHERE REFFICH = 'CLONE_STAGING_' || '&test_run_tag'
 ORDER BY REFNLIG;

-- Row count should match the "N candidate(s) evaluated" figure from Step 1's
-- final summary line exactly (one INTREM row per eligible deal/item):
SELECT COUNT(*) AS staged_row_count
  FROM INTREM
 WHERE REFFICH = 'CLONE_STAGING_' || '&test_run_tag';


--------------------------------------------------------------------------------
-- STEP 3: Cleanup, so the same source data can be re-tested. Only do this
-- in a test environment - in a real run, INTREM rows are meant to be
-- consumed by psifa42p, not deleted.
--------------------------------------------------------------------------------
-- DELETE FROM INTREM WHERE REFFICH = 'CLONE_STAGING_' || '&test_run_tag';
-- COMMIT;
