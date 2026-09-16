DECLARE @timeZone NVARCHAR(100) = 'Eastern Standard Time';
SELECT x.SALESORDERID, x.SALESORDER_AMOUNT INTO #rrpre_RentalOrders FROM (
    SELECT
        so.ID AS SALESORDERID,
        so.AMOUNT AS SALESORDER_AMOUNT
    FROM SALESORDER so
    INNER JOIN RESERVATION r
        ON r.ID = so.ID
) AS x;
SELECT x.PAYMENT_TRANSACTION_ID, x.REFUNDED_AMOUNT INTO #rrpre_PaymentRefunds FROM (
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
SELECT x.RESERVATIONID, x.PAID_VALUE, x.REFUNDED_AMOUNT INTO #rrpre_RentalPaymentRows FROM (
    SELECT
        ro.SALESORDERID AS RESERVATIONID,
        sop.AMOUNT AS PAID_VALUE,
        COALESCE(pr.REFUNDED_AMOUNT, 0) AS REFUNDED_AMOUNT
    FROM SALESORDERPAYMENT sop
    INNER JOIN FINANCIALTRANSACTION ft
        ON ft.ID = sop.PAYMENTID
        AND ft.TYPE = 'Payment'
    INNER JOIN #rrpre_RentalOrders ro
        ON ro.SALESORDERID = sop.SALESORDERID
    LEFT JOIN #rrpre_PaymentRefunds pr
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
    INNER JOIN #rrpre_RentalOrders ro
        ON ro.SALESORDERID = rsdp.RESERVATIONID
    LEFT JOIN #rrpre_PaymentRefunds pr
        ON pr.PAYMENT_TRANSACTION_ID = rsdp.PAYMENTID
) AS x;
SELECT x.RESERVATIONID, x.PAID_AMOUNT, x.TOTAL_REFUNDED_AMOUNT, x.NET_PAID_AMOUNT INTO #rrpre_RentalPaymentRollups FROM (
    SELECT
        RESERVATIONID,
        SUM(COALESCE(PAID_VALUE, 0)) AS PAID_AMOUNT,
        SUM(COALESCE(REFUNDED_AMOUNT, 0)) AS TOTAL_REFUNDED_AMOUNT,
        SUM(COALESCE(PAID_VALUE, 0)) - SUM(COALESCE(REFUNDED_AMOUNT, 0)) AS NET_PAID_AMOUNT
    FROM #rrpre_RentalPaymentRows
    GROUP BY RESERVATIONID
) AS x;
SELECT x.SALESORDERID, x.TotalDiscountAmount INTO #rrpre_OrderDiscounts FROM (
    SELECT
        soi.SALESORDERID,
        SUM(soi.TOTAL) AS TotalDiscountAmount
    FROM SALESORDERITEM soi
    INNER JOIN SALESORDERITEMORDERDISCOUNT soiod
        ON soi.ID = soiod.ID
    GROUP BY soi.SALESORDERID
) AS x;
SELECT x.Auctifera__Resource_Rental_Charge__c, x.Implementation_External_ID__c, x.Auctifera__Rental_Event__c, x.Auctifera__Resource_Fee_Model__c, x.Auctifera__Event_Start_Time__c, x.Auctifera__Event_End_Time__c, x.Auctifera__Ticketing__c, x.Auctifera__Resource__c, x.Auctifera__Location__c, x.Auctifera__Number_of_items_attendees__c, x.Auctifera__Per_Person_Item_Charge__c, x.Auctifera__Resource_Flat_Fee_Charge__c, x.Auctifera__Tax_Rate__c, x.Auctifera__Rental_Status__c, x.Auctifera__Discount__c, x.Auctifera__Is_Ticket__c, x.Auctifera__Subtotal_Amount3__c, x.Auctifera__Ticketing_Tax_Amount__c, x.Auctifera__Tax_Amount3__c, x.Auctifera__Disable_Trigger__c INTO #rrpre_BaseRentalResources FROM (
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
    LEFT JOIN SALESORDERITEMTAX soitax
        ON soitax.SALESORDERITEMID = soi.ID
    LEFT JOIN SALESORDERITEMORDERDISCOUNT soidiscount
        ON soidiscount.ID = soi.ID
    LEFT JOIN #rrpre_OrderDiscounts od
        ON od.SALESORDERID = soi.SALESORDERID
    
    
    LEFT JOIN #rrpre_RentalPaymentRollups rpr
        ON rpr.RESERVATIONID = r.ID
    WHERE soi.TYPECODE NOT IN ('4', '5')
) AS x;
SELECT x.Auctifera__Resource_Rental_Charge__c, x.Implementation_External_ID__c, x.Auctifera__Rental_Event__c, x.Auctifera__Resource_Fee_Model__c, x.Auctifera__Event_Start_Time__c, x.Auctifera__Event_End_Time__c, x.Auctifera__Ticketing__c, x.Auctifera__Resource__c, x.Auctifera__Location__c, x.Auctifera__Number_of_items_attendees__c, x.Auctifera__Per_Person_Item_Charge__c, x.Auctifera__Resource_Flat_Fee_Charge__c, x.Auctifera__Tax_Rate__c, x.Auctifera__Rental_Status__c, x.Auctifera__Discount__c, x.Auctifera__Is_Ticket__c, x.Auctifera__Subtotal_Amount3__c, x.Auctifera__Ticketing_Tax_Amount__c, x.Auctifera__Tax_Amount3__c, x.Auctifera__Disable_Trigger__c INTO #rrpre_AggregatedTicketRentalResources FROM (
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
    FROM #rrpre_BaseRentalResources
    WHERE Auctifera__Is_Ticket__c = 1
        AND Auctifera__Ticketing__c IS NOT NULL
    GROUP BY
        Auctifera__Rental_Event__c,
        Auctifera__Event_Start_Time__c,
        Auctifera__Event_End_Time__c,
        Auctifera__Ticketing__c,
        Auctifera__Rental_Status__c
) AS x;
SELECT q.Implementation_External_ID__c AS RRID, q.Auctifera__Rental_Status__c AS RST, q.Auctifera__Subtotal_Amount3__c AS SUB3, q.Auctifera__Tax_Amount3__c AS TAX3 INTO #qa_pre FROM (SELECT Implementation_External_ID__c AS Implementation_External_ID__c,
  Auctifera__Rental_Event__c AS Auctifera__Rental_Event__c,
  Auctifera__Rental_Status__c AS Auctifera__Rental_Status__c,
  Auctifera__Subtotal_Amount3__c AS Auctifera__Subtotal_Amount3__c,
  Auctifera__Tax_Amount3__c AS Auctifera__Tax_Amount3__c
