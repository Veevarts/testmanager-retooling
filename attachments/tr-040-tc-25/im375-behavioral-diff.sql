SET NOCOUNT ON;

/* ============================================================ */
/* IM-375 PR 102 — behavioral diff CORRECTED                     */
/*                                                                */
/* Real change: NO grain collapse. The 3 queries already         */
/* aggregated by FT (TransactionAgg CTE existed pre-fix).        */
/*                                                                */
/* Real delta is the SOURCE of vnfp__Opportunity__c per query:   */
/*                                                                */
/* donation_transaction.sql:                                      */
/*   pre:  ta.FinancialTransactionID                              */
/*   post: COALESCE(rgi.RecurringInstallmentID, ta.FT.ID)         */
/*                                                                */
/* fund_assignment_donations.sql:                                 */
/*   pre:  ft.ID                                                  */
/*   post: COALESCE(rgi.RecurringInstallmentID, ft.ID)            */
/*                                                                */
/* fund_assingments_donation_refunds.sql (THE KEY FIX):           */
/*   pre:  source_dli.FINANCIALTRANSACTIONID  (FT of source line) */
/*   post: COALESCE(rgi, rli.OriginalPaymentTransactionId)        */
/*                                                                */
/* The refund query is the most impactful: when source line is   */
/* in a different FT than the original payment (via CREDITPAYMENT),*/
/* pre-fix refund pointed to source line's FT (wrong); post-fix   */
/* points to the canonical original payment FT (right).           */
/* ============================================================ */

PRINT '=== B1: cardinality CORRECTED — pre and post both emit 1 Opp per donation-eligible FT ===';

WITH InstallmentByPayment AS (
    SELECT rgp.PAYMENTID, CASE WHEN COUNT(DISTINCT rgi.ID) = 1 THEN MIN(rgi.ID) ELSE NULL END AS RecurringInstallmentID
    FROM RECURRINGGIFTINSTALLMENT rgi
    LEFT JOIN RECURRINGGIFTINSTALLMENTPAYMENT rgp ON rgi.ID = rgp.RECURRINGGIFTINSTALLMENTID
    GROUP BY rgp.PAYMENTID
),
DonationEligibleFTs AS (
    SELECT DISTINCT ft.ID AS FinancialTransactionID
    FROM FINANCIALTRANSACTION ft
    INNER JOIN FINANCIALTRANSACTIONLINEITEM dli ON dli.FINANCIALTRANSACTIONID = ft.ID
    LEFT JOIN REVENUESPLIT_EXT rse ON rse.ID = dli.ID
    WHERE dli.[TYPE] IN ('Standard','Reversal')
      AND ft.TYPECODE NOT IN (1, 2, 20)
      AND NULLIF(rse.APPLICATION, '') IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
)
SELECT
    (SELECT COUNT(*) FROM DonationEligibleFTs)                                                      AS prefix_donation_opp_count,
    (SELECT COUNT(*) FROM DonationEligibleFTs)                                                      AS postfix_donation_opp_count,
    /* Same FT universe in both. The change is in the EXTERNAL ID VALUE for the RGI-backed FTs */
    (SELECT COUNT(*) FROM DonationEligibleFTs d INNER JOIN InstallmentByPayment ip ON ip.PAYMENTID = d.FinancialTransactionID WHERE ip.RecurringInstallmentID IS NOT NULL)
                                                                                                    AS opps_with_changed_external_id;

PRINT '=== B2: refunds query divergence — where pre-fix source_dli.FT.ID differs from post-fix rli.OriginalPaymentTransactionId ===';
/* The core bug fix: count refund lines where the 2 candidate Opp keys disagree */

WITH CreditPaymentPerRefund AS (
    SELECT cp.CREDITID AS RefundFinancialTransactionId, MIN(cp.REVENUEID) AS OriginalPaymentTransactionId
    FROM CREDITPAYMENT cp
    GROUP BY cp.CREDITID
),
RefundLineComparison AS (
    SELECT
        refund_li.ID AS refund_line_id,
        refund_li.SOURCELINEITEMID,
        source_dli.FINANCIALTRANSACTIONID AS prefix_opp_key,
        cppr.OriginalPaymentTransactionId AS postfix_opp_key_via_payment,
        CASE WHEN source_dli.FINANCIALTRANSACTIONID = cppr.OriginalPaymentTransactionId THEN 0 ELSE 1 END AS keys_diverge
    FROM FINANCIALTRANSACTIONLINEITEM refund_li
    INNER JOIN FINANCIALTRANSACTION refund_ft ON refund_ft.ID = refund_li.FINANCIALTRANSACTIONID AND refund_ft.[TYPE] = 'Refund'
    INNER JOIN FINANCIALTRANSACTIONLINEITEM source_dli ON source_dli.ID = refund_li.SOURCELINEITEMID
    LEFT JOIN CreditPaymentPerRefund cppr ON cppr.RefundFinancialTransactionId = refund_li.FINANCIALTRANSACTIONID
    INNER JOIN REVENUESPLIT_EXT src_rse ON src_rse.ID = refund_li.SOURCELINEITEMID
    WHERE NULLIF(src_rse.APPLICATION, '') IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
)
SELECT
    COUNT(*)                                                  AS total_donation_refund_lines,
    SUM(CASE WHEN keys_diverge = 0 THEN 1 ELSE 0 END)         AS keys_align_prefix_eq_postfix,
    SUM(CASE WHEN keys_diverge = 1 THEN 1 ELSE 0 END)         AS keys_diverge_prefix_neq_postfix,
    SUM(CASE WHEN postfix_opp_key_via_payment IS NULL THEN 1 ELSE 0 END) AS no_credit_payment_link
FROM RefundLineComparison;

PRINT '=== B3: divergence anchor sample — refund lines where pre/post keys differ ===';

