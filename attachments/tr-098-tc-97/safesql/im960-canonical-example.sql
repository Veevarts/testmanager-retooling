-- IM-960 canonical example: verify 5701BD79-05F3-4ED5-A1D1-B882AB44C299 is a Payment,
-- and find the correct Order/donation FT that the source_dli anchor now returns.
DECLARE @badId UNIQUEIDENTIFIER = '5701BD79-05F3-4ED5-A1D1-B882AB44C299';

-- 1. Classify the bad ID
SELECT
    'Bad ID characterization' AS section,
    ft.ID,
    ft.[TYPE] AS ft_type,
    ft.CALCULATEDUSERDEFINEDID AS revenue_id,
    ft.[DATE] AS ft_date,
    CAST(ft.TRANSACTIONAMOUNT AS DECIMAL(18,2)) AS amount
FROM FINANCIALTRANSACTION ft
WHERE ft.ID = @badId;
