SET NOCOUNT ON;

/* ============================================================ */
/* IM-770 PR 113 — Type-precedence fix in rental_events_groups   */
/*                                                                */
/* Bug: CASE mixes nvarchar literal '[ANONYMOUS_CONTACT]' and    */
/* uniqueidentifier so.CONSTITUENTID. SQL Server infers result   */
/* type as uniqueidentifier (higher precedence), then implicitly */
/* casts the placeholder literal to GUID at row eval -> fails.   */
/* The mssql Node driver streams row-by-row so partial output    */
/* is delivered (13 of 1547 on Tucson) before the stream dies.   */
/*                                                                */
/* Fix: CAST(so.CONSTITUENTID AS NVARCHAR(36)) on the GUID       */
/* branch -> CASE resolves to nvarchar, placeholder is valid.    */
/* ============================================================ */

PRINT '=== R1: RESERVATION universe + CASE branch breakdown ===';

WITH branch_eval AS (
    SELECT
        r.ID AS reservation_id,
        so.CONSTITUENTID,
        c.ID AS constituent_id_match,
        c.ISORGANIZATION,
        c.ISGROUP,
        c.ISCONSTITUENT,
        CASE
            WHEN so.CONSTITUENTID IS NULL OR c.ID IS NULL THEN 'anonymous'
            WHEN c.ISORGANIZATION = 0 AND c.ISGROUP = 0 AND c.ISCONSTITUENT = 1 THEN 'valid_guid'
            ELSE 'null_org_or_group'
        END AS branch
    FROM RESERVATION r
    LEFT JOIN SALESORDER so ON so.ID = r.ID
    LEFT JOIN CONSTITUENT c ON c.ID = so.CONSTITUENTID
)
SELECT
    COUNT(*)                                                AS reservation_total,
    SUM(CASE WHEN branch = 'anonymous' THEN 1 ELSE 0 END)   AS anonymous_branch_rows,
    SUM(CASE WHEN branch = 'valid_guid' THEN 1 ELSE 0 END)  AS valid_guid_branch_rows,
    SUM(CASE WHEN branch = 'null_org_or_group' THEN 1 ELSE 0 END) AS other_null_branch_rows
FROM branch_eval;

PRINT '=== R2: anonymous-branch anchor rows (RESERVATIONs hitting NULL/orphaned CONSTITUENTID) ===';

SELECT TOP 5
    CAST(r.ID AS NVARCHAR(36))                  AS reservation_id,
    r.NAME                                       AS reservation_name,
    CASE WHEN so.CONSTITUENTID IS NULL THEN 'NULL' ELSE 'orphaned (no CONSTITUENT.ID match)' END AS anonymous_reason,
    CAST(so.CONSTITUENTID AS NVARCHAR(36))      AS source_constituent_id
FROM RESERVATION r
LEFT JOIN SALESORDER so ON so.ID = r.ID
LEFT JOIN CONSTITUENT c ON c.ID = so.CONSTITUENTID
WHERE so.CONSTITUENTID IS NULL OR c.ID IS NULL
ORDER BY r.ID;

PRINT '=== R3: type-precedence repro on the unpatched CASE (returns the inferred column type) ===';
/* Use SELECT TOP 0 to inspect column metadata without forcing rows */
SELECT TOP 0
    CASE
        WHEN so.CONSTITUENTID IS NULL OR c.ID IS NULL THEN '[ANONYMOUS_CONTACT]'
        WHEN c.ISORGANIZATION = 0 AND c.ISGROUP = 0 AND c.ISCONSTITUENT = 1
            THEN so.CONSTITUENTID
        ELSE NULL
    END AS unpatched_client_contact_type_probe
FROM RESERVATION r
LEFT JOIN SALESORDER so ON so.ID = r.ID
LEFT JOIN CONSTITUENT c ON c.ID = so.CONSTITUENTID;

