DECLARE @timeZone NVARCHAR(100) = 'Eastern Standard Time';
SELECT x.SALESORDERID, x.SALESORDER_AMOUNT INTO #rr_RentalOrders FROM (
    SELECT
        so.ID AS SALESORDERID,
        so.AMOUNT AS SALESORDER_AMOUNT
    FROM SALESORDER so
    INNER JOIN RESERVATION r
        ON r.ID = so.ID
) AS x;
SELECT x.PAYMENT_TRANSACTION_ID, x.REFUNDED_AMOUNT INTO #rr_PaymentRefunds FROM (
    SELECT
        cp.REVENUEID AS PAYMENT_TRANSACTION_ID,
        SUM(refund.TRANSACTIONAMOUNT) AS REFUNDED_AMOUNT
    FROM CREDITPAYMENT cp
    INNER JOIN FINANCIALTRANSACTION refund
        ON refund.ID = cp.CREDITID
        AND refund.TYPE = 'Refund'
    INNER JOIN FINANCIALTRANSACTION pt
        ON pt.ID = cp.REVENUEID
        AND pt.TYPE = 'Payment'
    GROUP BY cp.REVENUEID
) AS x;
SELECT x.RESERVATIONID, x.PAID_VALUE, x.REFUNDED_AMOUNT INTO #rr_RentalPaymentRows FROM (
    SELECT
        ro.SALESORDERID AS RESERVATIONID,
        sop.AMOUNT AS PAID_VALUE,
        COALESCE(pr.REFUNDED_AMOUNT, 0) AS REFUNDED_AMOUNT
    FROM SALESORDERPAYMENT sop
    INNER JOIN FINANCIALTRANSACTION ft
        ON ft.ID = sop.PAYMENTID
        AND ft.TYPE = 'Payment'
    INNER JOIN #rr_RentalOrders ro
        ON ro.SALESORDERID = sop.SALESORDERID
    LEFT JOIN #rr_PaymentRefunds pr
        ON pr.PAYMENT_TRANSACTION_ID = sop.PAYMENTID
    UNION ALL
    SELECT
        ro.SALESORDERID AS RESERVATIONID,
        rsdp.AMOUNTTENDERED AS PAID_VALUE,
        COALESCE(pr.REFUNDED_AMOUNT, 0) AS REFUNDED_AMOUNT
    FROM RESERVATIONSECURITYDEPOSITPAYMENT rsdp
    INNER JOIN FINANCIALTRANSACTION ft
        ON ft.ID = rsdp.PAYMENTID
        AND ft.TYPE = 'Payment'
    INNER JOIN #rr_RentalOrders ro
        ON ro.SALESORDERID = rsdp.RESERVATIONID
    LEFT JOIN #rr_PaymentRefunds pr
        ON pr.PAYMENT_TRANSACTION_ID = rsdp.PAYMENTID
) AS x;
SELECT x.RESERVATIONID, x.PAID_AMOUNT, x.TOTAL_REFUNDED_AMOUNT, x.NET_PAID_AMOUNT INTO #rr_RentalPaymentRollups FROM (
    SELECT
        RESERVATIONID,
        SUM(COALESCE(PAID_VALUE, 0)) AS PAID_AMOUNT,
        SUM(COALESCE(REFUNDED_AMOUNT, 0)) AS TOTAL_REFUNDED_AMOUNT,
        SUM(COALESCE(PAID_VALUE, 0)) - SUM(COALESCE(REFUNDED_AMOUNT, 0)) AS NET_PAID_AMOUNT
    FROM #rr_RentalPaymentRows
    GROUP BY RESERVATIONID
) AS x;
SELECT x.SALESORDERID, x.TotalDiscountAmount INTO #rr_OrderDiscounts FROM (
    SELECT
        soi.SALESORDERID,
        SUM(soi.TOTAL) AS TotalDiscountAmount
    FROM SALESORDERITEM soi
    INNER JOIN SALESORDERITEMORDERDISCOUNT soiod
        ON soi.ID = soiod.ID
    GROUP BY soi.SALESORDERID
) AS x;
SELECT x.SALESORDERITEMID, x.TOTALTAX INTO #rr_RentalResourceItemTaxes FROM (
    SELECT
        SALESORDERITEMID,
        SUM(TOTALTAX) AS TOTALTAX
    FROM SALESORDERITEMTAX
    GROUP BY SALESORDERITEMID
) AS x;
SELECT x.Auctifera__Resource_Rental_Charge__c, x.Implementation_External_ID__c, x.Auctifera__Rental_Event__c, x.Auctifera__Resource_Fee_Model__c, x.Auctifera__Event_Start_Time__c, x.Auctifera__Event_End_Time__c, x.Auctifera__Ticketing__c, x.Auctifera__Resource__c, x.Auctifera__Location__c, x.Auctifera__Number_of_items_attendees__c, x.Auctifera__Per_Person_Item_Charge__c, x.Auctifera__Resource_Flat_Fee_Charge__c, x.Auctifera__Tax_Rate__c, x.Auctifera__Rental_Status__c, x.Auctifera__Discount__c, x.Auctifera__Is_Ticket__c, x.Auctifera__Subtotal_Amount3__c, x.Auctifera__Ticketing_Tax_Amount__c, x.Auctifera__Tax_Amount3__c, x.Auctifera__Disable_Trigger__c INTO #rr_BaseRentalResources FROM (
    SELECT
        soi.TOTAL AS Auctifera__Resource_Rental_Charge__c,
        CAST(soi.ID AS VARCHAR(36)) AS Implementation_External_ID__c,
        r.ID AS Auctifera__Rental_Event__c,
        CASE
            WHEN soi.PRICINGSTRUCTURECODE = '0' THEN 'Per Item'
            WHEN soi.PRICINGSTRUCTURECODE IN ('1', '2') THEN 'Flat Fee'
            ELSE NULL
        END AS Auctifera__Resource_Fee_Model__c,
        (r.STARTDATETIME AT TIME ZONE @timeZone) AT TIME ZONE 'UTC' AS Auctifera__Event_Start_Time__c,
        (r.ENDDATETIME AT TIME ZONE @timeZone) AT TIME ZONE 'UTC' AS Auctifera__Event_End_Time__c,
        CASE
            WHEN soi.TYPECODE = '0' THEN so.ID
            ELSE NULL
        END AS Auctifera__Ticketing__c,
        CASE
            WHEN soi.TYPECODE IN ('8', '9', '10', '11')
                THEN COALESCE(
                    iir.RESOURCEID,
                    ir.RESOURCEID,
                    isr.VOLUNTEERTYPEID,
                    iisr.VOLUNTEERTYPEID
                )
            ELSE NULL
        END AS Auctifera__Resource__c,
        CASE
            WHEN soi.TYPECODE = '7' THEN el.ID
            ELSE NULL
        END AS Auctifera__Location__c,
        soi.QUANTITY AS Auctifera__Number_of_items_attendees__c,
        CASE
            WHEN soi.PRICINGSTRUCTURECODE = '0' THEN soi.PRICE
            ELSE NULL
        END AS Auctifera__Per_Person_Item_Charge__c,
        CASE
            WHEN soi.PRICINGSTRUCTURECODE IN ('1', '2') THEN soi.PRICE
            ELSE NULL
        END AS Auctifera__Resource_Flat_Fee_Charge__c,
        soitax.TOTALTAX AS Auctifera__Tax_Rate__c,
        
        
        
        CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END AS Auctifera__Rental_Status__c,
        CAST(
            soi.TOTAL * (
                CAST(od.TotalDiscountAmount AS DECIMAL(18, 6)) /
                NULLIF(CAST(SUM(soi.TOTAL) OVER (PARTITION BY soi.SALESORDERID) AS DECIMAL(18, 6)), 0)
            )
        AS DECIMAL(18, 2)) AS Auctifera__Discount__c,
        CASE
            WHEN soi.TYPE = 'Ticket' THEN 1
            ELSE 0
        END AS Auctifera__Is_Ticket__c,
        CAST(
            soi.TOTAL - COALESCE(
                CAST(
                    soi.TOTAL * (
                        CAST(od.TotalDiscountAmount AS DECIMAL(18, 6)) /
                        NULLIF(CAST(SUM(soi.TOTAL) OVER (PARTITION BY soi.SALESORDERID) AS DECIMAL(18, 6)), 0)
                    )
                AS DECIMAL(18, 2)),
                0
            )
        AS DECIMAL(18, 2)) AS Auctifera__Subtotal_Amount3__c,
        CAST(
            CASE
                WHEN soi.TYPE = 'Ticket' THEN
                    (
                        soi.TOTAL - COALESCE(
                            CAST(
                                soi.TOTAL * (
                                    CAST(od.TotalDiscountAmount AS DECIMAL(18, 6)) /
                                    NULLIF(CAST(SUM(soi.TOTAL) OVER (PARTITION BY soi.SALESORDERID) AS DECIMAL(18, 6)), 0)
                                )
                            AS DECIMAL(18, 2)),
                            0
                        )
                    ) * (COALESCE(soitax.TOTALTAX, 0) / 100.0)
                ELSE 0
            END
        AS DECIMAL(18, 2)) AS Auctifera__Ticketing_Tax_Amount__c,
        CAST(
            (
                soi.TOTAL - COALESCE(
                    CAST(
                        soi.TOTAL * (
                            CAST(od.TotalDiscountAmount AS DECIMAL(18, 6)) /
                            NULLIF(CAST(SUM(soi.TOTAL) OVER (PARTITION BY soi.SALESORDERID) AS DECIMAL(18, 6)), 0)
                        )
                    AS DECIMAL(18, 2)),
                    0
                )
            ) * (COALESCE(soitax.TOTALTAX, 0) / 100.0)
        AS DECIMAL(18, 2)) AS Auctifera__Tax_Amount3__c,
        1 AS Auctifera__Disable_Trigger__c
    FROM SALESORDERITEM soi
    INNER JOIN RESERVATION r
        ON r.ID = soi.SALESORDERID
    INNER JOIN SALESORDER so
        ON r.ID = so.ID
    LEFT JOIN SALESORDERITEMTICKET soit
        ON soit.ID = soi.ID
    LEFT JOIN SALESORDERITEMITINERARYRESOURCE soir
        ON soir.SALESORDERITEMID = soi.ID
    LEFT JOIN ITINERARYRESOURCE ir
        ON ir.ID = soir.ITINERARYRESOURCEID
    LEFT JOIN SALESORDERITEMITINERARYITEMRESOURCE soiiir
        ON soiiir.SALESORDERITEMID = soi.ID
    LEFT JOIN ITINERARYITEMRESOURCE iir
        ON iir.ID = soiiir.ITINERARYITEMRESOURCEID
    LEFT JOIN SALESORDERITEMITINERARYSTAFFRESOURCE soistaff
        ON soistaff.SALESORDERITEMID = soi.ID
    LEFT JOIN SALESORDERITEMITINERARYITEMSTAFFRESOURCE soiistaff
        ON soiistaff.SALESORDERITEMID = soi.ID
    LEFT JOIN ITINERARYSTAFFRESOURCE isr
        ON isr.ID = soistaff.ITINERARYSTAFFRESOURCEID
    LEFT JOIN ITINERARYITEMSTAFFRESOURCE iisr
        ON iisr.ID = soiistaff.ITINERARYITEMSTAFFRESOURCEID
    LEFT JOIN VOLUNTEERTYPE vt
        ON vt.ID = isr.VOLUNTEERTYPEID
    LEFT JOIN SALESORDERITEMFACILITY soif
        ON soif.ID = soi.ID
    LEFT JOIN EVENTLOCATION el
        ON el.ID = soif.EVENTLOCATIONID
    LEFT JOIN #rr_RentalResourceItemTaxes soitax
        ON soitax.SALESORDERITEMID = soi.ID
    LEFT JOIN SALESORDERITEMORDERDISCOUNT soidiscount
        ON soidiscount.ID = soi.ID
    LEFT JOIN #rr_OrderDiscounts od
        ON od.SALESORDERID = soi.SALESORDERID
    
    
    LEFT JOIN #rr_RentalPaymentRollups rpr
        ON rpr.RESERVATIONID = r.ID
    WHERE soi.TYPECODE NOT IN ('4', '5')
) AS x;
SELECT x.Auctifera__Resource_Rental_Charge__c, x.Implementation_External_ID__c, x.Auctifera__Rental_Event__c, x.Auctifera__Resource_Fee_Model__c, x.Auctifera__Event_Start_Time__c, x.Auctifera__Event_End_Time__c, x.Auctifera__Ticketing__c, x.Auctifera__Resource__c, x.Auctifera__Location__c, x.Auctifera__Number_of_items_attendees__c, x.Auctifera__Per_Person_Item_Charge__c, x.Auctifera__Resource_Flat_Fee_Charge__c, x.Auctifera__Tax_Rate__c, x.Auctifera__Rental_Status__c, x.Auctifera__Discount__c, x.Auctifera__Is_Ticket__c, x.Auctifera__Subtotal_Amount3__c, x.Auctifera__Ticketing_Tax_Amount__c, x.Auctifera__Tax_Amount3__c, x.Auctifera__Disable_Trigger__c INTO #rr_AggregatedTicketRentalResources FROM (
    SELECT
        SUM(Auctifera__Resource_Rental_Charge__c) AS Auctifera__Resource_Rental_Charge__c,
        CAST(Auctifera__Ticketing__c AS VARCHAR(36)) AS Implementation_External_ID__c,
        Auctifera__Rental_Event__c,
        'Flat Fee' AS Auctifera__Resource_Fee_Model__c,
        Auctifera__Event_Start_Time__c,
        Auctifera__Event_End_Time__c,
        Auctifera__Ticketing__c,
        NULL AS Auctifera__Resource__c,
        NULL AS Auctifera__Location__c,
        SUM(Auctifera__Number_of_items_attendees__c) AS Auctifera__Number_of_items_attendees__c,
        NULL AS Auctifera__Per_Person_Item_Charge__c,
        SUM(Auctifera__Subtotal_Amount3__c) AS Auctifera__Resource_Flat_Fee_Charge__c,
        CASE
            WHEN COUNT(DISTINCT COALESCE(Auctifera__Tax_Rate__c, -1)) = 1
                THEN MAX(Auctifera__Tax_Rate__c)
            ELSE NULL
        END AS Auctifera__Tax_Rate__c,
        Auctifera__Rental_Status__c,
        SUM(Auctifera__Discount__c) AS Auctifera__Discount__c,
        1 AS Auctifera__Is_Ticket__c,
        SUM(Auctifera__Subtotal_Amount3__c) AS Auctifera__Subtotal_Amount3__c,
        SUM(Auctifera__Ticketing_Tax_Amount__c) AS Auctifera__Ticketing_Tax_Amount__c,
        SUM(Auctifera__Tax_Amount3__c) AS Auctifera__Tax_Amount3__c,
        1 AS Auctifera__Disable_Trigger__c
    FROM #rr_BaseRentalResources
    WHERE Auctifera__Is_Ticket__c = 1
        AND Auctifera__Ticketing__c IS NOT NULL
    GROUP BY
        Auctifera__Rental_Event__c,
        Auctifera__Event_Start_Time__c,
        Auctifera__Event_End_Time__c,
        Auctifera__Ticketing__c,
        Auctifera__Rental_Status__c
) AS x;
SELECT q.Implementation_External_ID__c AS RRID, q.Auctifera__Rental_Event__c AS RID, q.Auctifera__Rental_Status__c AS RST, q.Auctifera__Subtotal_Amount3__c AS SUB3, q.Auctifera__Tax_Amount3__c AS TAX3 INTO #qa_rr FROM (SELECT Implementation_External_ID__c AS Implementation_External_ID__c,
  Auctifera__Rental_Event__c AS Auctifera__Rental_Event__c,
  Auctifera__Rental_Status__c AS Auctifera__Rental_Status__c,
  Auctifera__Subtotal_Amount3__c AS Auctifera__Subtotal_Amount3__c,
  Auctifera__Tax_Amount3__c AS Auctifera__Tax_Amount3__c
