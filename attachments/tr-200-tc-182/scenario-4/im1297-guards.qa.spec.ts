/**
 * QA · IM-1297 — se puede sortear la guarda cambiando SOLO la clave del cuerpo?
 *
 * El autor probo cuatro claves ajenas: otro respaldo, otro cliente, `../../` y
 * un archivo no declarado. Aqui van las que no probo. La guarda compara por
 * igualdad exacta contra las rutas declaradas del respaldo, asi que la
 * pregunta real es si algo mas abajo normaliza la clave y vuelve a abrir lo
 * que la igualdad cerro: mayusculas, barras dobles, codificacion porcentual,
 * espacios al borde, sufijos y un byte nulo.
 *
 * Todas son claves DISTINTAS para S3, asi que todas deben ser rechazadas.
 * El control positivo es obligatorio: si la clave legitima tampoco firmara,
 * el rechazo de las demas no probaria nada.
 */
import { BackupsRepository } from '@/backups/application/ports/backups.repository.port';
import { SignBackupUploadUrlUseCase } from '@/backups/application/use-cases/sign-backup-upload-url.use-case';
import { BackupStatus } from '@/backups/domain/enums/backup-status.enum';
import { UploadStatus } from '@/backups/domain/enums/upload-status.enum';
import { Backup } from '@/backups/domain/model/backup.entity';
import { PresignS3UseCase } from '@/shared/application/use-cases/presign-s3.use-case';
import { BadRequestException } from '@nestjs/common';

describe('QA IM-1297 · sorteo de la guarda de clave', () => {
    const findById = jest.fn();
    const getPresignedPutUrl = jest.fn();
    const repo = { findById } as unknown as jest.Mocked<BackupsRepository>;
    const presigner = { getPresignedPutUrl } as unknown as jest.Mocked<PresignS3UseCase>;
    const useCase = new SignBackupUploadUrlUseCase(repo, presigner);

    const base = 'client-1/backups/backup-1/';
    const LEGITIMA = `${base}certificate.cer`;

    beforeEach(() => {
        jest.clearAllMocks();
        findById.mockResolvedValue(
            new Backup(
                'backup-1', 'client-1', 'db_de_prueba',
                BackupStatus.PENDING, UploadStatus.PENDING,
                new Date('2026-09-23T14:31:35.000Z'), 'encrypted',
                {
                    BACKUP: { path: `${base}backup.bak` },
                    CERTIFICATE: { path: LEGITIMA },
                    KEY: { path: `${base}key.pvk` },
                },
            ),
        );
        getPresignedPutUrl.mockResolvedValue('https://example.com/fresh-put');
    });

    // Control positivo: la clave buena SI firma. Sin esto lo de abajo no dice nada.
    it('CONTROL · la clave declarada del respaldo si obtiene su URL', async () => {
        await expect(
            useCase.execute({ clientId: 'client-1', backupId: 'backup-1', key: LEGITIMA }),
        ).resolves.toMatchObject({ key: LEGITIMA });
        expect(getPresignedPutUrl).toHaveBeenCalledTimes(1);
    });

    it.each([
        ['mayusculas en el nombre',        `${base}CERTIFICATE.CER`],
        ['mayusculas en el prefijo',       `CLIENT-1/backups/backup-1/certificate.cer`],
        ['barra doble',                    `client-1/backups/backup-1//certificate.cer`],
        ['segmento punto',                 `client-1/backups/./backup-1/certificate.cer`],
        ['travesia codificada',            `${base}%2e%2e%2fcertificate.cer`],
        ['espacio al final',               `${LEGITIMA} `],
        ['espacio al principio',           ` ${LEGITIMA}`],
        ['sufijo pegado',                  `${LEGITIMA}.evil`],
        ['cadena de consulta pegada',      `${LEGITIMA}?x=1`],
        ['byte nulo',                      `${LEGITIMA}\0.evil`],
        ['barra inicial absoluta',         `/${LEGITIMA}`],
        ['prefijo del bucket delante',     `veevart-client-backups/${LEGITIMA}`],
        ['clave vacia',                    ''],
    ])('rechaza %s y no firma nada', async (_etiqueta, key) => {
        await expect(
            useCase.execute({ clientId: 'client-1', backupId: 'backup-1', key }),
        ).rejects.toBeInstanceOf(BadRequestException);
        expect(getPresignedPutUrl).not.toHaveBeenCalled();
    });

    // El respaldo se busca por (clientId, backupId). Si el repositorio acota
    // por cliente, pedir el respaldo de otro cliente no encuentra nada.
    it('un respaldo de otro cliente no se resuelve, y el rechazo es 400 y no 404', async () => {
        findById.mockResolvedValue(null);
        await expect(
            useCase.execute({ clientId: 'client-2', backupId: 'backup-1', key: LEGITIMA }),
        ).rejects.toBeInstanceOf(BadRequestException);
        expect(getPresignedPutUrl).not.toHaveBeenCalled();
    });
});
