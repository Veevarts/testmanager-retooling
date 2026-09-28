-- QA TC-182 / IM-1297 · respaldo REAL y restaurable, con datos 100% sinteticos de QA.
-- Se cifra con TDE y un certificado propio de QA, como llegan los respaldos de los clientes.
-- Ninguna fila sale de un cliente: 100 marcadores "QA TC-182 ..." y lastre aleatorio para el tamano.
USE master;
GO
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<clave-maestra-local>';
GO
CREATE CERTIFICATE QaTc182TdeCert
    WITH SUBJECT = 'QA TC-182 IM-1297 synthetic TDE certificate', EXPIRY_DATE = '2027-12-31';
GO
CREATE DATABASE QA_TC182_IM1297;
GO
ALTER DATABASE QA_TC182_IM1297 SET RECOVERY SIMPLE;
GO
USE QA_TC182_IM1297;
GO
CREATE TABLE dbo.qa_marker (
    id INT NOT NULL PRIMARY KEY,
    label NVARCHAR(100) NOT NULL,
    created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
INSERT INTO dbo.qa_marker (id, label)
SELECT TOP (100) n, CONCAT(N'QA TC-182 IM-1297 synthetic row ', n)
FROM (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects) AS x;
CREATE TABLE dbo.qa_ballast (
    id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    payload VARBINARY(8000) NOT NULL
);
GO
SET NOCOUNT ON;
DECLARE @i INT = 0;
WHILE @i < 53
BEGIN
    INSERT INTO dbo.qa_ballast (payload)
    SELECT TOP (1000) CRYPT_GEN_RANDOM(7900)
    FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;
    CHECKPOINT;
    SET @i += 1;
END;
GO
CREATE DATABASE ENCRYPTION KEY
    WITH ALGORITHM = AES_256
    ENCRYPTION BY SERVER CERTIFICATE QaTc182TdeCert;
GO
ALTER DATABASE QA_TC182_IM1297 SET ENCRYPTION ON;
GO