FROM #rr_BaseRentalResources
WHERE Auctifera__Is_Ticket__c = 0 UNION ALL SELECT Implementation_External_ID__c AS Implementation_External_ID__c,
  Auctifera__Rental_Event__c AS Auctifera__Rental_Event__c,
  Auctifera__Rental_Status__c AS Auctifera__Rental_Status__c,
  Auctifera__Subtotal_Amount3__c AS Auctifera__Subtotal_Amount3__c,
  Auctifera__Tax_Amount3__c AS Auctifera__Tax_Amount3__c
FROM #rr_AggregatedTicketRentalResources) AS q;
SELECT x.RESERVATIONID, x.totalVisitors INTO #ev_VisitorsTotals FROM (
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
) AS x;
SELECT x.RESERVATIONID, x.reservationType INTO #ev_ReservationTypes FROM (
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
) AS x;
SELECT x.RESERVATIONID, x.concatenatedNotes INTO #ev_ReservationNotes FROM (
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
) AS x;
SELECT x.RESERVATIONID, x.concatenatedItemNotes INTO #ev_ItineraryItemNotes FROM (
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
) AS x;
SELECT x.RESERVATIONID, x.CONTACTCONSTITUENTID INTO #ev_ReservationClientContacts FROM (
SELECT
        so.ID AS RESERVATIONID,
        relc.ID AS CONTACTCONSTITUENTID
