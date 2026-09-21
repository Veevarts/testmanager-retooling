import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import { after, before, beforeEach, describe, it } from "node:test";
import { DynamoDBDocumentClient, GetCommand, QueryCommand, ScanCommand } from "@aws-sdk/lib-dynamodb";
import express, { type Router } from "express";
import type {
  Feature,
  JoinedResponse,
  Organization,
  ResponseAction,
  ResponseFilters,
  StoreDuplicateTarget,
  Survey,
  SurveyEvent,
  SurveyEventType,
  SurveyResponse,
} from "../data/types.js";
import { StoreConflictError, StoreDuplicateError } from "../data/types.js";
import { DynamoSurveyStore, setStoreForTesting, store as productionStore, type SurveyStore } from "../data/dynamodbStore.js";
import { featuresAdminRouter, featuresPublicRouter } from "./features.js";
import { surveysAdminRouter, surveysPublicRouter } from "./surveys.js";
import { responsesAdminRouter, responsesPublicRouter } from "./responses.js";
import { settingsRouter } from "./settings.js";
import { integrationsSalesforceRouter } from "./integrationsSalesforce.js";
import { organizationsRouter } from "./organizations.js";
import { analyticsRouter } from "./analytics.js";
import { resetSalesforceTokenCacheForTests } from "../lib/salesforce.js";
import type { RespondentEngagementSummary } from "../lib/respondentEngagement.js";

class MemoryStore {
  features: Feature[] = [];
  surveys: Survey[] = [];
  responses: SurveyResponse[] = [];
  actions: ResponseAction[] = [];
  events: SurveyEvent[] = [];
  organizations: Organization[] = [];
  settings = new Map<string, string | null>();
  counters = new Map<string, number>();
  responseActionFailureIds = new Set<number>();
  responseActionConflictIds = new Set<number>();
  surveyEligibilityHistoryReads = 0;

  reset() {
    this.features = [];
    this.surveys = [];
    this.responses = [];
    this.actions = [];
    this.events = [];
    this.organizations = [];
    this.settings.clear();
    this.counters.clear();
    this.responseActionFailureIds.clear();
    this.responseActionConflictIds.clear();
    this.surveyEligibilityHistoryReads = 0;
  }

  async listFeatures() {
    return [...this.features].sort((a, b) => a.id - b.id);
  }

  async getFeatureById(id: number) {
    return this.features.find((feature) => feature.id === id) ?? null;
  }

  async getFeatureBySlug(slug: string) {
    return this.features.find((feature) => feature.slug === slug) ?? null;
  }

  async createFeature(input: Omit<Feature, "id" | "createdAt">) {
    if (await this.getFeatureBySlug(input.slug)) throw duplicate("featureSlug", "Slug already exists");
    const feature: Feature = { ...input, id: this.nextId("features"), createdAt: new Date().toISOString() };
    this.features.push(feature);
    return feature;
  }

  async updateFeature(id: number, update: Partial<Omit<Feature, "id" | "createdAt">>) {
    const existing = await this.getFeatureById(id);
    if (!existing) return null;
    if (update.slug && update.slug !== existing.slug && (await this.getFeatureBySlug(update.slug))) {
      throw duplicate("featureSlug", "Slug already exists");
    }
    Object.assign(existing, update);
    return existing;
  }

  async deleteFeature(id: number) {
    const before = this.features.length;
    this.features = this.features.filter((feature) => feature.id !== id);
    this.surveys = this.surveys.filter((survey) => survey.featureId !== id);
    this.responses = this.responses.filter((response) => response.featureId !== id);
    return this.features.length !== before;
  }

  async listSurveys() {
    return [...this.surveys].sort((a, b) => a.id - b.id);
  }

  async getSurveyById(id: number) {
    return this.surveys.find((survey) => survey.id === id) ?? null;
  }

  async listSurveysByFeatureId(featureId: number, activeOnly = true) {
    return this.surveys
      .filter((survey) => survey.featureId === featureId && (!activeOnly || survey.active))
      .sort((a, b) => a.id - b.id);
  }

