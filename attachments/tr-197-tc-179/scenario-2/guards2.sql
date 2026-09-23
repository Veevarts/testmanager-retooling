/* TC-179 escenario 2 — la guarda 2 acotada al alcance que el autor declara.
   El autor escribe: "Two NULL-source Standard lines ON A SINGLE-ITEM CREDIT ...
   Measured on Long Island: 0 refunds carry more than one such line today".
   La medicion anterior (3.379) no estaba acotada a comprobantes de un solo item ni a
   items de membresia, asi que no contradice esa frase. Aqui se mide su poblacion exacta,
   en tres niveles. Solo lectura. */
WITH Refunds AS (
    SELECT
        ft.ID AS RefundID,
        (SELECT COUNT(*) FROM CREDITITEM c WHERE c.CREDITID = ft.ID) AS n_items_credito,
        (SELECT COUNT(*) FROM FINANCIALTRANSACTIONLINEITEM s
          WHERE s.FINANCIALTRANSACTIONID = ft.ID
            AND s.[TYPE] = 'Standard'
            AND s.SOURCELINEITEMID IS NULL) AS n_lineas_sin_origen,
        CASE WHEN EXISTS (
                SELECT 1 FROM CREDITITEM ci
                INNER JOIN SALESORDERITEMMEMBERSHIP soim
                    ON soim.ID = ci.SALESORDERITEMID
                   AND soim.MEMBERSHIPTRANSACTIONID IS NULL
                WHERE ci.CREDITID = ft.ID)
             THEN 1 ELSE 0 END AS tiene_item_membresia_por_orden
    FROM FINANCIALTRANSACTION ft
    WHERE ft.[TYPE] = 'Refund'
)
SELECT 'A_reembolsos_con_al_menos_una_linea_sin_origen' AS metric, COUNT(*) AS n
FROM Refunds WHERE n_lineas_sin_origen >= 1
UNION ALL
SELECT 'B_de_esos_con_credito_de_UN_solo_item', COUNT(*)
FROM Refunds WHERE n_lineas_sin_origen >= 1 AND n_items_credito = 1
UNION ALL
SELECT 'C_de_esos_cuyo_item_ES_membresia_por_orden', COUNT(*)
FROM Refunds WHERE n_lineas_sin_origen >= 1 AND n_items_credito = 1 AND tiene_item_membresia_por_orden = 1
UNION ALL
SELECT 'D_POBLACION_DE_LA_GUARDA_dos_o_mas_lineas_en_C', COUNT(*)
FROM Refunds WHERE n_lineas_sin_origen >= 2 AND n_items_credito = 1 AND tiene_item_membresia_por_orden = 1
UNION ALL
SELECT 'E_dos_o_mas_lineas_con_credito_de_un_item_sin_exigir_membresia', COUNT(*)
FROM Refunds WHERE n_lineas_sin_origen >= 2 AND n_items_credito = 1
UNION ALL
SELECT 'F_guarda1_credito_multi_item_con_item_membresia_por_orden', COUNT(*)
FROM Refunds WHERE n_lineas_sin_origen >= 1 AND n_items_credito > 1 AND tiene_item_membresia_por_orden = 1
UNION ALL
SELECT 'G_max_lineas_sin_origen_en_un_reembolso_de_C', MAX(n_lineas_sin_origen)
FROM Refunds WHERE n_items_credito = 1 AND tiene_item_membresia_por_orden = 1;