FROM
        SALESORDER so
INNER JOIN RESERVATION r
        ON
        r.ID = so.ID
INNER JOIN CONSTITUENT c
        ON
        c.ID = so.CONSTITUENTID
        AND c.ISORGANIZATION = 1
INNER JOIN RELATIONSHIP rel
        ON
        rel.ID = so.CONTACTRELATIONSHIPID
INNER JOIN CONSTITUENT relc
        ON
        relc.ID = rel.RECIPROCALCONSTITUENTID
        AND relc.ISORGANIZATION = 0
        AND relc.ISGROUP = 0
        AND relc.ISCONSTITUENT = 1
UNION ALL
SELECT
        so.ID AS RESERVATIONID,
        memc.ID AS CONTACTCONSTITUENTID
FROM
        SALESORDER so
INNER JOIN RESERVATION r
        ON
        r.ID = so.ID
INNER JOIN CONSTITUENT c
        ON
        c.ID = so.CONSTITUENTID
        AND c.ISORGANIZATION = 0
        AND c.ISGROUP = 1
CROSS APPLY (
        SELECT TOP 1
                gm.MEMBERID
        FROM
                GROUPMEMBER gm
        WHERE
                gm.GROUPID = c.ID
                AND gm.ISPRIMARY = 1
        ORDER BY
                gm.ID
) pm
INNER JOIN CONSTITUENT memc
        ON
        memc.ID = pm.MEMBERID
        AND memc.ISORGANIZATION = 0
        AND memc.ISGROUP = 0
        AND memc.ISCONSTITUENT = 1
) AS x;
SELECT x.RESERVATIONID, x.startInUTC, x.endInUTC INTO #ev_DateTimesUtc FROM (
SELECT
        r.ID AS RESERVATIONID,
        (r.STARTDATETIME AT TIME ZONE @timeZone) AT TIME ZONE 'UTC' AS startInUTC,
        (r.ENDDATETIME AT TIME ZONE @timeZone) AT TIME ZONE 'UTC' AS endInUTC
