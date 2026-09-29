Arnes de QA de TR-212 (IM-1207 v5). Nada de esto va al repo del producto.

mutate-v4.py <clon del frontend> <carpeta de salida>
    Aplica BASE + 8 mutaciones al adaptador (api/playbookEvaluations.ts) y al pie del log
    (components/PlaybookEvaluationList.tsx), corre los dos ficheros de test del cambio con vitest y
    restaura cada fichero con git checkout. Necesita Node 20 via fnm. No toca dev ni ninguna base.

Las lecturas de la base de dev se hicieron con harness/dq.py de TR-211 (solo SELECT via Data API).
