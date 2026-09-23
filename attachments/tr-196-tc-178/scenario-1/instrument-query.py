#!/usr/bin/env python3
"""TC-178 — instrumenta membership_transactions.sql para medir PRE vs POST en una pasada.

No reimplementa la logica: toma el archivo del PR tal cual, conserva sus 15 tablas
temporales, su FROM y su WHERE, y SOLO sustituye las listas de columnas de las dos ramas
del UNION por las columnas que hacen falta para medir. La clasificacion NUEVA se copia
literal del archivo; la ANTIGUA es la misma con el branch de REFUNDSTATUS reinstalado en
su posicion original (rama de transaccion) o sustituido (rama por orden).
"""
import sys, pathlib

SRC = pathlib.Path(sys.argv[1])
OUT = pathlib.Path(sys.argv[2])
MODE = sys.argv[3] if len(sys.argv) > 3 else "agg"   # agg | six
lines = SRC.read_text().splitlines()

# Limites verificados sobre el archivo del PR (1-indexados):
#   rama 1: SELECT 553, columnas 554-779, FROM 780, WHERE 912
#   UNION ALL 943
#   rama 2: SELECT 944, columnas 945-1049, FROM 1050, WHERE 1079, fin 1102
#   bloque DROP final: 1103-1117
B1_COLS = (554, 779)
B2_COLS = (945, 1049)
SEL1 = 553
END2 = 1099      # ultima linea del WHERE de la rama 2; 1100 es el OPTION, que sube al wrap
TAIL = 1102      # 1103+ es el bloque DROP final

for ln, expect in ((SEL1, "SELECT"), (943, "UNION ALL"), (944, "SELECT"), (780, "FROM"), (1050, "FROM")):
    got = lines[ln - 1].strip()
    assert got.startswith(expect), f"linea {ln}: esperaba {expect!r}, hay {got!r}"

INSTALLMENT_CASE = """		WHEN rgi.RecurringInstallmentID IS NOT NULL THEN
			CASE rgi.STATUSCODE
				WHEN 0 THEN 'Pledged' WHEN 1 THEN 'Closed Lost' WHEN 2 THEN 'Closed Won'
				WHEN 3 THEN 'Closed Lost' WHEN 4 THEN 'Closed Lost' ELSE 'Pledged'
			END
		WHEN mt.ACTION = 'Drop' THEN 'Closed Lost'
		WHEN rso.SalesOrderID IS NOT NULL THEN 'Closed Lost'
		WHEN rmt.MembershipTransactionID IS NOT NULL THEN 'Closed Lost'"""

ORDER_STATUS_TAIL = """		ELSE
			CASE
				WHEN COALESCE(so.ID, revenue_so.ID, payment_so.ID) IS NULL THEN 'Closed Won'
				WHEN COALESCE(so.STATUSCODE, revenue_so.STATUSCODE, payment_so.STATUSCODE) IN (1, 3, 4) THEN 'Closed Won'
				WHEN COALESCE(so.STATUSCODE, revenue_so.STATUSCODE, payment_so.STATUSCODE) IN (5) THEN 'Closed Lost'
				WHEN COALESCE(so.STATUSCODE, revenue_so.STATUSCODE, payment_so.STATUSCODE) IN (0, 2, 6, 7) THEN 'Prospecting'
				ELSE 'Prospecting'
			END
	END"""

B1 = f"""	COALESCE(rgi.RecurringInstallmentID, mt.ID) AS RowKey,
	'MT' AS BranchTag,
	-- POST: copia literal del CASE del PR (sin el branch de REFUNDSTATUS)
	CASE
{INSTALLMENT_CASE}
{ORDER_STATUS_TAIL} AS NewStage,
	-- PRE: el mismo CASE con el branch de REFUNDSTATUS reinstalado donde estaba
	CASE
{INSTALLMENT_CASE}
		WHEN COALESCE(so.REFUNDSTATUS, revenue_so.REFUNDSTATUS, payment_so.REFUNDSTATUS) = 2 THEN 'Closed Lost'
{ORDER_STATUS_TAIL} AS OldStage,
	CASE WHEN COALESCE(so.REFUNDSTATUS, revenue_so.REFUNDSTATUS, payment_so.REFUNDSTATUS) = 2 THEN 1 ELSE 0 END AS QtyFlag,
	-- revenue_so es un OUTER APPLY que solo proyecta ID/STATUSCODE/REFUNDSTATUS, asi que
	-- la venta a grupos se resuelve por subconsulta escalar sobre la MISMA orden que el
	-- CASE de StageName resuelve. Escalar sobre PK: no puede alterar el grano.
	(SELECT CASE WHEN so2.SALESMETHODTYPECODE = 3 THEN 1 ELSE 0 END
	   FROM SALESORDER so2
	  WHERE so2.ID = COALESCE(so.ID, revenue_so.ID, payment_so.ID)) AS GroupSales,
	CASE WHEN rso.SalesOrderID IS NOT NULL OR rmt.MembershipTransactionID IS NOT NULL THEN 1 ELSE 0 END AS DollarGate,
	CASE WHEN mt.ACTION = 'Drop' THEN 1 ELSE 0 END AS IsDrop,
	CASE WHEN EXISTS (SELECT 1 FROM #RankGapOlder g WHERE g.MembershipTransactionID = mt.ID)
	     THEN 1 ELSE 0 END AS RankGapOlder,
	-- copia literal de la expresion de Revenue_ID_legacy__c de la rama (IM-1206)
	CASE
		WHEN rgi.RecurringInstallmentID IS NOT NULL AND rgi.RevenueId IS NULL THEN NULL
		ELSE COALESCE(rgi.RevenueId, NULLIF(mli.Revenue_ID_legacy__c, ''), rmft.Revenue_ID_legacy__c)
	END AS RevId"""