FROM
        RESERVATION r
) AS x;
SELECT x.SALESORDERID, x.SALESORDER_AMOUNT INTO #ev_RentalOrders FROM (
SELECT
        so.ID AS SALESORDERID,
        so.AMOUNT AS SALESORDER_AMOUNT
FROM
        SALESORDER so
INNER JOIN RESERVATION r
        ON r.ID = so.ID
) AS x;
SELECT x.PAYMENT_TRANSACTION_ID, x.REFUNDED_AMOUNT INTO #ev_PaymentRefunds FROM (
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
) AS x;
SELECT x.RESERVATIONID, x.PAID_VALUE, x.REFUNDED_AMOUNT INTO #ev_RentalPaymentRows FROM (
SELECT
        ro.SALESORDERID AS RESERVATIONID,
        sop.AMOUNT AS PAID_VALUE,
        COALESCE(pr.REFUNDED_AMOUNT, 0) AS REFUNDED_AMOUNT
FROM
        SALESORDERPAYMENT sop
INNER JOIN FINANCIALTRANSACTION ft
        ON ft.ID = sop.PAYMENTID
        AND ft.TYPE = 'Payment'
INNER JOIN #ev_RentalOrders ro
        ON ro.SALESORDERID = sop.SALESORDERID
LEFT JOIN #ev_PaymentRefunds pr
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
INNER JOIN #ev_RentalOrders ro
        ON ro.SALESORDERID = rsdp.RESERVATIONID
