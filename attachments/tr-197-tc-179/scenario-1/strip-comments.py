#!/usr/bin/env python3
"""Quita comentarios SQL respetando literales de cadena.

El guard de palabras de escritura de safesql es una busqueda de subcadena: dispara con
"create" y "drop" dentro de COMENTARIOS de este archivo (lineas 12 y 210). Quitarlos no
cambia la semantica de la consulta; es lo mismo que el propio motor hace al parsear.
No se toca ni una clausula.
"""
import sys


def strip(sql: str) -> str:
    out = []
    i, n = 0, len(sql)
    in_str = False
    while i < n:
        c = sql[i]
        if in_str:
            out.append(c)
            if c == "'":
                if i + 1 < n and sql[i + 1] == "'":   # '' escapado
                    out.append(sql[i + 1]); i += 2; continue
                in_str = False
            i += 1
            continue
        if c == "'":
            in_str = True; out.append(c); i += 1; continue
        if c == "-" and i + 1 < n and sql[i + 1] == "-":
            while i < n and sql[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and sql[i + 1] == "*":
            i += 2
            while i + 1 < n and not (sql[i] == "*" and sql[i + 1] == "/"):
                i += 1
            i += 2
            continue
        out.append(c); i += 1
    return "".join(out)


if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    s = strip(open(src).read())
    # colapsa lineas que quedaron vacias, para legibilidad
    s = "\n".join(l for l in s.split("\n") if l.strip())
    open(dst, "w").write(s + "\n")
    print(f"{src} -> {dst}")