FROM #rrpre_BaseRentalResources
WHERE Auctifera__Is_Ticket__c = 0 UNION ALL SELECT Implementation_External_ID__c AS Implementation_External_ID__c,
  Auctifera__Rental_Event__c AS Auctifera__Rental_Event__c,
  Auctifera__Rental_Status__c AS Auctifera__Rental_Status__c,
  Auctifera__Subtotal_Amount3__c AS Auctifera__Subtotal_Amount3__c,
  Auctifera__Tax_Amount3__c AS Auctifera__Tax_Amount3__c
FROM #rrpre_AggregatedTicketRentalResources) AS q;
SELECT x.SALESORDERID, x.SALESORDER_AMOUNT INTO #rrpost_RentalOrders FROM (
    SELECT
        so.ID AS SALESORDERID,
        so.AMOUNT AS SALESORDER_AMOUNT
    FROM SALESORDER so
    INNER JOIN RESERVATION r
        ON r.ID = so.ID
) AS x;
SELECT x.PAYMENT_TRANSACTION_ID, x.REFUNDED_AMOUNT INTO #rrpost_PaymentRefunds FROM (
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
SELECT x.RESERVATIONID, x.PAID_VALUE, x.REFUNDED_AMOUNT INTO #rrpost_RentalPaymentRows FROM (
    SELECT
        ro.SALESORDERID AS RESERVATIONID,
        sop.AMOUNT AS PAID_VALUE,
        COALESCE(pr.REFUNDED_AMOUNT, 0) AS REFUNDED_AMOUNT
    FROM SALESORDERPAYMENT sop
    INNER JOIN FINANCIALTRANSACTION ft
        ON ft.ID = sop.PAYMENTID
        AND ft.TYPE = 'Payment'
    INNER JOIN #rrpost_RentalOrders ro
        ON ro.SALESORDERID = sop.SALESORDERID
    LEFT JOIN #rrpost_PaymentRefunds pr
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
    INNER JOIN #rrpost_RentalOrders ro
        ON ro.SALESORDERID = rsdp.RESERVATIONID
    LEFT JOIN #rrpost_PaymentRefunds pr
        ON pr.PAYMENT_TRANSACTION_ID = rsdp.PAYMENTID
) AS x;
SELECT x.RESERVATIONID, x.PAID_AMOUNT, x.TOTAL_REFUNDED_AMOUNT, x.NET_PAID_AMOUNT INTO #rrpost_RentalPaymentRollups FROM (
    SELECT
        RESERVATIONID,
        SUM(COALESCE(PAID_VALUE, 0)) AS PAID_AMOUNT,
        SUM(COALESCE(REFUNDED_AMOUNT, 0)) AS TOTAL_REFUNDED_AMOUNT,
        SUM(COALESCE(PAID_VALUE, 0)) - SUM(COALESCE(REFUNDED_AMOUNT, 0)) AS NET_PAID_AMOUNT
    FROM #rrpost_RentalPaymentRows
    GROUP BY RESERVATIONID
) AS x;
SELECT x.SALESORDERID, x.TotalDiscountAmount INTO #rrpost_OrderDiscounts FROM (
    SELECT
        soi.SALESORDERID,
        SUM(soi.TOTAL) AS TotalDiscountAmount
    FROM SALESORDERITEM soi
    INNER JOIN SALESORDERITEMORDERDISCOUNT soiod
        ON soi.ID = soiod.ID
    GROUP BY soi.SALESORDERID
) AS x;
SELECT x.SALESORDERITEMID, x.TOTALTAX INTO #rrpost_RentalResourceItemTaxes FROM (
    SELECT
        SALESORDERITEMID,
        SUM(TOTALTAX) AS TOTALTAX
    FROM SALESORDERITEMTAX
    GROUP BY SALESORDERITEMID
) AS x;
SELECT x.Auctifera__Resource_Rental_Charge__c, x.Implementation_External_ID__c, x.Auctifera__Rental_Event__c, x.Auctifera__Resource_Fee_Model__c, x.Auctifera__Event_Start_Time__c, x.Auctifera__Event_End_Time__c, x.Auctifera__Ticketing__c, x.Auctifera__Resource__c, x.Auctifera__Location__c, x.Auctifera__Number_of_items_attendees__c, x.Auctifera__Per_Person_Item_Charge__c, x.Auctifera__Resource_Flat_Fee_Charge__c, x.Auctifera__Tax_Rate__c, x.Auctifera__Rental_Status__c, x.Auctifera__Discount__c, x.Auctifera__Is_Ticket__c, x.Auctifera__Subtotal_Amount3__c, x.Auctifera__Ticketing_Tax_Amount__c, x.Auctifera__Tax_Amount3__c, x.Auctifera__Disable_Trigger__c INTO #rrpost_BaseRentalResources FROM (
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
    LEFT JOIN #rrpost_RentalResourceItemTaxes soitax
        ON soitax.SALESORDERITEMID = soi.ID
    LEFT JOIN SALESORDERITEMORDERDISCOUNT soidiscount
        ON soidiscount.ID = soi.ID
    LEFT JOIN #rrpost_OrderDiscounts od
        ON od.SALESORDERID = soi.SALESORDERID
    
    
    LEFT JOIN #rrpost_RentalPaymentRollups rpr
        ON rpr.RESERVATIONID = r.ID
    WHERE soi.TYPECODE NOT IN ('4', '5')
) AS x;
SELECT x.Auctifera__Resource_Rental_Charge__c, x.Implementation_External_ID__c, x.Auctifera__Rental_Event__c, x.Auctifera__Resource_Fee_Model__c, x.Auctifera__Event_Start_Time__c, x.Auctifera__Event_End_Time__c, x.Auctifera__Ticketing__c, x.Auctifera__Resource__c, x.Auctifera__Location__c, x.Auctifera__Number_of_items_attendees__c, x.Auctifera__Per_Person_Item_Charge__c, x.Auctifera__Resource_Flat_Fee_Charge__c, x.Auctifera__Tax_Rate__c, x.Auctifera__Rental_Status__c, x.Auctifera__Discount__c, x.Auctifera__Is_Ticket__c, x.Auctifera__Subtotal_Amount3__c, x.Auctifera__Ticketing_Tax_Amount__c, x.Auctifera__Tax_Amount3__c, x.Auctifera__Disable_Trigger__c INTO #rrpost_AggregatedTicketRentalResources FROM (
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
    FROM #rrpost_BaseRentalResources
    WHERE Auctifera__Is_Ticket__c = 1
        AND Auctifera__Ticketing__c IS NOT NULL
    GROUP BY
        Auctifera__Rental_Event__c,
        Auctifera__Event_Start_Time__c,
        Auctifera__Event_End_Time__c,
        Auctifera__Ticketing__c,
        Auctifera__Rental_Status__c
) AS x;
SELECT q.Implementation_External_ID__c AS RRID, q.Auctifera__Rental_Status__c AS RST, q.Auctifera__Subtotal_Amount3__c AS SUB3, q.Auctifera__Tax_Amount3__c AS TAX3 INTO #qa_post FROM (SELECT Implementation_External_ID__c AS Implementation_External_ID__c,
  Auctifera__Rental_Event__c AS Auctifera__Rental_Event__c,
  Auctifera__Rental_Status__c AS Auctifera__Rental_Status__c,
  Auctifera__Subtotal_Amount3__c AS Auctifera__Subtotal_Amount3__c,
  Auctifera__Tax_Amount3__c AS Auctifera__Tax_Amount3__c
