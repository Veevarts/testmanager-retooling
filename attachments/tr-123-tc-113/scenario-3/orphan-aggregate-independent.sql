-- IM-560 TC-113 S3 · donation-on-membership-line splits partitioned into
-- split-receipting (active MT) vs ORPHAN (no active MT). Aggregate only, no PII.
WITH DonationOnMembershipLine AS (
  SELECT
    dli.ID AS LineItemID,
    dli.TRANSACTIONAMOUNT AS Amount,
    CASE WHEN EXISTS (
      SELECT 1 FROM MEMBERSHIPTRANSACTION mt
      WHERE mt.REVENUESPLITID = dli.SOURCELINEITEMID AND ISNULL(mt.ACTION,'') <> ('Dr'+'op')
    ) THEN 1 ELSE 0 END AS HasMT
  FROM FINANCIALTRANSACTIONLINEITEM dli
  INNER JOIN REVENUESPLIT_EXT rse  ON rse.ID = dli.ID AND rse.APPLICATION = 'Donation'
  INNER JOIN FINANCIALTRANSACTIONLINEITEM sml ON sml.ID = dli.SOURCELINEITEMID AND sml.[TYPE] = 'Standard'
  INNER JOIN REVENUESPLIT_EXT smrse ON smrse.ID = sml.ID AND smrse.APPLICATION = 'Membership'
  WHERE dli.[TYPE] = 'Standard'
)
SELECT
  COUNT(*)                                                        AS total_donation_on_membership_line,
  SUM(HasMT)                                                      AS split_receipting_mt_backed,
  SUM(1 - HasMT)                                                  AS orphans_no_mt,
  CAST(SUM(CASE WHEN HasMT = 0 THEN Amount ELSE 0 END) AS DECIMAL(18,2)) AS orphans_sum
FROM DonationOnMembershipLine;
