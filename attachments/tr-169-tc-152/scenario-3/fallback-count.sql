-- Count membership transactions with NO sales-order line -> these hit the fallback
-- (COALESCE falls back to mt.*) and are unaffected by the fix.
SELECT
    COUNT(*)                                                    AS total_mt,
    SUM(CASE WHEN soim.ID IS NULL     THEN 1 ELSE 0 END)         AS transaction_only_no_soim,
    SUM(CASE WHEN soim.ID IS NOT NULL THEN 1 ELSE 0 END)         AS order_anchored_with_soim
FROM MEMBERSHIPTRANSACTION mt
LEFT JOIN SALESORDERITEMMEMBERSHIP soim ON soim.MEMBERSHIPTRANSACTIONID = mt.ID;
