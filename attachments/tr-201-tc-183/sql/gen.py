"""Genera tres ejecuciones sobre la MISMA fuente:

  ctrl_base.sql  la consulta de la base, sin tocar, materializada y agregada
  ctrl_pr.sql    la del PR, sin tocar, materializada y agregada
  instr.sql      la del PR con dos columnas mas por rama: la fecha fin VIEJA
                 calculada en la misma fila, y los datos del predicado

Solo se anade INTO #qa_out y columnas al final de cada lista; ninguna expresion
existente cambia. Los controles prueban que instr emite exactamente lo mismo
que la base (fecha vieja) y que el PR (fecha nueva): si no cuadran, la
comparacion no vale nada.
Nada sale fila a fila salvo los dos ejemplos del ticket, y solo fechas.
"""
import re, sys, os
D = os.path.dirname(os.path.abspath(__file__))
base = open(f"{D}/base.sql").read()
pr = open(f"{D}/pr.sql").read()

PARAMS = """DECLARE @hasDateFilterFrom BIT = 0;
DECLARE @hasDateFilterTo BIT = 0;
DECLARE @dateFilterFrom DATE = NULL;
DECLARE @dateFilterTo DATE = NULL;
"""
B1 = "\tEND AS npe03__Recurring_Donation__c\nFROM\n\tMEMBERSHIPTRANSACTION mt\n"
B2 = "\tNULL AS npe03__Recurring_Donation__c\nFROM\n"
for name, t in (("base", base), ("pr", pr)):
    assert t.count(B1) == 1, (name, "B1", t.count(B1))
    assert t.count(B2) == 1, (name, "B2", t.count(B2))

# Columnas de salida originales (rama 1), para la huella de "todo lo demas".
sel = pr[pr.index("\nSELECT\n\tCOALESCE(rgi.RecurringInstallmentID, mt.ID) AS vnfp__Implementation_External_ID__c"):pr.index(B1)]
cols = re.findall(r"\bAS\s+([A-Za-z_0-9]+)\s*,?\s*$", sel, re.M)
cols = [c for c in cols if not c.upper() in ("DATE", "NVARCHAR", "INT")]
seen = []
for c in cols:
    if c not in seen: seen.append(c)
cols = seen
assert "npe01__Membership_End_Date__c" in cols and len(cols) >= 30, cols
OTHER = [c for c in cols if c != "npe01__Membership_End_Date__c"]
open(f"{D}/columns.txt", "w").write("\n".join(cols) + "\n")

def materialize(t, extra1="", extra2=""):
    t = t.replace(B1, "\tEND AS npe03__Recurring_Donation__c" + extra1 + "\nINTO #qa_out\nFROM\n\tMEMBERSHIPTRANSACTION mt\n", 1)
    t = t.replace(B2, "\tNULL AS npe03__Recurring_Donation__c" + extra2 + "\nFROM\n", 1)
    return PARAMS + t

FP_OTHER = "CHECKSUM_AGG(BINARY_CHECKSUM(" + ", ".join(OTHER) + "))"
CTRL_AGG = f"""
SELECT
    COUNT_BIG(1) AS filas,
    CHECKSUM_AGG(BINARY_CHECKSUM(vnfp__Implementation_External_ID__c, npe01__Membership_End_Date__c)) AS huella_id_fecha_fin,
    {FP_OTHER} AS huella_resto_columnas,
    SUM(CASE WHEN npe01__Membership_End_Date__c > DATEADD(YEAR, 90, npe01__Membership_Start_Date__c) THEN 1 ELSE 0 END) AS fechas_lejanas
FROM #qa_out;
DROP TABLE IF EXISTS #qa_out;
"""
open(f"{D}/ctrl_base.sql", "w").write(materialize(base) + CTRL_AGG)
open(f"{D}/ctrl_pr.sql", "w").write(materialize(pr) + CTRL_AGG)

EX1 = """,
	CAST(CASE WHEN m.EXPIRATIONDATE IS NULL
		THEN DATEADD(YEAR, 100, COALESCE(rgi.InstallmentDate, mt.TRANSACTIONDATE))
		ELSE mt.EXPIRATIONDATE END AS DATE) AS qa_end_old,
	CAST(mt.EXPIRATIONDATE AS DATE) AS qa_term_exp,
	CAST(m.EXPIRATIONDATE AS DATE) AS qa_container_exp,
	CAST(m.STATUSCODE AS INT) AS qa_status,
	CAST(mt.ACTION AS NVARCHAR(100)) AS qa_action,
	1 AS qa_branch"""
