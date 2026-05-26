import {
  BatchExtractionOptions,
  ExtractionParams,
  ExtractionResult,
} from '@data-migration/application/ports/data-source.port';
import { MigrationObject } from '@data-migration/domain/enums/migration-object.enum';
import { TicketingRecord } from '@data-migration/domain/model/ticketing-record.entity';
import {
  TicketingProgramSpecification,
  TicketingProgramSpecificationFactory,
} from '@data-migration/domain/specifications/ticketing-program.specification';
import { ConnectionPool } from 'mssql';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { IObjectExtractor } from '../interfaces/object-extractor.interface';
import { TicketingMapper } from '../mappers/ticketing.mapper';
import { executeQueryAsStream } from '../utils/query-stream.util';

export class TicketingProgramExtractor
  implements IObjectExtractor<TicketingProgramSpecification, TicketingRecord>
{
  readonly objectType = MigrationObject.TICKETING_PROGRAM;
  private readonly mapper = new TicketingMapper();
  private readonly queryFile = 'ticketing_only_program.sql';

  async extract(
    pool: ConnectionPool,
    params: ExtractionParams<TicketingProgramSpecification>,
  ): Promise<ExtractionResult<TicketingRecord>> {
    const specification =
      params.specification ?? TicketingProgramSpecificationFactory.createDefault();
    const query = await this.buildQuery();
    const raw = await this.executeQuery(
      pool,
      query,
      this.mergeFilters(params.additionalFilters, specification),
    );
    const data = raw.map((row) => this.mapper.toDomain(row));

    return {
      objectName: this.objectType,
      objectType: this.objectType,
      data,
      dependencies: [],
      recordCount: data.length,
    };
  }

  async extractInBatches(
    pool: ConnectionPool,
    params: ExtractionParams<TicketingProgramSpecification>,
    options: BatchExtractionOptions<TicketingRecord>,
  ): Promise<void> {
    const specification =
      params.specification ?? TicketingProgramSpecificationFactory.createDefault();
    const query = await this.buildQuery();

    await executeQueryAsStream(
      pool,
      query,
      this.mergeFilters(params.additionalFilters, specification),
      {
        batchSize: options.batchSize,
        mapRow: (row) => this.mapper.toDomain(row),
        onBatch: async (batch) => {
          await options.onBatch({
            objectName: this.objectType,
            objectType: this.objectType,
            data: batch,
            dependencies: [],
            recordCount: batch.length,
          });
        },
      },
    );
  }

  private async buildQuery(): Promise<string> {
    const queryPath = join(__dirname, '..', 'queries', 'ticketing', this.queryFile);
    return readFile(queryPath, 'utf-8');
  }

  private mergeFilters(
    additionalFilters: Record<string, any> | undefined,
    specification: TicketingProgramSpecification,
  ): Record<string, any> {
    const { fromDate, toDate, status } = specification.filters ?? {};

    return {
      ...(additionalFilters ?? {}),
      hasDateFilterFrom: fromDate ? 1 : 0,
      hasDateFilterTo: toDate ? 1 : 0,
      hasStatusFilter: status ? 1 : 0,
      statusFilter: status ?? '',
      dateFilterFrom: fromDate ?? new Date('1900-01-01T00:00:00.000Z'),
      dateFilterTo: toDate ?? new Date('2100-12-31T23:59:59.999Z'),
    };
  }

  private async executeQuery(
    pool: ConnectionPool,
    query: string,
    additionalFilters?: Record<string, any>,
  ): Promise<any[]> {
    const result = await executeQueryAsStream(pool, query, additionalFilters, {
      mapRow: (row) => row,
      collectRows: true,
    });
    return result.rows;
  }
}