LEFT JOIN #ev_PaymentRefunds pr
        ON pr.PAYMENT_TRANSACTION_ID = rsdp.PAYMENTID
) AS x;
SELECT x.RESERVATIONID, x.PAID_AMOUNT, x.TOTAL_REFUNDED_AMOUNT, x.NET_PAID_AMOUNT INTO #ev_RentalPaymentRollups FROM (
SELECT
        RESERVATIONID,
        SUM(COALESCE(PAID_VALUE, 0)) AS PAID_AMOUNT,
        SUM(COALESCE(REFUNDED_AMOUNT, 0)) AS TOTAL_REFUNDED_AMOUNT,
        SUM(COALESCE(PAID_VALUE, 0)) - SUM(COALESCE(REFUNDED_AMOUNT, 0)) AS NET_PAID_AMOUNT
FROM
        #ev_RentalPaymentRows
GROUP BY
        RESERVATIONID
) AS x;
SELECT x.SALESORDERID, x.TotalDiscountAmount INTO #ev_RentalResourceOrderDiscounts FROM (
SELECT
        soi.SALESORDERID,
        SUM(soi.TOTAL) AS TotalDiscountAmount
FROM
        SALESORDERITEM soi
INNER JOIN SALESORDERITEMORDERDISCOUNT soiod
        ON
        soi.ID = soiod.ID
