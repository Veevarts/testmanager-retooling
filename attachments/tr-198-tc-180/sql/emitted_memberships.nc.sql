DECLARE @hasDateFilterFrom BIT = 0;
DECLARE @hasDateFilterTo BIT = 0;
DECLARE @dateFilterFrom VARCHAR(10) = NULL;
DECLARE @dateFilterTo VARCHAR(10) = NULL;
SET NOCOUNT ON;
DROP TABLE IF EXISTS #MembershipLineItems;
DROP TABLE IF EXISTS #MembershipAnchorCandidates;
DROP TABLE IF EXISTS #ResolvedMembershipFinancialTransactions;
DROP TABLE IF EXISTS #RecurringInstallments;
DROP TABLE IF EXISTS #DonationLineItems;
DROP TABLE IF EXISTS #DiscountLineItems;
DROP TABLE IF EXISTS #SalesOrderAddOnLineItems;
DROP TABLE IF EXISTS #MembershipTransactionAddOnLineItems;
DROP TABLE IF EXISTS #SalesOrdersByPayment;
DROP TABLE IF EXISTS #CreditPaymentPerRefund;
DROP TABLE IF EXISTS #RefundedSalesOrders;
DROP TABLE IF EXISTS #RefundedMembershipTransactions;
DROP TABLE IF EXISTS #OrderBackedMembershipFinancialCandidates;
DROP TABLE IF EXISTS #OrderBackedMembershipFinancialTransactions;
DROP TABLE IF EXISTS #LatestNoFinancialAnchorLifetimeMembershipTransactions;
DECLARE @useDateFrom BIT = IIF(@hasDateFilterFrom = 1, 1, 0);
DECLARE @useDateTo BIT = IIF(@hasDateFilterTo = 1, 1, 0);
DECLARE @filterDateFrom DATE = CAST(@dateFilterFrom AS DATE);
DECLARE @filterDateTo DATE = CAST(@dateFilterTo AS DATE);
SELECT
	ft.ID AS FinancialTransactionID,
	ft.CALCULATEDUSERDEFINEDID AS Revenue_ID_legacy__c,
	ft.CALCULATEDDATE AS OwnFinancialTransactionDate,
	mli.ID AS LineItemID,
	mli.TRANSACTIONAMOUNT AS MembershipAmount,
	mli.SOURCELINEITEMID
INTO #MembershipLineItems
FROM
	REVENUESPLIT_EXT rse
INNER JOIN FINANCIALTRANSACTIONLINEITEM mli
        ON
	mli.ID = rse.ID
	AND mli.[TYPE] = 'Standard'
INNER JOIN FINANCIALTRANSACTION ft
        ON
	ft.ID = mli.FINANCIALTRANSACTIONID
WHERE
	rse.APPLICATION = 'Membership';
CREATE NONCLUSTERED INDEX IX_MembershipLineItems ON #MembershipLineItems (LineItemID);
SELECT
	mt.ID                     AS MembershipTransactionID,
	mt.REVENUESPLITID         AS MembershipRevenueSplitId,
	cl.ID                     AS CandidateLineId,
	cl.SOURCELINEITEMID       AS CandidateSourceLineItemId,
	cl.DATEADDED              AS CandidateDateAdded,
	cl.FINANCIALTRANSACTIONID AS CandidateFinancialTransactionId
INTO #MembershipAnchorCandidates
FROM
	MEMBERSHIPTRANSACTION mt
INNER JOIN FINANCIALTRANSACTIONLINEITEM cl
        ON cl.ID = mt.REVENUESPLITID
       AND cl.[TYPE] = 'Standard'
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
       AND cl.[TYPE] = 'Standard';
