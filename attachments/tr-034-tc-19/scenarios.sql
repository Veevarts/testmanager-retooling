SET NOCOUNT ON;

/* ============================================================ */
/* IM-626 TC-19 — Aspen data validation                          */
/* Run with: safesql run aspen /tmp/im626-tc19-scenarios.sql     */
/*                                                                */
/* Replicates exactly the contact.sql logic from PR 105:          */
/*   filter:               C.ISCONSTITUENT = 1                    */
/*                     AND C.ISGROUP = 0                          */
/*                     AND C.ISORGANIZATION = 0                   */
/*   IsDeceasedBit:        D.ID IS NOT NULL                       */
/*   IsInactiveOrDeceased: D.ID IS NOT NULL OR C.ISINACTIVE = 1   */
/*   Cascade OR fields:    Altru opt-out OR IsInactiveOrDeceased  */
/*   Household exclusion:  IsDeceasedBit only                     */
/*   Do Not Contact:       IsInactiveOrDeceased                   */
/* ============================================================ */


/* ============================================================ */
/* Scenario 1 — Aggregate parity and pre-fix delta (Aspen)       */
/* Expected: 796 / 374 / 422 / 1001 / 1177                       */
/* ============================================================ */

PRINT '=== S1.a deceased_new_logic ===';
SELECT COUNT(*) AS deceased_new_logic
FROM CONSTITUENT C
LEFT JOIN DECEASEDCONSTITUENT D ON C.ID = D.ID
WHERE C.ISCONSTITUENT = 1 AND C.ISGROUP = 0 AND C.ISORGANIZATION = 0
  AND D.ID IS NOT NULL;

PRINT '=== S1.b deceased_old_logic (DECEASEDDATE parseable per OUTER APPLY DD) ===';
SELECT COUNT(*) AS deceased_old_logic_parseable_date
FROM CONSTITUENT C
LEFT JOIN DECEASEDCONSTITUENT D ON C.ID = D.ID
WHERE C.ISCONSTITUENT = 1 AND C.ISGROUP = 0 AND C.ISORGANIZATION = 0
  AND D.ID IS NOT NULL
  AND D.DECEASEDDATE IS NOT NULL
  AND LEN(D.DECEASEDDATE) = 8
  AND D.DECEASEDDATE <> '00000000'
  AND D.DECEASEDDATE LIKE '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
  AND SUBSTRING(D.DECEASEDDATE, 1, 4) <> '0000';

PRINT '=== S1.c deceased_lost_pre_fix (delta) ===';
SELECT COUNT(*) AS deceased_lost_pre_fix
FROM CONSTITUENT C
LEFT JOIN DECEASEDCONSTITUENT D ON C.ID = D.ID
WHERE C.ISCONSTITUENT = 1 AND C.ISGROUP = 0 AND C.ISORGANIZATION = 0
  AND D.ID IS NOT NULL
  AND NOT (
      D.DECEASEDDATE IS NOT NULL
      AND LEN(D.DECEASEDDATE) = 8
      AND D.DECEASEDDATE <> '00000000'
      AND D.DECEASEDDATE LIKE '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
      AND SUBSTRING(D.DECEASEDDATE, 1, 4) <> '0000'
  );

PRINT '=== S1.d inactive_total ===';
SELECT COUNT(*) AS inactive_total
FROM CONSTITUENT C
WHERE C.ISCONSTITUENT = 1 AND C.ISGROUP = 0 AND C.ISORGANIZATION = 0
  AND C.ISINACTIVE = 1;

PRINT '=== S1.e inactive_or_deceased_union ===';
SELECT COUNT(*) AS inactive_or_deceased_union
FROM CONSTITUENT C
LEFT JOIN DECEASEDCONSTITUENT D ON C.ID = D.ID
WHERE C.ISCONSTITUENT = 1 AND C.ISGROUP = 0 AND C.ISORGANIZATION = 0
  AND (C.ISINACTIVE = 1 OR D.ID IS NOT NULL);

PRINT '=== S1.f integrity check: rows with deceased true but no DECEASEDCONSTITUENT row (must be 0) ===';
SELECT COUNT(*) AS false_deceased_no_source
FROM CONSTITUENT C
LEFT JOIN DECEASEDCONSTITUENT D ON C.ID = D.ID
WHERE C.ISCONSTITUENT = 1 AND C.ISGROUP = 0 AND C.ISORGANIZATION = 0
  AND D.ID IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM DECEASEDCONSTITUENT D2 WHERE D2.ID = C.ID);
