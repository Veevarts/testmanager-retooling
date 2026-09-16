"""Verificacion independiente IM-1228. Cada CTE de cada archivo se materializa con su texto VERBATIM
en #temp (misma consulta logica, otro plan fisico) y el SELECT final real corre sobre esas tablas.
Salida solo numerica."""
import subprocess, sys, re
sys.path.insert(0, '.')
from sqlparse_cte import split_script, split_union_branches, lean_branch, rename, _scan_depth0
WT = '../tc170/etl-pr180'
Q = 'src/data-migration/infrastructure/destination/sql-server/queries/'
def show(ref, f): return subprocess.run(['git','-C',WT,'show', ref+':'+Q+f], capture_output=True, text=True, check=True).stdout

def cols(body):
    b = split_union_branches(body)[0]
    proj = re.sub(r'^\s*SELECT\b(\s+DISTINCT\b)?(\s+TOP\s*\(?\s*\d+\s*\)?)?', '', b[:_scan_depth0(b, r'FROM\b').start()], flags=re.I)
    items, cur, depth, ins = [], [], 0, False
    for ch in proj:
        if ins:
            cur.append(ch)
            if ch == "'": ins = False
            continue
        if ch == "'": ins = True
        elif ch == '(': depth += 1
        elif ch == ')': depth -= 1
        elif ch == ',' and depth == 0: items.append(''.join(cur).strip()); cur = []; continue
        cur.append(ch)
    items.append(''.join(cur).strip())
    out = []
    for it in items:
        a = re.search(r'\bAS\s+\[?([A-Za-z_][A-Za-z0-9_]*)\]?\s*$', it, re.I)
        out.append(a.group(1) if a else re.findall(r'([A-Za-z_][A-Za-z0-9_]*)\]?\s*$', it)[0])
    assert len(out) == len(set(o.lower() for o in out)), ('columnas duplicadas', out)
    return out

def materialize(ref, f, prefix, keep):
    pre, ctes, fin = split_script(show(ref, f))
    mp = {n: '#%s_%s' % (prefix, n) for n, _ in ctes}
    stm = []
    for n, body in ctes:
        c = cols(body)
        stm.append('SELECT %s INTO %s FROM (%s) AS x;' % (', '.join('x.' + k for k in c), mp[n], rename(body, mp)))
    final = rename(fin, mp)
    lean = ' UNION ALL '.join(lean_branch(b, keep) for b in split_union_branches(final))
    return pre, stm, lean

RR_KEEP = [(None,'Implementation_External_ID__c'), (None,'Auctifera__Rental_Event__c'), (None,'Auctifera__Rental_Status__c'),
           (None,'Auctifera__Subtotal_Amount3__c'), (None,'Auctifera__Tax_Amount3__c')]
EV_KEEP = [(None,'Implementation_External_ID__c'), (None,'Auctifera__Rental_Resource_Subtotals2__c'), (None,'Auctifera__Rental_Resource_Taxes3__c')]

