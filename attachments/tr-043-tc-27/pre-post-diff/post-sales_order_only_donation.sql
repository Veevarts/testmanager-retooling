DECLARE @useDateFrom BIT = IIF(@hasDateFilterFrom = 1, 1, 0);
DECLARE @useDateTo BIT = IIF(@hasDateFilterTo = 1, 1, 0);
DECLARE @filterDateFrom DATE = CAST(@dateFilterFrom AS DATE);
DECLARE @filterDateTo DATE = CAST(@dateFilterTo AS DATE);

;WITH MembershipLineItems AS (
    SELECT
        mli.ID AS MembershipLineItemID
    FROM FINANCIALTRANSACTIONLINEITEM mli
    INNER JOIN REVENUESPLIT_EXT rse
        ON rse.ID = mli.ID
    WHERE rse.APPLICATION = 'Membership'
      AND mli.[TYPE] = 'Standard'
),
EligibleLines AS (
    SELECT
        dli.FINANCIALTRANSACTIONID AS FinancialTransactionID,
        CASE
            WHEN dli.[TYPE] = 'Reversal' THEN -1 * dli.TRANSACTIONAMOUNT
            ELSE dli.TRANSACTIONAMOUNT
        END AS NetAmount
    FROM FINANCIALTRANSACTIONLINEITEM dli
    INNER JOIN FINANCIALTRANSACTION ft
        ON ft.ID = dli.FINANCIALTRANSACTIONID
    LEFT JOIN REVENUESPLIT_EXT rse
        ON rse.ID = dli.ID
    WHERE dli.[TYPE] IN ('Standard', 'Reversal')
      AND ft.TYPECODE NOT IN (1, 2, 20) -- Exclude pledge, recurring gift, write-off
      AND NOT EXISTS (
            SELECT 1
            FROM FINANCIALTRANSACTIONLINEITEM src
            INNER JOIN FINANCIALTRANSACTION ft_pledge
                ON ft_pledge.ID = src.FINANCIALTRANSACTIONID
               AND ft_pledge.TYPECODE = 1
            WHERE dli.SOURCELINEITEMID = src.ID
      )
      AND NOT EXISTS (
            SELECT 1
            FROM MembershipLineItems m
            WHERE m.MembershipLineItemID IN (dli.SOURCELINEITEMID, dli.REVERSEDLINEITEMID)
      )
      AND (
            (
                dli.[TYPE] = 'Reversal'
                AND EXISTS (
                    SELECT 1
                    FROM FINANCIALTRANSACTIONLINEITEM reversed_dli
                    LEFT JOIN REVENUESPLIT_EXT reversed_rse
                        ON reversed_rse.ID = reversed_dli.ID
                    WHERE reversed_dli.ID = dli.REVERSEDLINEITEMID
                      AND NULLIF(reversed_rse.APPLICATION, '') IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
                )
            )
            OR (
                dli.[TYPE] <> 'Reversal'
                AND NULLIF(rse.APPLICATION, '') IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
            )
      )
      AND (
            NULLIF(rse.[TYPE], '') IS NULL
            OR NULLIF(rse.[TYPE], '') NOT IN ('Membership')
      )
),
TransactionAgg AS (
    SELECT
        el.FinancialTransactionID,
        SUM(el.NetAmount) AS Amount
    FROM EligibleLines el
    GROUP BY el.FinancialTransactionID
    HAVING SUM(el.NetAmount) <> 0
),
SalesOrdersByPayment AS (
    SELECT
        sop.PAYMENTID,
        MIN(sop.SALESORDERID) AS SalesOrderID
    FROM SALESORDERPAYMENT sop
    GROUP BY sop.PAYMENTID
)
SELECT
    COALESCE(revenue_so.ID, payment_so.ID) AS Implementation_External_ID__c,
    COALESCE(revenue_so.LOOKUPID, payment_so.LOOKUPID) AS LookUp_ID_Legacy,
    ft.CALCULATEDUSERDEFINEDID AS Revenue_ID_legacy__c,
    COALESCE(revenue_so.SALESMETHODTYPE, payment_so.SALESMETHODTYPE) AS Auctifera__Source__c,
    CASE
        WHEN COALESCE(revenue_so.REFUNDSTATUS, payment_so.REFUNDSTATUS) IS NOT NULL
             AND COALESCE(revenue_so.REFUNDSTATUS, payment_so.REFUNDSTATUS) = 2 THEN 'Refunded'
	    WHEN COALESCE(revenue_so.STATUSCODE, payment_so.STATUSCODE) IN (1, 2, 3, 4) THEN 'Sold'
        WHEN COALESCE(revenue_so.STATUSCODE, payment_so.STATUSCODE) = 0 THEN 'Pending'
        WHEN COALESCE(revenue_so.STATUSCODE, payment_so.STATUSCODE) = 5 THEN 'Canceled'
        WHEN COALESCE(revenue_so.STATUSCODE, payment_so.STATUSCODE) IN (6, 7) THEN 'Pending'
        ELSE 'Pending'
    END AS Auctifera__Status__c,
    COALESCE(ta.Amount, 0) AS Auctifera__Subtotal_before_discount__c,
    COALESCE(ta.Amount, 0) AS Auctifera__Subtotal__c,
    COALESCE(ta.Amount, 0) AS Auctifera__Total__c,
    CASE
            WHEN c.ISORGANIZATION = 0
            AND c.ISGROUP = 0
            AND c.ISCONSTITUENT = 1 
    THEN COALESCE(revenue_so.CONSTITUENTID, payment_so.CONSTITUENTID)
            ELSE NULL
    END AS Auctifera__Client__c,
    CASE
            WHEN c.ISORGANIZATION = 1
            OR c.ISGROUP = 1
            OR c.ISCONSTITUENT = 0 
    THEN COALESCE(revenue_so.CONSTITUENTID, payment_so.CONSTITUENTID)
            ELSE chh.HOUSEHOLDID
    END AS Auctifera__Client2__c,
    addr.POSTCODE AS Auctifera__Postal_Code__c,
    1 AS Auctifera__Prevent_Email_Notification__c,
    CAST(
        COALESCE(
            revenue_so.TRANSACTIONDATE,
            payment_so.TRANSACTIONDATE,
            revenue_so.DATEADDED,
            payment_so.DATEADDED
        ) AS DATE
    ) AS Auctifera__Transaction_Date__c
