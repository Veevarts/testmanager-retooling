WITH Donors AS (
    SELECT DISTINCT rmg.MGSOURCEREVENUEID AS DonorFinancialTransactionID
    FROM REVENUEMATCHINGGIFT rmg
    WHERE rmg.ISACTIVE = 1 AND rmg.MGSOURCEREVENUEID IS NOT NULL
),
Cand AS (
    SELECT dl.FINANCIALTRANSACTIONID AS DonorFinancialTransactionID,
           mt.ID AS MembershipTransactionID, mt.REVENUESPLITID AS MembershipRevenueSplitId
    FROM Donors d
    INNER JOIN FINANCIALTRANSACTIONLINEITEM dl
        ON dl.FINANCIALTRANSACTIONID = d.DonorFinancialTransactionID AND dl.[TYPE] = 'Standard'
    INNER JOIN MEMBERSHIPTRANSACTION mt ON mt.REVENUESPLITID = dl.ID
    UNION ALL
    SELECT dl.FINANCIALTRANSACTIONID, mt.ID, mt.REVENUESPLITID
    FROM Donors d
    INNER JOIN FINANCIALTRANSACTIONLINEITEM dl
        ON dl.FINANCIALTRANSACTIONID = d.DonorFinancialTransactionID AND dl.[TYPE] = 'Standard'
    INNER JOIN MEMBERSHIPTRANSACTION mt ON mt.REVENUESPLITID = dl.SOURCELINEITEMID
),
Anchors AS (
    SELECT c.MembershipTransactionID, c.DonorFinancialTransactionID,
           al.FINANCIALTRANSACTIONID AS AnchorFinancialTransactionID
    FROM Cand c
    INNER JOIN FINANCIALTRANSACTIONLINEITEM al
        ON al.ID = c.MembershipRevenueSplitId AND al.[TYPE] = 'Standard'
    UNION
    SELECT c.MembershipTransactionID, c.DonorFinancialTransactionID, al.FINANCIALTRANSACTIONID
    FROM Cand c
    INNER JOIN FINANCIALTRANSACTIONLINEITEM al
        ON al.SOURCELINEITEMID = c.MembershipRevenueSplitId AND al.[TYPE] = 'Standard'
)
SELECT
    COUNT(DISTINCT a.MembershipTransactionID)                                        AS MembershipsReached,
    COUNT(DISTINCT CASE WHEN a.AnchorFinancialTransactionID <> a.DonorFinancialTransactionID
                        THEN a.MembershipTransactionID END)                          AS WithAnchorOtherThanDonor,
    COUNT(DISTINCT CASE WHEN unfinished.ID IS NOT NULL
                        THEN a.MembershipTransactionID END)                          AS AnchorHasUnfinishedOrder,
    COUNT(DISTINCT CASE WHEN rgi.ID IS NOT NULL
                        THEN a.MembershipTransactionID END)                          AS AnchorHasRecurringInstallment
FROM Anchors a
LEFT JOIN SALESORDER unfinished
    ON unfinished.REVENUEID = a.AnchorFinancialTransactionID AND unfinished.STATUSCODE IN (0, 6, 7)
LEFT JOIN RECURRINGGIFTINSTALLMENT rgi
    ON rgi.REVENUEID = a.AnchorFinancialTransactionID;
