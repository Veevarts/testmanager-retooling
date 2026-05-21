SET NOCOUNT ON;

/* ============================================================ */
/* IM-375 PR 102 — align donation opportunity keys for refunds   */
/*                                                                */
/* Fix: 3 queries (donation_transaction.sql, fund_assignment_     */
/* donations.sql, fund_assingments_donation_refunds.sql) ahora    */
/* usan EL MISMO opportunity key:                                 */
/*   COALESCE(RecurringInstallmentID, FinancialTransactionID)     */
/*                                                                */
/* Pre-fix: 1 Opp per line item (line grain).                     */
/* Post-fix: 1 Opp per payment/installment (payment grain).       */
/*                                                                */
/* Bug: shared SOURCELINEITEMID across multiple refund lines      */
/* causa over-refund. El fix alinea todos los queries al mismo    */
/* opportunity key derivado del payment original.                 */
/* ============================================================ */

PRINT '=== R1: Opportunity grain collapse — donation_transaction.sql post-fix universe ===';
/* Pre-fix grain = line item count. Post-fix grain = COALESCE(rgi.RecurringInstallmentID, ft.ID) */

WITH InstallmentByPayment AS (
    SELECT
        rgp.PAYMENTID,
        CASE
            WHEN COUNT(DISTINCT rgi.ID) = 1 THEN MIN(rgi.ID)
            ELSE NULL
        END AS RecurringInstallmentID
    FROM RECURRINGGIFTINSTALLMENT rgi
    LEFT JOIN RECURRINGGIFTINSTALLMENTPAYMENT rgp
        ON rgi.ID = rgp.RECURRINGGIFTINSTALLMENTID
    GROUP BY rgp.PAYMENTID
),
DonationEligibleLines AS (
    SELECT
        ft.ID AS FinancialTransactionID,
        dli.ID AS LineItemID
    FROM FINANCIALTRANSACTION ft
    INNER JOIN FINANCIALTRANSACTIONLINEITEM dli ON dli.FINANCIALTRANSACTIONID = ft.ID
    LEFT JOIN REVENUESPLIT_EXT rse ON rse.ID = dli.ID
    WHERE dli.[TYPE] IN ('Standard','Reversal')
      AND ft.TYPECODE NOT IN (1, 2, 20)
      AND NULLIF(rse.APPLICATION, '') IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
),
PostFixKey AS (
    SELECT DISTINCT
        COALESCE(CAST(ip.RecurringInstallmentID AS VARCHAR(36)), CAST(d.FinancialTransactionID AS VARCHAR(36))) AS OpportunityKey
    FROM DonationEligibleLines d
    LEFT JOIN InstallmentByPayment ip ON ip.PAYMENTID = d.FinancialTransactionID
)
SELECT
    (SELECT COUNT(*) FROM DonationEligibleLines)              AS prefix_opportunity_count_line_grain,
    (SELECT COUNT(DISTINCT FinancialTransactionID) FROM DonationEligibleLines) AS distinct_ft_count,
    (SELECT COUNT(*) FROM PostFixKey)                          AS postfix_opportunity_count_payment_grain,
    (SELECT COUNT(*) FROM DonationEligibleLines) - (SELECT COUNT(*) FROM PostFixKey) AS rows_collapsed;

PRINT '=== R2: Recurring installment usage — how many post-fix keys come from RGI vs FT ===';

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
    SUM(CASE WHEN ip.RecurringInstallmentID IS NOT NULL THEN 1 ELSE 0 END) AS keys_from_recurring_installment,
    SUM(CASE WHEN ip.RecurringInstallmentID IS NULL THEN 1 ELSE 0 END)     AS keys_from_financial_transaction,
    COUNT(*)                                                                AS distinct_ft_total
FROM DonationEligibleFTs d
LEFT JOIN InstallmentByPayment ip ON ip.PAYMENTID = d.FinancialTransactionID;

PRINT '=== R3: shared-SOURCELINEITEMID refund anchor — pattern described in the ticket ===';
/* Find refund lines that share SOURCELINEITEMID (= the bug pattern from Muhammad's orders) */

