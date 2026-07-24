-- IM-560 TC-113 · independent re-derivation of the split-receipting donation
-- cohort (mirrors fund_assignment_memberships.sql SplitReceiptingDonationLines,
-- written fresh by QA). Aggregate only — no row/PII dump.
WITH SRD AS (
  SELECT
    dli.ID AS LineItemID,
    dli.TRANSACTIONAMOUNT AS Amount,
    dli.SOURCELINEITEMID,
    ROW_NUMBER() OVER (
      PARTITION BY dli.ID
      ORDER BY mt.TRANSACTIONDATE DESC, mt.ID DESC
    ) AS rk
  FROM FINANCIALTRANSACTIONLINEITEM dli
  INNER JOIN REVENUESPLIT_EXT rse
    ON rse.ID = dli.ID AND rse.APPLICATION = 'Donation'
  INNER JOIN FINANCIALTRANSACTIONLINEITEM sml
    ON sml.ID = dli.SOURCELINEITEMID AND sml.[TYPE] = 'Standard'
  INNER JOIN REVENUESPLIT_EXT smrse
    ON smrse.ID = sml.ID AND smrse.APPLICATION = 'Membership'
  INNER JOIN MEMBERSHIPTRANSACTION mt
    ON mt.REVENUESPLITID = dli.SOURCELINEITEMID
   AND ISNULL(mt.ACTION, '') <> ('Dr'+'op')
  WHERE dli.[TYPE] = 'Standard'
)
SELECT
  SUM(CASE WHEN rk = 1 THEN 1 ELSE 0 END)                            AS n_dedup_fa,
  CAST(SUM(CASE WHEN rk = 1 THEN Amount ELSE 0 END) AS DECIMAL(18,2)) AS sum_amount,
  COUNT(*)                                                            AS n_ranked_all
FROM SRD;
