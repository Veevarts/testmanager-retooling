-- QA IM-1300 · el predicado, medido sobre las tablas de Altru (solo agregados).
-- Cota superior: no aplica los demas filtros de la exportacion, solo el de Drop.
-- p1: camino NUEVO de por vida (termino sin fecha sobre membresia CON expiracion). Antes: fin vacio.
-- p3: lo que el arreglo corrige (membresia no activa sin expiracion, termino con fecha). Antes: +100.
-- p4: terminos no activos SIN fecha propia: siguen recibiendo +100 por el brazo 1.
-- p5: membresia anual que despues paso a vitalicia: sus terminos fechados salen +100, antes y despues.
-- p6: vitalicias con fecha de expiracion igual al dia de alta (el placeholder de High Desert).

SELECT
    (SELECT COUNT_BIG(1) FROM MEMBERSHIPTRANSACTION) AS transacciones,
    (SELECT COUNT_BIG(1) FROM MEMBERSHIP) AS membresias,
    DB_NAME() AS base;

SELECT m.STATUSCODE AS estado, COUNT_BIG(1) AS membresias_sin_expiracion
FROM MEMBERSHIP m
WHERE m.EXPIRATIONDATE IS NULL
GROUP BY m.STATUSCODE
ORDER BY m.STATUSCODE;

SELECT
    SUM(CASE WHEN mt.EXPIRATIONDATE IS NULL AND m.EXPIRATIONDATE IS NOT NULL THEN 1 ELSE 0 END) AS p1_camino_nuevo_de_por_vida,
    SUM(CASE WHEN m.EXPIRATIONDATE IS NULL AND m.STATUSCODE <> 0 AND mt.EXPIRATIONDATE IS NOT NULL THEN 1 ELSE 0 END) AS p3_corregidas,
    SUM(CASE WHEN mt.EXPIRATIONDATE IS NULL AND m.STATUSCODE <> 0 THEN 1 ELSE 0 END) AS p4_no_activas_siguen_de_por_vida,
    SUM(CASE WHEN m.STATUSCODE = 0 AND m.EXPIRATIONDATE IS NULL AND mt.EXPIRATIONDATE IS NOT NULL
              AND CAST(mt.EXPIRATIONDATE AS DATE) <> CAST(mt.TRANSACTIONDATE AS DATE) THEN 1 ELSE 0 END) AS p5_anual_que_paso_a_vitalicia,
    SUM(CASE WHEN m.STATUSCODE = 0 AND m.EXPIRATIONDATE IS NULL AND mt.EXPIRATIONDATE IS NOT NULL
              AND CAST(mt.EXPIRATIONDATE AS DATE) = CAST(mt.TRANSACTIONDATE AS DATE) THEN 1 ELSE 0 END) AS p6_placeholder_vitalicio,
    SUM(CASE WHEN m.STATUSCODE = 0 AND m.EXPIRATIONDATE IS NULL AND mt.EXPIRATIONDATE IS NULL THEN 1 ELSE 0 END) AS vitalicias_sin_fecha_propia,
    SUM(CASE WHEN m.STATUSCODE <> 0 AND mt.EXPIRATIONDATE >= '20900101' THEN 1 ELSE 0 END) AS no_activas_con_fecha_lejana_de_altru,
    MAX(CASE WHEN m.STATUSCODE <> 0 AND mt.EXPIRATIONDATE >= '20900101' THEN CAST(mt.EXPIRATIONDATE AS DATE) END) AS max_fecha_lejana_de_altru,
    SUM(CASE WHEN mt.EXPIRATIONDATE < '19500101' THEN 1 ELSE 0 END) AS expiracion_antes_de_1950
FROM MEMBERSHIPTRANSACTION mt
INNER JOIN MEMBERSHIP m ON m.ID = mt.MEMBERSHIPID
WHERE ISNULL(mt.ACTION, '') <> 'Drop';

-- Drop con expiracion vacia sobre membresia con expiracion: seguras SOLO por el filtro de Drop.
SELECT COUNT_BIG(1) AS drop_sin_expiracion
FROM MEMBERSHIPTRANSACTION mt
INNER JOIN MEMBERSHIP m ON m.ID = mt.MEMBERSHIPID
WHERE mt.ACTION = 'Drop' AND mt.EXPIRATIONDATE IS NULL AND m.EXPIRATIONDATE IS NOT NULL;

-- Las vitalicias (Activa sin expiracion) con fecha propia, por nivel: nombres de nivel, no de personas.
SELECT ml.NAME AS nivel,
    SUM(CASE WHEN CAST(mt.EXPIRATIONDATE AS DATE) = CAST(mt.TRANSACTIONDATE AS DATE) THEN 1 ELSE 0 END) AS placeholder_dia_de_alta,
    SUM(CASE WHEN CAST(mt.EXPIRATIONDATE AS DATE) <> CAST(mt.TRANSACTIONDATE AS DATE) THEN 1 ELSE 0 END) AS fecha_real
FROM MEMBERSHIPTRANSACTION mt
INNER JOIN MEMBERSHIP m ON m.ID = mt.MEMBERSHIPID
LEFT JOIN MEMBERSHIPLEVEL ml ON ml.ID = mt.MEMBERSHIPLEVELID
WHERE ISNULL(mt.ACTION, '') <> 'Drop' AND m.STATUSCODE = 0 AND m.EXPIRATIONDATE IS NULL AND mt.EXPIRATIONDATE IS NOT NULL
GROUP BY ml.NAME
ORDER BY COUNT_BIG(1) DESC;
