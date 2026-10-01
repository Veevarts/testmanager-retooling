TR-220 · IM-1314 · arnes de QA

mutate-fe-tc190-v2.py <clon-frontend> <salida>
  Mutaciones R1-R7 de #222 sobre SuggestionPoolModal.tsx; corre MyDayTasksTab.test.tsx y SuggestionPoolModal.test.tsx
  con Node 20 y restaura con git checkout.

Medidas en dev (Playwright, clic real de raton): scrollTop y primera fila en vista de [data-testid="suggestion-pool-body"]
antes y despues de cada vuelta al Task Detail; sin enmascarar y con un enmascarado por MutationObserver que reescribe los
nombres al montarse las filas (reflujo tardio). Traza de eventos de scroll con un listener en captura sobre document.
Un clic sintetico (dispatchEvent) no mueve el foco al detalle y Escape no lo cierra: usar clic real.