  async listActiveGeneralSurveys(organizationKey?: string | null) {
    const normalizedOrganizationKey = organizationKey?.trim().toLowerCase();
    return this.surveys
      .filter((survey) => survey.active && survey.isGeneralSurvey)
      .filter((survey) => !normalizedOrganizationKey || !survey.generalClientOrgId || survey.generalClientOrgId === normalizedOrganizationKey)
      .sort((a, b) => a.id - b.id);
  }

  async createSurvey(input: Omit<Survey, "id" | "createdAt">) {
    const survey: Survey = { ...input, id: this.nextId("surveys"), createdAt: new Date().toISOString() };
    this.surveys.push(survey);
    return survey;
  }

  async updateSurvey(id: number, update: Partial<Omit<Survey, "id" | "createdAt">>) {
    const existing = await this.getSurveyById(id);
    if (!existing) return null;
    Object.assign(existing, update);
    return existing;
  }

  async deleteSurvey(id: number) {
    const before = this.surveys.length;
    this.surveys = this.surveys.filter((survey) => survey.id !== id);
    this.responses = this.responses.filter((response) => response.surveyId !== id);
    this.events = this.events.filter((event) => event.surveyId !== id);
    return this.surveys.length !== before;
  }

  async createResponse(input: Omit<SurveyResponse, "id" | "createdAt">) {
    const response: SurveyResponse = { ...input, id: this.nextId("responses"), createdAt: new Date().toISOString() };
    this.responses.push(response);
    return response;
  }

  async getResponseById(id: number) {
    return this.responses.find((response) => response.id === id) ?? null;
  }

  async listResponses(filters: ResponseFilters = {}) {
    return this.responses.filter((response) => matchesResponseFilters(response, filters)).sort((a, b) => a.id - b.id);
  }

  async listJoinedResponses(filters: ResponseFilters = {}) {
    const responses = await this.listResponses(filters);
    return responses.flatMap((response): JoinedResponse[] => {
      const feature = this.features.find((row) => row.id === response.featureId);
      const survey = this.surveys.find((row) => row.id === response.surveyId);
      return feature && survey ? [{ response, feature, survey }] : [];
    });
  }

  async updateResponse(id: number, update: Partial<Omit<SurveyResponse, "id" | "createdAt">>) {
    const existing = await this.getResponseById(id);
    if (!existing) return null;
    Object.assign(existing, update);
    return existing;
  }

  async updateResponseWithAction(
    existing: SurveyResponse,
    update: Partial<Omit<SurveyResponse, "id" | "createdAt">>,
    actionInput: Omit<ResponseAction, "id" | "createdAt">
  ) {
    if (this.responseActionFailureIds.has(existing.id)) throw new Error("Simulated response action failure");
    if (this.responseActionConflictIds.has(existing.id)) throw new StoreConflictError("Response was updated by another admin");
    const updated = { ...existing, ...update };
    const action: ResponseAction = {
      ...actionInput,
      id: this.nextId("responseActions"),
      createdAt: new Date().toISOString(),
    };
    const responseIndex = this.responses.findIndex((response) => response.id === existing.id);
    if (responseIndex < 0) throw new Error("Response not found");
    this.responses[responseIndex] = updated;
    this.actions.push(action);
    return updated;
  }

  async deleteResponse(id: number) {
    this.responses = this.responses.filter((response) => response.id !== id);
    this.actions = this.actions.filter((action) => action.responseId !== id);
  }

  async listDistinctClientOrgIds() {
    return [...new Set(this.responses.map((response) => response.clientOrgId).filter((id): id is string => Boolean(id)))].sort();
  }

  async listResponseActions(responseId: number) {
    return this.actions.filter((action) => action.responseId === responseId).sort((a, b) => b.id - a.id);
  }

  async createResponseAction(input: Omit<ResponseAction, "id" | "createdAt">) {
    const action: ResponseAction = { ...input, id: this.nextId("responseActions"), createdAt: new Date().toISOString() };
    this.actions.push(action);
    return action;
  }

  async createEvent(input: Omit<SurveyEvent, "id" | "createdAt">) {
    const event: SurveyEvent = { ...input, id: this.nextId("surveyEvents"), createdAt: new Date().toISOString() };
    this.events.push(event);
    return event;
  }

