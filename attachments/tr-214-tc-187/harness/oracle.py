"""Oraculo independiente de IM-1245: recalcula desde las filas crudas de dev lo que dicen los AC
y lo compara con cada respuesta de la API. Escrito desde el texto de los AC, no desde el codigo."""
import json, sys, math, collections
S = sys.argv[1]
rows = json.load(open(f"{S}/rows-qa.json"))["rows"]
api = json.load(open(f"{S}/api-matrix.json"))
NEWEST_TODAY = "2026-09"   # mes en curso el dia de la corrida

# Clasificacion declarada (catalogo de playbooks, PERIOD_COMPARISON.metricAggregation)
SUM = set("""courses_income courses_sold credit_card_transactions_count credit_card_transactions_income donations_income
grants_income groups_income groups_sold membership_income new_members number_of_chargebacks number_of_chargebacks_lost
number_of_donations number_of_grants number_of_memberships number_of_total_payments number_of_visitors rentals_income
rentals_income_split rentals_sold shop_income shopify_income ticketing_income tickets_sold total_payment_value_adyen
total_value_of_chargebacks total_value_of_chargebacks_lost waiting_list_revenue""".split())
LAST = {"active_campaigns_count", "current_members", "recurring_donations", "recurring_memberships"}
agg = lambda c: "flow" if c in SUM else "stock" if c in LAST else "unclassified"

MON = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()
idx = lambda m: int(m[:4]) * 12 + int(m[5:7]) - 1
mon = lambda i: f"{i // 12:04d}-{i % 12 + 1:02d}"
add = lambda m, d: mon(idx(m) + d)
span = lambda a, b: [mon(i) for i in range(idx(a), idx(b) + 1)]
lab = lambda m: f"{MON[int(m[5:7]) - 1]} {m[:4]}"
rlab = lambda a, b: lab(a) if a == b else f"{lab(a)} – {lab(b)}"

series = collections.defaultdict(dict)
for r in rows:
    series[r["metric_code"]][r["period_start"][:7]] = float(r["value"])
available = sorted({m for s in series.values() for m in s})
newest = available[-1]

def block(vals, months, reported, kind):
    rep = [m for m in months if m in reported]
    cov = (len(rep), len(months))
    if not rep: return None, cov, None
    if kind == "flow":
        return round(sum(vals.get(m, 0.0) for m in rep), 4), cov, None
    if kind == "stock":
        for m in reversed(rep):
            if m in vals: return vals[m], cov, m
        return None, cov, None
    if len(months) == 1 and months[0] in vals: return vals[months[0]], cov, months[0]
    return None, cov, None

def buckets(a, b, g):
    size = {"month": 1, "quarter": 3, "year": 12}[g]
    start = lambda m: m if g == "month" else (mon(idx(m) - idx(m) % 3) if g == "quarter" else m[:4] + "-01")
    out, cur = [], []
    for m in span(a, b):
        if cur and start(m) != start(cur[0]): out.append(cur); cur = []
        cur.append(m)
    out.append(cur)
    return [(ms, len(ms) < size) for ms in out]

def name(ms, g, cut_like):
    if g == "month": return lab(ms[0])
    if not cut_like and g == "quarter": return f"Q{(int(ms[0][5:7]) - 1) // 3 + 1} {ms[0][:4]}"
    if not cut_like and g == "year": return ms[0][:4]
    return rlab(ms[0], ms[-1])

def calendar_aligned(ms, g):
    if g == "quarter": return len(ms) == 3 and (int(ms[0][5:7]) - 1) % 3 == 0
    if g == "year": return len(ms) == 12 and ms[0][5:7] == "01"
    return True

def expected_applied(qs):
    p = dict(x.split("=") for x in qs.split("&") if x)
    to = p.get("to", newest); fr = p.get("from", add(to, -11))
    cmp = p.get("compare", "previous_period")
    return fr, to, cmp, int(p["compareYears"]) if cmp == "years_back" else None, p.get("compareFrom"), p.get("groupBy", "month")

def comparison(fr, to, cmp, yrs, cfrom):
    n = len(span(fr, to))
    if cmp == "none": return None
    if cmp == "previous_period": return add(fr, -n), add(fr, -1)
    if cmp == "years_back": return add(fr, -12 * (yrs or 1)), add(to, -12 * (yrs or 1))
    return cfrom, add(cfrom, n - 1)

fails, checked, notes = [], collections.Counter(), []
def eq(a, b):
    if a is None or b is None: return a is b
    return math.isclose(float(a), float(b), rel_tol=1e-9, abs_tol=1e-6)

