DECLARE @timeZone NVARCHAR(100) = 'Eastern Standard Time';
SELECT x.SALESORDERID, x.SALESORDER_AMOUNT INTO #pre_RentalOrders FROM (
SELECT
        so.ID AS SALESORDERID,
        so.AMOUNT AS SALESORDER_AMOUNT
FROM
        SALESORDER so
INNER JOIN RESERVATION r
        ON r.ID = so.ID
) AS x;
SELECT x.PAYMENT_TRANSACTION_ID, x.REFUNDED_AMOUNT INTO #pre_PaymentRefunds FROM (
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
SELECT x.RESERVATIONID, x.PAID_VALUE, x.REFUNDED_AMOUNT INTO #pre_RentalPaymentRows FROM (
SELECT
        ro.SALESORDERID AS RESERVATIONID,
        sop.AMOUNT AS PAID_VALUE,
        COALESCE(pr.REFUNDED_AMOUNT, 0) AS REFUNDED_AMOUNT
FROM
        SALESORDERPAYMENT sop
INNER JOIN FINANCIALTRANSACTION ft
        ON ft.ID = sop.PAYMENTID
        AND ft.TYPE = 'Payment'
INNER JOIN #pre_RentalOrders ro
        ON ro.SALESORDERID = sop.SALESORDERID
LEFT JOIN #pre_PaymentRefunds pr
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
INNER JOIN #pre_RentalOrders ro
        ON ro.SALESORDERID = rsdp.RESERVATIONID
LEFT JOIN #pre_PaymentRefunds pr
        ON pr.PAYMENT_TRANSACTION_ID = rsdp.PAYMENTID
) AS x;
SELECT x.RESERVATIONID, x.PAID_AMOUNT, x.TOTAL_REFUNDED_AMOUNT, x.NET_PAID_AMOUNT INTO #pre_RentalPaymentRollups FROM (
SELECT
        RESERVATIONID,
        SUM(COALESCE(PAID_VALUE, 0)) AS PAID_AMOUNT,
        SUM(COALESCE(REFUNDED_AMOUNT, 0)) AS TOTAL_REFUNDED_AMOUNT,
        SUM(COALESCE(PAID_VALUE, 0)) - SUM(COALESCE(REFUNDED_AMOUNT, 0)) AS NET_PAID_AMOUNT
FROM
        #pre_RentalPaymentRows
GROUP BY
        RESERVATIONID
) AS x;
SELECT x.SALESORDERID, x.SALESORDER_AMOUNT INTO #post_RentalOrders FROM (
SELECT
        so.ID AS SALESORDERID,
        so.AMOUNT AS SALESORDER_AMOUNT
FROM
        SALESORDER so
INNER JOIN RESERVATION r
        ON r.ID = so.ID
) AS x;
SELECT x.PAYMENT_TRANSACTION_ID, x.REFUNDED_AMOUNT INTO #post_PaymentRefunds FROM (
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
SELECT x.RESERVATIONID, x.PAID_VALUE, x.REFUNDED_AMOUNT INTO #post_RentalPaymentRows FROM (
SELECT
        ro.SALESORDERID AS RESERVATIONID,
        sop.AMOUNT AS PAID_VALUE,
        COALESCE(pr.REFUNDED_AMOUNT, 0) AS REFUNDED_AMOUNT
FROM
        SALESORDERPAYMENT sop
INNER JOIN FINANCIALTRANSACTION ft
        ON ft.ID = sop.PAYMENTID
        AND ft.TYPE = 'Payment'
INNER JOIN #post_RentalOrders ro
        ON ro.SALESORDERID = sop.SALESORDERID
LEFT JOIN #post_PaymentRefunds pr
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
INNER JOIN #post_RentalOrders ro
        ON ro.SALESORDERID = rsdp.RESERVATIONID
LEFT JOIN #post_PaymentRefunds pr
        ON pr.PAYMENT_TRANSACTION_ID = rsdp.PAYMENTID
) AS x;
SELECT x.RESERVATIONID, x.PAID_AMOUNT, x.TOTAL_REFUNDED_AMOUNT, x.NET_PAID_AMOUNT INTO #post_RentalPaymentRollups FROM (
SELECT
        RESERVATIONID,
        SUM(COALESCE(PAID_VALUE, 0)) AS PAID_AMOUNT,
        SUM(COALESCE(REFUNDED_AMOUNT, 0)) AS TOTAL_REFUNDED_AMOUNT,
        SUM(COALESCE(PAID_VALUE, 0)) - SUM(COALESCE(REFUNDED_AMOUNT, 0)) AS NET_PAID_AMOUNT
