TR-215 · IM-1312 · harness de QA

qa-tc188-block.tsx
  Dos specs de QA (Q1, Q2) que se anaden al final de una COPIA de
  src/features/csm/components/MyDayTasksTab.test.tsx (reutilizan sus helpers: Host, store, setupUser,
  openSuggestedPanel, getTaskSuggestionPool). Nunca se comitean en el repo del frontend.
    cat MyDayTasksTab.test.tsx qa-tc188-block.tsx > MyDayTasksTab.qa1312.test.tsx
    npx vitest run src/features/csm/components/MyDayTasksTab.qa1312.test.tsx -t "QA TC-188"

mutate-tc188.py
  Aplica las mutaciones BASE, M1-M7 a MyDayTasksTab.tsx, corre la copia anterior y restaura con git checkout.
    python3 mutate-tc188.py <clon-del-frontend> <carpeta-de-salida>
  Necesita la copia MyDayTasksTab.qa1312.test.tsx en el clon.

Recorrido en dev: Playwright con la sesion del perfil del navegador, "View as" de la CSM de prueba, nombres
enmascarados con un MutationObserver instalado por addInitScript, y un registro de peticiones no-GET. Para Accept y
Decline sin escribir se uso page.route('**/*') abortando todo lo que no fuera GET/OPTIONS/HEAD.
