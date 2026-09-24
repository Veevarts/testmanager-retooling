WITH q AS (
SELECT
        csc.ID AS Implementation_External_ID__c,
        CASE
                WHEN c.ISORGANIZATION = 0
                     AND c.ISGROUP = 0
                     AND c.ISCONSTITUENT = 1
                THEN c.ID
                ELSE NULL
        END AS Contact__c,
        CASE
                WHEN c.ISORGANIZATION = 1
                     OR c.ISGROUP = 1
                THEN c.ID
                ELSE NULL
        END AS Household_Organization__c,
        c.ID AS ConstituentID,
        sc.ID AS SolicitCodeID,
        csc.STARTDATE AS StartDate,
        csc.ENDDATE AS EndDate
FROM CONSTITUENTSOLICITCODE csc
        JOIN CONSTITUENT c ON
                c.ID = csc.CONSTITUENTID
        JOIN SOLICITCODE sc ON
                sc.ID = csc.SOLICITCODEID
)
SELECT
    CASE WHEN ConstituentID = '2E68B251-61E6-4668-98C3-ECDBEFBBC2DE'
         THEN 'Ejemplo-1' ELSE 'Ejemplo-2' END                       AS Ejemplo,
    CAST(Implementation_External_ID__c AS VARCHAR(36))               AS IdExternoEmitido,
    CASE WHEN Contact__c IS NOT NULL THEN 1 ELSE 0 END               AS ContactoInformado,
    CASE WHEN Household_Organization__c IS NOT NULL THEN 1 ELSE 0 END AS OrganizacionInformada,
    CASE WHEN CAST(Contact__c AS VARCHAR(36)) = CAST(ConstituentID AS VARCHAR(36))
         THEN 1 ELSE 0 END                                           AS ContactoEsElIdDeConstituyente,
    CASE WHEN SolicitCodeID = '333F7D7F-833A-4ECE-8D44-5D3C80E363E0'
         THEN 1 ELSE 0 END                                           AS EsElCodigoDelTicket,
    CAST(StartDate AS DATE)                                          AS Inicio,
    CAST(EndDate AS DATE)                                            AS Fin
FROM q
WHERE ConstituentID IN (
        '2E68B251-61E6-4668-98C3-ECDBEFBBC2DE',
        'B14F7EB8-1C1B-4EDC-A627-3194AA5C272E')
ORDER BY Ejemplo, IdExternoEmitido;
