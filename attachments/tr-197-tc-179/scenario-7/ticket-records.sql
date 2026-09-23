DECLARE @hasDateFilterFrom BIT = 0;
DECLARE @hasDateFilterTo BIT = 0;
DECLARE @dateFilterFrom DATE = NULL;
DECLARE @dateFilterTo DATE = NULL;

DECLARE @useDateFrom BIT = IIF(@hasDateFilterFrom = 1, 1, 0);
DECLARE @useDateTo BIT = IIF(@hasDateFilterTo = 1, 1, 0);
DECLARE @filterDateFrom DATE = CAST(@dateFilterFrom AS DATE);
DECLARE @filterDateTo DATE = CAST(@dateFilterTo AS DATE);

    /*
    Purpose: create fund-assignment rows for membership-related refunds.
    Approach:
    1) RefundLineItems gets refund FT standard line items, preserving source line item and original payment transaction id.
    2) Source membership revenue split determines whether the refund belongs to Membership or Membership add-on.
    3) Membership transaction / recurring installment mapping mirrors membership opportunity logic so vnfp__Opportunity__c matches membership_transactions.sql.
    Notes:
    - Uses refund line item id as fund-assignment external id (same pattern as donation refunds).
    - Refund amount is negated to represent the refunded fund assignment.
    - Refunds without a membership transaction or recurring installment match are excluded to avoid orphan fund assignments.
    */
    WITH
    -- CREDITPAYMENT can have multiple rows per refund; preserve all links to original payment transactions.
    CreditPaymentPerRefund AS (
        SELECT
            CREDITID,
            REVENUEID AS OriginalPaymentTransactionId
        FROM
            CREDITPAYMENT
    ),
    SalesOrdersByPayment AS (
        SELECT
            sop.PAYMENTID,
            MIN(sop.SALESORDERID) AS SalesOrderID
        FROM
            SALESORDERPAYMENT sop
        GROUP BY
            sop.PAYMENTID
    ),
    OrderBackedMembershipPerSalesOrder AS (
        SELECT
            soi.SALESORDERID,
            soim.ID AS OrderMembershipItemID,
            ROW_NUMBER() OVER (
                PARTITION BY soi.SALESORDERID
                ORDER BY soi.ID
            ) AS MembershipRank
        FROM
            SALESORDERITEMMEMBERSHIP soim
        INNER JOIN SALESORDERITEM soi
            ON soi.ID = soim.ID
        WHERE
            soim.MEMBERSHIPTRANSACTIONID IS NULL
    ),
    DirectMembershipOpportunityPerSalesOrder AS (
        SELECT
            soi.SALESORDERID,
            soim.MEMBERSHIPTRANSACTIONID AS MembershipTransactionID,
            ROW_NUMBER() OVER (
                PARTITION BY soi.SALESORDERID
                ORDER BY soi.ID
            ) AS MembershipRank
        FROM
            SALESORDERITEMMEMBERSHIP soim
        INNER JOIN SALESORDERITEM soi
            ON soi.ID = soim.ID
        WHERE
            soim.MEMBERSHIPTRANSACTIONID IS NOT NULL
    ),
    RecurringInstallments AS (
        SELECT
            rgi.ID AS RecurringInstallmentID,
            rgi.REVENUEID AS FinancialTransactionID,
            rgp.PAYMENTID AS InstallmentPaymentFinancialTransactionId,
            ft.CALCULATEDUSERDEFINEDID AS RevenueId
        FROM
            RECURRINGGIFTINSTALLMENT rgi
        LEFT JOIN RECURRINGGIFTINSTALLMENTPAYMENT rgp
            ON rgp.RECURRINGGIFTINSTALLMENTID = rgi.ID
        LEFT JOIN FINANCIALTRANSACTION ft
            ON ft.ID = rgp.PAYMENTID
    ),
    RefundLineItems AS (
        SELECT
            rli.[TYPE] AS RefundLineType,
            refund_ft.ID AS FinancialTransactionID,
            rli.ID AS LineItemID,
            rli.TRANSACTIONAMOUNT AS RefundAmount,
            rli.SOURCELINEITEMID,
            cp.OriginalPaymentTransactionId,
            refund_ft.CALCULATEDDATE AS RefundTransactionDate,
            credit_membership_item.OrderMembershipItemID AS CreditOrderMembershipItemID
        FROM
            FINANCIALTRANSACTIONLINEITEM rli
        INNER JOIN FINANCIALTRANSACTION refund_ft
            ON refund_ft.ID = rli.FINANCIALTRANSACTIONID
        AND refund_ft.[TYPE] = 'Refund'
        INNER JOIN CreditPaymentPerRefund cp
            ON cp.CREDITID = refund_ft.ID
        -- IM-1275: Altru's early POS refunds (Long Island: 2011-2012) leave the
        -- refund's Standard line with a NULL SOURCELINEITEMID, so the membership
        -- line it reverses is reachable only through the credit's own item. The
        -- line-level evidence IM-562 demands is still line-level here: the credit
        -- carries exactly ONE item (enforced by the NOT EXISTS below), that item is
        -- a membership item, and it names the order-backed SALESORDERITEMMEMBERSHIP
        -- that fund_assignment_memberships.sql already keys the dues row on. A
        -- credit with a sibling item stays excluded - there the single refund line
        -- could belong to either item, which is exactly the SO-grain guess IM-562
        -- forbids. Measured on Long Island: 10 refunds / $2,205, all order-backed,
        -- all 2011-2012, every one of them named in IM-1275.
        OUTER APPLY (
            SELECT
                soim.ID AS OrderMembershipItemID
            FROM
                CREDITITEM ci
            INNER JOIN SALESORDERITEMMEMBERSHIP soim
                ON soim.ID = ci.SALESORDERITEMID
               AND soim.MEMBERSHIPTRANSACTIONID IS NULL
            WHERE
                ci.CREDITID = refund_ft.ID
                AND rli.[TYPE] = 'Standard'
                AND rli.SOURCELINEITEMID IS NULL
                AND NOT EXISTS (
                    SELECT 1
                    FROM CREDITITEM other_ci
                    WHERE other_ci.CREDITID = refund_ft.ID
                      AND other_ci.ID <> ci.ID
                )
                -- ... and exactly one line to pair with that one item. Two
                -- NULL-source Standard lines on a single-item credit would both
                -- resolve here and sum past the dues they reverse, with nothing in
                -- the data to say which one the item belongs to. Same ambiguity
                -- rule as the sibling-item guard above. Measured on Long Island:
                -- 0 refunds carry more than one such line today, so this bounds a
                -- shape that does not yet exist rather than dropping known rows.
                AND NOT EXISTS (
                    SELECT 1
                    FROM FINANCIALTRANSACTIONLINEITEM sibling_line
                    WHERE sibling_line.FINANCIALTRANSACTIONID = refund_ft.ID
                      AND sibling_line.[TYPE] = 'Standard'
                      AND sibling_line.SOURCELINEITEMID IS NULL
                      AND sibling_line.ID <> rli.ID
                )
        ) credit_membership_item
        WHERE
            (rli.[TYPE] = 'Standard' AND rli.SOURCELINEITEMID IS NOT NULL)
            OR credit_membership_item.OrderMembershipItemID IS NOT NULL
            -- IM-1275: when a 2011-2012 membership order carried a discount, Altru
            -- typed the refund's revenue line 'Discount' instead of 'Standard' and
            -- emitted no Standard line at all. That line still points at the
            -- membership line through SOURCELINEITEMID and still carries the whole
            -- refunded amount, so it is the refund line under a different type
            -- label. The NOT EXISTS keeps this arm off any refund that does have a
            -- Standard line, where a 'Discount' line really is a discount. Measured
            -- on Long Island: 12 refunds / $948, all 2011-2012. The matching sale
            -- side is fixed in fund_assignment_memberships.sql, which stopped
            -- counting these lines as order discounts.
            OR (
                rli.[TYPE] = 'Discount'
                AND rli.SOURCELINEITEMID IS NOT NULL
                AND NOT EXISTS (
                    SELECT 1
                    FROM FINANCIALTRANSACTIONLINEITEM standard_line
                    WHERE standard_line.FINANCIALTRANSACTIONID = refund_ft.ID
                      AND standard_line.[TYPE] = 'Standard'
                )
            )
    ),
    CreditItemMembershipFallback AS (
        SELECT
            rli.LineItemID,
            mt.ID AS MembershipTransactionID,
            ROW_NUMBER() OVER (
                PARTITION BY rli.LineItemID
                ORDER BY mt.TRANSACTIONDATE DESC, mt.ID DESC
            ) AS MembershipRank
        FROM
            RefundLineItems rli
        INNER JOIN CREDITITEMMEMBERSHIP cim
            ON cim.ID = rli.SOURCELINEITEMID
            OR cim.ID = rli.LineItemID
        INNER JOIN MEMBERSHIPTRANSACTION mt
            ON mt.MEMBERSHIPID = cim.MEMBERSHIPID
        AND mt.TRANSACTIONDATE <= rli.RefundTransactionDate
    ),
    RawRefundFundAssignments AS (
    SELECT
        rli.RefundLineType AS RefundLineType,
        rli.CreditOrderMembershipItemID AS ArmCreditItemID,
        rli.LineItemID AS vnfp__Implementation_External_ID__c,
        -- SO resolution: direct membership > addon > original payment > payment-backed > refund
        -- fallback_membership_so excluded: it resolves via heuristic MT guess (same membership, not same transaction)
        COALESCE(membership_so.LOOKUPID, addon_so.LOOKUPID, original_so.LOOKUPID, payment_so.LOOKUPID, refund_so.LOOKUPID) AS LookUp_ID_Legacy,
        CASE COALESCE(source_rse.APPLICATION, CASE WHEN cimf.MembershipTransactionID IS NOT NULL OR rli.CreditOrderMembershipItemID IS NOT NULL THEN 'Membership' END)
            WHEN 'Membership' THEN 'Membership_Fund'
            WHEN 'Membership add-on' THEN 'Add_On_Fund'
        END AS Auctifera__Specific_Fund__c,
        d.NAME AS Auctifera__Specific_Fund_Name__c,
        'Posted' AS Auctifera__Accounting_Status__c,
        'Refunded' AS Auctifera__Status__c,
        (rli.RefundAmount * -1) AS Auctifera__Donated_Amount__c,
        CAST(refund_ft.CALCULATEDDATE AS DATE) AS Auctifera__Posted_Date__c,
        'Acknowledged' AS vnfp__Acknowledgment_Status__c,
        -- Opportunity resolution: recurring > line-specific MT > line-specific addon
        -- > SO-ranked direct MT (fallback) > order-backed MT (no MT) > CIM heuristic.
        -- fix(IM-561): line-specific lineage (mt.ID / ma.MEMBERSHIPTRANSACTIONID) MUST win
        -- before the SO-ranked direct_order_membership fallback; otherwise multi-membership
        -- refunds on one sales order collapse onto the first ranked opportunity.
        -- Recurring (rgi.RecurringInstallmentID) still ranks ahead of mt.ID: a refund of a
        -- recurring-gift installment payment must route to the installment opportunity
        -- emitted by membership_transactions.sql (RecurringInstallmentID-keyed), not to the
        -- membership transaction it touches. Membership opportunities are the per-line grain
        -- only for non-recurring sources.
        -- IM-1275: the credit's own membership item (CreditOrderMembershipItemID)
        -- ranks above both SO-grain fallbacks. It is line-level evidence - the one
        -- item on this credit - so it must not lose to direct_order_membership,
        -- which only ranks the sales order's membership items by SALESORDERITEM.ID.
        CAST(COALESCE(rgi.RecurringInstallmentID, mt.ID, ma.MEMBERSHIPTRANSACTIONID, rli.CreditOrderMembershipItemID, direct_order_membership.MembershipTransactionID, order_membership.OrderMembershipItemID, cimf.MembershipTransactionID) AS VARCHAR(36)) AS vnfp__Opportunity__c,
        COALESCE(membership_so.ID, addon_so.ID, original_so.ID, payment_so.ID, refund_so.ID) AS vnfp__Opportunity_POS_Purchase__c
    FROM
        RefundLineItems rli
    INNER JOIN FINANCIALTRANSACTION refund_ft
        ON refund_ft.ID = rli.FinancialTransactionID
    LEFT JOIN REVENUESPLIT_EXT source_rse
        ON source_rse.ID = rli.SOURCELINEITEMID
    AND source_rse.APPLICATION IN ('Membership', 'Membership add-on')
    LEFT JOIN CreditItemMembershipFallback cimf
        ON cimf.LineItemID = rli.LineItemID
    AND cimf.MembershipRank = 1
    LEFT JOIN MEMBERSHIPTRANSACTION mt
        ON mt.REVENUESPLITID = rli.SOURCELINEITEMID
    LEFT JOIN MEMBERSHIPADDON ma
        ON ma.REVENUESPLITID = rli.SOURCELINEITEMID
    LEFT JOIN RecurringInstallments rgi
        ON rgi.InstallmentPaymentFinancialTransactionId = rli.OriginalPaymentTransactionId
    LEFT JOIN SALESORDERITEMMEMBERSHIP soim
        ON soim.MEMBERSHIPTRANSACTIONID = mt.ID
    LEFT JOIN SALESORDERITEMMEMBERSHIPADDON soima
        ON soima.MEMBERSHIPTRANSACTIONID = ma.MEMBERSHIPTRANSACTIONID
    LEFT JOIN SALESORDERITEM soi
        ON soi.ID = COALESCE(soim.ID, soima.ID)
    LEFT JOIN SALESORDER membership_so
        ON membership_so.ID = soi.SALESORDERID
    LEFT JOIN SALESORDER addon_so
        ON addon_so.ID = soi.SALESORDERID
    LEFT JOIN SALESORDER original_so
        ON original_so.REVENUEID = rli.OriginalPaymentTransactionId
    LEFT JOIN SalesOrdersByPayment sop
        ON sop.PAYMENTID = rli.OriginalPaymentTransactionId
    LEFT JOIN SALESORDER payment_so
        ON payment_so.ID = sop.SalesOrderID
    LEFT JOIN SALESORDER refund_so
        ON refund_so.REVENUEID = refund_ft.ID
    LEFT JOIN DirectMembershipOpportunityPerSalesOrder direct_order_membership
        ON direct_order_membership.SALESORDERID = COALESCE(membership_so.ID, addon_so.ID, original_so.ID, payment_so.ID, refund_so.ID)
    AND direct_order_membership.MembershipRank = 1
    LEFT JOIN OrderBackedMembershipPerSalesOrder order_membership
        ON order_membership.SALESORDERID = COALESCE(membership_so.ID, addon_so.ID, original_so.ID, payment_so.ID, refund_so.ID)
    AND order_membership.MembershipRank = 1
    LEFT JOIN DESIGNATION d
        ON d.ID = source_rse.DESIGNATIONID
    WHERE
        COALESCE(rgi.RecurringInstallmentID, mt.ID, ma.MEMBERSHIPTRANSACTIONID, rli.CreditOrderMembershipItemID, direct_order_membership.MembershipTransactionID, order_membership.OrderMembershipItemID, cimf.MembershipTransactionID) IS NOT NULL
        -- IM-811: intentionally do NOT require a Sales Order here. Non-POS memberships
        -- (credit-item memberships linked only via CREDITITEMMEMBERSHIP, and direct-revenue
        -- dues) carry no SALESORDER in their lineage, so demanding one silently dropped their
        -- refunds even though the dues side (fund_assignment_memberships.sql:250-253) migrates
        -- the matching dues with a null POS purchase. The opportunity check above (a real
        -- MT / add-on / recurring / cimf) plus the line-level membership evidence gate below
        -- already prevent orphan fund assignments; a missing SO simply yields a null
        -- vnfp__Opportunity_POS_Purchase__c, matching the dues query (asymmetry fix).
        -- SO-backed refunds are unaffected: their SO COALESCE was already non-null.
        -- IM-562: require a line-level membership link so ticket refunds that share a
        -- sales order with a membership cannot qualify solely via direct_order_membership
        -- or order_membership (which resolve at SO grain, not line grain).
        --
        -- Note on asymmetry with the opportunity COALESCE above: direct_order_membership
        -- and order_membership intentionally stay in the COALESCE as opportunity-resolution
        -- fallbacks — they still map an opportunity ID for rows that already qualify via
        -- source_rse.APPLICATION / cimf / mt / ma / rgi, but they can no longer be the
        -- sole qualifier for a row. A refund with no line-level membership evidence is
        -- dropped even when its SO has an order-backed (SOIM without MT) membership; the
        -- tradeoff is intentional — we prefer a silent drop over a false-positive membership
        -- fund assignment attached to a sibling SOIM. Cross-tenant live validation
        -- (see PR #97) showed FixedOnly == IM-561 reroutes across every reachable profile,
        -- i.e. no rows in production are dropped purely by this asymmetry today.
        AND (
            source_rse.APPLICATION IN ('Membership', 'Membership add-on')
            OR cimf.MembershipTransactionID IS NOT NULL
            OR mt.ID IS NOT NULL
            OR ma.MEMBERSHIPTRANSACTIONID IS NOT NULL
            OR rgi.RecurringInstallmentID IS NOT NULL
            -- IM-1275: the credit-item link is line-level evidence too (one item on
            -- the credit, resolved above), so it qualifies a row on its own.
            OR rli.CreditOrderMembershipItemID IS NOT NULL
        )
        AND (@useDateFrom = 0 OR CAST(refund_ft.CALCULATEDDATE AS DATE) >= @filterDateFrom)
        AND (@useDateTo = 0 OR CAST(refund_ft.CALCULATEDDATE AS DATE) <= @filterDateTo)
    ),
    DedupedRefundFundAssignments AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY
                vnfp__Implementation_External_ID__c,
                LookUp_ID_Legacy,
                Auctifera__Specific_Fund__c,
                Auctifera__Specific_Fund_Name__c,
                Auctifera__Accounting_Status__c,
                Auctifera__Status__c,
                Auctifera__Donated_Amount__c,
                Auctifera__Posted_Date__c,
                vnfp__Acknowledgment_Status__c,
                vnfp__Opportunity__c,
                vnfp__Opportunity_POS_Purchase__c
            ORDER BY
                vnfp__Implementation_External_ID__c
        ) AS DedupRank
    FROM
        RawRefundFundAssignments
    )
    SELECT
        LookUp_ID_Legacy,
        CASE WHEN ArmCreditItemID IS NOT NULL THEN 'A_credit_item'
             WHEN RefundLineType = 'Discount' THEN 'B_discount_typed'
             ELSE 'C_pre_existing' END AS admit_arm,
        COUNT(*) AS n_rows,
        SUM(Auctifera__Donated_Amount__c) AS amount_sum,
        MIN(Auctifera__Posted_Date__c) AS posted_date
    FROM
        DedupedRefundFundAssignments
    WHERE
        DedupRank = 1
        AND (LookUp_ID_Legacy LIKE '%10006030' OR LookUp_ID_Legacy LIKE '%10001529' OR LookUp_ID_Legacy LIKE '%10009212' OR LookUp_ID_Legacy LIKE '%10009523' OR LookUp_ID_Legacy LIKE '%10009591' OR LookUp_ID_Legacy LIKE '%10009551' OR LookUp_ID_Legacy LIKE '%10025759' OR LookUp_ID_Legacy LIKE '%10025930' OR LookUp_ID_Legacy LIKE '%10015189' OR LookUp_ID_Legacy LIKE '%10020278' OR LookUp_ID_Legacy LIKE '%10036876' OR LookUp_ID_Legacy LIKE '%10037314' OR LookUp_ID_Legacy LIKE '%10031528' OR LookUp_ID_Legacy LIKE '%10017730' OR LookUp_ID_Legacy LIKE '%10041986' OR LookUp_ID_Legacy LIKE '%10111554' OR LookUp_ID_Legacy LIKE '%10041566')
    GROUP BY
        LookUp_ID_Legacy,
        CASE WHEN ArmCreditItemID IS NOT NULL THEN 'A_credit_item'
             WHEN RefundLineType = 'Discount' THEN 'B_discount_typed'
             ELSE 'C_pre_existing' END
    ORDER BY
        1;
