WITH 
MembershipLineItems AS (
    SELECT
        mli.ID AS MembershipLineItemID
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
-- For donation opportunities we keep only Payment (0), Order (5), and Refund (23).
EligibleLines AS (
    SELECT
        ft.ID AS FinancialTransactionID,
        ft.CALCULATEDUSERDEFINEDID AS Revenue_ID_legacy__c,
        ft.[TYPE] AS TransactionType,
        ft.CALCULATEDDATE,
        ft.CONSTITUENTID,
        rse.APPLICATION AS Application,
        CASE 
            WHEN dli.[TYPE] = 'Reversal' THEN -1 * dli.TRANSACTIONAMOUNT
            ELSE dli.TRANSACTIONAMOUNT
        END AS NetAmount,
        CASE
            WHEN rgpsli.SourceRecurringLineItemCount = 1 THEN rgpsli.SourceRecurringLineItemID
            ELSE NULL
        END AS RecurringDonationExternalId
    FROM FINANCIALTRANSACTIONLINEITEM dli
    LEFT JOIN REVENUESPLIT_EXT rse
      ON rse.ID = dli.ID
    JOIN FINANCIALTRANSACTION ft
      ON ft.ID = dli.FINANCIALTRANSACTIONID
    LEFT JOIN RecurringGiftPaymentSourceLineItems rgpsli
      ON rgpsli.PaymentLineItemID = dli.ID
    WHERE dli.[TYPE] IN ('Standard','Reversal')
      AND ft.TYPECODE NOT IN (1, 2, 20) -- Exclude Pledge, Recurring gift, Write off
      AND NOT EXISTS (
            SELECT 1
            FROM FINANCIALTRANSACTIONLINEITEM src
            JOIN FINANCIALTRANSACTION ft_pledge
              ON ft_pledge.ID = src.FINANCIALTRANSACTIONID
             AND ft_pledge.TYPECODE = 1
            WHERE dli.SOURCELINEITEMID = src.ID
      ) -- Exclude line items that are part of a pledge, since those will be represented as part of the pledge opportunity and we want to avoid duplication
      AND NOT EXISTS (
            SELECT 1 FROM MembershipLineItems m
            WHERE m.MembershipLineItemID IN (dli.SOURCELINEITEMID, dli.REVERSEDLINEITEMID)
      ) -- Exclude line items that are part of a membership, since those will be represented as part of the membership and we want to avoid duplication
      AND (
            (
                dli.[TYPE] = 'Reversal'
                AND EXISTS (
                    SELECT 1
                    FROM FINANCIALTRANSACTIONLINEITEM reversed_dli
                    LEFT JOIN REVENUESPLIT_EXT reversed_rse
                      ON reversed_rse.ID = reversed_dli.ID
                    WHERE reversed_dli.ID = dli.REVERSEDLINEITEMID
                      AND NULLIF(reversed_rse.APPLICATION, '') IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
                )
            )
         OR (
                dli.[TYPE] <> 'Reversal'
                AND NULLIF(rse.APPLICATION, '') IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
            )
      ) -- Keep non-reversal lines only for donation applications, and keep reversals only when their reversed line item is in a donation application
      AND (
            NULLIF(rse.[TYPE], '') IS NULL
         OR NULLIF(rse.[TYPE], '') NOT IN ('Membership')
      ) -- Exclude transactions that are linked to a revenue split with type of Membership, since those will be represented as part of the membership
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
        MIN(el.RecurringDonationExternalId) AS RecurringDonationExternalId
    FROM EligibleLines el
    GROUP BY el.FinancialTransactionID
)
SELECT
    COALESCE(rgi.RevenueId, ta.Revenue_ID_legacy__c) AS Revenue_ID_legacy__c,
    rgi.RecurringInstallmentID,
    so.LOOKUPID AS LookUp_ID_Legacy,
    ta.FinancialTransactionID AS Implementation_External_ID__c,
    ta.Application,
    '{{Donation_Record_Type}}' AS RecordTypeId,
    CONCAT(
        CASE WHEN ta.TransactionType = 'Refund' THEN 'Donation Refund - ' ELSE 'Donation - ' END,
        CAST(ta.CloseDate AS DATE)
    ) AS Name,
    CASE
        WHEN c.ISCONSTITUENT = 1 AND c.ISORGANIZATION = 0 AND c.ISGROUP = 0
            THEN CAST(ta.ConstituentID AS VARCHAR(36))
        ELSE NULL
    END AS npsp__Primary_Contact__c,
    CASE
        WHEN c.ISCONSTITUENT = 1 AND c.ISORGANIZATION = 0 AND c.ISGROUP = 0
            THEN CAST(chh.HOUSEHOLDID AS VARCHAR(36))
        WHEN c.ISORGANIZATION = 1
            THEN CAST(c.ID AS VARCHAR(36))
        ELSE NULL
    END AS AccountId,
    ta.CloseDate AS CloseDate,
    CASE
        WHEN ta.TransactionType = 'Refund' THEN 'Closed Lost'
        WHEN rgi.RecurringInstallmentID IS NOT NULL THEN
            CASE rgi.STATUSCODE
                WHEN 0 THEN 'Pledged'
                WHEN 1 THEN 'Closed Lost'
                WHEN 2 THEN 'Closed Won'
                WHEN 3 THEN 'Closed Lost'
                WHEN 4 THEN 'Closed Lost'
                ELSE 'Pledged'
            END
        WHEN so.ID IS NULL THEN 'Closed Won'
        WHEN so.STATUSCODE IN (1,2,3,4) THEN 'Closed Won'
        WHEN so.STATUSCODE IN (5) THEN 'Closed Lost'
        WHEN so.STATUSCODE IN (0,6,7) THEN 'Prospecting'
        ELSE 'Prospecting'
    END AS StageName,
    ta.Amount AS Amount,
    ta.CloseDate AS npsp__Acknowledgment_Date__c,
    'Acknowledged' AS npsp__Acknowledgment_Status__c,
    so.ID AS vnfp__POS_Purchase__c,
    re.GIVENANONYMOUSLY AS Given_Anonymously__c,
    CASE
        WHEN ta.RecurringDonationExternalIdCount = 1 THEN CAST(ta.RecurringDonationExternalId AS VARCHAR(36))
        ELSE NULL
    END AS npe03__Recurring_Donation__c
FROM TransactionAgg ta 	
LEFT JOIN RecurringInstallments rgi
  ON rgi.installmentPaymentFinancialTransactionId = ta.FinancialTransactionID
LEFT JOIN REVENUE_EXT re
  ON re.ID = ta.FinancialTransactionID
LEFT JOIN SALESORDER so
  ON so.REVENUEID = ta.FinancialTransactionID
LEFT JOIN CONSTITUENT c
  ON c.ID = ta.ConstituentID
LEFT JOIN CONSTITUENTHOUSEHOLD chh
  ON c.ID = chh.ID
WHERE ta.Amount <> 0
