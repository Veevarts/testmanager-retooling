SELECT
        'CONSTITUENCY' AS QueryGroup,
        cy.ID AS Implementation_External_ID__c,
        CASE
                WHEN ct.ISCONSTITUENT = 1
                AND ct.ISGROUP = 0
                AND ct.ISORGANIZATION = 0 THEN ct.ID
                ELSE NULL
        END AS Contact__c,
        CASE
                WHEN ct.ISGROUP = 1
                OR ct.ISORGANIZATION = 1 THEN ct.ID
                ELSE ch.HOUSEHOLDID
        END AS Organization__c,
        cc.DESCRIPTION AS Constituency__c,
        cc.ACTIVE AS Is_Active__c,
        cy.DATEFROM AS Date_From__c,
        cy.DATETO AS Date_To__c
FROM
        CONSTITUENCY cy
JOIN CONSTITUENT ct ON
        cy.CONSTITUENTID = ct.ID
LEFT JOIN CONSTITUENTHOUSEHOLD ch ON
        ch.ID = ct.ID
JOIN CONSTITUENCYCODE cc ON
        cc.ID = cy.CONSTITUENCYCODEID
UNION
SELECT
        'BOARDMEMBERDATERANGE' AS QueryGroup,
        bmdr.ID AS Implementation_External_ID__c,
        CASE
                WHEN ct.ISCONSTITUENT = 1
                AND ct.ISGROUP = 0
                AND ct.ISORGANIZATION = 0 THEN ct.ID
                ELSE NULL
        END AS Contact__c,
        CASE
                WHEN ct.ISGROUP = 1
                OR ct.ISORGANIZATION = 1 THEN ct.ID
                ELSE ch.HOUSEHOLDID
        END AS Organization__c,
        'Board Member' AS Constituency__c,
        CASE
                WHEN bmdr.DATETO IS NULL THEN 1
                ELSE 0
        END AS Is_Active__c,
        bmdr.DATEFROM AS Date_From__c,
        bmdr.DATETO AS Date_To__c
FROM
                BOARDMEMBERDATERANGE bmdr
JOIN CONSTITUENT ct ON
                bmdr.CONSTITUENTID = ct.ID
LEFT JOIN CONSTITUENTHOUSEHOLD ch ON
                ch.ID = ct.ID
UNION
SELECT
        'VOLUNTEERDATERANGE' AS QueryGroup,
        vdr.ID AS Implementation_External_ID__c,
        CASE
                WHEN ct.ISCONSTITUENT = 1
                AND ct.ISGROUP = 0
                AND ct.ISORGANIZATION = 0 THEN ct.ID
                ELSE NULL
        END AS Contact__c,
        CASE
                WHEN ct.ISGROUP = 1
                OR ct.ISORGANIZATION = 1 THEN ct.ID
                ELSE ch.HOUSEHOLDID
        END AS Organization__c,
        'Volunteer' AS Constituency__c,
        CASE
                WHEN vdr.DATETO IS NULL THEN 1
                ELSE 0
        END AS Is_Active__c,
        vdr.DATEFROM AS Date_From__c,
        vdr.DATETO AS Date_To__c
FROM
                VOLUNTEERDATERANGE vdr
JOIN CONSTITUENT ct ON
                vdr.CONSTITUENTID = ct.ID
LEFT JOIN CONSTITUENTHOUSEHOLD ch ON
                ch.ID = ct.ID
UNION
SELECT
        'STAFFDATERANGE' AS QueryGroup,
        sdr.ID AS Implementation_External_ID__c,
        CASE
                WHEN ct.ISCONSTITUENT = 1
                AND ct.ISGROUP = 0
                AND ct.ISORGANIZATION = 0 THEN ct.ID
                ELSE NULL
        END AS Contact__c,
        CASE
                WHEN ct.ISGROUP = 1
                OR ct.ISORGANIZATION = 1 THEN ct.ID
                ELSE ch.HOUSEHOLDID
        END AS Organization__c,
        'Staff' AS Constituency__c,
        CASE
                WHEN sdr.DATETO IS NULL THEN 1
                ELSE 0
        END AS Is_Active__c,
        sdr.DATEFROM AS Date_From__c,
        sdr.DATETO AS Date_To__c
FROM
                STAFFDATERANGE sdr
JOIN CONSTITUENT ct ON
                sdr.CONSTITUENTID = ct.ID
LEFT JOIN CONSTITUENTHOUSEHOLD ch ON
        ch.ID = ct.ID
UNION
SELECT
        'FUNDRAISERDATERANGE' AS QueryGroup,
        fdr.ID AS Implementation_External_ID__c,
        CASE
                WHEN ct.ISCONSTITUENT = 1
                AND ct.ISGROUP = 0
                AND ct.ISORGANIZATION = 0 THEN ct.ID
                ELSE NULL
        END AS Contact__c,
        CASE
                WHEN ct.ISGROUP = 1
                OR ct.ISORGANIZATION = 1 THEN ct.ID
                ELSE ch.HOUSEHOLDID
        END AS Organization__c,
        'Fundraiser' AS Constituency__c,
        CASE
                WHEN fdr.DATETO IS NULL THEN 1
                ELSE 0
        END AS Is_Active__c,
        fdr.DATEFROM AS Date_From__c,
        fdr.DATETO AS Date_To__c
FROM
                FUNDRAISERDATERANGE fdr
JOIN CONSTITUENT ct ON
                fdr.CONSTITUENTID = ct.ID
LEFT JOIN CONSTITUENTHOUSEHOLD ch ON
        ch.ID = ct.ID
        

        