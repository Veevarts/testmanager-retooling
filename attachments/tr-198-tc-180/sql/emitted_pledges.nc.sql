;WITH GiftInKindPledgeTransactions AS (
    SELECT DISTINCT
        ft_direct.ID AS PledgeFinancialTransactionID
    FROM REVENUEPAYMENTMETHOD rpm_direct
    JOIN GIFTINKINDPAYMENTMETHODDETAIL gik_direct
      ON gik_direct.ID = rpm_direct.ID
    JOIN FINANCIALTRANSACTION ft_direct
      ON ft_direct.ID = rpm_direct.REVENUEID
     AND ft_direct.TYPECODE = 1
    UNION
    SELECT DISTINCT
        ft_pledge.ID AS PledgeFinancialTransactionID
    FROM REVENUEPAYMENTMETHOD rpm_payment
    JOIN GIFTINKINDPAYMENTMETHODDETAIL gik_payment
      ON gik_payment.ID = rpm_payment.ID
    JOIN FINANCIALTRANSACTIONLINEITEM payment_line
      ON payment_line.FINANCIALTRANSACTIONID = rpm_payment.REVENUEID
     AND payment_line.[TYPE] IN ('Standard', 'Reversal')
    JOIN FINANCIALTRANSACTIONLINEITEM source_pledge_line
      ON source_pledge_line.ID = payment_line.SOURCELINEITEMID
    JOIN FINANCIALTRANSACTION ft_pledge
      ON ft_pledge.ID = source_pledge_line.FINANCIALTRANSACTIONID
     AND ft_pledge.TYPECODE = 1
),
StockPledgeTransactions AS (
    SELECT DISTINCT
        ft_direct.ID AS PledgeFinancialTransactionID
    FROM REVENUEPAYMENTMETHOD rpm_direct
    JOIN STOCKDETAIL stock_direct
      ON stock_direct.ID = rpm_direct.ID
    JOIN FINANCIALTRANSACTION ft_direct
      ON ft_direct.ID = rpm_direct.REVENUEID
     AND ft_direct.TYPECODE = 1
    UNION
    SELECT DISTINCT
        ft_pledge.ID AS PledgeFinancialTransactionID
    FROM REVENUEPAYMENTMETHOD rpm_payment
    JOIN STOCKDETAIL stock_payment
      ON stock_payment.ID = rpm_payment.ID
    JOIN FINANCIALTRANSACTIONLINEITEM payment_line
      ON payment_line.FINANCIALTRANSACTIONID = rpm_payment.REVENUEID
     AND payment_line.[TYPE] IN ('Standard', 'Reversal')
    JOIN FINANCIALTRANSACTIONLINEITEM source_pledge_line
      ON source_pledge_line.ID = payment_line.SOURCELINEITEMID
    JOIN FINANCIALTRANSACTION ft_pledge
      ON ft_pledge.ID = source_pledge_line.FINANCIALTRANSACTIONID
     AND ft_pledge.TYPECODE = 1
),
PropertyPledgeTransactions AS (
    SELECT DISTINCT
        ft_direct.ID AS PledgeFinancialTransactionID
    FROM REVENUEPAYMENTMETHOD rpm_direct
    JOIN PROPERTYDETAIL property_direct
      ON property_direct.ID = rpm_direct.ID
    JOIN FINANCIALTRANSACTION ft_direct
      ON ft_direct.ID = rpm_direct.REVENUEID
     AND ft_direct.TYPECODE = 1
    UNION
    SELECT DISTINCT
        ft_pledge.ID AS PledgeFinancialTransactionID
    FROM REVENUEPAYMENTMETHOD rpm_payment
    JOIN PROPERTYDETAIL property_payment
      ON property_payment.ID = rpm_payment.ID
    JOIN FINANCIALTRANSACTIONLINEITEM payment_line
      ON payment_line.FINANCIALTRANSACTIONID = rpm_payment.REVENUEID
     AND payment_line.[TYPE] IN ('Standard', 'Reversal')
    JOIN FINANCIALTRANSACTIONLINEITEM source_pledge_line
      ON source_pledge_line.ID = payment_line.SOURCELINEITEMID
    JOIN FINANCIALTRANSACTION ft_pledge
      ON ft_pledge.ID = source_pledge_line.FINANCIALTRANSACTIONID
     AND ft_pledge.TYPECODE = 1
),
PledgeInstallmentSplits AS (
    SELECT
        isplt.ID AS InstallmentSplitID,
        isplt.PLEDGEID AS PledgeID,
        COALESCE(isplt.TRANSACTIONAMOUNT, isplt.AMOUNT, 0) AS ScheduledAmount
    FROM INSTALLMENTSPLIT isplt
    WHERE isplt.PLEDGEID IS NOT NULL
),
PledgePaidBySplit AS (
    SELECT
        isplt.ID AS InstallmentSplitID,
        SUM(COALESCE(isp.AMOUNT, 0)) AS PaidAmount
    FROM INSTALLMENTSPLITPAYMENT isp
    JOIN INSTALLMENTSPLIT isplt
      ON isplt.ID = isp.INSTALLMENTSPLITID
    GROUP BY isplt.ID
),
PledgeWrittenOffBySplit AS (
    SELECT
        isplt.ID AS InstallmentSplitID,
        SUM(COALESCE(isw.AMOUNT, 0)) AS WrittenOffAmount
    FROM INSTALLMENTSPLITWRITEOFF isw
    JOIN INSTALLMENTSPLIT isplt
      ON isplt.ID = isw.INSTALLMENTSPLITID
    GROUP BY isplt.ID
),
PledgePaymentState AS (
    SELECT
        splits.PledgeID,
        COUNT(splits.InstallmentSplitID) AS InstallmentSplitCount,
        SUM(splits.ScheduledAmount) AS ScheduledAmount,
        SUM(COALESCE(paid.PaidAmount, 0)) AS PaidAmount,
        SUM(COALESCE(written_off.WrittenOffAmount, 0)) AS WrittenOffAmount,
        SUM(
            splits.ScheduledAmount
            - COALESCE(paid.PaidAmount, 0)
            - COALESCE(written_off.WrittenOffAmount, 0)
        ) AS RemainingAmount
    FROM PledgeInstallmentSplits splits
    LEFT JOIN PledgePaidBySplit paid
      ON paid.InstallmentSplitID = splits.InstallmentSplitID
    LEFT JOIN PledgeWrittenOffBySplit written_off
      ON written_off.InstallmentSplitID = splits.InstallmentSplitID
    GROUP BY splits.PledgeID
)
SELECT DISTINCT
    CAST(ft.ID AS VARCHAR(36)) AS OpportunityExternalId
FROM
    FINANCIALTRANSACTION ft
LEFT JOIN REVENUE_EXT re
    ON re.ID = ft.ID
LEFT JOIN SALESORDER so
    ON so.REVENUEID = ft.ID
LEFT JOIN CONSTITUENT c
    ON c.ID = ft.CONSTITUENTID
LEFT JOIN CONSTITUENTHOUSEHOLD chh
    ON c.ID = chh.ID
LEFT JOIN GiftInKindPledgeTransactions gift_in_kind_pledge
    ON gift_in_kind_pledge.PledgeFinancialTransactionID = ft.ID
LEFT JOIN StockPledgeTransactions stock_pledge
    ON stock_pledge.PledgeFinancialTransactionID = ft.ID
LEFT JOIN PropertyPledgeTransactions property_pledge
    ON property_pledge.PledgeFinancialTransactionID = ft.ID
LEFT JOIN PledgePaymentState pledge_payment_state
    ON pledge_payment_state.PledgeID = ft.ID
WHERE ft.[TYPE] = 'Pledge'
