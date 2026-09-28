ARNES · escenario 12 · TR-207
Chromium aparte con depuracion remota en 127.0.0.1; el usuario inicia sesion en el admin de dev; los
scripts se conectan por CDP y nunca leen cookies ni tokens (las llamadas de admin se hacen con fetch
dentro de la pagina). Orden: setup.mjs (feature + encuesta QA) -> probe.mjs baseline -> recorder.mjs
(red, sin tokens) -> widget.mjs open / score / reason / close -> admin.mjs progress, admin-detail.mjs,
admin-summary.mjs -> widget.mjs open (restore) / company / submit -> shot-masked.mjs (tapa el error) ->
probe.mjs final. El keepalive del cierre no aparece en net.jsonl (el frame ya se desmonta y CDP no lo
ve); se prueba por el estado del servidor: comentario nuevo y saveSequence 4 en el restore.
