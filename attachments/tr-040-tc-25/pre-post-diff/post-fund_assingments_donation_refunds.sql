DECLARE @useDateFrom BIT = IIF(@hasDateFilterFrom = 1, 1, 0);
DECLARE @useDateTo BIT = IIF(@hasDateFilterTo = 1, 1, 0);
DECLARE @filterDateFrom DATE = CAST(@dateFilterFrom AS DATE);
DECLARE @filterDateTo DATE = CAST(@dateFilterTo AS DATE);

/* 
Purpose: create fund-assignment rows for donation-related refunds.
Approach:
 1) MembershipLineItems filters out membership splits; refunds tied to membership are excluded.
 2) RefundLineItems pulls refund FT line items, keeps source line item reference and original payment transaction id.
 3) Final select negates refund amounts, derives fund from the source line's revenue split, and links back to the original payment's sales order when present (else the refund SO).
Key assumptions/notes:
 - Revenue_ID_legacy__c is blank on refunds in this source system.
 - vnfp__Opportunity__c points to the original donation opportunity transaction, so refunds do not create separate donation opportunities.
 - Only donation/recurring/planned/matching gift applications are allowed for fund lookup; other applications will be filtered out.
*/
WITH 
MembershipLineItems AS (
    SELECT
        mli.ID AS MembershipLineItemID
    FROM
        FINANCIALTRANSACTIONLINEITEM mli
    INNER JOIN REVENUESPLIT_EXT rse
            ON rse.ID = mli.ID
    WHERE
            rse.APPLICATION = 'Membership'
        AND mli.[TYPE] = 'Standard'
),
RecurringInstallments AS (
    SELECT
        rgp.PAYMENTID AS installmentPaymentFinancialTransactionId,
        CASE
            WHEN COUNT(DISTINCT rgi.ID) = 1 THEN MIN(rgi.ID)
            ELSE NULL
        END AS RecurringInstallmentID
    FROM RECURRINGGIFTINSTALLMENT rgi
    LEFT JOIN RECURRINGGIFTINSTALLMENTPAYMENT rgp
      ON rgi.ID = rgp.RECURRINGGIFTINSTALLMENTID
    GROUP BY rgp.PAYMENTID
),
-- CREDITPAYMENT can have multiple rows per refund; pick a single payment id to avoid duplicate refund line items
CreditPaymentPerRefund AS (
    SELECT
        CREDITID,
        MIN(REVENUEID) AS OriginalPaymentTransactionId
    FROM
        CREDITPAYMENT
    GROUP BY
        CREDITID
),
RefundLineItems AS (
    SELECT
        refund_ft.ID AS FinancialTransactionID,
        rli.ID AS LineItemID,
        rli.TRANSACTIONAMOUNT AS RefundAmount,
        rli.SOURCELINEITEMID,
        cp.OriginalPaymentTransactionId
    FROM
        FINANCIALTRANSACTIONLINEITEM rli
    INNER JOIN FINANCIALTRANSACTION refund_ft
        ON refund_ft.ID = rli.FINANCIALTRANSACTIONID
        AND refund_ft.[TYPE] = 'Refund'
    INNER JOIN CreditPaymentPerRefund cp
        ON cp.CREDITID = refund_ft.ID
    WHERE
        rli.[TYPE] = 'Standard'
        AND rli.SOURCELINEITEMID IS NOT NULL
        AND NOT EXISTS (
		    SELECT 1
		    FROM MembershipLineItems m
		    WHERE m.MembershipLineItemID = rli.SOURCELINEITEMID
		)
)
SELECT
    rli.LineItemID AS vnfp__Implementation_External_ID__c,
    COALESCE(original_so.LOOKUPID, refund_so.LOOKUPID) AS LookUp_ID_Legacy,
    CAST(source_rse.DESIGNATIONID AS VARCHAR(36)) AS Auctifera__Specific_Fund__c,
    d.NAME AS Auctifera__Specific_Fund_Name__c,
    'Posted' AS Auctifera__Accounting_Status__c,
    'Refunded' AS Auctifera__Status__c,
    (rli.RefundAmount * -1) AS Auctifera__Donated_Amount__c, -- Negative amount for refunds
    CAST(ft.CALCULATEDDATE AS DATE) AS Auctifera__Posted_Date__c,
    'Acknowledged' AS vnfp__Acknowledgment_Status__c,
    COALESCE(
        CAST(rgi.RecurringInstallmentID AS VARCHAR(36)),
        CAST(rli.OriginalPaymentTransactionId AS VARCHAR(36))
    ) AS vnfp__Opportunity__c,
    COALESCE(original_so.ID, refund_so.ID) AS vnfp__Opportunity_POS_Purchase__c --TODO: When IM-87 is implemented, modify accordingly to support refunds linked to non-SO transactions
FROM
    RefundLineItems rli
INNER JOIN FINANCIALTRANSACTION ft
    ON ft.ID = rli.FinancialTransactionID
INNER JOIN FINANCIALTRANSACTIONLINEITEM source_dli
    ON source_dli.ID = rli.SOURCELINEITEMID
-- Get the designation from the original source line item's revenue split
INNER JOIN REVENUESPLIT_EXT source_rse
    ON source_rse.ID = rli.SOURCELINEITEMID
    AND source_rse.APPLICATION IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
    AND source_rse.[TYPE] NOT IN ('Membership')
-- Link to the original sales order through the original payment transaction
LEFT JOIN SALESORDER original_so
    ON original_so.REVENUEID = rli.OriginalPaymentTransactionId
LEFT JOIN RecurringInstallments rgi
    ON rgi.installmentPaymentFinancialTransactionId = rli.OriginalPaymentTransactionId
-- Fallback to refund transaction's sales order if original not found
LEFT JOIN SALESORDER refund_so
    ON refund_so.REVENUEID = ft.ID
LEFT JOIN DESIGNATION d
    ON source_rse.DESIGNATIONID = d.ID
WHERE
    (@useDateFrom = 0 OR CAST(ft.CALCULATEDDATE AS DATE) >= @filterDateFrom)
    AND (@useDateTo = 0 OR CAST(ft.CALCULATEDDATE AS DATE) <= @filterDateTo)
ORDER BY
    ft.CALCULATEDUSERDEFINEDID;
