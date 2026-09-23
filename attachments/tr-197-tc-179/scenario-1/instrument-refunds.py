#!/usr/bin/env python3
"""TR-197 / TC-179 — instrumenta fund_assignments_membership_refunds.sql.

NO reimplementa la logica: toma el archivo del PR tal cual y solo
  1) anade dos columnas de clasificacion a dos CTEs, y
  2) sustituye la SELECT final por un agregado.
FROM, joins, OUTER APPLY y WHERE quedan byte a byte.

Limites verificados (1-indexed, post = 331 lineas, base = 258 lineas):
  POST  RefundLineItems SELECT ............ 79   (proyeccion 80-86, FROM 87)
        RawRefundFundAssignments SELECT ... 181  (proyeccion 182-211, FROM 212)
        SELECT final ...................... 314 .. 331 (fin de archivo)
  BASE  SELECT final ...................... 241 .. 258 (fin de archivo)
"""
import sys

PARAMS = """DECLARE @hasDateFilterFrom BIT = 0;
DECLARE @hasDateFilterTo BIT = 0;
DECLARE @dateFilterFrom DATE = NULL;
DECLARE @dateFilterTo DATE = NULL;
"""

# columna que expone el TIPO de la linea del reembolso (Standard / Discount)
RLI_EXTRA = "            rli.[TYPE] AS RefundLineType,"

# columnas que dejan visible por que rama entro la fila
RAW_EXTRA = (
    "        rli.RefundLineType AS RefundLineType,\n"
    "        rli.CreditOrderMembershipItemID AS ArmCreditItemID,"
)

ARM_CASE = (
    "CASE WHEN ArmCreditItemID IS NOT NULL THEN 'A_credit_item' "
    "WHEN RefundLineType = 'Discount' THEN 'B_discount_typed' "
    "ELSE 'C_pre_existing' END"
)

AGG_POST = f"""    SELECT
        {ARM_CASE} AS admit_arm,
        YEAR(Auctifera__Posted_Date__c) AS yr,
        COUNT(*) AS n_rows,
        SUM(Auctifera__Donated_Amount__c) AS amount_sum,
        SUM(CASE WHEN Auctifera__Specific_Fund__c = 'Membership_Fund' THEN 1 ELSE 0 END) AS n_membership_fund,
        SUM(CASE WHEN Auctifera__Specific_Fund__c IS NULL THEN 1 ELSE 0 END) AS n_fund_null,
        SUM(CASE WHEN vnfp__Opportunity_POS_Purchase__c IS NOT NULL THEN 1 ELSE 0 END) AS n_order_backed,
        SUM(CASE WHEN Auctifera__Specific_Fund_Name__c IS NULL THEN 1 ELSE 0 END) AS n_fund_name_null,
        COUNT(DISTINCT vnfp__Opportunity__c) AS n_distinct_opp
    FROM
        DedupedRefundFundAssignments
    WHERE
        DedupRank = 1
    GROUP BY
        {ARM_CASE},
        YEAR(Auctifera__Posted_Date__c)
    ORDER BY
        1, 2;
"""

AGG_BASE = """    SELECT
        YEAR(Auctifera__Posted_Date__c) AS yr,
        COUNT(*) AS n_rows,
        SUM(Auctifera__Donated_Amount__c) AS amount_sum,
        SUM(CASE WHEN Auctifera__Specific_Fund__c = 'Membership_Fund' THEN 1 ELSE 0 END) AS n_membership_fund,
        SUM(CASE WHEN Auctifera__Specific_Fund_Name__c IS NULL THEN 1 ELSE 0 END) AS n_fund_name_null,
        COUNT(DISTINCT vnfp__Opportunity__c) AS n_distinct_opp
    FROM
        DedupedRefundFundAssignments
    WHERE
        DedupRank = 1
    GROUP BY
        YEAR(Auctifera__Posted_Date__c)
    ORDER BY
        1;
"""


def build_post(path):
    lines = open(path).read().split("\n")
    assert lines[78].strip() == "SELECT", f"79 no es SELECT: {lines[78]!r}"
    assert lines[86].strip() == "FROM", f"87 no es FROM: {lines[86]!r}"
    assert lines[180].strip() == "SELECT", f"181 no es SELECT: {lines[180]!r}"
    assert lines[211].strip() == "FROM", f"212 no es FROM: {lines[211]!r}"
    assert lines[313].strip() == "SELECT", f"314 no es SELECT: {lines[313]!r}"
    out = [PARAMS]
    out.extend(lines[:79])          # ... hasta el SELECT de RefundLineItems
    out.append(RLI_EXTRA)           # + tipo de la linea
    out.extend(lines[79:181])       # proyeccion, FROM, OUTER APPLY y WHERE intactos
    out.append(RAW_EXTRA)           # + clasificador de rama
    out.extend(lines[181:313])      # proyeccion, FROM, joins y WHERE intactos
    out.append(AGG_POST)            # agregado en vez de la proyeccion final
    return "\n".join(out)


def build_base(path):
    lines = open(path).read().split("\n")
    assert lines[240].strip() == "SELECT", f"241 no es SELECT: {lines[240]!r}"
    out = [PARAMS]
    out.extend(lines[:240])
    out.append(AGG_BASE)
    return "\n".join(out)


if __name__ == "__main__":
    open("q/refunds-post-agg.sql", "w").write(build_post("post/fund_assignments_membership_refunds.sql"))
    open("q/refunds-base-agg.sql", "w").write(build_base("base/fund_assignments_membership_refunds.sql"))
    print("escritos q/refunds-post-agg.sql y q/refunds-base-agg.sql")