GROUP BY
        soi.SALESORDERID
) AS x;
SELECT x.SALESORDERITEMID, x.TOTALTAX INTO #ev_RentalResourceItemTaxes FROM (
SELECT
        SALESORDERITEMID,
        SUM(TOTALTAX) AS TOTALTAX
FROM
        SALESORDERITEMTAX
GROUP BY
        SALESORDERITEMID
) AS x;
SELECT x.RESERVATIONID, x.SALESORDER_STATUS, x.IS_TICKET, x.HAS_TICKETING, x.TOTAL, x.TOTALTAX, x.DISCOUNT_AMOUNT INTO #ev_RentalResourceItemDiscounts FROM (
SELECT
        r.ID AS RESERVATIONID,
        so.STATUS AS SALESORDER_STATUS,
        CASE
                WHEN soi.TYPE = 'Ticket' THEN 1
                ELSE 0
        END AS IS_TICKET,
        
        
        CASE
                WHEN soi.TYPECODE = '0' THEN 1
                ELSE 0
        END AS HAS_TICKETING,
        soi.TOTAL,
        soitax.TOTALTAX,
        CAST(
                soi.TOTAL * (
                        CAST(od.TotalDiscountAmount AS DECIMAL(18, 6)) /
                        NULLIF(CAST(SUM(soi.TOTAL) OVER (PARTITION BY soi.SALESORDERID) AS DECIMAL(18, 6)), 0)
                )
        AS DECIMAL(18, 2)) AS DISCOUNT_AMOUNT
FROM
        SALESORDERITEM soi
INNER JOIN RESERVATION r
        ON
        r.ID = soi.SALESORDERID
INNER JOIN SALESORDER so
        ON
        r.ID = so.ID
LEFT JOIN #ev_RentalResourceItemTaxes soitax
        ON
        soitax.SALESORDERITEMID = soi.ID
LEFT JOIN #ev_RentalResourceOrderDiscounts od
        ON
        od.SALESORDERID = soi.SALESORDERID
WHERE
        soi.TYPECODE NOT IN ('4', '5')
) AS x;
SELECT x.RESERVATIONID, x.SALESORDER_STATUS, x.IS_TICKET, x.HAS_TICKETING, x.SUBTOTAL_AMOUNT3, x.TAX_AMOUNT3 INTO #ev_RentalResourceItemAmounts FROM (
SELECT
        RESERVATIONID,
        SALESORDER_STATUS,
        IS_TICKET,
        HAS_TICKETING,
        CAST(TOTAL - COALESCE(DISCOUNT_AMOUNT, 0) AS DECIMAL(18, 2)) AS SUBTOTAL_AMOUNT3,
        CAST((TOTAL - COALESCE(DISCOUNT_AMOUNT, 0)) * (COALESCE(TOTALTAX, 0) / 100.0) AS DECIMAL(18, 2)) AS TAX_AMOUNT3
FROM
        #ev_RentalResourceItemDiscounts
) AS x;
SELECT x.RESERVATIONID, x.RESOURCE_SUBTOTALS, x.RESOURCE_TAXES INTO #ev_RentalResourceTotals FROM (
SELECT
        RESERVATIONID,
        SUM(SUBTOTAL_AMOUNT3) AS RESOURCE_SUBTOTALS,
        SUM(TAX_AMOUNT3) AS RESOURCE_TAXES
