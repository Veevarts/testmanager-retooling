-- IM-1204 aggregate wrapper: revert-proof numeric check of the divergent population
-- and the delta each of the 4 corrected columns would receive if the SQL fix were applied.
-- Contract: numeric-only, safesql-safe, read-only. Runs against ANY Altru profile.
-- Matches the shape of dev's evidence table.

WITH order_anchored AS (
    -- Every membership transaction with a sales-order line (soim is 1:1 per mt)
    SELECT
        mt.ID                                        AS mt_id,
        mt.MEMBERSHIPLEVELID                         AS mt_level_id,
        mt.MEMBERSHIPLEVELTERMID                     AS mt_term_id,
        soim.MEMBERSHIPLEVELID                       AS soim_level_id,
        soim.MEMBERSHIPLEVELTERMID                   AS soim_term_id,
        ml_mt.NAME                                   AS mt_level_name,
        ml_soim.NAME                                 AS soim_level_name,
        mlt_mt.LEVELID                               AS mt_program_key_lvl,
        mlt_soim.LEVELID                             AS soim_program_key_lvl,
        prog_mt.NAME                                 AS mt_program_name,
        prog_soim.NAME                               AS soim_program_name,
        mlt_mt.AMOUNT                                 AS mt_term_price,
        mlt_soim.AMOUNT                               AS soim_term_price
    FROM MEMBERSHIPTRANSACTION mt
    INNER JOIN SALESORDERITEMMEMBERSHIP soim ON soim.MEMBERSHIPTRANSACTIONID = mt.ID
    LEFT JOIN MEMBERSHIPLEVEL ml_mt        ON ml_mt.ID     = mt.MEMBERSHIPLEVELID
    LEFT JOIN MEMBERSHIPLEVEL ml_soim      ON ml_soim.ID   = soim.MEMBERSHIPLEVELID
    LEFT JOIN MEMBERSHIPLEVELTERM mlt_mt   ON mlt_mt.ID    = mt.MEMBERSHIPLEVELTERMID
    LEFT JOIN MEMBERSHIPLEVELTERM mlt_soim ON mlt_soim.ID  = soim.MEMBERSHIPLEVELTERMID
    LEFT JOIN MEMBERSHIPPROGRAM prog_mt    ON prog_mt.ID   = ml_mt.MEMBERSHIPPROGRAMID
    LEFT JOIN MEMBERSHIPPROGRAM prog_soim  ON prog_soim.ID = ml_soim.MEMBERSHIPPROGRAMID
)
SELECT
    -- Totals
    COUNT(*)                                                                          AS order_anchored_txns,
    -- Any divergence in level or term id
    SUM(CASE WHEN mt_level_id <> soim_level_id OR mt_term_id <> soim_term_id THEN 1 ELSE 0 END) AS any_divergent,
    SUM(CASE WHEN mt_level_id <> soim_level_id THEN 1 ELSE 0 END)                     AS level_divergent,
    SUM(CASE WHEN mt_term_id  <> soim_term_id  THEN 1 ELSE 0 END)                     AS term_divergent,
    -- Impact on output columns (any of the 4 corrected columns changes)
    SUM(CASE WHEN mt_program_key_lvl <> soim_program_key_lvl OR mt_term_id <> soim_term_id THEN 1 ELSE 0 END) AS program_key_changed,
    SUM(CASE WHEN mt_level_name <> soim_level_name THEN 1 ELSE 0 END)                 AS level_name_changed,
    SUM(CASE WHEN mt_term_price <> soim_term_price THEN 1 ELSE 0 END)                 AS term_price_changed,
    SUM(CASE WHEN mt_program_name <> soim_program_name THEN 1 ELSE 0 END)             AS program_name_changed,
    -- Grain check (must equal order_anchored_txns for 1:1)
    COUNT(DISTINCT mt_id)                                                             AS distinct_mt_ids
FROM order_anchored;
