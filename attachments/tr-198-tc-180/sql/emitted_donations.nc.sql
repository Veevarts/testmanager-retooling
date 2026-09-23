DECLARE @hasDateFilterFrom BIT = 0;
DECLARE @hasDateFilterTo BIT = 0;
DECLARE @dateFilterFrom VARCHAR(10) = NULL;
DECLARE @dateFilterTo VARCHAR(10) = NULL;
DECLARE @useDateFrom BIT = IIF(@hasDateFilterFrom = 1, 1, 0);
DECLARE @useDateTo BIT = IIF(@hasDateFilterTo = 1, 1, 0);
DECLARE @filterDateFrom DATE = CAST(@dateFilterFrom AS DATE);
DECLARE @filterDateTo DATE = CAST(@dateFilterTo AS DATE);
;WITH
MembershipLineItems AS (
    SELECT
        mli.ID AS MembershipLineItemID,
        CASE WHEN EXISTS (
            SELECT 1
            FROM MEMBERSHIPTRANSACTION mt
            WHERE mt.REVENUESPLITID = mli.ID
              AND ISNULL(mt.ACTION, '') <> 'Drop'
        ) THEN 1 ELSE 0 END AS HasMembershipTransaction
    FROM FINANCIALTRANSACTIONLINEITEM mli
    JOIN REVENUESPLIT_EXT rse
      ON rse.ID = mli.ID
    WHERE rse.APPLICATION = 'Membership'
      AND mli.[TYPE] = 'Standard'
),
RecurringInstallments AS (
    SELECT
        rgp.PAYMENTID AS installmentPaymentFinancialTransactionId,
        CASE
            WHEN COUNT(DISTINCT rgi.ID) = 1 THEN MIN(rgi.ID)
            ELSE NULL
        END AS RecurringInstallmentID,
        MIN(rgi.STATUSCODE) AS STATUSCODE,
        MIN(rgi.REVENUEID) AS FinancialTransactionID,
        MIN(rgi.TRANSACTIONAMOUNT) AS InstallmentAmount,
        MIN(rgi.[DATE]) AS InstallmentDate,
        MIN(rgi.STATUS) AS InstallmentStatus,
        MIN(ft.CALCULATEDUSERDEFINEDID) AS RevenueId
    FROM RECURRINGGIFTINSTALLMENT rgi
    LEFT JOIN RECURRINGGIFTINSTALLMENTPAYMENT rgp
      ON rgi.ID = rgp.RECURRINGGIFTINSTALLMENTID
    LEFT JOIN FINANCIALTRANSACTION ft
      ON ft.ID = rgp.PAYMENTID
    GROUP BY rgp.PAYMENTID
),
RecurringGiftPaymentSourceLineItems AS (
    SELECT
        rga.PAYMENTREVENUEID AS PaymentLineItemID,
        COUNT(DISTINCT src_li.ID) AS SourceRecurringLineItemCount,
        MIN(src_li.ID) AS SourceRecurringLineItemID
    FROM RECURRINGGIFTACTIVITY rga
    JOIN FINANCIALTRANSACTIONLINEITEM src_li
      ON src_li.FINANCIALTRANSACTIONID = rga.SOURCEREVENUEID
     AND src_li.[TYPE] = 'Standard'
    LEFT JOIN REVENUESPLIT_EXT src_rse
      ON src_rse.ID = src_li.ID
    WHERE NULLIF(src_rse.APPLICATION, '') IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
      AND (
            NULLIF(src_rse.[TYPE], '') IS NULL
         OR NULLIF(src_rse.[TYPE], '') NOT IN ('Membership')
      )
    GROUP BY rga.PAYMENTREVENUEID
),
GiftInKindTransactions AS (
    SELECT DISTINCT
        rpm.REVENUEID AS FinancialTransactionID
    FROM REVENUEPAYMENTMETHOD rpm
    JOIN GIFTINKINDPAYMENTMETHODDETAIL gik
      ON gik.ID = rpm.ID
),
StockGiftTransactions AS (
    SELECT DISTINCT
        rpm.REVENUEID AS FinancialTransactionID
    FROM REVENUEPAYMENTMETHOD rpm
    JOIN STOCKDETAIL stock_detail
      ON stock_detail.ID = rpm.ID
),
PropertyGiftTransactions AS (
    SELECT DISTINCT
        rpm.REVENUEID AS FinancialTransactionID
    FROM REVENUEPAYMENTMETHOD rpm
    JOIN PROPERTYDETAIL property_detail
      ON property_detail.ID = rpm.ID
),
ActiveMatchingGiftClaims AS (
    SELECT
        rmg_suppression.ID AS FinancialTransactionID
    FROM REVENUEMATCHINGGIFT rmg_suppression
    WHERE rmg_suppression.ISACTIVE = 1
),
SupersededLines AS (
    SELECT
        dli.ID AS LineItemID,
        superseded_dli.ID AS SupersededLineItemID,
        superseded_dli.SOURCELINEITEMID AS SupersededSourceLineItemID,
        superseded_rse.APPLICATION AS SupersededApplication,
        superseded_rse.[TYPE] AS SupersededSplitType,
        CASE WHEN EXISTS (
            SELECT 1
            FROM FINANCIALTRANSACTIONLINEITEM cancel
            WHERE cancel.REVERSEDLINEITEMID = dli.REVERSEDLINEITEMID
              AND cancel.[TYPE] = 'Reversal'
              AND cancel.FINANCIALTRANSACTIONID = dli.FINANCIALTRANSACTIONID
        ) THEN 1 ELSE 0 END AS SupersedeEffective
    FROM FINANCIALTRANSACTIONLINEITEM dli
    INNER JOIN FINANCIALTRANSACTIONLINEITEM superseded_dli
        ON superseded_dli.ID = dli.REVERSEDLINEITEMID
       AND superseded_dli.FINANCIALTRANSACTIONID = dli.FINANCIALTRANSACTIONID
    LEFT JOIN REVENUESPLIT_EXT superseded_rse
        ON superseded_rse.ID = superseded_dli.ID
    WHERE dli.REVERSEDLINEITEMID IS NOT NULL
),
LineSplit AS (
    SELECT
        dli.ID AS LineItemID,
        COALESCE(own_rse.APPLICATION, CASE WHEN dli.[TYPE] = 'Standard' THEN sl.SupersededApplication END) AS APPLICATION,
        COALESCE(own_rse.[TYPE], CASE WHEN dli.[TYPE] = 'Standard' THEN sl.SupersededSplitType END) AS [TYPE],
        COALESCE(dli.SOURCELINEITEMID, sl.SupersededSourceLineItemID) AS GATESOURCELINEITEMID,
        COALESCE(sl.SupersededLineItemID, dli.ID) AS GATELINEITEMID,
        ISNULL(sl.SupersedeEffective, 0) AS SUPERSEDEEFFECTIVE,
        CASE WHEN NULLIF(own_rse.APPLICATION, '') IS NOT NULL THEN 1 ELSE 0 END AS HASOWNSPLIT
    FROM FINANCIALTRANSACTIONLINEITEM dli
    LEFT JOIN REVENUESPLIT_EXT own_rse
        ON own_rse.ID = dli.ID
    LEFT JOIN SupersededLines sl
        ON sl.LineItemID = dli.ID
    WHERE dli.[TYPE] IN ('Standard', 'Reversal')
      AND (
            own_rse.APPLICATION IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
         OR dli.REVERSEDLINEITEMID IS NOT NULL
      )
),
EligibleLines AS (
    SELECT
        ft.ID AS FinancialTransactionID,
        ft.CALCULATEDUSERDEFINEDID AS Revenue_ID_legacy__c,
        ft.[TYPE] AS TransactionType,
        ft.CALCULATEDDATE,
        ft.CONSTITUENTID,
        ls.APPLICATION AS Application,
        CASE 
            WHEN dli.[TYPE] = 'Reversal' THEN -1 * dli.TRANSACTIONAMOUNT
            ELSE dli.TRANSACTIONAMOUNT
        END AS NetAmount,
        CASE
            WHEN rgpsli.SourceRecurringLineItemCount = 1 THEN rgpsli.SourceRecurringLineItemID
            ELSE NULL
        END AS RecurringDonationExternalId,
        CASE
            WHEN gift_in_kind.FinancialTransactionID IS NOT NULL THEN 1
            ELSE 0
        END AS HasGiftInKindPaymentDetail,
        CASE
            WHEN stock_gift.FinancialTransactionID IS NOT NULL THEN 1
            ELSE 0
        END AS HasStockPaymentDetail,
        CASE
            WHEN property_gift.FinancialTransactionID IS NOT NULL THEN 1
            ELSE 0
        END AS HasPropertyPaymentDetail,
        CASE
            WHEN active_mg_claim.FinancialTransactionID IS NOT NULL THEN 1
            ELSE 0
        END AS IsActiveMatchingGiftClaim
    FROM FINANCIALTRANSACTIONLINEITEM dli
    JOIN LineSplit ls
      ON ls.LineItemID = dli.ID
    JOIN FINANCIALTRANSACTION ft
      ON ft.ID = dli.FINANCIALTRANSACTIONID
    LEFT JOIN RecurringGiftPaymentSourceLineItems rgpsli
      ON rgpsli.PaymentLineItemID = dli.ID
    LEFT JOIN GiftInKindTransactions gift_in_kind
      ON gift_in_kind.FinancialTransactionID = ft.ID
    LEFT JOIN StockGiftTransactions stock_gift
      ON stock_gift.FinancialTransactionID = ft.ID
    LEFT JOIN PropertyGiftTransactions property_gift
      ON property_gift.FinancialTransactionID = ft.ID
    LEFT JOIN ActiveMatchingGiftClaims active_mg_claim
      ON active_mg_claim.FinancialTransactionID = ft.ID
    WHERE dli.[TYPE] IN ('Standard','Reversal')
      AND ft.TYPECODE NOT IN (1, 2, 20) 
      AND NOT EXISTS (
            SELECT 1
            FROM FINANCIALTRANSACTIONLINEITEM src
            JOIN FINANCIALTRANSACTION ft_pledge
              ON ft_pledge.ID = src.FINANCIALTRANSACTIONID
             AND ft_pledge.TYPECODE = 1
            WHERE ls.GATESOURCELINEITEMID = src.ID
      ) 
      AND NOT EXISTS (
            SELECT 1
            FROM INSTALLMENTSPLITPAYMENT isp_mg
            JOIN INSTALLMENTSPLIT isplt_mg
              ON isplt_mg.ID = isp_mg.INSTALLMENTSPLITID
            JOIN REVENUEMATCHINGGIFT rmg
              ON rmg.ID = isplt_mg.PLEDGEID
            WHERE isp_mg.PAYMENTID IN (dli.ID, ls.GATELINEITEMID)
      ) 
      AND NOT EXISTS (
            SELECT 1 FROM MembershipLineItems m
            WHERE m.MembershipLineItemID = dli.REVERSEDLINEITEMID
      ) 
      AND NOT EXISTS (
            SELECT 1 FROM MembershipLineItems m
            WHERE m.MembershipLineItemID = ls.GATESOURCELINEITEMID
              AND m.HasMembershipTransaction = 1
              AND (
                    (dli.[TYPE] <> 'Reversal' AND NULLIF(ls.APPLICATION, '') = 'Donation')
                 OR (dli.[TYPE] = 'Reversal' AND EXISTS (
                        SELECT 1
                        FROM LineSplit reversed_app_ls
                        WHERE reversed_app_ls.LineItemID = dli.REVERSEDLINEITEMID
                          AND NULLIF(reversed_app_ls.APPLICATION, '') = 'Donation'
                    ))
              )
      ) 
      AND (
            (
                dli.[TYPE] = 'Reversal'
                AND EXISTS (
                    SELECT 1
                    FROM LineSplit reversed_ls
                    WHERE reversed_ls.LineItemID = dli.REVERSEDLINEITEMID
                      AND NULLIF(reversed_ls.APPLICATION, '') IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
                      AND (reversed_ls.HASOWNSPLIT = 1 OR reversed_ls.SUPERSEDEEFFECTIVE = 1)
                )
            )
         OR (
                dli.[TYPE] <> 'Reversal'
                AND NULLIF(ls.APPLICATION, '') IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
             AND (
                        ls.HASOWNSPLIT = 1
                     OR dli.REVERSEDLINEITEMID IS NULL
                     OR ls.SUPERSEDEEFFECTIVE = 1
                    )
            )
      ) 
      AND (
            NULLIF(ls.[TYPE], '') IS NULL
         OR NULLIF(ls.[TYPE], '') NOT IN ('Membership')
      ) 
),
TransactionAgg AS (
    SELECT
        el.FinancialTransactionID,
        MIN(el.Revenue_ID_legacy__c) AS Revenue_ID_legacy__c,
        MIN(el.TransactionType) AS TransactionType,
        MIN(el.Application) AS Application,
        SUM(el.NetAmount) AS Amount,
        CAST(MAX(el.CALCULATEDDATE) AS DATE) AS CloseDate,
        MIN(el.CONSTITUENTID) AS ConstituentID,
        COUNT(DISTINCT el.RecurringDonationExternalId) AS RecurringDonationExternalIdCount,
        MIN(el.RecurringDonationExternalId) AS RecurringDonationExternalId,
        MAX(el.HasGiftInKindPaymentDetail) AS HasGiftInKindPaymentDetail,
        MAX(el.HasStockPaymentDetail) AS HasStockPaymentDetail,
        MAX(el.HasPropertyPaymentDetail) AS HasPropertyPaymentDetail,
        MAX(el.IsActiveMatchingGiftClaim) AS IsActiveMatchingGiftClaim
    FROM EligibleLines el
    GROUP BY el.FinancialTransactionID
),
SalesOrdersByPayment AS (
    SELECT
        sop.PAYMENTID,
        MIN(sop.SALESORDERID) AS SalesOrderID
    FROM SALESORDERPAYMENT sop
    GROUP BY sop.PAYMENTID
)
SELECT DISTINCT
    COALESCE(CAST(rgi.RecurringInstallmentID AS VARCHAR(36)), CAST(ta.FinancialTransactionID AS VARCHAR(36))) AS OpportunityExternalId
FROM TransactionAgg ta 	
LEFT JOIN RecurringInstallments rgi
  ON rgi.installmentPaymentFinancialTransactionId = ta.FinancialTransactionID
LEFT JOIN REVENUE_EXT re
  ON re.ID = ta.FinancialTransactionID
LEFT JOIN SALESORDER revenue_so
  ON revenue_so.REVENUEID = ta.FinancialTransactionID
LEFT JOIN SalesOrdersByPayment sop
  ON sop.PAYMENTID = ta.FinancialTransactionID
LEFT JOIN SALESORDER payment_so
  ON payment_so.ID = sop.SalesOrderID
LEFT JOIN CONSTITUENT c
  ON c.ID = ta.ConstituentID
LEFT JOIN CONSTITUENTHOUSEHOLD chh
  ON c.ID = chh.ID
WHERE ta.Amount <> 0
  AND (@useDateFrom = 0 OR ta.CloseDate >= @filterDateFrom)
  AND (@useDateTo = 0 OR ta.CloseDate <= @filterDateTo)