  async listEvents(input: { surveyId?: number; surveyIds?: number[]; respondentId?: string; clientOrgId?: string | null; type?: SurveyEventType; from?: string; to?: string } = {}) {
    const surveyIds = input.surveyIds ? new Set(input.surveyIds) : null;
    return this.events.filter((event) => {
      if (input.surveyId != null && event.surveyId !== input.surveyId) return false;
      if (surveyIds && !surveyIds.has(event.surveyId)) return false;
      if (input.respondentId && event.respondentId !== input.respondentId) return false;
      if (input.clientOrgId !== undefined && event.clientOrgId !== input.clientOrgId) return false;
      if (input.type && event.type !== input.type) return false;
      if (input.from && event.createdAt < input.from) return false;
      if (input.to && event.createdAt > input.to) return false;
      return true;
    });
  }

  async countEvents(input: Parameters<MemoryStore["listEvents"]>[0] = {}) {
    if (input.surveyId != null) this.surveyEligibilityHistoryReads += 1;
    return (await this.listEvents(input)).length;
  }

  async deleteEvents(input: Parameters<MemoryStore["listEvents"]>[0] = {}) {
    const matches = new Set((await this.listEvents(input)).map((event) => event.id));
    this.events = this.events.filter((event) => !matches.has(event.id));
    return matches.size;
  }

  async countResponses(filters: ResponseFilters = {}) {
    this.surveyEligibilityHistoryReads += 1;
    return (await this.listResponses(filters)).length;
  }

  async getLastResponse(filters: ResponseFilters = {}) {
    this.surveyEligibilityHistoryReads += 1;
    return (await this.listResponses(filters)).sort((a, b) => b.id - a.id)[0] ?? null;
  }

  async listOrganizations() {
    return [...this.organizations].sort((a, b) => a.name.localeCompare(b.name));
  }

  async getOrganizationById(id: number) {
    return this.organizations.find((organization) => organization.id === id) ?? null;
  }

  async getOrganizationBySalesforceOrgId(salesforceOrgId: string) {
    return this.organizations.find((organization) => organization.salesforceOrgId === salesforceOrgId) ?? null;
  }

  async hasActiveOrganization(input: { salesforceOrgId?: string | null; subdomain?: string | null }) {
    return this.organizations.some((organization) => {
      if (!organization.active) return false;
      return Boolean(
        (input.salesforceOrgId && organization.salesforceOrgId === input.salesforceOrgId) ||
          (input.subdomain && organization.subdomain === input.subdomain)
      );
    });
  }

  async createOrganization(input: Omit<Organization, "id" | "createdAt">) {
    this.assertOrganizationUnique(input);
    const organization: Organization = { ...input, id: this.nextId("organizations"), createdAt: new Date().toISOString() };
    this.organizations.push(organization);
    return organization;
  }

  async updateOrganization(id: number, update: Partial<Omit<Organization, "id" | "createdAt">>) {
    const existing = await this.getOrganizationById(id);
    if (!existing) return null;
    this.assertOrganizationUnique({ ...existing, ...update }, id);
    Object.assign(existing, update);
    return existing;
  }

  async deleteOrganization(id: number) {
    this.organizations = this.organizations.filter((organization) => organization.id !== id);
  }

  async getSetting(key: string) {
    return this.settings.get(key) ?? null;
  }

  async setSetting(key: string, value: string) {
    this.settings.set(key, value);
  }

  private assertOrganizationUnique(input: Pick<Organization, "subdomain" | "salesforceOrgId" | "salesforceAccountId">, exceptId?: number) {
    const conflict = this.organizations.find((organization) => {
      if (organization.id === exceptId) return false;
      return Boolean(
        (input.subdomain && organization.subdomain === input.subdomain) ||
          (input.salesforceOrgId && organization.salesforceOrgId === input.salesforceOrgId) ||
          (input.salesforceAccountId && organization.salesforceAccountId === input.salesforceAccountId)
      );
    });
    if (conflict) throw duplicate("organization", "Organization already exists");
  }

  private nextId(name: string) {
    const next = (this.counters.get(name) ?? 0) + 1;
    this.counters.set(name, next);
    return next;
  }
}

function duplicate(target: StoreDuplicateTarget, message: string): StoreDuplicateError {
  return new StoreDuplicateError(target, message);
}