B2_TAIL = """		WHEN obm.SalesOrderStatusCode IN (1, 3, 4) THEN 'Closed Won'
		WHEN obm.SalesOrderStatusCode IN (5) THEN 'Closed Lost'
		WHEN obm.SalesOrderStatusCode IN (0, 2, 6, 7) THEN 'Prospecting'
		ELSE 'Prospecting'
	END"""

B2 = f"""	obm.OrderMembershipItemID AS RowKey,
	'OBM' AS BranchTag,
	-- POST: copia literal del CASE del PR (compuerta de dolares)
	CASE
		WHEN obm_rso.SalesOrderID IS NOT NULL THEN 'Closed Lost'
{B2_TAIL} AS NewStage,
	-- PRE: el mismo CASE con la bandera de cantidad en su lugar
	CASE
		WHEN obm.SalesOrderRefundStatus = 2 THEN 'Closed Lost'
{B2_TAIL} AS OldStage,
	CASE WHEN obm.SalesOrderRefundStatus = 2 THEN 1 ELSE 0 END AS QtyFlag,
	(SELECT CASE WHEN so2.SALESMETHODTYPECODE = 3 THEN 1 ELSE 0 END
	   FROM SALESORDER so2 WHERE so2.ID = obm.SalesOrderID) AS GroupSales,
	CASE WHEN obm_rso.SalesOrderID IS NOT NULL THEN 1 ELSE 0 END AS DollarGate,
	0 AS IsDrop,
	0 AS RankGapOlder,
	COALESCE(NULLIF(obm.OwnRevenueIdLegacy, ''), obm.Revenue_ID_legacy__c) AS RevId"""

WRAP_HEAD = """SELECT
	q.BranchTag,
	COUNT(1)                                                                              AS rows_total,
	COUNT(DISTINCT q.RowKey)                                                              AS rows_distinct,
	SUM(CASE WHEN q.QtyFlag = 1 AND q.IsDrop = 0 THEN 1 ELSE 0 END)                       AS qty_flag_non_drop,
	SUM(CASE WHEN q.QtyFlag = 1 AND q.IsDrop = 0 AND q.DollarGate = 1 THEN 1 ELSE 0 END)   AS qty_flag_dollar_gated,
	SUM(CASE WHEN q.OldStage <> q.NewStage THEN 1 ELSE 0 END)                              AS changed_rows,
	SUM(CASE WHEN q.OldStage = 'Closed Lost' AND q.NewStage = 'Closed Won' THEN 1 ELSE 0 END) AS released_lost_to_won,
	SUM(CASE WHEN q.OldStage = 'Closed Won' AND q.NewStage = 'Closed Lost' THEN 1 ELSE 0 END) AS newly_lost_won_to_lost,
	SUM(CASE WHEN q.OldStage <> q.NewStage
		  AND NOT (q.OldStage IN ('Closed Lost','Closed Won') AND q.NewStage IN ('Closed Lost','Closed Won'))
		 THEN 1 ELSE 0 END)                                                               AS changed_other_shapes,
	SUM(CASE WHEN q.OldStage = 'Closed Lost' AND q.NewStage = 'Closed Won' AND q.GroupSales = 1 THEN 1 ELSE 0 END) AS released_group_sales,
	SUM(q.RankGapOlder)                                                                   AS rank_gap_older_rows,
	SUM(CASE WHEN q.RankGapOlder = 1 AND q.OldStage = 'Closed Lost' AND q.NewStage = 'Closed Won' THEN 1 ELSE 0 END) AS rank_gap_older_released,
	SUM(CASE WHEN q.OldStage = 'Closed Lost' THEN 1 ELSE 0 END)                            AS old_closed_lost,
	SUM(CASE WHEN q.NewStage = 'Closed Lost' THEN 1 ELSE 0 END)                            AS new_closed_lost,
	SUM(CASE WHEN q.OldStage = 'Closed Won' THEN 1 ELSE 0 END)                             AS old_closed_won,
	SUM(CASE WHEN q.NewStage = 'Closed Won' THEN 1 ELSE 0 END)                             AS new_closed_won
FROM (
"""
WRAP_TAIL = """) AS q
GROUP BY q.BranchTag
-- El hint vive en la sentencia mas externa: dentro de la derivada es sintaxis invalida.
-- Se conserva el del PR tal cual para no alterar el plan que el autor midio.
OPTION (LOOP JOIN, MAX_GRANT_PERCENT = 5);
"""

