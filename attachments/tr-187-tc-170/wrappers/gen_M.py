"""Lote M: cadenas de pago PRE y POST materializadas con texto verbatim; los 6 CASE de estado verbatim
evaluados por reserva; invariancia del ticket en ordenes que no son reservas. Salida numerica."""
import subprocess, sys, re
sys.path.insert(0, '.')
from sqlparse_cte import split_script, split_union_branches, projection_expr, rename
Q = 'src/data-migration/infrastructure/destination/sql-server/queries/'
PRE, POST = '8b522c3', '464c9d8'
EX1, EX2 = '128A24C3-4A69-403C-9102-C9E7FE883A56', '02245AEA-853E-4C9D-AF78-D86F940D95D9'
PAY = ['RentalOrders', 'PaymentRefunds', 'RentalPaymentRows', 'RentalPaymentRollups']
def show(ref, f): return subprocess.run(['git','-C','etl-pr180','show', ref+':'+Q+f], capture_output=True, text=True, check=True).stdout
norm = lambda s: ' '.join(s.split())

def rc(expr):   # codigo numerico de estado rental / crudo
    m = [('Canceled',1),('Paid',2),('Reserved/Partially Paid',3),('Signed Contract',4),('Proposal/Negotiation',5),('Inquiry',6),
         ('Pending',11),('Complete',12),('Tentative',13),('Confirmed',14),('Finalized',15),('Cancelled',16),('Reserved',17),('Unresolved',18)]
    return 'CASE WHEN %s IS NULL THEN 0 %s ELSE 99 END' % (expr, ' '.join("WHEN %s = '%s' THEN %d" % (expr, v, c) for v, c in m))
def tc(expr):   # codigo numerico de estado de ticket / crudo
    m = [('Canceled',21),('Sold',22),('Reserved',23),('Pending',24),('Confirmed',25),('Finalized',26),('Complete',27),
         ('Tentative',28),('Unresolved',29),('Cancelled',30),('Refunded',31)]
    return 'CASE WHEN %s IS NULL THEN 0 %s ELSE 99 END' % (expr, ' '.join("WHEN %s = '%s' THEN %d" % (expr, v, c) for v, c in m))

def event_case(ref):
    _, _, f = split_script(show(ref, 'rental-event/rental_events_groups.sql'))
    return projection_expr(split_union_branches(f)[0], 'Auctifera__Status__c')
def resource_case(ref):
    _, c, _ = split_script(show(ref, 'rental-resource/rental_resource.sql'))
    return projection_expr(split_union_branches(dict(c)['BaseRentalResources'])[0], 'Auctifera__Rental_Status__c')
def ticket_cases(ref):
    out = {}
    for f in ['ticketing/ticketing_only_program.sql', 'ticketing/ticketing_only_event.sql', 'ticketing/ticketing.sql']:
        _, _, fin = split_script(show(ref, f))
        for k, b in enumerate(split_union_branches(fin)):
            out['%s#%d' % (f.split('/')[-1], k)] = projection_expr(b, 'Auctifera__Status__c')
    return out

def pay_chain(ref, prefix):
    pre, c, _ = split_script(show(ref, 'rental-event/rental_events_groups.sql'))
    d = dict(c); mp = {n: '#%s_%s' % (prefix, n) for n in PAY}
    from sqlparse_cte import _scan_depth0
    def cols(body):
        b = split_union_branches(body)[0]
        proj = re.sub(r'^\s*SELECT\b(\s+DISTINCT\b)?', '', b[:_scan_depth0(b, r'FROM\b').start()], flags=re.I)
        items, cur, depth, in_str = [], [], 0, False
        for ch in proj:
            if in_str:
                cur.append(ch)
                if ch == "'": in_str = False
                continue
            if ch == "'": in_str = True
            elif ch == '(': depth += 1
            elif ch == ')': depth -= 1
            elif ch == ',' and depth == 0:
                items.append(''.join(cur).strip()); cur = []; continue
            cur.append(ch)
        items.append(''.join(cur).strip())
        out = []
        for it in items:
            a = re.search(r'\bAS\s+([A-Za-z_][A-Za-z0-9_]*)\s*$', it)
            out.append(a.group(1) if a else re.findall(r'([A-Za-z_][A-Za-z0-9_]*)\s*$', it)[0])
        return out
    stm = []
    for n in PAY:
        cl = cols(d[n]); assert cl, n
        stm.append('SELECT %s INTO %s FROM (%s) AS x;' % (', '.join('x.' + c for c in cl), mp[n], rename(d[n], mp)))
    return pre, stm