FROM
        #ev_RentalResourceItemAmounts
WHERE
        COALESCE(SALESORDER_STATUS, N'') <> N'Cancelled'
        AND (IS_TICKET = 0 OR HAS_TICKETING = 1)
GROUP BY
        RESERVATIONID
) AS x;
SELECT q.Implementation_External_ID__c AS RID, q.Auctifera__Rental_Resource_Subtotals2__c AS SUB2, q.Auctifera__Rental_Resource_Taxes3__c AS TAX3 INTO #qa_ev FROM (SELECT r.ID AS Implementation_External_ID__c,
  CAST(COALESCE(rrt.RESOURCE_SUBTOTALS, 0) AS DECIMAL(18, 2)) AS Auctifera__Rental_Resource_Subtotals2__c,
  CAST(COALESCE(rrt.RESOURCE_TAXES, 0) AS DECIMAL(18, 2)) AS Auctifera__Rental_Resource_Taxes3__c
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
LEFT JOIN #ev_ReservationClientContacts rcc
    ON
        rcc.RESERVATIONID = r.ID
LEFT JOIN #ev_VisitorsTotals vt
    ON
        vt.RESERVATIONID = r.ID
LEFT JOIN #ev_ReservationTypes rt
    ON
        rt.RESERVATIONID = r.ID
LEFT JOIN #ev_ReservationNotes rn
    ON
        rn.RESERVATIONID = r.ID
LEFT JOIN #ev_ItineraryItemNotes iin
    ON
        iin.RESERVATIONID = r.ID
LEFT JOIN #ev_DateTimesUtc dt
    ON
        dt.RESERVATIONID = r.ID
LEFT JOIN #ev_RentalPaymentRollups rpr
    ON
        rpr.RESERVATIONID = r.ID
LEFT JOIN #ev_RentalResourceTotals rrt
    ON
        rrt.RESERVATIONID = r.ID) AS q;
SELECT RID, COUNT(*) AS N_RR,
  SUM(CASE WHEN ISNULL(RST,'') <> 'Canceled' THEN COALESCE(SUB3, 0) ELSE 0 END) AS PKG_SUB,
  SUM(CASE WHEN ISNULL(RST,'') <> 'Canceled' THEN COALESCE(TAX3, 0) ELSE 0 END) AS PKG_TAX,
  SUM(CASE WHEN SUB3 IS NULL OR TAX3 IS NULL THEN 1 ELSE 0 END) AS N_NULL3,
  SUM(CASE WHEN RST = 'Canceled' THEN 1 ELSE 0 END) AS N_CANCELED_RR
INTO #qa_pkg FROM #qa_rr GROUP BY RID;
SELECT r.ID AS RID,
  CASE WHEN so.STATUS = 'Cancelled' THEN 1 ELSE 0 END AS F_CANCELLED,
  CASE WHEN EXISTS (SELECT 1 FROM SALESORDERITEM soi INNER JOIN SALESORDERITEMORDERDISCOUNT d ON d.ID = soi.ID WHERE soi.SALESORDERID = r.ID) THEN 1 ELSE 0 END AS F_DISCOUNT,
  CASE WHEN EXISTS (SELECT 1 FROM SALESORDERITEM soi WHERE soi.SALESORDERID = r.ID AND soi.TYPE = 'Ticket' AND soi.TYPECODE <> '0' AND soi.TYPECODE NOT IN ('4','5')) THEN 1 ELSE 0 END AS F_DROPPED_TICKET,
  CASE WHEN EXISTS (SELECT 1 FROM SALESORDERITEM soi WHERE soi.SALESORDERID = r.ID AND soi.TYPECODE NOT IN ('4','5')) THEN 1 ELSE 0 END AS F_HAS_ITEMS
INTO #qa_flags FROM RESERVATION r LEFT JOIN SALESORDER so ON so.ID = r.ID;
SELECT e.RID, e.SUB2, e.TAX3, ISNULL(p.N_RR,0) AS N_RR, COALESCE(p.PKG_SUB,0) AS PKG_SUB, COALESCE(p.PKG_TAX,0) AS PKG_TAX,
  ISNULL(p.N_NULL3,0) AS N_NULL3, ISNULL(p.N_CANCELED_RR,0) AS N_CANCELED_RR, f.F_CANCELLED, f.F_DISCOUNT, f.F_DROPPED_TICKET, f.F_HAS_ITEMS,
  CASE WHEN e.SUB2 IS NULL OR e.TAX3 IS NULL OR e.SUB2 <> COALESCE(p.PKG_SUB,0) OR e.TAX3 <> COALESCE(p.PKG_TAX,0) THEN 1 ELSE 0 END AS MISMATCH
