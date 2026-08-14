import { Router, type Request, type Response } from "express";
import { isStoreDuplicateError, store } from "../data/dynamodbStore.js";
import type { Feature, Survey } from "../data/types.js";
import { createFeatureSchema, updateFeatureSchema } from "../lib/validation.js";
import {
  evaluateSurveyEligibility,
  getCooldownDays,
  parseSurveyRow,
  toSurveyDeliveryContext,
  type ParsedSurvey,
  type SurveyDeliveryContext,
} from "../lib/surveyRuntime.js";
import { getMaxSurveysPerDay } from "../lib/appSettings.js";

export const featuresPublicRouter = Router();
export const featuresAdminRouter = Router();

export type GeneralSurveyTriggerMode = "featureTrigger" | "afterLogin" | "any";

function getGeneralSurveyTriggerMode(survey: ParsedSurvey): Exclude<GeneralSurveyTriggerMode, "any"> {
  const rules: Record<string, string> = {};
  for (const piece of (survey.triggerDetails ?? "").split(/[\n,;]+/g)) {
    const trimmed = piece.trim();
    if (!trimmed) continue;
    const match = trimmed.match(/^([a-zA-Z0-9_]+)\s*[:=]\s*(.+)$/);
    if (!match) continue;
    rules[match[1].trim().toLowerCase()] = match[2].trim();
  }
  const raw = rules.generaltrigger ?? rules.general_trigger ?? rules.deliverymode ?? rules.delivery_mode;
  return raw === "afterLogin" || raw === "after_login" ? "afterLogin" : "featureTrigger";
}

async function resolveFeature(raw: string): Promise<Feature | null> {
  const id = parseInt(raw, 10);
  if (!Number.isNaN(id)) return store.getFeatureById(id);
  return store.getFeatureBySlug(raw);
}

async function resolveFeatureId(raw: string): Promise<number | null> {
  return (await resolveFeature(raw))?.id ?? null;
}

async function isActiveClientOrg(ctx: SurveyDeliveryContext): Promise<boolean> {
  const salesforceOrgId = ctx.salesforceOrgId?.trim();
  const clientOrgId = ctx.clientOrgId?.trim().toLowerCase();
  if (!salesforceOrgId && !clientOrgId) return false;
  return store.hasActiveOrganization({ salesforceOrgId, subdomain: clientOrgId });
}

function normalizedOrganizationKey(ctx: SurveyDeliveryContext): string | null {
  const normalized = (ctx.salesforceOrgId ?? ctx.clientOrgId)?.trim().toLowerCase();
  return normalized || null;
}

function surveyAllowsClientOrg(survey: ParsedSurvey, organizationKey: string | null): boolean {
  if (!survey.isGeneralSurvey) return true;
  if (!organizationKey) return false;
  const legacyOrgId = survey.generalClientOrgId?.trim().toLowerCase();
  if (legacyOrgId) return legacyOrgId === organizationKey;
  if ((survey.audience ?? "everyone") === "everyone") return true;
  if (survey.audience === "organization") {
    const allowed =
      survey.audienceDetails
        ?.split(/[\n,;]+/g)
        .map((value) => value.trim().toLowerCase())
        .filter(Boolean) ?? [];
    return allowed.includes(organizationKey);
  }
  return false;
}

function scopedClientOrgId(survey: ParsedSurvey, ctx: SurveyDeliveryContext): string | undefined {
  const clientOrgId = normalizedOrganizationKey(ctx);
  return survey.isGeneralSurvey && !survey.generalClientOrgId && clientOrgId ? clientOrgId : undefined;
}

async function hasReachedMaxSurveysPerDay(ctx: SurveyDeliveryContext, skipDeliveryCaps?: boolean): Promise<boolean> {
  const maxSurveysPerDay = await getMaxSurveysPerDay();
  if (skipDeliveryCaps || maxSurveysPerDay == null || !ctx.respondentId) return false;
  const shownToday = await store.countEvents({
    respondentId: ctx.respondentId,
    type: "impression",
    from: new Date().toISOString().slice(0, 10),
  });
  return shownToday >= maxSurveysPerDay;
}

