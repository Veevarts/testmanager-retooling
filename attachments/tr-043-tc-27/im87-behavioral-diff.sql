SET NOCOUNT ON;

/* ============================================================ */
/* IM-87 PR 94 — behavioral diff POS purchase + donation chain  */
/*                                                                */
/* Cambios principales:                                           */
/* - POS donation/membership/pledge ahora aggregan a nivel        */
/*   transaction (no line item)                                   */
/* - Donation POS: fallback payment-backed (SALESORDERPAYMENT)    */
/*   ademas del revenue-backed (SALESORDER.REVENUEID)             */
/* - Donation transaction.sql y fund_assignment_donations.sql     */
/*   ahora usan el MISMO COALESCE(revenue_so, payment_so) para    */
/*   vnfp__POS_Purchase__c y vnfp__Opportunity_POS_Purchase__c    */
/* ============================================================ */

PRINT '=== R1: pre-fix donation POS count (revenue-backed only, line-grain) ===';
WITH MembershipLineItems_pre AS (
    SELECT mli.ID AS MembershipLineItemID, mli.FINANCIALTRANSACTIONID AS FinancialTransactionId
    FROM FINANCIALTRANSACTIONLINEITEM mli
    INNER JOIN REVENUESPLIT_EXT rse ON rse.ID = mli.ID
    WHERE rse.APPLICATION = 'Membership' AND mli.[TYPE] = 'Standard'
),
DonationLineItems_pre AS (
    SELECT DISTINCT ft.ID AS FinancialTransactionID
    FROM FINANCIALTRANSACTIONLINEITEM dli
    INNER JOIN REVENUESPLIT_EXT rse ON rse.ID = dli.ID
        AND rse.APPLICATION IN ('Donation','Recurring gift','Planned gift','Matching gift')
        AND rse.[TYPE] NOT IN ('Membership')
    INNER JOIN FINANCIALTRANSACTION ft ON ft.ID = dli.FINANCIALTRANSACTIONID
    WHERE dli.[TYPE] = 'Standard'
      AND NOT EXISTS (SELECT 1 FROM MembershipLineItems_pre m WHERE m.FinancialTransactionId = dli.FINANCIALTRANSACTIONID)
)
SELECT COUNT(DISTINCT so.ID) AS prefix_donation_pos_rows
FROM DonationLineItems_pre dt
INNER JOIN FINANCIALTRANSACTION ft ON ft.ID = dt.FinancialTransactionID
INNER JOIN SALESORDER so ON so.REVENUEID = ft.ID;

