DECLARE @timeZone NVARCHAR(100) = 'Eastern Standard Time'; -- Windows time zone name; matches rental_resource.sql and rental_events_groups.sql
DECLARE @useDateFrom BIT = IIF(0 = 1, 1, 0);
DECLARE @useDateTo BIT = IIF(0 = 1, 1, 0);
DECLARE @filterDateFrom DATE = CAST(NULL AS DATE);
DECLARE @filterDateTo DATE = CAST(NULL AS DATE);

SELECT DISTINCT CONVERT(VARCHAR(10), c.Auctifera__Visitor_Management__c, 23) AS Auctifera__Visitor_Management__c
FROM (
SELECT
        'Program' AS RecordTypeColumn,
        so.ID AS Auctifera__POS_Purchase__c,
        COALESCE(
                CAST(r.ARRIVALDATE AS DATE),
                ticket_dates.EarliestTicketDate,
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
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
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
                CAST(r.ARRIVALDATE AS DATE),
                ticket_dates.EarliestTicketDate,
                CAST(so.TRANSACTIONDATE AS DATE)
        ) AS Ticket_Date_Do_Not_Map, -- (para el visitor management)
        -- IM-774: skip ReservationTriggerHandler on the migration load. Without this Salesforce
        -- auto-creates a Rental Resource for every ticket that has a Rental Event, with no
        -- Implementation External ID, so the migrated Rental Resource cannot upsert onto it and a
        -- duplicate is left behind. Must be emitted on EVERY row: the framework's bypass is
        -- batch-scoped (TriggerHandler.anyRecordBypassFieldKey), so a conditional flag would make
        -- behaviour depend on Bulk API chunking.
        -- Requires Auctifera__Technical_Bypass_Triggers__c on Group Reservation (PP-1438,
        -- Auctifera >= 8.317.0.2) and Bypass_POS_Transaction_Lock on the loading user.
        -- Emitted as the string 'true', not 1: a Bulk API CSV silently treats 1 as FALSE for a
        -- Checkbox. The TS mapper would coerce either form, but AGENTS.md requires this query's
        -- output to be loadable as-is by someone running the SQL by hand.
        'true' AS Auctifera__Technical_Bypass_Triggers__c,
        -- IM-774: ReservationTriggerHandler.beforeInsert used to stamp this with Datetime.now() --
        -- the migration run date, not a historical one. Bypassing the trigger removes that, so the
        -- value is sourced here instead.
        --
        -- Source is RESERVATION.STARTDATETIME, which IS the exact arrival datetime: measured across
        -- all 27 Confirmed ticket-backed reservations in Tucson, its date component equals
        -- ARRIVALDATE and its time component equals ARRIVALTIME on 27/27 rows. ARRIVALDATE alone is
        -- a DATE column, so emitting it as an instant lands on midnight and renders as the PREVIOUS
        -- day in every org west of UTC.
        --
        -- Converted with the same idiom the sibling queries already apply to this very column
        -- (rental_resource.sql:22, rental_events_groups.sql:66): interpret the naive Altru value as
        -- museum-local, then normalise to UTC. Style 127 serialises it as an explicit-UTC ISO-8601
        -- string, so the app path and a hand-run export resolve to the same instant regardless of
        -- the loading machine's timezone.
        -- NOTE: this branch tests the RAW so.STATUS, while Auctifera__Status__c above is the
        -- mapped value. They agree only because no branch of that CASE produces 'Confirmed' --
        -- it survives via the ELSE fallthrough. Adding a THEN 'Confirmed' branch there would
        -- export Confirmed rows with a blank date. Pinned by a regression assertion in
        -- ticketing-trigger-bypass-query.spec.ts.
        CASE
                WHEN so.STATUS = 'Confirmed' THEN CONVERT(NVARCHAR(40), (r.STARTDATETIME AT TIME ZONE @timeZone) AT TIME ZONE 'UTC', 127)
                ELSE CAST(NULL AS NVARCHAR(40))
        END AS Auctifera__Confirmed_Date_Time__c
FROM
        SALESORDER so
LEFT JOIN FINANCIALTRANSACTION ft ON
        so.REVENUEID = ft.ID
LEFT JOIN CONSTITUENT ct ON
        so.CONSTITUENTID = ct.ID
LEFT JOIN CONSTITUENTHOUSEHOLD ch ON
        ch.ID = ct.ID
LEFT JOIN RESERVATION r ON r.ID = so.ID
OUTER APPLY (
        SELECT TOP 1
                CAST(e.STARTDATE AS DATE) AS EarliestTicketDate
        FROM
                SALESORDERITEM soi
                LEFT JOIN SALESORDERITEMTICKET soit ON soi.ID = soit.ID
                LEFT JOIN EVENT e ON e.ID = soit.EVENTID
        WHERE
                soi.SALESORDERID = so.ID
                AND e.STARTDATE IS NOT NULL
        ORDER BY
                e.STARTDATE ASC
) ticket_dates
WHERE 1 = 1
        AND (@useDateFrom = 0 OR COALESCE(CAST(r.ARRIVALDATE AS DATE), ticket_dates.EarliestTicketDate, CAST(so.TRANSACTIONDATE AS DATE)) >= @filterDateFrom)
        AND (@useDateTo = 0 OR COALESCE(CAST(r.ARRIVALDATE AS DATE), ticket_dates.EarliestTicketDate, CAST(so.TRANSACTIONDATE AS DATE)) <= @filterDateTo)
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
) AS c;
