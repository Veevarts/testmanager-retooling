DECLARE @useDateFrom BIT = IIF(@hasDateFilterFrom = 1, 1, 0);
DECLARE @useDateTo BIT = IIF(@hasDateFilterTo = 1, 1, 0);
DECLARE @filterDateFrom DATE = CAST(@dateFilterFrom AS DATE);
DECLARE @filterDateTo DATE = CAST(@dateFilterTo AS DATE);

/*
title: Sales Order Only Pledge
product: POS Purchase
description: Creates Sales Order Only Pledge from FINANCIALTRANSACTION when TYPECODE = 1 (Pledge) without sales order linkage.
tables: FINANCIALTRANSACTION, CONSTITUENT, CONSTITUENTHOUSEHOLD
*/

SELECT
    ft.ID AS Implementation_External_ID__c,
    NULL AS LookUp_ID_Legacy,
    ft.CALCULATEDUSERDEFINEDID AS Revenue_ID_legacy__c,
    NULL AS Auctifera__Source__c,
    'Pending' AS Auctifera__Status__c,
    COALESCE(ft.TRANSACTIONAMOUNT, 0) AS Auctifera__Subtotal_before_discount__c,
    COALESCE(ft.TRANSACTIONAMOUNT, 0) AS Auctifera__Subtotal__c,
    COALESCE(ft.TRANSACTIONAMOUNT, 0) AS Auctifera__Total__c,
    CASE
        WHEN c.ISORGANIZATION = 0
         AND c.ISGROUP = 0
         AND c.ISCONSTITUENT = 1 THEN ft.CONSTITUENTID
        ELSE NULL
    END AS Auctifera__Client__c,
    CASE
        WHEN c.ISORGANIZATION = 1
         OR c.ISGROUP = 1
         OR c.ISCONSTITUENT = 0 THEN ft.CONSTITUENTID
        ELSE chh.HOUSEHOLDID
    END AS Auctifera__Client2__c,
    NULL AS Auctifera__Postal_Code__c,
    1 AS Auctifera__Prevent_Email_Notification__c,
    CAST(COALESCE(ft.CALCULATEDDATE, ft.DATEADDED) AS DATE) AS Auctifera__Transaction_Date__c
FROM FINANCIALTRANSACTION ft
LEFT JOIN CONSTITUENT c
    ON c.ID = ft.CONSTITUENTID
LEFT JOIN CONSTITUENTHOUSEHOLD chh
    ON c.ID = chh.ID
WHERE ft.TYPECODE = 1 -- Pledge
AND (@useDateFrom = 0 OR CAST(COALESCE(ft.CALCULATEDDATE, ft.DATEADDED) AS DATE) >= @filterDateFrom)
AND (@useDateTo = 0 OR CAST(COALESCE(ft.CALCULATEDDATE, ft.DATEADDED) AS DATE) <= @filterDateTo)
ORDER BY ft.CALCULATEDDATE DESC;