EX2 = """,
	CAST(COALESCE(obm.EXPIRATIONDATE,
		DATEADD(YEAR, 100, COALESCE(obm.FinancialTransactionDate, obm.SalesOrderTransactionDate))) AS DATE) AS qa_end_old,
	CAST(obm.EXPIRATIONDATE AS DATE) AS qa_term_exp,
	CAST(NULL AS DATE) AS qa_container_exp,
	CAST(NULL AS INT) AS qa_status,
	CAST(NULL AS NVARCHAR(100)) AS qa_action,
	2 AS qa_branch"""

FAR_OLD = "qa_end_old > DATEADD(YEAR, 90, npe01__Membership_Start_Date__c)"
FAR_NEW = "npe01__Membership_End_Date__c > DATEADD(YEAR, 90, npe01__Membership_Start_Date__c)"
NEQ = "(ISNULL(qa_end_old, '19000101') <> ISNULL(npe01__Membership_End_Date__c, '19000101'))"
FIXED = f"({FAR_OLD} AND NOT ({FAR_NEW}))"
INSTR_AGG = f"""
-- R0 · grano y huellas, para cuadrar contra los dos controles
SELECT
    COUNT_BIG(1) AS filas,
    SUM(CASE WHEN qa_branch = 1 THEN 1 ELSE 0 END) AS rama1,
    SUM(CASE WHEN qa_branch = 2 THEN 1 ELSE 0 END) AS rama2,
    CHECKSUM_AGG(BINARY_CHECKSUM(vnfp__Implementation_External_ID__c, qa_end_old)) AS huella_fecha_vieja,
    CHECKSUM_AGG(BINARY_CHECKSUM(vnfp__Implementation_External_ID__c, npe01__Membership_End_Date__c)) AS huella_fecha_nueva,
    {FP_OTHER} AS huella_resto_columnas
FROM #qa_out;

-- R1 · fechas lejanas antes y despues, por rama
SELECT qa_branch,
    SUM(CASE WHEN {FAR_OLD} THEN 1 ELSE 0 END) AS lejanas_base,
    SUM(CASE WHEN {FAR_NEW} THEN 1 ELSE 0 END) AS lejanas_pr,
    SUM(CASE WHEN {NEQ} THEN 1 ELSE 0 END) AS filas_que_cambian
FROM #qa_out GROUP BY qa_branch ORDER BY qa_branch;

-- R2 · direccion de cada cambio
SELECT
    SUM(CASE WHEN {NEQ} AND {FIXED} THEN 1 ELSE 0 END) AS lejana_a_real,
    SUM(CASE WHEN {NEQ} AND NOT ({FAR_OLD}) AND {FAR_NEW} THEN 1 ELSE 0 END) AS real_a_lejana,
    SUM(CASE WHEN {NEQ} AND qa_end_old IS NULL THEN 1 ELSE 0 END) AS vacia_a_algo,
    SUM(CASE WHEN {NEQ} AND npe01__Membership_End_Date__c IS NULL THEN 1 ELSE 0 END) AS algo_a_vacia,
    SUM(CASE WHEN {NEQ} AND NOT ({FIXED}) THEN 1 ELSE 0 END) AS cualquier_otro_cambio
FROM #qa_out;

-- R3 · las corregidas: toman su propia expiracion? que duracion tienen? de que estado son?
SELECT
    COUNT_BIG(1) AS corregidas,
    SUM(CASE WHEN npe01__Membership_End_Date__c = qa_term_exp THEN 1 ELSE 0 END) AS toman_su_propia_expiracion,
    SUM(CASE WHEN DATEDIFF(MONTH, npe01__Membership_Start_Date__c, npe01__Membership_End_Date__c) = 12 THEN 1 ELSE 0 END) AS de_un_ano,
    SUM(CASE WHEN DATEDIFF(MONTH, npe01__Membership_Start_Date__c, npe01__Membership_End_Date__c) = 24 THEN 1 ELSE 0 END) AS de_dos_anos,
    SUM(CASE WHEN DATEDIFF(MONTH, npe01__Membership_Start_Date__c, npe01__Membership_End_Date__c) NOT IN (12, 24) THEN 1 ELSE 0 END) AS otra_duracion,
    SUM(CASE WHEN qa_status = 0 THEN 1 ELSE 0 END) AS estado_activa,
    SUM(CASE WHEN qa_status = 1 THEN 1 ELSE 0 END) AS estado_cancelada,
    SUM(CASE WHEN qa_container_exp IS NULL THEN 1 ELSE 0 END) AS contenedor_sin_expiracion,
    MIN(npe01__Membership_Start_Date__c) AS inicio_min,
    MAX(npe01__Membership_Start_Date__c) AS inicio_max,
    SUM(CASE WHEN StageName = 'Closed Won' THEN 1 ELSE 0 END) AS closed_won
FROM #qa_out WHERE {NEQ} AND {FIXED};

-- R4 · lo que SIGUE lejano en el PR, por brazo del predicado y estado
SELECT
    qa_branch,
    CASE
        WHEN qa_branch = 2 THEN 'rama2'
        WHEN qa_term_exp IS NULL THEN 'brazo1_termino_sin_fecha'
        WHEN qa_status = 0 AND qa_container_exp IS NULL THEN 'brazo2_activa_sin_expiracion'
        ELSE 'fecha_lejana_propia_de_altru'
    END AS origen,
    qa_status,
    COUNT_BIG(1) AS filas,
    MAX(npe01__Membership_End_Date__c) AS fin_max
FROM #qa_out WHERE {FAR_NEW}
GROUP BY qa_branch,
    CASE
        WHEN qa_branch = 2 THEN 'rama2'
        WHEN qa_term_exp IS NULL THEN 'brazo1_termino_sin_fecha'
        WHEN qa_status = 0 AND qa_container_exp IS NULL THEN 'brazo2_activa_sin_expiracion'
        ELSE 'fecha_lejana_propia_de_altru'
    END,
    qa_status
ORDER BY qa_branch, origen, qa_status;

-- R5 · camino NUEVO de por vida en la salida: termino sin fecha sobre membresia CON expiracion
SELECT
    COUNT_BIG(1) AS filas_camino_nuevo,
    SUM(CASE WHEN ISNULL(qa_action, '') = 'Drop' THEN 1 ELSE 0 END) AS de_ellas_drop
FROM #qa_out WHERE qa_branch = 1 AND qa_term_exp IS NULL AND qa_container_exp IS NOT NULL;

-- R6 · rarezas de Altru: fecha fin anterior al inicio, o del siglo XX temprano
SELECT
    SUM(CASE WHEN npe01__Membership_End_Date__c < npe01__Membership_Start_Date__c THEN 1 ELSE 0 END) AS fin_antes_del_inicio,
    SUM(CASE WHEN YEAR(npe01__Membership_End_Date__c) < 1950 THEN 1 ELSE 0 END) AS fin_antes_de_1950,
    SUM(CASE WHEN {NEQ} AND (npe01__Membership_End_Date__c < npe01__Membership_Start_Date__c) THEN 1 ELSE 0 END) AS de_ellas_cambian
FROM #qa_out;

-- R7 · los dos ejemplos del ticket: solo fechas y banderas, ninguna persona
SELECT
    Revenue_ID_legacy__c AS rev,
    qa_branch AS rama,
    npe01__Membership_Start_Date__c AS inicio,
    qa_end_old AS fin_base,
    npe01__Membership_End_Date__c AS fin_pr,
    qa_term_exp AS expiracion_del_termino,
    qa_status AS estado_membresia,
    CASE WHEN qa_container_exp IS NULL THEN 1 ELSE 0 END AS contenedor_sin_expiracion,
    StageName
FROM #qa_out WHERE Revenue_ID_legacy__c IN ('rev-10049355', 'rev-10015151')
ORDER BY rev, inicio;

DROP TABLE IF EXISTS #qa_out;
"""
open(f"{D}/instr.sql", "w").write(materialize(pr, EX1, EX2) + INSTR_AGG)

