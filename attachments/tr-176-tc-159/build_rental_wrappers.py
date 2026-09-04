#!/usr/bin/env python3
"""Construye wrappers agregados PRE/POST de rental_events_groups.sql para TC-159.

El query real corre completo (CTEs intactos); solo se envuelve el SELECT final en
una derived table y se proyectan contadores + checksums agregados. Así el PRE/POST
es numérico (sin traer 16,731 filas ni PII) y sigue siendo el query de verdad.

Los comentarios se strippean porque el keyword-scan de safesql los escanea y este
archivo dice "merge", "drop" e "Insert" en prosa (líneas 53/88/101/198/390).
"""
import subprocess
import sys

REPO = "/Users/veevart/Desktop/MigrationToolETL"
REL = "src/data-migration/infrastructure/destination/sql-server/queries/rental-event/rental_events_groups.sql"
OUT = "/private/tmp/claude-501/-Users-veevart-Desktop-testmanager-retooling/92c04aef-7c31-4c1c-93eb-b5e9022751ff/scratchpad"
PRE_SHA = "51c84e7"  # merge-base con origin/main

AGGREGATES = """SELECT
        COUNT(*) AS TotalRows,
        COUNT(DISTINCT q.Implementation_External_ID__c) AS DistinctExternalIds,
        SUM(CASE WHEN q.Auctifera__Client_Contact__c IS NOT NULL THEN 1 ELSE 0 END) AS ContactFilled,
        SUM(CASE WHEN q.Auctifera__Client_Company_Household__c IS NOT NULL THEN 1 ELSE 0 END) AS CompanyHouseholdFilled,
        SUM(CASE WHEN q.Auctifera__Client_Contact__c = '[ANONYMOUS_CONTACT]' THEN 1 ELSE 0 END) AS AnonymousContactRows,
        CHECKSUM_AGG(CHECKSUM(q.Implementation_External_ID__c, q.Auctifera__Client_Company_Household__c)) AS CompanyHouseholdChecksum,
        CHECKSUM_AGG(CHECKSUM(q.Implementation_External_ID__c, q.Auctifera__Client_Contact__c)) AS ContactChecksum
FROM (
"""


def strip_comments(text):
    """Quita comentarios -- respetando literales entre comillas simples."""
    out = []
    for line in text.split("\n"):
        in_str = False
        cut = None
        i = 0
        while i < len(line):
            ch = line[i]
            if ch == "'":
                in_str = not in_str
            elif not in_str and ch == "-" and i + 1 < len(line) and line[i + 1] == "-":
                cut = i
                break
            i += 1
        out.append(line if cut is None else line[:cut].rstrip())
    return "\n".join(out)


def build(sql_text, label):
    lines = sql_text.split("\n")
    # El SELECT final es el último ^SELECT del archivo; todo lo anterior es DECLARE + WITH + CTEs.
    final_idx = max(i for i, ln in enumerate(lines) if ln.startswith("SELECT"))
    header = "\n".join(lines[:final_idx])
    final = "\n".join(lines[final_idx:]).rstrip().rstrip(";")
    wrapper = strip_comments(header) + "\n" + AGGREGATES + strip_comments(final) + "\n) AS q;\n"
    path = f"{OUT}/rental-aggregate-{label}.sql"
    open(path, "w").write(wrapper)
    print(f"{label}: final SELECT en línea {final_idx + 1}, wrapper {len(wrapper)} chars -> {path}")


post = open(f"{REPO}/{REL}").read()
pre = subprocess.check_output(["git", "-C", REPO, "show", f"{PRE_SHA}:{REL}"], text=True)
build(post, "postfix")
build(pre, "prefix")