FROM #rrpost_BaseRentalResources
WHERE Auctifera__Is_Ticket__c = 0 UNION ALL SELECT Implementation_External_ID__c AS Implementation_External_ID__c,
  Auctifera__Rental_Event__c AS Auctifera__Rental_Event__c,
  Auctifera__Rental_Status__c AS Auctifera__Rental_Status__c,
  Auctifera__Subtotal_Amount3__c AS Auctifera__Subtotal_Amount3__c,
  Auctifera__Tax_Amount3__c AS Auctifera__Tax_Amount3__c
FROM #rrpost_AggregatedTicketRentalResources) AS q;
SELECT RRID, COUNT(*) AS N, MIN(SUB3) AS SUB_MIN, MAX(SUB3) AS SUB_MAX, SUM(TAX3) AS TAX_SUM, MIN(RST) AS RST_MIN, MAX(RST) AS RST_MAX
INTO #qa_pre_g FROM #qa_pre GROUP BY RRID;
SELECT
  (SELECT COUNT(*) FROM #qa_pre) AS pre_rows, (SELECT COUNT(*) FROM #qa_pre_g) AS pre_distinct_ids,
  (SELECT COUNT(*) FROM #qa_pre_g WHERE N > 1) AS pre_ids_duplicated, (SELECT COALESCE(SUM(N - 1),0) FROM #qa_pre_g WHERE N > 1) AS pre_extra_rows,
  (SELECT COUNT(*) FROM #qa_post) AS post_rows, (SELECT COUNT(DISTINCT RRID) FROM #qa_post) AS post_distinct_ids,
  (SELECT COUNT(*) FROM #qa_pre_g g LEFT JOIN #qa_post p ON p.RRID = g.RRID WHERE p.RRID IS NULL) AS ids_lost,
  (SELECT COUNT(*) FROM #qa_post p LEFT JOIN #qa_pre_g g ON g.RRID = p.RRID WHERE g.RRID IS NULL) AS ids_new,
  (SELECT COUNT(*) FROM #qa_pre_g g JOIN #qa_post p ON p.RRID = g.RRID WHERE g.N = 1 AND (ISNULL(g.SUB_MIN,-1) <> ISNULL(p.SUB3,-1) OR ISNULL(g.TAX_SUM,-1) <> ISNULL(p.TAX3,-1))) AS single_rate_amount_changed,
  (SELECT COUNT(*) FROM #qa_pre_g g JOIN #qa_post p ON p.RRID = g.RRID WHERE g.N > 1 AND ISNULL(g.SUB_MIN,-1) <> ISNULL(p.SUB3,-1)) AS multi_subtotal_changed,
  (SELECT COUNT(*) FROM #qa_pre_g g JOIN #qa_post p ON p.RRID = g.RRID WHERE g.N > 1 AND ABS(ISNULL(g.TAX_SUM,0) - ISNULL(p.TAX3,0)) > 0.01 * (g.N - 1)) AS multi_tax_not_combined,
  (SELECT COUNT(*) FROM #qa_pre_g g JOIN #qa_post p ON p.RRID = g.RRID WHERE ISNULL(g.RST_MIN,'~') <> ISNULL(p.RST,'~') OR ISNULL(g.RST_MAX,'~') <> ISNULL(p.RST,'~')) AS status_changed,
  CAST((SELECT SUM(SUB3) FROM #qa_pre) AS DECIMAL(18,2)) AS pre_sum_sub3, CAST((SELECT SUM(SUB3) FROM #qa_post) AS DECIMAL(18,2)) AS post_sum_sub3,
  CAST((SELECT SUM(TAX3) FROM #qa_pre) AS DECIMAL(18,2)) AS pre_sum_tax3, CAST((SELECT SUM(TAX3) FROM #qa_post) AS DECIMAL(18,2)) AS post_sum_tax3;
