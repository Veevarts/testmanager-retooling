-- IM-1228 live parity check (aggregate-only; safe for safesql).
-- Generated from the shipped rental_resource.sql and rental_events_groups.sql
-- on this branch (the event copy of RentalResourceItemTaxes is renamed so both
-- CTE lists fit one statement); regenerate if either file changes. Every
-- column is a count or a sum -- no row-level or PII data.
--   reservations                   RESERVATION rows
--   resource_rows / distinct_ids   rental_resource.sql grain (must be equal)
--   rental_items_multi_tax         rental items with > 1 SALESORDERITEMTAX row
--                                  (informational; pre-aggregated since IM-1228)
--   rental_items_link_fanout       rental items with > 1 itinerary/staff
--                                  resource link row (expect 0; > 0 breaks the
--                                  resource export grain and the parity below)
--   events_mismatched              event totals != package rollup over the
--                                  exported resources (expect 0)
--   events_nonzero_subtotal        events whose Subtotals2 would be > 0
--   total_subtotals / total_taxes  sums over all reservations
DECLARE @timeZone NVARCHAR(100) = 'Eastern Standard Time';

WITH RentalOrders AS (
    SELECT
        so.ID AS SALESORDERID,
        so.AMOUNT AS SALESORDER_AMOUNT
    FROM SALESORDER so
    INNER JOIN RESERVATION r
        ON r.ID = so.ID
),
PaymentRefunds AS (
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
),
RentalPaymentRows AS (
    SELECT
        ro.SALESORDERID AS RESERVATIONID,
        sop.AMOUNT AS PAID_VALUE,
        COALESCE(pr.REFUNDED_AMOUNT, 0) AS REFUNDED_AMOUNT
    FROM SALESORDERPAYMENT sop
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
    FROM RESERVATIONSECURITYDEPOSITPAYMENT rsdp
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
    FROM RentalPaymentRows
    GROUP BY RESERVATIONID
),
OrderDiscounts AS (
    SELECT
        soi.SALESORDERID,
        SUM(soi.TOTAL) AS TotalDiscountAmount
    FROM SALESORDERITEM soi
    INNER JOIN SALESORDERITEMORDERDISCOUNT soiod
        ON soi.ID = soiod.ID
    GROUP BY soi.SALESORDERID
),
-- IM-1228: SALESORDERITEMTAX is one row per (item, TAXID), so an item with a
-- state and a local tax used to emit two rows under one external id, each
-- taxed at one rate. Pre-aggregated to one row per item, TOTALTAX is the
-- combined percent. `rental-event/rental_events_groups.sql` joins the same
-- CTE text to compute the event's resource totals; keep both in step.
RentalResourceItemTaxes AS (
    SELECT
        SALESORDERITEMID,
        SUM(TOTALTAX) AS TOTALTAX
    FROM SALESORDERITEMTAX
    GROUP BY SALESORDERITEMID
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
        -- IM-1227: THE shared rental status ladder -- byte-identical to the
        -- Auctifera__Status__c projection in
        -- `rental-event/rental_events_groups.sql`. See the header contract.
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
    LEFT JOIN RentalResourceItemTaxes soitax
        ON soitax.SALESORDERITEMID = soi.ID
    LEFT JOIN SALESORDERITEMORDERDISCOUNT soidiscount
        ON soidiscount.ID = soi.ID
    LEFT JOIN OrderDiscounts od
        ON od.SALESORDERID = soi.SALESORDERID
    -- IM-1227: one row per RESERVATIONID (pre-aggregated), joined on that key,
    -- so the rental-resource row grain is untouched.
    LEFT JOIN RentalPaymentRollups rpr
        ON rpr.RESERVATIONID = r.ID
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
Emitted AS (
SELECT
    Auctifera__Resource_Rental_Charge__c,
    Implementation_External_ID__c,
    Auctifera__Rental_Event__c,
    Auctifera__Resource_Fee_Model__c,
    Auctifera__Event_Start_Time__c,
    Auctifera__Event_End_Time__c,
    Auctifera__Ticketing__c,
    Auctifera__Resource__c,
    Auctifera__Location__c,
    Auctifera__Number_of_items_attendees__c,
    Auctifera__Per_Person_Item_Charge__c,
    Auctifera__Resource_Flat_Fee_Charge__c,
    Auctifera__Tax_Rate__c,
    Auctifera__Rental_Status__c,
    Auctifera__Discount__c,
    Auctifera__Is_Ticket__c,
    Auctifera__Subtotal_Amount3__c,
    Auctifera__Ticketing_Tax_Amount__c,
    Auctifera__Tax_Amount3__c,
    Auctifera__Disable_Trigger__c
FROM BaseRentalResources
WHERE Auctifera__Is_Ticket__c = 0

UNION ALL

SELECT
    Auctifera__Resource_Rental_Charge__c,
    Implementation_External_ID__c,
    Auctifera__Rental_Event__c,
    Auctifera__Resource_Fee_Model__c,
    Auctifera__Event_Start_Time__c,
    Auctifera__Event_End_Time__c,
    Auctifera__Ticketing__c,
    Auctifera__Resource__c,
    Auctifera__Location__c,
    Auctifera__Number_of_items_attendees__c,
    Auctifera__Per_Person_Item_Charge__c,
    Auctifera__Resource_Flat_Fee_Charge__c,
    Auctifera__Tax_Rate__c,
    Auctifera__Rental_Status__c,
    Auctifera__Discount__c,
    Auctifera__Is_Ticket__c,
    Auctifera__Subtotal_Amount3__c,
    Auctifera__Ticketing_Tax_Amount__c,
    Auctifera__Tax_Amount3__c,
    Auctifera__Disable_Trigger__c
FROM AggregatedTicketRentalResources
),
PackageRollup AS (
    SELECT
        Auctifera__Rental_Event__c AS RESERVATIONID,
        SUM(CASE WHEN COALESCE(Auctifera__Rental_Status__c, N'') <> N'Canceled' THEN Auctifera__Subtotal_Amount3__c ELSE 0 END) AS SUBTOTALS,
        SUM(CASE WHEN COALESCE(Auctifera__Rental_Status__c, N'') <> N'Canceled' THEN Auctifera__Tax_Amount3__c ELSE 0 END) AS TAXES
    FROM Emitted
    GROUP BY Auctifera__Rental_Event__c
),
RentalItems AS (
    SELECT soi.ID FROM SALESORDERITEM soi INNER JOIN RESERVATION r ON r.ID = soi.SALESORDERID
),
-- IM-1228: the per-item money of `rental-resource/rental_resource.sql`, rolled
-- up the way the package's resource trigger would. See "Resource totals
-- contract" in the header before editing any expression below.
RentalResourceOrderDiscounts AS (
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
),
EventRentalResourceItemTaxes AS (
SELECT
        SALESORDERITEMID,
        SUM(TOTALTAX) AS TOTALTAX
FROM
        SALESORDERITEMTAX
GROUP BY
        SALESORDERITEMID
),
RentalResourceItemDiscounts AS (
SELECT
        r.ID AS RESERVATIONID,
        so.STATUS AS SALESORDER_STATUS,
        CASE
                WHEN soi.TYPE = 'Ticket' THEN 1
                ELSE 0
        END AS IS_TICKET,
        -- rental_resource.sql sets Auctifera__Ticketing__c = so.ID only for
        -- TYPECODE '0' (so.ID is never NULL behind the INNER JOIN).
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
LEFT JOIN EventRentalResourceItemTaxes soitax
        ON
        soitax.SALESORDERITEMID = soi.ID
LEFT JOIN RentalResourceOrderDiscounts od
        ON
        od.SALESORDERID = soi.SALESORDERID
WHERE
        soi.TYPECODE NOT IN ('4', '5')
),
RentalResourceItemAmounts AS (
SELECT
        RESERVATIONID,
        SALESORDER_STATUS,
        IS_TICKET,
        HAS_TICKETING,
        CAST(TOTAL - COALESCE(DISCOUNT_AMOUNT, 0) AS DECIMAL(18, 2)) AS SUBTOTAL_AMOUNT3,
        CAST((TOTAL - COALESCE(DISCOUNT_AMOUNT, 0)) * (COALESCE(TOTALTAX, 0) / 100.0) AS DECIMAL(18, 2)) AS TAX_AMOUNT3
FROM
        RentalResourceItemDiscounts
),
-- One row per RESERVATION, so the LEFT JOIN below cannot multiply rows.
RentalResourceTotals AS (
SELECT
        RESERVATIONID,
        SUM(SUBTOTAL_AMOUNT3) AS RESOURCE_SUBTOTALS,
        SUM(TAX_AMOUNT3) AS RESOURCE_TAXES
FROM
        RentalResourceItemAmounts
WHERE
        COALESCE(SALESORDER_STATUS, N'') <> N'Cancelled'
        AND (IS_TICKET = 0 OR HAS_TICKETING = 1)
GROUP BY
        RESERVATIONID
)
SELECT
    (SELECT COUNT(*) FROM RESERVATION) AS reservations,
    (SELECT COUNT(*) FROM Emitted) AS resource_rows,
    (SELECT COUNT(DISTINCT Implementation_External_ID__c) FROM Emitted) AS distinct_ids,
    (SELECT COUNT(*) FROM (SELECT t.SALESORDERITEMID FROM SALESORDERITEMTAX t INNER JOIN RentalItems ri ON ri.ID = t.SALESORDERITEMID GROUP BY t.SALESORDERITEMID HAVING COUNT(*) > 1) x) AS rental_items_multi_tax,
    (SELECT COUNT(*) FROM (SELECT l.SALESORDERITEMID FROM (SELECT SALESORDERITEMID FROM SALESORDERITEMITINERARYRESOURCE UNION ALL SELECT SALESORDERITEMID FROM SALESORDERITEMITINERARYITEMRESOURCE UNION ALL SELECT SALESORDERITEMID FROM SALESORDERITEMITINERARYSTAFFRESOURCE UNION ALL SELECT SALESORDERITEMID FROM SALESORDERITEMITINERARYITEMSTAFFRESOURCE) l INNER JOIN RentalItems ri ON ri.ID = l.SALESORDERITEMID GROUP BY l.SALESORDERITEMID HAVING COUNT(*) > 1) y) AS rental_items_link_fanout,
    SUM(CASE WHEN COALESCE(pr.SUBTOTALS, 0) <> COALESCE(rrt.RESOURCE_SUBTOTALS, 0)
              OR COALESCE(pr.TAXES, 0) <> COALESCE(rrt.RESOURCE_TAXES, 0) THEN 1 ELSE 0 END) AS events_mismatched,
    SUM(CASE WHEN COALESCE(rrt.RESOURCE_SUBTOTALS, 0) > 0 THEN 1 ELSE 0 END) AS events_nonzero_subtotal,
    SUM(COALESCE(rrt.RESOURCE_SUBTOTALS, 0)) AS total_subtotals,
    SUM(COALESCE(rrt.RESOURCE_TAXES, 0)) AS total_taxes
FROM RESERVATION r
LEFT JOIN PackageRollup pr ON pr.RESERVATIONID = r.ID
LEFT JOIN RentalResourceTotals rrt ON rrt.RESERVATIONID = r.ID;
