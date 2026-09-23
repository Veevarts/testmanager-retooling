DROP TABLE IF EXISTS #emitted;
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
        END AS RecurringInstallmentID
    FROM RECURRINGGIFTINSTALLMENT rgi
    LEFT JOIN RECURRINGGIFTINSTALLMENTPAYMENT rgp
      ON rgi.ID = rgp.RECURRINGGIFTINSTALLMENTID
    GROUP BY rgp.PAYMENTID
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
        CASE
            WHEN dli.[TYPE] = 'Reversal' THEN -1 * dli.TRANSACTIONAMOUNT
            ELSE dli.TRANSACTIONAMOUNT
        END AS NetAmount
    FROM FINANCIALTRANSACTIONLINEITEM dli
    JOIN LineSplit ls
      ON ls.LineItemID = dli.ID
    JOIN FINANCIALTRANSACTION ft
      ON ft.ID = dli.FINANCIALTRANSACTIONID
    WHERE dli.[TYPE] IN ('Standard', 'Reversal')
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
        SUM(el.NetAmount) AS Amount
    FROM EligibleLines el
    GROUP BY el.FinancialTransactionID
),


DonationOpportunityExternalIds AS (
    SELECT
        COALESCE(rgi.RecurringInstallmentID, ta.FinancialTransactionID) AS OpportunityExternalId
    FROM TransactionAgg ta
    LEFT JOIN RecurringInstallments rgi
      ON rgi.installmentPaymentFinancialTransactionId = ta.FinancialTransactionID
    WHERE ta.Amount <> 0
),

PledgeOpportunityExternalIds AS (
    SELECT
        pledge_ft.ID AS OpportunityExternalId
    FROM FINANCIALTRANSACTION pledge_ft
    WHERE pledge_ft.[TYPE] = 'Pledge'
),
OpportunityExternalIds AS (
    SELECT OpportunityExternalId FROM DonationOpportunityExternalIds
    UNION
    SELECT OpportunityExternalId FROM PledgeOpportunityExternalIds
)
SELECT OpportunityExternalId INTO #emitted FROM OpportunityExternalIds;
CREATE INDEX ix_emitted ON #emitted (OpportunityExternalId);
























































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
        END AS RecurringInstallmentID
    FROM RECURRINGGIFTINSTALLMENT rgi
    LEFT JOIN RECURRINGGIFTINSTALLMENTPAYMENT rgp
      ON rgi.ID = rgp.RECURRINGGIFTINSTALLMENTID
    GROUP BY rgp.PAYMENTID
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
        CASE
            WHEN dli.[TYPE] = 'Reversal' THEN -1 * dli.TRANSACTIONAMOUNT
            ELSE dli.TRANSACTIONAMOUNT
        END AS NetAmount
    FROM FINANCIALTRANSACTIONLINEITEM dli
    JOIN LineSplit ls
      ON ls.LineItemID = dli.ID
    JOIN FINANCIALTRANSACTION ft
      ON ft.ID = dli.FINANCIALTRANSACTIONID
    WHERE dli.[TYPE] IN ('Standard', 'Reversal')
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
        SUM(el.NetAmount) AS Amount
    FROM EligibleLines el
    GROUP BY el.FinancialTransactionID
),


DonationOpportunityExternalIds AS (
    SELECT
        COALESCE(rgi.RecurringInstallmentID, ta.FinancialTransactionID) AS OpportunityExternalId
    FROM TransactionAgg ta
    LEFT JOIN RecurringInstallments rgi
      ON rgi.installmentPaymentFinancialTransactionId = ta.FinancialTransactionID
    WHERE ta.Amount <> 0
),

PledgeOpportunityExternalIds AS (
    SELECT
        pledge_ft.ID AS OpportunityExternalId
    FROM FINANCIALTRANSACTION pledge_ft
    WHERE pledge_ft.[TYPE] = 'Pledge'
),
OpportunityExternalIds AS (
    SELECT OpportunityExternalId FROM #emitted
),



MatchingGiftDonorTransactions AS (
    SELECT DISTINCT
        rmg.MGSOURCEREVENUEID AS DonorFinancialTransactionID
    FROM REVENUEMATCHINGGIFT rmg
    WHERE rmg.ISACTIVE = 1
      AND rmg.MGSOURCEREVENUEID IS NOT NULL
),












