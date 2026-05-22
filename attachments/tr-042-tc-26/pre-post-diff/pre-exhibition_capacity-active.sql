DECLARE @useDateFrom BIT = IIF(@hasDateFilterFrom = 1, 1, 0);
DECLARE @useDateTo BIT = IIF(@hasDateFilterTo = 1, 1, 0);
DECLARE @filterDateFrom DATETIME2 = CAST(@dateFilterFrom AS DATETIME2);
DECLARE @filterDateTo DATETIME2 = CAST(@dateFilterTo AS DATETIME2);

SELECT
    e.ID AS Implementation_External_ID__c,
    e.LOOKUPID AS Lookup_ID__c,
    SWITCHOFFSET(e.STARTDATETIMEWITHOFFSET, '+00:00') AS Auctifera__Date_Time__c,
    e.EVENTLOCATIONID AS Auctifera__Display_Storage_Location__c,
    e.NAME AS Auctifera__Session_Name__c,
    e.CAPACITY AS Auctifera__Target_Capacity__c,
    e.PROGRAMID AS "Auctifera__Exposition__r:Auctifera__Inventory_Service__c-Implementation_External_ID__c"
FROM
    EVENT e
WHERE 1 = 1
    AND e.PROGRAMID IS NOT NULL
    AND (@useDateFrom = 0 OR CAST(e.STARTDATETIMEWITHOFFSET AS DATETIME2) >= @filterDateFrom)
    AND (@useDateTo = 0 OR CAST(e.STARTDATETIMEWITHOFFSET AS DATETIME2) <= @filterDateTo)
    AND (@hasProgramIdFilter = 0 OR e.PROGRAMID = @programIdFilter)
