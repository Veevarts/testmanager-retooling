// Crea en DynamoDB Local las 5 tablas EXACTAMENTE como las define el stack sintetizado.
import { DynamoDBClient, CreateTableCommand, ListTablesCommand } from "@aws-sdk/client-dynamodb";
import { readFileSync } from "node:fs";
const tables = JSON.parse(readFileSync(process.argv[2], "utf8"));
const c = new DynamoDBClient({});
for (const t of tables) {
  const gsis = t.GSIs.map((g) => ({ IndexName: g.IndexName, KeySchema: g.KeySchema, Projection: g.Projection }));
  await c.send(new CreateTableCommand({
    TableName: t.TableName, KeySchema: t.KeySchema, AttributeDefinitions: t.AttributeDefinitions,
    BillingMode: "PAY_PER_REQUEST", ...(gsis.length ? { GlobalSecondaryIndexes: gsis } : {}),
  }));
}
console.log((await c.send(new ListTablesCommand({}))).TableNames.join("\n"));
