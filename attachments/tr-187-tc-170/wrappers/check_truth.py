"""Compara la salida de truth_table.sql (CASE verbatim en SQL Server) con la regla declarada en el PR."""
import json, glob, sys
RC = {1:'Canceled',2:'Paid',3:'Reserved/Partially Paid',4:'Signed Contract',5:'Proposal/Negotiation',6:'Inquiry',0:'NULL',99:'otro'}
TC = {21:'Canceled',22:'Sold',23:'Reserved',24:'Pending',25:'Confirmed',26:'Finalized',27:'Complete',28:'Tentative',29:'Unresolved',30:'Cancelled',31:'Refunded',0:'NULL',99:'otro'}
def rental(st, amt, paid):                      # regla declarada en el body del PR
    a, p = (amt or 0), (paid or 0)
    if st == 'Cancelled': return 'Canceled'
    if p > 0 and p >= a: return 'Paid'
    if p > 0: return 'Reserved/Partially Paid'
    if st in ('Complete', 'Finalized') and a <= 0: return 'Paid'
    if st in ('Complete', 'Finalized', 'Confirmed'): return 'Signed Contract'
    if st == 'Tentative': return 'Proposal/Negotiation'
    if st == 'Pending': return 'Inquiry'
    if st in ('Reserved', 'Unresolved'): return 'Reserved/Partially Paid'
    return 'Inquiry'
TMAP = {'Paid':'Sold','Reserved/Partially Paid':'Reserved','Signed Contract':'Reserved','Proposal/Negotiation':'Reserved','Inquiry':'Pending','Canceled':'Canceled'}
rows = {r[0]: r for r in json.load(open('truth_rows.json'))}
out = json.load(open(sys.argv[1]))['recordsets'][0]
fails, lines = 0, []
for o in out:
    k, st, sc, amt, paid = rows[o['k']]
    exp = rental(st, amt, paid)
    got_ev, got_rr, got_tk = RC[o['ev_post']], RC[o['rr_post']], TC[o['tk_post_res']]
    ok = (got_ev == exp and got_rr == exp and got_tk == TMAP[exp] and o['tk_post_nonres'] == o['tk_pre_nonres'])
    fails += 0 if ok else 1
    lines.append('%2d %-10s total=%-5s pagado=%-5s | esperado %-24s | evento %-24s recurso %-24s ticket %-9s | no-reserva PRE=%-10s POST=%-10s | %s' % (
        k, st, amt, paid, exp, got_ev, got_rr, got_tk, TC[o['tk_pre_nonres']], TC[o['tk_post_nonres']], 'OK' if ok else 'DIVERGE'))
print('\n'.join(lines))
print('\nfilas: %d | divergencias: %d' % (len(out), fails))
