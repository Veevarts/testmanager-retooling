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
        mli.ID AS LineItemID,
        mli.TRANSACTIONAMOUNT AS Amount,
        mli.SOURCELINEITEMID,
        rse.APPLICATION
FROM
        FINANCIALTRANSACTIONLINEITEM mli
INNER JOIN REVENUESPLIT_EXT rse
        ON
        rse.ID = mli.ID
        AND rse.APPLICATION IN ('Membership','Membership add-on')
WHERE
        mli.[TYPE] = 'Standard'
),
ResolvedMembershipFinancialTransactions AS (
SELECT
        mli.LineItemID AS SourceLineItemID,
        ft.ID AS FinancialTransactionID,
        ft.CALCULATEDUSERDEFINEDID AS Revenue_ID_legacy__c,
        ft.CALCULATEDDATE AS FinancialTransactionDate,
        ROW_NUMBER() OVER (
            PARTITION BY mli.LineItemID
            ORDER BY
                CASE
                    WHEN candidate_line.SOURCELINEITEMID = mli.LineItemID THEN 0
                    WHEN candidate_line.ID = mli.LineItemID THEN 1
                    ELSE 2
                END,
                CASE
                    WHEN ft.[TYPE] = 'Refund' THEN 1
                    ELSE 0
                END,
                ft.CALCULATEDDATE DESC,
                candidate_line.DATEADDED DESC,
                ft.ID DESC
        ) AS ResolutionRank
FROM
        MembershipLineItems mli
INNER JOIN FINANCIALTRANSACTIONLINEITEM candidate_line
        ON (
            candidate_line.ID = mli.LineItemID
            OR candidate_line.SOURCELINEITEMID = mli.LineItemID
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
	FROM
		RECURRINGGIFTINSTALLMENT rgi
	LEFT JOIN RECURRINGGIFTINSTALLMENTPAYMENT rgp ON
		rgi.ID = rgp.RECURRINGGIFTINSTALLMENTID
	LEFT JOIN FINANCIALTRANSACTION ft ON
		ft.ID = rgp.PAYMENTID
) recurring_installments
WHERE
	InstallmentPaymentRank = 1
),
DiscountLineItems AS (
SELECT
        xli.SOURCELINEITEMID,
        SUM(xli.TRANSACTIONAMOUNT) AS DiscountAmount
FROM
        FINANCIALTRANSACTIONLINEITEM xli
WHERE
        xli.[TYPE] = 'Discount'
GROUP BY xli.SOURCELINEITEMID
),
SalesOrdersByPayment AS (
SELECT
        sop.PAYMENTID,
        MIN(sop.SALESORDERID) AS SalesOrderID
FROM
        SALESORDERPAYMENT sop
GROUP BY
        sop.PAYMENTID
),
OrderBackedMembershipFinancialCandidates AS (
SELECT
        soim.ID AS OrderMembershipItemID,
        so.ID AS SalesOrderID,
        so.STATUSCODE AS SalesOrderStatusCode,
        ft.ID AS FinancialTransactionID,
        source_line.ID AS MembershipLineItemID,
        ROW_NUMBER() OVER (
            PARTITION BY soim.ID
            ORDER BY
                CASE WHEN candidate.SourceType = 'Payment' THEN 0 ELSE 1 END,
                ft.CALCULATEDDATE DESC,
                ft.ID DESC
        ) AS ResolutionRank
FROM (
        SELECT
                soim.ID AS OrderMembershipItemID,
                so.ID AS SalesOrderID,
                so.REVENUEID AS FinancialTransactionID,
                'Order' AS SourceType
        FROM
                SALESORDERITEMMEMBERSHIP soim
        INNER JOIN SALESORDERITEM soi
            ON soi.ID = soim.ID
        INNER JOIN SALESORDER so
            ON so.ID = soi.SALESORDERID
        WHERE
                soim.MEMBERSHIPTRANSACTIONID IS NULL
                AND so.REVENUEID IS NOT NULL
        UNION ALL
        SELECT
                soim.ID AS OrderMembershipItemID,
                so.ID AS SalesOrderID,
                sop.PAYMENTID AS FinancialTransactionID,
                'Payment' AS SourceType
        FROM
                SALESORDERITEMMEMBERSHIP soim
        INNER JOIN SALESORDERITEM soi
            ON soi.ID = soim.ID
        INNER JOIN SALESORDER so
            ON so.ID = soi.SALESORDERID
        INNER JOIN SALESORDERPAYMENT sop
            ON sop.SALESORDERID = so.ID
        WHERE
                soim.MEMBERSHIPTRANSACTIONID IS NULL
) candidate
INNER JOIN SALESORDERITEMMEMBERSHIP soim
    ON soim.ID = candidate.OrderMembershipItemID
INNER JOIN SALESORDER so
    ON so.ID = candidate.SalesOrderID
INNER JOIN FINANCIALTRANSACTION ft
    ON ft.ID = candidate.FinancialTransactionID
INNER JOIN FINANCIALTRANSACTIONLINEITEM ftli
    ON ftli.FINANCIALTRANSACTIONID = ft.ID
   AND ftli.[TYPE] = 'Standard'
INNER JOIN FINANCIALTRANSACTIONLINEITEM source_line
    ON source_line.ID = COALESCE(ftli.SOURCELINEITEMID, ftli.ID)
INNER JOIN REVENUESPLIT_EXT source_rse
    ON source_rse.ID = source_line.ID
   AND source_rse.APPLICATION = 'Membership'
),
OrderBackedMembershipFinancialTransactions AS (
SELECT
        *
FROM
        OrderBackedMembershipFinancialCandidates
WHERE
        ResolutionRank = 1
),
SplitReceiptingDonationLines AS (







SELECT
        dli.ID AS LineItemID,
        dli.TRANSACTIONAMOUNT AS Amount,
        dli.SOURCELINEITEMID,
        rse.DESIGNATIONID
FROM
        FINANCIALTRANSACTIONLINEITEM dli
INNER JOIN REVENUESPLIT_EXT rse
        ON rse.ID = dli.ID
       AND rse.APPLICATION = 'Donation'
INNER JOIN FINANCIALTRANSACTIONLINEITEM source_membership_line
        ON source_membership_line.ID = dli.SOURCELINEITEMID
       AND source_membership_line.[TYPE] = 'Standard'
INNER JOIN REVENUESPLIT_EXT source_membership_rse
        ON source_membership_rse.ID = source_membership_line.ID
       AND source_membership_rse.APPLICATION = 'Membership'
WHERE
        dli.[TYPE] = 'Standard'
)
SELECT COUNT(*) AS fa_rows,
  SUM(CASE WHEN q.vnfp__Opportunity_POS_Purchase__c IS NULL THEN 1 ELSE 0 END) AS fa_pos_null,
  SUM(CASE WHEN q.vnfp__Opportunity_POS_Purchase__c IS NOT NULL THEN 1 ELSE 0 END) AS fa_pos_real
