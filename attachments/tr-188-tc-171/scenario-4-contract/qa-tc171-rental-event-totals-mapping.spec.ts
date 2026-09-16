/**
 * QA TC-171 (IM-1228) — test PROPIO DE QA, temporal. Cubre el camino TS de runtime que el PR 181
 * agrega y que ningun spec del repo ejercita: fila SQL -> RentalEventMapper -> RentalEventRecord ->
 * RentalEventPipeline.buildCsvDescriptor -> columnas del CSV de carga.
 */
import { RentalEventMapper } from './rental-event.mapper';
import { RentalEventPipeline } from '@data-migration/application/pipelines/rental-event.pipeline';

const SUB = 'Auctifera__Rental_Resource_Subtotals2__c';
const TAX = 'Auctifera__Rental_Resource_Taxes3__c';

const baseRow = (extra: Record<string, unknown>) => ({
  Implementation_External_ID__c: '00000000-0000-0000-0000-00000000QA01',
  Name: 'QA TC-171',
  Auctifera__Status__c: 'Paid',
  ...extra,
});

describe('QA TC-171 · totales de recursos del Rental Event: mapper y pipeline', () => {
  const mapper = new RentalEventMapper();
  const pipeline = new RentalEventPipeline();
  const ctx = {} as never;

  it('la cabecera del CSV incluye los dos campos nuevos exactamente una vez', () => {
    const d = pipeline.buildCsvDescriptor([], ctx);
    expect(d.headers.filter((h) => h === SUB)).toHaveLength(1);
    expect(d.headers.filter((h) => h === TAX)).toHaveLength(1);
  });

  it('un valor numerico con decimales llega intacto a la fila del CSV', () => {
    const rec = mapper.toDomain(baseRow({ [SUB]: 1234.56, [TAX]: 98.77 }));
    expect(rec.rentalResourceSubtotals).toBe(1234.56);
    expect(rec.rentalResourceTaxes).toBe(98.77);
    const row = pipeline.buildCsvDescriptor([rec], ctx).rows[0] as Record<string, unknown>;
    expect(row[SUB]).toBe(1234.56);
    expect(row[TAX]).toBe(98.77);
  });

  it('el 0 que emite la query se conserva como 0 y NO se convierte en blanco', () => {
    const rec = mapper.toDomain(baseRow({ [SUB]: 0, [TAX]: 0 }));
    expect(rec.rentalResourceSubtotals).toBe(0);
    expect(rec.rentalResourceTaxes).toBe(0);
    const row = pipeline.buildCsvDescriptor([rec], ctx).rows[0] as Record<string, unknown>;
    expect(row[SUB]).toBe(0);
    expect(row[TAX]).toBe(0);
  });

  it('un DECIMAL que el driver entrega como string se convierte a numero', () => {
    const rec = mapper.toDomain(baseRow({ [SUB]: '1234.56', [TAX]: '0.00' }));
    expect(rec.rentalResourceSubtotals).toBe(1234.56);
    expect(rec.rentalResourceTaxes).toBe(0);
  });

  it('cada clave de la fila tiene su columna en la cabecera (nada se pierde al escribir el CSV)', () => {
    const d = pipeline.buildCsvDescriptor([mapper.toDomain(baseRow({ [SUB]: 1, [TAX]: 2 }))], ctx);
    const row = d.rows[0] as Record<string, unknown>;
    expect(Object.keys(row).filter((k) => !(d.headers as readonly string[]).includes(k))).toEqual([]);
  });

  it('DOCUMENTA el limite: una columna ausente del SQL se mapearia a blanco, no a 0', () => {
    const rec = mapper.toDomain(baseRow({}));
    expect(rec.rentalResourceSubtotals).toBeNull();
    expect(rec.rentalResourceTaxes).toBeNull();
  });
});