FROM TransactionAgg ta
INNER JOIN FINANCIALTRANSACTION ft
    ON ft.ID = ta.FinancialTransactionID
LEFT JOIN SALESORDER revenue_so
    ON revenue_so.REVENUEID = ft.ID
LEFT JOIN SalesOrdersByPayment sop
    ON sop.PAYMENTID = ft.ID
LEFT JOIN SALESORDER payment_so
    ON payment_so.ID = sop.SalesOrderID
LEFT JOIN ADDRESS addr
    ON addr.ID = COALESCE(revenue_so.ADDRESSID, payment_so.ADDRESSID)
LEFT JOIN CONSTITUENT c
    ON c.ID = ft.CONSTITUENTID
LEFT JOIN CONSTITUENTHOUSEHOLD chh
    ON c.ID = chh.ID
WHERE
    COALESCE(revenue_so.ID, payment_so.ID) IS NOT NULL
    AND (@useDateFrom = 0 OR CAST(COALESCE(revenue_so.TRANSACTIONDATE, payment_so.TRANSACTIONDATE, revenue_so.DATEADDED, payment_so.DATEADDED) AS DATE) >= @filterDateFrom)
    AND (@useDateTo = 0 OR CAST(COALESCE(revenue_so.TRANSACTIONDATE, payment_so.TRANSACTIONDATE, revenue_so.DATEADDED, payment_so.DATEADDED) AS DATE) <= @filterDateTo)
