#!/usr/bin/env python3
"""TC-180 escenario 8 — desbloqueo de la identidad de filas.

El preludio de inclusion es BYTE-IDENTICO en 382172b y en c1a9d82 (4.923 chars
normalizados). Se materializa UNA SOLA VEZ en #emitted y se sustituye, en LOS DOS
shapes por igual, el CUERPO de la CTE OpportunityExternalIds por una lectura de esa
tabla. Nada mas cambia: cada shape conserva intactos sus propios puntos de
aplicacion del gate, que es justamente lo que difiere entre ellos.

La sustitucion es identica en ambos lados, asi que no puede sesgar la comparacion:
si las dos salidas coinciden, coinciden por la logica que las distingue, no por el
andamiaje. La pregunta de COSTE no se toca aqui — ya quedo medida sobre las
consultas sin modificar (8,8 s el head, >120 s las dos formas previas).
"""
import re, pathlib

D = pathlib.Path(__file__).parent
NC = D / "nc"


def strip_comments(t):
    t = re.sub(r'--[^\n]*', '', t)
    return re.sub(r'/\*.*?\*/', '', t, flags=re.S)


def find_cte_body(t, name):
    """Devuelve (inicio_parentesis, fin_parentesis) del cuerpo de `name AS ( ... )`.

    Con frontera por delante: `DonationOpportunityExternalIds AS (` CONTIENE
    `OpportunityExternalIds AS (` y un find() a secas se queda con la CTE
    equivocada, que es justo el fallo que produjo "Invalid object name".
    """
    m = re.search(r'(?<![A-Za-z])' + name + r'\s+AS\s*\(', t)
    if not m:
        raise ValueError(f'CTE no encontrada: {name}')
    k = t.index('(', m.start())
    depth = 0
    for n in range(k, len(t)):
        if t[n] == '(':
            depth += 1
        elif t[n] == ')':
            depth -= 1
            if depth == 0:
                return k, n
    raise ValueError(name)


def prelude(t):
    i = t.find(';WITH')
    _, end = find_cte_body(t, 'OpportunityExternalIds')
    return t[i:end + 1]


head = strip_comments((D / "q" / "mg_head.sql").read_text())
pre = strip_comments((D / "q" / "mg_preperf.sql").read_text())

# 1. El preludio tiene que ser identico; si no, este metodo no es valido.
norm = lambda s: re.sub(r'\s+', ' ', s).strip()
assert norm(prelude(head)) == norm(prelude(pre)), "los preludios difieren: metodo invalido"

MATERIALIZE = (
    "DROP TABLE IF EXISTS #emitted;\n"
    + prelude(head)
    + "\nSELECT OpportunityExternalId INTO #emitted FROM OpportunityExternalIds;\n"
    + "CREATE INDEX ix_emitted ON #emitted (OpportunityExternalId);\n\n"
)

STUB = "(\n    SELECT OpportunityExternalId FROM #emitted\n)"

for label, text in (("preperf", pre), ("head", head)):
    a, b = find_cte_body(text, 'OpportunityExternalIds')
    swapped = text[:a] + STUB + text[b + 1:]
    out = NC / f"factored_{label}.nc.sql"
    out.write_text(MATERIALIZE + swapped)
    print(f"{out.name}: {len(out.read_text().splitlines())} lineas")

# 2. Fuera del cuerpo sustituido, los dos ficheros deben seguir difiriendo solo en
#    lo que el commit de rendimiento cambio. Se reporta para que quede escrito.
fa = norm((NC / "factored_preperf.nc.sql").read_text())
fb = norm((NC / "factored_head.nc.sql").read_text())
print(f"\ntexto normalizado: preperf={len(fa)} chars  head={len(fb)} chars  "
      f"{'IDENTICOS (sospechoso)' if fa == fb else 'siguen difiriendo (correcto)'}")
