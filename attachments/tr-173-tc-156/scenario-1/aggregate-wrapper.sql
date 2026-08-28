-- IM-1206 aggregate wrapper — quantify what the anchor change moves.
-- Runs against any Altru profile. Expected Long Island (dev PR body):
--   CloseDate changes  : 33
--   Revenue ID moves    : 42,610 (42,573 payment→order + 37 blank→populated)
--   Grain              : Opp 97,047, FA 97,014, POS 51,482 PRE=POST

-- Structural probe of the mechanism: for each membership line, compare
-- (owning transaction date, id) vs (ranked transaction date, id).
WITH mli_pairs AS (
    SELECT
        mli.ID AS mli_id,
        ft_own.CALCULATEDDATE  AS own_date,
        ft_own.CALCULATEDUSERDEFINEDID AS own_rev_id,
        -- Ranked transaction (child preferred, same shape as resolver)
        (SELECT TOP 1 ft2.CALCULATEDDATE
         FROM FINANCIALTRANSACTIONLINEITEM cline
         JOIN FINANCIALTRANSACTION ft2 ON ft2.ID = cline.FINANCIALTRANSACTIONID
         WHERE cline.SOURCELINEITEMID = mli.ID OR cline.ID = mli.ID
         ORDER BY CASE WHEN cline.SOURCELINEITEMID = mli.ID THEN 0
                       WHEN cline.ID = mli.ID THEN 1 ELSE 2 END,
                  CASE WHEN ft2.[TYPE] = 'Refund' THEN 1 ELSE 0 END,
                  ft2.CALCULATEDDATE DESC) AS ranked_date,
        (SELECT TOP 1 ft2.CALCULATEDUSERDEFINEDID
         FROM FINANCIALTRANSACTIONLINEITEM cline
         JOIN FINANCIALTRANSACTION ft2 ON ft2.ID = cline.FINANCIALTRANSACTIONID
         WHERE cline.SOURCELINEITEMID = mli.ID OR cline.ID = mli.ID
         ORDER BY CASE WHEN cline.SOURCELINEITEMID = mli.ID THEN 0
                       WHEN cline.ID = mli.ID THEN 1 ELSE 2 END,
                  CASE WHEN ft2.[TYPE] = 'Refund' THEN 1 ELSE 0 END,
                  ft2.CALCULATEDDATE DESC) AS ranked_rev_id
    FROM FINANCIALTRANSACTIONLINEITEM mli
    JOIN FINANCIALTRANSACTION ft_own ON ft_own.ID = mli.FINANCIALTRANSACTIONID
    JOIN REVENUESPLIT_EXT rse ON rse.ID = mli.ID AND rse.APPLICATION = 'Membership'
    WHERE mli.[TYPE] = 'Standard'
)
SELECT
    COUNT(*)                                                                    AS total_membership_lines,
    SUM(CASE WHEN own_date <> ranked_date THEN 1 ELSE 0 END)                    AS date_diff_count,
    SUM(CASE WHEN own_rev_id <> ranked_rev_id THEN 1 ELSE 0 END)                AS rev_id_diff_count,
    SUM(CASE WHEN NULLIF(own_rev_id,'') IS NULL THEN 1 ELSE 0 END)              AS own_rev_id_blank,
    SUM(CASE WHEN NULLIF(ranked_rev_id,'') IS NULL THEN 1 ELSE 0 END)           AS ranked_rev_id_blank,
    SUM(CASE WHEN NULLIF(own_rev_id,'') IS NULL AND NULLIF(ranked_rev_id,'') IS NOT NULL THEN 1 ELSE 0 END) AS own_blank_ranked_populated,
    SUM(CASE WHEN NULLIF(own_rev_id,'') IS NOT NULL AND NULLIF(ranked_rev_id,'') IS NULL THEN 1 ELSE 0 END) AS own_populated_ranked_blank
FROM mli_pairs;
