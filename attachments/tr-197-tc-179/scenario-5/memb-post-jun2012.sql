DECLARE @hasDateFilterFrom BIT = 1;
DECLARE @hasDateFilterTo BIT = 1;
DECLARE @dateFilterFrom DATE = '2012-06-01';
DECLARE @dateFilterTo DATE = '2012-06-30';

DECLARE @useDateFrom BIT = IIF(@hasDateFilterFrom = 1, 1, 0);
DECLARE @useDateTo BIT = IIF(@hasDateFilterTo = 1, 1, 0);
DECLARE @filterDateFrom DATE = CAST(@dateFilterFrom AS DATE);
DECLARE @filterDateTo DATE = CAST(@dateFilterTo AS DATE);

WITH MembershipLineItems AS (
SELECT
        mli.ID AS LineItemID,
        mli.TRANSACTIONAMOUNT AS Amount,
        mli.SOURCELINEITEMID,
        mli.FINANCIALTRANSACTIONID AS OwnFinancialTransactionID,
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
        ft.[TYPE] AS FinancialTransactionType,
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
-- IM-1275: only the ORDER's own discount belongs here. Altru's 2011-2012 POS
-- refunds on a discounted membership carry their revenue reversal on a
-- 'Discount'-typed line of the REFUND transaction, pointing at the same
-- membership line, so the unfiltered SUM subtracted the refund from the dues
-- and emitted the sale at $0 - and the refund itself was dropped for lack of a
-- Standard line. Measured on Long Island: 12 memberships / $948, all
-- 2011-2012; every one of them now emits its real net amount here and a
-- matching Refunded row in fund_assignments_membership_refunds.sql.
-- membership_transactions.sql carries the identical filter so the opportunity
-- Amount keeps matching the sum of its fund assignments.
SELECT
        xli.SOURCELINEITEMID,
        SUM(xli.TRANSACTIONAMOUNT) AS DiscountAmount
FROM
        FINANCIALTRANSACTIONLINEITEM xli
LEFT JOIN FINANCIALTRANSACTION xft
        ON xft.ID = xli.FINANCIALTRANSACTIONID
WHERE
        xli.[TYPE] = 'Discount'
        AND ISNULL(xft.[TYPE], '') <> 'Refund'
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
-- IM-560: donation revenue splits whose SOURCELINEITEMID points at a
-- membership line backed by a membership transaction. The membership
-- opportunity absorbs their amount through split receipting
-- (vnfp__Split_Receipting__c in membership_transactions.sql) and
-- fund_assignment_donations.sql intentionally skips them, so this file must
-- emit their fund assignment against that same membership opportunity to keep
-- the donation portion's real Altru designation.
SELECT
        dli.ID AS LineItemID,
        dli.TRANSACTIONAMOUNT AS Amount,
        dli.SOURCELINEITEMID,
        dli.FINANCIALTRANSACTIONID AS OwnFinancialTransactionID,
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
SELECT own_so_only, yr, COUNT(*) AS n_rows, SUM(amt_new) AS sum_new, SUM(amt_old) AS sum_old, SUM(CASE WHEN amt_new <> amt_old THEN 1 ELSE 0 END) AS n_amt_cambiado, SUM(CASE WHEN amt_old = 0 AND amt_new <> 0 THEN 1 ELSE 0 END) AS n_de_cero_a_real, SUM(sin_pos) AS n_sin_pos FROM (
SELECT
    CASE WHEN COALESCE(so.ID, addon_so.ID, revenue_so.ID, payment_so.ID) IS NULL
              AND own_so.ID IS NOT NULL THEN 1 ELSE 0 END AS own_so_only,
    CASE WHEN rgi.RecurringInstallmentID IS NOT NULL THEN rgi.InstallmentAmount
         ELSE mli.Amount - COALESCE(xli.DiscountAmount, 0) END AS amt_new,
    CASE WHEN rgi.RecurringInstallmentID IS NOT NULL THEN rgi.InstallmentAmount
         ELSE mli.Amount - COALESCE((SELECT SUM(x2.TRANSACTIONAMOUNT) FROM FINANCIALTRANSACTIONLINEITEM x2 WHERE x2.[TYPE] = 'Discount' AND x2.SOURCELINEITEMID = mli.LineItemID), 0) END AS amt_old,
    CASE WHEN COALESCE(so.ID, addon_so.ID, revenue_so.ID, payment_so.ID, own_so.ID) IS NULL
         THEN 1 ELSE 0 END AS sin_pos,
    YEAR(CAST(COALESCE(rgi.InstallmentDate, own_ft.CALCULATEDDATE, rmft.FinancialTransactionDate, mt.TRANSACTIONDATE) AS DATE)) AS yr
FROM
        MembershipLineItems mli
INNER JOIN REVENUESPLIT_EXT source_rse
    ON source_rse.ID = mli.LineItemID
-- IM-1205: the membership line's own financial transaction. LEFT JOIN keeps the
-- row grain untouched even if a backup carries a dangling FINANCIALTRANSACTIONID;
-- the column is NOT NULL and FINANCIALTRANSACTION.ID is the primary key, so this
-- resolves at most one row per membership line.
LEFT JOIN FINANCIALTRANSACTION own_ft
    ON own_ft.ID = mli.OwnFinancialTransactionID
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
   -- IM-560: membership_transactions.sql never emits Drop transactions, so a
   -- Drop-anchored line must not resolve its fund assignment to that
   -- opportunity key; without this filter the row would reference an
   -- opportunity that is never exported.
   AND ISNULL(mt.ACTION, '') <> 'Drop'
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
-- IM-1275: an order-backed membership line whose ONLY child line is a refund
-- has no sales order left to resolve: rmft ranks that refund child first (rank
-- 0 by SOURCELINEITEMID), a Refund transaction backs no SALESORDER.REVENUEID and
-- no SALESORDERPAYMENT, and with no MEMBERSHIPTRANSACTION there is no soim path
-- either. The whole COALESCE below went NULL, order_membership never matched,
-- and the dues row was dropped while fund_assignments_membership_refunds.sql
-- still emitted its Refunded counterpart - a fund assignment showing only money
-- going out (Long Island rev-10111554 / 8-10041986, $170, IM-1275 example 1).
-- The line's own transaction is the Order, so its SALESORDER is the right home;
-- SALESORDER.REVENUEID is unique among non-NULL values, so this adds no rows.
-- The gate is deliberately narrow: it fires ONLY when the ranked winner is a
-- Refund, because widening it to every unresolved row also re-homed the
-- multi-membership orders of 2022-2025, whose line-to-item mapping is a
-- separate (already duplicated) defect. With the Refund gate, 2014-2026 output
-- is byte-identical to the pre-fix export.
LEFT JOIN SALESORDER own_so
    ON
        own_so.REVENUEID = mli.OwnFinancialTransactionID
        AND rmft.FinancialTransactionType = 'Refund'
LEFT JOIN OrderBackedMembershipFinancialTransactions order_membership
    ON
        order_membership.MembershipLineItemID = mli.LineItemID
        AND order_membership.SalesOrderID = COALESCE(so.ID, addon_so.ID, revenue_so.ID, payment_so.ID, own_so.ID)
WHERE
        COALESCE(rgi.RecurringInstallmentID, mt.ID, ma.MEMBERSHIPTRANSACTIONID, order_membership.OrderMembershipItemID) IS NOT NULL
        AND (
            COALESCE(so.ID, addon_so.ID, revenue_so.ID, payment_so.ID, own_so.ID, order_membership.SalesOrderID) IS NULL
            OR COALESCE(so.STATUSCODE, addon_so.STATUSCODE, revenue_so.STATUSCODE, payment_so.STATUSCODE, own_so.STATUSCODE, order_membership.SalesOrderStatusCode) NOT IN (0, 6, 7)
        )
        -- IM-621: matches the relaxed inclusion gate in membership_transactions.sql
        -- so every $0 membership opportunity still receives its fund assignment.
        -- The outer membership-anchor check above already filters true orphans.
        --
        -- IM-1275: the ONE exception to "the window never moves with the emitted
        -- date" is the row own_so rescues. There the ranked transaction is by
        -- construction the Refund, so windowing on it splits the row from its own
        -- parents: the Opportunity's order-backed branch windows on
        -- COALESCE(obm.FinancialTransactionDate, obm.SalesOrderTransactionDate) and
        -- sales_order_only_membership.sql windows on SALESORDER.TRANSACTIONDATE, both
        -- the Order's date, while this row would gate on the refund's (Long Island
        -- 8-10041986: order 2012-06-06, refund 2012-07-09, 33 days). A June run would
        -- emit the Opportunity and its POS purchase and drop this fund assignment -
        -- the very defect IM-1275 fixes - and a July run would emit a fund assignment
        -- whose Opportunity is not in the run at all. The CASE is deliberately keyed on
        -- own_so being the ONLY resolution, not merely on the winner being a Refund.
        -- The reason is which Opportunity a row is paired with, not scope caution:
        --   * a Refund can also win the ranking on an MT-backed row (IM-1205 counted 10
        --     such positive fund assignments on Long Island). Those take their
        --     Opportunity from the MT-anchored branch of membership_transactions.sql,
        --     which gates on COALESCE(rgi.InstallmentDate, rmft.FinancialTransactionDate,
        --     mt.TRANSACTIONDATE) - the identical expression this file uses - so they
        --     already travel together, and moving their window would BREAK that pairing;
        --   * the rows own_so rescues are order-backed, so their Opportunity comes from
        --     the other branch, which gates on COALESCE(obm.FinancialTransactionDate,
        --     obm.SalesOrderTransactionDate) - the Order's date. Two different gate
        --     chains, which is why these rows and only these rows need the exception.
        --
        -- Date filter mirrors the CloseDate fallback chain used by the MT-anchored
        -- branch of membership_transactions.sql. Using rmft.FinancialTransactionDate
        -- alone drops $0 comp rows where rmft is NULL, because NULL >= @filterDateFrom
        -- evaluates to NULL (falsy in WHERE), producing orphan opportunities without
        -- a matching fund assignment under any date-windowed run.
        AND (
            @useDateFrom = 0
            OR CAST(COALESCE(rgi.InstallmentDate, CASE WHEN COALESCE(so.ID, addon_so.ID, revenue_so.ID, payment_so.ID) IS NULL AND own_so.ID IS NOT NULL THEN own_ft.CALCULATEDDATE END, rmft.FinancialTransactionDate, mt.TRANSACTIONDATE) AS DATE) >= @filterDateFrom
        )
        AND (
            @useDateTo = 0
            OR CAST(COALESCE(rgi.InstallmentDate, CASE WHEN COALESCE(so.ID, addon_so.ID, revenue_so.ID, payment_so.ID) IS NULL AND own_so.ID IS NOT NULL THEN own_ft.CALCULATEDDATE END, rmft.FinancialTransactionDate, mt.TRANSACTIONDATE) AS DATE) <= @filterDateTo
        )
) q GROUP BY own_so_only, yr ORDER BY 1, 2;