CREATE NONCLUSTERED INDEX IX_MembershipAnchorCandidates ON #MembershipAnchorCandidates (CandidateFinancialTransactionId);
SELECT
	candidate_line.MembershipTransactionID,
	ft.ID AS FinancialTransactionID,
	ft.CALCULATEDUSERDEFINEDID AS Revenue_ID_legacy__c,
	ft.CALCULATEDDATE AS FinancialTransactionDate,
	ft.CONSTITUENTID AS FinancialTransactionConstituentID,
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
INTO #ResolvedMembershipFinancialTransactions
FROM
	#MembershipAnchorCandidates candidate_line
INNER JOIN FINANCIALTRANSACTION ft
        ON ft.ID = candidate_line.CandidateFinancialTransactionId;
CREATE NONCLUSTERED INDEX IX_ResolvedMembershipFinancialTransactions ON #ResolvedMembershipFinancialTransactions (MembershipTransactionID, ResolutionRank);
SELECT
	RecurringInstallmentID,
	STATUSCODE,
	FinancialTransactionID,
	InstallmentAmount,
	InstallmentDate,
	InstallmentStatus,
	RevenueId
INTO #RecurringInstallments
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
	InstallmentPaymentRank = 1;
CREATE NONCLUSTERED INDEX IX_RecurringInstallments ON #RecurringInstallments (FinancialTransactionID);
SELECT
	dli.SOURCELINEITEMID,
	dli.TRANSACTIONAMOUNT AS DonationAmount
INTO #DonationLineItems
FROM
	FINANCIALTRANSACTIONLINEITEM dli
INNER JOIN REVENUESPLIT_EXT drse
        ON
	drse.ID = dli.ID
	AND drse.APPLICATION = 'Donation'
WHERE
	dli.[TYPE] = 'Standard';
CREATE NONCLUSTERED INDEX IX_DonationLineItems ON #DonationLineItems (SOURCELINEITEMID);
SELECT
	xli.SOURCELINEITEMID,
	SUM(xli.TRANSACTIONAMOUNT) AS DiscountAmount
INTO #DiscountLineItems
FROM
	FINANCIALTRANSACTIONLINEITEM xli
WHERE
	xli.[TYPE] = 'Discount'
GROUP BY
	xli.SOURCELINEITEMID;
CREATE NONCLUSTERED INDEX IX_DiscountLineItems ON #DiscountLineItems (SOURCELINEITEMID);
SELECT
	soi.SALESORDERID,
	SUM(COALESCE(soi.QUANTITY, 0)) AS AddOnQuantity,
	SUM(COALESCE(soi.TOTAL, 0)) AS AddOnTotal
INTO #SalesOrderAddOnLineItems
FROM
	SALESORDERITEM soi
WHERE
	soi.[TYPE] = 'Membership add-on'
GROUP BY
	soi.SALESORDERID;
CREATE NONCLUSTERED INDEX IX_SalesOrderAddOnLineItems ON #SalesOrderAddOnLineItems (SALESORDERID);
SELECT
	ma.MEMBERSHIPTRANSACTIONID,
	SUM(COALESCE(ma.QUANTITY, 0)) AS AddOnQuantity,
	SUM(COALESCE(addon_line.TRANSACTIONAMOUNT, 0) - COALESCE(xli.DiscountAmount, 0)) AS AddOnTotal
INTO #MembershipTransactionAddOnLineItems
FROM
	MEMBERSHIPADDON ma
INNER JOIN FINANCIALTRANSACTIONLINEITEM addon_line
    ON addon_line.ID = ma.REVENUESPLITID
   AND addon_line.[TYPE] = 'Standard'
INNER JOIN REVENUESPLIT_EXT addon_rse
    ON addon_rse.ID = addon_line.ID
   AND addon_rse.APPLICATION = 'Membership add-on'
LEFT JOIN #DiscountLineItems xli
    ON xli.SOURCELINEITEMID = addon_line.ID
WHERE
	ma.MEMBERSHIPTRANSACTIONID IS NOT NULL
GROUP BY
	ma.MEMBERSHIPTRANSACTIONID;
