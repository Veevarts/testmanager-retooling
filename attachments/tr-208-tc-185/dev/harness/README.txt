iframe-r5.mjs: un solo proceso Playwright (Chromium headless, perfil persistente de QA). Entra en nps_03
por el frontdoor de sf (la URL no se imprime), replica la secuencia del LWC npsWidget, contesta,
provoca el conflicto con el borrador activo, pulsa Continue here y envia. Guarda estado y red
(pasos.jsonl, net.jsonl) sin tokens. intento-1-*: primer intento, que abrio sin token (el borrador de
TR-207 quedo sin token al borrarse el perfil anterior) y se corto porque Submit estaba deshabilitado.
