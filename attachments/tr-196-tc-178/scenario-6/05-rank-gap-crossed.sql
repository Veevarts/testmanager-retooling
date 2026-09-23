-- TC-178: parametros que el harness inyecta. Sin ventana de fechas = todos los anios,
-- que es lo que el ticket pide para la recarga.
DECLARE @hasDateFilterFrom BIT = 0;
DECLARE @hasDateFilterTo   BIT = 0;
DECLARE @dateFilterFrom DATE = NULL;
DECLARE @dateFilterTo   DATE = NULL;

-- TC-178 escenario 6: transacciones que quedan DETRAS del rango 1 en una particion cuyo
-- reembolso cubre de sobra a la mas nueva. Son las candidatas a que el ranking las pierda
-- ahora que la bandera de cantidad ya no hace de respaldo. Logica copiada de la derivada
-- `rm` del propio archivo.
DROP TABLE IF EXISTS #RankGapOlder;
WITH rm AS (
    SELECT
        mt.ID AS MembershipTransactionID,
        mt.REVENUESPLITID AS RevenueSplitId,
        refund_ft.ID AS RefundId,
        cim.MEMBERSHIPID AS MembershipId,
        refund_line.TRANSACTIONAMOUNT AS RefundAmount,
        ROW_NUMBER() OVER (
            PARTITION BY refund_ft.ID, cim.MEMBERSHIPID
            ORDER BY mt.TRANSACTIONDATE DESC, mt.ID DESC
        ) AS RefundMatchRank
    FROM FINANCIALTRANSACTION refund_ft
    INNER JOIN FINANCIALTRANSACTIONLINEITEM refund_line
        ON refund_line.FINANCIALTRANSACTIONID = refund_ft.ID
       AND refund_line.[TYPE] = 'Standard'
    CROSS APPLY (
        SELECT cim_by_source.MEMBERSHIPID FROM CREDITITEMMEMBERSHIP cim_by_source
         WHERE cim_by_source.ID = refund_line.SOURCELINEITEMID
        UNION ALL
        SELECT cim_by_line.MEMBERSHIPID FROM CREDITITEMMEMBERSHIP cim_by_line
         WHERE cim_by_line.ID = refund_line.ID
    ) cim
    INNER JOIN MEMBERSHIPTRANSACTION mt
        ON mt.MEMBERSHIPID = cim.MEMBERSHIPID
       AND mt.TRANSACTIONDATE <= refund_ft.CALCULATEDDATE
    WHERE refund_ft.[TYPE] = 'Refund'
),
OverCovering AS (
    SELECT r.RefundId, r.MembershipId
    FROM rm r
    LEFT JOIN FINANCIALTRANSACTIONLINEITEM ol
        ON ol.ID = r.RevenueSplitId AND ol.[TYPE] = 'Standard'
    GROUP BY r.RefundId, r.MembershipId
    HAVING MAX(CASE WHEN r.RefundMatchRank = 1 THEN ABS(r.RefundAmount) END)
         > MAX(CASE WHEN r.RefundMatchRank = 1 THEN ABS(ISNULL(ol.TRANSACTIONAMOUNT, 0)) END)
)
SELECT DISTINCT rm.MembershipTransactionID
INTO #RankGapOlder
FROM rm
INNER JOIN OverCovering oc
    ON oc.RefundId = rm.RefundId AND oc.MembershipId = rm.MembershipId
WHERE rm.RefundMatchRank > 1;

-- IM-1161: staged extraction.
-- Every #temp below is session-scoped and dropped again at the end, so this
-- file stays a self-contained artifact you can paste into SSMS and run as-is.
-- Run it top to bottom; the single result set is the last statement.
SET NOCOUNT ON;

-- Re-runnable in the same session.
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