INTO #qa_cmp FROM #qa_ev e LEFT JOIN #qa_pkg p ON p.RID = e.RID LEFT JOIN #qa_flags f ON f.RID = e.RID;
SELECT
  (SELECT COUNT(*) FROM #qa_ev) AS ev_rows, (SELECT COUNT(DISTINCT RID) FROM #qa_ev) AS ev_distinct,
  (SELECT COUNT(*) FROM #qa_rr) AS rr_rows, (SELECT COUNT(DISTINCT RRID) FROM #qa_rr) AS rr_distinct_ids,
  (SELECT COUNT(*) FROM #qa_rr WHERE RID IS NOT NULL AND RID NOT IN (SELECT RID FROM #qa_ev)) AS rr_orphans,
  SUM(CASE WHEN SUB2 IS NULL THEN 1 ELSE 0 END) AS ev_sub2_null, SUM(CASE WHEN TAX3 IS NULL THEN 1 ELSE 0 END) AS ev_tax3_null,
  SUM(MISMATCH) AS ev_mismatch_exact,
  SUM(CASE WHEN ABS(COALESCE(SUB2,0) - PKG_SUB) > 0.005 OR ABS(COALESCE(TAX3,0) - PKG_TAX) > 0.005 THEN 1 ELSE 0 END) AS ev_mismatch_tol,
  SUM(CASE WHEN SUB2 > 0 THEN 1 ELSE 0 END) AS ev_nonzero_sub, SUM(CASE WHEN TAX3 > 0 THEN 1 ELSE 0 END) AS ev_nonzero_tax,
  CAST(SUM(COALESCE(SUB2,0)) AS DECIMAL(18,2)) AS sum_ev_sub2, CAST(SUM(PKG_SUB) AS DECIMAL(18,2)) AS sum_pkg_sub,
  CAST(SUM(COALESCE(TAX3,0)) AS DECIMAL(18,2)) AS sum_ev_tax3, CAST(SUM(PKG_TAX) AS DECIMAL(18,2)) AS sum_pkg_tax,
  SUM(N_NULL3) AS rr_rows_with_null_amount3,
  SUM(F_CANCELLED) AS res_cancelled, SUM(CASE WHEN F_CANCELLED = 1 AND N_RR > 0 THEN 1 ELSE 0 END) AS res_cancelled_with_rr,
  SUM(CASE WHEN F_CANCELLED = 1 AND (COALESCE(SUB2,0) <> 0 OR COALESCE(TAX3,0) <> 0) THEN 1 ELSE 0 END) AS cancelled_nonzero_totals,
  SUM(CASE WHEN F_CANCELLED = 1 AND N_RR > 0 AND N_CANCELED_RR <> N_RR THEN 1 ELSE 0 END) AS cancelled_with_non_canceled_rr,
  SUM(CASE WHEN N_RR = 0 THEN 1 ELSE 0 END) AS res_without_rr,
  SUM(CASE WHEN N_RR = 0 AND (SUB2 IS NULL OR TAX3 IS NULL OR SUB2 <> 0 OR TAX3 <> 0) THEN 1 ELSE 0 END) AS without_rr_not_zero,
  SUM(F_DISCOUNT) AS res_discount, SUM(CASE WHEN F_DISCOUNT = 1 THEN MISMATCH ELSE 0 END) AS discount_mismatch,
  SUM(F_DROPPED_TICKET) AS res_dropped_ticket, SUM(CASE WHEN F_DROPPED_TICKET = 1 THEN MISMATCH ELSE 0 END) AS dropped_ticket_mismatch,
  SUM(CASE WHEN F_HAS_ITEMS = 0 THEN 1 ELSE 0 END) AS res_without_items,
  SUM(CASE WHEN F_HAS_ITEMS = 0 AND (SUB2 IS NULL OR SUB2 <> 0 OR TAX3 IS NULL OR TAX3 <> 0) THEN 1 ELSE 0 END) AS without_items_not_zero
FROM #qa_cmp;