SELECT TOP 3
    CAST(refund_li.SOURCELINEITEMID AS NVARCHAR(36)) AS shared_source_line_id,
    COUNT(refund_li.ID)                              AS refund_line_count,
    CAST(SUM(refund_li.TRANSACTIONAMOUNT) AS NVARCHAR(20)) AS total_refund_amount,
    CAST(source_dli.FINANCIALTRANSACTIONID AS NVARCHAR(36)) AS source_ft_id,
    src_ft.CALCULATEDUSERDEFINEDID                   AS source_rev_id
FROM FINANCIALTRANSACTIONLINEITEM refund_li
INNER JOIN FINANCIALTRANSACTION refund_ft ON refund_ft.ID = refund_li.FINANCIALTRANSACTIONID
INNER JOIN FINANCIALTRANSACTIONLINEITEM source_dli ON source_dli.ID = refund_li.SOURCELINEITEMID
INNER JOIN FINANCIALTRANSACTION src_ft ON src_ft.ID = source_dli.FINANCIALTRANSACTIONID
WHERE refund_ft.[TYPE] = 'Refund'
  AND refund_li.SOURCELINEITEMID IS NOT NULL
GROUP BY refund_li.SOURCELINEITEMID, source_dli.FINANCIALTRANSACTIONID, src_ft.CALCULATEDUSERDEFINEDID
HAVING COUNT(refund_li.ID) >= 10
ORDER BY COUNT(refund_li.ID) DESC;

PRINT '=== R4: anchor F68D5E3A — derive the patched Opportunity key for its 32 refund lines ===';
/* Top anchor: F68D5E3A has 32 refund lines. Confirm all align to the SAME post-fix Opp key */

WITH InstallmentByPayment AS (
    SELECT rgp.PAYMENTID, CASE WHEN COUNT(DISTINCT rgi.ID) = 1 THEN MIN(rgi.ID) ELSE NULL END AS RecurringInstallmentID
    FROM RECURRINGGIFTINSTALLMENT rgi
    LEFT JOIN RECURRINGGIFTINSTALLMENTPAYMENT rgp ON rgi.ID = rgp.RECURRINGGIFTINSTALLMENTID
    GROUP BY rgp.PAYMENTID
)
SELECT
    CAST(source_dli.ID AS NVARCHAR(36))                AS source_line_id,
    CAST(source_dli.FINANCIALTRANSACTIONID AS NVARCHAR(36)) AS original_payment_ft_id,
    src_ft.CALCULATEDUSERDEFINEDID                     AS original_payment_rev_id,
    COUNT(DISTINCT refund_li.ID)                       AS refund_lines_under_anchor,
    CAST(MAX(ip.RecurringInstallmentID) AS NVARCHAR(36)) AS rgi_id_if_any,
    COALESCE(CAST(MAX(ip.RecurringInstallmentID) AS VARCHAR(36)), CAST(source_dli.FINANCIALTRANSACTIONID AS VARCHAR(36)))
                                                       AS postfix_opportunity_key_for_all_32_refunds
FROM FINANCIALTRANSACTIONLINEITEM source_dli
INNER JOIN FINANCIALTRANSACTION src_ft ON src_ft.ID = source_dli.FINANCIALTRANSACTIONID
LEFT JOIN InstallmentByPayment ip ON ip.PAYMENTID = source_dli.FINANCIALTRANSACTIONID
LEFT JOIN FINANCIALTRANSACTIONLINEITEM refund_li ON refund_li.SOURCELINEITEMID = source_dli.ID
LEFT JOIN FINANCIALTRANSACTION refund_ft ON refund_ft.ID = refund_li.FINANCIALTRANSACTIONID AND refund_ft.[TYPE] = 'Refund'
WHERE source_dli.ID = 'F68D5E3A-8E77-4DD2-826B-6B1E0FBD9737'
GROUP BY source_dli.ID, source_dli.FINANCIALTRANSACTIONID, src_ft.CALCULATEDUSERDEFINEDID;

