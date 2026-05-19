SET NOCOUNT ON;

/* ============================================================ */
/* IM-696 PR 109 — Tucson catalog inventory (corregido)           */
/* Replica el filtro real del query nuevo (attributes.sql):       */
/*   ac.FLAGGEDFORDELETE = 0                                      */
/*   AND ac.FLAGGEDFOREXTENSIONREMOVAL = 0                        */
/*   JOIN TABLECATALOG tc ON tc.ID = ac.TABLECATALOGID            */
/*   JOIN INFORMATION_SCHEMA.TABLES it ON it.TABLE_NAME = tc.TABLENAME */
/*   JOIN INFORMATION_SCHEMA.COLUMNS ic ON ic.TABLE_NAME = tc.TABLENAME */
/*                                       AND ic.COLUMN_NAME = 'CONSTITUENTID' */
/* PR baseline (sha b58ac472c40c, 2026-05-11):                    */
/*   103 active categories / 69,563 active rows / 62,647 emitted  */
/* ============================================================ */

PRINT '=== R1: ATTRIBUTECATEGORY total ===';
SELECT COUNT(*) AS total_categories FROM ATTRIBUTECATEGORY;

PRINT '=== R2: Categorias no flaggeadas (FLAGGEDFORDELETE=0 AND FLAGGEDFOREXTENSIONREMOVAL=0) ===';
SELECT COUNT(*) AS not_flagged
FROM ATTRIBUTECATEGORY
WHERE FLAGGEDFORDELETE = 0
  AND FLAGGEDFOREXTENSIONREMOVAL = 0;

PRINT '=== R3: Categorias activas + tabla fisica existe + columna CONSTITUENTID presente (constituent-scoped) ===';
SELECT COUNT(DISTINCT ac.ID) AS active_constituent_scoped
FROM ATTRIBUTECATEGORY ac
JOIN TABLECATALOG tc ON tc.ID = ac.TABLECATALOGID
JOIN INFORMATION_SCHEMA.TABLES it ON it.TABLE_NAME = tc.TABLENAME
JOIN INFORMATION_SCHEMA.COLUMNS ic ON ic.TABLE_NAME = tc.TABLENAME AND ic.COLUMN_NAME = 'CONSTITUENTID'
WHERE ac.FLAGGEDFORDELETE = 0
  AND ac.FLAGGEDFOREXTENSIONREMOVAL = 0;

PRINT '=== R4: Categorias huerfanas (no flaggeadas pero sin tabla fisica) ===';
SELECT COUNT(*) AS active_orphans
FROM ATTRIBUTECATEGORY ac
JOIN TABLECATALOG tc ON tc.ID = ac.TABLECATALOGID
LEFT JOIN INFORMATION_SCHEMA.TABLES it ON it.TABLE_NAME = tc.TABLENAME
WHERE ac.FLAGGEDFORDELETE = 0
  AND ac.FLAGGEDFOREXTENSIONREMOVAL = 0
  AND it.TABLE_NAME IS NULL;

PRINT '=== R5: Categorias no flaggeadas con tabla fisica pero SIN columna CONSTITUENTID (no constituent-scoped, descartadas por el query) ===';
SELECT COUNT(DISTINCT ac.ID) AS active_with_table_no_constituent_col
FROM ATTRIBUTECATEGORY ac
JOIN TABLECATALOG tc ON tc.ID = ac.TABLECATALOGID
JOIN INFORMATION_SCHEMA.TABLES it ON it.TABLE_NAME = tc.TABLENAME
LEFT JOIN INFORMATION_SCHEMA.COLUMNS ic ON ic.TABLE_NAME = tc.TABLENAME AND ic.COLUMN_NAME = 'CONSTITUENTID'
WHERE ac.FLAGGEDFORDELETE = 0
  AND ac.FLAGGEDFOREXTENSIONREMOVAL = 0
  AND ic.COLUMN_NAME IS NULL;

PRINT '=== R6: Distribucion por DATATYPECODE de las categorias activas constituent-scoped ===';
SELECT
    ac.DATATYPECODE,
    COUNT(*) AS n,
    CASE ac.DATATYPECODE
        WHEN 0 THEN 'Text'
        WHEN 1 THEN 'Number'
        WHEN 2 THEN 'Date'
        WHEN 3 THEN 'Currency'
        WHEN 4 THEN 'Code Table'
        WHEN 5 THEN 'Yes/No'
        ELSE 'Other'
    END AS data_type_label
FROM ATTRIBUTECATEGORY ac
JOIN TABLECATALOG tc ON tc.ID = ac.TABLECATALOGID
JOIN INFORMATION_SCHEMA.TABLES it ON it.TABLE_NAME = tc.TABLENAME
JOIN INFORMATION_SCHEMA.COLUMNS ic ON ic.TABLE_NAME = tc.TABLENAME AND ic.COLUMN_NAME = 'CONSTITUENTID'
WHERE ac.FLAGGEDFORDELETE = 0
  AND ac.FLAGGEDFOREXTENSIONREMOVAL = 0
GROUP BY ac.DATATYPECODE
ORDER BY ac.DATATYPECODE;

PRINT '=== R7: Total approximate rows across active constituent-scoped categories (catalog stats) ===';
SELECT SUM(CAST(p.rows AS BIGINT)) AS approx_total_rows
FROM ATTRIBUTECATEGORY ac
JOIN TABLECATALOG tc ON tc.ID = ac.TABLECATALOGID
JOIN INFORMATION_SCHEMA.TABLES it ON it.TABLE_NAME = tc.TABLENAME
JOIN INFORMATION_SCHEMA.COLUMNS ic ON ic.TABLE_NAME = tc.TABLENAME AND ic.COLUMN_NAME = 'CONSTITUENTID'
JOIN sys.tables st ON st.name = tc.TABLENAME
JOIN sys.partitions p ON p.object_id = st.object_id
WHERE ac.FLAGGEDFORDELETE = 0
  AND ac.FLAGGEDFOREXTENSIONREMOVAL = 0
  AND p.index_id IN (0, 1);

PRINT '=== R8: CODETABLECATALOG sanity — confirmar que DBTABLENAME es el campo de catalog name (NO TABLENAME) ===';
SELECT TOP 1
    CASE WHEN COL_LENGTH('CODETABLECATALOG', 'DBTABLENAME') IS NOT NULL THEN 1 ELSE 0 END AS has_dbtablename_col,
    CASE WHEN COL_LENGTH('CODETABLECATALOG', 'TABLENAME')   IS NOT NULL THEN 1 ELSE 0 END AS has_tablename_col
FROM CODETABLECATALOG;
