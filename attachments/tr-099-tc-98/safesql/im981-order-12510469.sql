-- IM-981 verify Order #12510469 5 items transition from Refunded to non-Refunded.
WITH
per_item_flags AS (
    SELECT
        soi.ID AS SALESORDERITEMID,
        so.LOOKUPID AS OrderLookup,
        so.[STATUS] AS OrderStatus,
        soi.QUANTITY AS Quantity,
        soi.TOTAL AS Total,
        SUM(CAST(t.ISREFUNDED AS INT)) AS FlaggedRefundedQuantity,
        SUM(CASE WHEN t.ISREFUNDED = 1 AND t.STATUS = 'Canceled' THEN 1 ELSE 0 END) AS CanceledRefundedQuantity
    FROM SALESORDER so
    INNER JOIN SALESORDERITEM soi ON soi.SALESORDERID = so.ID
    INNER JOIN SALESORDERITEMTICKET soit ON soit.ID = soi.ID
    INNER JOIN TICKET t ON t.SALESORDERITEMTICKETID = soit.ID
    WHERE so.LOOKUPID = '8-12510469'
    GROUP BY soi.ID, so.LOOKUPID, so.[STATUS], soi.QUANTITY, soi.TOTAL
),
per_item_refund_summary AS (
    SELECT cie.SALESORDERITEMID, SUM(ftl.TRANSACTIONAMOUNT) AS RefundedAmount
    FROM CREDITITEM_EXT cie
    JOIN FINANCIALTRANSACTIONLINEITEM ftl ON ftl.ID = cie.ID
    JOIN FINANCIALTRANSACTION refundft ON refundft.ID = ftl.FINANCIALTRANSACTIONID
    WHERE refundft.[TYPE] = 'Refund' AND cie.SALESORDERITEMID IS NOT NULL
    GROUP BY cie.SALESORDERITEMID
)
SELECT
    p.OrderLookup,
    p.OrderStatus,
    p.Quantity,
    CAST(p.Total AS DECIMAL(18,2)) AS Total,
    p.FlaggedRefundedQuantity,
    p.CanceledRefundedQuantity,
    CAST(COALESCE(irs.RefundedAmount, 0) AS DECIMAL(18,2)) AS RefundedAmount,
    CASE WHEN p.FlaggedRefundedQuantity = p.Quantity THEN 'Refunded' ELSE 'Other' END AS pre_fix_status,
    CASE
      WHEN p.CanceledRefundedQuantity = p.Quantity THEN 'Refunded'
      WHEN p.FlaggedRefundedQuantity = p.Quantity
           AND p.Total > 0
           AND COALESCE(irs.RefundedAmount, 0) >= p.Total THEN 'Refunded'
      ELSE 'Other'
    END AS post_fix_status
FROM per_item_flags p
LEFT JOIN per_item_refund_summary irs ON irs.SALESORDERITEMID = p.SALESORDERITEMID
ORDER BY p.SALESORDERITEMID;
