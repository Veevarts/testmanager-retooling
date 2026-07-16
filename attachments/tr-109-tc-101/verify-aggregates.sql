-- QA verification query for IM-1005 / PR #145. Aggregates only — no PII, no rows.
-- Verifies dev-reported numbers: 79,713 sale-item join · 4,977 sale-items referencing
-- inactive variants · 234 distinct inactive variants owning those 4,977 sales ·
-- 267 total inactive variants across all shop products.

WITH sale_item_join AS (
    SELECT
        soim.ID AS sale_line_id,
        soim.MERCHANDISEPRODUCTINSTANCEID AS variant_id,
        pi.ID AS pi_id,
        pi.ISACTIVE AS variant_isactive,
        pi.MERCHANDISEPRODUCTID AS product_id
    FROM SALESORDERITEMMERCHANDISE soim
        LEFT JOIN MERCHANDISEPRODUCTINSTANCE pi ON pi.ID = soim.MERCHANDISEPRODUCTINSTANCEID
)
SELECT
    'total_sale_item_join'          AS metric,  COUNT(*) AS n FROM sale_item_join
UNION ALL
SELECT
    'sale_items_ref_inactive_variant',            COUNT(*) FROM sale_item_join WHERE variant_isactive = 0
UNION ALL
SELECT
    'distinct_inactive_variants_with_sales',      COUNT(DISTINCT variant_id) FROM sale_item_join WHERE variant_isactive = 0
UNION ALL
SELECT
    'distinct_inactive_products_with_sales',      COUNT(DISTINCT product_id) FROM sale_item_join WHERE variant_isactive = 0
UNION ALL
SELECT
    'variants_total_all_state',                   COUNT(*) FROM MERCHANDISEPRODUCTINSTANCE
UNION ALL
SELECT
    'variants_active_only',                       COUNT(*) FROM MERCHANDISEPRODUCTINSTANCE WHERE ISACTIVE = 1
UNION ALL
SELECT
    'variants_inactive_only',                     COUNT(*) FROM MERCHANDISEPRODUCTINSTANCE WHERE ISACTIVE = 0
UNION ALL
SELECT
    'sample_uuid_present_in_source',
    CASE WHEN EXISTS (SELECT 1 FROM MERCHANDISEPRODUCTINSTANCE WHERE UPPER(ID) = '3CF8166E-B2DF-41A6-B11C-CAB43A066AE0') THEN 1 ELSE 0 END
UNION ALL
SELECT
    'sample_uuid_isactive_flag',
    CAST((SELECT TOP 1 ISACTIVE FROM MERCHANDISEPRODUCTINSTANCE WHERE UPPER(ID) = '3CF8166E-B2DF-41A6-B11C-CAB43A066AE0') AS INT)
UNION ALL
SELECT
    'sample_uuid_sales_count',
    (SELECT COUNT(*) FROM SALESORDERITEMMERCHANDISE WHERE UPPER(MERCHANDISEPRODUCTINSTANCEID) = '3CF8166E-B2DF-41A6-B11C-CAB43A066AE0');
