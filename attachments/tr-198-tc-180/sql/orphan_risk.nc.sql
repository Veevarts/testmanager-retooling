WITH ActiveClaims AS (
    SELECT rmg.ID AS ClaimId
    FROM REVENUEMATCHINGGIFT rmg
    WHERE rmg.ISACTIVE = 1
),
Inst AS (
    SELECT
        isplt.PLEDGEID           AS ClaimId,
        ins.ID                   AS InstallmentId,
        ins.TRANSACTIONAMOUNT    AS InstallmentAmount
    FROM INSTALLMENTSPLIT isplt
    INNER JOIN INSTALLMENT ins ON ins.ID = isplt.INSTALLMENTID
    INNER JOIN ActiveClaims ac ON ac.ClaimId = isplt.PLEDGEID
),
Paid AS (
    SELECT isplt.PLEDGEID AS ClaimId, SUM(isp.AMOUNT) AS PaidAmount
    FROM INSTALLMENTSPLITPAYMENT isp
    INNER JOIN INSTALLMENTSPLIT isplt ON isplt.ID = isp.INSTALLMENTSPLITID
    INNER JOIN ActiveClaims ac ON ac.ClaimId = isplt.PLEDGEID
    GROUP BY isplt.PLEDGEID
),
Woff AS (
    SELECT isplt.PLEDGEID AS ClaimId, SUM(isw.AMOUNT) AS WrittenOffAmount
    FROM INSTALLMENTSPLITWRITEOFF isw
    INNER JOIN INSTALLMENTSPLIT isplt ON isplt.ID = isw.INSTALLMENTSPLITID
    INNER JOIN ActiveClaims ac ON ac.ClaimId = isplt.PLEDGEID
    GROUP BY isplt.PLEDGEID
),
PerClaim AS (
    SELECT
        ac.ClaimId,
        ISNULL((SELECT SUM(i.InstallmentAmount) FROM Inst i WHERE i.ClaimId = ac.ClaimId), 0) AS InstallmentAmount,
        ISNULL((SELECT p.PaidAmount FROM Paid p WHERE p.ClaimId = ac.ClaimId), 0)             AS PaidAmount,
        ISNULL((SELECT w.WrittenOffAmount FROM Woff w WHERE w.ClaimId = ac.ClaimId), 0)       AS WrittenOffAmount,
        ISNULL((SELECT SUM(CASE WHEN li.[TYPE] = 'Reversal' THEN -li.TRANSACTIONAMOUNT ELSE li.TRANSACTIONAMOUNT END)
                FROM FINANCIALTRANSACTIONLINEITEM li
                WHERE li.FINANCIALTRANSACTIONID = ac.ClaimId
                  AND li.[TYPE] IN ('Standard', 'Reversal')), 0)                              AS ClaimNetAmount
    FROM ActiveClaims ac
)
SELECT
    COUNT(*)                                                                      AS ActiveClaims,
    SUM(CASE WHEN ClaimNetAmount = 0 THEN 1 ELSE 0 END)                           AS NetsToZero,
    SUM(CASE WHEN ClaimNetAmount = 0
              AND (InstallmentAmount - PaidAmount - WrittenOffAmount) > 0
             THEN 1 ELSE 0 END)                                                   AS OrphanRiskPopulation,
    SUM(CASE WHEN ClaimNetAmount = 0 THEN InstallmentAmount - PaidAmount - WrittenOffAmount ELSE 0 END)
                                                                                  AS ZeroNetRemainingTotal
FROM PerClaim;
