/* TC-179 escenario 6 — radio de impacto COMPLETO del filtro de descuentos.

   El filtro nuevo es: WHERE xli.[TYPE]='Discount' AND ISNULL(xft.[TYPE],'') <> 'Refund'.
   Se replica en cuatro archivos. En membership_transactions.sql el CTE alimenta DOS
   consumidores, no uno:
     (a) la linea de membresia  -> Amount y vnfp__Discount_Amount__c
     (b) la linea de ADD-ON     -> #MembershipTransactionAddOnLineItems.AddOnTotal
   El autor solo declara cifras para (a). Aqui se mide el conjunto ENTERO de lineas
   cuyo descuento cambia, y se reparte entre los dos consumidores. Solo lectura. */
WITH DiscountDelta AS (
    SELECT
        xli.SOURCELINEITEMID,
        SUM(xli.TRANSACTIONAMOUNT) AS old_amount,
        SUM(CASE WHEN ISNULL(xft.[TYPE], '') <> 'Refund' THEN xli.TRANSACTIONAMOUNT ELSE 0 END) AS new_amount
    FROM FINANCIALTRANSACTIONLINEITEM xli
    LEFT JOIN FINANCIALTRANSACTION xft ON xft.ID = xli.FINANCIALTRANSACTIONID
    WHERE xli.[TYPE] = 'Discount'
    GROUP BY xli.SOURCELINEITEMID
),
Changed AS (
    SELECT * FROM DiscountDelta WHERE old_amount <> new_amount
)
SELECT 'A_lineas_con_descuento_afectadas' AS metric, COUNT(*) AS n, SUM(c.old_amount - c.new_amount) AS delta
FROM Changed c
UNION ALL
SELECT 'B_de_esas_que_son_linea_de_MEMBRESIA', COUNT(*), SUM(c.old_amount - c.new_amount)
FROM Changed c
WHERE EXISTS (SELECT 1 FROM REVENUESPLIT_EXT rse
              WHERE rse.ID = c.SOURCELINEITEMID AND rse.APPLICATION = 'Membership')
UNION ALL
SELECT 'C_de_esas_que_son_linea_de_ADD_ON', COUNT(*), SUM(c.old_amount - c.new_amount)
FROM Changed c
WHERE EXISTS (SELECT 1 FROM REVENUESPLIT_EXT rse
              WHERE rse.ID = c.SOURCELINEITEMID AND rse.APPLICATION = 'Membership add-on')
UNION ALL
SELECT 'D_de_esas_que_NO_son_ni_membresia_ni_addon', COUNT(*), SUM(c.old_amount - c.new_amount)
FROM Changed c
WHERE NOT EXISTS (SELECT 1 FROM REVENUESPLIT_EXT rse
                  WHERE rse.ID = c.SOURCELINEITEMID
                    AND rse.APPLICATION IN ('Membership', 'Membership add-on'))
UNION ALL
SELECT 'E_anio_minimo_afectado', MIN(YEAR(ft2.CALCULATEDDATE)), NULL
FROM Changed c
INNER JOIN FINANCIALTRANSACTIONLINEITEM l ON l.ID = c.SOURCELINEITEMID
INNER JOIN FINANCIALTRANSACTION ft2 ON ft2.ID = l.FINANCIALTRANSACTIONID
UNION ALL
SELECT 'F_anio_maximo_afectado', MAX(YEAR(ft2.CALCULATEDDATE)), NULL
FROM Changed c
INNER JOIN FINANCIALTRANSACTIONLINEITEM l ON l.ID = c.SOURCELINEITEMID
INNER JOIN FINANCIALTRANSACTION ft2 ON ft2.ID = l.FINANCIALTRANSACTIONID;
