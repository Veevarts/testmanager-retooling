Arnes de QA de IM-1245 (TR-210). Nada de esto va al repo del producto.

fetch_rows.py <account-uuid> <salida.json>
  SELECT de solo lectura de csm_os.product_metrics de una cuenta en la base de dev, via RDS Data API
  con el perfil de AWS SSO. Lee el ARN del cluster de dev del generador del autor (skill
  csm-playbook-qa), que rechaza produccion; el script no contiene ARNs ni credenciales.
oracle.py <dir>
  Recalcula desde esas filas, siguiendo el texto de los AC, lo que la API debe devolver para cada
  combinacion de api-matrix.json y lo compara metrica a metrica. api-matrix.json se obtiene desde el
  navegador con la sesion de dev (el token no sale del navegador); no se publica porque trae el id
  interno de la cuenta.
ui_vs_api.py <tarjetas.json> <api-matrix.json> <clave>
  Compara el texto de las tarjetas de la pestana con la respuesta de la API de la misma combinacion.
qa-im1245-harness.spec.ts
  Jest: ejecuta el WorkspaceService real del arbol donde se copia, con un repositorio falso que
  devuelve las filas dadas y emula la ventana SQL de la version (QA_MODE=pre|post). Se usa para la
  regresion de Overview antes/despues, el mes sin reporte y los rangos desmesurados (N1). Se borra
  del arbol al terminar.
mutate-im1245.py <scratchpad>
  Las 15 mutaciones de scenario-0-unit-tests/mutaciones.txt.
