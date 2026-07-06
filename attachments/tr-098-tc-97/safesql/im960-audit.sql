-- IM-960 pre-fix vs post-fix audit for donation refund fund assignments.
-- Pre-fix: vnfp__Opportunity__c = CREDITPAYMENT.REVENUEID (payment FT id)
-- Post-fix: vnfp__Opportunity__c = source_dli.FINANCIALTRANSACTIONID (donation/order FT id)
-- We check both interpretations for the same refund line item universe
-- and classify each resulting id as Payment vs Order (donation opportunity).

WITH
MembershipLineItems AS (
    SELECT mli.ID AS MembershipLineItemID
    FROM FINANCIALTRANSACTIONLINEITEM mli
    INNER JOIN REVENUESPLIT_EXT rse ON rse.ID = mli.ID
    WHERE rse.APPLICATION = 'Membership' AND mli.[TYPE] = 'Standard'
),
CreditPaymentPerRefundOld AS (
    -- pre-fix used MIN(REVENUEID) per CREDITID
    SELECT CREDITID, MIN(REVENUEID) AS OriginalPaymentTransactionId
    FROM CREDITPAYMENT
    GROUP BY CREDITID
),
CreditPaymentPerRefundNew AS (
    -- post-fix collapses to CREDITID only (join used to filter, not to fan out)
    SELECT DISTINCT CREDITID FROM CREDITPAYMENT
),
RefundLineItems AS (
    SELECT
        refund_ft.ID AS FinancialTransactionID,
        rli.ID AS LineItemID,
        rli.TRANSACTIONAMOUNT AS RefundAmount,
        rli.SOURCELINEITEMID,
        cp_old.OriginalPaymentTransactionId AS pre_fix_key,
        source_dli.FINANCIALTRANSACTIONID AS post_fix_key
    FROM FINANCIALTRANSACTIONLINEITEM rli
    INNER JOIN FINANCIALTRANSACTION refund_ft
        ON refund_ft.ID = rli.FINANCIALTRANSACTIONID
       AND refund_ft.[TYPE] = 'Refund'
    LEFT JOIN CreditPaymentPerRefundOld cp_old ON cp_old.CREDITID = refund_ft.ID
    INNER JOIN CreditPaymentPerRefundNew cp_new ON cp_new.CREDITID = refund_ft.ID
    INNER JOIN FINANCIALTRANSACTIONLINEITEM source_dli ON source_dli.ID = rli.SOURCELINEITEMID
    LEFT JOIN MembershipLineItems mli ON mli.MembershipLineItemID = rli.SOURCELINEITEMID
    WHERE rli.[TYPE] = 'Standard'
      AND rli.SOURCELINEITEMID IS NOT NULL
      AND mli.MembershipLineItemID IS NULL
)
SELECT
    COUNT(*) AS total_refund_rows,
    SUM(CASE WHEN pre_fix_key <> post_fix_key THEN 1 ELSE 0 END) AS rows_where_key_changes,
    SUM(CASE WHEN pre_fix_key = post_fix_key THEN 1 ELSE 0 END) AS rows_where_key_same,
    -- Classify pre-fix key
    SUM(CASE WHEN pre_ft.[TYPE] = 'Payment' THEN 1 ELSE 0 END) AS pre_fix_is_payment,
    SUM(CASE WHEN pre_ft.[TYPE] = 'Order' THEN 1 ELSE 0 END) AS pre_fix_is_order,
    SUM(CASE WHEN pre_ft.[TYPE] IS NULL THEN 1 ELSE 0 END) AS pre_fix_ft_not_found,
    -- Classify post-fix key
    SUM(CASE WHEN post_ft.[TYPE] = 'Payment' THEN 1 ELSE 0 END) AS post_fix_is_payment,
    SUM(CASE WHEN post_ft.[TYPE] = 'Order' THEN 1 ELSE 0 END) AS post_fix_is_order,
    SUM(CASE WHEN post_ft.[TYPE] IS NULL THEN 1 ELSE 0 END) AS post_fix_ft_not_found,
    -- LookUp/POS Purchase resolution: does the source line's FT have a SALESORDER?
    SUM(CASE WHEN post_so.ID IS NOT NULL THEN 1 ELSE 0 END) AS post_fix_has_original_so,
    SUM(CASE WHEN pre_so.ID IS NOT NULL THEN 1 ELSE 0 END) AS pre_fix_has_original_so
FROM RefundLineItems rli
LEFT JOIN FINANCIALTRANSACTION pre_ft ON pre_ft.ID = rli.pre_fix_key
LEFT JOIN FINANCIALTRANSACTION post_ft ON post_ft.ID = rli.post_fix_key
LEFT JOIN SALESORDER pre_so ON pre_so.REVENUEID = rli.pre_fix_key
LEFT JOIN SALESORDER post_so ON post_so.REVENUEID = rli.post_fix_key;