FROM
        #post_RentalPaymentRows
GROUP BY
        RESERVATIONID
) AS x;
WITH OrderDiscounts AS (
    SELECT
        soi.SALESORDERID,
        SUM(soi.TOTAL) AS TotalDiscountAmount
    FROM SALESORDERITEM soi
    INNER JOIN SALESORDERITEMORDERDISCOUNT soiod
        ON soi.ID = soiod.ID
    GROUP BY soi.SALESORDERID
),
BaseRentalResources AS (
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
            WHEN so.STATUS = 'Pending' THEN 'Inquiry'
            WHEN so.STATUS = 'Complete' THEN 'Paid'
            WHEN so.STATUS = 'Finalized' THEN 'Paid'
            WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
            WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
            WHEN so.STATUS = 'Confirmed' THEN 'Paid'
            WHEN so.STATUS = 'Reserved' THEN 'Reserved/Partially Paid'
            WHEN so.STATUS = 'Unresolved' THEN 'Reserved/Partially Paid'
            ELSE so.STATUS
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
    LEFT JOIN SALESORDERITEMTAX soitax
        ON soitax.SALESORDERITEMID = soi.ID
    LEFT JOIN SALESORDERITEMORDERDISCOUNT soidiscount
        ON soidiscount.ID = soi.ID
    LEFT JOIN OrderDiscounts od
        ON od.SALESORDERID = soi.SALESORDERID
    WHERE soi.TYPECODE NOT IN ('4', '5')
),
AggregatedTicketRentalResources AS (
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
    FROM BaseRentalResources
    WHERE Auctifera__Is_Ticket__c = 1
        AND Auctifera__Ticketing__c IS NOT NULL
    GROUP BY
        Auctifera__Rental_Event__c,
        Auctifera__Event_Start_Time__c,
        Auctifera__Event_End_Time__c,
        Auctifera__Ticketing__c,
        Auctifera__Rental_Status__c
),
ResourceOut AS (SELECT Auctifera__Rental_Event__c AS Auctifera__Rental_Event__c
FROM BaseRentalResources
WHERE Auctifera__Is_Ticket__c = 0 UNION ALL SELECT Auctifera__Rental_Event__c AS Auctifera__Rental_Event__c
FROM AggregatedTicketRentalResources)
SELECT Auctifera__Rental_Event__c AS RID, COUNT(*) AS N_RR INTO #qa_rrn FROM ResourceOut GROUP BY Auctifera__Rental_Event__c;
SELECT r.ID AS RID, so.STATUSCODE AS SC, so.STATUS AS ST, COALESCE(so.AMOUNT,0) AS AMT,
  COALESCE(rpr_post.PAID_AMOUNT,0) AS PG, COALESCE(rpr_post.NET_PAID_AMOUNT,0) AS PN, COALESCE(rpr_post.TOTAL_REFUNDED_AMOUNT,0) AS RF,
  COALESCE(rpr_pre.NET_PAID_AMOUNT,0) AS PN_PRECHAIN,
  CASE WHEN so.LOOKUPID = '8-15359860' THEN 1 WHEN so.LOOKUPID = '8-15013828' THEN 2 ELSE 0 END AS LK,
  CASE WHEN r.ID = '128A24C3-4A69-403C-9102-C9E7FE883A56' THEN 1 WHEN r.ID = '02245AEA-853E-4C9D-AF78-D86F940D95D9' THEN 2 ELSE 0 END AS EX,
  (CASE
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Paid'
                WHEN so.STATUS NOT IN ('Pending', 'Tentative', 'Cancelled')
                        AND COALESCE(rpr_pre.NET_PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0)
                        AND COALESCE(so.AMOUNT, 0) > 0 THEN 'Paid'
                WHEN so.STATUS NOT IN ('Pending', 'Tentative', 'Cancelled')
                        AND COALESCE(rpr_pre.NET_PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Reserved' THEN 'Reserved/Partially Paid'
                WHEN so.STATUS = 'Unresolved' THEN 'Reserved/Partially Paid'
                ELSE so.STATUS
        END) AS EV_PRE, (CASE
            WHEN so.STATUS = 'Pending' THEN 'Inquiry'
            WHEN so.STATUS = 'Complete' THEN 'Paid'
            WHEN so.STATUS = 'Finalized' THEN 'Paid'
            WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
            WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
            WHEN so.STATUS = 'Confirmed' THEN 'Paid'
            WHEN so.STATUS = 'Reserved' THEN 'Reserved/Partially Paid'
            WHEN so.STATUS = 'Unresolved' THEN 'Reserved/Partially Paid'
            ELSE so.STATUS
        END) AS RR_PRE, (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr_post.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr_post.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr_post.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) AS EV_POST, (CASE
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN COALESCE(rpr_post.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr_post.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Paid'
                WHEN COALESCE(rpr_post.PAID_AMOUNT, 0) > 0 THEN 'Reserved/Partially Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Paid'
                WHEN so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Signed Contract'
                WHEN so.STATUS = 'Tentative' THEN 'Proposal/Negotiation'
                WHEN so.STATUS = 'Pending' THEN 'Inquiry'
                WHEN so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved/Partially Paid'
                ELSE 'Inquiry'
        END) AS RR_POST, (CASE
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) AS TK_PRE, (CASE
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r.ID IS NOT NULL
                        AND COALESCE(rpr_post.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr_post.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r.ID IS NOT NULL AND COALESCE(rpr_post.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) AS TK_POST
INTO #qa_res
FROM RESERVATION r
LEFT JOIN SALESORDER so ON so.ID = r.ID
LEFT JOIN #pre_RentalPaymentRollups rpr_pre ON rpr_pre.RESERVATIONID = r.ID
LEFT JOIN #post_RentalPaymentRollups rpr_post ON rpr_post.RESERVATIONID = r.ID;
SELECT q.RID, q.SC, q.ST, q.AMT, q.PG, q.PN, q.RF, q.PN_PRECHAIN, q.LK, q.EX, q.EV_PRE, q.RR_PRE, q.EV_POST, q.RR_POST, q.TK_PRE, q.TK_POST, ISNULL(n.N_RR,0) AS N_RR,
  CASE WHEN q.EV_PRE IS NULL THEN 0 WHEN q.EV_PRE = 'Canceled' THEN 1 WHEN q.EV_PRE = 'Paid' THEN 2 WHEN q.EV_PRE = 'Reserved/Partially Paid' THEN 3 WHEN q.EV_PRE = 'Signed Contract' THEN 4 WHEN q.EV_PRE = 'Proposal/Negotiation' THEN 5 WHEN q.EV_PRE = 'Inquiry' THEN 6 WHEN q.EV_PRE = 'Pending' THEN 11 WHEN q.EV_PRE = 'Complete' THEN 12 WHEN q.EV_PRE = 'Tentative' THEN 13 WHEN q.EV_PRE = 'Confirmed' THEN 14 WHEN q.EV_PRE = 'Finalized' THEN 15 WHEN q.EV_PRE = 'Cancelled' THEN 16 WHEN q.EV_PRE = 'Reserved' THEN 17 WHEN q.EV_PRE = 'Unresolved' THEN 18 ELSE 99 END AS C_EV_PRE, CASE WHEN q.RR_PRE IS NULL THEN 0 WHEN q.RR_PRE = 'Canceled' THEN 1 WHEN q.RR_PRE = 'Paid' THEN 2 WHEN q.RR_PRE = 'Reserved/Partially Paid' THEN 3 WHEN q.RR_PRE = 'Signed Contract' THEN 4 WHEN q.RR_PRE = 'Proposal/Negotiation' THEN 5 WHEN q.RR_PRE = 'Inquiry' THEN 6 WHEN q.RR_PRE = 'Pending' THEN 11 WHEN q.RR_PRE = 'Complete' THEN 12 WHEN q.RR_PRE = 'Tentative' THEN 13 WHEN q.RR_PRE = 'Confirmed' THEN 14 WHEN q.RR_PRE = 'Finalized' THEN 15 WHEN q.RR_PRE = 'Cancelled' THEN 16 WHEN q.RR_PRE = 'Reserved' THEN 17 WHEN q.RR_PRE = 'Unresolved' THEN 18 ELSE 99 END AS C_RR_PRE, CASE WHEN q.EV_POST IS NULL THEN 0 WHEN q.EV_POST = 'Canceled' THEN 1 WHEN q.EV_POST = 'Paid' THEN 2 WHEN q.EV_POST = 'Reserved/Partially Paid' THEN 3 WHEN q.EV_POST = 'Signed Contract' THEN 4 WHEN q.EV_POST = 'Proposal/Negotiation' THEN 5 WHEN q.EV_POST = 'Inquiry' THEN 6 WHEN q.EV_POST = 'Pending' THEN 11 WHEN q.EV_POST = 'Complete' THEN 12 WHEN q.EV_POST = 'Tentative' THEN 13 WHEN q.EV_POST = 'Confirmed' THEN 14 WHEN q.EV_POST = 'Finalized' THEN 15 WHEN q.EV_POST = 'Cancelled' THEN 16 WHEN q.EV_POST = 'Reserved' THEN 17 WHEN q.EV_POST = 'Unresolved' THEN 18 ELSE 99 END AS C_EV_POST, CASE WHEN q.RR_POST IS NULL THEN 0 WHEN q.RR_POST = 'Canceled' THEN 1 WHEN q.RR_POST = 'Paid' THEN 2 WHEN q.RR_POST = 'Reserved/Partially Paid' THEN 3 WHEN q.RR_POST = 'Signed Contract' THEN 4 WHEN q.RR_POST = 'Proposal/Negotiation' THEN 5 WHEN q.RR_POST = 'Inquiry' THEN 6 WHEN q.RR_POST = 'Pending' THEN 11 WHEN q.RR_POST = 'Complete' THEN 12 WHEN q.RR_POST = 'Tentative' THEN 13 WHEN q.RR_POST = 'Confirmed' THEN 14 WHEN q.RR_POST = 'Finalized' THEN 15 WHEN q.RR_POST = 'Cancelled' THEN 16 WHEN q.RR_POST = 'Reserved' THEN 17 WHEN q.RR_POST = 'Unresolved' THEN 18 ELSE 99 END AS C_RR_POST, CASE WHEN q.TK_PRE IS NULL THEN 0 WHEN q.TK_PRE = 'Canceled' THEN 21 WHEN q.TK_PRE = 'Sold' THEN 22 WHEN q.TK_PRE = 'Reserved' THEN 23 WHEN q.TK_PRE = 'Pending' THEN 24 WHEN q.TK_PRE = 'Confirmed' THEN 25 WHEN q.TK_PRE = 'Finalized' THEN 26 WHEN q.TK_PRE = 'Complete' THEN 27 WHEN q.TK_PRE = 'Tentative' THEN 28 WHEN q.TK_PRE = 'Unresolved' THEN 29 WHEN q.TK_PRE = 'Cancelled' THEN 30 WHEN q.TK_PRE = 'Refunded' THEN 31 ELSE 99 END AS C_TK_PRE, CASE WHEN q.TK_POST IS NULL THEN 0 WHEN q.TK_POST = 'Canceled' THEN 21 WHEN q.TK_POST = 'Sold' THEN 22 WHEN q.TK_POST = 'Reserved' THEN 23 WHEN q.TK_POST = 'Pending' THEN 24 WHEN q.TK_POST = 'Confirmed' THEN 25 WHEN q.TK_POST = 'Finalized' THEN 26 WHEN q.TK_POST = 'Complete' THEN 27 WHEN q.TK_POST = 'Tentative' THEN 28 WHEN q.TK_POST = 'Unresolved' THEN 29 WHEN q.TK_POST = 'Cancelled' THEN 30 WHEN q.TK_POST = 'Refunded' THEN 31 ELSE 99 END AS C_TK_POST,
  CASE WHEN CASE q.EV_POST WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END IS NULL THEN 0 WHEN CASE q.EV_POST WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END = 'Canceled' THEN 21 WHEN CASE q.EV_POST WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END = 'Sold' THEN 22 WHEN CASE q.EV_POST WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END = 'Reserved' THEN 23 WHEN CASE q.EV_POST WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END = 'Pending' THEN 24 WHEN CASE q.EV_POST WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END = 'Confirmed' THEN 25 WHEN CASE q.EV_POST WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END = 'Finalized' THEN 26 WHEN CASE q.EV_POST WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END = 'Complete' THEN 27 WHEN CASE q.EV_POST WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END = 'Tentative' THEN 28 WHEN CASE q.EV_POST WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END = 'Unresolved' THEN 29 WHEN CASE q.EV_POST WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END = 'Cancelled' THEN 30 WHEN CASE q.EV_POST WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END = 'Refunded' THEN 31 ELSE 99 END AS C_TK_EXPECTED_POST,
  CASE WHEN q.PG > 0 AND q.PG >= q.AMT THEN 2 WHEN q.PG > 0 THEN 1 WHEN q.AMT <= 0 THEN 3 ELSE 0 END AS BAND,
  CASE WHEN q.PN > 0 AND q.PN >= q.AMT THEN 1 ELSE 0 END AS NET_FULL
INTO #qa_codes FROM #qa_res q LEFT JOIN #qa_rrn n ON n.RID = q.RID;
SELECT
  COUNT(*) AS n_res,
  SUM(CASE WHEN N_RR > 0 THEN 1 ELSE 0 END) AS n_res_with_rr,
  SUM(CASE WHEN N_RR > 0 AND C_EV_PRE <> C_RR_PRE THEN 1 ELSE 0 END) AS pre_div_query,
  SUM(CASE WHEN N_RR > 0 AND C_EV_POST <> C_RR_POST THEN 1 ELSE 0 END) AS post_div_query,
  SUM(CASE WHEN N_RR > 0 AND (CASE WHEN C_EV_PRE <> 1 AND PG > 0 AND PG >= AMT THEN 2 ELSE C_EV_PRE END) = 2 AND C_RR_PRE NOT IN (1,2) THEN 1 ELSE 0 END) AS pre_trg_paid_vs_rr_npc,
  SUM(CASE WHEN N_RR > 0 AND (CASE WHEN C_EV_POST <> 1 AND PG > 0 AND PG >= AMT THEN 2 ELSE C_EV_POST END) = 2 AND C_RR_POST NOT IN (1,2) THEN 1 ELSE 0 END) AS post_trg_paid_vs_rr_npc,
  SUM(CASE WHEN N_RR > 0 AND (CASE WHEN C_EV_PRE <> 1 AND PG > 0 AND PG >= AMT THEN 2 ELSE C_EV_PRE END) <> C_RR_PRE THEN 1 ELSE 0 END) AS pre_div_after_trigger_any,
  SUM(CASE WHEN N_RR > 0 AND (CASE WHEN C_EV_POST <> 1 AND PG > 0 AND PG >= AMT THEN 2 ELSE C_EV_POST END) <> C_RR_POST THEN 1 ELSE 0 END) AS post_div_after_trigger_any,
  SUM(CASE WHEN C_EV_PRE = 2 AND PG < AMT THEN 1 ELSE 0 END) AS pre_ev_paid_owed,
  SUM(CASE WHEN C_EV_POST = 2 AND PG < AMT THEN 1 ELSE 0 END) AS post_ev_paid_owed,
  SUM(CASE WHEN N_RR > 0 AND C_RR_PRE = 2 AND PG < AMT THEN 1 ELSE 0 END) AS pre_rr_paid_owed,
  SUM(CASE WHEN N_RR > 0 AND C_RR_POST = 2 AND PG < AMT THEN 1 ELSE 0 END) AS post_rr_paid_owed,
  SUM(CASE WHEN N_RR > 0 AND C_EV_PRE = 2 AND C_RR_PRE = 2 AND PG < AMT THEN 1 ELSE 0 END) AS pre_both_paid_owed,
  SUM(CASE WHEN N_RR > 0 AND C_EV_POST = 2 AND C_RR_POST = 2 AND PG < AMT THEN 1 ELSE 0 END) AS post_both_paid_owed,
  SUM(CASE WHEN C_EV_PRE >= 11 THEN 1 ELSE 0 END) AS pre_ev_raw, SUM(CASE WHEN C_EV_POST >= 11 THEN 1 ELSE 0 END) AS post_ev_raw,
  SUM(CASE WHEN C_RR_PRE >= 11 THEN 1 ELSE 0 END) AS pre_rr_raw, SUM(CASE WHEN C_RR_POST >= 11 THEN 1 ELSE 0 END) AS post_rr_raw,
  SUM(CASE WHEN C_TK_PRE IN (25,26,27,28,29,30,99) THEN 1 ELSE 0 END) AS pre_tk_raw_or_confirmed,
  SUM(CASE WHEN C_TK_POST IN (25,26,27,28,29,30,99) THEN 1 ELSE 0 END) AS post_tk_raw_or_confirmed,
  SUM(CASE WHEN C_TK_PRE = 25 THEN 1 ELSE 0 END) AS pre_tk_confirmed, SUM(CASE WHEN C_TK_PRE = 26 THEN 1 ELSE 0 END) AS pre_tk_finalized,
  SUM(CASE WHEN C_TK_POST = 25 THEN 1 ELSE 0 END) AS post_tk_confirmed, SUM(CASE WHEN C_TK_POST = 26 THEN 1 ELSE 0 END) AS post_tk_finalized,
  SUM(CASE WHEN C_TK_PRE = 24 AND PG > 0 AND PG >= AMT THEN 1 ELSE 0 END) AS pre_tk_pending_fully_paid,
  SUM(CASE WHEN C_TK_POST = 24 AND PG > 0 AND PG >= AMT THEN 1 ELSE 0 END) AS post_tk_pending_fully_paid,
  SUM(CASE WHEN C_TK_POST <> C_TK_EXPECTED_POST THEN 1 ELSE 0 END) AS post_tk_vs_mapping_mismatch,
  SUM(CASE WHEN C_TK_PRE <> (CASE WHEN CASE EV_PRE WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END IS NULL THEN 0 WHEN CASE EV_PRE WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END = 'Canceled' THEN 21 WHEN CASE EV_PRE WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END = 'Sold' THEN 22 WHEN CASE EV_PRE WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END = 'Reserved' THEN 23 WHEN CASE EV_PRE WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END = 'Pending' THEN 24 WHEN CASE EV_PRE WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END = 'Confirmed' THEN 25 WHEN CASE EV_PRE WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END = 'Finalized' THEN 26 WHEN CASE EV_PRE WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END = 'Complete' THEN 27 WHEN CASE EV_PRE WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END = 'Tentative' THEN 28 WHEN CASE EV_PRE WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END = 'Unresolved' THEN 29 WHEN CASE EV_PRE WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END = 'Cancelled' THEN 30 WHEN CASE EV_PRE WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END = 'Refunded' THEN 31 ELSE 99 END) THEN 1 ELSE 0 END) AS pre_tk_vs_mapping_mismatch,
  SUM(CASE WHEN C_EV_PRE <> C_EV_POST THEN 1 ELSE 0 END) AS ev_status_changed,
  SUM(CASE WHEN C_RR_PRE <> C_RR_POST THEN 1 ELSE 0 END) AS rr_status_changed,
  SUM(CASE WHEN N_RR > 0 AND (C_EV_PRE <> C_EV_POST OR C_RR_PRE <> C_RR_POST) THEN 1 ELSE 0 END) AS ev_or_rr_changed_with_rr,
  SUM(CASE WHEN C_TK_PRE <> C_TK_POST THEN 1 ELSE 0 END) AS tk_status_changed,
  SUM(CASE WHEN RF > 0 THEN 1 ELSE 0 END) AS n_refunded,
  SUM(CASE WHEN BAND = 2 AND NET_FULL = 0 THEN 1 ELSE 0 END) AS n_paid_gross_not_net,
  SUM(CASE WHEN BAND = 2 AND NET_FULL = 0 AND C_EV_POST = 2 THEN 1 ELSE 0 END) AS post_emitted_paid_gross_not_net,
  SUM(CASE WHEN ABS(PN - PN_PRECHAIN) > 0.001 THEN 1 ELSE 0 END) AS net_paid_prechain_vs_postchain_diff
FROM #qa_codes;
SELECT EX, LK, SC, AMT, PG, PN, RF, N_RR, C_EV_PRE, C_RR_PRE, C_TK_PRE, C_EV_POST, C_RR_POST, C_TK_POST
FROM #qa_codes WHERE EX > 0 ORDER BY EX;
SELECT SC, BAND, CASE WHEN AMT <= 0 THEN 1 ELSE 0 END AS AMT_ZERO, NET_FULL,
  C_EV_PRE, C_RR_PRE, C_EV_POST, C_RR_POST, C_TK_PRE, C_TK_POST, COUNT(*) AS n,
  SUM(CASE WHEN N_RR > 0 THEN 1 ELSE 0 END) AS n_with_rr,
  SUM(CASE WHEN ST = 'Pending' THEN 1 ELSE 0 END) AS st_pending, SUM(CASE WHEN ST = 'Complete' THEN 1 ELSE 0 END) AS st_complete,
  SUM(CASE WHEN ST = 'Tentative' THEN 1 ELSE 0 END) AS st_tentative, SUM(CASE WHEN ST = 'Confirmed' THEN 1 ELSE 0 END) AS st_confirmed,
  SUM(CASE WHEN ST = 'Finalized' THEN 1 ELSE 0 END) AS st_finalized, SUM(CASE WHEN ST = 'Cancelled' THEN 1 ELSE 0 END) AS st_cancelled,
  SUM(CASE WHEN ST = 'Reserved' THEN 1 ELSE 0 END) AS st_reserved, SUM(CASE WHEN ST = 'Unresolved' THEN 1 ELSE 0 END) AS st_unresolved
FROM #qa_codes
GROUP BY SC, BAND, CASE WHEN AMT <= 0 THEN 1 ELSE 0 END, NET_FULL, C_EV_PRE, C_RR_PRE, C_EV_POST, C_RR_POST, C_TK_PRE, C_TK_POST
ORDER BY SC, BAND, AMT_ZERO, NET_FULL, C_EV_POST;
SELECT COUNT(*) AS n_orders,
  SUM(CASE WHEN r.ID IS NULL THEN 1 ELSE 0 END) AS n_non_reservation_orders,
  SUM(CASE WHEN r.ID IS NULL AND ISNULL(PRE_TK,'~') <> ISNULL(POST_TK,'~') THEN 1 ELSE 0 END) AS non_res_ticket_status_changed,
  SUM(CASE WHEN r.ID IS NOT NULL AND ISNULL(PRE_TK,'~') <> ISNULL(POST_TK,'~') THEN 1 ELSE 0 END) AS res_ticket_status_changed
FROM SALESORDER so
LEFT JOIN RESERVATION r ON r.ID = so.ID
LEFT JOIN #pre_RentalPaymentRollups rpr_pre ON rpr_pre.RESERVATIONID = so.ID
LEFT JOIN #post_RentalPaymentRollups rpr_post ON rpr_post.RESERVATIONID = so.ID
CROSS APPLY (SELECT (CASE
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) AS PRE_TK, (CASE
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN r.ID IS NOT NULL
                        AND COALESCE(rpr_post.PAID_AMOUNT, 0) > 0
                        AND COALESCE(rpr_post.PAID_AMOUNT, 0) >= COALESCE(so.AMOUNT, 0) THEN 'Sold'
                WHEN r.ID IS NOT NULL AND COALESCE(rpr_post.PAID_AMOUNT, 0) > 0 THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized')
                        AND COALESCE(so.AMOUNT, 0) <= 0 THEN 'Sold'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Complete', 'Finalized', 'Confirmed') THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Tentative' THEN 'Reserved'
                WHEN r.ID IS NOT NULL AND so.STATUS = 'Pending' THEN 'Pending'
                WHEN r.ID IS NOT NULL AND so.STATUS IN ('Reserved', 'Unresolved') THEN 'Reserved'
                WHEN r.ID IS NOT NULL THEN 'Pending'
                
                WHEN so.STATUS = 'Complete' THEN 'Sold'
                WHEN so.STATUS = 'Pending' THEN 'Pending'
                WHEN so.STATUS = 'Cancelled' THEN 'Canceled'
                WHEN so.STATUS = 'Unresolved' THEN 'Pending'
                WHEN so.STATUS = 'Tentative' OR so.STATUSCODE = 2 THEN 'Reserved'
                ELSE so.STATUS
        END) AS POST_TK) t;
