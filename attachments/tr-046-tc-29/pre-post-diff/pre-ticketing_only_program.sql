DECLARE @useDateFrom BIT = IIF(@hasDateFilterFrom = 1, 1, 0);
DECLARE @useDateTo BIT = IIF(@hasDateFilterTo = 1, 1, 0);
DECLARE @useStatus BIT = IIF(@hasStatusFilter = 1, 1, 0);
DECLARE @filterDateFrom DATE = CAST(@dateFilterFrom AS DATE);
DECLARE @filterDateTo DATE = CAST(@dateFilterTo AS DATE);

SELECT
        'Program' AS RecordTypeColumn,
        so.ID AS Auctifera__POS_Purchase__c,
        COALESCE(
        (
            SELECT TOP 1
                CAST(e.STARTDATE AS DATE)
            FROM
                SALESORDERITEM soi
                LEFT JOIN SALESORDERITEMTICKET soit ON soi.ID = soit.ID
                LEFT JOIN EVENT e ON e.ID = soit.EVENTID
            WHERE
                soi.SALESORDERID = so.ID
                AND e.STARTDATE IS NOT NULL
            ORDER BY
                e.STARTDATE ASC
        ),
        CAST(so.TRANSACTIONDATE AS DATE)
    ) AS Auctifera__Visitor_Management__c,
        so.ID AS vnfp__Implementation_External_ID__c,
        ft.CALCULATEDUSERDEFINEDID AS Revenue_ID_legacy__c,
        so.LOOKUPID AS LookUp_ID_Legacy,
        so.SALESMETHODTYPE AS Auctifera__Source__c,
        CASE
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                ELSE so.STATUS
        END AS Auctifera__Status__c,
        CASE
                WHEN ct.ISGROUP = 1
                OR ct.ISORGANIZATION = 1 THEN ct.ID
                ELSE COALESCE(ch.HOUSEHOLDID, NULL)
        END AS Auctifera__Account__c,
        CASE
                WHEN ct.ISGROUP = 0
                AND ct.ISORGANIZATION = 0
                AND ct.ISCONSTITUENT = 1 THEN ct.ID
                ELSE NULL
        END AS Auctifera__Contact_Requesting_the_Visit__c,
        so.COMMENTS AS Auctifera__General_Comments__c,
        r.ID AS Auctifera__Rental_Event__c,
        COALESCE(
        (
            SELECT TOP 1
                CAST(e.STARTDATE AS DATE)
            FROM
                SALESORDERITEM soi
                LEFT JOIN SALESORDERITEMTICKET soit ON soi.ID = soit.ID
                LEFT JOIN EVENT e ON e.ID = soit.EVENTID
            WHERE
                soi.SALESORDERID = so.ID
                AND e.STARTDATE IS NOT NULL
            ORDER BY
                e.STARTDATE ASC
        ),
        CAST(so.TRANSACTIONDATE AS DATE)
    ) AS Ticket_Date_Do_Not_Map -- (para el visitor management)
FROM
        SALESORDER so
LEFT JOIN FINANCIALTRANSACTION ft ON
        so.REVENUEID = ft.ID
LEFT JOIN CONSTITUENT ct ON
        so.CONSTITUENTID = ct.ID
LEFT JOIN CONSTITUENTHOUSEHOLD ch ON
        ch.ID = ct.ID
LEFT JOIN RESERVATION r ON r.ID = so.ID
WHERE 1 = 1
        AND (@useDateFrom = 0 OR CAST(so.TRANSACTIONDATE AS DATE) >= @filterDateFrom)
        AND (@useDateTo = 0 OR CAST(so.TRANSACTIONDATE AS DATE) <= @filterDateTo)
        AND (@useStatus = 0 OR so.STATUS = @statusFilter)
        AND EXISTS (
        SELECT
                        1
        FROM
                        SALESORDERITEM soi
        INNER JOIN SALESORDERITEMTICKET soit ON
                        soi.ID = soit.ID
        LEFT JOIN EVENT e ON
                        e.ID = soit.EVENTID
        WHERE
                        soi.SALESORDERID = so.ID)
