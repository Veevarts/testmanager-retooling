DECLARE @useDateFrom BIT = IIF(@hasDateFilterFrom = 1, 1, 0);
DECLARE @useDateTo BIT = IIF(@hasDateFilterTo = 1, 1, 0);
DECLARE @filterDateFrom DATE = CAST(@dateFilterFrom AS DATE);
DECLARE @filterDateTo DATE = CAST(@dateFilterTo AS DATE);

;WITH 
MembershipLineItems AS (
SELECT
        mli.ID AS MembershipLineItemID,
        mli.FINANCIALTRANSACTIONID AS FinancialTransactionId
FROM
        FINANCIALTRANSACTIONLINEITEM mli
INNER JOIN REVENUESPLIT_EXT rse
        ON
        rse.ID = mli.ID
WHERE
        rse.APPLICATION = 'Membership'
        AND mli.[TYPE] = 'Standard'
),
DonationLineItems AS (
SELECT
        ft.ID AS FinancialTransactionID,
        ft.CALCULATEDUSERDEFINEDID AS Revenue_ID_legacy__c,
        dli.ID AS LineItemID,
        dli.TRANSACTIONAMOUNT AS DonationAmount,
        rse.APPLICATION  AS Application,
        rse.[TYPE] AS Type,
        dli.SOURCELINEITEMID
FROM
        FINANCIALTRANSACTIONLINEITEM dli
INNER JOIN REVENUESPLIT_EXT rse
        ON
        rse.ID = dli.ID
        AND rse.APPLICATION IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
        AND rse.[TYPE] NOT IN ('Membership')
INNER JOIN FINANCIALTRANSACTION ft
        ON
        ft.ID = dli.FINANCIALTRANSACTIONID
WHERE
        dli.[TYPE] = 'Standard'
        AND NOT EXISTS (
        SELECT
                1
        FROM
                MembershipLineItems m
        WHERE
                m.FinancialTransactionId = dli.FINANCIALTRANSACTIONID
        )
),
DonationTransactions AS (
SELECT DISTINCT
        dli.FinancialTransactionID
FROM
        DonationLineItems dli
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
        DonationTransactions dt
INNER JOIN FINANCIALTRANSACTION ft
    ON
        ft.ID = dt.FinancialTransactionID
INNER JOIN SALESORDER so
    ON
        so.REVENUEID = ft.ID
LEFT JOIN ADDRESS addr
    ON
        so.ADDRESSID = addr.ID
LEFT JOIN CONSTITUENT c
    ON
        c.ID = ft.CONSTITUENTID
LEFT JOIN CONSTITUENTHOUSEHOLD chh
    ON
        c.ID = chh.ID
WHERE
        1 = 1
        AND (@useDateFrom = 0 OR CAST(COALESCE(so.TRANSACTIONDATE, so.DATEADDED) AS DATE) >= @filterDateFrom)
        AND (@useDateTo = 0 OR CAST(COALESCE(so.TRANSACTIONDATE, so.DATEADDED) AS DATE) <= @filterDateTo)
