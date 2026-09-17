-- IM-1217 aggregate wrapper — quantify what the recurring donation fix changes.
-- Runs against any Altru profile.
-- Expected illinois_2 (dev PR body):
--   79 rows / 79 distinct external ids PRE = POST
--   installment periods PRE: 34 Annually; POST: 45 Monthly + 34 Yearly
--   installment frequency: 79 × 1 POST (never null)
--   recurring type: 79 × Open POST (43 Fixed / 36 Open PRE under ENDDATE gate)
--   planned installments: 79 × 0 POST

-- Structural probe of the source data (Altru side):
SELECT
    COUNT(DISTINCT rg.REVENUEID) AS total_recurring_gifts,
    SUM(CASE WHEN rs.FREQUENCYCODE = 0 THEN 1 ELSE 0 END) AS annually_pre_fix,
    SUM(CASE WHEN rs.FREQUENCYCODE = 3 THEN 1 ELSE 0 END) AS monthly_pre_fix,
    SUM(CASE WHEN rs.FREQUENCYCODE = 5 THEN 1 ELSE 0 END) AS single_installment_pre_fix,
    SUM(CASE WHEN rs.FREQUENCYCODE IN (0, 5) THEN 1 ELSE 0 END) AS would_map_yearly_post_fix,
    SUM(CASE WHEN rs.FREQUENCYCODE IN (1, 2, 3, 6) THEN 1 ELSE 0 END) AS would_map_monthly_post_fix,
    SUM(CASE WHEN rs.FREQUENCYCODE = 7 THEN 1 ELSE 0 END) AS would_map_1st_and_15th_post_fix,
    SUM(CASE WHEN rs.FREQUENCYCODE = 8 THEN 1 ELSE 0 END) AS would_map_weekly_post_fix,
    SUM(CASE WHEN rs.NUMBEROFINSTALLMENTS > 0 THEN 1 ELSE 0 END) AS fixed_by_altru_count,
    SUM(CASE WHEN rg.ENDDATE IS NOT NULL THEN 1 ELSE 0 END) AS end_date_pre_fix_would_be_fixed,
    SUM(CASE WHEN rg.ENDDATE IS NOT NULL AND (rs.NUMBEROFINSTALLMENTS IS NULL OR rs.NUMBEROFINSTALLMENTS = 0) THEN 1 ELSE 0 END) AS ended_but_open_by_altru
FROM FINANCIALTRANSACTION rg
LEFT JOIN REVENUESCHEDULE rs ON rs.REVENUEID = rg.ID
WHERE rg.[TYPE] = 'RecurringGift';
