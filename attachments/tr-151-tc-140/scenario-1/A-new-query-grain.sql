DECLARE @hasDateFilterFrom BIT = 0;
DECLARE @hasDateFilterTo BIT = 0;
DECLARE @dateFilterFrom DATETIME2 = '1900-01-01';
DECLARE @dateFilterTo DATETIME2 = '2100-12-31';
DECLARE @useDateFrom BIT = IIF(@hasDateFilterFrom = 1, 1, 0);
DECLARE @useDateTo BIT = IIF(@hasDateFilterTo = 1, 1, 0);
DECLARE @filterDateFrom DATE = CAST(@dateFilterFrom AS DATE);
DECLARE @filterDateTo DATE = CAST(@dateFilterTo AS DATE);



WITH MembershipLineItems AS (
    
    
    
    
    
    
    SELECT
        ft.ID AS FinancialTransactionID,
        ft.CALCULATEDUSERDEFINEDID AS Revenue_ID_legacy__c,
        mli.ID AS LineItemID,
        mli.TRANSACTIONAMOUNT AS MembershipAmount,
        mli.SOURCELINEITEMID
    FROM
        FINANCIALTRANSACTION ft
    INNER JOIN REVENUESPLIT_EXT rse
            ON
        rse.APPLICATION = 'Membership'
    INNER JOIN FINANCIALTRANSACTIONLINEITEM mli
            ON
        mli.ID = rse.ID
        AND mli.FINANCIALTRANSACTIONID = ft.ID
        AND mli.[TYPE] = 'Standard'
),
ResolvedMembershipFinancialTransactions AS (
    SELECT
        mt.ID AS MembershipTransactionID,
        ft.ID AS FinancialTransactionID,
        ft.CALCULATEDUSERDEFINEDID AS Revenue_ID_legacy__c,
        ft.CALCULATEDDATE AS FinancialTransactionDate,
        ft.CONSTITUENTID AS FinancialTransactionConstituentID,
        ROW_NUMBER() OVER (
            PARTITION BY mt.ID
            ORDER BY
                CASE
                    WHEN candidate_line.SOURCELINEITEMID = mt.REVENUESPLITID THEN 0
                    WHEN candidate_line.ID = mt.REVENUESPLITID THEN 1
                    ELSE 2
                END,
                CASE WHEN ft.[TYPE] = 'Refund' THEN 1 ELSE 0 END,
                ft.CALCULATEDDATE DESC,
                candidate_line.DATEADDED DESC,
                ft.ID DESC
        ) AS ResolutionRank
    FROM MEMBERSHIPTRANSACTION mt
    INNER JOIN FINANCIALTRANSACTIONLINEITEM candidate_line
        ON (
            candidate_line.ID = mt.REVENUESPLITID
            OR candidate_line.SOURCELINEITEMID = mt.REVENUESPLITID
        )
       AND candidate_line.[TYPE] = 'Standard'
    INNER JOIN FINANCIALTRANSACTION ft
        ON ft.ID = candidate_line.FINANCIALTRANSACTIONID
),
RecurringInstallments AS (
    SELECT
        RecurringInstallmentID,
        STATUSCODE,
        FinancialTransactionID,
        InstallmentAmount,
        InstallmentDate,
        InstallmentStatus,
        RevenueId
    FROM (
        SELECT
            rgi.ID AS RecurringInstallmentID,
            rgi.STATUSCODE,
            rgi.REVENUEID AS FinancialTransactionID,
            rgi.TRANSACTIONAMOUNT AS InstallmentAmount,
            rgi.[DATE] AS InstallmentDate,
            rgi.STATUS AS InstallmentStatus,
            ft.CALCULATEDUSERDEFINEDID AS RevenueId,
            ROW_NUMBER() OVER (
                PARTITION BY rgi.ID
                ORDER BY
                    CASE WHEN rgp.PAYMENTID IS NULL THEN 1 ELSE 0 END,
                    rgp.PAYMENTID
            ) AS InstallmentPaymentRank
        FROM RECURRINGGIFTINSTALLMENT rgi
        LEFT JOIN RECURRINGGIFTINSTALLMENTPAYMENT rgp
            ON rgi.ID = rgp.RECURRINGGIFTINSTALLMENTID
        LEFT JOIN FINANCIALTRANSACTION ft
            ON ft.ID = rgp.PAYMENTID
    ) recurring_installments
    WHERE InstallmentPaymentRank = 1
),
DonationLineItems AS (
    SELECT
        dli.SOURCELINEITEMID,
        dli.TRANSACTIONAMOUNT AS DonationAmount
    FROM FINANCIALTRANSACTIONLINEITEM dli
    INNER JOIN REVENUESPLIT_EXT drse
        ON drse.ID = dli.ID
       AND drse.APPLICATION = 'Donation'
    WHERE dli.[TYPE] = 'Standard'
),
DiscountLineItems AS (
    SELECT
        xli.SOURCELINEITEMID,
        SUM(xli.TRANSACTIONAMOUNT) AS DiscountAmount
    FROM FINANCIALTRANSACTIONLINEITEM xli
    WHERE xli.[TYPE] = 'Discount'
    GROUP BY xli.SOURCELINEITEMID
),
MembershipTransactionAddOnLineItems AS (
    
    
    SELECT
        ma.MEMBERSHIPTRANSACTIONID,
        SUM(COALESCE(addon_line.TRANSACTIONAMOUNT, 0) - COALESCE(xli.DiscountAmount, 0)) AS AddOnTotal
    FROM MEMBERSHIPADDON ma
    INNER JOIN FINANCIALTRANSACTIONLINEITEM addon_line
        ON addon_line.ID = ma.REVENUESPLITID
       AND addon_line.[TYPE] = 'Standard'
    INNER JOIN REVENUESPLIT_EXT addon_rse
        ON addon_rse.ID = addon_line.ID
       AND addon_rse.APPLICATION = 'Membership add-on'
    LEFT JOIN DiscountLineItems xli
        ON xli.SOURCELINEITEMID = addon_line.ID
    WHERE ma.MEMBERSHIPTRANSACTIONID IS NOT NULL
    GROUP BY ma.MEMBERSHIPTRANSACTIONID
),
SalesOrdersByPayment AS (
    SELECT
        sop.PAYMENTID,
        MIN(sop.SALESORDERID) AS SalesOrderID
    FROM SALESORDERPAYMENT sop
    GROUP BY sop.PAYMENTID
),
RefundedMembershipTransactions AS (
    
    
    
    
    
    
    SELECT
        mt.ID AS MembershipTransactionID
    FROM MEMBERSHIPTRANSACTION mt
    INNER JOIN FINANCIALTRANSACTIONLINEITEM original_line
        ON original_line.ID = mt.REVENUESPLITID
       AND original_line.[TYPE] = 'Standard'
    INNER JOIN FINANCIALTRANSACTIONLINEITEM refund_line
        ON refund_line.SOURCELINEITEMID = mt.REVENUESPLITID
       AND refund_line.[TYPE] = 'Standard'
    INNER JOIN FINANCIALTRANSACTION refund_ft
        ON refund_ft.ID = refund_line.FINANCIALTRANSACTIONID
       AND refund_ft.[TYPE] = 'Refund'
    GROUP BY
        mt.ID,
        original_line.TRANSACTIONAMOUNT
    HAVING
        ABS(SUM(refund_line.TRANSACTIONAMOUNT))
        >= ABS(MAX(original_line.TRANSACTIONAMOUNT))
    UNION
    
    SELECT
        rm.MembershipTransactionID
    FROM (
        SELECT
            mt.ID                          AS MembershipTransactionID,
            mt.REVENUESPLITID              AS RevenueSplitId,
            refund_line.TRANSACTIONAMOUNT  AS RefundAmount,
            ROW_NUMBER() OVER (
                PARTITION BY refund_ft.ID, cim.MEMBERSHIPID
                ORDER BY mt.TRANSACTIONDATE DESC, mt.ID DESC
            ) AS RefundMatchRank
        FROM FINANCIALTRANSACTION refund_ft
        INNER JOIN FINANCIALTRANSACTIONLINEITEM refund_line
            ON refund_line.FINANCIALTRANSACTIONID = refund_ft.ID
           AND refund_line.[TYPE] = 'Standard'
        INNER JOIN CREDITITEMMEMBERSHIP cim
            ON cim.ID = refund_line.SOURCELINEITEMID
            OR cim.ID = refund_line.ID
        INNER JOIN MEMBERSHIPTRANSACTION mt
            ON mt.MEMBERSHIPID = cim.MEMBERSHIPID
           AND mt.TRANSACTIONDATE <= refund_ft.CALCULATEDDATE
        WHERE refund_ft.[TYPE] = 'Refund'
    ) rm
    LEFT JOIN FINANCIALTRANSACTIONLINEITEM original_line
        ON original_line.ID = rm.RevenueSplitId
       AND original_line.[TYPE] = 'Standard'
    WHERE rm.RefundMatchRank = 1
    GROUP BY
        rm.MembershipTransactionID
    HAVING
        ABS(SUM(rm.RefundAmount))
        >= ABS(MAX(ISNULL(original_line.TRANSACTIONAMOUNT, 0)))
),
LatestNoFinancialAnchorLifetimeMembershipTransactions AS (
    
    
    
    SELECT MembershipTransactionID
    FROM (
        SELECT
            mt.ID AS MembershipTransactionID,
            ROW_NUMBER() OVER (
                PARTITION BY m.ID
                ORDER BY mt.TRANSACTIONDATE DESC, mt.ID DESC
            ) AS LifetimeTransactionRank
        FROM MEMBERSHIPTRANSACTION mt
        INNER JOIN MEMBERSHIP m
            ON m.ID = mt.MEMBERSHIPID
        LEFT JOIN SALESORDERITEMMEMBERSHIP no_anchor_soim
            ON no_anchor_soim.MEMBERSHIPTRANSACTIONID = mt.ID
        LEFT JOIN MEMBERSHIPADDON no_anchor_ma
            ON no_anchor_ma.MEMBERSHIPTRANSACTIONID = mt.ID
        LEFT JOIN FINANCIALTRANSACTIONLINEITEM no_anchor_candidate_line
            ON (
                no_anchor_candidate_line.ID = mt.REVENUESPLITID
                OR no_anchor_candidate_line.SOURCELINEITEMID = mt.REVENUESPLITID
            )
           AND no_anchor_candidate_line.[TYPE] = 'Standard'
        LEFT JOIN FINANCIALTRANSACTION no_anchor_ft
            ON no_anchor_ft.ID = no_anchor_candidate_line.FINANCIALTRANSACTIONID
        WHERE
            ISNULL(mt.ACTION, '') <> ('Dr'+'op')
            AND m.STATUSCODE = 0
            AND m.EXPIRATIONDATE IS NULL
            AND no_anchor_soim.ID IS NULL
            AND no_anchor_ma.ID IS NULL
            AND no_anchor_ft.ID IS NULL
    ) ranked_lifetime_memberships
    WHERE LifetimeTransactionRank = 1
),
OrderlessMemberships AS (
    SELECT
        
        
        CONCAT(
            'membership-no-order-pos-',
            CAST(COALESCE(rgi.RecurringInstallmentID, mt.ID) AS NVARCHAR(36))
        ) AS Implementation_External_ID__c,
        CASE
            WHEN rgi.RecurringInstallmentID IS NOT NULL AND rgi.RevenueId IS NULL THEN NULL
            ELSE COALESCE(rgi.RevenueId, rmft.Revenue_ID_legacy__c)
        END AS Revenue_ID_legacy__c,
        COALESCE(
            rgi.InstallmentAmount,
            COALESCE(mli.MembershipAmount, 0)
                + COALESCE(dli.DonationAmount, 0)
                + COALESCE(mt_addon.AddOnTotal, 0)
                - COALESCE(xli.DiscountAmount, 0)
        ) AS Amount,
        COALESCE(mt.DONORID, rmft.FinancialTransactionConstituentID, pmember.CONSTITUENTID) AS ResolvedConstituentID,
        CAST(COALESCE(rgi.InstallmentDate, rmft.FinancialTransactionDate, mt.TRANSACTIONDATE) AS DATE) AS TransactionDate,
        rgi.RecurringInstallmentID AS InstallmentID,
        rgi.STATUSCODE AS InstallmentStatusCode,
        CASE WHEN rmt.MembershipTransactionID IS NOT NULL THEN 1 ELSE 0 END AS IsRefunded,
        
        
        
        
        ROW_NUMBER() OVER (
            PARTITION BY COALESCE(rgi.RecurringInstallmentID, mt.ID)
            ORDER BY rmft.FinancialTransactionID, mt.ID, mli.LineItemID
        ) AS PurchaseRank
    FROM MEMBERSHIPTRANSACTION mt
    INNER JOIN MEMBERSHIP m
        ON mt.MEMBERSHIPID = m.ID
    LEFT JOIN MembershipLineItems mli
        ON mli.LineItemID = mt.REVENUESPLITID
    LEFT JOIN ResolvedMembershipFinancialTransactions rmft
        ON rmft.MembershipTransactionID = mt.ID
       AND rmft.ResolutionRank = 1
    LEFT JOIN RecurringInstallments rgi
        ON rgi.FinancialTransactionID = rmft.FinancialTransactionID
    LEFT JOIN DonationLineItems dli
        ON dli.SOURCELINEITEMID = mli.LineItemID
    LEFT JOIN DiscountLineItems xli
        ON xli.SOURCELINEITEMID = mli.LineItemID
    LEFT JOIN MembershipTransactionAddOnLineItems mt_addon
        ON mt_addon.MEMBERSHIPTRANSACTIONID = mt.ID
    LEFT JOIN LatestNoFinancialAnchorLifetimeMembershipTransactions lna
        ON lna.MembershipTransactionID = mt.ID
    LEFT JOIN RefundedMembershipTransactions rmt
        ON rmt.MembershipTransactionID = mt.ID
    
    
    
    
    
    
    
    
    
    
    
    
    LEFT JOIN SALESORDERITEMMEMBERSHIP soim
        ON mt.ID = soim.MEMBERSHIPTRANSACTIONID
    LEFT JOIN SALESORDERITEM soi
        ON soim.ID = soi.ID
    LEFT JOIN SALESORDER so
        ON soi.SALESORDERID = so.ID
    LEFT JOIN SALESORDER revenue_so
        ON revenue_so.REVENUEID = rmft.FinancialTransactionID
    LEFT JOIN SalesOrdersByPayment sop
        ON sop.PAYMENTID = rmft.FinancialTransactionID
    LEFT JOIN SALESORDER payment_so
        ON payment_so.ID = sop.SalesOrderID
    LEFT JOIN MEMBER pmember
        ON m.ID = pmember.MEMBERSHIPID
       AND pmember.ISPRIMARY = 1
       AND pmember.ISDROPPED = 0
    WHERE
        ISNULL(mt.ACTION, '') <> ('Dr'+'op')
        AND COALESCE(so.ID, revenue_so.ID, payment_so.ID) IS NULL
        
        AND (
            mli.LineItemID IS NOT NULL
            OR rmft.FinancialTransactionID IS NOT NULL
            OR rgi.RecurringInstallmentID IS NOT NULL
            OR lna.MembershipTransactionID IS NOT NULL
            OR EXISTS (
                SELECT 1 FROM MEMBERSHIPADDON ma
                WHERE ma.MEMBERSHIPTRANSACTIONID = mt.ID
            )
        )
        AND (
            @useDateFrom = 0
            OR CAST(COALESCE(rgi.InstallmentDate, rmft.FinancialTransactionDate, mt.TRANSACTIONDATE) AS DATE) >= @filterDateFrom
        )
        AND (
            @useDateTo = 0
            OR CAST(COALESCE(rgi.InstallmentDate, rmft.FinancialTransactionDate, mt.TRANSACTIONDATE) AS DATE) <= @filterDateTo
        )
)
SELECT COUNT(*) AS emitted_rows,
  COUNT(DISTINCT om.Implementation_External_ID__c) AS distinct_keys,
  SUM(CASE WHEN om.Implementation_External_ID__c LIKE 'membership-no-order-pos-%' THEN 1 ELSE 0 END) AS prefixed_rows,
  SUM(CASE WHEN om.Implementation_External_ID__c IS NULL THEN 1 ELSE 0 END) AS null_keys
FROM OrderlessMemberships om
LEFT JOIN CONSTITUENT c
    ON c.ID = om.ResolvedConstituentID
LEFT JOIN CONSTITUENTHOUSEHOLD chh
    ON chh.ID = om.ResolvedConstituentID
WHERE om.PurchaseRank = 1;