-- PERF: previously written as FINANCIALTRANSACTION joined to REVENUESPLIT_EXT on
-- nothing but a constant predicate, which reads as a cross join of two of the
-- largest tables in the graph that only narrows on the third join. Driving from
-- the selective REVENUESPLIT_EXT side keeps the intent obvious. Inner joins are
-- associative and the moved predicate is on the same table, so the result set is
-- unchanged.
SELECT
	ft.ID AS FinancialTransactionID,
	ft.CALCULATEDUSERDEFINEDID AS Revenue_ID_legacy__c,
	-- IM-1206: the date of the transaction that OWNS the membership line. The
	-- rev id above already came from this transaction; only the date was missing.
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

-- PERF: a membership transaction reaches its line item either directly
-- (line.ID = REVENUESPLITID) or through a refund/adjustment child
-- (line.SOURCELINEITEMID = REVENUESPLITID). This was one INNER JOIN with those
-- two predicates OR'd together. Both columns are indexed, but SQL Server cannot
-- satisfy a single predicate from two different indexes, so it read
-- FINANCIALTRANSACTIONLINEITEM in full. Splitting the disjunction into two
-- independent equijoins under UNION ALL lets the optimizer cost each branch on
-- its own and pick one sequential pass per branch.
--
-- Measured on Long Island (2026-07-30), whole-CTE wall time, identical
-- 140,378 rows and identical BINARY_CHECKSUM in all three shapes:
--   original OR join .......... 50s
--   CROSS APPLY per transaction 87s  (rejected: forces per-row key lookups)
--   UNION ALL of equijoins ..... 22s  (this one)
--
-- A line satisfying both branches is emitted twice, but the duplicate is
-- identical in every projected and ordering column, so the ResolutionRank = 1
-- winner is unchanged.
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

-- IM-952: Some Altru membership add-ons have revenue split + MEMBERSHIPADDON
-- lineage but no SALESORDERITEM row. Use this parent-MT aggregate only as a
-- fallback after #SalesOrderAddOnLineItems so sales-order-backed add-ons keep
-- their existing totals without being counted twice.
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

-- Only flag a sales order as fully refunded when total refund magnitude
-- meets or exceeds the SO amount. Partial refunds (e.g., a $10 downgrade
-- adjustment on a $66.95 order) must NOT force the membership opportunity
-- to Closed Lost; the order-status branch keeps it Closed Won.
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
	-- PERF: `LEFT JOIN SALESORDER ON REVENUEID = <key>` is pathological on this
	-- table (1.1M rows / ~424 MB). Measured on Long Island, this branch alone did
	-- not finish inside the app's 120s request timeout; as an OUTER APPLY with
	-- TOP 1 — which pins the correlated index seek instead of letting the
	-- optimizer un-nest it back into the same plan — the same 8,411 rows and the
	-- same checksum come back in ~3s. Dropping the TOP 1 restores the timeout, so
	-- it is load-bearing, not decoration.
	--
	-- TOP 1 is a no-op here: SALESORDER.REVENUEID is unique among non-NULL values
	-- (1,125,095 rows, 367,650 NULL, 757,445 non-NULL = 757,445 distinct), and a
	-- NULL key matches nothing under either shape. See "Sales order, POS, charge,
	-- and refund model" in docs/altru-model-context.md for the cross-profile check.
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

