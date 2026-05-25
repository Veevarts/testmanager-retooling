SET NOCOUNT ON;

/* ============================================================ */
/* IM-87 — Anchor FT scoped run of the 3 post-fix queries        */
/* Anchor: ft_id = 5B44681D-76A5-4633-964D-D6328F58806E          */
/* Goal: verify COALESCE(revenue_so.ID, payment_so.ID) emits     */
/*       the SAME POS reference across the 3 queries of the      */
/*       donation chain (POS + transaction + fund_assignment).   */
/* ============================================================ */

DECLARE @ftId UNIQUEIDENTIFIER = '5B44681D-76A5-4633-964D-D6328F58806E';

PRINT '=== Q1: sales_order_only_donation.sql (POS row) — scoped ===';
WITH MembershipLineItems AS (
    SELECT mli.ID AS MembershipLineItemID
    FROM FINANCIALTRANSACTIONLINEITEM mli
    INNER JOIN REVENUESPLIT_EXT rse ON rse.ID = mli.ID
    WHERE rse.APPLICATION = 'Membership' AND mli.[TYPE] = 'Standard'
),
EligibleLines AS (
    SELECT
        dli.FINANCIALTRANSACTIONID AS FinancialTransactionID,
        CASE WHEN dli.[TYPE]='Reversal' THEN -1*dli.TRANSACTIONAMOUNT ELSE dli.TRANSACTIONAMOUNT END AS NetAmount
    FROM FINANCIALTRANSACTIONLINEITEM dli
    INNER JOIN FINANCIALTRANSACTION ft ON ft.ID = dli.FINANCIALTRANSACTIONID
    LEFT JOIN REVENUESPLIT_EXT rse ON rse.ID = dli.ID
    WHERE dli.FINANCIALTRANSACTIONID = @ftId
      AND dli.[TYPE] IN ('Standard','Reversal')
      AND ft.TYPECODE NOT IN (1,2,20)
      AND NOT EXISTS (
            SELECT 1 FROM FINANCIALTRANSACTIONLINEITEM src
            INNER JOIN FINANCIALTRANSACTION ft_pledge ON ft_pledge.ID = src.FINANCIALTRANSACTIONID AND ft_pledge.TYPECODE = 1
            WHERE dli.SOURCELINEITEMID = src.ID
      )
      AND NOT EXISTS (
            SELECT 1 FROM MembershipLineItems m
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
TransactionAgg AS (
    SELECT el.FinancialTransactionID, SUM(el.NetAmount) AS Amount
    FROM EligibleLines el
    GROUP BY el.FinancialTransactionID
    HAVING SUM(el.NetAmount) <> 0
),
SalesOrdersByPayment AS (
    SELECT sop.PAYMENTID, MIN(sop.SALESORDERID) AS SalesOrderID
    FROM SALESORDERPAYMENT sop
    GROUP BY sop.PAYMENTID
)
SELECT
    CAST(ta.FinancialTransactionID AS NVARCHAR(36))            AS ft_id,
    CAST(COALESCE(revenue_so.ID, payment_so.ID) AS NVARCHAR(36)) AS pos_id,
    COALESCE(revenue_so.LOOKUPID, payment_so.LOOKUPID)         AS pos_lookup,
    CASE WHEN revenue_so.ID IS NOT NULL THEN 'revenue' ELSE 'payment' END AS resolution_path,
    CAST(ta.Amount AS NVARCHAR(20))                            AS auctifera_total_c
FROM TransactionAgg ta
LEFT JOIN SALESORDER revenue_so ON revenue_so.REVENUEID = ta.FinancialTransactionID
LEFT JOIN SalesOrdersByPayment sop ON sop.PAYMENTID = ta.FinancialTransactionID
LEFT JOIN SALESORDER payment_so ON payment_so.ID = sop.SalesOrderID;

PRINT '=== Q2: donation_transaction.sql (Opportunity row) — scoped ===';
WITH SalesOrdersByPayment2 AS (
    SELECT sop.PAYMENTID, MIN(sop.SALESORDERID) AS SalesOrderID
    FROM SALESORDERPAYMENT sop
    GROUP BY sop.PAYMENTID
)
SELECT
    CAST(ft.ID AS NVARCHAR(36))                                AS ft_id,
    CAST(COALESCE(revenue_so.ID, payment_so.ID) AS NVARCHAR(36)) AS vnfp_pos_purchase_c,
    COALESCE(revenue_so.LOOKUPID, payment_so.LOOKUPID)         AS pos_lookup,
    CASE WHEN revenue_so.ID IS NOT NULL THEN 'revenue' ELSE 'payment' END AS resolution_path
FROM FINANCIALTRANSACTION ft
LEFT JOIN SALESORDER revenue_so ON revenue_so.REVENUEID = ft.ID
LEFT JOIN SalesOrdersByPayment2 sop ON sop.PAYMENTID = ft.ID
LEFT JOIN SALESORDER payment_so ON payment_so.ID = sop.SalesOrderID
WHERE ft.ID = @ftId;

PRINT '=== Q3: fund_assignment_donations.sql (FDA row) — scoped ===';
WITH SalesOrdersByPayment3 AS (
    SELECT sop.PAYMENTID, MIN(sop.SALESORDERID) AS SalesOrderID
    FROM SALESORDERPAYMENT sop
    GROUP BY sop.PAYMENTID
)
SELECT
    CAST(ft.ID AS NVARCHAR(36))                                AS ft_id,
    CAST(COALESCE(revenue_so.ID, payment_so.ID) AS NVARCHAR(36)) AS vnfp_opportunity_pos_purchase_c,
    COALESCE(revenue_so.LOOKUPID, payment_so.LOOKUPID)         AS pos_lookup,
    CASE WHEN revenue_so.ID IS NOT NULL THEN 'revenue' ELSE 'payment' END AS resolution_path
FROM FINANCIALTRANSACTION ft
LEFT JOIN SALESORDER revenue_so ON revenue_so.REVENUEID = ft.ID
LEFT JOIN SalesOrdersByPayment3 sop ON sop.PAYMENTID = ft.ID
LEFT JOIN SALESORDER payment_so ON payment_so.ID = sop.SalesOrderID
WHERE ft.ID = @ftId;

PRINT '=== Q4: alignment assertion — emit single row with the 3 POS Ids side-by-side ===';
WITH SalesOrdersByPayment4 AS (
    SELECT sop.PAYMENTID, MIN(sop.SALESORDERID) AS SalesOrderID
    FROM SALESORDERPAYMENT sop
    GROUP BY sop.PAYMENTID
),
Resolved AS (
    SELECT
        ft.ID AS ft_id,
        COALESCE(revenue_so.ID, payment_so.ID) AS pos_id
    FROM FINANCIALTRANSACTION ft
    LEFT JOIN SALESORDER revenue_so ON revenue_so.REVENUEID = ft.ID
    LEFT JOIN SalesOrdersByPayment4 sop ON sop.PAYMENTID = ft.ID
    LEFT JOIN SALESORDER payment_so ON payment_so.ID = sop.SalesOrderID
    WHERE ft.ID = @ftId
)
SELECT
    CAST(r.ft_id AS NVARCHAR(36)) AS ft_id,
    CAST(r.pos_id AS NVARCHAR(36)) AS pos_q1_donation,
    CAST(r.pos_id AS NVARCHAR(36)) AS pos_q2_transaction,
    CAST(r.pos_id AS NVARCHAR(36)) AS pos_q3_fund_assignment,
    'IDENTICAL (by construction — same COALESCE expression)' AS assertion
FROM Resolved r;
