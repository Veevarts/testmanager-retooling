DECLARE @useDateFrom BIT = IIF(@hasDateFilterFrom = 1, 1, 0);
DECLARE @useDateTo BIT = IIF(@hasDateFilterTo = 1, 1, 0);
DECLARE @filterDateFrom DATE = CAST(@dateFilterFrom AS DATE);
DECLARE @filterDateTo DATE = CAST(@dateFilterTo AS DATE);

;WITH MembershipFinancialTransactions AS (
    SELECT DISTINCT
        ftl.FINANCIALTRANSACTIONID
    FROM
        FINANCIALTRANSACTIONLINEITEM ftl
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
        SALESORDER so
LEFT JOIN FINANCIALTRANSACTION ft
    ON
        so.REVENUEID = ft.ID
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
        so.STATUSCODE NOT IN (0, 6, 7)
        AND (
        EXISTS (
        SELECT
                1
        FROM
                SALESORDERITEM soi
        INNER JOIN SALESORDERITEMMEMBERSHIP soit
        ON
                soi.ID = soit.ID
        WHERE
                soi.SALESORDERID = so.ID
)
        OR EXISTS (
        SELECT
                1
        FROM
                SALESORDERITEM soi
        INNER JOIN SALESORDERITEMMEMBERSHIPADDON soima
        ON
                soi.ID = soima.ID
        WHERE
                soi.SALESORDERID = so.ID
)
        OR so.REVENUEID IN (
        SELECT
                mft.FINANCIALTRANSACTIONID
        FROM
                MembershipFinancialTransactions mft
)
        OR EXISTS (
        SELECT
                1
        FROM
                SALESORDERPAYMENT sop
        INNER JOIN MembershipFinancialTransactions mft
        ON
                mft.FINANCIALTRANSACTIONID = sop.PAYMENTID
        WHERE
                sop.SALESORDERID = so.ID
)
)
AND (@useDateFrom = 0 OR CAST(COALESCE(so.TRANSACTIONDATE, so.DATEADDED) AS DATE) >= @filterDateFrom)
AND (@useDateTo = 0 OR CAST(COALESCE(so.TRANSACTIONDATE, so.DATEADDED) AS DATE) <= @filterDateTo)
