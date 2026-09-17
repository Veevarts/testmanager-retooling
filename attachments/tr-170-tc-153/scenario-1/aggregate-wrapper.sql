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
)

-- Wrapper aggregate: quantify what fund_assignment_memberships.sql's
-- Auctifera__Posted_Date__c change would move.
-- PRE: COALESCE(rgi.InstallmentDate, rmft.FinancialTransactionDate)
-- POST: COALESCE(rgi.InstallmentDate, own_ft.CALCULATEDDATE, rmft.FinancialTransactionDate, mt.TRANSACTIONDATE)
SELECT
    COUNT(*) AS total_membership_lines,
    SUM(CASE WHEN mli.OwnFinancialTransactionID IS NOT NULL THEN 1 ELSE 0 END) AS lines_with_own_ft,
    SUM(CASE WHEN own_ft.ID IS NULL THEN 1 ELSE 0 END) AS lines_missing_own_ft,
    SUM(CASE
        WHEN rgi.InstallmentDate IS NULL
         AND own_ft.CALCULATEDDATE IS NOT NULL
         AND rmft.FinancialTransactionDate IS NOT NULL
         AND CAST(own_ft.CALCULATEDDATE AS DATE) <> CAST(rmft.FinancialTransactionDate AS DATE)
        THEN 1 ELSE 0 END) AS delta_line_items,
    SUM(CASE
        WHEN rgi.InstallmentDate IS NULL
         AND own_ft.CALCULATEDDATE IS NOT NULL
         AND rmft.FinancialTransactionDate IS NOT NULL
         AND (YEAR(own_ft.CALCULATEDDATE) <> YEAR(rmft.FinancialTransactionDate)
              OR MONTH(own_ft.CALCULATEDDATE) <> MONTH(rmft.FinancialTransactionDate))
        THEN 1 ELSE 0 END) AS delta_month_or_year_jump,
    SUM(CASE
        WHEN rgi.InstallmentDate IS NULL
         AND YEAR(own_ft.CALCULATEDDATE) <> YEAR(rmft.FinancialTransactionDate)
        THEN 1 ELSE 0 END) AS delta_year_jump,
    SUM(CASE
        WHEN rgi.InstallmentDate IS NOT NULL
         AND own_ft.CALCULATEDDATE IS NOT NULL
         AND rmft.FinancialTransactionDate IS NOT NULL
         AND CAST(own_ft.CALCULATEDDATE AS DATE) <> CAST(rmft.FinancialTransactionDate AS DATE)
        THEN 1 ELSE 0 END) AS recurring_would_have_changed_but_installment_wins,
    SUM(CASE WHEN rgi.InstallmentDate IS NOT NULL THEN 1 ELSE 0 END) AS recurring_rows_total,
    SUM(CASE
        WHEN rgi.InstallmentDate IS NULL
         AND own_ft.[TYPE] = 'Refund'
         AND rmft.FinancialTransactionID <> own_ft.ID
        THEN 1 ELSE 0 END) AS lines_where_own_ft_is_refund_and_ranked_child_differs
FROM MembershipLineItems mli
LEFT JOIN FINANCIALTRANSACTION own_ft ON own_ft.ID = mli.OwnFinancialTransactionID
LEFT JOIN ResolvedMembershipFinancialTransactions rmft
     ON rmft.SourceLineItemID = mli.LineItemID AND rmft.ResolutionRank = 1
LEFT JOIN RecurringInstallments rgi
     ON rgi.FinancialTransactionID = own_ft.ID;
