#!/usr/bin/env python3
"""Analiza outputs de safesql para TC-158 (visitor_management.sql PRE vs POST).

Uso:
  analyze_vm.py summary <out.json>            -> filas, columnas, fechas del ticket presentes
  analyze_vm.py diff <pre.json> <post.json>   -> added/removed/kept + fechas ticket + dedup
  analyze_vm.py children <post.json> <child1.json> [<child2.json> ...]
      -> completeness: dangling (referenciada por un child, ausente en parent)
         y surplus (en parent, no referenciada por ningun child)
"""
import json
import sys

TICKET_DATES = {"2024-09-26", "2026-07-03", "2026-08-07", "2026-08-20", "2026-08-21"}


def load_rows(path):
    d = json.load(open(path))
    rows = []
    for rs in d.get("recordsets", []):
        rows.extend(rs)
    return rows


def ext_ids(rows):
    return [r.get("Implementation_External_ID__c") for r in rows if r.get("Implementation_External_ID__c") is not None]


def vm_refs(rows):
    """Fechas referenciadas por un child via Auctifera__Visitor_Management__c."""
    out = []
    for r in rows:
        v = r.get("Auctifera__Visitor_Management__c")
        if v:
            out.append(v)
    return out


def cmd_summary(path):
    rows = load_rows(path)
    ids = ext_ids(rows)
    dset = set(ids)
    print(f"file: {path}")
    print(f"rows: {len(rows)}  distinct_external_ids: {len(dset)}  duplicados: {len(ids) - len(dset)}")
    if rows:
        print(f"columns: {sorted(rows[0].keys())}")
    present = sorted(TICKET_DATES & dset)
    absent = sorted(TICKET_DATES - dset)
    print(f"fechas ticket PRESENTES: {present or '(ninguna)'}")
    print(f"fechas ticket AUSENTES:  {absent or '(ninguna)'}")


def cmd_diff(pre_path, post_path):
    pre_rows, post_rows = load_rows(pre_path), load_rows(post_path)
    pre_ids, post_ids = ext_ids(pre_rows), ext_ids(post_rows)
    pre, post = set(pre_ids), set(post_ids)
    added, removed, kept = sorted(post - pre), sorted(pre - post), pre & post
    print(f"PRE : {len(pre_rows)} rows, {len(pre)} fechas distintas (dup: {len(pre_ids)-len(pre)})")
    print(f"POST: {len(post_rows)} rows, {len(post)} fechas distintas (dup: {len(post_ids)-len(post)})")
    print(f"added: {len(added)}  removed: {len(removed)}  kept: {len(kept)}")
    print(f"fechas ticket en added: {sorted(TICKET_DATES & set(added))}")
    print(f"fechas ticket en POST:  {sorted(TICKET_DATES & post)}")
    print(f"fechas ticket en PRE:   {sorted(TICKET_DATES & pre) or '(ninguna - reproduce el reporte)'}")
    print(f"removed dates: {removed}")
    if len(added) <= 60:
        print(f"added dates: {added}")


def cmd_children(post_path, *child_paths):
    post = set(ext_ids(load_rows(post_path)))
    referenced = set()
    for cp in child_paths:
        refs = vm_refs(load_rows(cp))
        print(f"child {cp.split('/')[-1]}: {len(refs)} rows con lookup, {len(set(refs))} fechas distintas")
        referenced |= set(refs)
    dangling = sorted(referenced - post)
    surplus = sorted(post - referenced)
    print(f"parent POST: {len(post)} fechas | referenced (union children): {len(referenced)}")
    print(f"DANGLING (child referencia, parent no tiene): {len(dangling)} {dangling[:20]}")
    print(f"SURPLUS  (parent tiene, ningun child referencia): {len(surplus)} {surplus[:20]}")
    print(f"fechas ticket referenciadas por children: {sorted(TICKET_DATES & referenced)}")


if __name__ == "__main__":
    import os
    here = os.path.dirname(os.path.abspath(__file__))
    cmd = sys.argv[1]
    if cmd == "summary":
        cmd_summary(sys.argv[2])
    elif cmd == "diff":
        cmd_diff(sys.argv[2], sys.argv[3])
    elif cmd == "children":
        cmd_children(*sys.argv[2:])
    elif cmd == "children-auto":
        cmd_children(
            f"{here}/postfix-longisland.json",
            f"{here}/child-program.json",
            f"{here}/child-event.json",
            f"{here}/child-direct.json",
        )
    else:
        sys.exit(f"comando desconocido: {cmd}")
