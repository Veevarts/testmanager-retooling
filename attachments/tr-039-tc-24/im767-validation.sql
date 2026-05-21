SET NOCOUNT ON;

/* ============================================================ */
/* IM-767 PR 112 — Altru in-kind gift record types               */
/*                                                                */
/* Fix: donation_transaction.sql adds a GiftInKindTransactions   */
/* CTE that flags FTs with REVENUEPAYMENTMETHOD ->               */
/* GIFTINKINDPAYMENTMETHODDETAIL. EligibleLines carries the      */
/* flag, TransactionAgg MAX-aggregates per FT, and the final     */
/* SELECT emits '{{IN_KIND_GIFT_RECORD_TYPE_ID}}' (in-kind) or   */
/* '{{Donation_Record_Type}}' (standard) as RecordTypeId.        */
/*                                                                */
/* Scope: In-Kind Gift only. Matching/Major gifts out of scope.  */
/* Anchor: rev-10672300 (TCR Solutions, Inc., Org 1935950).      */
/* ============================================================ */

PRINT '=== R1: anchor rev-10672300 in-kind classification ===';

SELECT TOP 1
    ft.CALCULATEDUSERDEFINEDID                  AS rev_id,
    CAST(ft.ID AS NVARCHAR(36))                 AS ft_id,
    ft.[TYPE]                                   AS ft_type,
    ft.TYPECODE                                 AS ft_typecode,
    CAST(ft.TRANSACTIONAMOUNT AS NVARCHAR(20))  AS ft_amount,
    CONVERT(NVARCHAR(10), ft.CALCULATEDDATE, 23) AS ft_date,
    CASE WHEN EXISTS (
        SELECT 1 FROM REVENUEPAYMENTMETHOD rpm
        JOIN GIFTINKINDPAYMENTMETHODDETAIL gik ON gik.ID = rpm.ID
        WHERE rpm.REVENUEID = ft.ID
    ) THEN 1 ELSE 0 END                         AS has_gift_in_kind_detail,
    CASE WHEN EXISTS (
        SELECT 1 FROM REVENUEPAYMENTMETHOD rpm
        JOIN GIFTINKINDPAYMENTMETHODDETAIL gik ON gik.ID = rpm.ID
        WHERE rpm.REVENUEID = ft.ID
    ) THEN '{{IN_KIND_GIFT_RECORD_TYPE_ID}}' ELSE '{{Donation_Record_Type}}' END
                                                AS expected_record_type_token
FROM FINANCIALTRANSACTION ft
WHERE ft.CALCULATEDUSERDEFINEDID = 'rev-10672300';

PRINT '=== R2: anchor constituent TCR Solutions, Inc. — all FT classifications ===';

SELECT TOP 20
    ft.CALCULATEDUSERDEFINEDID                  AS rev_id,
    CAST(ft.ID AS NVARCHAR(36))                 AS ft_id,
    ft.[TYPE]                                   AS ft_type,
    ft.TYPECODE                                 AS ft_typecode,
    CAST(ft.TRANSACTIONAMOUNT AS NVARCHAR(20))  AS ft_amount,
    CONVERT(NVARCHAR(10), ft.CALCULATEDDATE, 23) AS ft_date,
    CASE WHEN EXISTS (
        SELECT 1 FROM REVENUEPAYMENTMETHOD rpm
        JOIN GIFTINKINDPAYMENTMETHODDETAIL gik ON gik.ID = rpm.ID
        WHERE rpm.REVENUEID = ft.ID
    ) THEN 1 ELSE 0 END                         AS has_gift_in_kind_detail
FROM FINANCIALTRANSACTION ft
WHERE ft.CONSTITUENTID = '363ADBF9-BD7E-4656-8A79-9CFC6073360B'
ORDER BY ft.CALCULATEDDATE DESC;

PRINT '=== R3: in-kind universe — distinct FT IDs flagged by the GiftInKindTransactions CTE ===';