# Toda escritura debe apuntar a un objeto temporal (#). Si no, no se ejecuta.
for f in ("ctrl_base.sql", "ctrl_pr.sql", "instr.sql"):
    t = open(f"{D}/{f}").read()
    code = re.sub(r"--[^\n]*", "", t)
    code = re.sub(r"'[^']*'", "''", code)
    bad = []
    for kw, tgt in re.findall(r"\b(INTO|CREATE\s+(?:NONCLUSTERED\s+|CLUSTERED\s+|UNIQUE\s+)?(?:INDEX\s+\w+\s+ON|TABLE)|DROP\s+TABLE\s+IF\s+EXISTS|INSERT\s+INTO|UPDATE|DELETE\s+FROM|TRUNCATE\s+TABLE|ALTER\s+TABLE|MERGE)\s+([#\w\[\]\.]+)", code, re.I):
        if not tgt.startswith("#"): bad.append((kw, tgt))
    ex = re.findall(r"\b(EXEC|EXECUTE|sp_executesql)\b", code, re.I)
    print(f"{f:14} {len(t):>7} bytes · escrituras no temporales: {bad or 'ninguna'} · EXEC: {ex or 'ninguno'}")
    assert not bad and not ex
print(f"columnas de salida: {len(cols)} (huella del resto: {len(OTHER)})")