# chequeo estatico: los CASE de ticket son identicos entre los 3 archivos / ramas
for ref in (PRE, POST):
    tk = ticket_cases(ref)
    print('%s CASE de ticket en %d ramas: %s' % (ref, len(tk), 'IDENTICOS' if len({norm(v) for v in tk.values()}) == 1 else 'DIFIEREN ' + str({k: norm(v)[:60] for k, v in tk.items()})))

preamble, pre_stm = pay_chain(PRE, 'pre')
_, post_stm = pay_chain(POST, 'post')
ev_pre  = rename(event_case(PRE), {'rpr': 'rpr_pre'})
ev_post = rename(event_case(POST), {'rpr': 'rpr_post'})
rr_pre  = rename(resource_case(PRE), {'rpr': 'rpr_pre'})
rr_post = rename(resource_case(POST), {'rpr': 'rpr_post'})
tk_pre  = rename(list(ticket_cases(PRE).values())[0], {'rpr': 'rpr_pre'})
tk_post = rename(list(ticket_cases(POST).values())[0], {'rpr': 'rpr_post'})
assert 'rpr_pre' in ev_pre and 'rpr_post' in ev_post and 'rpr_post' in rr_post and 'rpr_post' in tk_post

# recursos existentes por reserva: query real de recurso PRE (sin cadena de pago), solo clave
_, rrc, rrf = split_script(show(PRE, 'rental-resource/rental_resource.sql'))
from sqlparse_cte import lean_branch
rr_key = ' UNION ALL '.join(lean_branch(b, [(None, 'Auctifera__Rental_Event__c')]) for b in split_union_branches(rrf))
rr_presence = ('WITH ' + ',\n'.join('%s AS (%s)' % x for x in rrc + [('ResourceOut', rr_key)]) +
               '\nSELECT Auctifera__Rental_Event__c AS RID, COUNT(*) AS N_RR INTO #qa_rrn FROM ResourceOut GROUP BY Auctifera__Rental_Event__c;')

MAP = """CASE %s WHEN 'Paid' THEN 'Sold' WHEN 'Reserved/Partially Paid' THEN 'Reserved' WHEN 'Signed Contract' THEN 'Reserved'
  WHEN 'Proposal/Negotiation' THEN 'Reserved' WHEN 'Inquiry' THEN 'Pending' WHEN 'Canceled' THEN 'Canceled' END"""

res = """SELECT r.ID AS RID, so.STATUSCODE AS SC, so.STATUS AS ST, COALESCE(so.AMOUNT,0) AS AMT,
  COALESCE(rpr_post.PAID_AMOUNT,0) AS PG, COALESCE(rpr_post.NET_PAID_AMOUNT,0) AS PN, COALESCE(rpr_post.TOTAL_REFUNDED_AMOUNT,0) AS RF,
  COALESCE(rpr_pre.NET_PAID_AMOUNT,0) AS PN_PRECHAIN,
  CASE WHEN so.LOOKUPID = '8-15359860' THEN 1 WHEN so.LOOKUPID = '8-15013828' THEN 2 ELSE 0 END AS LK,
  CASE WHEN r.ID = '%s' THEN 1 WHEN r.ID = '%s' THEN 2 ELSE 0 END AS EX,
  (%s) AS EV_PRE, (%s) AS RR_PRE, (%s) AS EV_POST, (%s) AS RR_POST, (%s) AS TK_PRE, (%s) AS TK_POST
INTO #qa_res
FROM RESERVATION r
LEFT JOIN SALESORDER so ON so.ID = r.ID
LEFT JOIN #pre_RentalPaymentRollups rpr_pre ON rpr_pre.RESERVATIONID = r.ID
LEFT JOIN #post_RentalPaymentRollups rpr_post ON rpr_post.RESERVATIONID = r.ID;""" % (EX1, EX2, ev_pre, rr_pre, ev_post, rr_post, tk_pre, tk_post)

