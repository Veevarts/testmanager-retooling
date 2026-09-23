-- TC-178 escenario 6 — el hueco del RefundMatchRank, que este PR deja sin respaldo.
-- La rama B de #RefundedMembershipTransactions particiona por (reembolso, membresia) y
-- conserva SOLO la transaccion mas reciente (RefundMatchRank = 1). Si un reembolso deberia
-- alcanzar varias transacciones de una misma membresia, solo se marca la mas nueva.
-- Hasta este PR eso lo tapaba la bandera de cantidad; ahora no.
-- La logica de abajo es copia literal de la derivada `rm` de la consulta (lineas 337-371).
-- Solo lectura. Salida puramente numerica.
WITH rm AS (
    SELECT
        mt.ID                         AS MembershipTransactionID,
        refund_ft.ID                  AS RefundId,
        cim.MEMBERSHIPID              AS MembershipId,
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
        RefundId,
        MembershipId,
        COUNT_BIG(DISTINCT MembershipTransactionID) AS distinct_mts
    FROM rm
    GROUP BY RefundId, MembershipId
)
SELECT
    COUNT_BIG(1)                                                    AS partitions_total,
    SUM(CASE WHEN distinct_mts > 1 THEN 1 ELSE 0 END)               AS partitions_with_several_mts,
    SUM(CASE WHEN distinct_mts > 1 THEN distinct_mts - 1 ELSE 0 END) AS mts_left_unflagged,
    MAX(distinct_mts)                                               AS max_mts_in_one_partition
FROM PerPartition;
