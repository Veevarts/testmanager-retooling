WITH q AS (
SELECT
        c.ID AS ConstituentID,
        c.NAME AS ConstituentName,
        sc.ID AS SolicitCodeID,
        sc.DESCRIPTION AS SolicitCodeDescription,
        sc.ACTIVE AS SolicitCodeActive,
        sc.SITEID AS SolicitCodeSiteID,
        sc.EXCLUSIONCODE AS SolicitCodeExclusionCode,
        sc.EXCLUSION AS SolicitCodeExclusion,
        csc.STARTDATE AS ConstituentSolicitCodeStartDate,
        csc.ENDDATE AS ConstituentSolicitCodeEndDate
FROM CONSTITUENTSOLICITCODE csc
        JOIN CONSTITUENT c ON
                c.ID = csc.CONSTITUENTID
        JOIN SOLICITCODE sc ON
                sc.ID = csc.SOLICITCODEID
)
SELECT COUNT(*) AS Filas FROM q;