codes = """SELECT q.RID, q.SC, q.ST, q.AMT, q.PG, q.PN, q.RF, q.PN_PRECHAIN, q.LK, q.EX, q.EV_PRE, q.RR_PRE, q.EV_POST, q.RR_POST, q.TK_PRE, q.TK_POST, ISNULL(n.N_RR,0) AS N_RR,
  %s AS C_EV_PRE, %s AS C_RR_PRE, %s AS C_EV_POST, %s AS C_RR_POST, %s AS C_TK_PRE, %s AS C_TK_POST,
  %s AS C_TK_EXPECTED_POST,
  CASE WHEN q.PG > 0 AND q.PG >= q.AMT THEN 2 WHEN q.PG > 0 THEN 1 WHEN q.AMT <= 0 THEN 3 ELSE 0 END AS BAND,
  CASE WHEN q.PN > 0 AND q.PN >= q.AMT THEN 1 ELSE 0 END AS NET_FULL
INTO #qa_codes FROM #qa_res q LEFT JOIN #qa_rrn n ON n.RID = q.RID;""" % (
    rc('q.EV_PRE'), rc('q.RR_PRE'), rc('q.EV_POST'), rc('q.RR_POST'), tc('q.TK_PRE'), tc('q.TK_POST'), tc(MAP % 'q.EV_POST'))