MembershipAnchorCandidates AS (
    SELECT
        donor_li.FINANCIALTRANSACTIONID AS DonorFinancialTransactionID,
        mt.ID AS MembershipTransactionID,
        mt.REVENUESPLITID AS MembershipRevenueSplitId
    FROM MatchingGiftDonorTransactions donor
    INNER JOIN FINANCIALTRANSACTIONLINEITEM donor_li
        ON donor_li.FINANCIALTRANSACTIONID = donor.DonorFinancialTransactionID
       AND donor_li.[TYPE] = 'Standard'
    INNER JOIN MEMBERSHIPTRANSACTION mt
        ON mt.REVENUESPLITID = donor_li.ID

    UNION ALL

    SELECT
        donor_li.FINANCIALTRANSACTIONID AS DonorFinancialTransactionID,
        mt.ID AS MembershipTransactionID,
        mt.REVENUESPLITID AS MembershipRevenueSplitId
    FROM MatchingGiftDonorTransactions donor
    INNER JOIN FINANCIALTRANSACTIONLINEITEM donor_li
        ON donor_li.FINANCIALTRANSACTIONID = donor.DonorFinancialTransactionID
       AND donor_li.[TYPE] = 'Standard'
    INNER JOIN MEMBERSHIPTRANSACTION mt
        ON mt.REVENUESPLITID = donor_li.SOURCELINEITEMID
),

















MembershipAnchorTransactions AS (
    SELECT
        mac.MembershipTransactionID,
        anchor_li.FINANCIALTRANSACTIONID AS AnchorFinancialTransactionID
    FROM MembershipAnchorCandidates mac
    INNER JOIN FINANCIALTRANSACTIONLINEITEM anchor_li
        ON anchor_li.ID = mac.MembershipRevenueSplitId
       AND anchor_li.[TYPE] = 'Standard'

    UNION

    SELECT
        mac.MembershipTransactionID,
        anchor_li.FINANCIALTRANSACTIONID AS AnchorFinancialTransactionID
    FROM MembershipAnchorCandidates mac
    INNER JOIN FINANCIALTRANSACTIONLINEITEM anchor_li
        ON anchor_li.SOURCELINEITEMID = mac.MembershipRevenueSplitId
       AND anchor_li.[TYPE] = 'Standard'
),






















MembershipAnchorFlags AS (
    SELECT
        mat.MembershipTransactionID,
        MAX(CASE
                WHEN unfinished_revenue_so.ID IS NOT NULL
                  OR unfinished_payment_so.ID IS NOT NULL
                THEN 1 ELSE 0
            END) AS HasUnfinishedSalesOrder,
        MAX(CASE WHEN anchor_rgi.ID IS NOT NULL THEN 1 ELSE 0 END) AS HasRecurringInstallment
    FROM MembershipAnchorTransactions mat
    LEFT JOIN SALESORDER unfinished_revenue_so
        ON unfinished_revenue_so.REVENUEID = mat.AnchorFinancialTransactionID
       AND unfinished_revenue_so.STATUSCODE IN (0, 6, 7)
    LEFT JOIN SALESORDERPAYMENT sop
        ON sop.PAYMENTID = mat.AnchorFinancialTransactionID
    LEFT JOIN SALESORDER unfinished_payment_so
        ON unfinished_payment_so.ID = sop.SALESORDERID
       AND unfinished_payment_so.STATUSCODE IN (0, 6, 7)
    LEFT JOIN RECURRINGGIFTINSTALLMENT anchor_rgi
        ON anchor_rgi.REVENUEID = mat.AnchorFinancialTransactionID
    GROUP BY mat.MembershipTransactionID
),
MembershipOrderItemFlags AS (
    SELECT
        soim.MEMBERSHIPTRANSACTIONID AS MembershipTransactionID,
        MAX(CASE WHEN item_so.STATUSCODE IN (0, 6, 7) THEN 1 ELSE 0 END) AS HasUnfinishedSalesOrder
    FROM MembershipAnchorCandidates mac
    INNER JOIN SALESORDERITEMMEMBERSHIP soim
        ON soim.MEMBERSHIPTRANSACTIONID = mac.MembershipTransactionID
    INNER JOIN SALESORDERITEM soi
        ON soi.ID = soim.ID
    INNER JOIN SALESORDER item_so
        ON item_so.ID = soi.SALESORDERID
    GROUP BY soim.MEMBERSHIPTRANSACTIONID
),
MembershipOpportunityCandidates AS (
    SELECT DISTINCT
        mac.DonorFinancialTransactionID,
        mac.MembershipTransactionID AS OpportunityExternalId
    FROM MembershipAnchorCandidates mac
    INNER JOIN MEMBERSHIPTRANSACTION mt
        ON mt.ID = mac.MembershipTransactionID
    INNER JOIN MEMBERSHIP m
        ON m.ID = mt.MEMBERSHIPID
    LEFT JOIN MembershipAnchorFlags anchor_flags
        ON anchor_flags.MembershipTransactionID = mac.MembershipTransactionID
    LEFT JOIN MembershipOrderItemFlags item_flags
        ON item_flags.MembershipTransactionID = mac.MembershipTransactionID
    WHERE ISNULL(mt.ACTION, '') <> 'Drop'
      AND ISNULL(anchor_flags.HasUnfinishedSalesOrder, 0) = 0
      AND ISNULL(item_flags.HasUnfinishedSalesOrder, 0) = 0
      AND ISNULL(anchor_flags.HasRecurringInstallment, 0) = 0
),




