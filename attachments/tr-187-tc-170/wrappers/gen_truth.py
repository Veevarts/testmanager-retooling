"""Tabla de verdad: los CASE de estado VERBATIM del PR evaluados en SQL Server sobre filas sinteticas.
No lee tablas del cliente. Las expectativas se calculan aparte en Python desde la regla declarada del PR."""
import sys, re, json, itertools
sys.path.insert(0, '.')
from sqlparse_cte import rename
from gen_M import event_case, resource_case, ticket_cases, rc, tc, PRE, POST
STATUSES = [('Pending',0),('Complete',1),('Tentative',2),('Confirmed',3),('Finalized',4),('Cancelled',5),('Reserved',6),('Unresolved',7)]
# (amount, paid)  None = sin fila de pago (rpr NULL)
PAY = [(100, None), (100, 0), (100, 40), (100, 100), (100, 150), (0, None), (0, 50), (None, None)]
rows, k = [], 0
for (st, sc), (amt, paid) in itertools.product(STATUSES, PAY):
    k += 1
    rows.append((k, st, sc, amt, paid))
def lit(v): return 'NULL' if v is None else str(v)
values = ',\n  '.join("(%d, '%s', %d, %s, %s)" % (k, st, sc, lit(a), lit(p)) for k, st, sc, a, p in rows)
ev_post = event_case(POST); rr_post = resource_case(POST)
tk_post = list(ticket_cases(POST).values())[0]; tk_pre = list(ticket_cases(PRE).values())[0]
tk_post_nonres = rename(tk_post, {'r': 'r0'}); tk_pre_nonres = rename(tk_pre, {'r': 'r0'})
sql = """SELECT t.k,
  %s AS ev_post, %s AS rr_post, %s AS tk_post_res, %s AS tk_post_nonres, %s AS tk_pre_nonres
FROM (VALUES
  %s
) AS t(k, STATUS, STATUSCODE, AMOUNT, PAID)
CROSS APPLY (SELECT CAST(t.STATUS AS NVARCHAR(20)) AS STATUS, CAST(t.STATUSCODE AS TINYINT) AS STATUSCODE, CAST(t.AMOUNT AS MONEY) AS AMOUNT) so
CROSS APPLY (SELECT CAST(t.PAID AS MONEY) AS PAID_AMOUNT, CAST(t.PAID AS MONEY) AS NET_PAID_AMOUNT) rpr
CROSS APPLY (SELECT CAST('00000000-0000-0000-0000-000000000001' AS UNIQUEIDENTIFIER) AS ID) r
CROSS APPLY (SELECT CAST(NULL AS UNIQUEIDENTIFIER) AS ID) r0
ORDER BY t.k;""" % (rc('(%s)' % ev_post), rc('(%s)' % rr_post), tc('(%s)' % tk_post), tc('(%s)' % tk_post_nonres), tc('(%s)' % tk_pre_nonres), values)
open('truth_table.sql', 'w').write(sql + '\n')
json.dump(rows, open('truth_rows.json', 'w'))
print('truth_table.sql: %d filas sinteticas, %d bytes, escrituras: %s' % (len(rows), len(sql),
      sorted(set(re.findall(r'\b(INSERT|UPDATE|DELETE|MERGE|DROP|ALTER|TRUNCATE|INTO)\b', sql, re.I))) or 'ninguna'))