WITH CreditPaymentPerRefund AS (
    SELECT cp.CREDITID AS RefundFinancialTransactionId, MIN(cp.REVENUEID) AS OriginalPaymentTransactionId
    FROM CREDITPAYMENT cp
    GROUP BY cp.CREDITID
)
SELECT TOP 5
    CAST(refund_li.ID AS NVARCHAR(36))                                          AS refund_line_id,
    CAST(refund_li.SOURCELINEITEMID AS NVARCHAR(36))                            AS source_line_id,
    CAST(source_dli.FINANCIALTRANSACTIONID AS NVARCHAR(36))                     AS prefix_opp_key_source_FT,
    src_ft.CALCULATEDUSERDEFINEDID                                              AS prefix_opp_rev_id,
    CAST(cppr.OriginalPaymentTransactionId AS NVARCHAR(36))                     AS postfix_opp_key_via_payment,
    payment_ft.CALCULATEDUSERDEFINEDID                                          AS postfix_opp_rev_id,
    CAST(refund_li.TRANSACTIONAMOUNT AS NVARCHAR(20))                           AS refund_amount
FROM FINANCIALTRANSACTIONLINEITEM refund_li
INNER JOIN FINANCIALTRANSACTION refund_ft ON refund_ft.ID = refund_li.FINANCIALTRANSACTIONID AND refund_ft.[TYPE] = 'Refund'
INNER JOIN FINANCIALTRANSACTIONLINEITEM source_dli ON source_dli.ID = refund_li.SOURCELINEITEMID
INNER JOIN FINANCIALTRANSACTION src_ft ON src_ft.ID = source_dli.FINANCIALTRANSACTIONID
LEFT JOIN CreditPaymentPerRefund cppr ON cppr.RefundFinancialTransactionId = refund_li.FINANCIALTRANSACTIONID
LEFT JOIN FINANCIALTRANSACTION payment_ft ON payment_ft.ID = cppr.OriginalPaymentTransactionId
INNER JOIN REVENUESPLIT_EXT src_rse ON src_rse.ID = refund_li.SOURCELINEITEMID
WHERE NULLIF(src_rse.APPLICATION, '') IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
  AND source_dli.FINANCIALTRANSACTIONID <> cppr.OriginalPaymentTransactionId
ORDER BY refund_li.ID;

PRINT '=== B4: RGI adoption — donation FTs that switch from FT.ID to RGI.ID as external_id ===';

WITH InstallmentByPayment AS (
    SELECT rgp.PAYMENTID, CASE WHEN COUNT(DISTINCT rgi.ID) = 1 THEN MIN(rgi.ID) ELSE NULL END AS RecurringInstallmentID
    FROM RECURRINGGIFTINSTALLMENT rgi
    LEFT JOIN RECURRINGGIFTINSTALLMENTPAYMENT rgp ON rgi.ID = rgp.RECURRINGGIFTINSTALLMENTID
    GROUP BY rgp.PAYMENTID
),
DonationEligibleFTs AS (
    SELECT DISTINCT ft.ID AS FinancialTransactionID
    FROM FINANCIALTRANSACTION ft
    INNER JOIN FINANCIALTRANSACTIONLINEITEM dli ON dli.FINANCIALTRANSACTIONID = ft.ID
    LEFT JOIN REVENUESPLIT_EXT rse ON rse.ID = dli.ID
    WHERE dli.[TYPE] IN ('Standard','Reversal')
      AND ft.TYPECODE NOT IN (1, 2, 20)
      AND NULLIF(rse.APPLICATION, '') IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
)
SELECT
    COUNT(*)                                                                   AS total_donation_opps,
    SUM(CASE WHEN ip.RecurringInstallmentID IS NOT NULL THEN 1 ELSE 0 END)     AS opps_now_keyed_by_rgi,
    SUM(CASE WHEN ip.RecurringInstallmentID IS NULL THEN 1 ELSE 0 END)         AS opps_keyed_by_ft_unchanged
FROM DonationEligibleFTs d
LEFT JOIN InstallmentByPayment ip ON ip.PAYMENTID = d.FinancialTransactionID;

PRINT '=== B5: F68D5E3A re-check — does the pre/post differ for this anchor? ===';

WITH CreditPaymentPerRefund AS (
    SELECT cp.CREDITID AS RefundFinancialTransactionId, MIN(cp.REVENUEID) AS OriginalPaymentTransactionId
    FROM CREDITPAYMENT cp
    GROUP BY cp.CREDITID
)
SELECT TOP 5
    CAST(refund_li.ID AS NVARCHAR(36))                                          AS refund_line_id,
    CAST(source_dli.FINANCIALTRANSACTIONID AS NVARCHAR(36))                     AS prefix_opp_key,
    CAST(cppr.OriginalPaymentTransactionId AS NVARCHAR(36))                     AS postfix_opp_key,
    CASE WHEN source_dli.FINANCIALTRANSACTIONID = cppr.OriginalPaymentTransactionId THEN 'same' ELSE 'DIVERGES' END AS verdict
FROM FINANCIALTRANSACTIONLINEITEM refund_li
INNER JOIN FINANCIALTRANSACTION refund_ft ON refund_ft.ID = refund_li.FINANCIALTRANSACTIONID AND refund_ft.[TYPE] = 'Refund'
INNER JOIN FINANCIALTRANSACTIONLINEITEM source_dli ON source_dli.ID = refund_li.SOURCELINEITEMID
LEFT JOIN CreditPaymentPerRefund cppr ON cppr.RefundFinancialTransactionId = refund_li.FINANCIALTRANSACTIONID
WHERE refund_li.SOURCELINEITEMID = 'F68D5E3A-8E77-4DD2-826B-6B1E0FBD9737';