MatchingGiftClaims AS (
    SELECT
        rmg.ID                 AS MatchingGiftFinancialTransactionID,
        rmg.MGSOURCEREVENUEID  AS DonorFinancialTransactionID,
        mg.CALCULATEDDATE      AS MatchingGiftClaimDate
    FROM REVENUEMATCHINGGIFT rmg
    INNER JOIN FINANCIALTRANSACTION mg
        ON mg.ID = rmg.ID
    INNER JOIN OpportunityExternalIds claim_opportunity
        ON claim_opportunity.OpportunityExternalId = rmg.ID
    WHERE rmg.ISACTIVE = 1
),



DonorOpportunityCandidates AS (
    
    
    SELECT
        mgc.MatchingGiftFinancialTransactionID,
        mgc.DonorFinancialTransactionID AS OpportunityExternalId,
        1 AS CandidateRank
    FROM MatchingGiftClaims mgc

    UNION ALL

    
    
    SELECT
        mgc.MatchingGiftFinancialTransactionID,
        rgi.RecurringInstallmentID AS OpportunityExternalId,
        2 AS CandidateRank
    FROM MatchingGiftClaims mgc
    INNER JOIN RecurringInstallments rgi
        ON rgi.installmentPaymentFinancialTransactionId = mgc.DonorFinancialTransactionID
    WHERE rgi.RecurringInstallmentID IS NOT NULL

    UNION ALL

    
    
    
    
    
    SELECT DISTINCT
        mgc.MatchingGiftFinancialTransactionID,
        ft_pledge.ID AS OpportunityExternalId,
        3 AS CandidateRank
    FROM MatchingGiftClaims mgc
    INNER JOIN FINANCIALTRANSACTIONLINEITEM donor_li
        ON donor_li.FINANCIALTRANSACTIONID = mgc.DonorFinancialTransactionID
    INNER JOIN FINANCIALTRANSACTIONLINEITEM src_li
        ON src_li.ID = donor_li.SOURCELINEITEMID
    INNER JOIN FINANCIALTRANSACTION ft_pledge
        ON ft_pledge.ID = src_li.FINANCIALTRANSACTIONID
       AND ft_pledge.TYPECODE = 1

    UNION ALL

    
    
    
    SELECT DISTINCT
        mgc.MatchingGiftFinancialTransactionID,
        order_so.REVENUEID AS OpportunityExternalId,
        4 AS CandidateRank
    FROM MatchingGiftClaims mgc
    INNER JOIN SALESORDERPAYMENT sop
        ON sop.PAYMENTID = mgc.DonorFinancialTransactionID
    INNER JOIN SALESORDER order_so
        ON order_so.ID = sop.SALESORDERID
    WHERE order_so.REVENUEID IS NOT NULL

    UNION ALL

    
    
    
    SELECT DISTINCT
        mgc.MatchingGiftFinancialTransactionID,
        moc.OpportunityExternalId,
        5 AS CandidateRank
    FROM MatchingGiftClaims mgc
    INNER JOIN MembershipOpportunityCandidates moc
        ON moc.DonorFinancialTransactionID = mgc.DonorFinancialTransactionID
),












ResolvedDonorOpportunity AS (
    SELECT
        gated.MatchingGiftFinancialTransactionID,
        gated.OpportunityExternalId,
        ROW_NUMBER() OVER (
            PARTITION BY gated.MatchingGiftFinancialTransactionID
            ORDER BY gated.CandidateRank, gated.OpportunityExternalId
        ) AS CandidateOrder
    FROM (
        SELECT
            candidates.MatchingGiftFinancialTransactionID,
            candidates.OpportunityExternalId,
            candidates.CandidateRank
        FROM DonorOpportunityCandidates candidates
        LEFT JOIN OpportunityExternalIds opportunities
            ON opportunities.OpportunityExternalId = candidates.OpportunityExternalId
        WHERE candidates.CandidateRank = 5
           OR opportunities.OpportunityExternalId IS NOT NULL
    ) gated
),
RankedLinks AS (
    SELECT
        rdo.OpportunityExternalId AS DonorOpportunityExternalId,
        rdo.MatchingGiftFinancialTransactionID,
        ROW_NUMBER() OVER (
            PARTITION BY rdo.OpportunityExternalId
            ORDER BY mgc.MatchingGiftClaimDate ASC, rdo.MatchingGiftFinancialTransactionID ASC
        ) AS LinkRank
    FROM ResolvedDonorOpportunity rdo
    INNER JOIN MatchingGiftClaims mgc
        ON mgc.MatchingGiftFinancialTransactionID = rdo.MatchingGiftFinancialTransactionID
    WHERE rdo.CandidateOrder = 1
)
SELECT
    CAST(DonorOpportunityExternalId AS VARCHAR(36))         AS Implementation_External_ID__c,
    CAST(MatchingGiftFinancialTransactionID AS VARCHAR(36)) AS npsp__Matching_Gift__c
FROM RankedLinks
WHERE LinkRank = 1
ORDER BY Implementation_External_ID__c;