-- Gate both branches by refund completeness against the MT's original
-- Standard line. Partial refunds tied to the same membership line must
-- not flag the MT as refunded (see IM-762 — $10 senior-downgrade
-- adjustment on a $65 membership line was being marked Closed Lost).
-- Branch A: refund line points directly at the MT's revenue split.
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
-- Branch B: refund line is associated with the membership via
-- CREDITITEMMEMBERSHIP. The inner subquery and rank are unchanged so the
-- MT picked by RefundMatchRank=1 is identical to before; the completeness
-- gate is applied AFTER the rank via a LEFT JOIN on the MT's revenue
-- split line so the row population driving the rank stays invariant.
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
	-- PERF: same non-seekable OR rewritten as two seeks. CREDITITEMMEMBERSHIP.ID
	-- is the primary key, so each branch is a single-row lookup. A credit line
	-- satisfying both predicates yields a duplicate, but duplicates land in the
	-- same (refund_ft.ID, cim.MEMBERSHIPID) partition and only RefundMatchRank = 1
	-- survives, so the population the rank and the outer SUM see is unchanged.
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
	-- IM-1206: the rev id of the transaction that OWNS the membership line. This
	-- branch ranks SourceType = 'Payment' first, so Revenue_ID_legacy__c above is
	-- the payment's even when the order is the record Altru files the membership
	-- under. Unlike the date, that mismatch is NOT same-day-latent: sibling
	-- transactions always carry different ids, so all 121 Long Island rows cited
	-- the payment while their POS Purchase and fund assignment cited the order.
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
-- IM-1206: owning transaction of the membership line. LEFT JOIN on a NOT NULL
-- column against the primary key, so it resolves at most one row and cannot
-- change this CTE's grain or its ResolutionRank.
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

-- PERF / dead code: the PositiveMembershipTransactions -> DropTransactions ->
-- MatchedDropTransactions -> DropTransactionsByPositiveMembership chain used to
-- feed a `dtm.DropTransactionDate` CloseDate fallback and a 'Closed Lost'
-- StageName branch. IM-463 (784561d) replaced both consumers, but left the CTEs
-- and their LEFT JOIN in place, so the chain has been computing a triangular
-- self-join of MEMBERSHIPTRANSACTION (every drop paired with every earlier
-- positive transaction of the same membership) plus a window sort, and then
-- discarding the result. The join was grouped by MembershipTransactionID, so it
-- could never add or remove an output row. Removed outright.
-- IM-950: legacy lifetime memberships can have an active membership
-- transaction but no revenue split, sales order item, add-on, or resolved
-- financial transaction. Emit only the latest active no-expiration
-- membership transaction per membership so the fallback broadens coverage
-- without multiplying logical lifetime memberships.
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
	-- PERF: these three probes exist only to feed the IS NULL anti-join tests
	-- below. As LEFT JOINs they first multiplied every anchored membership
	-- transaction by all of its sales-order-item, add-on and line-item matches
	-- and only then threw those rows away, and the line-item probe used the same
	-- non-seekable OR as #ResolvedMembershipFinancialTransactions above. TOP 1
	-- OUTER APPLY yields at most one row per probe and stops at the first match,
	-- which is exactly what an existence test needs. Each probed ID column is a
	-- primary key and therefore never NULL on a match, so "ID IS NULL" still
	-- means "no anchor" precisely as it did with the LEFT JOINs.
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
	q.BranchTag,
	COUNT(1)                                                                              AS rows_total,
	COUNT(DISTINCT q.RowKey)                                                              AS rows_distinct,
	SUM(CASE WHEN q.QtyFlag = 1 AND q.IsDrop = 0 THEN 1 ELSE 0 END)                       AS qty_flag_non_drop,
	SUM(CASE WHEN q.QtyFlag = 1 AND q.IsDrop = 0 AND q.DollarGate = 1 THEN 1 ELSE 0 END)   AS qty_flag_dollar_gated,
	SUM(CASE WHEN q.OldStage <> q.NewStage THEN 1 ELSE 0 END)                              AS changed_rows,
	SUM(CASE WHEN q.OldStage = 'Closed Lost' AND q.NewStage = 'Closed Won' THEN 1 ELSE 0 END) AS released_lost_to_won,
	SUM(CASE WHEN q.OldStage = 'Closed Won' AND q.NewStage = 'Closed Lost' THEN 1 ELSE 0 END) AS newly_lost_won_to_lost,
	SUM(CASE WHEN q.OldStage <> q.NewStage
		  AND NOT (q.OldStage IN ('Closed Lost','Closed Won') AND q.NewStage IN ('Closed Lost','Closed Won'))
		 THEN 1 ELSE 0 END)                                                               AS changed_other_shapes,
	SUM(CASE WHEN q.OldStage = 'Closed Lost' AND q.NewStage = 'Closed Won' AND q.GroupSales = 1 THEN 1 ELSE 0 END) AS released_group_sales,
	SUM(q.RankGapOlder)                                                                   AS rank_gap_older_rows,
	SUM(CASE WHEN q.RankGapOlder = 1 AND q.OldStage = 'Closed Lost' AND q.NewStage = 'Closed Won' THEN 1 ELSE 0 END) AS rank_gap_older_released,
	SUM(CASE WHEN q.OldStage = 'Closed Lost' THEN 1 ELSE 0 END)                            AS old_closed_lost,
	SUM(CASE WHEN q.NewStage = 'Closed Lost' THEN 1 ELSE 0 END)                            AS new_closed_lost,
	SUM(CASE WHEN q.OldStage = 'Closed Won' THEN 1 ELSE 0 END)                             AS old_closed_won,
	SUM(CASE WHEN q.NewStage = 'Closed Won' THEN 1 ELSE 0 END)                             AS new_closed_won
