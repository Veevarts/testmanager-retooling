-- IM-560 TC-113 S1 · pinpoint the reported record (rev-10026520, 2026-02-02)
-- within the split-receipting donation cohort on aspen.
WITH SRD AS (
  SELECT
    dli.ID AS LineItemID,
    dli.TRANSACTIONAMOUNT AS Amount,
    mt.TRANSACTIONDATE AS MTDate,
    ROW_NUMBER() OVER (PARTITION BY dli.ID ORDER BY mt.TRANSACTIONDATE DESC, mt.ID DESC) AS rk
  FROM FINANCIALTRANSACTIONLINEITEM dli
  INNER JOIN REVENUESPLIT_EXT rse ON rse.ID = dli.ID AND rse.APPLICATION = 'Donation'
  INNER JOIN FINANCIALTRANSACTIONLINEITEM sml ON sml.ID = dli.SOURCELINEITEMID AND sml.[TYPE] = 'Standard'
  INNER JOIN REVENUESPLIT_EXT smrse ON smrse.ID = sml.ID AND smrse.APPLICATION = 'Membership'
  INNER JOIN MEMBERSHIPTRANSACTION mt ON mt.REVENUESPLITID = dli.SOURCELINEITEMID AND ISNULL(mt.ACTION,'') <> ('Dr'+'op')
  WHERE dli.[TYPE] = 'Standard'
)
SELECT
  COUNT(*) AS n_on_2026_02_02,
  CAST(SUM(Amount) AS DECIMAL(18,2)) AS sum_amount_that_day,
  CAST(MIN(MTDate) AS DATE) AS cohort_min_date,
  CAST(MAX(MTDate) AS DATE) AS cohort_max_date
FROM SRD
WHERE rk = 1 AND CAST(MTDate AS DATE) = '2026-02-02';
