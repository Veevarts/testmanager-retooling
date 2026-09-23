-- TC-178 escenario 6 (afinado) — separar el hueco REAL del ruido de historico.
-- Que una membresia tenga varias transacciones no significa que el reembolso las abarque:
-- el rango 1 elige la mas reciente, y para la inmensa mayoria eso es lo correcto.
-- El caso que el PR describe es otro: un reembolso que abarca MAS que la transaccion mas
-- nueva. Se aproxima con el mismo criterio que usa la compuerta de dolares del propio
-- archivo (lineas 380-382): ABS(reembolso) >= ABS(importe de la transaccion).
-- Solo lectura. Salida puramente numerica.
WITH rm AS (
    SELECT
        mt.ID                         AS MembershipTransactionID,
        mt.REVENUESPLITID             AS RevenueSplitId,
        refund_ft.ID                  AS RefundId,
        cim.MEMBERSHIPID              AS MembershipId,
        refund_line.TRANSACTIONAMOUNT AS RefundAmount,
        ROW_NUMBER() OVER (
            PARTITION BY refund_ft.ID, cim.MEMBERSHIPID
            ORDER BY mt.TRANSACTIONDATE DESC, mt.ID DESC
        ) AS RefundMatchRank
    FROM FINANCIALTRANSACTION refund_ft
    INNER JOIN FINANCIALTRANSACTIONLINEITEM refund_line
        ON refund_line.FINANCIALTRANSACTIONID = refund_ft.ID
       AND refund_line.[TYPE] = 'Standard'
    CROSS APPLY (
        SELECT cim_by_source.MEMBERSHIPID
        FROM CREDITITEMMEMBERSHIP cim_by_source
        WHERE cim_by_source.ID = refund_line.SOURCELINEITEMID
        UNION ALL
        SELECT cim_by_line.MEMBERSHIPID
        FROM CREDITITEMMEMBERSHIP cim_by_line
        WHERE cim_by_line.ID = refund_line.ID
    ) cim
    INNER JOIN MEMBERSHIPTRANSACTION mt
        ON mt.MEMBERSHIPID = cim.MEMBERSHIPID
       AND mt.TRANSACTIONDATE <= refund_ft.CALCULATEDDATE
    WHERE refund_ft.[TYPE] = 'Refund'
),
PerPartition AS (
    SELECT
        r.RefundId,
        r.MembershipId,
        COUNT_BIG(DISTINCT r.MembershipTransactionID) AS distinct_mts,
        MAX(CASE WHEN r.RefundMatchRank = 1 THEN ABS(r.RefundAmount) END)               AS rank1_refund_abs,
        MAX(CASE WHEN r.RefundMatchRank = 1 THEN ABS(ISNULL(ol.TRANSACTIONAMOUNT, 0)) END) AS rank1_line_abs
    FROM rm r
    LEFT JOIN FINANCIALTRANSACTIONLINEITEM ol
        ON ol.ID = r.RevenueSplitId
       AND ol.[TYPE] = 'Standard'
    GROUP BY r.RefundId, r.MembershipId
)
SELECT
    COUNT_BIG(1)                                                     AS partitions_total,
    SUM(CASE WHEN distinct_mts > 1 THEN 1 ELSE 0 END)                AS partitions_with_several_mts,
    -- el reembolso NO cubre siquiera la mas nueva: parcial, el caso que este PR libera
    SUM(CASE WHEN rank1_refund_abs < rank1_line_abs THEN 1 ELSE 0 END) AS rank1_partial_refund,
    -- el reembolso cubre la mas nueva Y sobra: candidato a alcanzar tambien a una anterior
    SUM(CASE WHEN distinct_mts > 1 AND rank1_refund_abs > rank1_line_abs
             THEN 1 ELSE 0 END)                                      AS refund_exceeds_newest,
    SUM(CASE WHEN distinct_mts > 1 AND rank1_refund_abs > rank1_line_abs
             THEN distinct_mts - 1 ELSE 0 END)                       AS older_mts_behind_those
FROM PerPartition;
