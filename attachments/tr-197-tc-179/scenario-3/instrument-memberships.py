#!/usr/bin/env python3
"""TR-197 / TC-179 — instrumenta fund_assignment_memberships.sql (rama de cuotas).

Toma el archivo tal cual y sustituye SOLO la lista de columnas de la rama de cuotas.
CTEs, FROM, joins, OUTER APPLY y WHERE quedan byte a byte. La rama de donaciones
(IM-560, que este PR no toca) se recorta porque el UNION ALL solo concatena.

La clave del escenario 3: `amt_old` recalcula el descuento SIN el filtro del PR,
mediante una subconsulta escalar sobre la MISMA clave del join
(`xli.SOURCELINEITEMID = mli.LineItemID`). Asi la clasificacion vieja y la nueva
salen en la MISMA fila y la identidad es por construccion.

Limites verificados (1-indexed):
  POST  SELECT rama 1 .. 219   proyeccion 220-259   FROM 260   fin WHERE 390   UNION ALL 391
  BASE  SELECT rama 1 .. 205   proyeccion 206-245   FROM 246   fin WHERE 333   UNION ALL 334
"""

PARAMS = """DECLARE @hasDateFilterFrom BIT = {hff};
DECLARE @hasDateFilterTo BIT = {hft};
DECLARE @dateFilterFrom DATE = {dff};
DECLARE @dateFilterTo DATE = {dft};
"""

# descuento tal y como lo calculaba la version BASE: sin excluir el reembolso
OLD_DISCOUNT = (
    "(SELECT SUM(x2.TRANSACTIONAMOUNT) FROM FINANCIALTRANSACTIONLINEITEM x2 "
    "WHERE x2.[TYPE] = 'Discount' AND x2.SOURCELINEITEMID = mli.LineItemID)"
)

POST_COLS = f"""    CASE WHEN COALESCE(so.ID, addon_so.ID, revenue_so.ID, payment_so.ID) IS NULL
              AND own_so.ID IS NOT NULL THEN 1 ELSE 0 END AS own_so_only,
    CASE WHEN rgi.RecurringInstallmentID IS NOT NULL THEN rgi.InstallmentAmount
         ELSE mli.Amount - COALESCE(xli.DiscountAmount, 0) END AS amt_new,
    CASE WHEN rgi.RecurringInstallmentID IS NOT NULL THEN rgi.InstallmentAmount
         ELSE mli.Amount - COALESCE({OLD_DISCOUNT}, 0) END AS amt_old,
    CASE WHEN COALESCE(so.ID, addon_so.ID, revenue_so.ID, payment_so.ID, own_so.ID) IS NULL
         THEN 1 ELSE 0 END AS sin_pos,
    YEAR(CAST(COALESCE(rgi.InstallmentDate, own_ft.CALCULATEDDATE, rmft.FinancialTransactionDate, mt.TRANSACTIONDATE) AS DATE)) AS yr"""

POST_HEAD = "SELECT own_so_only, yr, COUNT(*) AS n_rows, SUM(amt_new) AS sum_new, SUM(amt_old) AS sum_old, SUM(CASE WHEN amt_new <> amt_old THEN 1 ELSE 0 END) AS n_amt_cambiado, SUM(CASE WHEN amt_old = 0 AND amt_new <> 0 THEN 1 ELSE 0 END) AS n_de_cero_a_real, SUM(sin_pos) AS n_sin_pos FROM ("
POST_TAIL = ") q GROUP BY own_so_only, yr ORDER BY 1, 2;"

BASE_COLS = """    CASE WHEN rgi.RecurringInstallmentID IS NOT NULL THEN rgi.InstallmentAmount
         ELSE mli.Amount - COALESCE(xli.DiscountAmount, 0) END AS amt,
    YEAR(CAST(COALESCE(rgi.InstallmentDate, own_ft.CALCULATEDDATE, rmft.FinancialTransactionDate, mt.TRANSACTIONDATE) AS DATE)) AS yr"""

BASE_HEAD = "SELECT yr, COUNT(*) AS n_rows, SUM(amt) AS sum_amt, SUM(CASE WHEN amt = 0 THEN 1 ELSE 0 END) AS n_en_cero FROM ("
BASE_TAIL = ") q GROUP BY yr ORDER BY 1;"


def params(hff=0, hft=0, dff="NULL", dft="NULL"):
    return PARAMS.format(hff=hff, hft=hft, dff=dff, dft=dft)


def build(path, sel, proj_end, branch_end, cols, head, tail, p):
    lines = open(path).read().split("\n")
    assert lines[sel - 1].strip() == "SELECT", f"{sel} no es SELECT: {lines[sel-1]!r}"
    assert lines[proj_end].strip() == "FROM", f"{proj_end+1} no es FROM: {lines[proj_end]!r}"
    assert lines[branch_end].strip() == "UNION ALL", f"{branch_end+1} no es UNION ALL: {lines[branch_end]!r}"
    out = [p]
    out.extend(lines[: sel - 1])      # CTEs intactas
    out.append(head)                  # envoltorio agregado
    out.append(lines[sel - 1])        # el SELECT propio de la rama
    out.append(cols)                  # columnas sustituidas
    out.extend(lines[proj_end:branch_end])  # FROM + joins + WHERE, byte a byte
    out.append(tail)
    return "\n".join(out)


def post(p):
    return build("post/fund_assignment_memberships.sql", 219, 259, 390, POST_COLS, POST_HEAD, POST_TAIL, p)


def base(p):
    return build("base/fund_assignment_memberships.sql", 205, 245, 333, BASE_COLS, BASE_HEAD, BASE_TAIL, p)


if __name__ == "__main__":
    open("q/memb-post-agg.sql", "w").write(post(params()))
    open("q/memb-base-agg.sql", "w").write(base(params()))
    # escenario 5: ventana de fechas — junio 2012 (mes de la orden) y julio 2012 (mes del reembolso)
    jun = params(1, 1, "'2012-06-01'", "'2012-06-30'")
    jul = params(1, 1, "'2012-07-01'", "'2012-07-31'")
    open("q/memb-post-jun2012.sql", "w").write(post(jun))
    open("q/memb-base-jun2012.sql", "w").write(base(jun))
    open("q/memb-post-jul2012.sql", "w").write(post(jul))
    open("q/memb-base-jul2012.sql", "w").write(base(jul))
    print("escritos 6 archivos en q/")