CREATE NONCLUSTERED INDEX IX_MembershipTransactionAddOnLineItems ON #MembershipTransactionAddOnLineItems (MEMBERSHIPTRANSACTIONID);
SELECT
	sop.PAYMENTID,
	MIN(sop.SALESORDERID) AS SalesOrderID
INTO #SalesOrdersByPayment
FROM
	SALESORDERPAYMENT sop
GROUP BY
	sop.PAYMENTID;
CREATE NONCLUSTERED INDEX IX_SalesOrdersByPayment ON #SalesOrdersByPayment (PAYMENTID);
SELECT
	cp.CREDITID,
	MIN(cp.REVENUEID) AS OriginalPaymentTransactionId
INTO #CreditPaymentPerRefund
FROM
	CREDITPAYMENT cp
GROUP BY
	cp.CREDITID;
CREATE NONCLUSTERED INDEX IX_CreditPaymentPerRefund ON #CreditPaymentPerRefund (CREDITID);
SELECT
	rso_base.SalesOrderID
INTO #RefundedSalesOrders
FROM (
	SELECT
		COALESCE(original_so.ID, payment_so.ID, refund_so.ID) AS SalesOrderID,
		refund_ft.TRANSACTIONAMOUNT                           AS RefundAmount,
		COALESCE(original_so.AMOUNT, payment_so.AMOUNT, refund_so.AMOUNT)
		                                                      AS SalesOrderAmount
	FROM
		FINANCIALTRANSACTION refund_ft
	INNER JOIN #CreditPaymentPerRefund cp
	    ON cp.CREDITID = refund_ft.ID
	OUTER APPLY (
		SELECT TOP 1 so.ID, so.AMOUNT
		FROM SALESORDER so
		WHERE so.REVENUEID = cp.OriginalPaymentTransactionId
	) original_so
	LEFT JOIN #SalesOrdersByPayment refund_sop
	    ON refund_sop.PAYMENTID = cp.OriginalPaymentTransactionId
	LEFT JOIN SALESORDER payment_so
	    ON payment_so.ID = refund_sop.SalesOrderID
	OUTER APPLY (
		SELECT TOP 1 so.ID, so.AMOUNT
		FROM SALESORDER so
		WHERE so.REVENUEID = refund_ft.ID
	) refund_so
	WHERE
		refund_ft.[TYPE] = 'Refund'
		AND COALESCE(original_so.ID, payment_so.ID, refund_so.ID) IS NOT NULL
) rso_base
GROUP BY
	rso_base.SalesOrderID
HAVING
	ABS(SUM(rso_base.RefundAmount))
	>= ABS(MAX(ISNULL(rso_base.SalesOrderAmount, 0)));
CREATE NONCLUSTERED INDEX IX_RefundedSalesOrders ON #RefundedSalesOrders (SalesOrderID);
SELECT
	mt.ID AS MembershipTransactionID
INTO #RefundedMembershipTransactions
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
	CROSS APPLY (
		SELECT cim_by_source.MEMBERSHIPID
		FROM CREDITITEMMEMBERSHIP cim_by_source
		WHERE cim_by_source.ID = refund_line.SOURCELINEITEMID
		UNION ALL
		SELECT cim_by_line.MEMBERSHIPID
		FROM CREDITITEMMEMBERSHIP cim_by_line
		WHERE cim_by_line.ID = refund_line.ID
	) cim
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
	>= ABS(MAX(ISNULL(original_line.TRANSACTIONAMOUNT, 0)));
CREATE NONCLUSTERED INDEX IX_RefundedMembershipTransactions ON #RefundedMembershipTransactions (MembershipTransactionID);
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
	own_src_ft.CALCULATEDUSERDEFINEDID AS OwnRevenueIdLegacy,
	source_line.TRANSACTIONAMOUNT AS MembershipAmount,
	ROW_NUMBER() OVER (
        PARTITION BY soim.ID
        ORDER BY
            CASE WHEN candidate.SourceType = 'Payment' THEN 0 ELSE 1 END,
            ft.CALCULATEDDATE DESC,
            ft.ID DESC
    ) AS ResolutionRank
