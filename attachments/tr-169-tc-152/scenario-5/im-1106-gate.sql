-- IM-1106 gate: for every order-anchored MT, check that both PRE-fix and POST-fix key
-- resolves to a real MEMBERSHIPLEVELTERM row (term_owner_level + term).
-- The vnfp__Membership_Program__c key is: CAST(mlt.LEVELID) + '-' + CAST(mlt.ID)
-- PRE-fix: mlt is picked from mt.MEMBERSHIPLEVELTERMID
-- POST-fix: mlt is picked from COALESCE(soim.MEMBERSHIPLEVELTERMID, mt.*)
-- A dangling key means the mlt row doesn't exist -> lookup imports as N/A.

WITH mt_join AS (
    SELECT
        mt.ID AS mt_id,
        mt.MEMBERSHIPLEVELTERMID AS pre_term_id,
        COALESCE(soim.MEMBERSHIPLEVELTERMID, mt.MEMBERSHIPLEVELTERMID) AS post_term_id
    FROM MEMBERSHIPTRANSACTION mt
    INNER JOIN SALESORDERITEMMEMBERSHIP soim ON soim.MEMBERSHIPTRANSACTIONID = mt.ID
)
SELECT
    COUNT(*) AS total_order_anchored,
    SUM(CASE WHEN mlt_pre.ID IS NULL THEN 1 ELSE 0 END) AS pre_fix_dangling_term,
    SUM(CASE WHEN mlt_post.ID IS NULL THEN 1 ELSE 0 END) AS post_fix_dangling_term,
    -- Also check that mlt.LEVELID always resolves to a real MEMBERSHIPLEVEL (the term owner)
    SUM(CASE WHEN mlt_pre.ID IS NOT NULL AND ml_pre_owner.ID IS NULL THEN 1 ELSE 0 END) AS pre_fix_dangling_term_owner_level,
    SUM(CASE WHEN mlt_post.ID IS NOT NULL AND ml_post_owner.ID IS NULL THEN 1 ELSE 0 END) AS post_fix_dangling_term_owner_level
FROM mt_join
LEFT JOIN MEMBERSHIPLEVELTERM mlt_pre  ON mlt_pre.ID  = mt_join.pre_term_id
LEFT JOIN MEMBERSHIPLEVELTERM mlt_post ON mlt_post.ID = mt_join.post_term_id
LEFT JOIN MEMBERSHIPLEVEL ml_pre_owner  ON ml_pre_owner.ID  = mlt_pre.LEVELID
LEFT JOIN MEMBERSHIPLEVEL ml_post_owner ON ml_post_owner.ID = mlt_post.LEVELID;