export async function getSurveyEligibilityVerdict(
  survey: ParsedSurvey,
  ctx: SurveyDeliveryContext,
  options: { ignoreImpressionCount?: boolean; activeClientOrg?: boolean } = {}
) {
  const clientOrgId = scopedClientOrgId(survey, ctx);
  const responseCount = await store.countResponses({ surveyId: survey.id });
  const lastForRespondent = ctx.respondentId
    ? await store.getLastResponse({
        surveyId: survey.id,
        respondentId: ctx.respondentId,
        ...(clientOrgId !== undefined ? { clientOrgId } : {}),
      })
    : null;
  const impressionCount = ctx.respondentId
    ? await store.countEvents({
        surveyId: survey.id,
        respondentId: ctx.respondentId,
        ...(clientOrgId !== undefined ? { clientOrgId } : {}),
        type: "impression",
      })
    : 0;
  const todayImpressionCount = ctx.respondentId
    ? await store.countEvents({
        surveyId: survey.id,
        respondentId: ctx.respondentId,
        ...(clientOrgId !== undefined ? { clientOrgId } : {}),
        type: "impression",
        from: ctx.today,
      })
    : 0;
  const cooldownDays = getCooldownDays(survey);
  const dismissalFrom =
    cooldownDays != null ? new Date(Date.now() - cooldownDays * 24 * 60 * 60 * 1000).toISOString() : undefined;
  const dismissalCount = ctx.respondentId
    ? await store.countEvents({
        surveyId: survey.id,
        respondentId: ctx.respondentId,
        ...(clientOrgId !== undefined ? { clientOrgId } : {}),
        type: "dismissal",
        from: dismissalFrom,
      })
    : 0;
  return evaluateSurveyEligibility({
    survey,
    ctx,
    responseCount,
    lastRespondedAt: lastForRespondent?.createdAt ?? null,
    impressionCount: options.ignoreImpressionCount ? 0 : impressionCount,
    todayImpressionCount: options.ignoreImpressionCount ? 0 : todayImpressionCount,
    dismissalCount,
    activeClientOrg: options.activeClientOrg,
  });
}

export async function selectEligibleGeneralSurveys(
  ctx: SurveyDeliveryContext,
  options: { requestedSurveyId?: number; skipDeliveryCaps?: boolean; triggerMode?: GeneralSurveyTriggerMode } = {}
): Promise<ParsedSurvey[]> {
  if (await hasReachedMaxSurveysPerDay(ctx, options.skipDeliveryCaps)) return [];

  const generalClientOrgId = normalizedOrganizationKey(ctx);
  const activeClientOrg = await isActiveClientOrg(ctx);
  const triggerMode = options.triggerMode ?? "featureTrigger";
  const generalSurveys = generalClientOrgId
    ? (await store.listActiveGeneralSurveys())
        .map(parseSurveyRow)
        .filter((survey) => options.requestedSurveyId == null || survey.id === options.requestedSurveyId)
        .filter((survey) => surveyAllowsClientOrg(survey, generalClientOrgId))
        .filter((survey) => triggerMode === "any" || getGeneralSurveyTriggerMode(survey) === triggerMode)
    : [];

  const eligible: ParsedSurvey[] = [];
  for (const survey of generalSurveys) {
    const verdict = await getSurveyEligibilityVerdict(survey, ctx, {
      ignoreImpressionCount: options.skipDeliveryCaps,
      activeClientOrg: survey.generalClientOrgId ? undefined : activeClientOrg,
    });
    if (!verdict.ok && verdict.reason?.startsWith("user_created_date_")) {
      console.warn("General survey skipped", {
        reason: verdict.reason,
        surveyId: survey.id,
        hasClientOrgId: ctx.clientOrgId != null,
        hasSalesforceOrgId: ctx.salesforceOrgId != null,
        hasRespondentId: ctx.respondentId != null,
      });
    }
    if (verdict.ok) eligible.push(survey);
  }
  return eligible;
}

