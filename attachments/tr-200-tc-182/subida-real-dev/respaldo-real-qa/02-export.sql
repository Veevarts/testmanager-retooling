-- Exporta certificado, clave privada y respaldo, en el formato que pide el formulario de la app.
-- La contrasena de la clave es SINTETICA de QA: protege solo datos sinteticos.
USE master;
GO
BACKUP CERTIFICATE QaTc182TdeCert
    TO FILE = '/var/opt/mssql/data/qa-tc182-real.cer'
    WITH PRIVATE KEY (
        FILE = '/var/opt/mssql/data/qa-tc182-real.pvk',
        ENCRYPTION BY PASSWORD = '<contrasena-sintetica-del-formulario>'
    );
GO
BACKUP DATABASE QA_TC182_IM1297
    TO DISK = '/var/opt/mssql/data/qa-tc182-real.bak'
    WITH INIT, FORMAT, CHECKSUM, NO_COMPRESSION;
GO