INTO #OrderBackedMembershipFinancialCandidates
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
LEFT JOIN FINANCIALTRANSACTION own_src_ft
    ON own_src_ft.ID = source_line.FINANCIALTRANSACTIONID;
CREATE NONCLUSTERED INDEX IX_OrderBackedMembershipFinancialCandidates ON #OrderBackedMembershipFinancialCandidates (OrderMembershipItemID, ResolutionRank);
SELECT
	*
INTO #OrderBackedMembershipFinancialTransactions
FROM
	#OrderBackedMembershipFinancialCandidates
WHERE
	ResolutionRank = 1;
CREATE NONCLUSTERED INDEX IX_OrderBackedMembershipFinancialTransactions ON #OrderBackedMembershipFinancialTransactions (OrderMembershipItemID);
SELECT
	MembershipTransactionID
INTO #LatestNoFinancialAnchorLifetimeMembershipTransactions
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
	OUTER APPLY (
		SELECT TOP 1 soim_anchor.ID
		FROM SALESORDERITEMMEMBERSHIP soim_anchor
		WHERE soim_anchor.MEMBERSHIPTRANSACTIONID = mt.ID
	) no_anchor_soim
	OUTER APPLY (
		SELECT TOP 1 addon_anchor.ID
		FROM MEMBERSHIPADDON addon_anchor
		WHERE addon_anchor.MEMBERSHIPTRANSACTIONID = mt.ID
	) no_anchor_ma
	OUTER APPLY (
		SELECT TOP 1 anchor.ID
		FROM (
			SELECT ft_by_split.ID
			FROM FINANCIALTRANSACTIONLINEITEM line_by_split
			INNER JOIN FINANCIALTRANSACTION ft_by_split
			    ON ft_by_split.ID = line_by_split.FINANCIALTRANSACTIONID
			WHERE line_by_split.ID = mt.REVENUESPLITID
			  AND line_by_split.[TYPE] = 'Standard'
			UNION ALL
			SELECT ft_by_source.ID
			FROM FINANCIALTRANSACTIONLINEITEM line_by_source
			INNER JOIN FINANCIALTRANSACTION ft_by_source
			    ON ft_by_source.ID = line_by_source.FINANCIALTRANSACTIONID
			WHERE line_by_source.SOURCELINEITEMID = mt.REVENUESPLITID
			  AND line_by_source.[TYPE] = 'Standard'
		) anchor
	) no_anchor_ft
	WHERE
		ISNULL(mt.ACTION, '') <> 'Drop'
		AND m.STATUSCODE = 0
		AND m.EXPIRATIONDATE IS NULL
		AND no_anchor_soim.ID IS NULL
		AND no_anchor_ma.ID IS NULL
		AND no_anchor_ft.ID IS NULL
) ranked_lifetime_memberships
WHERE
	LifetimeTransactionRank = 1;
CREATE NONCLUSTERED INDEX IX_LatestNoFinancialAnchorLifetimeMembershipTransactions ON #LatestNoFinancialAnchorLifetimeMembershipTransactions (MembershipTransactionID);
SELECT
	CAST(COALESCE(rgi.RecurringInstallmentID, mt.ID) AS VARCHAR(36)) AS OpportunityExternalId
FROM
	MEMBERSHIPTRANSACTION mt
INNER JOIN MEMBERSHIP m
    ON
	mt.MEMBERSHIPID = m.ID
LEFT JOIN #MembershipLineItems mli
    ON
	mli.LineItemID = mt.REVENUESPLITID
LEFT JOIN #ResolvedMembershipFinancialTransactions rmft
    ON
	rmft.MembershipTransactionID = mt.ID
	AND rmft.ResolutionRank = 1