FROM (

SELECT
	COALESCE(rgi.RecurringInstallmentID, mt.ID) AS RowKey,
	'MT' AS BranchTag,
	-- POST: copia literal del CASE del PR (sin el branch de REFUNDSTATUS)
	CASE
		WHEN rgi.RecurringInstallmentID IS NOT NULL THEN
			CASE rgi.STATUSCODE
				WHEN 0 THEN 'Pledged' WHEN 1 THEN 'Closed Lost' WHEN 2 THEN 'Closed Won'
				WHEN 3 THEN 'Closed Lost' WHEN 4 THEN 'Closed Lost' ELSE 'Pledged'
			END
		WHEN mt.ACTION = 'Drop' THEN 'Closed Lost'
		WHEN rso.SalesOrderID IS NOT NULL THEN 'Closed Lost'
		WHEN rmt.MembershipTransactionID IS NOT NULL THEN 'Closed Lost'
		ELSE
			CASE
				WHEN COALESCE(so.ID, revenue_so.ID, payment_so.ID) IS NULL THEN 'Closed Won'
				WHEN COALESCE(so.STATUSCODE, revenue_so.STATUSCODE, payment_so.STATUSCODE) IN (1, 3, 4) THEN 'Closed Won'
				WHEN COALESCE(so.STATUSCODE, revenue_so.STATUSCODE, payment_so.STATUSCODE) IN (5) THEN 'Closed Lost'
				WHEN COALESCE(so.STATUSCODE, revenue_so.STATUSCODE, payment_so.STATUSCODE) IN (0, 2, 6, 7) THEN 'Prospecting'
				ELSE 'Prospecting'
			END
	END AS NewStage,
	-- PRE: el mismo CASE con el branch de REFUNDSTATUS reinstalado donde estaba
	CASE
		WHEN rgi.RecurringInstallmentID IS NOT NULL THEN
			CASE rgi.STATUSCODE
				WHEN 0 THEN 'Pledged' WHEN 1 THEN 'Closed Lost' WHEN 2 THEN 'Closed Won'
				WHEN 3 THEN 'Closed Lost' WHEN 4 THEN 'Closed Lost' ELSE 'Pledged'
			END
		WHEN mt.ACTION = 'Drop' THEN 'Closed Lost'
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
	END AS OldStage,
	CASE WHEN COALESCE(so.REFUNDSTATUS, revenue_so.REFUNDSTATUS, payment_so.REFUNDSTATUS) = 2 THEN 1 ELSE 0 END AS QtyFlag,
	-- revenue_so es un OUTER APPLY que solo proyecta ID/STATUSCODE/REFUNDSTATUS, asi que
	-- la venta a grupos se resuelve por subconsulta escalar sobre la MISMA orden que el
	-- CASE de StageName resuelve. Escalar sobre PK: no puede alterar el grano.
	(SELECT CASE WHEN so2.SALESMETHODTYPECODE = 3 THEN 1 ELSE 0 END
	   FROM SALESORDER so2
	  WHERE so2.ID = COALESCE(so.ID, revenue_so.ID, payment_so.ID)) AS GroupSales,
	CASE WHEN rso.SalesOrderID IS NOT NULL OR rmt.MembershipTransactionID IS NOT NULL THEN 1 ELSE 0 END AS DollarGate,
	CASE WHEN mt.ACTION = 'Drop' THEN 1 ELSE 0 END AS IsDrop,
	CASE WHEN EXISTS (SELECT 1 FROM #RankGapOlder g WHERE g.MembershipTransactionID = mt.ID)
	     THEN 1 ELSE 0 END AS RankGapOlder,
	-- copia literal de la expresion de Revenue_ID_legacy__c de la rama (IM-1206)
	CASE
		WHEN rgi.RecurringInstallmentID IS NOT NULL AND rgi.RevenueId IS NULL THEN NULL
		ELSE COALESCE(rgi.RevenueId, NULLIF(mli.Revenue_ID_legacy__c, ''), rmft.Revenue_ID_legacy__c)
	END AS RevId
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
-- PERF: same pathological SALESORDER-by-REVENUEID join as in #RefundedSalesOrders
-- above, here driven by every membership transaction rather than by refunds.
-- OUTER APPLY + TOP 1 pins the correlated index seek; TOP 1 is a no-op because
-- REVENUEID is unique among non-NULL values.
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
-- IM-1204: read the level and term from the sales-order line, not from
-- MEMBERSHIPTRANSACTION. When a user follows "Go to Membership" from a transaction
-- and changes the membership, Altru rewrites MEMBERSHIPTRANSACTION.MEMBERSHIPLEVELID
-- / .MEMBERSHIPLEVELTERMID in place, while SALESORDERITEMMEMBERSHIP keeps what the
-- transaction actually sold.
--
-- Long Island: 189 of 45,444 order-anchored membership transactions disagree on level
-- or term (182 on level, 183 on term). Three independent signals all point the same
-- way, and none points the other way:
--   * SALESORDERITEM.DESCRIPTION, which Altru writes once at sale time and never
--     rewrites, names the SALESORDERITEMMEMBERSHIP level on 179 of the 182
--     level-divergent rows and the MEMBERSHIPTRANSACTION level on 0 of them.
--   * SALESORDERITEM.TOTAL matches the sales-order term price on 110 of those rows and
--     the transaction term price on 42 -- but all 42 are ties, rows where the two term
--     prices happen to be equal. Exclusively, it is 110 to 0; on the 89 rows where the
--     two prices actually differ, 68 to 0.
--   * No SALESORDERITEM among the 182 was last changed by a different user than added
--     it (0 of 182, against a 40 of 45,262 baseline), while 150 of the 182
--     MEMBERSHIPTRANSACTION rows were (82%, against a 43% baseline).
-- Do NOT use a plain "DATECHANGED > DATEADDED" test here: SALESORDERITEMMEMBERSHIP has
-- no row at all where the two are equal, so that test returns 100% on both buckets and
-- discriminates nothing.
--
-- SALESORDERITEMMEMBERSHIP is exactly one row per MEMBERSHIPTRANSACTION -- Long Island
-- 45,444 of 45,444, Tucson 19,617 of 19,617, High Desert 25,068 of 25,068, with no
-- other bucket -- so this cannot change the row grain, and the COALESCE keeps the
-- MEMBERSHIPTRANSACTION anchor for the 80,821 Long Island transactions that resolve no
-- sales-order line at all. The term always resolves and always owns its own level on
-- the sales-order side (45,444 of 45,444 here, and on every tenant measured), so the
-- IM-1106 key below stays resolvable either way.
--
-- Blast radius is NOT uniform: Tucson is the most affected tenant at 627 of 19,617
-- (3.20%) against Long Island's 189 of 45,444 (0.42%) and High Desert's 21 of 25,068.
--
-- Known gap, deliberately out of scope: mt.ACTION drifts in the same edit and still
-- feeds Membership_Upgraded_Downgraded__c and npe01__Membership_Origin__c above. See
-- the IM-1204 entry in docs/altru-model-context.md.
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
	-- IM-621: include any non-Drop membership transaction that has at least one
	-- financial anchor. The previous predicate required amount > 0 or a paid
	-- add-on, which silently dropped legitimate $0 comp memberships and
	-- understated the current-member count. This gate is mirrored in
	-- fund_assignment_memberships.sql and contact_roles.sql — revert all three
	-- together or not at all, otherwise the FA / CR paths produce orphans.
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
	obm.OrderMembershipItemID AS RowKey,
	'OBM' AS BranchTag,
	-- POST: copia literal del CASE del PR (compuerta de dolares)
	CASE
		WHEN obm_rso.SalesOrderID IS NOT NULL THEN 'Closed Lost'
		WHEN obm.SalesOrderStatusCode IN (1, 3, 4) THEN 'Closed Won'
		WHEN obm.SalesOrderStatusCode IN (5) THEN 'Closed Lost'
		WHEN obm.SalesOrderStatusCode IN (0, 2, 6, 7) THEN 'Prospecting'
		ELSE 'Prospecting'
	END AS NewStage,
	-- PRE: el mismo CASE con la bandera de cantidad en su lugar
	CASE
		WHEN obm.SalesOrderRefundStatus = 2 THEN 'Closed Lost'
		WHEN obm.SalesOrderStatusCode IN (1, 3, 4) THEN 'Closed Won'
		WHEN obm.SalesOrderStatusCode IN (5) THEN 'Closed Lost'
		WHEN obm.SalesOrderStatusCode IN (0, 2, 6, 7) THEN 'Prospecting'
		ELSE 'Prospecting'
	END AS OldStage,
	CASE WHEN obm.SalesOrderRefundStatus = 2 THEN 1 ELSE 0 END AS QtyFlag,
	(SELECT CASE WHEN so2.SALESMETHODTYPECODE = 3 THEN 1 ELSE 0 END
	   FROM SALESORDER so2 WHERE so2.ID = obm.SalesOrderID) AS GroupSales,
	CASE WHEN obm_rso.SalesOrderID IS NOT NULL THEN 1 ELSE 0 END AS DollarGate,
	0 AS IsDrop,
	0 AS RankGapOlder,
	COALESCE(NULLIF(obm.OwnRevenueIdLegacy, ''), obm.Revenue_ID_legacy__c) AS RevId
FROM
	#OrderBackedMembershipFinancialTransactions obm
-- IM-1272: dollar-complete refund gate for this branch's StageName, keyed on the same
-- sales order the row is built from. #RefundedSalesOrders holds one row per fully
-- refunded sales order, so this cannot change the row grain.
LEFT JOIN #RefundedSalesOrders obm_rso
    ON obm_rso.SalesOrderID = obm.SalesOrderID
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
-- IM-1161: this hint is load-bearing, not decoration. Measured on high_desert
-- with every input above already staged into #temp tables:
--   no hint ............ SerialDesiredMemory 911 MB, required 17 MB -> err 8645
--   LOOP JOIN .......... SerialDesiredMemory 394 MB, required  3 MB -> err 8645
--   LOOP JOIN + cap .... completes: 164,465 rows in ~445 s
-- Nested loops over the indexed #temp inputs drop 17 of the 28 grant consumers,
-- and the cap makes the request small enough to be granted immediately instead
-- of queueing on the resource semaphore until it times out. The instance offers
-- a single query at most ~154 MB (2 vCPU / 3 GB box), so asking for more is
-- asking to fail. MAX_GRANT_PERCENT = 25 also completes (~458 s); 5 is used
-- because a smaller request is likelier to be granted on a busy instance.
) AS q
GROUP BY q.BranchTag
-- El hint vive en la sentencia mas externa: dentro de la derivada es sintaxis invalida.
-- Se conserva el del PR tal cual para no alterar el plan que el autor midio.
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