for key, v in api.items():
    if v["status"] != 200 or key in ("c30_unfiltered", "n16_sin_parametros_overview"): continue
    b = v["body"]; fr, to, cmp, yrs, cfrom, g = expected_applied(v["qs"])
    ap = b["appliedFilters"]
    got = (ap["from"], ap["to"], ap["compare"], ap["compareYears"], ap["compareFrom"], ap["groupBy"])
    exp = (fr, to, cmp, yrs, cfrom if cmp == "custom" else None, g)
    checked["applied"] += 1
    if got != exp: fails.append((key, "appliedFilters", exp, got))
    B = comparison(fr, to, cmp, yrs, cfrom)
    if (b["comparisonPeriod"] and (b["comparisonPeriod"]["from"], b["comparisonPeriod"]["to"])) != (B if B else None):
        fails.append((key, "comparisonPeriod", B, b["comparisonPeriod"]))
    if b["availableMonths"] != available: fails.append((key, "availableMonths", len(available), len(b["availableMonths"])))
    if b["dataThroughPeriod"] != newest or b["dataThroughLabel"] != lab(newest): fails.append((key, "dataThrough", newest, b["dataThroughPeriod"]))
    # groupings: >= 2 buckets (month siempre)
    eg = ["month"] + [x for x in ("quarter", "year") if len(buckets(fr, to, x)) >= 2]
    checked["groupings"] += 1
    if b["groupings"] != eg: fails.append((key, "groupings", eg, b["groupings"]))
    # comparisonOptions
    n = len(span(fr, to)); opts = []
    def opt(kind, y, bf):
        bt = add(bf, n - 1); rep = sum(1 for m in span(bf, bt) if m in available)
        ov = bf <= to and fr <= bt
        reason = "overlaps_primary" if ov else ("no_data" if rep == 0 else None)
        return {"compare": kind, "years": y, "from": bf, "to": bt, "reportedMonths": rep, "of": n, "unavailableReason": reason, "available": reason is None}
    opts.append(opt("previous_period", None, add(fr, -n)))
    for y in range(1, 11):
        bf = add(fr, -12 * y)
        if add(bf, n - 1) < available[0]: break
        opts.append(opt("years_back", y, bf))
    gotopts = [{k: o[k] for k in ("compare", "years", "from", "to", "reportedMonths", "of", "unavailableReason", "available")} for o in b["comparisonOptions"]]
    checked["options"] += 1
    if gotopts != opts: fails.append((key, "comparisonOptions", opts, gotopts))
    hasData = any(fr <= m <= to for m in available)
    if b["hasData"] != hasData: fails.append((key, "hasData", hasData, b["hasData"]))
    if not hasData:
        if b["metrics"]: fails.append((key, "metrics-when-no-data", 0, len(b["metrics"])))
        continue
    bks = buckets(fr, to, g)
    gotm = {m["metricCode"]: m for m in b["metrics"]}
    if set(gotm) != set(series): fails.append((key, "metric-set", len(series), len(gotm)))
    for code, vals in series.items():
        m = gotm.get(code)
        if not m: continue
        kind = agg(code); first = min(vals)
        reported = {x for x in available if x >= first}
        checked["metric"] += 1
        if m["aggregation"] != kind: fails.append((key, code, "aggregation", kind, m["aggregation"]))
        va, ca, asa = block(vals, span(fr, to), reported, kind)
        for fld, e in (("latestValue", va), ("latestAsOf", asa)):
            if not (eq(m[fld], e) if fld == "latestValue" else m[fld] == e): fails.append((key, code, fld, e, m[fld]))
        if (m["coverage"]["months"], m["coverage"]["of"]) != ca: fails.append((key, code, "coverage", ca, m["coverage"]))
        trend = []
        for ms, cut in bks:
            bv, bc, _ = block(vals, ms, reported, kind)
            trend.append((name(ms, g, cut), bv, cut or bc[0] < bc[1]))
        gt = [(p["periodLabel"], p["value"], p["partial"]) for p in m["trend"]]
        if len(gt) != len(trend) or any(x[0] != y[0] or not eq(x[1], y[1]) or x[2] != y[2] for x, y in zip(trend, gt)):
            fails.append((key, code, "trend", trend, gt))
        if B is None:
            if m["previousValue"] is not None or m["changePct"] is not None or m["comparisonTrend"] is not None:
                fails.append((key, code, "none-leaks", m["previousValue"], m["changePct"]))
            continue
        vb, cb, asb = block(vals, span(*B), reported, kind)
        if not eq(m["previousValue"], vb) or m["previousAsOf"] != asb: fails.append((key, code, "previous", (vb, asb), (m["previousValue"], m["previousAsOf"])))
        if (m["comparisonCoverage"]["months"], m["comparisonCoverage"]["of"]) != cb: fails.append((key, code, "comparisonCoverage", cb, m["comparisonCoverage"]))
        fair = ca[0] == ca[1] and cb[0] == cb[1]
        pct = ((va - vb) / abs(vb) * 100) if (fair and va is not None and vb not in (None, 0)) else None
        if not eq(m["changePct"], pct): fails.append((key, code, "changePct", pct, m["changePct"]))
        if m["comparisonLabel"] != f"vs {rlab(*B)}": fails.append((key, code, "comparisonLabel", rlab(*B), m["comparisonLabel"]))
        d = idx(B[0]) - idx(fr); ct = []
        for ms, cut in bks:
            sm = [add(x, d) for x in ms]
            bv, bc, _ = block(vals, sm, reported, kind)
            cut_like = g != "month" and (cut or not calendar_aligned(sm, g))
            ct.append((name(sm, g, cut_like), bv, cut or bc[0] < bc[1]))
        gct = [(p["periodLabel"], p["value"], p["partial"]) for p in m["comparisonTrend"]]
        if len(gct) != len(ct) or any(x[0] != y[0] or not eq(x[1], y[1]) or x[2] != y[2] for x, y in zip(ct, gct)):
            fails.append((key, code, "comparisonTrend", ct, gct))
        checked["pct_shown" if pct is not None else "pct_withheld"] += 1

print("checked:", dict(checked))
print("fails:", len(fails))
for f in fails[:40]: print(" ", f)
json.dump({"checked": checked, "fails": fails}, open(f"{S}/oracle-result.json", "w"), default=str, indent=1)