async function selectEligibleSurveysForFeature(
  featureId: number,
  ctx: SurveyDeliveryContext,
  options: { requestedSurveyId?: number; skipDeliveryCaps?: boolean } = {}
): Promise<ParsedSurvey[]> {
  const parsed = (await store.listSurveysByFeatureId(featureId, true)).map(parseSurveyRow);

  if (await hasReachedMaxSurveysPerDay(ctx, options.skipDeliveryCaps)) return [];

  const eligibleGeneralSurvey = (
    await selectEligibleGeneralSurveys(ctx, {
      requestedSurveyId: options.requestedSurveyId,
      skipDeliveryCaps: options.skipDeliveryCaps,
      triggerMode: options.requestedSurveyId != null ? "any" : "featureTrigger",
    })
  )[0];
  if (eligibleGeneralSurvey) {
    const eligible = [eligibleGeneralSurvey];
    return options.requestedSurveyId != null
      ? eligible.filter((survey) => survey.id === options.requestedSurveyId)
      : eligible;
  }

  const eligible: ParsedSurvey[] = [];
  for (const survey of parsed) {
    const verdict = await getSurveyEligibilityVerdict(survey, ctx, {
      ignoreImpressionCount: options.skipDeliveryCaps,
    });
    if (!survey.isGeneralSurvey && verdict.ok) eligible.push(survey);
  }
  return options.requestedSurveyId != null
    ? eligible.filter((survey) => survey.id === options.requestedSurveyId)
    : eligible;
}

function getSurveyEventBody(req: Request): { surveyId: number; ctx: SurveyDeliveryContext } | { error: string } {
  const { surveyId, respondentId } = req.body as { surveyId?: unknown; respondentId?: unknown };
  if (
    typeof surveyId !== "number" ||
    !Number.isFinite(surveyId) ||
    surveyId <= 0 ||
    typeof respondentId !== "string" ||
    !respondentId.trim()
  ) {
    return { error: "surveyId (number) and respondentId (string) are required" };
  }
  const ctx = toSurveyDeliveryContext(req.body as Record<string, unknown>);
  if (!ctx.respondentId) return { error: "surveyId (number) and respondentId (string) are required" };
  return { surveyId, ctx };
}

async function validateSurveyEvent(
  req: Request,
  options: { skipDeliveryCaps: boolean }
): Promise<{ surveyId: number; ctx: SurveyDeliveryContext } | { error: string; status: number }> {
  const featureId = await resolveFeatureId(req.params.featureId);
  if (featureId == null) return { error: "Feature not found", status: 404 };

  const parsed = getSurveyEventBody(req);
  if ("error" in parsed) return { error: parsed.error, status: 400 };

  const eligible = await selectEligibleSurveysForFeature(featureId, parsed.ctx, {
    requestedSurveyId: parsed.surveyId,
    skipDeliveryCaps: options.skipDeliveryCaps,
  });
  if (!eligible.some((survey) => survey.id === parsed.surveyId)) {
    return { error: "surveyId is not eligible for this feature context", status: 400 };
  }

  return parsed;
}

featuresAdminRouter.get("/", async (_req, res) => {
  try {
    res.json(await store.listFeatures());
  } catch (e) {
    res.status(500).json({ error: String(e) });
  }
});

featuresPublicRouter.get("/by-slug/:slug", async (req, res) => {
  try {
    const feature = await store.getFeatureBySlug(req.params.slug);
    if (!feature) return res.status(404).json({ error: "Not found" });
    res.json(feature);
  } catch (e) {
    res.status(500).json({ error: String(e) });
  }
});

export async function getFeatureSurveys(req: Request, res: Response, options: { allowAdminLookup: boolean }) {
  const { featureId: raw } = req.params;
  try {
    const featureId = await resolveFeatureId(raw);
    if (featureId == null) return res.status(404).json({ error: "Feature not found" });

    const previewMode = options.allowAdminLookup && (req.query.preview === "1" || req.query.preview === "true");
    const renderMode = req.query.render === "1" || req.query.render === "true";
    const requestedSurveyIdRaw = req.query.surveyId;
    const requestedSurveyId =
      requestedSurveyIdRaw != null && String(requestedSurveyIdRaw).trim() !== ""
        ? Number(String(requestedSurveyIdRaw))
        : undefined;
    if (requestedSurveyId != null && (!Number.isFinite(requestedSurveyId) || requestedSurveyId <= 0)) {
      return res.status(400).json({ error: "Invalid surveyId" });
    }
    const activeOnly = options.allowAdminLookup ? (previewMode ? false : req.query.active !== "false") : true;
    const list = await store.listSurveysByFeatureId(featureId, activeOnly);
    const parsed = list.map(parseSurveyRow);
    if (!activeOnly || previewMode) return res.json(parsed);

    const ctx = toSurveyDeliveryContext(req.query as Record<string, unknown>, {
      allowDateOverride: options.allowAdminLookup,
    });
    res.json(
      await selectEligibleSurveysForFeature(featureId, ctx, {
        requestedSurveyId,
        skipDeliveryCaps: renderMode && requestedSurveyId != null,
      })
    );
  } catch (e) {
    res.status(500).json({ error: String(e) });
  }
}

