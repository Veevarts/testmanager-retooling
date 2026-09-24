/**
 * QA · IM-1297 — reproduccion del defecto, ejecutable en las DOS versiones.
 *
 * El AC1 pide una subida mas larga que S3_PRESIGN_EXPIRATION. No se puede
 * forzar aqui: el valor vive en SSM (/<env>/migration-app-backend/
 * s3-presign-expiration), no hay credenciales de AWS en esta maquina, y
 * bajarlo exige acuerdo con el dueno del entorno. Asi que en vez de esperar
 * una hora se modela lo unico que importa del reloj: una URL prefirmada
 * CADUCA, y S3 contesta 403 "Request has expired" a quien la use tarde.
 *
 * Cada URL lleva su instante de firma. El S3 falso rechaza la que se firmo
 * hace mas de EXPIRY. La subida del .bak por multipart hace avanzar el reloj
 * por encima de ese limite, igual que las 3h34m del incidente.
 *
 * El MISMO fichero se ejecuta contra la version de antes del arreglo y contra
 * la de despues. Ese es el punto: si solo pasara en la nueva, no probaria que
 * reproduce el defecto.
 */
import { beforeEach, afterEach, describe, expect, it, vi } from "vitest";
import { uploadBackupFiles } from "@/features/migration/api/backupUploads";

vi.mock("@/constants/upload", () => ({
  MULTIPART_CHUNK_SIZE_BYTES: 4,
  MULTIPART_THRESHOLD_BYTES: 8,
}));

const EXPIRY = 3600;          // segundos, el valor de produccion
const PART_SECONDS = 5000;    // cada parte del .bak tarda; 3 partes = 4h10m

/** Reloj virtual. Nadie espera: se avanza. */
const clock = { now: 0 };
const mint = (label: string) => `https://s3.test/${label}?exp=${clock.now}`;
const mintedAt = (url: string) => Number(new URL(url).searchParams.get("exp"));

vi.mock("@/features/migration/api/backups", () => {
  class SignBackupUploadUrlError extends Error {
    status: number;
    constructor(message: string, status: number) {
      super(message);
      this.name = "SignBackupUploadUrlError";
      this.status = status;
    }
  }
  return {
    SignBackupUploadUrlError,
    // La ruta nueva: firma AHORA, con el reloj donde este.
    signBackupUploadUrl: vi.fn(async (_c: string, _b: string, p: { key: string }) => ({
      key: p.key,
      url: mint(`fresh/${p.key}`),
    })),
    initMultipartUpload: vi.fn(async () => ({
      uploadId: "upload-1",
      partCount: 3,
      partUrls: [],
    })),
    // Las partes YA se firmaban bajo demanda antes del arreglo: por eso el
    // .bak nunca fue el problema.
    signMultipartUploadPart: vi.fn(async (_c: string, _b: string, p: { partNumber: number }) => ({
      partNumber: p.partNumber,
      url: mint(`part-${p.partNumber}`),
    })),
    completeMultipartUpload: vi.fn(async () => undefined),
    abortMultipartUpload: vi.fn(async () => undefined),
    getMultipartUploadStatus: vi.fn(async () => null),
  };
});

const sized = (name: string, size: number) =>
  new File(["a".repeat(size)], name, { type: "application/octet-stream" });

const backupFiles = {
  BACKUP: { path: "client-1/backups/backup-1/backup.bak" },
  CERTIFICATE: { path: "client-1/backups/backup-1/certificate.cer" },
  KEY: { path: "client-1/backups/backup-1/key.pvk" },
};

/** El S3 falso: caduca las URLs viejas y el .bak consume tiempo real. */
const fakeS3 = vi.fn(async (url: string | URL) => {
  const href = String(url);
  if (clock.now - mintedAt(href) > EXPIRY) {
    return new Response(
      "<Error><Code>AccessDenied</Code><Message>Request has expired</Message></Error>",
      { status: 403, headers: { "x-amz-request-id": "SIMULADO" } },
    );
  }
  if (href.includes("part-")) clock.now += PART_SECONDS;   // subir el .bak tarda
  return new Response(null, { status: 200, headers: { ETag: '"etag"' } });
});

describe("IM-1297 · el certificado detras de una subida larga", () => {
  let creationLinks: Record<string, string>;

  beforeEach(() => {
    clock.now = 0;
    // Los enlaces de creacion se firman al crear el respaldo: t = 0.
    creationLinks = {
      BACKUP: mint("creation-backup"),
      CERTIFICATE: mint("creation-cert"),
      KEY: mint("creation-key"),
    };
    vi.stubGlobal("fetch", fakeS3);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.clearAllMocks();
  });

  it("sube un .bak que tarda mas que la vida de la URL, y termina con los tres archivos", async () => {
    const result = await uploadBackupFiles(
      creationLinks as never,
      {
        BACKUP: sized("backup.bak", 12),        // 3 partes -> multipart
        CERTIFICATE: sized("certificate.cer", 3),
        KEY: sized("key.pvk", 3),
      },
      { clientId: "client-1", backupId: "backup-1", backupFiles } as never,
    ).then(
      () => ({ ok: true }) as const,
      (error: { diagnostics?: Record<string, unknown>; message?: string }) =>
        ({ ok: false, d: error.diagnostics ?? { errorMessage: error.message } }) as const,
    );

    // Cuanto duro la subida del .bak, para que conste que excede la caducidad.
    expect(clock.now).toBeGreaterThan(EXPIRY);

    if (!result.ok) {
      // Esto es el defecto: deja escrito EXACTAMENTE como se manifiesta.
      console.log("DEFECTO REPRODUCIDO ->", JSON.stringify(result.d));
    }
    expect(result).toEqual({ ok: true });
  });

  it("el caso inverso: un .bak PEQUENO por PUT unico detras de un certificado lento", async () => {
    // El certificado tarda; despues el .bak va por PUT unico y hereda el
    // problema al reves. Es el R4 del caso de prueba.
    const slowS3 = vi.fn(async (url: string | URL) => {
      const href = String(url);
      if (clock.now - mintedAt(href) > EXPIRY) {
        return new Response("<Error><Code>AccessDenied</Code><Message>Request has expired</Message></Error>",
          { status: 403 });
      }
      if (href.includes("cert")) clock.now += EXPIRY * 2;   // el certificado tarda 2h
      return new Response(null, { status: 200 });
    });
    vi.stubGlobal("fetch", slowS3);

    const result = await uploadBackupFiles(
      creationLinks as never,
      {
        BACKUP: sized("backup.bak", 4),          // por debajo del umbral -> PUT unico
        CERTIFICATE: sized("certificate.cer", 3),
      },
      { clientId: "client-1", backupId: "backup-1", backupFiles } as never,
    ).then(
      () => ({ ok: true }) as const,
      (error: { diagnostics?: Record<string, unknown>; message?: string }) =>
        ({ ok: false, d: error.diagnostics ?? { errorMessage: error.message } }) as const,
    );

    if (!result.ok) console.log("DEFECTO REPRODUCIDO (inverso) ->", JSON.stringify(result.d));
    expect(result).toEqual({ ok: true });
  });
});
