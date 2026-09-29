"""Compara el texto de cada tarjeta de la UI con la respuesta de la API para la misma combinacion."""
import json, re, sys
ui = json.load(open(sys.argv[1])); ui = json.loads(ui) if isinstance(ui, str) else ui
api = json.load(open(sys.argv[2]))[sys.argv[3]]["body"]
def num(s):
    s = s.replace("$", "").replace(",", "").strip()
    m = {"K": 1e3, "M": 1e6}.get(s[-1:], 1)
    return float(s[:-1] if m != 1 else s) * m
def close(disp, val):
    if val is None: return disp in ("—", None)
    x = num(disp); tol = max(abs(val) * 0.0051, 0.51)  # redondeo de 1 decimal en K/M o entero
    return abs(x - val) <= tol
bym = {m["label"]: m for m in api["metrics"]}
bad = 0
for t in ui["all"]:
    parts = [p.strip() for p in t.split("|")]
    name = parts[0]; m = bym[name]
    pct = next((p for p in parts[1:3] if re.fullmatch(r"[+-]?\d+\.\d%", p)), None)
    if m["changePct"] is None:
        ok_pct = pct is None
    else:
        ok_pct = pct is not None and abs(float(pct[:-1]) - m["changePct"]) <= 0.051
    if "Only for a single month" in t:
        ok_val = m["latestValue"] is None and m["aggregation"] == "unclassified"
        ok_prev = True
    else:
        i = next((k for k, p in enumerate(parts) if p == api["period"]["label"] or p.startswith(api["period"]["label"] + " ·")), None)
        val = parts[i - 1] if i else None
        ok_val = val is not None and close(val, m["latestValue"])
        j = next((k for k, p in enumerate(parts) if p.startswith("vs ")), None)
        ok_prev = (j is None and m["previousValue"] is None) or (j is not None and close(parts[j + 1], m["previousValue"]))
    if not (ok_pct and ok_val and ok_prev):
        bad += 1; print("MISMATCH", name, "|", t, "| api:", m["latestValue"], m["previousValue"], m["changePct"])
print(f"tarjetas={len(ui['all'])} discrepancias={bad}")