# trigger simulado (PR): Paid si no esta Canceled y paid bruto > 0 y >= total
TRG = "CASE WHEN %s <> 1 AND PG > 0 AND PG >= AMT THEN 2 ELSE %s END"
summary = """SELECT
  COUNT(*) AS n_res,
  SUM(CASE WHEN N_RR > 0 THEN 1 ELSE 0 END) AS n_res_with_rr,
  SUM(CASE WHEN N_RR > 0 AND C_EV_PRE <> C_RR_PRE THEN 1 ELSE 0 END) AS pre_div_query,
  SUM(CASE WHEN N_RR > 0 AND C_EV_POST <> C_RR_POST THEN 1 ELSE 0 END) AS post_div_query,
  SUM(CASE WHEN N_RR > 0 AND (%s) = 2 AND C_RR_PRE NOT IN (1,2) THEN 1 ELSE 0 END) AS pre_trg_paid_vs_rr_npc,
  SUM(CASE WHEN N_RR > 0 AND (%s) = 2 AND C_RR_POST NOT IN (1,2) THEN 1 ELSE 0 END) AS post_trg_paid_vs_rr_npc,
  SUM(CASE WHEN N_RR > 0 AND (%s) <> C_RR_PRE THEN 1 ELSE 0 END) AS pre_div_after_trigger_any,
  SUM(CASE WHEN N_RR > 0 AND (%s) <> C_RR_POST THEN 1 ELSE 0 END) AS post_div_after_trigger_any,
  SUM(CASE WHEN C_EV_PRE = 2 AND PG < AMT THEN 1 ELSE 0 END) AS pre_ev_paid_owed,
  SUM(CASE WHEN C_EV_POST = 2 AND PG < AMT THEN 1 ELSE 0 END) AS post_ev_paid_owed,
  SUM(CASE WHEN N_RR > 0 AND C_RR_PRE = 2 AND PG < AMT THEN 1 ELSE 0 END) AS pre_rr_paid_owed,
  SUM(CASE WHEN N_RR > 0 AND C_RR_POST = 2 AND PG < AMT THEN 1 ELSE 0 END) AS post_rr_paid_owed,
  SUM(CASE WHEN N_RR > 0 AND C_EV_PRE = 2 AND C_RR_PRE = 2 AND PG < AMT THEN 1 ELSE 0 END) AS pre_both_paid_owed,
  SUM(CASE WHEN N_RR > 0 AND C_EV_POST = 2 AND C_RR_POST = 2 AND PG < AMT THEN 1 ELSE 0 END) AS post_both_paid_owed,
  SUM(CASE WHEN C_EV_PRE >= 11 THEN 1 ELSE 0 END) AS pre_ev_raw, SUM(CASE WHEN C_EV_POST >= 11 THEN 1 ELSE 0 END) AS post_ev_raw,
  SUM(CASE WHEN C_RR_PRE >= 11 THEN 1 ELSE 0 END) AS pre_rr_raw, SUM(CASE WHEN C_RR_POST >= 11 THEN 1 ELSE 0 END) AS post_rr_raw,
  SUM(CASE WHEN C_TK_PRE IN (25,26,27,28,29,30,99) THEN 1 ELSE 0 END) AS pre_tk_raw_or_confirmed,
  SUM(CASE WHEN C_TK_POST IN (25,26,27,28,29,30,99) THEN 1 ELSE 0 END) AS post_tk_raw_or_confirmed,
  SUM(CASE WHEN C_TK_PRE = 25 THEN 1 ELSE 0 END) AS pre_tk_confirmed, SUM(CASE WHEN C_TK_PRE = 26 THEN 1 ELSE 0 END) AS pre_tk_finalized,
  SUM(CASE WHEN C_TK_POST = 25 THEN 1 ELSE 0 END) AS post_tk_confirmed, SUM(CASE WHEN C_TK_POST = 26 THEN 1 ELSE 0 END) AS post_tk_finalized,
  SUM(CASE WHEN C_TK_PRE = 24 AND PG > 0 AND PG >= AMT THEN 1 ELSE 0 END) AS pre_tk_pending_fully_paid,
  SUM(CASE WHEN C_TK_POST = 24 AND PG > 0 AND PG >= AMT THEN 1 ELSE 0 END) AS post_tk_pending_fully_paid,
  SUM(CASE WHEN C_TK_POST <> C_TK_EXPECTED_POST THEN 1 ELSE 0 END) AS post_tk_vs_mapping_mismatch,
  SUM(CASE WHEN C_TK_PRE <> (%s) THEN 1 ELSE 0 END) AS pre_tk_vs_mapping_mismatch,
  SUM(CASE WHEN C_EV_PRE <> C_EV_POST THEN 1 ELSE 0 END) AS ev_status_changed,
  SUM(CASE WHEN C_RR_PRE <> C_RR_POST THEN 1 ELSE 0 END) AS rr_status_changed,
  SUM(CASE WHEN N_RR > 0 AND (C_EV_PRE <> C_EV_POST OR C_RR_PRE <> C_RR_POST) THEN 1 ELSE 0 END) AS ev_or_rr_changed_with_rr,
  SUM(CASE WHEN C_TK_PRE <> C_TK_POST THEN 1 ELSE 0 END) AS tk_status_changed,
  SUM(CASE WHEN RF > 0 THEN 1 ELSE 0 END) AS n_refunded,
  SUM(CASE WHEN BAND = 2 AND NET_FULL = 0 THEN 1 ELSE 0 END) AS n_paid_gross_not_net,
  SUM(CASE WHEN BAND = 2 AND NET_FULL = 0 AND C_EV_POST = 2 THEN 1 ELSE 0 END) AS post_emitted_paid_gross_not_net,
  SUM(CASE WHEN ABS(PN - PN_PRECHAIN) > 0.001 THEN 1 ELSE 0 END) AS net_paid_prechain_vs_postchain_diff
FROM #qa_codes;""" % (TRG % ('C_EV_PRE', 'C_EV_PRE'), TRG % ('C_EV_POST', 'C_EV_POST'),
                      TRG % ('C_EV_PRE', 'C_EV_PRE'), TRG % ('C_EV_POST', 'C_EV_POST'),
                      tc(MAP % 'q2.EV_PRE').replace('q2.EV_PRE', 'EV_PRE'))

