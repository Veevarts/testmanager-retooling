DECLARE @hasDateFilterFrom BIT = 0;
DECLARE @dateFilterFrom DATETIME = NULL;
DECLARE @hasDateFilterTo BIT = 0;
DECLARE @dateFilterTo DATETIME = NULL;
DECLARE @useDateFrom BIT = IIF(@hasDateFilterFrom = 1, 1, 0);
DECLARE @useDateTo BIT = IIF(@hasDateFilterTo = 1, 1, 0);
DECLARE @filterDateFrom DATE = CAST(@dateFilterFrom AS DATE);
DECLARE @filterDateTo DATE = CAST(@dateFilterTo AS DATE);

WITH event_registration_attendance_key AS (
	SELECT DISTINCT
		ep.EVENTID,
		r.CONSTITUENTID
	FROM SALESORDERITEMEVENTREGISTRATION soier
		INNER JOIN SALESORDERITEMEVENTREGISTRANTREGISTRATION soierrn ON soierrn.SALESORDERITEMEVENTREGISTRATIONID = soier.ID
		INNER JOIN EVENTPRICE ep ON ep.ID = soierrn.EVENTPRICEID
		INNER JOIN REGISTRANT r ON r.ID = soier.REGISTRANTID
	WHERE r.CONSTITUENTID IS NOT NULL
),
ticket_registrant_contact AS (
	SELECT
		sitr.SALESORDERITEMTICKETID,
		MIN(r.CONSTITUENTID) AS ContactID
	FROM SALESORDERITEMTICKETREGISTRANT sitr
		INNER JOIN REGISTRANT r ON r.ID = sitr.REGISTRANTID
	WHERE r.CONSTITUENTID IS NOT NULL
	GROUP BY sitr.SALESORDERITEMTICKETID
),
ticket_attendance_key AS (
	SELECT DISTINCT
		COALESCE(t.EVENTID, soit.EVENTID) AS EVENTID,
		COALESCE(trc.ContactID, so.CONSTITUENTID) AS CONSTITUENTID
	FROM TICKET t
		LEFT JOIN SALESORDERITEMTICKET soit ON soit.ID = t.SALESORDERITEMTICKETID
		LEFT JOIN SALESORDERITEM soi ON soi.ID = soit.ID
		LEFT JOIN SALESORDER so ON so.ID = soi.SALESORDERID
		LEFT JOIN ticket_registrant_contact trc ON trc.SALESORDERITEMTICKETID = soit.ID
	WHERE t.SALESORDERITEMTICKETID IS NOT NULL
		AND COALESCE(t.EVENTID, soit.EVENTID) IS NOT NULL
		AND COALESCE(trc.ContactID, so.CONSTITUENTID) IS NOT NULL
),
current_attendance_key AS (
	SELECT EVENTID, CONSTITUENTID
	FROM event_registration_attendance_key
	UNION
	SELECT EVENTID, CONSTITUENTID
	FROM ticket_attendance_key
),
eligible_direct_registrant AS (
	SELECT
		r.ID,
		r.EVENTID,
		r.CONSTITUENTID,
		r.ATTENDED,
		r.ISWALKIN,
		r.LOOKUPID,
		r.NOTES,
		r.DATEADDED,
		e.NAME AS EventName,
		e.STARTDATE,
		e.STARTDATETIMEWITHOFFSET
	FROM REGISTRANT r
		INNER JOIN EVENT e ON e.ID = r.EVENTID
	WHERE r.CONSTITUENTID IS NOT NULL
		AND r.ISCANCELLED = 0
		AND r.WILLNOTATTEND = 0
		AND NOT EXISTS (
			SELECT 1
			FROM REGISTRANTREGISTRATION rr
			WHERE rr.REGISTRANTID = r.ID
		)
		AND NOT EXISTS (
			SELECT 1
			FROM SALESORDERITEMEVENTREGISTRATION soier
			WHERE soier.REGISTRANTID = r.ID
		)
		AND NOT EXISTS (
			SELECT 1
			FROM SALESORDERITEMTICKETREGISTRANT sitr
			WHERE sitr.REGISTRANTID = r.ID
		)
		AND NOT EXISTS (
			SELECT 1
			FROM current_attendance_key cak
			WHERE cak.EVENTID = r.EVENTID
				AND cak.CONSTITUENTID = r.CONSTITUENTID
		)
		AND NOT EXISTS (
			SELECT 1
			FROM SALESORDER so
				INNER JOIN SALESORDERITEM soi ON soi.SALESORDERID = so.ID
				INNER JOIN SALESORDERITEMTICKET soit ON soit.ID = soi.ID
			WHERE so.CONSTITUENTID = r.CONSTITUENTID
				AND soit.EVENTID = r.EVENTID
		)
		AND NOT EXISTS (
			SELECT 1
			FROM SALESORDER so
				INNER JOIN SALESORDERITEM soi ON soi.SALESORDERID = so.ID
				INNER JOIN SALESORDERITEMEVENTREGISTRATION soier ON soier.ID = soi.ID
				INNER JOIN SALESORDERITEMEVENTREGISTRANTREGISTRATION soierrn ON soierrn.SALESORDERITEMEVENTREGISTRATIONID = soier.ID
				INNER JOIN EVENTPRICE ep ON ep.ID = soierrn.EVENTPRICEID
			WHERE so.CONSTITUENTID = r.CONSTITUENTID
				AND ep.EVENTID = r.EVENTID
		)
)
SELECT DISTINCT CONVERT(VARCHAR(10), c.Auctifera__Visitor_Management__c, 23) AS Auctifera__Visitor_Management__c
FROM (
SELECT
	'Event' AS RecordTypeColumn,
	CONCAT('direct-registrant-pos-', CAST(r.ID AS NVARCHAR(36))) AS Auctifera__POS_Purchase__c,
	CAST(r.STARTDATE AS DATE) AS Auctifera__Visitor_Management__c,
	CONCAT('direct-registrant-ticketing-', CAST(r.ID AS NVARCHAR(36))) AS vnfp__Implementation_External_ID__c,
	CAST(NULL AS NVARCHAR(255)) AS Revenue_ID_legacy__c,
	r.LOOKUPID AS LookUp_ID_Legacy,
	CASE WHEN r.ISWALKIN = 1 THEN 'Walk-in registration' ELSE 'Preregistration' END AS Auctifera__Source__c,
	'Sold' AS Auctifera__Status__c,
	CASE
		WHEN ct.ISGROUP = 1
			OR ct.ISORGANIZATION = 1 THEN CAST(ct.ID AS NVARCHAR(36))
		ELSE CAST(ch.HOUSEHOLDID AS NVARCHAR(36))
	END AS Auctifera__Account__c,
	CASE
		WHEN ct.ISGROUP = 0
			AND ct.ISORGANIZATION = 0
			AND ct.ISCONSTITUENT = 1 THEN CAST(ct.ID AS NVARCHAR(36))
		ELSE NULL
	END AS Auctifera__Contact_Requesting_the_Visit__c,
	NULLIF(r.NOTES, '') AS Auctifera__General_Comments__c,
	CAST(NULL AS NVARCHAR(36)) AS Auctifera__Rental_Event__c,
	CAST(r.STARTDATE AS DATE) AS Ticket_Date_Do_Not_Map,
	-- IM-774: emitted on every row so the column set stays aligned with ticketing_only_event.sql --
	-- TicketingEventExtractor runs both files through the same mapper and CSV descriptor.
	-- This path cannot itself hit the duplicate-Rental-Resource defect (Rental_Event__c is always
	-- NULL above, so ReservationTriggerHandler never calls createRentalItemsForTicket), but the flag
	-- must still be uniform: the bypass is batch-scoped, and a Bulk chunk mixing flagged and
	-- unflagged rows would behave according to whichever rows happened to land together.
	-- Emitted as the string 'true', not 1: a Bulk API CSV silently treats 1 as FALSE for a Checkbox.
	'true' AS Auctifera__Technical_Bypass_Triggers__c,
	-- IM-774: no RESERVATION row on this path, and Auctifera__Status__c is the literal 'Sold' above,
	-- so the Confirmed branch is unreachable here. NULL keeps the column set aligned.
	CAST(NULL AS NVARCHAR(40)) AS Auctifera__Confirmed_Date_Time__c
FROM eligible_direct_registrant r
	INNER JOIN CONSTITUENT ct ON ct.ID = r.CONSTITUENTID
	OUTER APPLY (
		SELECT TOP 1 ch.HOUSEHOLDID
		FROM CONSTITUENTHOUSEHOLD ch
		WHERE ch.ID = ct.ID
		ORDER BY ch.ISPRIMARYMEMBER DESC, ch.HOUSEHOLDID
	) ch
WHERE (@useDateFrom = 0 OR r.STARTDATE >= @filterDateFrom)
	AND (@useDateTo = 0 OR r.STARTDATE <= @filterDateTo)
) AS c;
