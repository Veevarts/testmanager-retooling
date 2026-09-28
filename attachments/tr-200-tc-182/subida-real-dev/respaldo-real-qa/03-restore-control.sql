-- CONTROL: un SQL Server limpio que solo recibe los tres ficheros y la contrasena del formulario.
-- Si esto restaura, un fallo del aprovisionamiento en dev no puede achacarse al respaldo.
USE master;
GO
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<clave-maestra-local>';
GO
CREATE CERTIFICATE QaTc182Restored
    FROM FILE = '/tmp/in/qa-tc182-real.cer'
    WITH PRIVATE KEY (
        FILE = '/tmp/in/qa-tc182-real.pvk',
        DECRYPTION BY PASSWORD = '<contrasena-sintetica-del-formulario>'
    );
GO
RESTORE FILELISTONLY FROM DISK = '/tmp/in/qa-tc182-real.bak';
GO
RESTORE DATABASE QA_TC182_Control
    FROM DISK = '/tmp/in/qa-tc182-real.bak'
    WITH MOVE 'QA_TC182_IM1297' TO '/var/opt/mssql/data/qa_control.mdf',
         MOVE 'QA_TC182_IM1297_log' TO '/var/opt/mssql/data/qa_control_log.ldf',
         CHECKSUM, STATS = 50;
GO
SET NOCOUNT ON;
SELECT (SELECT COUNT(*) FROM QA_TC182_Control.dbo.qa_marker) AS marcadores,
       (SELECT COUNT(*) FROM QA_TC182_Control.dbo.qa_ballast) AS lastre,
       (SELECT MIN(label) FROM QA_TC182_Control.dbo.qa_marker) AS primer_marcador,
       (SELECT encryption_state FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID('QA_TC182_Control')) AS estado_tde;
GO
