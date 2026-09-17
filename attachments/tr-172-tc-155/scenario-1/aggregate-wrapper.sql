-- IM-1212 aggregate wrapper: quantify unpaid rows recovered by the windowing fix.
-- Runs against any Altru profile.
-- Expected illinois_2 (dev PR body): PRE 0 / POST 141 unpaid rows in a 2026 window.
--
-- The wrapper uses the same 3-CTE structure as the query but only counts.
-- To be run PRE-fix and POST-fix separately, with windowed params:
--   @useDateFrom = 1, @filterDateFrom = '2026-01-01'
--   @useDateTo   = 1, @filterDateTo   = '2026-12-31'
--
-- What to count:
--   1. Total emitted rows
--   2. Unpaid rows (Auctifera__Posted_Date__c IS NULL)
--   3. Paid rows (Auctifera__Posted_Date__c IS NOT NULL)
-- 
-- Expected outcome:
--   PRE-fix  windowed: rows_unpaid = 0 (all dropped by NULL >= @dateFrom = UNKNOWN)
--   POST-fix windowed: rows_unpaid = 141 in Illinois 2026 window
--   Both variants unwindowed produce identical total row counts (fix only affects windowed).

-- Simple structural test — enumerate installments where the installment date falls in the
-- window but no payment/writeoff has posted yet:
DECLARE @filterDateFrom DATE = '2026-01-01';
DECLARE @filterDateTo DATE = '2026-12-31';

SELECT
    COUNT(*) AS total_unpaid_installments_in_window,
    SUM(CASE WHEN isplt.TRANSACTIONAMOUNT > 0 THEN 1 ELSE 0 END) AS with_amount_gt_zero
FROM INSTALLMENTSPLIT isplt
JOIN INSTALLMENT ins ON ins.ID = isplt.INSTALLMENTID
LEFT JOIN INSTALLMENTSPLITPAYMENT isp ON isp.INSTALLMENTSPLITID = isplt.ID
LEFT JOIN INSTALLMENTSPLITWRITEOFF isw ON isw.INSTALLMENTSPLITID = isplt.ID
WHERE ins.[DATE] >= @filterDateFrom
  AND ins.[DATE] <= @filterDateTo
  AND isp.ID IS NULL
  AND isw.ID IS NULL;