FROM (
SELECT
    COALESCE(rgi.RecurringInstallmentID, mli.LineItemID) AS Implementation_External_ID__c,
    COALESCE(rgi.RevenueId, rmft.Revenue_ID_legacy__c) AS Revenue_ID_legacy__c,
    CASE 
	    WHEN mli.APPLICATION = 'Membership' THEN 'Membership_Fund'
	    WHEN mli.APPLICATION = 'Membership add-on' THEN 'Add_On_Fund'
	    ELSE CAST(source_rse.DESIGNATIONID AS VARCHAR(36))
	END AS Auctifera__Specific_Fund__c,
    'Posted' AS Auctifera__Accounting_Status__c,
    'Succeeded' AS Auctifera__Status__c,
    CASE WHEN rgi.RecurringInstallmentID IS NOT NULL
         THEN rgi.InstallmentAmount
         ELSE mli.Amount - COALESCE(xli.DiscountAmount, 0)
    END AS Auctifera__Donated_Amount__c,
    CAST(COALESCE(rgi.InstallmentDate, rmft.FinancialTransactionDate) AS DATE) AS Auctifera__Posted_Date__c,
    'Acknowledged' AS vnfp__Acknowledgment_Status__c,
    CAST(COALESCE(rgi.RecurringInstallmentID, mt.ID, ma.MEMBERSHIPTRANSACTIONID, order_membership.OrderMembershipItemID) AS VARCHAR(36)) AS vnfp__Opportunity__c,
    COALESCE(so.ID, addon_so.ID, revenue_so.ID, payment_so.ID) AS vnfp__Opportunity_POS_Purchase__c
FROM
        MembershipLineItems mli
INNER JOIN REVENUESPLIT_EXT source_rse
    ON source_rse.ID = mli.LineItemID
LEFT JOIN DESIGNATION d
    ON source_rse.DESIGNATIONID = d.ID
LEFT JOIN ResolvedMembershipFinancialTransactions rmft
    ON
        rmft.SourceLineItemID = mli.LineItemID
        AND rmft.ResolutionRank = 1
LEFT JOIN RecurringInstallments rgi
    ON
	rgi.FinancialTransactionID = rmft.FinancialTransactionID
LEFT JOIN DiscountLineItems xli
    ON
        xli.SOURCELINEITEMID = mli.LineItemID
LEFT JOIN MEMBERSHIPTRANSACTION mt
    ON mt.REVENUESPLITID = mli.LineItemID
   
   
   
   
   AND ISNULL(mt.ACTION, '') <> ('Dr'+'op')
LEFT JOIN MEMBERSHIPADDON ma
    ON ma.REVENUESPLITID = mli.LineItemID
LEFT JOIN MEMBERSHIP m
    ON
        m.ID = COALESCE(mt.MEMBERSHIPID, ma.MEMBERSHIPID)
LEFT JOIN SALESORDERITEMMEMBERSHIP soim
    ON
        mt.ID = soim.MEMBERSHIPTRANSACTIONID
LEFT JOIN SALESORDERITEMMEMBERSHIPADDON soima
    ON
        ma.ID = soima.MEMBERSHIPADDONID
LEFT JOIN SALESORDERITEM soi
    ON
        soim.ID = soi.ID
LEFT JOIN SALESORDERITEM addon_soi
    ON
        soima.ID = addon_soi.ID
LEFT JOIN SALESORDER so
    ON
        soi.SALESORDERID = so.ID
LEFT JOIN SALESORDER addon_so
    ON
        addon_soi.SALESORDERID = addon_so.ID
LEFT JOIN SALESORDER revenue_so
    ON
        revenue_so.REVENUEID = rmft.FinancialTransactionID
LEFT JOIN SalesOrdersByPayment sop
    ON
        sop.PAYMENTID = rmft.FinancialTransactionID
LEFT JOIN SALESORDER payment_so
    ON
        payment_so.ID = sop.SalesOrderID
LEFT JOIN OrderBackedMembershipFinancialTransactions order_membership
    ON
        order_membership.MembershipLineItemID = mli.LineItemID
        AND order_membership.SalesOrderID = COALESCE(so.ID, addon_so.ID, revenue_so.ID, payment_so.ID)
WHERE
        COALESCE(rgi.RecurringInstallmentID, mt.ID, ma.MEMBERSHIPTRANSACTIONID, order_membership.OrderMembershipItemID) IS NOT NULL
        AND (
            COALESCE(so.ID, addon_so.ID, revenue_so.ID, payment_so.ID, order_membership.SalesOrderID) IS NULL
            OR COALESCE(so.STATUSCODE, addon_so.STATUSCODE, revenue_so.STATUSCODE, payment_so.STATUSCODE, order_membership.SalesOrderStatusCode) NOT IN (0, 6, 7)
        )
        
        
        
        
        
        
        
        
        
        AND (
            @useDateFrom = 0
            OR CAST(COALESCE(rgi.InstallmentDate, rmft.FinancialTransactionDate, mt.TRANSACTIONDATE) AS DATE) >= @filterDateFrom
        )
        AND (
            @useDateTo = 0
            OR CAST(COALESCE(rgi.InstallmentDate, rmft.FinancialTransactionDate, mt.TRANSACTIONDATE) AS DATE) <= @filterDateTo
        )
UNION ALL


















SELECT
    ranked.LineItemID AS Implementation_External_ID__c,
    ranked.Revenue_ID_legacy__c,
    CAST(ranked.DESIGNATIONID AS VARCHAR(36)) AS Auctifera__Specific_Fund__c,
    'Posted' AS Auctifera__Accounting_Status__c,
    'Succeeded' AS Auctifera__Status__c,
    ranked.Amount AS Auctifera__Donated_Amount__c,
    CAST(ranked.PostedDate AS DATE) AS Auctifera__Posted_Date__c,
    'Acknowledged' AS vnfp__Acknowledgment_Status__c,
    CAST(ranked.OpportunityKey AS VARCHAR(36)) AS vnfp__Opportunity__c,
    ranked.ResolvedSalesOrderID AS vnfp__Opportunity_POS_Purchase__c
FROM (
    SELECT
        srdli.LineItemID,
        srdli.Amount,
        srdli.DESIGNATIONID,
        COALESCE(rgi.RevenueId, rmft.Revenue_ID_legacy__c) AS Revenue_ID_legacy__c,
        COALESCE(rgi.InstallmentDate, rmft.FinancialTransactionDate, mt.TRANSACTIONDATE) AS PostedDate,
        COALESCE(rgi.RecurringInstallmentID, mt.ID) AS OpportunityKey,
        COALESCE(so.ID, revenue_so.ID, payment_so.ID) AS ResolvedSalesOrderID,
        COALESCE(so.STATUSCODE, revenue_so.STATUSCODE, payment_so.STATUSCODE) AS ResolvedSalesOrderStatusCode,
        ROW_NUMBER() OVER (
            PARTITION BY srdli.LineItemID
            ORDER BY
                mt.TRANSACTIONDATE DESC,
                mt.ID DESC,
                rgi.RecurringInstallmentID
        ) AS SplitReceiptingRank
    FROM
            SplitReceiptingDonationLines srdli
    INNER JOIN MEMBERSHIPTRANSACTION mt
        ON mt.REVENUESPLITID = srdli.SOURCELINEITEMID
       AND ISNULL(mt.ACTION, '') <> ('Dr'+'op')
    LEFT JOIN ResolvedMembershipFinancialTransactions rmft
        ON rmft.SourceLineItemID = srdli.SOURCELINEITEMID
       AND rmft.ResolutionRank = 1
    LEFT JOIN RecurringInstallments rgi
        ON rgi.FinancialTransactionID = rmft.FinancialTransactionID
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
) ranked
WHERE
        ranked.SplitReceiptingRank = 1
        
        
        
        
        
        AND (
            ranked.ResolvedSalesOrderID IS NULL
            OR ranked.ResolvedSalesOrderStatusCode NOT IN (0, 6, 7)
        )
        AND (
            @useDateFrom = 0
            OR CAST(ranked.PostedDate AS DATE) >= @filterDateFrom
        )
        AND (
            @useDateTo = 0
            OR CAST(ranked.PostedDate AS DATE) <= @filterDateTo
        )
) q;