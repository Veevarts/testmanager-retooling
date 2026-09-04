


















































































DECLARE @timeZone NVARCHAR(100) = 'Eastern Standard Time';

WITH VisitorsTotals AS (
SELECT
        it.RESERVATIONID,
        SUM(ia.QUANTITY) AS totalVisitors
FROM
        ITINERARY it
LEFT JOIN ITINERARYATTENDEE ia
        ON
        ia.ITINERARYID = it.ID
GROUP BY
        it.RESERVATIONID
),
ReservationTypes AS (
SELECT
        it.RESERVATIONID,
        CASE
                WHEN SUM(
                CASE
                    WHEN LOWER(gstc.DESCRIPTION) LIKE '%group%' THEN 1
                    ELSE 0
                END
            ) > 0 THEN 'Group'
                ELSE 'Rental_Event'
        END AS reservationType
FROM
        ITINERARY it
LEFT JOIN GROUPSALESGROUPTYPECODE gstc
        ON
        gstc.ID = it.GROUPSALESGROUPTYPECODEID
GROUP BY
        it.RESERVATIONID
),
ReservationNotes AS (
SELECT
        rn.RESERVATIONID,
        STRING_AGG(
                CONCAT_WS(
                        N' — ',
                        NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                LTRIM(RTRIM(CAST(rn.TITLE AS NVARCHAR(MAX)))),
                                N'&', N'&amp;'), N'<', N'&lt;'), N'>', N'&gt;'),
                                NCHAR(13) + NCHAR(10), N'<br>'), NCHAR(13), N'<br>'), NCHAR(10), N'<br>'), N''),
                        NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                LTRIM(RTRIM(CAST(rn.TEXTNOTE AS NVARCHAR(MAX)))),
                                N'&', N'&amp;'), N'<', N'&lt;'), N'>', N'&gt;'),
                                NCHAR(13) + NCHAR(10), N'<br>'), NCHAR(13), N'<br>'), NCHAR(10), N'<br>'), N'')),
                N' | ')
            WITHIN GROUP (ORDER BY rn.DATEENTERED, rn.ID) AS concatenatedNotes
FROM
        RESERVATIONNOTE rn
WHERE





        (rn.TEXTNOTE IS NOT NULL AND LTRIM(RTRIM(rn.TEXTNOTE)) <> '')
        OR (rn.TITLE IS NOT NULL AND LTRIM(RTRIM(rn.TITLE)) <> '')
GROUP BY
        rn.RESERVATIONID
),


ItineraryItemNotes AS (
SELECT
        it.RESERVATIONID,
        STRING_AGG(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                        LTRIM(RTRIM(CAST(ii.NOTES AS NVARCHAR(MAX)))),
                        N'&', N'&amp;'), N'<', N'&lt;'), N'>', N'&gt;'),
                        NCHAR(13) + NCHAR(10), N'<br>'), NCHAR(13), N'<br>'), NCHAR(10), N'<br>'), N' | ')
            WITHIN GROUP (ORDER BY ii.STARTDATETIME, ii.ID) AS concatenatedItemNotes
FROM
        ITINERARY it
INNER JOIN ITINERARYITEM ii
        ON
        ii.ITINERARYID = it.ID
WHERE
        ii.NOTES IS NOT NULL
        AND LTRIM(RTRIM(ii.NOTES)) <> ''