def run_A(tag):
    """S1 paridad + S3 casos limite + grano del evento, todo sobre el head 9555d56"""
    pre, s_rr, rr = materialize('9555d56', 'rental-resource/rental_resource.sql', 'rr', RR_KEEP)
    _, s_ev, ev = materialize('9555d56', 'rental-event/rental_events_groups.sql', 'ev', EV_KEEP)
    body = [pre] + s_rr + ['SELECT q.Implementation_External_ID__c AS RRID, q.Auctifera__Rental_Event__c AS RID, q.Auctifera__Rental_Status__c AS RST, q.Auctifera__Subtotal_Amount3__c AS SUB3, q.Auctifera__Tax_Amount3__c AS TAX3 INTO #qa_rr FROM (%s) AS q;' % rr]
    body += s_ev + ['SELECT q.Implementation_External_ID__c AS RID, q.Auctifera__Rental_Resource_Subtotals2__c AS SUB2, q.Auctifera__Rental_Resource_Taxes3__c AS TAX3 INTO #qa_ev FROM (%s) AS q;' % ev]
    body.append("""SELECT RID, COUNT(*) AS N_RR,
  SUM(CASE WHEN ISNULL(RST,'') <> 'Canceled' THEN COALESCE(SUB3, 0) ELSE 0 END) AS PKG_SUB,
  SUM(CASE WHEN ISNULL(RST,'') <> 'Canceled' THEN COALESCE(TAX3, 0) ELSE 0 END) AS PKG_TAX,
  SUM(CASE WHEN SUB3 IS NULL OR TAX3 IS NULL THEN 1 ELSE 0 END) AS N_NULL3,
  SUM(CASE WHEN RST = 'Canceled' THEN 1 ELSE 0 END) AS N_CANCELED_RR
INTO #qa_pkg FROM #qa_rr GROUP BY RID;""")
    body.append("""SELECT r.ID AS RID,
  CASE WHEN so.STATUS = 'Cancelled' THEN 1 ELSE 0 END AS F_CANCELLED,
  CASE WHEN EXISTS (SELECT 1 FROM SALESORDERITEM soi INNER JOIN SALESORDERITEMORDERDISCOUNT d ON d.ID = soi.ID WHERE soi.SALESORDERID = r.ID) THEN 1 ELSE 0 END AS F_DISCOUNT,
  CASE WHEN EXISTS (SELECT 1 FROM SALESORDERITEM soi WHERE soi.SALESORDERID = r.ID AND soi.TYPE = 'Ticket' AND soi.TYPECODE <> '0' AND soi.TYPECODE NOT IN ('4','5')) THEN 1 ELSE 0 END AS F_DROPPED_TICKET,
  CASE WHEN EXISTS (SELECT 1 FROM SALESORDERITEM soi WHERE soi.SALESORDERID = r.ID AND soi.TYPECODE NOT IN ('4','5')) THEN 1 ELSE 0 END AS F_HAS_ITEMS
INTO #qa_flags FROM RESERVATION r LEFT JOIN SALESORDER so ON so.ID = r.ID;""")
    body.append("""SELECT e.RID, e.SUB2, e.TAX3, ISNULL(p.N_RR,0) AS N_RR, COALESCE(p.PKG_SUB,0) AS PKG_SUB, COALESCE(p.PKG_TAX,0) AS PKG_TAX,
  ISNULL(p.N_NULL3,0) AS N_NULL3, ISNULL(p.N_CANCELED_RR,0) AS N_CANCELED_RR, f.F_CANCELLED, f.F_DISCOUNT, f.F_DROPPED_TICKET, f.F_HAS_ITEMS,
  CASE WHEN e.SUB2 IS NULL OR e.TAX3 IS NULL OR e.SUB2 <> COALESCE(p.PKG_SUB,0) OR e.TAX3 <> COALESCE(p.PKG_TAX,0) THEN 1 ELSE 0 END AS MISMATCH
INTO #qa_cmp FROM #qa_ev e LEFT JOIN #qa_pkg p ON p.RID = e.RID LEFT JOIN #qa_flags f ON f.RID = e.RID;""")
    body.append("""SELECT
  (SELECT COUNT(*) FROM #qa_ev) AS ev_rows, (SELECT COUNT(DISTINCT RID) FROM #qa_ev) AS ev_distinct,
  (SELECT COUNT(*) FROM #qa_rr) AS rr_rows, (SELECT COUNT(DISTINCT RRID) FROM #qa_rr) AS rr_distinct_ids,
  (SELECT COUNT(*) FROM #qa_rr WHERE RID IS NOT NULL AND RID NOT IN (SELECT RID FROM #qa_ev)) AS rr_orphans,
  SUM(CASE WHEN SUB2 IS NULL THEN 1 ELSE 0 END) AS ev_sub2_null, SUM(CASE WHEN TAX3 IS NULL THEN 1 ELSE 0 END) AS ev_tax3_null,
  SUM(MISMATCH) AS ev_mismatch_exact,
  SUM(CASE WHEN ABS(COALESCE(SUB2,0) - PKG_SUB) > 0.005 OR ABS(COALESCE(TAX3,0) - PKG_TAX) > 0.005 THEN 1 ELSE 0 END) AS ev_mismatch_tol,
  SUM(CASE WHEN SUB2 > 0 THEN 1 ELSE 0 END) AS ev_nonzero_sub, SUM(CASE WHEN TAX3 > 0 THEN 1 ELSE 0 END) AS ev_nonzero_tax,
  CAST(SUM(COALESCE(SUB2,0)) AS DECIMAL(18,2)) AS sum_ev_sub2, CAST(SUM(PKG_SUB) AS DECIMAL(18,2)) AS sum_pkg_sub,
  CAST(SUM(COALESCE(TAX3,0)) AS DECIMAL(18,2)) AS sum_ev_tax3, CAST(SUM(PKG_TAX) AS DECIMAL(18,2)) AS sum_pkg_tax,
  SUM(N_NULL3) AS rr_rows_with_null_amount3,
  SUM(F_CANCELLED) AS res_cancelled, SUM(CASE WHEN F_CANCELLED = 1 AND N_RR > 0 THEN 1 ELSE 0 END) AS res_cancelled_with_rr,
  SUM(CASE WHEN F_CANCELLED = 1 AND (COALESCE(SUB2,0) <> 0 OR COALESCE(TAX3,0) <> 0) THEN 1 ELSE 0 END) AS cancelled_nonzero_totals,
  SUM(CASE WHEN F_CANCELLED = 1 AND N_RR > 0 AND N_CANCELED_RR <> N_RR THEN 1 ELSE 0 END) AS cancelled_with_non_canceled_rr,
  SUM(CASE WHEN N_RR = 0 THEN 1 ELSE 0 END) AS res_without_rr,
  SUM(CASE WHEN N_RR = 0 AND (SUB2 IS NULL OR TAX3 IS NULL OR SUB2 <> 0 OR TAX3 <> 0) THEN 1 ELSE 0 END) AS without_rr_not_zero,
  SUM(F_DISCOUNT) AS res_discount, SUM(CASE WHEN F_DISCOUNT = 1 THEN MISMATCH ELSE 0 END) AS discount_mismatch,
  SUM(F_DROPPED_TICKET) AS res_dropped_ticket, SUM(CASE WHEN F_DROPPED_TICKET = 1 THEN MISMATCH ELSE 0 END) AS dropped_ticket_mismatch,
  SUM(CASE WHEN F_HAS_ITEMS = 0 THEN 1 ELSE 0 END) AS res_without_items,
  SUM(CASE WHEN F_HAS_ITEMS = 0 AND (SUB2 IS NULL OR SUB2 <> 0 OR TAX3 IS NULL OR TAX3 <> 0) THEN 1 ELSE 0 END) AS without_items_not_zero
FROM #qa_cmp;""")
    sql = '\n'.join(body) + '\n'
    open('M2_A_%s.sql' % tag, 'w').write(sql)
    return sql

