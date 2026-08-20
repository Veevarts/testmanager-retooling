-- TC-151 / IM-1200 - charge_without_order.sql PRE (5a6122d37694), aggregate-only, read-only wrapper (v2:
-- GUID/string joins via CONVERT to NVARCHAR - FINANCIALTRANSACTION.ID es uniqueidentifier en los tenants reales).
WITH ParentLink AS (
    SELECT childItem.FINANCIALTRANSACTIONID AS ChildTransactionId,
        parentItem.FINANCIALTRANSACTIONID AS ParentTransactionID
    FROM FINANCIALTRANSACTIONLINEITEM childItem
        JOIN FINANCIALTRANSACTIONLINEITEM parentItem ON parentItem.ID = childItem.SOURCELINEITEMID
    WHERE childItem.SOURCELINEITEMID IS NOT NULL AND childItem.[TYPE] = 'Standard' AND parentItem.[TYPE] = 'Standard'
    UNION ALL
    SELECT ftli.FINANCIALTRANSACTIONID AS ChildTransactionId,
        ftli.FINANCIALTRANSACTIONID AS ParentTransactionID
    FROM FINANCIALTRANSACTIONLINEITEM ftli
    WHERE ftli.SOURCELINEITEMID IS NULL AND ftli.[TYPE] = 'Standard'
),
SalesOrdersByPayment AS (
    SELECT sop.PAYMENTID,
        MIN(sop.SALESORDERID) AS SalesOrderID
    FROM SALESORDERPAYMENT sop
    GROUP BY sop.PAYMENTID
),
RentalPayments AS (
    SELECT sop.PAYMENTID AS PaymentId
    FROM SALESORDERPAYMENT sop
        JOIN SALESORDER rental_so ON rental_so.ID = sop.SALESORDERID
        JOIN RESERVATION res ON res.ID = rental_so.ID
        JOIN FINANCIALTRANSACTION rental_ft ON rental_ft.ID = sop.PAYMENTID AND rental_ft.[TYPE] = 'Payment'
    UNION
    SELECT rsdp.PAYMENTID
    FROM RESERVATIONSECURITYDEPOSITPAYMENT rsdp
        JOIN SALESORDER deposit_so ON deposit_so.ID = rsdp.RESERVATIONID
        JOIN RESERVATION res2 ON res2.ID = deposit_so.ID
        JOIN FINANCIALTRANSACTION deposit_ft ON deposit_ft.ID = rsdp.PAYMENTID AND deposit_ft.[TYPE] = 'Payment'
),
PledgeTransactions AS (
    SELECT dli.FINANCIALTRANSACTIONID AS TxnId
    FROM FINANCIALTRANSACTIONLINEITEM dli
        JOIN FINANCIALTRANSACTION pledge_ft ON pledge_ft.ID = dli.FINANCIALTRANSACTIONID
    WHERE dli.[TYPE] IN ('Standard', 'Reversal')
        AND pledge_ft.TYPECODE = 1
        AND NOT EXISTS (
            SELECT 1 FROM SALESORDER pledge_so WHERE pledge_so.REVENUEID = dli.FINANCIALTRANSACTIONID
        )
    GROUP BY dli.FINANCIALTRANSACTIONID
    HAVING SUM(CASE WHEN dli.[TYPE] = 'Reversal' THEN -1 * dli.TRANSACTIONAMOUNT ELSE dli.TRANSACTIONAMOUNT END) <> 0
),
MembershipAnchorCandidates AS (
    SELECT
    mt.ID                     AS MembershipTransactionID,
    mt.REVENUESPLITID         AS MembershipRevenueSplitId,
    cl.ID                     AS CandidateLineId,
    cl.SOURCELINEITEMID       AS CandidateSourceLineItemId,
    cl.DATEADDED              AS CandidateDateAdded,
    cl.FINANCIALTRANSACTIONID AS CandidateFinancialTransactionId
    FROM
    MEMBERSHIPTRANSACTION mt
    INNER JOIN FINANCIALTRANSACTIONLINEITEM cl
            ON cl.ID = mt.REVENUESPLITID
           AND cl.[TYPE] = 'Standard'
    WHERE ISNULL(mt.ACTION, '') <> ('Dro' + 'p')
    UNION ALL
    SELECT
    mt.ID,
    mt.REVENUESPLITID,
    cl.ID,
    cl.SOURCELINEITEMID,
    cl.DATEADDED,
    cl.FINANCIALTRANSACTIONID
    FROM
    MEMBERSHIPTRANSACTION mt
    INNER JOIN FINANCIALTRANSACTIONLINEITEM cl
            ON cl.SOURCELINEITEMID = mt.REVENUESPLITID
           AND cl.[TYPE] = 'Standard'
    WHERE ISNULL(mt.ACTION, '') <> ('Dro' + 'p')
),
ResolvedMembershipFinancialTransactions AS (
    SELECT
    candidate_line.MembershipTransactionID,
    ft.ID AS FinancialTransactionID,
    ROW_NUMBER() OVER (
            PARTITION BY candidate_line.MembershipTransactionID
            ORDER BY
                CASE
                    WHEN candidate_line.CandidateSourceLineItemId = candidate_line.MembershipRevenueSplitId THEN 0
                    WHEN candidate_line.CandidateLineId = candidate_line.MembershipRevenueSplitId THEN 1
                    ELSE 2
                END,
                CASE
                    WHEN ft.[TYPE] = 'Refund' THEN 1
                    ELSE 0
                END,
                ft.CALCULATEDDATE DESC,
                candidate_line.CandidateDateAdded DESC,
                ft.ID DESC
        ) AS ResolutionRank
    FROM
    MembershipAnchorCandidates candidate_line
    INNER JOIN FINANCIALTRANSACTION ft
            ON ft.ID = candidate_line.CandidateFinancialTransactionId
),
MembershipRecurringInstallments AS (
    SELECT RecurringInstallmentID, FinancialTransactionID
    FROM (
        SELECT
            rgi.ID AS RecurringInstallmentID,
            rgi.REVENUEID AS FinancialTransactionID,
            ROW_NUMBER() OVER (
                PARTITION BY rgi.ID
                ORDER BY
                    CASE WHEN rgp.PAYMENTID IS NULL THEN 1 ELSE 0 END,
                    rgp.PAYMENTID
            ) AS InstallmentPaymentRank
        FROM RECURRINGGIFTINSTALLMENT rgi
        LEFT JOIN RECURRINGGIFTINSTALLMENTPAYMENT rgp
            ON rgi.ID = rgp.RECURRINGGIFTINSTALLMENTID
    ) membership_recurring_installments
    WHERE InstallmentPaymentRank = 1
),
RecurringInstallmentsByPayment AS (
    SELECT
        rgp.PAYMENTID AS PaymentId,
        CASE WHEN COUNT(DISTINCT rgi.ID) = 1 THEN MIN(rgi.ID) ELSE NULL END AS RecurringInstallmentID
    FROM RECURRINGGIFTINSTALLMENT rgi
        JOIN RECURRINGGIFTINSTALLMENTPAYMENT rgp ON rgi.ID = rgp.RECURRINGGIFTINSTALLMENTID
    GROUP BY rgp.PAYMENTID
),
MembershipPosByPayment AS (
    SELECT PaymentId, PosExternalId
    FROM (
        SELECT
            rmft.FinancialTransactionID AS PaymentId,
            CAST(CONCAT(
                'membership-no-order-pos-',
                CAST(COALESCE(mri.RecurringInstallmentID, rmft.MembershipTransactionID) AS NVARCHAR(36))
            ) AS NVARCHAR(100)) AS PosExternalId,
            ROW_NUMBER() OVER (
                PARTITION BY rmft.FinancialTransactionID
                ORDER BY rmft.MembershipTransactionID, mri.RecurringInstallmentID
            ) AS MembershipRank
        FROM ResolvedMembershipFinancialTransactions rmft
            LEFT JOIN MembershipRecurringInstallments mri ON mri.FinancialTransactionID = rmft.FinancialTransactionID
            LEFT JOIN SALESORDERITEMMEMBERSHIP soim ON soim.MEMBERSHIPTRANSACTIONID = rmft.MembershipTransactionID
            LEFT JOIN SALESORDERITEM soi ON soi.ID = soim.ID
            LEFT JOIN SALESORDER membership_so ON membership_so.ID = soi.SALESORDERID
            LEFT JOIN SALESORDER revenue_so ON revenue_so.REVENUEID = rmft.FinancialTransactionID
            LEFT JOIN SalesOrdersByPayment msop ON msop.PAYMENTID = rmft.FinancialTransactionID
            LEFT JOIN SALESORDER payment_so ON payment_so.ID = msop.SalesOrderID
        WHERE rmft.ResolutionRank = 1
            AND COALESCE(membership_so.ID, revenue_so.ID, payment_so.ID) IS NULL
    ) ranked_membership
    WHERE MembershipRank = 1
),
DonationMembershipLineItems AS (
    SELECT
        mli.ID AS MembershipLineItemID,
        CASE WHEN EXISTS (
            SELECT 1
            FROM MEMBERSHIPTRANSACTION mt
            WHERE mt.REVENUESPLITID = mli.ID
              AND ISNULL(mt.ACTION, '') <> ('Dro' + 'p')
        ) THEN 1 ELSE 0 END AS HasMembershipTransaction
    FROM FINANCIALTRANSACTIONLINEITEM mli
    JOIN REVENUESPLIT_EXT rse
      ON rse.ID = mli.ID
    WHERE rse.APPLICATION = 'Membership'
      AND mli.[TYPE] = 'Standard'
),
DonationSupersededLines AS (
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
DonationLineSplit AS (
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
    LEFT JOIN DonationSupersededLines sl
        ON sl.LineItemID = dli.ID
    WHERE dli.[TYPE] IN ('Standard', 'Reversal')
      AND (
            own_rse.APPLICATION IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
         OR dli.REVERSEDLINEITEMID IS NOT NULL
      )
),
DonationEligibleLines AS (
    SELECT
        ft.ID AS FinancialTransactionID,
        CASE
            WHEN dli.[TYPE] = 'Reversal' THEN -1 * dli.TRANSACTIONAMOUNT
            ELSE dli.TRANSACTIONAMOUNT
        END AS NetAmount
    FROM FINANCIALTRANSACTIONLINEITEM dli
    JOIN DonationLineSplit ls
      ON ls.LineItemID = dli.ID
    JOIN FINANCIALTRANSACTION ft
      ON ft.ID = dli.FINANCIALTRANSACTIONID
    WHERE dli.[TYPE] IN ('Standard','Reversal')
      AND ft.TYPECODE NOT IN (1, 2, 20) -- Exclude Pledge, Recurring gift, Write off
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
            SELECT 1 FROM DonationMembershipLineItems m
            WHERE m.MembershipLineItemID = dli.REVERSEDLINEITEMID
      )
      AND NOT EXISTS (
            SELECT 1 FROM DonationMembershipLineItems m
            WHERE m.MembershipLineItemID = ls.GATESOURCELINEITEMID
              AND m.HasMembershipTransaction = 1
              AND (
                    (dli.[TYPE] <> 'Reversal' AND NULLIF(ls.APPLICATION, '') = 'Donation')
                 OR (dli.[TYPE] = 'Reversal' AND EXISTS (
                        SELECT 1
                        FROM DonationLineSplit reversed_app_ls
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
                    FROM DonationLineSplit reversed_ls
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
DonationTransactions AS (
    SELECT del.FinancialTransactionID AS TxnId
    FROM DonationEligibleLines del
    GROUP BY del.FinancialTransactionID
    HAVING SUM(del.NetAmount) <> 0
),
PaymentMethods AS (
    SELECT rpm.ID, rpm.REVENUEID, rpm.PAYMENTMETHOD
    FROM REVENUEPAYMENTMETHOD rpm
    JOIN (
        SELECT REVENUEID, MIN(ID) AS ID
        FROM REVENUEPAYMENTMETHOD
        GROUP BY REVENUEID
    ) rpm_first ON rpm_first.ID = rpm.ID
),
ChargeRows AS (
    SELECT
        ft.CALCULATEDDATE AS TRANSACTIONDATE,
        NULL AS LOOKUPID, -- no SALESORDER.LOOKUPID exists for an order-less payment
        CASE
            WHEN rental.PaymentId IS NOT NULL
                THEN CAST(ft.ID AS NVARCHAR(100))
            WHEN payment_so.ID IS NOT NULL
                THEN CAST(payment_so.ID AS NVARCHAR(100))
            WHEN pledge.TxnId IS NOT NULL
                THEN CAST(ft.ID AS NVARCHAR(100))
            WHEN membership_pos.PosExternalId IS NOT NULL
                THEN CAST(membership_pos.PosExternalId AS NVARCHAR(100))
            WHEN donation.TxnId IS NOT NULL
                THEN CAST(CONCAT(
                    'donation-no-order-pos-',
                    CAST(COALESCE(rip.RecurringInstallmentID, ft.ID) AS NVARCHAR(36))
                ) AS NVARCHAR(100))
            ELSE NULL
        END AS 'Auctifera__POS_Purchase__r:Auctifera__POS_Purchase__c-Implementation_External_ID__c',
        chargeRevenue.TYPE as ChargeRevenueType,
        ft.TYPE as ftType,
        COALESCE(chargeRevenue.ID, ft.ID) AS Implementation_External_ID__c,
        COALESCE(
            chargeRevenue.CALCULATEDUSERDEFINEDID,
            ft.CALCULATEDUSERDEFINEDID
        ) AS Revenue_ID_legacy__c,
        'Succeeded' AS Auctifera__Status__c,
        rpm.PAYMENTMETHOD AS Auctifera__Type__c,
        COALESCE(
            chargeRevenue.TRANSACTIONAMOUNT,
            ft.TRANSACTIONAMOUNT
        ) AS Auctifera__Amount__c,
        chk.CHECKNUMBER AS Auctifera__Check_Reference__c,
        ccp.CREDITCARDPARTIALNUMBER AS Auctifera__Credit_Card__c,
        COALESCE(chargeRevenue.CALCULATEDDATE, ft.CALCULATEDDATE) AS Auctifera__Tech_Payment_Date__c,
        ccp.FEE AS CreditCardFee,
        ccp.NETAMOUNT AS CreditCardNetAmount,
        ccp.SETTLEMENTDATE AS CreditCardSettlementDate,
        ccp.AUTHORIZATIONCODE AS CreditCardAuthCode,
        ROW_NUMBER() OVER (
            PARTITION BY COALESCE(chargeRevenue.ID, ft.ID)
            ORDER BY
                CASE
                    WHEN rental.PaymentId IS NOT NULL
                      OR payment_so.ID IS NOT NULL
                      OR pledge.TxnId IS NOT NULL
                      OR membership_pos.PosExternalId IS NOT NULL
                      OR donation.TxnId IS NOT NULL
                    THEN 0 ELSE 1
                END,
                ft.ID
        ) AS ChargeRank
    FROM FINANCIALTRANSACTION ft
        JOIN ParentLink pl ON ft.ID = pl.ParentTransactionID
        JOIN FINANCIALTRANSACTION chargeRevenue ON chargeRevenue.ID = pl.ChildTransactionId
        LEFT JOIN SALESORDER so ON so.REVENUEID = ft.ID
        LEFT JOIN SalesOrdersByPayment sop_link ON sop_link.PAYMENTID = ft.ID
        LEFT JOIN SALESORDER payment_so ON payment_so.ID = sop_link.SalesOrderID
        LEFT JOIN RentalPayments rental ON rental.PaymentId = ft.ID
        LEFT JOIN PledgeTransactions pledge ON pledge.TxnId = ft.ID
        LEFT JOIN MembershipPosByPayment membership_pos ON membership_pos.PaymentId = ft.ID
        LEFT JOIN DonationTransactions donation ON donation.TxnId = ft.ID
        LEFT JOIN RecurringInstallmentsByPayment rip ON rip.PaymentId = ft.ID
        LEFT JOIN PaymentMethods rpm ON rpm.REVENUEID = COALESCE(chargeRevenue.ID, ft.ID)
        LEFT JOIN CREDITCARDPAYMENTMETHODDETAIL ccp ON ccp.ID = rpm.ID
        LEFT JOIN CHECKPAYMENTMETHODDETAIL chk ON chk.ID = rpm.ID
    WHERE so.ID IS NULL
    AND chargeRevenue.TYPE = 'Payment'
)
, QaOrderlessPledges AS (
    SELECT ft_qa.ID, CONVERT(NVARCHAR(64), ft_qa.ID) AS IdText
    FROM FINANCIALTRANSACTION ft_qa
    WHERE ft_qa.TYPECODE = 1
      AND NOT EXISTS (SELECT 1 FROM SALESORDER so_qa WHERE so_qa.REVENUEID = ft_qa.ID)
),
QaOldGate AS (
    SELECT dli_qa.FINANCIALTRANSACTIONID AS FtId
    FROM FINANCIALTRANSACTIONLINEITEM dli_qa
    INNER JOIN FINANCIALTRANSACTION ft2_qa ON ft2_qa.ID = dli_qa.FINANCIALTRANSACTIONID
    WHERE dli_qa.[TYPE] IN ('Standard', 'Reversal') AND ft2_qa.TYPECODE = 1
    GROUP BY dli_qa.FINANCIALTRANSACTIONID
    HAVING SUM(CASE WHEN dli_qa.[TYPE] = 'Reversal' THEN -1 * dli_qa.TRANSACTIONAMOUNT ELSE dli_qa.TRANSACTIONAMOUNT END) <> 0
)
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT x.ext_id) AS distinct_external_ids,
    SUM(x.is_null_ref) AS null_pos_refs,
    SUM(x.is_orderless_pledge_ref) AS orderless_pledge_refs,
    SUM(CASE WHEN x.is_orderless_pledge_ref = 1 AND x.in_old_gate = 0 THEN 1 ELSE 0 END) AS pledge_refs_not_minted_by_old_gate,
    SUM(x.is_ticket_id_ref) AS ticket_id_refs
FROM (
    SELECT
        CONVERT(NVARCHAR(128), q.Implementation_External_ID__c) AS ext_id,
        CASE WHEN q.[Auctifera__POS_Purchase__r:Auctifera__POS_Purchase__c-Implementation_External_ID__c] IS NULL THEN 1 ELSE 0 END AS is_null_ref,
        CASE WHEN op_qa.ID IS NOT NULL THEN 1 ELSE 0 END AS is_orderless_pledge_ref,
        CASE WHEN og_qa.FtId IS NOT NULL THEN 1 ELSE 0 END AS in_old_gate,
        CASE WHEN CONVERT(NVARCHAR(64), q.[Auctifera__POS_Purchase__r:Auctifera__POS_Purchase__c-Implementation_External_ID__c]) IN ('aef807ba-59fc-4594-9e63-babe9f8f5083', 'e72b9b13-55b8-46f2-b184-6db67c60f111') THEN 1 ELSE 0 END AS is_ticket_id_ref
    FROM ChargeRows q
    LEFT JOIN QaOrderlessPledges op_qa ON op_qa.IdText = CONVERT(NVARCHAR(64), q.[Auctifera__POS_Purchase__r:Auctifera__POS_Purchase__c-Implementation_External_ID__c])
    LEFT JOIN QaOldGate og_qa ON og_qa.FtId = op_qa.ID
    WHERE q.ChargeRank = 1
) x
