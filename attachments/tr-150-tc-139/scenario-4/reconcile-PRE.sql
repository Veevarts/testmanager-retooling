

DECLARE @hasDateFilterFrom BIT = 0;
DECLARE @hasDateFilterTo   BIT = 0;
DECLARE @dateFilterFrom DATETIME2 = '1900-01-01';
DECLARE @dateFilterTo   DATETIME2 = '2100-12-31';
DECLARE @useDateFrom BIT = IIF(@hasDateFilterFrom = 1, 1, 0);
DECLARE @useDateTo BIT = IIF(@hasDateFilterTo = 1, 1, 0);
DECLARE @filterDateFrom DATE = CAST(@dateFilterFrom AS DATE);
DECLARE @filterDateTo DATE = CAST(@dateFilterTo AS DATE);

WITH Pledges AS (
SELECT
	ft.ID AS PledgeID,
	ft.CALCULATEDUSERDEFINEDID AS PledgeRevenueIdLegacy
FROM
	FINANCIALTRANSACTION ft
WHERE
	ft.[TYPE] = 'Pledge'
	
	
	
	OR EXISTS (SELECT 1 FROM REVENUEMATCHINGGIFT rmg WHERE rmg.ID = ft.ID AND rmg.ISACTIVE = 1)
),
PledgePaymentIds AS (
SELECT
    PledgeID,
    PaymentRevenueID AS PaymentID,
    CONCAT(CAST(PledgeID AS VARCHAR(36)), '-', CAST(PaymentRevenueID AS VARCHAR(36))) AS PledgePaymentExternalId
FROM (
    SELECT DISTINCT
        isplt.PLEDGEID,
        payFt.ID AS PaymentRevenueID
    FROM INSTALLMENTSPLITPAYMENT isp
    JOIN INSTALLMENTSPLIT isplt
      ON isplt.ID = isp.INSTALLMENTSPLITID
    JOIN FINANCIALTRANSACTIONLINEITEM payLi
      ON payLi.ID = isp.PAYMENTID
     AND payLi.[TYPE] = 'Standard'
    JOIN FINANCIALTRANSACTION payFt
      ON payFt.ID = payLi.FINANCIALTRANSACTIONID
) payment_ids
),
PledgeWriteOffIds AS (
SELECT
    PLEDGEID,
    WriteOffID,
    CONCAT(CAST(PLEDGEID AS VARCHAR(36)), '-', CAST(WriteOffID AS VARCHAR(36))) AS PledgeWriteOffExternalId
FROM (
    SELECT DISTINCT
        isplt.PLEDGEID,
        wFt.ID AS WriteOffID
    FROM INSTALLMENTSPLITWRITEOFF isw
    JOIN INSTALLMENTSPLIT isplt
      ON isplt.ID = isw.INSTALLMENTSPLITID
    JOIN FINANCIALTRANSACTION wFt
      ON wFt.ID = isw.WRITEOFFID
) writeoff_ids
),
Installments AS (
SELECT DISTINCT
	ins.ID AS InstallmentID,
	isplt.PLEDGEID AS PledgeID,
	ins.DATE AS InstallmentDate,
	ins.TRANSACTIONAMOUNT AS InstallmentAmount,
	ins.[SEQUENCE] AS InstallmentSequence
FROM INSTALLMENT ins
JOIN INSTALLMENTSPLIT isplt
  ON isplt.INSTALLMENTID = ins.ID
WHERE isplt.PLEDGEID IS NOT NULL
),
PaymentPerInstallment AS (
SELECT
	isplt.PLEDGEID,
	isplt.INSTALLMENTID,
	payFt.ID AS PaymentRevenueID,
	SUM(isp.AMOUNT) AS AppliedAmount,
	MIN(payFt.CALCULATEDDATE) AS PaymentDate,
	MAX(payFt.CALCULATEDUSERDEFINEDID) AS PaymentRevenueIdLegacy,
	MAX(payFt.DESCRIPTION) AS PaymentDescription,
	MAX(rpm.PAYMENTMETHOD) AS PaymentMethod,
	MAX(ccp.CREDITCARDPARTIALNUMBER) AS CardLast4,
	MAX(chk.CHECKNUMBER) AS CheckNumber,
	MIN(ins.DATE) AS InstallmentDate
FROM INSTALLMENTSPLITPAYMENT isp
JOIN INSTALLMENTSPLIT isplt
  ON isplt.ID = isp.INSTALLMENTSPLITID
JOIN INSTALLMENT ins
  ON ins.ID = isplt.INSTALLMENTID
JOIN FINANCIALTRANSACTIONLINEITEM payLi
  ON payLi.ID = isp.PAYMENTID
 AND payLi.[TYPE] = 'Standard'
JOIN FINANCIALTRANSACTION payFt
  ON payFt.ID = payLi.FINANCIALTRANSACTIONID
LEFT JOIN REVENUEPAYMENTMETHOD rpm
  ON rpm.REVENUEID = payFt.ID
LEFT JOIN CREDITCARDPAYMENTMETHODDETAIL ccp
  ON ccp.ID = rpm.ID
LEFT JOIN CHECKPAYMENTMETHODDETAIL chk
  ON chk.ID = rpm.ID
GROUP BY
	isplt.PLEDGEID,
	isplt.INSTALLMENTID,
	payFt.ID
),
PaymentAgg AS (
SELECT
    PLEDGEID,
    PaymentRevenueID AS PaymentID,
    SUM(AppliedAmount) AS AppliedAmount,
    MIN(PaymentDate) AS PaymentDate,
    MAX(PaymentRevenueIdLegacy) AS PaymentRevenueIdLegacy,
    MAX(PaymentDescription) AS PaymentDescription,
    MAX(PaymentMethod) AS PaymentMethod,
    MAX(CardLast4) AS CardLast4,
    MAX(CheckNumber) AS CheckNumber,
    MIN(InstallmentDate) AS InstallmentDate
FROM PaymentPerInstallment
GROUP BY
    PLEDGEID,
    PaymentRevenueID
),
PaymentTotals AS (
SELECT
    PLEDGEID,
    INSTALLMENTID,
    SUM(AppliedAmount) AS TotalApplied
FROM
    PaymentPerInstallment
GROUP BY
    PLEDGEID,
    INSTALLMENTID
),
WriteOffPerInstallment AS (
SELECT
	isplt.PLEDGEID,
	isplt.INSTALLMENTID,
	wFt.ID AS WriteOffID,
	MIN(wFt.CALCULATEDDATE) AS WriteOffDate,
	SUM(isw.AMOUNT) AS WrittenOffAmount,
	MIN(ins.DATE) AS InstallmentDate
FROM
	INSTALLMENTSPLITWRITEOFF isw
JOIN INSTALLMENTSPLIT isplt
        ON
	isplt.ID = isw.INSTALLMENTSPLITID
JOIN INSTALLMENT ins
        ON
	ins.ID = isplt.INSTALLMENTID
JOIN FINANCIALTRANSACTION wFt
        ON
	wFt.ID = isw.WRITEOFFID
GROUP BY
	isplt.PLEDGEID,
	isplt.INSTALLMENTID,
	wFT.ID
),
WriteOffAgg AS (
SELECT
	PLEDGEID,
	WriteOffID,
	MIN(WriteOffDate) AS WriteOffDate,
	SUM(WrittenOffAmount) AS WrittenOffAmount,
	MIN(InstallmentDate) AS InstallmentDate
FROM
	WriteOffPerInstallment
GROUP BY
	PLEDGEID,
	WriteOffID
),
WriteOffTotals AS (
SELECT
    PLEDGEID,
    INSTALLMENTID,
    SUM(WrittenOffAmount) AS TotalWrittenOff
FROM
    WriteOffPerInstallment
GROUP BY
    PLEDGEID,
    INSTALLMENTID
)
SELECT
  COUNT(*) AS total_rows,
  SUM(CASE WHEN q.npe01__Paid__c = 1 THEN 1 ELSE 0 END) AS paid_rows,
  SUM(CASE WHEN q.npe01__Paid__c = 0 AND q.npe01__Written_Off__c = 1 THEN 1 ELSE 0 END) AS writeoff_rows,
  SUM(CASE WHEN q.npe01__Paid__c = 0 AND q.npe01__Written_Off__c = 0 THEN 1 ELSE 0 END) AS unpaid_rows,
  SUM(CASE WHEN q.npe01__Scheduled_Date__c IS NULL THEN 1 ELSE 0 END) AS sched_null,
  SUM(CASE WHEN q.npe01__Payment_Date__c   IS NULL THEN 1 ELSE 0 END) AS pay_null,
  SUM(CASE WHEN q.npe01__Written_Off__c = 1 AND q.npe01__Payment_Date__c IS NULL THEN 1 ELSE 0 END) AS wo_pay_null,
  SUM(CASE WHEN q.npe01__Written_Off__c = 1 AND q.npe01__Payment_Date__c IS NOT NULL
                AND CAST(q.npe01__Payment_Date__c AS DATE) <> CAST(q.npe01__Scheduled_Date__c AS DATE)
           THEN 1 ELSE 0 END) AS wo_pay_differs_from_sched,
  SUM(CASE WHEN q.npe01__Paid__c = 0 AND q.npe01__Written_Off__c = 0 AND q.npe01__Payment_Date__c IS NULL
           THEN 1 ELSE 0 END) AS unpaid_pay_null
