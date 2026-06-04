-- IM-811 aggregate validation (POST-FIX, without SO gate) — 2017-2019 membership refunds
-- Mirrors fund_assignments_membership_refunds.sql, simplified to aggregates.
WITH
CreditPaymentPerRefund AS (
    SELECT CREDITID, REVENUEID AS OriginalPaymentTransactionId FROM CREDITPAYMENT
),
SalesOrdersByPayment AS (
    SELECT sop.PAYMENTID, MIN(sop.SALESORDERID) AS SalesOrderID
    FROM SALESORDERPAYMENT sop GROUP BY sop.PAYMENTID
),
OrderBackedMembershipPerSalesOrder AS (
    SELECT soi.SALESORDERID, soim.ID AS OrderMembershipItemID,
           ROW_NUMBER() OVER (PARTITION BY soi.SALESORDERID ORDER BY soi.ID) AS MembershipRank
    FROM SALESORDERITEMMEMBERSHIP soim INNER JOIN SALESORDERITEM soi ON soi.ID = soim.ID
    WHERE soim.MEMBERSHIPTRANSACTIONID IS NULL
),
DirectMembershipOpportunityPerSalesOrder AS (
    SELECT soi.SALESORDERID, soim.MEMBERSHIPTRANSACTIONID AS MembershipTransactionID,
           ROW_NUMBER() OVER (PARTITION BY soi.SALESORDERID ORDER BY soi.ID) AS MembershipRank
    FROM SALESORDERITEMMEMBERSHIP soim INNER JOIN SALESORDERITEM soi ON soi.ID = soim.ID
    WHERE soim.MEMBERSHIPTRANSACTIONID IS NOT NULL
),
RecurringInstallments AS (
    SELECT rgi.ID AS RecurringInstallmentID, rgi.REVENUEID AS FinancialTransactionID,
           rgp.PAYMENTID AS InstallmentPaymentFinancialTransactionId,
           ft.CALCULATEDUSERDEFINEDID AS RevenueId
    FROM RECURRINGGIFTINSTALLMENT rgi
    LEFT JOIN RECURRINGGIFTINSTALLMENTPAYMENT rgp ON rgp.RECURRINGGIFTINSTALLMENTID = rgi.ID
    LEFT JOIN FINANCIALTRANSACTION ft ON ft.ID = rgp.PAYMENTID
),
RefundLineItems AS (
    SELECT refund_ft.ID AS FinancialTransactionID, rli.ID AS LineItemID,
           rli.TRANSACTIONAMOUNT AS RefundAmount, rli.SOURCELINEITEMID,
           cp.OriginalPaymentTransactionId, refund_ft.CALCULATEDDATE AS RefundTransactionDate
    FROM FINANCIALTRANSACTIONLINEITEM rli
    INNER JOIN FINANCIALTRANSACTION refund_ft
        ON refund_ft.ID = rli.FINANCIALTRANSACTIONID AND refund_ft.[TYPE] = 'Refund'
    INNER JOIN CreditPaymentPerRefund cp ON cp.CREDITID = refund_ft.ID
    WHERE rli.[TYPE] = 'Standard' AND rli.SOURCELINEITEMID IS NOT NULL
),
CreditItemMembershipFallback AS (
    SELECT rli.LineItemID, mt.ID AS MembershipTransactionID,
           ROW_NUMBER() OVER (PARTITION BY rli.LineItemID
                              ORDER BY mt.TRANSACTIONDATE DESC, mt.ID DESC) AS MembershipRank
    FROM RefundLineItems rli
    INNER JOIN CREDITITEMMEMBERSHIP cim ON cim.ID = rli.SOURCELINEITEMID OR cim.ID = rli.LineItemID
    INNER JOIN MEMBERSHIPTRANSACTION mt
        ON mt.MEMBERSHIPID = cim.MEMBERSHIPID
       AND mt.TRANSACTIONDATE <= rli.RefundTransactionDate
),
RawRefundFundAssignments AS (
    SELECT
        rli.LineItemID AS vnfp__Implementation_External_ID__c,
        (rli.RefundAmount * -1) AS Auctifera__Donated_Amount__c,
        CAST(refund_ft.CALCULATEDDATE AS DATE) AS Auctifera__Posted_Date__c,
        COALESCE(membership_so.ID, addon_so.ID, original_so.ID, payment_so.ID, refund_so.ID) AS vnfp__Opportunity_POS_Purchase__c,
        cimf.MembershipTransactionID AS cimf_mt_id,
        mt.ID AS mt_on_source
    FROM RefundLineItems rli
    INNER JOIN FINANCIALTRANSACTION refund_ft ON refund_ft.ID = rli.FinancialTransactionID
    LEFT JOIN REVENUESPLIT_EXT source_rse
        ON source_rse.ID = rli.SOURCELINEITEMID
       AND source_rse.APPLICATION IN ('Membership', 'Membership add-on')
    LEFT JOIN CreditItemMembershipFallback cimf
        ON cimf.LineItemID = rli.LineItemID AND cimf.MembershipRank = 1
    LEFT JOIN MEMBERSHIPTRANSACTION mt ON mt.REVENUESPLITID = rli.SOURCELINEITEMID
    LEFT JOIN MEMBERSHIPADDON ma ON ma.REVENUESPLITID = rli.SOURCELINEITEMID
    LEFT JOIN RecurringInstallments rgi
        ON rgi.InstallmentPaymentFinancialTransactionId = rli.OriginalPaymentTransactionId
    LEFT JOIN SALESORDERITEMMEMBERSHIP soim ON soim.MEMBERSHIPTRANSACTIONID = mt.ID
    LEFT JOIN SALESORDERITEMMEMBERSHIPADDON soima ON soima.MEMBERSHIPTRANSACTIONID = ma.MEMBERSHIPTRANSACTIONID
    LEFT JOIN SALESORDERITEM soi ON soi.ID = COALESCE(soim.ID, soima.ID)
    LEFT JOIN SALESORDER membership_so ON membership_so.ID = soi.SALESORDERID
    LEFT JOIN SALESORDER addon_so ON addon_so.ID = soi.SALESORDERID
    LEFT JOIN SALESORDER original_so ON original_so.REVENUEID = rli.OriginalPaymentTransactionId
    LEFT JOIN SalesOrdersByPayment sop ON sop.PAYMENTID = rli.OriginalPaymentTransactionId
    LEFT JOIN SALESORDER payment_so ON payment_so.ID = sop.SalesOrderID
    LEFT JOIN SALESORDER refund_so ON refund_so.REVENUEID = refund_ft.ID
    LEFT JOIN DirectMembershipOpportunityPerSalesOrder direct_order_membership
        ON direct_order_membership.SALESORDERID = COALESCE(membership_so.ID, addon_so.ID, original_so.ID, payment_so.ID, refund_so.ID)
       AND direct_order_membership.MembershipRank = 1
    LEFT JOIN OrderBackedMembershipPerSalesOrder order_membership
        ON order_membership.SALESORDERID = COALESCE(membership_so.ID, addon_so.ID, original_so.ID, payment_so.ID, refund_so.ID)
       AND order_membership.MembershipRank = 1
    WHERE
        COALESCE(rgi.RecurringInstallmentID, mt.ID, ma.MEMBERSHIPTRANSACTIONID,
                 direct_order_membership.MembershipTransactionID,
                 order_membership.OrderMembershipItemID,
                 cimf.MembershipTransactionID) IS NOT NULL
        AND (
            source_rse.APPLICATION IN ('Membership', 'Membership add-on')
            OR cimf.MembershipTransactionID IS NOT NULL
            OR mt.ID IS NOT NULL
            OR ma.MEMBERSHIPTRANSACTIONID IS NOT NULL
            OR rgi.RecurringInstallmentID IS NOT NULL
        )
        AND CAST(refund_ft.CALCULATEDDATE AS DATE) BETWEEN '2017-01-01' AND '2019-12-31'
),
Deduped AS (
    SELECT
        vnfp__Implementation_External_ID__c,
        Auctifera__Donated_Amount__c,
        Auctifera__Posted_Date__c,
        vnfp__Opportunity_POS_Purchase__c,
        cimf_mt_id,
        mt_on_source,
        ROW_NUMBER() OVER (
            PARTITION BY vnfp__Implementation_External_ID__c, Auctifera__Donated_Amount__c,
                         Auctifera__Posted_Date__c, vnfp__Opportunity_POS_Purchase__c
            ORDER BY vnfp__Implementation_External_ID__c
        ) AS DedupRank
    FROM RawRefundFundAssignments
)
SELECT
    COUNT(*) AS post_fix_rows,
    SUM(Auctifera__Donated_Amount__c) AS post_fix_total_amount,
    SUM(CASE WHEN vnfp__Opportunity_POS_Purchase__c IS NULL THEN 1 ELSE 0 END) AS rows_with_null_pos,
    SUM(CASE WHEN vnfp__Opportunity_POS_Purchase__c IS NULL THEN Auctifera__Donated_Amount__c ELSE 0 END) AS amount_with_null_pos,
    SUM(CASE WHEN vnfp__Opportunity_POS_Purchase__c IS NOT NULL THEN 1 ELSE 0 END) AS pre_fix_rows_so_backed,
    SUM(CASE WHEN vnfp__Opportunity_POS_Purchase__c IS NOT NULL THEN Auctifera__Donated_Amount__c ELSE 0 END) AS pre_fix_amount_so_backed
FROM Deduped WHERE DedupRank = 1;