arms = """SELECT SC, BAND, CASE WHEN AMT <= 0 THEN 1 ELSE 0 END AS AMT_ZERO, NET_FULL,
  C_EV_PRE, C_RR_PRE, C_EV_POST, C_RR_POST, C_TK_PRE, C_TK_POST, COUNT(*) AS n,
  SUM(CASE WHEN N_RR > 0 THEN 1 ELSE 0 END) AS n_with_rr,
  SUM(CASE WHEN ST = 'Pending' THEN 1 ELSE 0 END) AS st_pending, SUM(CASE WHEN ST = 'Complete' THEN 1 ELSE 0 END) AS st_complete,
  SUM(CASE WHEN ST = 'Tentative' THEN 1 ELSE 0 END) AS st_tentative, SUM(CASE WHEN ST = 'Confirmed' THEN 1 ELSE 0 END) AS st_confirmed,
  SUM(CASE WHEN ST = 'Finalized' THEN 1 ELSE 0 END) AS st_finalized, SUM(CASE WHEN ST = 'Cancelled' THEN 1 ELSE 0 END) AS st_cancelled,
  SUM(CASE WHEN ST = 'Reserved' THEN 1 ELSE 0 END) AS st_reserved, SUM(CASE WHEN ST = 'Unresolved' THEN 1 ELSE 0 END) AS st_unresolved
FROM #qa_codes
GROUP BY SC, BAND, CASE WHEN AMT <= 0 THEN 1 ELSE 0 END, NET_FULL, C_EV_PRE, C_RR_PRE, C_EV_POST, C_RR_POST, C_TK_PRE, C_TK_POST
ORDER BY SC, BAND, AMT_ZERO, NET_FULL, C_EV_POST;"""

examples = """SELECT EX, LK, SC, AMT, PG, PN, RF, N_RR, C_EV_PRE, C_RR_PRE, C_TK_PRE, C_EV_POST, C_RR_POST, C_TK_POST
FROM #qa_codes WHERE EX > 0 ORDER BY EX;"""

nonres = """SELECT COUNT(*) AS n_orders,
  SUM(CASE WHEN r.ID IS NULL THEN 1 ELSE 0 END) AS n_non_reservation_orders,
  SUM(CASE WHEN r.ID IS NULL AND ISNULL(PRE_TK,'~') <> ISNULL(POST_TK,'~') THEN 1 ELSE 0 END) AS non_res_ticket_status_changed,
  SUM(CASE WHEN r.ID IS NOT NULL AND ISNULL(PRE_TK,'~') <> ISNULL(POST_TK,'~') THEN 1 ELSE 0 END) AS res_ticket_status_changed
FROM SALESORDER so
LEFT JOIN RESERVATION r ON r.ID = so.ID
LEFT JOIN #pre_RentalPaymentRollups rpr_pre ON rpr_pre.RESERVATIONID = so.ID
LEFT JOIN #post_RentalPaymentRollups rpr_post ON rpr_post.RESERVATIONID = so.ID
CROSS APPLY (SELECT (%s) AS PRE_TK, (%s) AS POST_TK) t;""" % (tk_pre, tk_post)

sql = '\n'.join([preamble] + pre_stm + post_stm + [rr_presence, res, codes, summary, examples, arms, nonres]) + '\n'
open('M_batch.sql', 'w').write(sql)
bad = sorted(set(w.upper() for w in re.findall(r'\b(DROP|DELETE|UPDATE|MERGE|ALTER|TRUNCATE|EXEC|GRANT)\b', sql, re.I)))
print('M_batch.sql %d bytes | SELECT INTO -> %s | otras escrituras: %s' % (len(sql), re.findall(r'\bINTO\s+(#\w+)', sql), bad or 'ninguna'))