GROUP BY
        it.RESERVATIONID
),
DateTimesUtc AS (
SELECT
        r.ID AS RESERVATIONID,
        (r.STARTDATETIME AT TIME ZONE @timeZone) AT TIME ZONE 'UTC' AS startInUTC,
        (r.ENDDATETIME AT TIME ZONE @timeZone) AT TIME ZONE 'UTC' AS endInUTC
FROM
        RESERVATION r
),
RentalOrders AS (
SELECT
        so.ID AS SALESORDERID,
        so.AMOUNT AS SALESORDER_AMOUNT
FROM
        SALESORDER so
INNER JOIN RESERVATION r
        ON r.ID = so.ID
),
PaymentRefunds AS (
SELECT
        cp.REVENUEID AS PAYMENT_TRANSACTION_ID,
        SUM(refund.TRANSACTIONAMOUNT) AS REFUNDED_AMOUNT
FROM
        CREDITPAYMENT cp
INNER JOIN FINANCIALTRANSACTION refund
        ON refund.ID = cp.CREDITID
        AND refund.TYPE = 'Refund'
INNER JOIN FINANCIALTRANSACTION pt
        ON pt.ID = cp.REVENUEID
        AND pt.TYPE = 'Payment'
GROUP BY
        cp.REVENUEID
),
RentalPaymentRows AS (
SELECT
        ro.SALESORDERID AS RESERVATIONID,
        sop.AMOUNT AS PAID_VALUE,
        COALESCE(pr.REFUNDED_AMOUNT, 0) AS REFUNDED_AMOUNT
FROM
        SALESORDERPAYMENT sop
INNER JOIN FINANCIALTRANSACTION ft
        ON ft.ID = sop.PAYMENTID
        AND ft.TYPE = 'Payment'
INNER JOIN RentalOrders ro
        ON ro.SALESORDERID = sop.SALESORDERID
LEFT JOIN PaymentRefunds pr
        ON pr.PAYMENT_TRANSACTION_ID = sop.PAYMENTID
UNION ALL
SELECT
        ro.SALESORDERID AS RESERVATIONID,
        rsdp.AMOUNTTENDERED AS PAID_VALUE,
        COALESCE(pr.REFUNDED_AMOUNT, 0) AS REFUNDED_AMOUNT
FROM
        RESERVATIONSECURITYDEPOSITPAYMENT rsdp
INNER JOIN FINANCIALTRANSACTION ft
        ON ft.ID = rsdp.PAYMENTID
        AND ft.TYPE = 'Payment'
INNER JOIN RentalOrders ro
        ON ro.SALESORDERID = rsdp.RESERVATIONID
LEFT JOIN PaymentRefunds pr
        ON pr.PAYMENT_TRANSACTION_ID = rsdp.PAYMENTID
),
RentalPaymentRollups AS (
SELECT
        RESERVATIONID,
        SUM(COALESCE(PAID_VALUE, 0)) AS PAID_AMOUNT,
        SUM(COALESCE(REFUNDED_AMOUNT, 0)) AS TOTAL_REFUNDED_AMOUNT,
        SUM(COALESCE(PAID_VALUE, 0)) - SUM(COALESCE(REFUNDED_AMOUNT, 0)) AS NET_PAID_AMOUNT
FROM
        RentalPaymentRows
GROUP BY
        RESERVATIONID
)
SELECT
        COUNT(*) AS TotalRows,
        COUNT(DISTINCT q.Implementation_External_ID__c) AS DistinctExternalIds,
        SUM(CASE WHEN q.Auctifera__Client_Contact__c IS NOT NULL THEN 1 ELSE 0 END) AS ContactFilled,
        SUM(CASE WHEN q.Auctifera__Client_Company_Household__c IS NOT NULL THEN 1 ELSE 0 END) AS CompanyHouseholdFilled,
        SUM(CASE WHEN q.Auctifera__Client_Contact__c = '[ANONYMOUS_CONTACT]' THEN 1 ELSE 0 END) AS AnonymousContactRows,
        CHECKSUM_AGG(CHECKSUM(q.Implementation_External_ID__c, q.Auctifera__Client_Company_Household__c)) AS CompanyHouseholdChecksum,
        CHECKSUM_AGG(CHECKSUM(q.Implementation_External_ID__c, q.Auctifera__Client_Contact__c)) AS ContactChecksum
