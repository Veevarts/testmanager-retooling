RESPALDO REAL PROPIO DE QA · IM-1297 / TC-182 / TR-200 v2 · 2026-09-28
======================================================================
POR QUE. Para la mitad "y aprovisiona" del AC1 hace falta un respaldo que el entorno pueda
RESTAURAR de verdad. Los .bak de B1-B4 son bytes aleatorios. Reutilizar el de otro workspace
exigia bajar su clave privada y leer su contrasena de Secrets Manager, y eso no se hizo. QA
fabrica el suyo: sin datos de ningun cliente y con credenciales propias de QA.

COMO (SQL Server 2022 Developer en Docker local, desechable)
  01-build.sql            base QA_TC182_IM1297: 100 filas "QA TC-182 IM-1297 synthetic row N"
                          + 53.000 filas de lastre aleatorio (CRYPT_GEN_RANDOM) para el tamano.
                          TDE AES_256 con el certificado QaTc182TdeCert de QA, como llegan
                          los respaldos de los clientes.
  02-export.sql           exporta el certificado, la clave privada (cifrada con la contrasena
                          sintetica que se escribe en el formulario) y el respaldo con CHECKSUM,
                          sin compresion.
  03-restore-control.sql  CONTROL en un SQL Server LIMPIO que solo recibe los tres ficheros y
                          la contrasena, como el aprovisionamiento de la app.

FICHEROS SUBIDOS (db_5)
  qa-tc182-real.bak  446.816.256 B  (54.370 paginas; TDE)
  qa-tc182-real.cer        1.015 B
  qa-tc182-real.pvk        1.788 B

RESULTADO DEL CONTROL (servidor limpio, 2026-09-28 ~21:44 UTC)
  CREATE CERTIFICATE ... FROM FILE ... DECRYPTION BY PASSWORD   OK
  RESTORE FILELISTONLY    QA_TC182_IM1297 (D, 478.150.656 B) · QA_TC182_IM1297_log (L)
  RESTORE DATABASE        54.370 paginas en 1,484 s, CHECKSUM OK
  contenido restaurado    marcadores 100 · lastre 53.000 · "QA TC-182 IM-1297 synthetic row 1"
                          · TDE encryption_state 3
  => El respaldo se restaura con solo esos tres ficheros y la contrasena. Si el entorno no lo
     aprovisiona, el fallo no esta en el respaldo.

Las contrasenas del script se sustituyen por marcadores. La del formulario es sintetica y solo
protege datos sinteticos, pero no se publica igualmente.
