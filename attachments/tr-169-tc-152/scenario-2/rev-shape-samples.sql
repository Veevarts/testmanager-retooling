-- 5 sample divergent transactions in tucson, illustrating the "Go to Membership drift" shape:
-- MT.LEVELID differs from SOIM.LEVELID -> pre-fix outputs mt_level, post-fix outputs soim_level.
-- Same shape as Long Island's rev-11546037 (Imagination vs Imagination Plus),
-- rev-11203390 (Basic Dual vs Basic Family), etc.
WITH divergent AS (
    SELECT
        mt.ID                       AS mt_id,
        ml_mt.NAME                  AS pre_fix_level,
        ml_soim.NAME                AS post_fix_level,
        mlt_mt.AMOUNT               AS pre_fix_price,
        mlt_soim.AMOUNT             AS post_fix_price,
        prog_mt.NAME                AS pre_fix_program,
        prog_soim.NAME              AS post_fix_program,
        ROW_NUMBER() OVER (ORDER BY mt.DATEADDED DESC) AS rn
    FROM MEMBERSHIPTRANSACTION mt
    INNER JOIN SALESORDERITEMMEMBERSHIP soim ON soim.MEMBERSHIPTRANSACTIONID = mt.ID
    LEFT JOIN MEMBERSHIPLEVEL ml_mt        ON ml_mt.ID     = mt.MEMBERSHIPLEVELID
    LEFT JOIN MEMBERSHIPLEVEL ml_soim      ON ml_soim.ID   = soim.MEMBERSHIPLEVELID
    LEFT JOIN MEMBERSHIPLEVELTERM mlt_mt   ON mlt_mt.ID    = mt.MEMBERSHIPLEVELTERMID
    LEFT JOIN MEMBERSHIPLEVELTERM mlt_soim ON mlt_soim.ID  = soim.MEMBERSHIPLEVELTERMID
    LEFT JOIN MEMBERSHIPPROGRAM prog_mt    ON prog_mt.ID   = ml_mt.MEMBERSHIPPROGRAMID
    LEFT JOIN MEMBERSHIPPROGRAM prog_soim  ON prog_soim.ID = ml_soim.MEMBERSHIPPROGRAMID
    WHERE mt.MEMBERSHIPLEVELID <> soim.MEMBERSHIPLEVELID
)
SELECT
    mt_id,
    pre_fix_level,
    post_fix_level,
    pre_fix_price,
    post_fix_price,
    pre_fix_program,
    post_fix_program
FROM divergent
WHERE rn <= 5;
