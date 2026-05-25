SET NOCOUNT ON;

DECLARE @ftId UNIQUEIDENTIFIER = 'D3966BA0-2FAE-4930-9A91-29BC8827D6DA';

PRINT '=== Anchor #2: COALESCE alignment in real data ===';
WITH SalesOrdersByPayment AS (
    SELECT sop.PAYMENTID, MIN(sop.SALESORDERID) AS SalesOrderID
    FROM SALESORDERPAYMENT sop
    GROUP BY sop.PAYMENTID
)
SELECT
    CAST(ft.ID AS NVARCHAR(36))                                AS ft_id,
    CAST(COALESCE(revenue_so.ID, payment_so.ID) AS NVARCHAR(36)) AS pos_id_resolved,
    COALESCE(revenue_so.LOOKUPID, payment_so.LOOKUPID)         AS pos_lookup,
    CASE WHEN revenue_so.ID IS NOT NULL THEN 'revenue' ELSE 'payment' END AS resolution_path
FROM FINANCIALTRANSACTION ft
LEFT JOIN SALESORDER revenue_so ON revenue_so.REVENUEID = ft.ID
LEFT JOIN SalesOrdersByPayment sop ON sop.PAYMENTID = ft.ID
LEFT JOIN SALESORDER payment_so ON payment_so.ID = sop.SalesOrderID
WHERE ft.ID = @ftId;

PRINT '=== Net amount via TransactionAgg ===';
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
      AND NOT EXISTS (SELECT 1 FROM FINANCIALTRANSACTIONLINEITEM src INNER JOIN FINANCIALTRANSACTION ft_pledge ON ft_pledge.ID = src.FINANCIALTRANSACTIONID AND ft_pledge.TYPECODE = 1 WHERE dli.SOURCELINEITEMID = src.ID)
      AND NOT EXISTS (SELECT 1 FROM MembershipLineItems m WHERE m.MembershipLineItemID IN (dli.SOURCELINEITEMID, dli.REVERSEDLINEITEMID))
      AND ((dli.[TYPE]='Reversal' AND EXISTS (SELECT 1 FROM FINANCIALTRANSACTIONLINEITEM reversed_dli LEFT JOIN REVENUESPLIT_EXT reversed_rse ON reversed_rse.ID = reversed_dli.ID WHERE reversed_dli.ID = dli.REVERSEDLINEITEMID AND NULLIF(reversed_rse.APPLICATION,'') IN ('Donation','Recurring gift','Planned gift','Matching gift')))
           OR (dli.[TYPE]<>'Reversal' AND NULLIF(rse.APPLICATION,'') IN ('Donation','Recurring gift','Planned gift','Matching gift')))
      AND (NULLIF(rse.[TYPE],'') IS NULL OR NULLIF(rse.[TYPE],'') NOT IN ('Membership'))
)
SELECT CAST(SUM(NetAmount) AS NVARCHAR(20)) AS auctifera_total_c FROM EligibleLines;
