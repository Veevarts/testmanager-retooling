#!/usr/bin/env python3
"""TC-180 instrumentation.

NO reimplementa ninguna logica. Toma cada consulta tal cual y sustituye UNICAMENTE
la lista de columnas de la proyeccion final por el identificador externo que esa
consulta emite. Cadena de CTEs, joins, WHERE, temp tables y hints quedan byte a byte.
"""
import sys, pathlib

Q = pathlib.Path(__file__).parent / "q"
OUT = pathlib.Path(__file__).parent / "nc"
OUT.mkdir(exist_ok=True)

PARAMS = """DECLARE @hasDateFilterFrom BIT = 0;
DECLARE @hasDateFilterTo BIT = 0;
DECLARE @dateFilterFrom VARCHAR(10) = NULL;
DECLARE @dateFilterTo VARCHAR(10) = NULL;
"""


def splice(lines, start_keep, proj_first, proj_last, new_proj):
    """Reemplaza [proj_first..proj_last] (1-indexado) por new_proj. start_keep es la
    linea del SELECT, que se conserva."""
    out = lines[: proj_first - 1]
    out.append(new_proj)
    out.extend(lines[proj_last:])
    return out


def read(name):
    return (Q / name).read_text().splitlines(keepends=True)


# ---- donation_transaction.sql : SELECT 341, proyeccion 342..430, FROM 431 -------
dt = read("donation_transaction.sql")
assert dt[340].strip() == "SELECT", dt[340]
assert dt[430].startswith("FROM TransactionAgg"), dt[430]
dt[340] = "SELECT DISTINCT\n"
dt = splice(
    dt, 341, 342, 430,
    "    COALESCE(CAST(rgi.RecurringInstallmentID AS VARCHAR(36)),"
    " CAST(ta.FinancialTransactionID AS VARCHAR(36))) AS OpportunityExternalId\n",
)
(OUT / "emitted_donations.sql").write_text(PARAMS + "".join(dt))

# ---- donation_pledges.sql : SELECT 129, proyeccion 130..186, FROM 187 -----------
dp = read("donation_pledges.sql")
assert dp[128].strip() == "SELECT", dp[128]
assert dp[186].strip() == "FROM", dp[186]
dp[128] = "SELECT DISTINCT\n"
dp = splice(dp, 129, 130, 186,
            "    CAST(ft.ID AS VARCHAR(36)) AS OpportunityExternalId\n")
# el ORDER BY final referencia una columna que ya no se proyecta bajo DISTINCT
dp = [l for l in dp if not l.startswith("ORDER BY ft.CALCULATEDDATE")]
(OUT / "emitted_pledges.sql").write_text("".join(dp))

# ---- membership_transactions.sql : dos ramas bajo UNION ALL --------------------
#      rama 1: SELECT 553, proyeccion 554..758, FROM 759
#      rama 2: SELECT 923, proyeccion 924..1022, FROM 1023
mt = read("membership_transactions.sql")
assert mt[552].strip() == "SELECT", mt[552]
assert mt[758].strip() == "FROM", mt[758]
assert mt[922].strip() == "SELECT", mt[922]
assert mt[1022].strip() == "FROM", mt[1022]
# de atras hacia delante para no desplazar los indices de la rama 1
mt = splice(mt, 923, 924, 1022,
            "\tCAST(obm.OrderMembershipItemID AS VARCHAR(36)) AS OpportunityExternalId\n")
mt = splice(mt, 553, 554, 758,
            "\tCAST(COALESCE(rgi.RecurringInstallmentID, mt.ID) AS VARCHAR(36))"
            " AS OpportunityExternalId\n")
(OUT / "emitted_memberships.sql").write_text(PARAMS + "".join(mt))

for f in sorted(OUT.glob("emitted_*.sql")):
    print(f"{f.name}: {len(f.read_text().splitlines())} lineas")