function matchesResponseFilters(response: SurveyResponse, filters: ResponseFilters): boolean {
  if (filters.featureId != null && response.featureId !== filters.featureId) return false;
  if (filters.surveyId != null && response.surveyId !== filters.surveyId) return false;
  if (filters.from && (response.createdAt ?? "") < filters.from) return false;
  if (filters.to && (response.createdAt ?? "") > filters.to) return false;
  if (filters.version && response.version !== filters.version) return false;
  if (filters.clientOrgId && response.clientOrgId !== filters.clientOrgId) return false;
  if (filters.respondentId && response.respondentId !== filters.respondentId) return false;
  if (filters.qualityStatus && response.qualityStatus !== filters.qualityStatus) return false;
  if (filters.exportIncluded === true && response.exportIncluded === false) return false;
  if (filters.exportIncluded === false && response.exportIncluded !== false) return false;
  return true;
}

const testStore = new MemoryStore();
const originalStore = productionStore;
const originalFetch = globalThis.fetch;
const salesforceEnvKeys = ["SFDC_LOGIN_URL", "SFDC_CLIENT_ID", "SFDC_USERNAME", "SFDC_JWT_PRIVATE_KEY"] as const;
const originalSalesforceEnv = Object.fromEntries(salesforceEnvKeys.map((key) => [key, process.env[key]]));

function clearSalesforceEnvironment() {
  for (const key of salesforceEnvKeys) delete process.env[key];
}

