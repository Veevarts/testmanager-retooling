SET NOCOUNT ON;

/* ============================================================ */
/* IM-718 PR 108 — Revenue Reference aggregate validation (Tucson) */
/* PR baseline:                                                  */
/*   REVENUE_EXT total:   641,668                                */
/*   REVENUE_EXT w/ REF:  621,843 (96.9%)                        */
/*   Pledge FTs total:    679                                    */
/*   Pledge FTs w/ REF:   652 (96.0%)                            */
/*   Donation candidates: 55,223 / 45,412 (82.2%)                */
/*   Memberships active:  103,627 / 87,217 (84.2% via COALESCE)  */
/* ============================================================ */

PRINT '=== R1: REVENUE_EXT universe + REFERENCE coverage ===';

SELECT COUNT(*) AS revenue_ext_total FROM REVENUE_EXT;

SELECT COUNT(*) AS revenue_ext_with_ref
FROM REVENUE_EXT
WHERE NULLIF(LTRIM(RTRIM(REFERENCE)), '') IS NOT NULL;

SELECT MAX(LEN(REFERENCE)) AS max_ref_length FROM REVENUE_EXT;

PRINT '=== R2: Pledge FTs total + Description coverage ===';

SELECT COUNT(*) AS pledge_ft_total
FROM FINANCIALTRANSACTION ft
WHERE ft.[TYPE] = 'Pledge';

SELECT COUNT(*) AS pledge_with_ref
FROM FINANCIALTRANSACTION ft
JOIN REVENUE_EXT re ON re.ID = ft.ID
WHERE ft.[TYPE] = 'Pledge'
  AND NULLIF(LTRIM(RTRIM(re.REFERENCE)), '') IS NOT NULL;

PRINT '=== R3: Sample 5 pledge FTs with their Description value (proves the field maps 1:1) ===';

SELECT TOP 5
    CAST(ft.ID AS NVARCHAR(36)) AS ft_id,
    ft.[TYPE]                   AS ft_type,
    LEFT(re.REFERENCE, 80)      AS description_preview,
    CAST(ft.TRANSACTIONAMOUNT AS NVARCHAR(20)) AS amount
FROM FINANCIALTRANSACTION ft
JOIN REVENUE_EXT re ON re.ID = ft.ID
WHERE ft.[TYPE] = 'Pledge'
  AND NULLIF(LTRIM(RTRIM(re.REFERENCE)), '') IS NOT NULL
ORDER BY ft.CALCULATEDDATE DESC;

PRINT '=== R4: Active MEMBERSHIPTRANSACTION rows + Description coverage via COALESCE(COMMENTS, REFERENCE) ===';

SELECT COUNT(*) AS membership_transaction_total
FROM MEMBERSHIPTRANSACTION mt;

SELECT COUNT(*) AS membership_with_description
FROM MEMBERSHIPTRANSACTION mt
LEFT JOIN FINANCIALTRANSACTIONLINEITEM li ON li.ID = mt.REVENUESPLITID
LEFT JOIN REVENUE_EXT re ON re.ID = li.FINANCIALTRANSACTIONID
WHERE NULLIF(LTRIM(RTRIM(mt.COMMENTS)), '') IS NOT NULL
   OR NULLIF(LTRIM(RTRIM(re.REFERENCE)), '') IS NOT NULL;

PRINT '=== R5: Membership semantic — rows where BOTH COMMENTS and REFERENCE are populated with DIFFERENT text ===';

SELECT COUNT(*) AS membership_both_populated_diff
FROM MEMBERSHIPTRANSACTION mt
JOIN FINANCIALTRANSACTIONLINEITEM li ON li.ID = mt.REVENUESPLITID
JOIN REVENUE_EXT re ON re.ID = li.FINANCIALTRANSACTIONID
WHERE NULLIF(LTRIM(RTRIM(mt.COMMENTS)), '') IS NOT NULL
  AND NULLIF(LTRIM(RTRIM(re.REFERENCE)), '') IS NOT NULL
  AND LTRIM(RTRIM(mt.COMMENTS)) <> LTRIM(RTRIM(re.REFERENCE));

PRINT '=== R6: Donation candidates (Payment FT type + Donation/Recurring lineage, ballpark) ===';

SELECT COUNT(DISTINCT ft.ID) AS donation_candidate_total
FROM FINANCIALTRANSACTION ft
JOIN FINANCIALTRANSACTIONLINEITEM li ON li.FINANCIALTRANSACTIONID = ft.ID
JOIN REVENUESPLIT_EXT rse ON rse.ID = li.ID
WHERE ft.TYPECODE IN (0, 5, 23)
  AND rse.APPLICATION IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
  AND li.[TYPE] = 'Standard';

SELECT COUNT(DISTINCT ft.ID) AS donation_with_ref
FROM FINANCIALTRANSACTION ft
JOIN FINANCIALTRANSACTIONLINEITEM li ON li.FINANCIALTRANSACTIONID = ft.ID
JOIN REVENUESPLIT_EXT rse ON rse.ID = li.ID
JOIN REVENUE_EXT re ON re.ID = ft.ID
WHERE ft.TYPECODE IN (0, 5, 23)
  AND rse.APPLICATION IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
  AND li.[TYPE] = 'Standard'
  AND NULLIF(LTRIM(RTRIM(re.REFERENCE)), '') IS NOT NULL;
