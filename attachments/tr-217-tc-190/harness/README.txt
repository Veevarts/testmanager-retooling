TR-217 · IM-1314 · harness de QA

mutate-fe-tc190.py <clon-frontend> <salida>
  Mutaciones G1-G7 sobre main (MyDayTasksTab.tsx y TaskToastBanner.tsx). Corre MyDayTasksTab.test.tsx y
  SuggestionPoolModal.test.tsx con Node 20 (fnm exec --using=20) y restaura con git checkout.

Medida del scroll en dev: scrollTop de [data-testid="suggestion-pool-body"] antes y despues de abrir y cerrar el Task
Detail; clic con dispatchEvent('click') para que Playwright no desplace la fila antes de pulsar; repetido con
emulateMedia({ reducedMotion: 'reduce' }) y con la ventana a 1920x1080.

Carrera del escenario 14: page.context().route('**/csm/tasks/**') retrasa 5 s el envio del POST .../accept y deja pasar
todo lo demas; se cierra el pool antes de que salga la peticion.