WITH GiftInKindTransactions AS (
    SELECT DISTINCT
        rpm.REVENUEID AS FinancialTransactionID
    FROM REVENUEPAYMENTMETHOD rpm
    JOIN GIFTINKINDPAYMENTMETHODDETAIL gik ON gik.ID = rpm.ID
)
SELECT
    (SELECT COUNT(*) FROM GiftInKindTransactions)                       AS in_kind_distinct_ft_count,
    (SELECT COUNT(*) FROM REVENUEPAYMENTMETHOD)                         AS rpm_total,
    (SELECT COUNT(*) FROM GIFTINKINDPAYMENTMETHODDETAIL)                AS gik_detail_total;

PRINT '=== R4: in-kind universe intersected with donation-eligible FTs (final RecordTypeId distribution) ===';
/* Donation-eligible filter: ft.TYPECODE NOT IN (1,2,20) Pledge/Recurring/Write-off; line type = Standard or Reversal */

WITH GiftInKindTransactions AS (
    SELECT DISTINCT rpm.REVENUEID AS FinancialTransactionID
    FROM REVENUEPAYMENTMETHOD rpm
    JOIN GIFTINKINDPAYMENTMETHODDETAIL gik ON gik.ID = rpm.ID
),
DonationEligibleFT AS (
    SELECT DISTINCT ft.ID AS FinancialTransactionID
    FROM FINANCIALTRANSACTION ft
    INNER JOIN FINANCIALTRANSACTIONLINEITEM dli ON dli.FINANCIALTRANSACTIONID = ft.ID
    LEFT JOIN REVENUESPLIT_EXT rse ON rse.ID = dli.ID
    WHERE dli.[TYPE] IN ('Standard','Reversal')
      AND ft.TYPECODE NOT IN (1, 2, 20)
      AND NULLIF(rse.APPLICATION, '') IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
)
SELECT
    (SELECT COUNT(*) FROM DonationEligibleFT)                                      AS donation_eligible_ft_total,
    (SELECT COUNT(*) FROM DonationEligibleFT def
       WHERE EXISTS (SELECT 1 FROM GiftInKindTransactions gik WHERE gik.FinancialTransactionID = def.FinancialTransactionID))
                                                                                    AS donation_eligible_in_kind_ft,
    (SELECT COUNT(*) FROM DonationEligibleFT def
       WHERE NOT EXISTS (SELECT 1 FROM GiftInKindTransactions gik WHERE gik.FinancialTransactionID = def.FinancialTransactionID))
                                                                                    AS donation_eligible_standard_ft;

PRINT '=== R5: sample 5 donation-eligible IN-KIND FTs (would emit IN_KIND_GIFT_RECORD_TYPE_ID) ===';

WITH GiftInKindTransactions AS (
    SELECT DISTINCT rpm.REVENUEID AS FinancialTransactionID
    FROM REVENUEPAYMENTMETHOD rpm
    JOIN GIFTINKINDPAYMENTMETHODDETAIL gik ON gik.ID = rpm.ID
)
SELECT TOP 5
    ft.CALCULATEDUSERDEFINEDID                  AS rev_id,
    CAST(ft.ID AS NVARCHAR(36))                 AS ft_id,
    ft.[TYPE]                                   AS ft_type,
    CAST(ft.TRANSACTIONAMOUNT AS NVARCHAR(20))  AS ft_amount,
    CONVERT(NVARCHAR(10), ft.CALCULATEDDATE, 23) AS ft_date,
    '{{IN_KIND_GIFT_RECORD_TYPE_ID}}'           AS emitted_record_type_token
FROM FINANCIALTRANSACTION ft
INNER JOIN GiftInKindTransactions gik ON gik.FinancialTransactionID = ft.ID
INNER JOIN FINANCIALTRANSACTIONLINEITEM dli ON dli.FINANCIALTRANSACTIONID = ft.ID
LEFT JOIN REVENUESPLIT_EXT rse ON rse.ID = dli.ID
WHERE dli.[TYPE] IN ('Standard','Reversal')
  AND ft.TYPECODE NOT IN (1, 2, 20)
  AND NULLIF(rse.APPLICATION, '') IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
