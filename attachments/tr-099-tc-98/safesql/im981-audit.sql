-- IM-981 pre-fix vs post-fix ticket_item_program audit.
-- Pre-fix: an item is Refunded when RefundedQuantity (SUM ISREFUNDED) == QUANTITY.
-- Post-fix: an item is Refunded when
--   (all tickets both flagged AND canceled) OR
--   (all tickets flagged AND net paid > 0 AND refunded amount >= net paid)
--
-- Aggregate over all salesorderitems with ticket line items.

WITH
per_item_flags AS (
    SELECT
        soi.ID AS SALESORDERITEMID,
        soi.QUANTITY AS Quantity,
        soi.TOTAL AS Total,
        SUM(CAST(t.ISREFUNDED AS INT)) AS FlaggedRefundedQuantity,
        SUM(CASE WHEN t.ISREFUNDED = 1 AND t.STATUS = 'Canceled' THEN 1 ELSE 0 END) AS CanceledRefundedQuantity
    FROM SALESORDERITEM soi
    INNER JOIN SALESORDERITEMTICKET soit ON soit.ID = soi.ID
    INNER JOIN TICKET t ON t.SALESORDERITEMTICKETID = soit.ID
    GROUP BY soi.ID, soi.QUANTITY, soi.TOTAL
),
per_item_refund_summary AS (
    SELECT
        cie.SALESORDERITEMID,
        SUM(ftl.TRANSACTIONAMOUNT) AS RefundedAmount
    FROM CREDITITEM_EXT cie
    JOIN FINANCIALTRANSACTIONLINEITEM ftl ON ftl.ID = cie.ID
    JOIN FINANCIALTRANSACTION refundft ON refundft.ID = ftl.FINANCIALTRANSACTIONID
    WHERE refundft.[TYPE] = 'Refund' AND cie.SALESORDERITEMID IS NOT NULL
    GROUP BY cie.SALESORDERITEMID
),
combined AS (
    SELECT
        p.SALESORDERITEMID,
        p.Quantity,
        p.Total,
        p.FlaggedRefundedQuantity,
        p.CanceledRefundedQuantity,
        COALESCE(irs.RefundedAmount, 0) AS RefundedAmount,
        -- pre-fix rule: RefundedQuantity (raw flag) == Quantity
        CASE WHEN p.FlaggedRefundedQuantity = p.Quantity THEN 1 ELSE 0 END AS pre_fix_refunded,
        -- post-fix rule: canceled-all OR flagged-all + total>0 + refunded>=total (discount omitted; stricter bound)
        CASE
          WHEN p.CanceledRefundedQuantity = p.Quantity THEN 1
          WHEN p.FlaggedRefundedQuantity = p.Quantity
               AND p.Total > 0
               AND COALESCE(irs.RefundedAmount, 0) >= p.Total
            THEN 1
          ELSE 0
        END AS post_fix_refunded
    FROM per_item_flags p
    LEFT JOIN per_item_refund_summary irs ON irs.SALESORDERITEMID = p.SALESORDERITEMID
)
SELECT
    COUNT(*) AS total_items,
    SUM(pre_fix_refunded) AS pre_fix_refunded_count,
    SUM(post_fix_refunded) AS post_fix_refunded_count,
    SUM(CASE WHEN pre_fix_refunded = 1 AND post_fix_refunded = 1 THEN 1 ELSE 0 END) AS kept_refunded,
    SUM(CASE WHEN pre_fix_refunded = 1 AND post_fix_refunded = 0 THEN 1 ELSE 0 END) AS flipped_off,
    SUM(CASE WHEN pre_fix_refunded = 0 AND post_fix_refunded = 1 THEN 1 ELSE 0 END) AS new_refunded,
    SUM(CASE WHEN pre_fix_refunded = 0 AND post_fix_refunded = 0 THEN 1 ELSE 0 END) AS never_refunded
FROM combined;