featuresPublicRouter.get("/:featureId/surveys", (req, res) => {
  void getFeatureSurveys(req, res, { allowAdminLookup: false });
});

featuresAdminRouter.get("/:featureId/surveys", (req, res) => {
  void getFeatureSurveys(req, res, { allowAdminLookup: true });
});

featuresPublicRouter.post("/:featureId/dismissals", async (req, res) => {
  try {
    const event = await validateSurveyEvent(req, { skipDeliveryCaps: true });
    if ("error" in event) return res.status(event.status).json({ error: event.error });
    await store.createEvent({
      surveyId: event.surveyId,
      respondentId: event.ctx.respondentId!,
      clientOrgId: normalizedOrganizationKey(event.ctx),
      type: "dismissal",
    });
    res.status(201).json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: String(e) });
  }
});

featuresPublicRouter.post("/:featureId/impressions", async (req, res) => {
  try {
    const event = await validateSurveyEvent(req, { skipDeliveryCaps: false });
    if ("error" in event) return res.status(event.status).json({ error: event.error });
    await store.createEvent({
      surveyId: event.surveyId,
      respondentId: event.ctx.respondentId!,
      clientOrgId: normalizedOrganizationKey(event.ctx),
      type: "impression",
    });
    res.status(201).json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: String(e) });
  }
});

featuresAdminRouter.get("/:featureId/respondent-state/:respondentId", async (req, res) => {
  const { featureId: raw, respondentId } = req.params;
  if (!respondentId || !respondentId.trim()) return res.status(400).json({ error: "respondentId is required" });
  const rid = respondentId.trim();
  try {
    const feature = await resolveFeature(raw);
    if (!feature) return res.status(404).json({ error: "Feature not found" });

    const ctx = toSurveyDeliveryContext(req.query as Record<string, unknown>);
    ctx.respondentId = rid;

    const maxSurveysPerDay = await getMaxSurveysPerDay();
    const surveysShownToday = await store.countEvents({
      respondentId: rid,
      type: "impression",
      from: new Date().toISOString().slice(0, 10),
    });

    const featureSurveys = (await store.listSurveysByFeatureId(feature.id, false)).map(parseSurveyRow);
    const report = [];
    for (const survey of featureSurveys) {
      const responseCount = await store.countResponses({ surveyId: survey.id, respondentId: rid });
      const lastForRespondent = await store.getLastResponse({ surveyId: survey.id, respondentId: rid });
      const impressionCount = await store.countEvents({ surveyId: survey.id, respondentId: rid, type: "impression" });
      const todayImpressionCount = await store.countEvents({
        surveyId: survey.id,
        respondentId: rid,
        type: "impression",
        from: new Date().toISOString().slice(0, 10),
      });
      const cooldownDays = getCooldownDays(survey);
      const dismissalCountAllTime = await store.countEvents({ surveyId: survey.id, respondentId: rid, type: "dismissal" });
      const dismissalCount = await store.countEvents({
        surveyId: survey.id,
        respondentId: rid,
        type: "dismissal",
        from: cooldownDays != null ? new Date(Date.now() - cooldownDays * 24 * 60 * 60 * 1000).toISOString() : undefined,
      });
      const verdict = evaluateSurveyEligibility({
        survey,
        ctx,
        responseCount,
        lastRespondedAt: lastForRespondent?.createdAt ?? null,
        impressionCount,
        todayImpressionCount,
        dismissalCount,
      });
      report.push({
        surveyId: survey.id,
        active: survey.active,
        limits: {
          maxDismissals: survey.maxDismissals,
          maxShowsPerDay: survey.maxImpressions,
          cooldownDays,
        },
        counters: {
          impressionCount,
          todayImpressionCount,
          dismissalCount,
          dismissalCountAllTime,
          responseCount,
          lastRespondedAt: lastForRespondent?.createdAt ?? null,
        },
        eligible: verdict.ok,
        reason: verdict.reason ?? null,
      });
    }

    res.json({
      feature: { id: feature.id, slug: feature.slug },
      respondentId: rid,
      global: { maxSurveysPerDay, surveysShownToday },
      surveys: report,
    });
  } catch (e) {
    res.status(500).json({ error: String(e) });
  }
});