function restoreSalesforceEnvironment() {
  for (const key of salesforceEnvKeys) {
    const value = originalSalesforceEnv[key];
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
}

function buildApp() {
  const app = express();
  app.use(express.json());
  app.use("/api/features", featuresPublicRouter as Router);
  app.use("/api/surveys", surveysPublicRouter as Router);
  app.use("/api/responses", responsesPublicRouter as Router);
  app.use("/api/admin", (_req, res, next) => {
    res.locals.adminSession = { sub: "admin-1", email: "admin@example.com", exp: 4_000_000_000 };
    next();
  });
  app.use("/api/admin/features", featuresAdminRouter as Router);
  app.use("/api/admin/surveys", surveysAdminRouter as Router);
  app.use("/api/admin/responses", responsesAdminRouter as Router);
  app.use("/api/admin/settings", settingsRouter as Router);
  app.use("/api/admin/integrations/salesforce", integrationsSalesforceRouter as Router);
  app.use("/api/admin/organizations", organizationsRouter as Router);
  app.use("/api/admin/analytics", analyticsRouter as Router);
  return app.listen(0);
}

describe("QA TC-172 · General NPS specific users (pruebas escritas por QA)", () => {
  let server: ReturnType<typeof buildApp>;
  let baseUrl: string;

  before(() => {
    setStoreForTesting(testStore as unknown as SurveyStore);
    server = buildApp();
    const address = server.address();
    assert(address && typeof address === "object");
    baseUrl = `http://127.0.0.1:${address.port}`;
  });

  beforeEach(() => {
    testStore.reset();
    globalThis.fetch = originalFetch;
    clearSalesforceEnvironment();
    resetSalesforceTokenCacheForTests();
  });

  after(() => {
    globalThis.fetch = originalFetch;
    restoreSalesforceEnvironment();
    resetSalesforceTokenCacheForTests();
    setStoreForTesting(originalStore);
    server.close();
  });


  // ---------------------------------------------------------------------------
  // Pruebas escritas por QA para TC-172 (IM-1271). Cubren los huecos que los
  // tests del PR 76 no cubren: casing del Salesforce User ID, vaciado de la
  // lista por API, regresion de las audiencias previas, y los requisitos de
  // contexto que el ticket no documenta (respondentId y organizacion).
  // ---------------------------------------------------------------------------

  async function createGeneralFeature() {
    const res = await fetch(`${baseUrl}/api/admin/features`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: "General NPS", slug: "general-nps", productOwner: "platform" }),
    });
    assert.equal(res.status, 201);
    return (await res.json()) as Feature;
  }

  async function createOrg(salesforceOrgId: string, subdomain: string) {
    await testStore.createOrganization({
      name: subdomain,
      subdomain,
      salesforceOrgId,
      salesforceAccountId: null,
      domain: null,
      source: "manual",
      active: true,
      updatedAt: new Date().toISOString(),
    });
  }

  async function createSurvey(body: Record<string, unknown>) {
    return fetch(`${baseUrl}/api/admin/surveys`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  }

  async function eligibleGeneral(body: Record<string, unknown>): Promise<number[]> {
    const res = await fetch(`${baseUrl}/api/surveys/general/eligible`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    assert.equal(res.status, 200);
    return ((await res.json()) as Survey[]).map((row) => row.id);
  }

  it("QA AC3 · matches a manually entered Salesforce User ID regardless of casing", async () => {
    const feature = await createGeneralFeature();
    await createOrg("00D000000000001AAA", "qa-casing");
    const created = await createSurvey({
      featureId: feature.id,
      type: "nps",
      scale: 10,
      questionText: "How likely are you to recommend Veevart?",
      audience: "specific_users",
      audienceDetails: "005EmABCdefGHIjk",
      triggerDetails: "generalTrigger=afterLogin;loginDelaySeconds=0",
      isGeneralSurvey: true,
      accountCreatedDelayDays: 0,
    });
    assert.equal(created.status, 201);
    const survey = (await created.json()) as Survey;

    const ctx = {
      salesforceOrgId: "00D000000000001AAA",
      userCreatedDate: "2026-08-01T00:00:00.000Z",
      today: "2026-08-13",
    };

    assert.deepEqual(await eligibleGeneral({ ...ctx, respondentId: "005EmABCdefGHIjk" }), [survey.id]);
    assert.deepEqual(await eligibleGeneral({ ...ctx, respondentId: "005emabcdefghijk" }), [survey.id]);
    assert.deepEqual(await eligibleGeneral({ ...ctx, respondentId: "005EMABCDEFGHIJK" }), [survey.id]);
    assert.deepEqual(await eligibleGeneral({ ...ctx, respondentId: "005EmABCdefGHIjX" }), []);
  });

  it("QA AC5 · emptying the identifier list through the API leaves nobody eligible", async () => {
    const feature = await createGeneralFeature();
    await createOrg("00D000000000001AAA", "qa-empty");
    const created = await createSurvey({
      featureId: feature.id,
      type: "nps",
      scale: 10,
      questionText: "How likely are you to recommend Veevart?",
      audience: "specific_users",
      audienceDetails: "005AllowedAAA",
      triggerDetails: "generalTrigger=afterLogin;loginDelaySeconds=0",
      isGeneralSurvey: true,
      accountCreatedDelayDays: 0,
    });
    assert.equal(created.status, 201);
    const survey = (await created.json()) as Survey;

    const ctx = {
      salesforceOrgId: "00D000000000001AAA",
      userCreatedDate: "2026-08-01T00:00:00.000Z",
      today: "2026-08-13",
    };
    assert.deepEqual(await eligibleGeneral({ ...ctx, respondentId: "005AllowedAAA" }), [survey.id]);

    const emptied = await fetch(`${baseUrl}/api/admin/surveys/${survey.id}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ audienceDetails: "" }),
    });
    console.log(`[QA TC-172] PUT audienceDetails:"" respondio ${emptied.status}`);
    const afterEmptyStatus = emptied.status;
    const stored = await testStore.getSurveyById(survey.id);
    console.log(`[QA TC-172] audienceDetails almacenado tras el PUT: ${JSON.stringify(stored?.audienceDetails)}`);
    console.log(`[QA TC-172] la encuesta sigue activa: ${stored?.active}`);

    const stillEligible = await eligibleGeneral({ ...ctx, respondentId: "005AllowedAAA" });
    if (afterEmptyStatus === 200 && (stored?.audienceDetails ?? "") === "") {
      assert.deepEqual(stillEligible, [], "una lista vacia no puede dejar pasar a nadie");
      console.log("[QA TC-172] el vaciado se acepto y la encuesta quedo activa apuntando a nadie");
    } else {
      assert.deepEqual(stillEligible, [survey.id], "si el vaciado se rechaza, la lista previa sigue vigente");
      console.log("[QA TC-172] el vaciado fue rechazado y la lista previa sigue vigente");
    }
  });

  it("QA S9 · a matching email is not enough without a respondent ID", async () => {
    const feature = await createGeneralFeature();
    await createOrg("00D000000000001AAA", "qa-noid");
    const created = await createSurvey({
      featureId: feature.id,
      type: "nps",
      scale: 10,
      questionText: "How likely are you to recommend Veevart?",
      audience: "specific_users",
      audienceDetails: "allowed@example.com",
      triggerDetails: "generalTrigger=afterLogin;loginDelaySeconds=0",
      isGeneralSurvey: true,
      accountCreatedDelayDays: 0,
    });
    assert.equal(created.status, 201);
    const survey = (await created.json()) as Survey;

    const ctx = {
      salesforceOrgId: "00D000000000001AAA",
      userCreatedDate: "2026-08-01T00:00:00.000Z",
      today: "2026-08-13",
    };

    assert.deepEqual(
      await eligibleGeneral({ ...ctx, respondentEmail: "Allowed@Example.com" }),
      [],
      "sin respondentId la General NPS no se entrega aunque el email coincida"
    );
    assert.deepEqual(
      await eligibleGeneral({ ...ctx, respondentId: "005AnyoneAAA", respondentEmail: "Allowed@Example.com" }),
      [survey.id],
      "con respondentId presente el email configurado si alcanza"
    );
  });

  it("QA S9 · without organization context no general survey is listed at all", async () => {
    const feature = await createGeneralFeature();
    await createOrg("00D000000000001AAA", "qa-noorg");
    const created = await createSurvey({
      featureId: feature.id,
      type: "nps",
      scale: 10,
      questionText: "How likely are you to recommend Veevart?",
      audience: "specific_users",
      audienceDetails: "005AllowedAAA",
      triggerDetails: "generalTrigger=afterLogin;loginDelaySeconds=0",
      isGeneralSurvey: true,
      accountCreatedDelayDays: 0,
    });
    assert.equal(created.status, 201);
    const survey = (await created.json()) as Survey;

    assert.deepEqual(
      await eligibleGeneral({
        respondentId: "005AllowedAAA",
        userCreatedDate: "2026-08-01T00:00:00.000Z",
        today: "2026-08-13",
      }),
      [],
      "el alcance global de activacion no exime al embebedor de mandar organizacion"
    );
    assert.deepEqual(
      await eligibleGeneral({
        salesforceOrgId: "00D000000000001AAA",
        respondentId: "005AllowedAAA",
        userCreatedDate: "2026-08-01T00:00:00.000Z",
        today: "2026-08-13",
      }),
      [survey.id],
      "con organizacion la misma peticion si entrega la encuesta"
    );
  });

  it("QA AC7 · the created-date delay and one-response rule still apply to a manual audience", async () => {
    const feature = await createGeneralFeature();
    await createOrg("00D000000000001AAA", "qa-delay");
    const created = await createSurvey({
      featureId: feature.id,
      type: "nps",
      scale: 10,
      questionText: "How likely are you to recommend Veevart?",
      audience: "specific_users",
      audienceDetails: "005AllowedAAA",
      triggerDetails: "generalTrigger=afterLogin;loginDelaySeconds=0",
      isGeneralSurvey: true,
      accountCreatedDelayDays: 30,
    });
    assert.equal(created.status, 201);
    const survey = (await created.json()) as Survey;

    // El endpoint publico de elegibilidad NO acepta override de fecha
    // (toSurveyDeliveryContext solo lo permite en consultas de admin), asi que
    // las fechas de creacion se calculan relativas al dia real del servidor.
    const daysAgo = (days: number) => new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
    const base = {
      salesforceOrgId: "00D000000000001AAA",
      respondentId: "005AllowedAAA",
    };

    assert.deepEqual(
      await eligibleGeneral({ ...base, userCreatedDate: daysAgo(12) }),
      [],
      "a 12 dias de creado el usuario, el retraso de 30 dias todavia bloquea"
    );
    assert.deepEqual(
      await eligibleGeneral({ ...base, userCreatedDate: daysAgo(40) }),
      [survey.id],
      "a 40 dias de creado el usuario, cumplido el retraso, si se entrega"
    );

    const answered = await fetch(`${baseUrl}/api/responses`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        surveyId: survey.id,
        featureId: feature.id,
        score: 9,
        respondentId: "005AllowedAAA",
        salesforceOrgId: "00D000000000001AAA",
        userCreatedDate: daysAgo(40),
      }),
    });
    assert.equal(answered.status, 201);

    assert.deepEqual(
      await eligibleGeneral({ ...base, userCreatedDate: daysAgo(40) }),
      [],
      "una vez respondida no se vuelve a entregar al mismo destinatario"
    );
  });

  it("QA AC7 · the everyone and organization audiences keep their previous behavior", async () => {
    const feature = await createGeneralFeature();
    await createOrg("00D000000000001AAA", "qa-museum-a");
    await createOrg("00D000000000002AAA", "qa-museum-b");

    const everyone = await createSurvey({
      featureId: feature.id,
      type: "nps",
      scale: 10,
      questionText: "How likely are you to recommend Veevart?",
      audience: "everyone",
      triggerDetails: "generalTrigger=afterLogin;loginDelaySeconds=0",
      isGeneralSurvey: true,
      accountCreatedDelayDays: 0,
    });
    assert.equal(everyone.status, 201);
    const everyoneSurvey = (await everyone.json()) as Survey;

    const ctxA = { salesforceOrgId: "00D000000000001AAA", userCreatedDate: "2026-08-01T00:00:00.000Z", today: "2026-08-13" };
    const ctxB = { salesforceOrgId: "00D000000000002AAA", userCreatedDate: "2026-08-01T00:00:00.000Z", today: "2026-08-13" };

    assert.deepEqual(await eligibleGeneral({ ...ctxA, respondentId: "005AnyoneAAA" }), [everyoneSurvey.id]);
    assert.deepEqual(await eligibleGeneral({ ...ctxB, respondentId: "005AnyoneBBB" }), [everyoneSurvey.id]);

    const collision = await createSurvey({
      featureId: feature.id,
      type: "nps",
      scale: 10,
      questionText: "How likely are you to recommend this museum?",
      audience: "specific_users",
      audienceDetails: "005AllowedAAA",
      triggerDetails: "generalTrigger=afterLogin;loginDelaySeconds=0",
      isGeneralSurvey: true,
      accountCreatedDelayDays: 0,
    });
    assert.equal(collision.status, 409, "la audiencia manual es global y choca con la General NPS para todos");

    const missingOrg = await createSurvey({
      featureId: feature.id,
      type: "nps",
      scale: 10,
      questionText: "How likely are you to recommend this museum?",
      audience: "organization",
      audienceDetails: "",
      triggerDetails: "generalTrigger=afterLogin;loginDelaySeconds=0",
      isGeneralSurvey: true,
      accountCreatedDelayDays: 0,
    });
    assert.equal(missingOrg.status, 400, "una General NPS de organizacion sigue exigiendo al menos una organizacion");
  });

  it("QA AC7 · feature surveys with specific users keep filtering by ID and email", async () => {
    const featureRes = await fetch(`${baseUrl}/api/admin/features`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: "Payments", slug: "payments", productOwner: "platform" }),
    });
    assert.equal(featureRes.status, 201);
    const feature = (await featureRes.json()) as Feature;

    const created = await createSurvey({
      featureId: feature.id,
      type: "csat",
      scale: 5,
      questionText: "How was the payment experience?",
      audience: "specific_users",
      audienceDetails: "005PayAAA\nimplementation@example.com",
      triggerDetails: "",
    });
    assert.equal(created.status, 201);
    const survey = (await created.json()) as Survey;

    const ask = async (query: string) => {
      const res = await fetch(`${baseUrl}/api/features/payments/surveys?${query}`);
      assert.equal(res.status, 200);
      const rows = (await res.json()) as Survey[];
      return { ids: rows.map((row) => row.id), details: rows.map((row) => row.audienceDetails) };
    };

    assert.deepEqual((await ask("respondentId=005PayAAA")).ids, [survey.id]);
    assert.deepEqual((await ask("respondentEmail=IMPLEMENTATION%40EXAMPLE.COM")).ids, [survey.id]);
    assert.deepEqual((await ask("respondentId=005OtherAAA")).ids, []);
    assert.deepEqual((await ask("respondentId=005PayAAA")).details, [null], "la lista no viaja por el camino publico");
  });

});
