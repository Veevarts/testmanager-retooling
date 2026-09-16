"""Parser minimo de scripts T-SQL de MigrationToolETL: DECLARE + WITH cte AS (...), ... + SELECT final.
Respeta literales '...' y quita comentarios, para no romperse con parentesis dentro de strings."""
import re

def strip_comments(sql):
    out, i, n, in_str = [], 0, len(sql), False
    while i < n:
        c = sql[i]
        if in_str:
            out.append(c)
            if c == "'":
                if i + 1 < n and sql[i+1] == "'":
                    out.append("'"); i += 2; continue
                in_str = False
            i += 1; continue
        if c == "'":
            in_str = True; out.append(c); i += 1; continue
        if sql.startswith('--', i):
            j = sql.find('\n', i); i = n if j < 0 else j; continue
        if sql.startswith('/*', i):
            j = sql.find('*/', i + 2); i = n if j < 0 else j + 2; continue
        out.append(c); i += 1
    return ''.join(out)

def match_paren(s, i):
    """s[i] == '(' ; devuelve el indice del ')' que lo cierra."""
    depth, in_str, n = 0, False, len(s)
    while i < n:
        c = s[i]
        if in_str:
            if c == "'":
                if i + 1 < n and s[i+1] == "'": i += 2; continue
                in_str = False
        elif c == "'": in_str = True
        elif c == '(': depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0: return i
        i += 1
    raise ValueError('parentesis sin cerrar')

def split_script(sql):
    s = strip_comments(sql)
    m = re.search(r'(?<=;)\s*WITH\s+(?=[A-Za-z_][A-Za-z0-9_]*\s+AS\s*\()', s, re.I)
    if not m:
        decl_end = 0
        for d in re.finditer(r'\bDECLARE\b[^;]*;', s, re.I): decl_end = d.end()
        return s[:decl_end].strip(), [], s[decl_end:].strip().rstrip(';').strip()
    preamble = s[:m.start()]
    i, ctes = m.end(), []
    while True:
        mm = re.compile(r'\s*([A-Za-z_][A-Za-z0-9_]*)\s+AS\s*\(', re.I).match(s, i)
        if not mm: raise ValueError('CTE esperado en %d: %r' % (i, s[i:i+60]))
        open_i = mm.end() - 1
        close_i = match_paren(s, open_i)
        ctes.append((mm.group(1), s[open_i+1:close_i]))
        j = close_i + 1
        while j < len(s) and s[j].isspace(): j += 1
        if j < len(s) and s[j] == ',':
            i = j + 1; continue
        final = s[j:].strip().rstrip(';').strip()
        return preamble.strip(), ctes, final

def rename(text, mapping):
    for old, new in mapping.items():
        text = re.sub(r'\b%s\b' % re.escape(old), new, text)
    return text

def _scan_depth0(s, pattern, start=0):
    """primer match de pattern (regex) a profundidad 0 de parentesis y fuera de strings"""
    rx = re.compile(pattern, re.I)
    depth, in_str, i, n = 0, False, start, len(s)
    while i < n:
        c = s[i]
        if in_str:
            if c == "'":
                if i + 1 < n and s[i+1] == "'": i += 2; continue
                in_str = False
            i += 1; continue
        if c == "'": in_str = True; i += 1; continue
        if c == '(': depth += 1
        elif c == ')': depth -= 1
        elif depth == 0:
            m = rx.match(s, i)
            if m and (i == 0 or not (s[i-1].isalnum() or s[i-1] == '_')): return m
        i += 1
    return None

def split_union_branches(final):
    """parte el SELECT final en ramas por UNION ALL a profundidad 0"""
    branches, start = [], 0
    while True:
        m = _scan_depth0(final, r'UNION\s+ALL\b', start)
        seg = final[start:] if not m else final[start:m.start()]
        t = seg.strip()
        while t.startswith('(') and match_paren(t, 0) == len(t) - 1:   # rama entre parentesis
            t = t[1:-1].strip()
        branches.append(t)
        if not m: return branches
        start = m.end()

def projection_expr(branch, alias):
    """texto de la expresion proyectada como <alias> en una rama SELECT ... FROM"""
    frm = _scan_depth0(branch, r'FROM\b')
    proj = branch[:frm.start()]
    m = re.search(r'\bAS\s+' + re.escape(alias) + r'\b', proj)
    if not m:
        # columna pasada tal cual desde una CTE: SELECT col, col2 FROM cte
        if re.search(r'(^|[\s,])' + re.escape(alias) + r'\s*(,|$)', re.sub(r'^\s*SELECT\b', '', proj.strip(), flags=re.I)):
            return alias
        return None
    # retrocede hasta la coma de profundidad 0 anterior (o el SELECT)
    depth, in_str, i = 0, False, m.start() - 1
    while i >= 0:
        c = proj[i]
        if c == "'": in_str = not in_str
        elif not in_str:
            if c == ')': depth += 1
            elif c == '(': depth -= 1
            elif c == ',' and depth == 0: break
        i -= 1
    head = proj[i+1:m.start()].strip()
    head = re.sub(r'^\s*SELECT\b(\s+DISTINCT\b)?', '', head, flags=re.I).strip()
    return head

def lean_branch(branch, keep):
    """reemplaza la lista de proyeccion de una rama por [(expr_o_None, alias)] conservando FROM... intacto"""
    frm = _scan_depth0(branch, r'FROM\b')
    sel = re.match(r'\s*SELECT\b(\s+DISTINCT\b)?', branch, re.I)
    cols = []
    for expr, alias in keep:
        e = expr if expr is not None else projection_expr(branch, alias)
        if e is None: raise ValueError('no encuentro la proyeccion de ' + alias)
        cols.append('%s AS %s' % (e, alias))
    return sel.group(0) + ' ' + ',\n  '.join(cols) + '\n' + branch[frm.start():]