PARAMS = """-- TC-178: parametros que el harness inyecta. Sin ventana de fechas = todos los anios,
-- que es lo que el ticket pide para la recarga.
DECLARE @hasDateFilterFrom BIT = 0;
DECLARE @hasDateFilterTo   BIT = 0;
DECLARE @dateFilterFrom DATE = NULL;
DECLARE @dateFilterTo   DATE = NULL;

-- TC-178 escenario 6: transacciones que quedan DETRAS del rango 1 en una particion cuyo
-- reembolso cubre de sobra a la mas nueva. Son las candidatas a que el ranking las pierda
-- ahora que la bandera de cantidad ya no hace de respaldo. Logica copiada de la derivada
-- `rm` del propio archivo.
DROP TABLE IF EXISTS #RankGapOlder;
WITH rm AS (
    SELECT
        mt.ID AS MembershipTransactionID,
        mt.REVENUESPLITID AS RevenueSplitId,
        refund_ft.ID AS RefundId,
        cim.MEMBERSHIPID AS MembershipId,
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
        SELECT cim_by_source.MEMBERSHIPID FROM CREDITITEMMEMBERSHIP cim_by_source
         WHERE cim_by_source.ID = refund_line.SOURCELINEITEMID
        UNION ALL
        SELECT cim_by_line.MEMBERSHIPID FROM CREDITITEMMEMBERSHIP cim_by_line
         WHERE cim_by_line.ID = refund_line.ID
    ) cim
    INNER JOIN MEMBERSHIPTRANSACTION mt
        ON mt.MEMBERSHIPID = cim.MEMBERSHIPID
       AND mt.TRANSACTIONDATE <= refund_ft.CALCULATEDDATE
    WHERE refund_ft.[TYPE] = 'Refund'
),
OverCovering AS (
    SELECT r.RefundId, r.MembershipId
    FROM rm r
    LEFT JOIN FINANCIALTRANSACTIONLINEITEM ol
        ON ol.ID = r.RevenueSplitId AND ol.[TYPE] = 'Standard'
    GROUP BY r.RefundId, r.MembershipId
    HAVING MAX(CASE WHEN r.RefundMatchRank = 1 THEN ABS(r.RefundAmount) END)
         > MAX(CASE WHEN r.RefundMatchRank = 1 THEN ABS(ISNULL(ol.TRANSACTIONAMOUNT, 0)) END)
)
SELECT DISTINCT rm.MembershipTransactionID
INTO #RankGapOlder
FROM rm
INNER JOIN OverCovering oc
    ON oc.RefundId = rm.RefundId AND oc.MembershipId = rm.MembershipId
WHERE rm.RefundMatchRank > 1;
"""

SIX_HEAD = """-- Los seis registros de IM-1272, por su revenue id VIGENTE (IM-1206 los cambio del
-- pago a la orden; los de la descripcion del ticket ya no encuentran nada).
SELECT
	q.BranchTag,
	q.RevId,
	q.OldStage,
	q.NewStage,
	q.QtyFlag,
	q.DollarGate
FROM (
"""
SIX_TAIL = """) AS q
WHERE q.RevId IN ('rev-11546037','rev-11203390','rev-11395299',
                  'rev-11070451','rev-10833452','rev-10841307')
ORDER BY q.RevId
OPTION (LOOP JOIN, MAX_GRANT_PERCENT = 5);
"""

if MODE == "six":
    WRAP_HEAD, WRAP_TAIL = SIX_HEAD, SIX_TAIL

out = []
out.append(PARAMS)
out.extend(lines[: SEL1 - 1])          # todo lo anterior a la sentencia final: los 15 #temp
out.append(WRAP_HEAD)
out.append(lines[SEL1 - 1])            # SELECT de la rama 1
out.append(B1)                         # lista de columnas sustituida
out.extend(lines[B1_COLS[1] : 942])    # FROM + joins + WHERE de la rama 1, intactos (780-942)
out.append(lines[942])                 # UNION ALL (943)
out.append(lines[943])                 # SELECT de la rama 2
out.append(B2)
out.extend(lines[B2_COLS[1] : END2])   # FROM + joins + WHERE de la rama 2, intactos (1050-1099)
out.append(WRAP_TAIL)
out.extend(lines[TAIL:])               # bloque DROP final (1103+)

OUT.write_text("\n".join(out) + "\n")
print(f"escrito {OUT} ({len(out)} bloques)")