LEFT JOIN REVENUE_EXT re
    ON re.ID = rmft.FinancialTransactionID
LEFT JOIN #RecurringInstallments rgi
    ON
	rgi.FinancialTransactionID = rmft.FinancialTransactionID
LEFT JOIN #DonationLineItems dli
    ON
	dli.SOURCELINEITEMID = mli.LineItemID
LEFT JOIN #DiscountLineItems xli
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
OUTER APPLY (
	SELECT TOP 1
		so_by_revenue.ID,
		so_by_revenue.STATUSCODE,
		so_by_revenue.REFUNDSTATUS
	FROM SALESORDER so_by_revenue
	WHERE so_by_revenue.REVENUEID = rmft.FinancialTransactionID
) revenue_so
LEFT JOIN #SalesOrdersByPayment sop
    ON
	sop.PAYMENTID = rmft.FinancialTransactionID
LEFT JOIN SALESORDER payment_so
    ON
	payment_so.ID = sop.SalesOrderID
LEFT JOIN #RefundedSalesOrders rso
    ON
	rso.SalesOrderID = COALESCE(so.ID, revenue_so.ID, payment_so.ID)
LEFT JOIN #RefundedMembershipTransactions rmt
    ON
	rmt.MembershipTransactionID = mt.ID
LEFT JOIN #SalesOrderAddOnLineItems so_addon
    ON
	so_addon.SALESORDERID = COALESCE(so.ID, revenue_so.ID, payment_so.ID)
LEFT JOIN #MembershipTransactionAddOnLineItems mt_addon
    ON
	mt_addon.MEMBERSHIPTRANSACTIONID = mt.ID
LEFT JOIN #LatestNoFinancialAnchorLifetimeMembershipTransactions lna
    ON
	lna.MembershipTransactionID = mt.ID
LEFT JOIN MEMBERSHIPLEVEL ml
    ON
	COALESCE(soim.MEMBERSHIPLEVELID, mt.MEMBERSHIPLEVELID) = ml.ID
LEFT JOIN MEMBERSHIPPROGRAM prog ON
	prog.ID = ml.MEMBERSHIPPROGRAMID
LEFT JOIN MEMBERSHIPLEVELTERM mlt
    ON
	COALESCE(soim.MEMBERSHIPLEVELTERMID, mt.MEMBERSHIPLEVELTERMID) = mlt.ID
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
	ISNULL(mt.ACTION, '') <> 'Drop'
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
	CAST(obm.OrderMembershipItemID AS VARCHAR(36)) AS OpportunityExternalId
FROM
	#OrderBackedMembershipFinancialTransactions obm
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
OPTION (LOOP JOIN, MAX_GRANT_PERCENT = 5);
DROP TABLE IF EXISTS #MembershipLineItems;
DROP TABLE IF EXISTS #MembershipAnchorCandidates;
DROP TABLE IF EXISTS #ResolvedMembershipFinancialTransactions;
DROP TABLE IF EXISTS #RecurringInstallments;
DROP TABLE IF EXISTS #DonationLineItems;
DROP TABLE IF EXISTS #DiscountLineItems;
DROP TABLE IF EXISTS #SalesOrderAddOnLineItems;
DROP TABLE IF EXISTS #MembershipTransactionAddOnLineItems;
DROP TABLE IF EXISTS #SalesOrdersByPayment;
DROP TABLE IF EXISTS #CreditPaymentPerRefund;
DROP TABLE IF EXISTS #RefundedSalesOrders;
DROP TABLE IF EXISTS #RefundedMembershipTransactions;
DROP TABLE IF EXISTS #OrderBackedMembershipFinancialCandidates;
DROP TABLE IF EXISTS #OrderBackedMembershipFinancialTransactions;
DROP TABLE IF EXISTS #LatestNoFinancialAnchorLifetimeMembershipTransactions;