PRINT '=== R2: post-fix donation POS count (transaction-grain + payment-backed fallback) ===';
WITH MembershipLineItems_post AS (
    SELECT mli.ID AS MembershipLineItemID
    FROM FINANCIALTRANSACTIONLINEITEM mli
    INNER JOIN REVENUESPLIT_EXT rse ON rse.ID = mli.ID
    WHERE rse.APPLICATION = 'Membership' AND mli.[TYPE] = 'Standard'
),
EligibleLines_post AS (
    SELECT
        dli.FINANCIALTRANSACTIONID AS FinancialTransactionID,
        CASE WHEN dli.[TYPE]='Reversal' THEN -1*dli.TRANSACTIONAMOUNT ELSE dli.TRANSACTIONAMOUNT END AS NetAmount
    FROM FINANCIALTRANSACTIONLINEITEM dli
    INNER JOIN FINANCIALTRANSACTION ft ON ft.ID = dli.FINANCIALTRANSACTIONID
    LEFT JOIN REVENUESPLIT_EXT rse ON rse.ID = dli.ID
    WHERE dli.[TYPE] IN ('Standard','Reversal')
      AND ft.TYPECODE NOT IN (1,2,20)
      AND NOT EXISTS (
            SELECT 1 FROM FINANCIALTRANSACTIONLINEITEM src
            INNER JOIN FINANCIALTRANSACTION ft_pledge ON ft_pledge.ID = src.FINANCIALTRANSACTIONID AND ft_pledge.TYPECODE = 1
            WHERE dli.SOURCELINEITEMID = src.ID
      )
      AND NOT EXISTS (
            SELECT 1 FROM MembershipLineItems_post m
            WHERE m.MembershipLineItemID IN (dli.SOURCELINEITEMID, dli.REVERSEDLINEITEMID)
      )
      AND (
            (dli.[TYPE]='Reversal' AND EXISTS (
                SELECT 1 FROM FINANCIALTRANSACTIONLINEITEM reversed_dli
                LEFT JOIN REVENUESPLIT_EXT reversed_rse ON reversed_rse.ID = reversed_dli.ID
                WHERE reversed_dli.ID = dli.REVERSEDLINEITEMID
                  AND NULLIF(reversed_rse.APPLICATION,'') IN ('Donation','Recurring gift','Planned gift','Matching gift')
            ))
            OR (dli.[TYPE]<>'Reversal' AND NULLIF(rse.APPLICATION,'') IN ('Donation','Recurring gift','Planned gift','Matching gift'))
      )
      AND (NULLIF(rse.[TYPE],'') IS NULL OR NULLIF(rse.[TYPE],'') NOT IN ('Membership'))
),
TransactionAgg_post AS (
    SELECT el.FinancialTransactionID, SUM(el.NetAmount) AS Amount
    FROM EligibleLines_post el
    GROUP BY el.FinancialTransactionID
    HAVING SUM(el.NetAmount) <> 0
),
SalesOrdersByPayment_post AS (
    SELECT sop.PAYMENTID, MIN(sop.SALESORDERID) AS SalesOrderID
    FROM SALESORDERPAYMENT sop
    GROUP BY sop.PAYMENTID
)
SELECT
    (SELECT COUNT(*) FROM TransactionAgg_post)                          AS postfix_eligible_ft_count,
    (SELECT COUNT(*) FROM TransactionAgg_post ta
        WHERE EXISTS (SELECT 1 FROM SALESORDER s WHERE s.REVENUEID = ta.FinancialTransactionID)
           OR EXISTS (SELECT 1 FROM SalesOrdersByPayment_post sop WHERE sop.PAYMENTID = ta.FinancialTransactionID)) AS postfix_donation_pos_rows,
    (SELECT COUNT(*) FROM TransactionAgg_post ta
        WHERE EXISTS (SELECT 1 FROM SALESORDER s WHERE s.REVENUEID = ta.FinancialTransactionID))                   AS revenue_backed_only,
    (SELECT COUNT(*) FROM TransactionAgg_post ta
        WHERE NOT EXISTS (SELECT 1 FROM SALESORDER s WHERE s.REVENUEID = ta.FinancialTransactionID)
          AND EXISTS (SELECT 1 FROM SalesOrdersByPayment_post sop WHERE sop.PAYMENTID = ta.FinancialTransactionID)) AS payment_backed_only_new;