FROM (

SELECT
	paymentIds.PledgePaymentExternalId AS Implementation_External_ID__c,
	pa.PaymentRevenueIdLegacy AS Revenue_ID_legacy__c,
	pa.PLEDGEID AS npe01__Opportunity__c,
	1 AS npe01__Paid__c,
	pa.InstallmentDate AS npe01__Scheduled_Date__c,
	pa.PaymentDate AS npe01__Payment_Date__c,
	pa.AppliedAmount AS npe01__Payment_Amount__c,
	pa.AppliedAmount AS vnfp__Amount_Paid__c,
	pa.PaymentMethod AS npe01__Payment_Method__c,
	0 AS npe01__Written_Off__c,
	pa.CheckNumber AS npe01__Check_Reference_Number__c,
	NULL AS npsp__Card_Expiration_Month__c,
	NULL AS npsp__Card_Expiration_Year__c,
	pa.CardLast4 AS npsp__Card_Last_4__c,
	NULL AS npsp__Card_Network__c,
	NULL AS npsp__ACH_Last_4__c,
	NULL AS npsp__ACH_Code__c,
	pa.PaymentDescription AS vnfp__Description__c
FROM
	PaymentAgg pa
JOIN Pledges p
    ON p.PledgeID = pa.PLEDGEID
JOIN PledgePaymentIds paymentIds
    ON paymentIds.PledgeID = pa.PLEDGEID
    AND paymentIds.PaymentID = pa.PaymentID
UNION ALL

SELECT
	writeoffIds.PledgeWriteOffExternalId AS Implementation_External_ID__c,
	NULL AS Revenue_ID_legacy__c,
	wo.PLEDGEID AS npe01__Opportunity__c,
	0 AS npe01__Paid__c,
	wo.InstallmentDate AS npe01__Scheduled_Date__c,
	wo.WriteOffDate AS npe01__Payment_Date__c,
	wo.WrittenOffAmount AS npe01__Payment_Amount__c,
	0 AS vnfp__Amount_Paid__c,
	NULL AS npe01__Payment_Method__c,
	1 AS npe01__Written_Off__c,
	NULL AS npe01__Check_Reference_Number__c,	
	NULL AS npsp__Card_Expiration_Month__c,
	NULL AS npsp__Card_Expiration_Year__c,
	NULL AS npsp__Card_Last_4__c,
	NULL AS npsp__Card_Network__c,
	NULL AS npsp__ACH_Last_4__c,
	NULL AS npsp__ACH_Code__c,
	NULL AS vnfp__Description__c
FROM
	WriteOffAgg wo
JOIN Pledges pledges
    ON
	pledges.PledgeID = wo.PLEDGEID
JOIN PledgeWriteOffIds writeoffIds
    ON writeoffIds.PLEDGEID = wo.PLEDGEID
    AND writeoffIds.WriteOffID = wo.WriteOffID
UNION ALL

SELECT
	CONCAT(
        CAST(ins.PledgeID AS VARCHAR(36)),
        '-',
        CAST(ins.InstallmentID AS VARCHAR(36))
    ) AS Implementation_External_ID__c,
	NULL AS Revenue_ID_legacy__c,
	ins.PledgeID AS npe01__Opportunity__c,
	0 AS npe01__Paid__c,
	ins.InstallmentDate AS npe01__Scheduled_Date__c,
	NULL AS npe01__Payment_Date__c,
	ins.InstallmentAmount
        - COALESCE(pt.TotalApplied, 0)
        - COALESCE(wt.TotalWrittenOff, 0) AS npe01__Payment_Amount__c,
	0 AS vnfp__Amount_Paid__c,
	NULL AS npe01__Payment_Method__c,
	0 AS npe01__Written_Off__c,
	NULL AS npe01__Check_Reference_Number__c,
	NULL AS npsp__Card_Expiration_Month__c,
	NULL AS npsp__Card_Expiration_Year__c,
	NULL AS npsp__Card_Last_4__c,
	NULL AS npsp__Card_Network__c,
	NULL AS npsp__ACH_Last_4__c,
	NULL AS npsp__ACH_Code__c,
	NULL AS vnfp__Description__c
FROM
	Installments ins
JOIN Pledges pledges
    ON
	pledges.PledgeID = ins.PledgeID
LEFT JOIN PaymentTotals pt
    ON
	pt.PLEDGEID = ins.PledgeID
	AND pt.INSTALLMENTID = ins.InstallmentID
LEFT JOIN WriteOffTotals wt
    ON
	wt.PLEDGEID = ins.PledgeID
	AND wt.INSTALLMENTID = ins.InstallmentID
WHERE
	ins.InstallmentAmount
        - COALESCE(pt.TotalApplied, 0)
        - COALESCE(wt.TotalWrittenOff, 0) > 0
) q
WHERE
	(
		@useDateFrom = 0
		OR CAST(COALESCE(q.npe01__Payment_Date__c, q.npe01__Scheduled_Date__c) AS DATE) >= @filterDateFrom
	)
	AND (
		@useDateTo = 0
		OR CAST(COALESCE(q.npe01__Payment_Date__c, q.npe01__Scheduled_Date__c) AS DATE) <= @filterDateTo
	)
;
