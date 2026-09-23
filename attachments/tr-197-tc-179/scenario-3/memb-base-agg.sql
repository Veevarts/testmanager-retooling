DECLARE @hasDateFilterFrom BIT = 0;
DECLARE @hasDateFilterTo BIT = 0;
DECLARE @dateFilterFrom DATE = NULL;
DECLARE @dateFilterTo DATE = NULL;

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
SELECT yr, COUNT(*) AS n_rows, SUM(amt) AS sum_amt, SUM(CASE WHEN amt = 0 THEN 1 ELSE 0 END) AS n_en_cero FROM (
SELECT
    CASE WHEN rgi.RecurringInstallmentID IS NOT NULL THEN rgi.InstallmentAmount
         ELSE mli.Amount - COALESCE(xli.DiscountAmount, 0) END AS amt,
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
        -- IM-621: matches the relaxed inclusion gate in membership_transactions.sql
        -- so every $0 membership opportunity still receives its fund assignment.
        -- The outer membership-anchor check above already filters true orphans.
        --
        -- Date filter mirrors the CloseDate fallback chain used by the MT-anchored
        -- branch of membership_transactions.sql. Using rmft.FinancialTransactionDate
        -- alone drops $0 comp rows where rmft is NULL, because NULL >= @filterDateFrom
        -- evaluates to NULL (falsy in WHERE), producing orphan opportunities without
        -- a matching fund assignment under any date-windowed run.
        AND (
            @useDateFrom = 0
            OR CAST(COALESCE(rgi.InstallmentDate, rmft.FinancialTransactionDate, mt.TRANSACTIONDATE) AS DATE) >= @filterDateFrom
        )
        AND (
            @useDateTo = 0
            OR CAST(COALESCE(rgi.InstallmentDate, rmft.FinancialTransactionDate, mt.TRANSACTIONDATE) AS DATE) <= @filterDateTo
        )
) q GROUP BY yr ORDER BY 1;