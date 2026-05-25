DECLARE @useDateFrom BIT = IIF(@hasDateFilterFrom = 1, 1, 0);
DECLARE @useDateTo BIT = IIF(@hasDateFilterTo = 1, 1, 0);
DECLARE @filterDateFrom DATE = CAST(@dateFilterFrom AS DATE);
DECLARE @filterDateTo DATE = CAST(@dateFilterTo AS DATE);

;WITH MembershipFinancialTransactions AS (
    SELECT DISTINCT
        ftl.FINANCIALTRANSACTIONID
    FROM FINANCIALTRANSACTIONLINEITEM ftl
    LEFT JOIN REVENUESPLIT_EXT direct_rse
        ON direct_rse.ID = ftl.ID
       AND direct_rse.APPLICATION IN ('Membership', 'Membership add-on')
    LEFT JOIN REVENUESPLIT_EXT source_rse
        ON source_rse.ID = ftl.SOURCELINEITEMID
       AND source_rse.APPLICATION IN ('Membership', 'Membership add-on')
    LEFT JOIN CREDITITEMMEMBERSHIP cim
        ON cim.ID = ftl.ID
        OR cim.ID = ftl.SOURCELINEITEMID
    WHERE
        ftl.[TYPE] = 'Standard'
        AND (
            direct_rse.ID IS NOT NULL
            OR source_rse.ID IS NOT NULL
            OR cim.ID IS NOT NULL
        )
),
EligibleLines AS (
    SELECT
        dli.FINANCIALTRANSACTIONID AS FinancialTransactionID,
        CASE
            WHEN dli.[TYPE] = 'Reversal' THEN -1 * dli.TRANSACTIONAMOUNT
            ELSE dli.TRANSACTIONAMOUNT
        END AS NetAmount
    FROM FINANCIALTRANSACTIONLINEITEM dli
    LEFT JOIN REVENUESPLIT_EXT rse
        ON rse.ID = dli.ID
    WHERE dli.[TYPE] IN ('Standard', 'Reversal')
      AND (
            (
                dli.[TYPE] = 'Reversal'
                AND EXISTS (
                    SELECT 1
                    FROM FINANCIALTRANSACTIONLINEITEM reversed_dli
                    LEFT JOIN REVENUESPLIT_EXT reversed_rse
                        ON reversed_rse.ID = reversed_dli.ID
                    WHERE reversed_dli.ID = dli.REVERSEDLINEITEMID
                      AND NULLIF(reversed_rse.APPLICATION, '') IN ('Membership', 'Membership add-on')
                )
            )
            OR (
                dli.[TYPE] <> 'Reversal'
                AND NULLIF(rse.APPLICATION, '') IN ('Membership', 'Membership add-on')
            )
      )
),
TransactionAgg AS (
    SELECT
        el.FinancialTransactionID,
        SUM(el.NetAmount) AS Amount
    FROM EligibleLines el
    GROUP BY el.FinancialTransactionID
),
ResolvedSalesOrders AS (
    SELECT DISTINCT
        so.ID AS SalesOrderID,
        COALESCE(revenue_mft.FinancialTransactionID, payment_mft.FinancialTransactionID, so.REVENUEID) AS FinancialTransactionID
    FROM SALESORDER so
    OUTER APPLY (
        SELECT TOP 1
            mft.FINANCIALTRANSACTIONID AS FinancialTransactionID
        FROM MembershipFinancialTransactions mft
        WHERE mft.FINANCIALTRANSACTIONID = so.REVENUEID
    ) revenue_mft
    OUTER APPLY (
        SELECT TOP 1
            sop.PAYMENTID AS FinancialTransactionID
        FROM SALESORDERPAYMENT sop
        INNER JOIN MembershipFinancialTransactions mft
            ON mft.FINANCIALTRANSACTIONID = sop.PAYMENTID
        WHERE sop.SALESORDERID = so.ID
        ORDER BY sop.PAYMENTID
    ) payment_mft
    WHERE
        so.STATUSCODE NOT IN (0, 6, 7)
        AND (
            EXISTS (
                SELECT 1
                FROM SALESORDERITEM soi
                INNER JOIN SALESORDERITEMMEMBERSHIP soim
                    ON soi.ID = soim.ID
                WHERE soi.SALESORDERID = so.ID
            )
            OR EXISTS (
                SELECT 1
                FROM SALESORDERITEM soi
                INNER JOIN SALESORDERITEMMEMBERSHIPADDON soima
                    ON soi.ID = soima.ID
                WHERE soi.SALESORDERID = so.ID
            )
            OR so.REVENUEID IN (
                SELECT mft.FINANCIALTRANSACTIONID
                FROM MembershipFinancialTransactions mft
            )
            OR EXISTS (
                SELECT 1
                FROM SALESORDERPAYMENT sop
                INNER JOIN MembershipFinancialTransactions mft
                    ON mft.FINANCIALTRANSACTIONID = sop.PAYMENTID
                WHERE sop.SALESORDERID = so.ID
            )
        )
)
SELECT
    so.ID AS Implementation_External_ID__c,
    so.LOOKUPID AS LookUp_ID_Legacy,
    ft.CALCULATEDUSERDEFINEDID AS Revenue_ID_legacy__c,
    so.SALESMETHODTYPE AS Auctifera__Source__c,
    CASE
        WHEN so.REFUNDSTATUS IS NOT NULL AND so.REFUNDSTATUS = 2 THEN 'Refunded'
	    WHEN so.STATUSCODE IN (1, 2, 3, 4) THEN 'Sold'
        WHEN so.STATUSCODE = 0 THEN 'Pending'
        WHEN so.STATUSCODE = 5 THEN 'Canceled'
        WHEN so.STATUSCODE IN (6, 7) THEN 'Pending'
        ELSE 'Pending'
    END AS Auctifera__Status__c,
    COALESCE(ta.Amount, 0) AS Auctifera__Subtotal_before_discount__c,
    COALESCE(ta.Amount, 0) AS Auctifera__Subtotal__c,
    COALESCE(ta.Amount, 0) AS Auctifera__Total__c,
    CASE
            WHEN c.ISORGANIZATION = 0
            AND c.ISGROUP = 0
            AND c.ISCONSTITUENT = 1 
    THEN so.CONSTITUENTID
            ELSE NULL
    END AS Auctifera__Client__c,
    CASE
            WHEN c.ISORGANIZATION = 1
            OR c.ISGROUP = 1
            OR c.ISCONSTITUENT = 0 
    THEN so.CONSTITUENTID
            ELSE chh.HOUSEHOLDID
    END AS Auctifera__Client2__c,
    addr.POSTCODE AS Auctifera__Postal_Code__c,
    1 AS Auctifera__Prevent_Email_Notification__c,
    CAST(COALESCE(so.TRANSACTIONDATE, so.DATEADDED) AS DATE) AS Auctifera__Transaction_Date__c
FROM
        ResolvedSalesOrders rso
LEFT JOIN TransactionAgg ta
    ON ta.FinancialTransactionID = rso.FinancialTransactionID
LEFT JOIN FINANCIALTRANSACTION ft
    ON
        ft.ID = rso.FinancialTransactionID
INNER JOIN SALESORDER so
    ON
        so.ID = rso.SalesOrderID
LEFT JOIN ADDRESS addr
    ON
        so.ADDRESSID = addr.ID
LEFT JOIN CONSTITUENTHOUSEHOLD
 chh
    ON
        so.CONSTITUENTID = chh.ID
LEFT JOIN CONSTITUENT c ON
        c.ID = so.CONSTITUENTID
WHERE
        (@useDateFrom = 0 OR CAST(COALESCE(so.TRANSACTIONDATE, so.DATEADDED) AS DATE) >= @filterDateFrom)
        AND (@useDateTo = 0 OR CAST(COALESCE(so.TRANSACTIONDATE, so.DATEADDED) AS DATE) <= @filterDateTo)
