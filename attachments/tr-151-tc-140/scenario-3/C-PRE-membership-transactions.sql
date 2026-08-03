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
            CASE
                WHEN ft.[TYPE] = 'Refund' THEN 1
                ELSE 0
            END,
            ft.CALCULATEDDATE DESC,
            candidate_line.DATEADDED DESC,
            ft.ID DESC
    ) AS ResolutionRank
FROM
	MEMBERSHIPTRANSACTION mt
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
DonationLineItems AS (
SELECT
	dli.SOURCELINEITEMID,
	dli.TRANSACTIONAMOUNT AS DonationAmount
FROM
	FINANCIALTRANSACTIONLINEITEM dli
INNER JOIN REVENUESPLIT_EXT drse
        ON
	drse.ID = dli.ID
	AND drse.APPLICATION = 'Donation'
WHERE
	dli.[TYPE] = 'Standard'
),
DiscountLineItems AS (
SELECT
	xli.SOURCELINEITEMID,
	SUM(xli.TRANSACTIONAMOUNT) AS DiscountAmount
FROM
	FINANCIALTRANSACTIONLINEITEM xli
WHERE
	xli.[TYPE] = 'Discount'
GROUP BY
	xli.SOURCELINEITEMID
),
SalesOrderAddOnLineItems AS (
SELECT
	soi.SALESORDERID,
	SUM(COALESCE(soi.QUANTITY, 0)) AS AddOnQuantity,
	SUM(COALESCE(soi.TOTAL, 0)) AS AddOnTotal
FROM
	SALESORDERITEM soi
WHERE
	soi.[TYPE] = 'Membership add-on'
GROUP BY
	soi.SALESORDERID
),
MembershipTransactionAddOnLineItems AS (




SELECT
	ma.MEMBERSHIPTRANSACTIONID,
	SUM(COALESCE(ma.QUANTITY, 0)) AS AddOnQuantity,
	SUM(COALESCE(addon_line.TRANSACTIONAMOUNT, 0) - COALESCE(xli.DiscountAmount, 0)) AS AddOnTotal
FROM
	MEMBERSHIPADDON ma
INNER JOIN FINANCIALTRANSACTIONLINEITEM addon_line
    ON addon_line.ID = ma.REVENUESPLITID
   AND addon_line.[TYPE] = 'Standard'
INNER JOIN REVENUESPLIT_EXT addon_rse
    ON addon_rse.ID = addon_line.ID
   AND addon_rse.APPLICATION = 'Membership add-on'
LEFT JOIN DiscountLineItems xli
    ON xli.SOURCELINEITEMID = addon_line.ID
WHERE
	ma.MEMBERSHIPTRANSACTIONID IS NOT NULL
GROUP BY
	ma.MEMBERSHIPTRANSACTIONID
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
CreditPaymentPerRefund AS (
SELECT
	cp.CREDITID,
	MIN(cp.REVENUEID) AS OriginalPaymentTransactionId
FROM
	CREDITPAYMENT cp
GROUP BY
	cp.CREDITID
),
RefundedSalesOrders AS (




SELECT
	rso_base.SalesOrderID
FROM (
	SELECT
		COALESCE(original_so.ID, payment_so.ID, refund_so.ID) AS SalesOrderID,
		refund_ft.TRANSACTIONAMOUNT                           AS RefundAmount,
		COALESCE(original_so.AMOUNT, payment_so.AMOUNT, refund_so.AMOUNT)
		                                                      AS SalesOrderAmount
	FROM
		FINANCIALTRANSACTION refund_ft
	INNER JOIN CreditPaymentPerRefund cp
	    ON cp.CREDITID = refund_ft.ID
	LEFT JOIN SALESORDER original_so
	    ON original_so.REVENUEID = cp.OriginalPaymentTransactionId
	LEFT JOIN SalesOrdersByPayment refund_sop
	    ON refund_sop.PAYMENTID = cp.OriginalPaymentTransactionId
	LEFT JOIN SALESORDER payment_so
	    ON payment_so.ID = refund_sop.SalesOrderID
	LEFT JOIN SALESORDER refund_so
	    ON refund_so.REVENUEID = refund_ft.ID
	WHERE
		refund_ft.[TYPE] = 'Refund'
		AND COALESCE(original_so.ID, payment_so.ID, refund_so.ID) IS NOT NULL
) rso_base
GROUP BY
	rso_base.SalesOrderID
HAVING
	ABS(SUM(rso_base.RefundAmount))
	>= ABS(MAX(ISNULL(rso_base.SalesOrderAmount, 0)))
),
RefundedMembershipTransactions AS (





SELECT
	mt.ID AS MembershipTransactionID
FROM
	MEMBERSHIPTRANSACTION mt
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
	FROM
		FINANCIALTRANSACTION refund_ft
	INNER JOIN FINANCIALTRANSACTIONLINEITEM refund_line
        ON refund_line.FINANCIALTRANSACTIONID = refund_ft.ID
       AND refund_line.[TYPE] = 'Standard'
	INNER JOIN CREDITITEMMEMBERSHIP cim
        ON cim.ID = refund_line.SOURCELINEITEMID
        OR cim.ID = refund_line.ID
	INNER JOIN MEMBERSHIPTRANSACTION mt
        ON mt.MEMBERSHIPID = cim.MEMBERSHIPID
       AND mt.TRANSACTIONDATE <= refund_ft.CALCULATEDDATE
	WHERE
		refund_ft.[TYPE] = 'Refund'
) rm
LEFT JOIN FINANCIALTRANSACTIONLINEITEM original_line
    ON original_line.ID = rm.RevenueSplitId
   AND original_line.[TYPE] = 'Standard'
WHERE
	rm.RefundMatchRank = 1
GROUP BY
	rm.MembershipTransactionID
HAVING
	ABS(SUM(rm.RefundAmount))
	>= ABS(MAX(ISNULL(original_line.TRANSACTIONAMOUNT, 0)))
),
OrderBackedMembershipFinancialCandidates AS (
SELECT
	soim.ID AS OrderMembershipItemID,
	so.ID AS SalesOrderID,
	so.LOOKUPID AS SalesOrderLookupID,
	so.STATUSCODE AS SalesOrderStatusCode,
	so.REFUNDSTATUS AS SalesOrderRefundStatus,
	so.CONSTITUENTID AS SalesOrderConstituentID,
	so.TRANSACTIONDATE AS SalesOrderTransactionDate,
	soim.MEMBERSHIPID,
	soim.MEMBERSHIPPROGRAMID,
	soim.MEMBERSHIPLEVELID,
	soim.MEMBERSHIPLEVELTERMID,
	soim.MEMBERSHIPLEVELTYPECODEID,
	soim.EXPIRATIONDATE,
	soim.GIVENBYID,
	soim.GIFTDELIVERYCODE,
	soim.GIFTMESSAGE,
	soi.DESCRIPTION AS SalesOrderItemDescription,
	ft.ID AS FinancialTransactionID,
	ft.CALCULATEDUSERDEFINEDID AS Revenue_ID_legacy__c,
	ft.CALCULATEDDATE AS FinancialTransactionDate,
	ft.CONSTITUENTID AS FinancialTransactionConstituentID,
	source_line.ID AS MembershipLineItemID,
	source_line.TRANSACTIONAMOUNT AS MembershipAmount,
	ROW_NUMBER() OVER (
        PARTITION BY soim.ID
        ORDER BY
            CASE WHEN candidate.SourceType = 'Payment' THEN 0 ELSE 1 END,
            ft.CALCULATEDDATE DESC,
            ft.ID DESC
    ) AS ResolutionRank
FROM (
    SELECT soim.ID AS OrderMembershipItemID, so.ID AS SalesOrderID, so.REVENUEID AS FinancialTransactionID, 'Order' AS SourceType
	FROM SALESORDERITEMMEMBERSHIP soim
    INNER JOIN SALESORDERITEM soi
        ON soi.ID = soim.ID
	INNER JOIN SALESORDER so
	    ON so.ID = soi.SALESORDERID
	WHERE soim.MEMBERSHIPTRANSACTIONID IS NULL
	  AND so.REVENUEID IS NOT NULL
	UNION ALL
	SELECT soim.ID AS OrderMembershipItemID, so.ID AS SalesOrderID, sop.PAYMENTID AS FinancialTransactionID, 'Payment' AS SourceType
	FROM SALESORDERITEMMEMBERSHIP soim
    INNER JOIN SALESORDERITEM soi
        ON soi.ID = soim.ID
	INNER JOIN SALESORDER so
	    ON so.ID = soi.SALESORDERID
	INNER JOIN SALESORDERPAYMENT sop
	    ON sop.SALESORDERID = so.ID
	WHERE soim.MEMBERSHIPTRANSACTIONID IS NULL
) candidate
INNER JOIN SALESORDERITEMMEMBERSHIP soim
    ON soim.ID = candidate.OrderMembershipItemID
INNER JOIN SALESORDER so
    ON so.ID = candidate.SalesOrderID
INNER JOIN SALESORDERITEM soi
    ON soi.ID = soim.ID
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
PositiveMembershipTransactions AS (
SELECT
	mt.ID AS MembershipTransactionID,
	mt.MEMBERSHIPID,
	mt.TRANSACTIONDATE
FROM
	MEMBERSHIPTRANSACTION mt
WHERE
	ISNULL(mt.ACTION, '') <> ('Dr'+'op')
),
DropTransactions AS (
SELECT
	mt.ID AS DropTransactionID,
	mt.MEMBERSHIPID,
	mt.TRANSACTIONDATE AS DropTransactionDate
FROM
	MEMBERSHIPTRANSACTION mt
WHERE
	mt.ACTION = ('Dr'+'op')
),
MatchedDropTransactions AS (
SELECT
	pmt.MembershipTransactionID,
	dt.DropTransactionDate,
	ROW_NUMBER() OVER (
        PARTITION BY dt.DropTransactionID
        ORDER BY pmt.TRANSACTIONDATE DESC, pmt.MembershipTransactionID DESC
    ) AS DropMatchRank
FROM
	DropTransactions dt
INNER JOIN PositiveMembershipTransactions pmt
        ON pmt.MEMBERSHIPID = dt.MEMBERSHIPID
	AND pmt.TRANSACTIONDATE <= dt.DropTransactionDate
),
DropTransactionsByPositiveMembership AS (
SELECT
	mdt.MembershipTransactionID,
	MAX(mdt.DropTransactionDate) AS DropTransactionDate
FROM
	MatchedDropTransactions mdt
WHERE
	mdt.DropMatchRank = 1
GROUP BY
	mdt.MembershipTransactionID
),
LatestNoFinancialAnchorLifetimeMembershipTransactions AS (





SELECT
	MembershipTransactionID
FROM (
	SELECT
		mt.ID AS MembershipTransactionID,
		ROW_NUMBER() OVER (
			PARTITION BY m.ID
			ORDER BY mt.TRANSACTIONDATE DESC, mt.ID DESC
		) AS LifetimeTransactionRank
	FROM
		MEMBERSHIPTRANSACTION mt
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
WHERE
	LifetimeTransactionRank = 1
)
SELECT COUNT(*) AS total_opportunities,
  SUM(CASE WHEN q.vnfp__POS_Purchase__c IS NULL THEN 1 ELSE 0 END) AS pos_null,
  SUM(CASE WHEN CAST(q.vnfp__POS_Purchase__c AS NVARCHAR(100)) LIKE 'membership-no-order-pos-%' THEN 1 ELSE 0 END) AS pos_synthetic,
  SUM(CASE WHEN q.vnfp__POS_Purchase__c IS NOT NULL
            AND CAST(q.vnfp__POS_Purchase__c AS NVARCHAR(100)) NOT LIKE 'membership-no-order-pos-%' THEN 1 ELSE 0 END) AS pos_real,
  COUNT(DISTINCT CAST(q.vnfp__POS_Purchase__c AS NVARCHAR(100))) AS distinct_pos_values
FROM (
SELECT
	COALESCE(rgi.RecurringInstallmentID, mt.ID) AS vnfp__Implementation_External_ID__c,
	
	CASE
		WHEN rgi.RecurringInstallmentID IS NOT NULL AND rgi.RevenueId IS NULL THEN NULL
		ELSE COALESCE(rgi.RevenueId, rmft.Revenue_ID_legacy__c)
	END AS Revenue_ID_legacy__c,
	'{{MEMBERSHIP_RECORDTYPE_ID}}' AS RecordTypeId,
	CONCAT('Membership - ', ml.NAME, ' - ', CAST(COALESCE(rgi.InstallmentDate, mt.TRANSACTIONDATE) AS DATE)) AS Name,
	CASE
		WHEN mt.ACTION LIKE 'Upgrade%' THEN 'Upgraded'
		WHEN mt.ACTION LIKE 'Downgrade%' THEN 'Downgraded'
		ELSE 'Equal'
	END AS Membership_Upgraded_Downgraded__c,
	CASE
		WHEN mt.ACTION LIKE 'Renew%' THEN 'Renewal'
		WHEN mt.ACTION LIKE 'Reacquire%' OR mt.ACTION LIKE 'Rejoin%' THEN 'Reacquire'
		ELSE 'New'
	END AS npe01__Membership_Origin__c,
	CASE
		WHEN pmc.ID IS NOT NULL
		AND pmc.ISORGANIZATION = 0
		AND pmc.ISGROUP = 0
		AND pmc.ISCONSTITUENT = 1
		THEN pmc.ID
		ELSE NULL
	END AS vnfp__Member__c,
	COALESCE(
	    CASE 
	        WHEN giver.ID IS NOT NULL AND giver.ISORGANIZATION = 0 AND giver.ISGROUP = 0 AND giver.ISCONSTITUENT = 1 
	        THEN giver.ID 
	        ELSE NULL 
	    END,
	    CASE 
	        WHEN donor.ID IS NOT NULL AND donor.ISORGANIZATION = 0 AND donor.ISGROUP = 0 AND donor.ISCONSTITUENT = 1 
	        THEN donor.ID 
	        ELSE NULL 
	    END,
	    CASE 
	        WHEN ftc.ID IS NOT NULL AND ftc.ISORGANIZATION = 0 AND ftc.ISGROUP = 0 AND ftc.ISCONSTITUENT = 1 
	        THEN ftc.ID 
	        ELSE NULL 
	    END,
	    CASE 
	        WHEN pmc.ID IS NOT NULL AND pmc.ISORGANIZATION = 0 AND pmc.ISGROUP = 0 AND pmc.ISCONSTITUENT = 1 
	        THEN pmc.ID 
	        ELSE NULL 
	    END
	) AS npsp__Primary_Contact__c,
	CASE
		WHEN (primaryC.ISCONSTITUENT = 1
			AND primaryC.ISORGANIZATION = 0
			AND primaryC.ISGROUP = 0)
     THEN COALESCE(chh.HOUSEHOLDID, NULL)
		WHEN primaryC.ISORGANIZATION = 1
     THEN primaryC.ID
		ELSE NULL
	END AS AccountId,
	CAST(
		CASE
			WHEN rgi.RecurringInstallmentID IS NOT NULL
				THEN COALESCE(rgi.InstallmentDate, rmft.FinancialTransactionDate, mt.TRANSACTIONDATE)
			ELSE COALESCE(rmft.FinancialTransactionDate, mt.TRANSACTIONDATE)
		END
	AS DATE) AS CloseDate,
	CAST(COALESCE(rgi.InstallmentDate, mt.TRANSACTIONDATE) AS DATE) AS npe01__Membership_Start_Date__c,
	CAST(
		CASE
			WHEN m.EXPIRATIONDATE IS NULL
				THEN DATEADD(YEAR, 100, COALESCE(rgi.InstallmentDate, mt.TRANSACTIONDATE))
			ELSE mt.EXPIRATIONDATE
		END
	AS DATE) AS npe01__Membership_End_Date__c,
	COALESCE(mt.GIFTMESSAGE, soim.GIFTMESSAGE) AS vnfp__Gift_Message__c,
	
	
	
	
	
	COALESCE(mt.COMMENTS, re.REFERENCE) AS Description,
	re.REFERENCE AS Revenue_Reference__c,
	CASE
		WHEN rgi.RecurringInstallmentID IS NOT NULL THEN
            CASE
			rgi.STATUSCODE
			WHEN 0 THEN 'Pledged'
			WHEN 1 THEN 'Closed Lost'
			WHEN 2 THEN 'Closed Won'
			WHEN 3 THEN 'Closed Lost'
			WHEN 4 THEN 'Closed Lost'
			ELSE 'Pledged'
		END
		WHEN mt.ACTION = ('Dr'+'op') THEN 'Closed Lost'
		WHEN rso.SalesOrderID IS NOT NULL THEN 'Closed Lost'
		WHEN rmt.MembershipTransactionID IS NOT NULL THEN 'Closed Lost'
		WHEN COALESCE(so.REFUNDSTATUS, revenue_so.REFUNDSTATUS, payment_so.REFUNDSTATUS) = 2 THEN 'Closed Lost'
		ELSE
		
            CASE
			WHEN COALESCE(so.ID, revenue_so.ID, payment_so.ID) IS NULL THEN 'Closed Won'
			WHEN COALESCE(so.STATUSCODE, revenue_so.STATUSCODE, payment_so.STATUSCODE) IN (1, 3, 4) THEN 'Closed Won'
			WHEN COALESCE(so.STATUSCODE, revenue_so.STATUSCODE, payment_so.STATUSCODE) IN (5) THEN 'Closed Lost'
			WHEN COALESCE(so.STATUSCODE, revenue_so.STATUSCODE, payment_so.STATUSCODE) IN (0, 2, 6, 7) THEN 'Prospecting'
			ELSE 'Prospecting'
		END
	END AS StageName,
	COALESCE(
    rgi.InstallmentAmount,
    COALESCE(mli.MembershipAmount, 0)
        + COALESCE(dli.DonationAmount, 0)
        + COALESCE(so_addon.AddOnTotal, mt_addon.AddOnTotal, 0)
        - COALESCE(xli.DiscountAmount, 0)
) AS Amount,
	dli.DonationAmount AS vnfp__Split_Receipting_Donation_Amount__c,
	CASE
		WHEN dli.DonationAmount IS NOT NULL THEN mli.MembershipAmount
		ELSE NULL
	END AS vnfp__Split_Receipting_Membership_Amount__c,
	CASE
		WHEN dli.DonationAmount IS NOT NULL THEN mli.MembershipAmount
		ELSE NULL
	END AS vnfp__Split_Receipting_Membership_Subtotal__c,
	CASE
		WHEN dli.DonationAmount IS NOT NULL THEN 1
		ELSE 0
	END AS vnfp__Split_Receipting__c,
	COALESCE(so_addon.AddOnQuantity, mt_addon.AddOnQuantity) AS Add_On_Quantity__c,
	COALESCE(so_addon.AddOnTotal, mt_addon.AddOnTotal) AS Add_On_Total__c,
	xli.DiscountAmount * -1 AS vnfp__Discount_Amount__c,
	mlt.AMOUNT AS vnfp__Membership_Price__c,
	
	
	
	
	
	
	
	
	
	CAST(mlt.LEVELID AS VARCHAR(36)) + '-' + CAST(mlt.ID AS VARCHAR(36)) AS vnfp__Membership_Program__c,
	CAST(COALESCE(rgi.InstallmentDate, mt.TRANSACTIONDATE) AS DATE) AS npsp__Acknowledgment_Date__c,
	'Acknowledged' AS npsp__Acknowledgment_Status__c,
	CASE
		WHEN soim.GIFTDELIVERYCODE = 0 THEN 'Member'
		WHEN soim.GIFTDELIVERYCODE = 1 THEN 'Buyer'
		ELSE NULL
	END AS vnfp__Deliver_Membership_To__c,
	CASE
		WHEN mt.UPGRADEMETHODCODE = 2 THEN 1
		ELSE 0
	END AS vnfp__Midterm_Upgrade__c,
	COALESCE(so.ID, revenue_so.ID, payment_so.ID) AS vnfp__POS_Purchase__c,
	prog.NAME AS Program_Name__c,
	primaryC.ISORGANIZATION AS vnfp__Corporate_Membership__c,
	re.GIVENANONYMOUSLY AS Given_Anonymously__c,
	CASE
		WHEN rgi.RecurringInstallmentID IS NOT NULL THEN rmft.FinancialTransactionID
		ELSE NULL
	END AS npe03__Recurring_Donation__c
FROM
	MEMBERSHIPTRANSACTION mt
INNER JOIN MEMBERSHIP m
    ON
	mt.MEMBERSHIPID = m.ID
LEFT JOIN MembershipLineItems mli
    ON
	mli.LineItemID = mt.REVENUESPLITID
LEFT JOIN ResolvedMembershipFinancialTransactions rmft
    ON
	rmft.MembershipTransactionID = mt.ID
	AND rmft.ResolutionRank = 1
LEFT JOIN REVENUE_EXT re
    ON re.ID = rmft.FinancialTransactionID
LEFT JOIN RecurringInstallments rgi
    ON
	rgi.FinancialTransactionID = rmft.FinancialTransactionID
LEFT JOIN DonationLineItems dli
    ON
	dli.SOURCELINEITEMID = mli.LineItemID
LEFT JOIN DiscountLineItems xli
    ON
	xli.SOURCELINEITEMID = mli.LineItemID
LEFT JOIN SALESORDERITEMMEMBERSHIP soim
    ON
	mt.ID = soim.MEMBERSHIPTRANSACTIONID
LEFT JOIN SALESORDERITEM soi
    ON
	soim.ID = soi.ID
LEFT JOIN SALESORDER so
    ON
	soi.SALESORDERID = so.ID
LEFT JOIN SALESORDER revenue_so
    ON
	revenue_so.REVENUEID = rmft.FinancialTransactionID
LEFT JOIN SalesOrdersByPayment sop
    ON
	sop.PAYMENTID = rmft.FinancialTransactionID
LEFT JOIN SALESORDER payment_so
    ON
	payment_so.ID = sop.SalesOrderID
LEFT JOIN RefundedSalesOrders rso
    ON
	rso.SalesOrderID = COALESCE(so.ID, revenue_so.ID, payment_so.ID)
LEFT JOIN RefundedMembershipTransactions rmt
    ON
	rmt.MembershipTransactionID = mt.ID
LEFT JOIN SalesOrderAddOnLineItems so_addon
    ON
	so_addon.SALESORDERID = COALESCE(so.ID, revenue_so.ID, payment_so.ID)
LEFT JOIN MembershipTransactionAddOnLineItems mt_addon
    ON
	mt_addon.MEMBERSHIPTRANSACTIONID = mt.ID
LEFT JOIN DropTransactionsByPositiveMembership dtm
    ON
	dtm.MembershipTransactionID = mt.ID
LEFT JOIN LatestNoFinancialAnchorLifetimeMembershipTransactions lna
    ON
	lna.MembershipTransactionID = mt.ID
LEFT JOIN MEMBERSHIPLEVEL ml
    ON
	mt.MEMBERSHIPLEVELID = ml.ID
LEFT JOIN MEMBERSHIPPROGRAM prog ON
	prog.ID = ml.MEMBERSHIPPROGRAMID
LEFT JOIN MEMBERSHIPLEVELTERM mlt
    ON
	mt.MEMBERSHIPLEVELTERMID = mlt.ID
LEFT JOIN CONSTITUENT donor
    ON
	mt.DONORID = donor.ID
LEFT JOIN CONSTITUENT giver
    ON
	soim.GIVENBYID = giver.ID
LEFT JOIN MEMBER pmember
    ON
	m.ID = pmember.MEMBERSHIPID
	AND pmember.ISPRIMARY = 1
	AND pmember.ISDROPPED = 0
LEFT JOIN CONSTITUENT pmc
    ON
	pmember.CONSTITUENTID = pmc.ID
LEFT JOIN CONSTITUENT ftc on
	rmft.FinancialTransactionConstituentID = ftc.ID
LEFT JOIN CONSTITUENT primaryC
    ON
	primaryC.ID = COALESCE(soim.GIVENBYID, mt.DONORID, rmft.FinancialTransactionConstituentID, pmember.CONSTITUENTID)
LEFT JOIN CONSTITUENTHOUSEHOLD chh
    ON
	primaryC.ID = chh.ID
WHERE
	ISNULL(mt.ACTION, '') <> ('Dr'+'op')
	AND (
		COALESCE(so.ID, revenue_so.ID, payment_so.ID) IS NULL
		OR COALESCE(so.STATUSCODE, revenue_so.STATUSCODE, payment_so.STATUSCODE) NOT IN (0, 6, 7)
	)
	
	
	
	
	
	
	AND (
		COALESCE(so.ID, revenue_so.ID, payment_so.ID) IS NOT NULL
		OR mli.LineItemID IS NOT NULL
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
UNION ALL
SELECT
	obm.OrderMembershipItemID AS vnfp__Implementation_External_ID__c,
	obm.Revenue_ID_legacy__c,
	'{{MEMBERSHIP_RECORDTYPE_ID}}' AS RecordTypeId,
	CONCAT('Membership - ', ml.NAME, ' - ', CAST(COALESCE(obm.FinancialTransactionDate, obm.SalesOrderTransactionDate) AS DATE)) AS Name,
	'Equal' AS Membership_Upgraded_Downgraded__c,
	CASE
		WHEN obm.SalesOrderItemDescription LIKE '%Renew%' THEN 'Renewal'
		WHEN obm.SalesOrderItemDescription LIKE '%Rejoin%' OR obm.SalesOrderItemDescription LIKE '%Reacquire%' THEN 'Reacquire'
		ELSE 'New'
	END AS npe01__Membership_Origin__c,
	CASE
		WHEN pmc.ID IS NOT NULL
		AND pmc.ISORGANIZATION = 0
		AND pmc.ISGROUP = 0
		AND pmc.ISCONSTITUENT = 1
		THEN pmc.ID
		ELSE NULL
	END AS vnfp__Member__c,
	COALESCE(
	    CASE
	        WHEN giver.ID IS NOT NULL AND giver.ISORGANIZATION = 0 AND giver.ISGROUP = 0 AND giver.ISCONSTITUENT = 1
	        THEN giver.ID
	        ELSE NULL
	    END,
	    CASE
	        WHEN ftc.ID IS NOT NULL AND ftc.ISORGANIZATION = 0 AND ftc.ISGROUP = 0 AND ftc.ISCONSTITUENT = 1
	        THEN ftc.ID
	        ELSE NULL
	    END,
	    CASE
	        WHEN pmc.ID IS NOT NULL AND pmc.ISORGANIZATION = 0 AND pmc.ISGROUP = 0 AND pmc.ISCONSTITUENT = 1
	        THEN pmc.ID
	        ELSE NULL
	    END
	) AS npsp__Primary_Contact__c,
	CASE
		WHEN (primaryC.ISCONSTITUENT = 1
			AND primaryC.ISORGANIZATION = 0
			AND primaryC.ISGROUP = 0)
     THEN COALESCE(chh.HOUSEHOLDID, NULL)
		WHEN primaryC.ISORGANIZATION = 1
     THEN primaryC.ID
		ELSE NULL
	END AS AccountId,
	CAST(COALESCE(obm.FinancialTransactionDate, obm.SalesOrderTransactionDate) AS DATE) AS CloseDate,
	CAST(COALESCE(obm.FinancialTransactionDate, obm.SalesOrderTransactionDate) AS DATE) AS npe01__Membership_Start_Date__c,
	CAST(
		COALESCE(
			obm.EXPIRATIONDATE,
			DATEADD(YEAR, 100, COALESCE(obm.FinancialTransactionDate, obm.SalesOrderTransactionDate))
		)
	AS DATE) AS npe01__Membership_End_Date__c,
	obm.GIFTMESSAGE AS vnfp__Gift_Message__c,
	
	
	
	
	
	re.REFERENCE AS Description,
	re.REFERENCE AS Revenue_Reference__c,
	CASE
		WHEN obm.SalesOrderRefundStatus = 2 THEN 'Closed Lost'
		WHEN obm.SalesOrderStatusCode IN (1, 3, 4) THEN 'Closed Won'
		WHEN obm.SalesOrderStatusCode IN (5) THEN 'Closed Lost'
		WHEN obm.SalesOrderStatusCode IN (0, 2, 6, 7) THEN 'Prospecting'
		ELSE 'Prospecting'
	END AS StageName,
	obm.MembershipAmount AS Amount,
	NULL AS vnfp__Split_Receipting_Donation_Amount__c,
	NULL AS vnfp__Split_Receipting_Membership_Amount__c,
	NULL AS vnfp__Split_Receipting_Membership_Subtotal__c,
	0 AS vnfp__Split_Receipting__c,
	NULL AS Add_On_Quantity__c,
	NULL AS Add_On_Total__c,
	NULL AS vnfp__Discount_Amount__c,
	mlt.AMOUNT AS vnfp__Membership_Price__c,
	
	
	CAST(mlt.LEVELID AS VARCHAR(36)) + '-' + CAST(mlt.ID AS VARCHAR(36)) AS vnfp__Membership_Program__c,
	CAST(COALESCE(obm.FinancialTransactionDate, obm.SalesOrderTransactionDate) AS DATE) AS npsp__Acknowledgment_Date__c,
	'Acknowledged' AS npsp__Acknowledgment_Status__c,
	CASE
		WHEN obm.GIFTDELIVERYCODE = 0 THEN 'Member'
		WHEN obm.GIFTDELIVERYCODE = 1 THEN 'Buyer'
		ELSE NULL
	END AS vnfp__Deliver_Membership_To__c,
	0 AS vnfp__Midterm_Upgrade__c,
	obm.SalesOrderID AS vnfp__POS_Purchase__c,
	prog.NAME AS Program_Name__c,
	primaryC.ISORGANIZATION AS vnfp__Corporate_Membership__c,
	re.GIVENANONYMOUSLY AS Given_Anonymously__c,
	NULL AS npe03__Recurring_Donation__c
FROM
	OrderBackedMembershipFinancialTransactions obm
LEFT JOIN REVENUE_EXT re
    ON re.ID = obm.FinancialTransactionID
LEFT JOIN CONSTITUENT giver
    ON obm.GIVENBYID = giver.ID
LEFT JOIN MEMBER pmember
    ON obm.MEMBERSHIPID = pmember.MEMBERSHIPID
	AND pmember.ISPRIMARY = 1
	AND pmember.ISDROPPED = 0
LEFT JOIN CONSTITUENT pmc
    ON pmember.CONSTITUENTID = pmc.ID
LEFT JOIN CONSTITUENT ftc
    ON obm.FinancialTransactionConstituentID = ftc.ID
LEFT JOIN MEMBERSHIPLEVEL ml
    ON obm.MEMBERSHIPLEVELID = ml.ID
LEFT JOIN MEMBERSHIPPROGRAM prog
    ON prog.ID = obm.MEMBERSHIPPROGRAMID
LEFT JOIN MEMBERSHIPLEVELTERM mlt
    ON obm.MEMBERSHIPLEVELTERMID = mlt.ID
LEFT JOIN CONSTITUENT primaryC
    ON primaryC.ID = COALESCE(obm.GIVENBYID, obm.FinancialTransactionConstituentID, pmember.CONSTITUENTID)
LEFT JOIN CONSTITUENTHOUSEHOLD chh
    ON primaryC.ID = chh.ID
WHERE
	obm.SalesOrderStatusCode NOT IN (0, 6, 7)
	AND (
		@useDateFrom = 0
		OR CAST(COALESCE(obm.FinancialTransactionDate, obm.SalesOrderTransactionDate) AS DATE) >= @filterDateFrom
	)
	AND (
		@useDateTo = 0
		OR CAST(COALESCE(obm.FinancialTransactionDate, obm.SalesOrderTransactionDate) AS DATE) <= @filterDateTo
	)
) q;