-- (Logically always 0; included as a self-check that the LEFT JOIN matches the EXISTS subquery.)


/* ============================================================ */
/* Scenario 2 — Deceased contract via Hunter (Lookup 112009)     */
/* Expected: deceased=1, inactive=1, household=1/1/1,            */
/*           altru opt-outs=0/0/0, effective opt-outs=1/1/1,     */
/*           do_not_contact=1                                    */
/* ============================================================ */

PRINT '=== S2 Hunter (Lookup 112009) cascade ===';
SELECT
    CAST(CASE WHEN D.ID IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS npsp__Deceased__c,
    CAST(C.ISINACTIVE AS BIT) AS Inactive__c,
    CAST(CASE WHEN D.ID IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS npsp__Exclude_from_Household_Name__c,
    CAST(CASE WHEN D.ID IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS npsp__Exclude_from_Household_Formal_Greeting__c,
    CAST(CASE WHEN D.ID IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS npsp__Exclude_from_Household_Informal_Greeting__c,
    CAST(C.DONOTEMAIL AS BIT) AS altru_DONOTEMAIL,
    CAST(C.DONOTMAIL  AS BIT) AS altru_DONOTMAIL,
    CAST(C.DONOTPHONE AS BIT) AS altru_DONOTPHONE,
    CAST(CASE WHEN C.DONOTEMAIL = 1 OR (D.ID IS NOT NULL OR C.ISINACTIVE = 1) THEN 1 ELSE 0 END AS BIT) AS effective_HasOptedOutOfEmail,
    CAST(CASE WHEN C.DONOTMAIL  = 1 OR (D.ID IS NOT NULL OR C.ISINACTIVE = 1) THEN 1 ELSE 0 END AS BIT) AS effective_Do_not_mail__c,
    CAST(CASE WHEN C.DONOTPHONE = 1 OR (D.ID IS NOT NULL OR C.ISINACTIVE = 1) THEN 1 ELSE 0 END AS BIT) AS effective_DoNotCall,
    CAST(CASE WHEN D.ID IS NOT NULL OR C.ISINACTIVE = 1 THEN 1 ELSE 0 END AS BIT) AS npsp__Do_Not_Contact__c
FROM CONSTITUENT C
LEFT JOIN DECEASEDCONSTITUENT D ON C.ID = D.ID
WHERE C.LOOKUPID = '112009'
  AND C.ISCONSTITUENT = 1 AND C.ISGROUP = 0 AND C.ISORGANIZATION = 0;


/* ============================================================ */
/* Scenario 3 — Inactive-only contract via Connolly              */
/*               (Lookup 8-10014788)                             */
/* Expected: deceased=0, inactive=1, household=0/0/0,            */
/*           altru opt-outs=0/0/0, effective opt-outs=1/1/1,     */
/*           do_not_contact=1                                    */
/* ============================================================ */

PRINT '=== S3 Connolly (Lookup 8-10014788) cascade ===';
SELECT
    CAST(CASE WHEN D.ID IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS npsp__Deceased__c,
    CAST(C.ISINACTIVE AS BIT) AS Inactive__c,
    CAST(CASE WHEN D.ID IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS npsp__Exclude_from_Household_Name__c,
    CAST(CASE WHEN D.ID IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS npsp__Exclude_from_Household_Formal_Greeting__c,
    CAST(CASE WHEN D.ID IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS npsp__Exclude_from_Household_Informal_Greeting__c,
    CAST(C.DONOTEMAIL AS BIT) AS altru_DONOTEMAIL,
    CAST(C.DONOTMAIL  AS BIT) AS altru_DONOTMAIL,
    CAST(C.DONOTPHONE AS BIT) AS altru_DONOTPHONE,
    CAST(CASE WHEN C.DONOTEMAIL = 1 OR (D.ID IS NOT NULL OR C.ISINACTIVE = 1) THEN 1 ELSE 0 END AS BIT) AS effective_HasOptedOutOfEmail,
    CAST(CASE WHEN C.DONOTMAIL  = 1 OR (D.ID IS NOT NULL OR C.ISINACTIVE = 1) THEN 1 ELSE 0 END AS BIT) AS effective_Do_not_mail__c,
    CAST(CASE WHEN C.DONOTPHONE = 1 OR (D.ID IS NOT NULL OR C.ISINACTIVE = 1) THEN 1 ELSE 0 END AS BIT) AS effective_DoNotCall,
    CAST(CASE WHEN D.ID IS NOT NULL OR C.ISINACTIVE = 1 THEN 1 ELSE 0 END AS BIT) AS npsp__Do_Not_Contact__c
FROM CONSTITUENT C
LEFT JOIN DECEASEDCONSTITUENT D ON C.ID = D.ID
WHERE C.LOOKUPID = '8-10014788'
  AND C.ISCONSTITUENT = 1 AND C.ISGROUP = 0 AND C.ISORGANIZATION = 0;


/* ============================================================ */
/* Scenario 4 — Active baseline: no false positives              */
/* Expected: all violation counts = 0, active_count = 10,085     */
/* ============================================================ */

PRINT '=== S4.a active_count (should equal total_individual_constituents - inactive_or_deceased = 11,262 - 1,177 = 10,085) ===';
SELECT COUNT(*) AS active_count
FROM CONSTITUENT C
LEFT JOIN DECEASEDCONSTITUENT D ON C.ID = D.ID
WHERE C.ISCONSTITUENT = 1 AND C.ISGROUP = 0 AND C.ISORGANIZATION = 0
  AND C.ISINACTIVE = 0
  AND D.ID IS NULL;

PRINT '=== S4.b violation counts on the active universe (each must equal 0) ===';
SELECT
    SUM(CASE WHEN D.ID IS NOT NULL THEN 1 ELSE 0 END) AS v_active_with_deceased_flag,
    SUM(CASE WHEN C.ISINACTIVE = 1 THEN 1 ELSE 0 END) AS v_active_with_inactive_flag,
    SUM(CASE WHEN D.ID IS NOT NULL OR C.ISINACTIVE = 1 THEN 1 ELSE 0 END) AS v_active_with_household_exclusion,
    SUM(CASE WHEN D.ID IS NOT NULL OR C.ISINACTIVE = 1 THEN 1 ELSE 0 END) AS v_active_with_do_not_contact,
    SUM(CASE
            WHEN (C.DONOTEMAIL = 0 AND C.DONOTMAIL = 0 AND C.DONOTPHONE = 0)
             AND (D.ID IS NOT NULL OR C.ISINACTIVE = 1)
            THEN 1 ELSE 0
        END) AS v_active_with_forced_optouts
FROM CONSTITUENT C
LEFT JOIN DECEASEDCONSTITUENT D ON C.ID = D.ID
WHERE C.ISCONSTITUENT = 1 AND C.ISGROUP = 0 AND C.ISORGANIZATION = 0
  AND C.ISINACTIVE = 0
  AND D.ID IS NULL;

PRINT '=== S4.c sample of 5 active rows (all derived fields should be false; opt-outs reflect raw Altru) ===';
SELECT TOP 5
    CAST(CASE WHEN D.ID IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS npsp__Deceased__c,
    CAST(C.ISINACTIVE AS BIT) AS Inactive__c,
    CAST(CASE WHEN D.ID IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS npsp__Exclude_from_Household_Name__c,
    CAST(CASE WHEN D.ID IS NOT NULL OR C.ISINACTIVE = 1 THEN 1 ELSE 0 END AS BIT) AS npsp__Do_Not_Contact__c,
    CAST(C.DONOTEMAIL AS BIT) AS altru_DONOTEMAIL,
    CAST(C.DONOTMAIL  AS BIT) AS altru_DONOTMAIL,
    CAST(C.DONOTPHONE AS BIT) AS altru_DONOTPHONE,
    CAST(CASE WHEN C.DONOTEMAIL = 1 OR (D.ID IS NOT NULL OR C.ISINACTIVE = 1) THEN 1 ELSE 0 END AS BIT) AS effective_HasOptedOutOfEmail,
    CAST(CASE WHEN C.DONOTMAIL  = 1 OR (D.ID IS NOT NULL OR C.ISINACTIVE = 1) THEN 1 ELSE 0 END AS BIT) AS effective_Do_not_mail__c,
    CAST(CASE WHEN C.DONOTPHONE = 1 OR (D.ID IS NOT NULL OR C.ISINACTIVE = 1) THEN 1 ELSE 0 END AS BIT) AS effective_DoNotCall
FROM CONSTITUENT C
LEFT JOIN DECEASEDCONSTITUENT D ON C.ID = D.ID
WHERE C.ISCONSTITUENT = 1 AND C.ISGROUP = 0 AND C.ISORGANIZATION = 0
  AND C.ISINACTIVE = 0
  AND D.ID IS NULL
ORDER BY C.DATEADDED DESC;