FROM (
SELECT
        r.ID AS Implementation_External_ID__c,
        r.NAME AS Name,
        CASE
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Paid'
                WHEN so.STATUS NOT IN ('Pending', 'Tentative', 'Cancelled')
                        AND COALESCE(rpr.NET_PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0)
                        AND COALESCE(so.AMOUNT, 0) > 0 THEN 'Paid'
                WHEN so.STATUS NOT IN ('Pending', 'Tentative', 'Cancelled')
                        AND COALESCE(rpr.NET_PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Reserved' THEN 'Reserved/Partially Paid'
                WHEN so.STATUS = 'Unresolved' THEN 'Reserved/Partially Paid'
                ELSE so.STATUS
        END AS Auctifera__Status__c,
        rt.reservationType AS Auctifera__Type__c,
        vt.totalVisitors AS Auctifera__Approx_number_of_people_attending__c,
        (
        COALESCE(addr.ADDRESSBLOCK, '') + 
        CASE
                WHEN addr.CITY IS NOT NULL
                        AND addr.CITY <> '' 
             THEN ', ' + addr.CITY
                        ELSE ''
                END +
        CASE
                        WHEN addr.POSTCODE IS NOT NULL
                        AND addr.POSTCODE <> '' 
             THEN ', ' + addr.POSTCODE
                        ELSE ''
                END
    ) AS Auctifera__Billing_Address__c,



        CASE
                WHEN so.CONSTITUENTID IS NULL OR c.ID IS NULL THEN '[ANONYMOUS_CONTACT]'
                WHEN c.ISORGANIZATION = 0
                AND c.ISGROUP = 0
                AND c.ISCONSTITUENT = 1
        THEN CAST(so.CONSTITUENTID AS NVARCHAR(36))
                ELSE NULL
        END AS Auctifera__Client_Contact__c,
        CASE
                WHEN so.CONSTITUENTID IS NULL OR c.ID IS NULL THEN NULL
                WHEN c.ISORGANIZATION = 1
                OR c.ISGROUP = 1
                OR c.ISCONSTITUENT = 0
        THEN so.CONSTITUENTID
                ELSE chh.HOUSEHOLDID
        END AS Auctifera__Client_Company_Household__c,












        NULLIF(CONCAT_WS(
                N'<br>',
                N'Important notes: '
                        + NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                LTRIM(RTRIM(CAST(so.COMMENTS AS NVARCHAR(MAX)))),
                                N'&', N'&amp;'), N'<', N'&lt;'), N'>', N'&gt;'),
                                NCHAR(13) + NCHAR(10), N'<br>'), NCHAR(13), N'<br>'), NCHAR(10), N'<br>'), N''),
                N'Reservation notes: ' + rn.concatenatedNotes,
                N'Arrival notes: '
                        + NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                                LTRIM(RTRIM(CAST(r.ARRIVALNOTES AS NVARCHAR(MAX)))),
                                N'&', N'&amp;'), N'<', N'&lt;'), N'>', N'&gt;'),
                                NCHAR(13) + NCHAR(10), N'<br>'), NCHAR(13), N'<br>'), NCHAR(10), N'<br>'), N''),
                N'Itinerary notes: ' + iin.concatenatedItemNotes
        ), N'') AS Auctifera__Description__c,
        dt.startInUTC AS Auctifera__Event_Start_Date_and_Time__c,
        CASE
                WHEN dt.startInUTC = dt.endInUTC
            THEN DATEADD(HOUR, 1, dt.endInUTC)
                ELSE dt.endInUTC
        END AS Auctifera__Event_End_Date_and_Time__c,
        COALESCE(rpr.PAID_AMOUNT, 0) AS Auctifera__Paid_Amount_2__c,
        COALESCE(rpr.TOTAL_REFUNDED_AMOUNT, 0) AS Auctifera__Total_Refunded_Amount__c,
        so.LOOKUPID AS Auctifera__Rental_Event_Invoice_Number__c
FROM
        RESERVATION r
LEFT JOIN SALESORDER so
        ON
        so.ID = r.ID
LEFT JOIN ADDRESS addr
        ON
        addr.ID = so.ADDRESSID
LEFT JOIN CONSTITUENT c
        ON
        c.ID = so.CONSTITUENTID
LEFT JOIN CONSTITUENTHOUSEHOLD chh
    ON
        so.CONSTITUENTID = chh.ID
LEFT JOIN VisitorsTotals vt
    ON
        vt.RESERVATIONID = r.ID
LEFT JOIN ReservationTypes rt
    ON
        rt.RESERVATIONID = r.ID
LEFT JOIN ReservationNotes rn
    ON
        rn.RESERVATIONID = r.ID
LEFT JOIN ItineraryItemNotes iin
    ON
        iin.RESERVATIONID = r.ID
LEFT JOIN DateTimesUtc dt
    ON
        dt.RESERVATIONID = r.ID
LEFT JOIN RentalPaymentRollups rpr
    ON
        rpr.RESERVATIONID = r.ID
) AS q;
