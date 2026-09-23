/* TC-179 escenario 5 — fechas del registro rescatado (orden 8-10041986) y de su duplicado.
   La fecha del reembolso (2012-07-09) ya consta en scenario-7/: es la fila
   C_pre_existing de la orden 8-10041986. Aqui se mide la fecha de la ORDEN. */
SELECT
    so.LOOKUPID                           AS orden,
    CAST(so.TRANSACTIONDATE AS DATE)      AS fecha_orden,
    CAST(order_ft.CALCULATEDDATE AS DATE) AS fecha_transaccion_de_la_orden,
    order_ft.[TYPE]                       AS tipo_transaccion,
    DATEDIFF(DAY, so.TRANSACTIONDATE, '2012-07-09') AS dias_hasta_el_reembolso
FROM SALESORDER so
LEFT JOIN FINANCIALTRANSACTION order_ft ON order_ft.ID = so.REVENUEID
WHERE so.LOOKUPID IN ('8-10041986', '8-10041566', '8-10036876');