PRINT '=== R4: patched CASE (with CAST) emits anonymous placeholder for the 16 rows + GUIDs for the rest ===';

WITH patched AS (
    SELECT
        r.ID AS reservation_id,
        CASE
            WHEN so.CONSTITUENTID IS NULL OR c.ID IS NULL THEN '[ANONYMOUS_CONTACT]'
            WHEN c.ISORGANIZATION = 0 AND c.ISGROUP = 0 AND c.ISCONSTITUENT = 1
                THEN CAST(so.CONSTITUENTID AS NVARCHAR(36))
            ELSE NULL
        END AS Auctifera__Client_Contact__c
    FROM RESERVATION r
    LEFT JOIN SALESORDER so ON so.ID = r.ID
    LEFT JOIN CONSTITUENT c ON c.ID = so.CONSTITUENTID
)
SELECT
    COUNT(*)                                                                   AS total_rows_emitted,
    SUM(CASE WHEN Auctifera__Client_Contact__c = '[ANONYMOUS_CONTACT]' THEN 1 ELSE 0 END) AS anonymous_placeholder_rows,
    SUM(CASE WHEN Auctifera__Client_Contact__c IS NOT NULL AND Auctifera__Client_Contact__c <> '[ANONYMOUS_CONTACT]' THEN 1 ELSE 0 END) AS guid_string_rows,
    SUM(CASE WHEN Auctifera__Client_Contact__c IS NULL THEN 1 ELSE 0 END)      AS null_rows
FROM patched;

PRINT '=== R5: sample output rows from patched query (placeholder + GUID-as-string side by side) ===';

WITH patched AS (
    SELECT
        r.ID AS reservation_id,
        r.NAME AS reservation_name,
        CASE
            WHEN so.CONSTITUENTID IS NULL OR c.ID IS NULL THEN '[ANONYMOUS_CONTACT]'
            WHEN c.ISORGANIZATION = 0 AND c.ISGROUP = 0 AND c.ISCONSTITUENT = 1
                THEN CAST(so.CONSTITUENTID AS NVARCHAR(36))
            ELSE NULL
        END AS Auctifera__Client_Contact__c
    FROM RESERVATION r
    LEFT JOIN SALESORDER so ON so.ID = r.ID
    LEFT JOIN CONSTITUENT c ON c.ID = so.CONSTITUENTID
)
SELECT TOP 3
    CAST(reservation_id AS NVARCHAR(36)) AS reservation_id,
    reservation_name,
    Auctifera__Client_Contact__c        AS client_contact_emitted,
    'anonymous' AS branch
FROM patched
WHERE Auctifera__Client_Contact__c = '[ANONYMOUS_CONTACT]'
UNION ALL
SELECT TOP 3
    CAST(reservation_id AS NVARCHAR(36)) AS reservation_id,
    reservation_name,
    Auctifera__Client_Contact__c        AS client_contact_emitted,
    'valid_guid' AS branch
FROM patched
WHERE Auctifera__Client_Contact__c <> '[ANONYMOUS_CONTACT]'
  AND Auctifera__Client_Contact__c IS NOT NULL;

PRINT '=== R6: sibling CASE (Client_Company_Household) returns only NULL or uniqueidentifier — no type clash ===';
/* Confirm that the household sibling did not need the fix */
SELECT TOP 0
    CASE
        WHEN so.CONSTITUENTID IS NULL OR c.ID IS NULL THEN NULL
        WHEN c.ISORGANIZATION = 1 OR c.ISGROUP = 1 OR c.ISCONSTITUENT = 0
            THEN so.CONSTITUENTID
        ELSE chh.HOUSEHOLDID
    END AS household_type_probe
FROM RESERVATION r
LEFT JOIN SALESORDER so ON so.ID = r.ID
LEFT JOIN CONSTITUENT c ON c.ID = so.CONSTITUENTID
LEFT JOIN CONSTITUENTHOUSEHOLD chh ON so.CONSTITUENTID = chh.ID;