def run_B(tag):
    """S2 grano de recursos PRE (464c9d8) vs POST (9555d56) + S5 estado identico por fila"""
    pre, s_pre, rr_pre = materialize('464c9d8', 'rental-resource/rental_resource.sql', 'rrpre', RR_KEEP)
    _, s_post, rr_post = materialize('9555d56', 'rental-resource/rental_resource.sql', 'rrpost', RR_KEEP)
    body = [pre] + s_pre + ['SELECT q.Implementation_External_ID__c AS RRID, q.Auctifera__Rental_Status__c AS RST, q.Auctifera__Subtotal_Amount3__c AS SUB3, q.Auctifera__Tax_Amount3__c AS TAX3 INTO #qa_pre FROM (%s) AS q;' % rr_pre]
    body += s_post + ['SELECT q.Implementation_External_ID__c AS RRID, q.Auctifera__Rental_Status__c AS RST, q.Auctifera__Subtotal_Amount3__c AS SUB3, q.Auctifera__Tax_Amount3__c AS TAX3 INTO #qa_post FROM (%s) AS q;' % rr_post]
    body.append("""SELECT RRID, COUNT(*) AS N, MIN(SUB3) AS SUB_MIN, MAX(SUB3) AS SUB_MAX, SUM(TAX3) AS TAX_SUM, MIN(RST) AS RST_MIN, MAX(RST) AS RST_MAX
INTO #qa_pre_g FROM #qa_pre GROUP BY RRID;""")
    body.append("""SELECT
  (SELECT COUNT(*) FROM #qa_pre) AS pre_rows, (SELECT COUNT(*) FROM #qa_pre_g) AS pre_distinct_ids,
  (SELECT COUNT(*) FROM #qa_pre_g WHERE N > 1) AS pre_ids_duplicated, (SELECT COALESCE(SUM(N - 1),0) FROM #qa_pre_g WHERE N > 1) AS pre_extra_rows,
  (SELECT COUNT(*) FROM #qa_post) AS post_rows, (SELECT COUNT(DISTINCT RRID) FROM #qa_post) AS post_distinct_ids,
  (SELECT COUNT(*) FROM #qa_pre_g g LEFT JOIN #qa_post p ON p.RRID = g.RRID WHERE p.RRID IS NULL) AS ids_lost,
  (SELECT COUNT(*) FROM #qa_post p LEFT JOIN #qa_pre_g g ON g.RRID = p.RRID WHERE g.RRID IS NULL) AS ids_new,
  (SELECT COUNT(*) FROM #qa_pre_g g JOIN #qa_post p ON p.RRID = g.RRID WHERE g.N = 1 AND (ISNULL(g.SUB_MIN,-1) <> ISNULL(p.SUB3,-1) OR ISNULL(g.TAX_SUM,-1) <> ISNULL(p.TAX3,-1))) AS single_rate_amount_changed,
  (SELECT COUNT(*) FROM #qa_pre_g g JOIN #qa_post p ON p.RRID = g.RRID WHERE g.N > 1 AND ISNULL(g.SUB_MIN,-1) <> ISNULL(p.SUB3,-1)) AS multi_subtotal_changed,
  (SELECT COUNT(*) FROM #qa_pre_g g JOIN #qa_post p ON p.RRID = g.RRID WHERE g.N > 1 AND ABS(ISNULL(g.TAX_SUM,0) - ISNULL(p.TAX3,0)) > 0.01 * (g.N - 1)) AS multi_tax_not_combined,
  (SELECT COUNT(*) FROM #qa_pre_g g JOIN #qa_post p ON p.RRID = g.RRID WHERE ISNULL(g.RST_MIN,'~') <> ISNULL(p.RST,'~') OR ISNULL(g.RST_MAX,'~') <> ISNULL(p.RST,'~')) AS status_changed,
  CAST((SELECT SUM(SUB3) FROM #qa_pre) AS DECIMAL(18,2)) AS pre_sum_sub3, CAST((SELECT SUM(SUB3) FROM #qa_post) AS DECIMAL(18,2)) AS post_sum_sub3,
  CAST((SELECT SUM(TAX3) FROM #qa_pre) AS DECIMAL(18,2)) AS pre_sum_tax3, CAST((SELECT SUM(TAX3) FROM #qa_post) AS DECIMAL(18,2)) AS post_sum_tax3;""")
    sql = '\n'.join(body) + '\n'
    open('M2_B_%s.sql' % tag, 'w').write(sql)
    return sql

for fn, s in [('M2_A', run_A('li')), ('M2_B', run_B('li'))]:
    bad = sorted(set(w.upper() for w in re.findall(r'\b(DROP|DELETE|UPDATE|MERGE|ALTER|TRUNCATE|EXEC|GRANT)\b', s, re.I)))
    print('%s: %d bytes | INTO -> %d tablas #temp | otras escrituras: %s | SELECT *: %d' % (fn, len(s), len(re.findall(r'\bINTO\s+#', s)), bad or 'ninguna', len(re.findall(r'SELECT\s+\*', s, re.I))))