ORDER BY ft.CALCULATEDDATE DESC;

PRINT '=== R6: sample 5 donation-eligible STANDARD FTs (would emit Donation_Record_Type) ===';

WITH GiftInKindTransactions AS (
    SELECT DISTINCT rpm.REVENUEID AS FinancialTransactionID
    FROM REVENUEPAYMENTMETHOD rpm
    JOIN GIFTINKINDPAYMENTMETHODDETAIL gik ON gik.ID = rpm.ID
)
SELECT TOP 5
    ft.CALCULATEDUSERDEFINEDID                  AS rev_id,
    CAST(ft.ID AS NVARCHAR(36))                 AS ft_id,
    ft.[TYPE]                                   AS ft_type,
    CAST(ft.TRANSACTIONAMOUNT AS NVARCHAR(20))  AS ft_amount,
    CONVERT(NVARCHAR(10), ft.CALCULATEDDATE, 23) AS ft_date,
    '{{Donation_Record_Type}}'                  AS emitted_record_type_token
FROM FINANCIALTRANSACTION ft
INNER JOIN FINANCIALTRANSACTIONLINEITEM dli ON dli.FINANCIALTRANSACTIONID = ft.ID
LEFT JOIN REVENUESPLIT_EXT rse ON rse.ID = dli.ID
WHERE dli.[TYPE] IN ('Standard','Reversal')
  AND ft.TYPECODE NOT IN (1, 2, 20)
  AND NULLIF(rse.APPLICATION, '') IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
  AND NOT EXISTS (SELECT 1 FROM GiftInKindTransactions gik WHERE gik.FinancialTransactionID = ft.ID)
ORDER BY ft.CALCULATEDDATE DESC;

PRINT '=== R7: row-grain invariance — IN-KIND FTs with multiple lines do NOT multiply rows ===';
/* CTE uses DISTINCT + MAX(HasGiftInKindPaymentDetail), so multi-line in-kind FTs emit 1 row */

WITH GiftInKindTransactions AS (
    SELECT DISTINCT rpm.REVENUEID AS FinancialTransactionID
    FROM REVENUEPAYMENTMETHOD rpm
    JOIN GIFTINKINDPAYMENTMETHODDETAIL gik ON gik.ID = rpm.ID
),
InKindFTLineCounts AS (
    SELECT
        gik.FinancialTransactionID,
        COUNT(dli.ID) AS eligible_line_count
    FROM GiftInKindTransactions gik
    INNER JOIN FINANCIALTRANSACTIONLINEITEM dli ON dli.FINANCIALTRANSACTIONID = gik.FinancialTransactionID
    LEFT JOIN REVENUESPLIT_EXT rse ON rse.ID = dli.ID
    INNER JOIN FINANCIALTRANSACTION ft ON ft.ID = gik.FinancialTransactionID
    WHERE dli.[TYPE] IN ('Standard','Reversal')
      AND ft.TYPECODE NOT IN (1, 2, 20)
      AND NULLIF(rse.APPLICATION, '') IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
    GROUP BY gik.FinancialTransactionID
)
SELECT
    COUNT(*)                                                            AS in_kind_fts_with_eligible_lines,
    SUM(CASE WHEN eligible_line_count = 1 THEN 1 ELSE 0 END)            AS single_line_fts,
    SUM(CASE WHEN eligible_line_count >  1 THEN 1 ELSE 0 END)           AS multi_line_fts,
    MAX(eligible_line_count)                                            AS max_lines_per_ft,
    SUM(eligible_line_count)                                            AS total_eligible_lines_under_in_kind_fts
FROM InKindFTLineCounts;
