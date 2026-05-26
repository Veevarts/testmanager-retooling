SET NOCOUNT ON;

/* ============================================================ */
/* IM-791 PR 118 — behavioral diff ticketing_only_program       */
/*                                                              */
/* El predicate removido fue:                                   */
/*   AND (@useStatus = 0 OR so.STATUS = @statusFilter)          */
/* El extractor SIEMPRE bindeaba @hasStatusFilter = 0           */
/* (no hay UI que setee status), asi que @useStatus = 0 siempre */
/* y el predicate evaluaba a (0 = 0 OR ...) = TRUE = no-op.     */
/*                                                              */
/* Pero el Dev dice "Cancelled rows now appear" — sugiriendo    */
/* que pre-fix las cancelled rows NO aparecian. Esto contradice */
/* la mecanica no-op. Comprobemos contra Tucson.                */
/* ============================================================ */

PRINT '=== R1: STATUS distribution en SALESORDER (universe baseline) ===';
SELECT
    so.STATUS                       AS so_status,
    COUNT(*)                        AS row_count
FROM SALESORDER so
WHERE EXISTS (
        SELECT 1
        FROM SALESORDERITEM soi
        INNER JOIN SALESORDERITEMTICKET soit ON soit.ID = soi.ID
        INNER JOIN PROGRAM p ON p.ID = soit.PROGRAMID
        WHERE soi.SALESORDERID = so.ID
)
GROUP BY so.STATUS
ORDER BY row_count DESC;

PRINT '=== R2: post-fix count (sin status filter) ===';
SELECT COUNT(DISTINCT so.ID) AS postfix_total_rows
FROM SALESORDER so
WHERE 1 = 1
  AND EXISTS (
        SELECT 1
        FROM SALESORDERITEM soi
        INNER JOIN SALESORDERITEMTICKET soit ON soit.ID = soi.ID
        INNER JOIN PROGRAM p ON p.ID = soit.PROGRAMID
        WHERE soi.SALESORDERID = so.ID
  );

PRINT '=== R3: pre-fix count simulando @useStatus=0 (no-op filter) ===';
DECLARE @useStatusSim BIT = 0;
DECLARE @statusFilterSim NVARCHAR(50) = '';
SELECT COUNT(DISTINCT so.ID) AS prefix_total_rows_no_op
FROM SALESORDER so
WHERE 1 = 1
  AND (@useStatusSim = 0 OR so.STATUS = @statusFilterSim)
  AND EXISTS (
        SELECT 1
        FROM SALESORDERITEM soi
        INNER JOIN SALESORDERITEMTICKET soit ON soit.ID = soi.ID
        INNER JOIN PROGRAM p ON p.ID = soit.PROGRAMID
        WHERE soi.SALESORDERID = so.ID
  );

PRINT '=== R4: Cancelled rows count (la cuenta que SUPUESTAMENTE no aparecia pre-fix) ===';
SELECT COUNT(DISTINCT so.ID) AS cancelled_rows
FROM SALESORDER so
WHERE so.STATUS = 'Cancelled'
  AND EXISTS (
        SELECT 1
        FROM SALESORDERITEM soi
        INNER JOIN SALESORDERITEMTICKET soit ON soit.ID = soi.ID
        INNER JOIN PROGRAM p ON p.ID = soit.PROGRAMID
        WHERE soi.SALESORDERID = so.ID
  );

PRINT '=== R5: PRE vs POST delta (deberia ser 0 si filter era no-op) ===';
WITH PostFix AS (
    SELECT COUNT(DISTINCT so.ID) AS n
    FROM SALESORDER so
    WHERE EXISTS (
            SELECT 1 FROM SALESORDERITEM soi
            INNER JOIN SALESORDERITEMTICKET soit ON soit.ID = soi.ID
            INNER JOIN PROGRAM p ON p.ID = soit.PROGRAMID
            WHERE soi.SALESORDERID = so.ID
    )
),
PreFix AS (
    SELECT COUNT(DISTINCT so.ID) AS n
    FROM SALESORDER so
    WHERE (0 = 0 OR so.STATUS = '')
      AND EXISTS (
            SELECT 1 FROM SALESORDERITEM soi
            INNER JOIN SALESORDERITEMTICKET soit ON soit.ID = soi.ID
            INNER JOIN PROGRAM p ON p.ID = soit.PROGRAMID
            WHERE soi.SALESORDERID = so.ID
      )
)
SELECT (SELECT n FROM PostFix) - (SELECT n FROM PreFix) AS delta_pre_to_post;