PRINT '=== R3: anchor — sample 5 payment-backed donations (NEW coverage) ===';
WITH MembershipLineItems AS (
    SELECT mli.ID AS MembershipLineItemID FROM FINANCIALTRANSACTIONLINEITEM mli
    INNER JOIN REVENUESPLIT_EXT rse ON rse.ID = mli.ID
    WHERE rse.APPLICATION = 'Membership' AND mli.[TYPE] = 'Standard'
),
EligibleLines AS (
    SELECT dli.FINANCIALTRANSACTIONID AS FinancialTransactionID,
           CASE WHEN dli.[TYPE]='Reversal' THEN -1*dli.TRANSACTIONAMOUNT ELSE dli.TRANSACTIONAMOUNT END AS NetAmount
    FROM FINANCIALTRANSACTIONLINEITEM dli
    INNER JOIN FINANCIALTRANSACTION ft ON ft.ID = dli.FINANCIALTRANSACTIONID
    LEFT JOIN REVENUESPLIT_EXT rse ON rse.ID = dli.ID
    WHERE dli.[TYPE] IN ('Standard','Reversal') AND ft.TYPECODE NOT IN (1,2,20)
      AND NOT EXISTS (SELECT 1 FROM FINANCIALTRANSACTIONLINEITEM src INNER JOIN FINANCIALTRANSACTION ft_pledge ON ft_pledge.ID = src.FINANCIALTRANSACTIONID AND ft_pledge.TYPECODE = 1 WHERE dli.SOURCELINEITEMID = src.ID)
      AND NOT EXISTS (SELECT 1 FROM MembershipLineItems m WHERE m.MembershipLineItemID IN (dli.SOURCELINEITEMID, dli.REVERSEDLINEITEMID))
      AND ((dli.[TYPE]='Reversal' AND EXISTS (SELECT 1 FROM FINANCIALTRANSACTIONLINEITEM reversed_dli LEFT JOIN REVENUESPLIT_EXT reversed_rse ON reversed_rse.ID = reversed_dli.ID WHERE reversed_dli.ID = dli.REVERSEDLINEITEMID AND NULLIF(reversed_rse.APPLICATION,'') IN ('Donation','Recurring gift','Planned gift','Matching gift')))
           OR (dli.[TYPE]<>'Reversal' AND NULLIF(rse.APPLICATION,'') IN ('Donation','Recurring gift','Planned gift','Matching gift')))
      AND (NULLIF(rse.[TYPE],'') IS NULL OR NULLIF(rse.[TYPE],'') NOT IN ('Membership'))
),
TransactionAgg AS (
    SELECT el.FinancialTransactionID, SUM(el.NetAmount) AS Amount FROM EligibleLines el GROUP BY el.FinancialTransactionID HAVING SUM(el.NetAmount) <> 0
),
SalesOrdersByPayment AS (SELECT sop.PAYMENTID, MIN(sop.SALESORDERID) AS SalesOrderID FROM SALESORDERPAYMENT sop GROUP BY sop.PAYMENTID)
SELECT TOP 5
    CAST(ta.FinancialTransactionID AS NVARCHAR(36)) AS ft_id,
    ft.CALCULATEDUSERDEFINEDID                       AS rev_id,
    ft.[TYPE]                                        AS ft_type,
    CAST(ta.Amount AS NVARCHAR(20))                  AS net_amount,
    CAST(sop.SalesOrderID AS NVARCHAR(36))           AS payment_backed_so_id,
    payment_so.LOOKUPID                              AS payment_backed_lookup
FROM TransactionAgg ta
INNER JOIN FINANCIALTRANSACTION ft ON ft.ID = ta.FinancialTransactionID
INNER JOIN SalesOrdersByPayment sop ON sop.PAYMENTID = ta.FinancialTransactionID
INNER JOIN SALESORDER payment_so ON payment_so.ID = sop.SalesOrderID
WHERE NOT EXISTS (SELECT 1 FROM SALESORDER s WHERE s.REVENUEID = ta.FinancialTransactionID)
ORDER BY ta.Amount DESC;

PRINT '=== R4: membership POS — count of SALESORDERITEMMEMBERSHIP ===';
SELECT
    (SELECT COUNT(*) FROM SALESORDERITEMMEMBERSHIP) AS sales_order_item_membership_total;

PRINT '=== R5: pledge POS — sample pledges WITHOUT existing sales order ===';
SELECT
    (SELECT COUNT(*) FROM FINANCIALTRANSACTION ft WHERE ft.TYPECODE = 1) AS pledge_ft_total,
    (SELECT COUNT(*) FROM FINANCIALTRANSACTION ft WHERE ft.TYPECODE = 1
        AND NOT EXISTS (SELECT 1 FROM SALESORDER so WHERE so.REVENUEID = ft.ID)) AS pledge_without_so_count;
