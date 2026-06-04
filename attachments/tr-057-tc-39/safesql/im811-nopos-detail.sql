-- List the 2 non-POS refunds the fix recovers in 2017-2019 with constituent lookup id.
WITH
CreditPaymentPerRefund AS (
    SELECT CREDITID, REVENUEID AS OriginalPaymentTransactionId FROM CREDITPAYMENT
),
SalesOrdersByPayment AS (
    SELECT sop.PAYMENTID, MIN(sop.SALESORDERID) AS SalesOrderID
    FROM SALESORDERPAYMENT sop GROUP BY sop.PAYMENTID
),
RecurringInstallments AS (
    SELECT rgi.ID AS RecurringInstallmentID,
           rgp.PAYMENTID AS InstallmentPaymentFinancialTransactionId
    FROM RECURRINGGIFTINSTALLMENT rgi
    LEFT JOIN RECURRINGGIFTINSTALLMENTPAYMENT rgp ON rgp.RECURRINGGIFTINSTALLMENTID = rgi.ID
),
RefundLineItems AS (
    SELECT refund_ft.ID AS FinancialTransactionID, rli.ID AS LineItemID,
           rli.TRANSACTIONAMOUNT AS RefundAmount, rli.SOURCELINEITEMID,
           cp.OriginalPaymentTransactionId, refund_ft.CALCULATEDDATE AS RefundTransactionDate
    FROM FINANCIALTRANSACTIONLINEITEM rli
    INNER JOIN FINANCIALTRANSACTION refund_ft
        ON refund_ft.ID = rli.FINANCIALTRANSACTIONID AND refund_ft.[TYPE] = 'Refund'
    INNER JOIN CreditPaymentPerRefund cp ON cp.CREDITID = refund_ft.ID
    WHERE rli.[TYPE] = 'Standard' AND rli.SOURCELINEITEMID IS NOT NULL
),
CIM AS (
    SELECT rli.LineItemID, mt.ID AS MembershipTransactionID, mt.MEMBERSHIPID,
           ROW_NUMBER() OVER (PARTITION BY rli.LineItemID
                              ORDER BY mt.TRANSACTIONDATE DESC, mt.ID DESC) AS rn
    FROM RefundLineItems rli
    INNER JOIN CREDITITEMMEMBERSHIP cim ON cim.ID = rli.SOURCELINEITEMID OR cim.ID = rli.LineItemID
    INNER JOIN MEMBERSHIPTRANSACTION mt
        ON mt.MEMBERSHIPID = cim.MEMBERSHIPID AND mt.TRANSACTIONDATE <= rli.RefundTransactionDate
)
SELECT
    (rli.RefundAmount * -1) AS donated_amount,
    CAST(refund_ft.CALCULATEDDATE AS DATE) AS refund_date,
    refund_ft.CALCULATEDUSERDEFINEDID AS refund_revenue_id,
    m.LOOKUPID AS membership_lookup_id,
    mp.NAME AS membership_program,
    ml.NAME AS membership_level,
    COALESCE(membership_so.ID, original_so.ID, payment_so.ID, refund_so.ID) AS so_id
FROM RefundLineItems rli
INNER JOIN FINANCIALTRANSACTION refund_ft ON refund_ft.ID = rli.FinancialTransactionID
LEFT JOIN REVENUESPLIT_EXT source_rse
    ON source_rse.ID = rli.SOURCELINEITEMID
   AND source_rse.APPLICATION IN ('Membership', 'Membership add-on')
LEFT JOIN CIM cimf ON cimf.LineItemID = rli.LineItemID AND cimf.rn = 1
LEFT JOIN MEMBERSHIPTRANSACTION mt ON mt.REVENUESPLITID = rli.SOURCELINEITEMID
LEFT JOIN MEMBERSHIPADDON ma ON ma.REVENUESPLITID = rli.SOURCELINEITEMID
LEFT JOIN RecurringInstallments rgi
    ON rgi.InstallmentPaymentFinancialTransactionId = rli.OriginalPaymentTransactionId
LEFT JOIN SALESORDERITEMMEMBERSHIP soim ON soim.MEMBERSHIPTRANSACTIONID = mt.ID
LEFT JOIN SALESORDERITEM soi ON soi.ID = soim.ID
LEFT JOIN SALESORDER membership_so ON membership_so.ID = soi.SALESORDERID
LEFT JOIN SALESORDER original_so ON original_so.REVENUEID = rli.OriginalPaymentTransactionId
LEFT JOIN SalesOrdersByPayment sop ON sop.PAYMENTID = rli.OriginalPaymentTransactionId
LEFT JOIN SALESORDER payment_so ON payment_so.ID = sop.SalesOrderID
LEFT JOIN SALESORDER refund_so ON refund_so.REVENUEID = refund_ft.ID
LEFT JOIN MEMBERSHIP m ON m.ID = cimf.MEMBERSHIPID
LEFT JOIN MEMBERSHIPLEVEL ml ON ml.ID = m.MEMBERSHIPLEVELID
LEFT JOIN MEMBERSHIPPROGRAM mp ON mp.ID = ml.MEMBERSHIPPROGRAMID
WHERE
    COALESCE(membership_so.ID, original_so.ID, payment_so.ID, refund_so.ID) IS NULL
    AND (
        source_rse.APPLICATION IN ('Membership', 'Membership add-on')
        OR cimf.MembershipTransactionID IS NOT NULL
        OR mt.ID IS NOT NULL
        OR ma.MEMBERSHIPTRANSACTIONID IS NOT NULL
        OR rgi.RecurringInstallmentID IS NOT NULL
    )
    AND CAST(refund_ft.CALCULATEDDATE AS DATE) BETWEEN '2017-01-01' AND '2019-12-31'
ORDER BY refund_date;
