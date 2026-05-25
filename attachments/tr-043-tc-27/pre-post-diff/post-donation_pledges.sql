SELECT
        ft.CALCULATEDUSERDEFINEDID AS Revenue_ID_legacy__c,
        so.LOOKUPID AS LookUp_ID_Legacy,
        ft.ID AS Implementation_External_ID__c,
        '{{Donation_Record_Type}}' AS RecordTypeId,
        CONCAT('Pledge - ', CAST(ft.CALCULATEDDATE AS DATE)) AS Name,
        1 AS npsp__Do_Not_Automatically_Create_Payments__c,
        CASE
            WHEN c.ISCONSTITUENT = 1
                AND c.ISORGANIZATION = 0
                AND c.ISGROUP = 0
            THEN CAST(ft.CONSTITUENTID AS VARCHAR(36))
            ELSE NULL
        END AS npsp__Primary_Contact__c,
        CASE
                WHEN c.ISCONSTITUENT = 1 AND c.ISORGANIZATION = 0 AND c.ISGROUP = 0
                    THEN CAST(chh.HOUSEHOLDID AS VARCHAR(36))
                WHEN c.ISORGANIZATION = 1
                        THEN CAST(c.ID AS VARCHAR(36))
                ELSE NULL
        END AS AccountId,
        CAST(ft.CALCULATEDDATE AS DATE) AS CloseDate,
        'Pledged' AS StageName,
        COALESCE(ft.TRANSACTIONAMOUNT , 0) AS Amount,
        ft.CALCULATEDDATE AS npsp__Acknowledgment_Date__c,
        'Acknowledged' AS npsp__Acknowledgment_Status__c,
        COALESCE(so.ID, ft.ID) AS vnfp__POS_Purchase__c,
        re.GIVENANONYMOUSLY AS Given_Anonymously__c
FROM
    FINANCIALTRANSACTION ft
LEFT JOIN REVENUE_EXT re
    ON re.ID = ft.ID
LEFT JOIN SALESORDER so
    ON so.REVENUEID = ft.ID
LEFT JOIN CONSTITUENT c
    ON c.ID = ft.CONSTITUENTID
LEFT JOIN CONSTITUENTHOUSEHOLD chh
    ON c.ID = chh.ID
WHERE ft.[TYPE] = 'Pledge'
ORDER BY ft.CALCULATEDDATE DESC