featuresAdminRouter.delete("/:featureId/respondent-state/:respondentId", async (req, res) => {
  const { featureId: raw, respondentId } = req.params;
  if (!respondentId || !respondentId.trim()) return res.status(400).json({ error: "respondentId is required" });
  try {
    const feature = await resolveFeature(raw);
    if (!feature) return res.status(404).json({ error: "Feature not found" });
    const surveyIds = (await store.listSurveysByFeatureId(feature.id, false)).map((survey) => survey.id);
    const impressionsDeleted = await store.deleteEvents({ surveyIds, respondentId: respondentId.trim(), type: "impression" });
    const dismissalsDeleted = await store.deleteEvents({ surveyIds, respondentId: respondentId.trim(), type: "dismissal" });
    res.json({ ok: true, impressionsDeleted, dismissalsDeleted });
  } catch (e) {
    res.status(500).json({ error: String(e) });
  }
});

const getFeatureById = async (req: Request, res: Response) => {
  const id = parseInt(req.params.id, 10);
  if (Number.isNaN(id)) return res.status(400).json({ error: "Invalid id" });
  try {
    const feature = await store.getFeatureById(id);
    if (!feature) return res.status(404).json({ error: "Not found" });
    res.json(feature);
  } catch (e) {
    res.status(500).json({ error: String(e) });
  }
};

featuresPublicRouter.get("/:id", getFeatureById);
featuresAdminRouter.get("/:id", getFeatureById);

featuresAdminRouter.post("/", async (req, res) => {
  const parsed = createFeatureSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  try {
    const inserted = await store.createFeature({
      name: parsed.data.name,
      slug: parsed.data.slug,
      description: parsed.data.description ?? null,
      productOwner: parsed.data.productOwner ?? null,
      version: parsed.data.version ?? null,
      implementationPerson: parsed.data.implementationPerson?.trim() || null,
      customerSuccessExecutive: parsed.data.customerSuccessExecutive?.trim() || null,
      isFeature: parsed.data.isFeature ?? null,
    });
    res.status(201).json(inserted);
  } catch (e: unknown) {
    if (isStoreDuplicateError(e)) return res.status(409).json({ error: "Slug already exists" });
    res.status(500).json({ error: String(e) });
  }
});

featuresAdminRouter.put("/:id", async (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (Number.isNaN(id)) return res.status(400).json({ error: "Invalid id" });
  const parsed = updateFeatureSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  try {
    const update: Partial<Omit<Feature, "id" | "createdAt">> = {};
    if (parsed.data.name !== undefined) update.name = parsed.data.name;
    if (parsed.data.slug !== undefined) update.slug = parsed.data.slug;
    if (parsed.data.description !== undefined) update.description = parsed.data.description ?? null;
    if (parsed.data.productOwner !== undefined) update.productOwner = parsed.data.productOwner ?? null;
    if (parsed.data.version !== undefined) update.version = parsed.data.version ?? null;
    if (parsed.data.implementationPerson !== undefined) {
      update.implementationPerson = parsed.data.implementationPerson?.trim() || null;
    }
    if (parsed.data.customerSuccessExecutive !== undefined) {
      update.customerSuccessExecutive = parsed.data.customerSuccessExecutive?.trim() || null;
    }
    if (parsed.data.isFeature !== undefined) update.isFeature = parsed.data.isFeature;
    const updated = await store.updateFeature(id, update);
    if (!updated) return res.status(404).json({ error: "Not found" });
    res.json(updated);
  } catch (e: unknown) {
    if (isStoreDuplicateError(e)) return res.status(409).json({ error: "Slug already exists" });
    res.status(500).json({ error: String(e) });
  }
});

featuresAdminRouter.delete("/:id", async (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (Number.isNaN(id)) return res.status(400).json({ error: "Invalid id" });
  try {
    const deleted = await store.deleteFeature(id);
    if (!deleted) return res.status(404).json({ error: "Not found" });
    res.status(204).send();
  } catch (e) {
    res.status(500).json({ error: String(e) });
  }
});
