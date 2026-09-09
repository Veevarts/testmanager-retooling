/**
 * QA-authored tests for TC-160 / IM-1251 (TR-177). NOT part of the repo:
 * se crean para ejecutar la evidencia y se borran al terminar.
 * Prueban los ACs de la historia contra el agregador puro con fixtures controlados.
 */
import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { SurveyEvent, SurveyResponse } from "../data/types.js";
import { buildRespondentEngagement } from "./respondentEngagement.js";

function response(overrides: Partial<SurveyResponse> = {}): SurveyResponse {
  return {
    id: 1, surveyId: 10, featureId: 20, score: 9, comment: null, scoreReason: null,
    companyRecommendScore: null, version: null, clientOrgId: "00d-demo",
    respondentId: "user-1", context: null, customAnswers: null, qualityStatus: "pending",
    qualityNotes: null, exportIncluded: true, qualityUpdatedAt: null,
    createdAt: "2026-09-01T12:00:00.000Z", ...overrides,
  };
}

function event(overrides: Partial<SurveyEvent> = {}): SurveyEvent {
  return {
    id: 1, surveyId: 10, respondentId: "user-1", clientOrgId: "00d-demo",
    type: "impression", createdAt: "2026-09-01T11:00:00.000Z", ...overrides,
  };
}

describe("QA TC-160 · AC1 + AC4 · union of the three sources without double-counting", () => {
  it("emits exactly one row per respondent across responses, impressions and dismissals", () => {
    const result = buildRespondentEngagement(
      [response({ respondentId: "user-a" })],
      [
        event({ respondentId: "user-a", type: "impression" }),
        event({ respondentId: "user-a", type: "dismissal", id: 2 }),
        event({ respondentId: "user-b", type: "impression", id: 3 }),
      ]
    );
    assert.equal(result.rows.length, 2, "un respondent en 3 fuentes + uno solo con evento = 2 filas");
    const a = result.rows.find((r) => r.respondentId === "user-a")!;
    assert.equal(a.impressions, 1, "la impression se cuenta una sola vez");
    assert.equal(a.dismissals, 1, "el dismissal se cuenta una sola vez");
    assert.equal(a.responded, true);
  });

  it("does not multiply rows when the same respondent has many events", () => {
    const result = buildRespondentEngagement(
      [response({ respondentId: "user-a" })],
      [
        event({ respondentId: "user-a", id: 1, type: "impression" }),
        event({ respondentId: "user-a", id: 2, type: "impression" }),
        event({ respondentId: "user-a", id: 3, type: "impression" }),
        event({ respondentId: "user-a", id: 4, type: "dismissal" }),
      ]
    );
    assert.equal(result.rows.length, 1);
    assert.equal(result.rows[0].impressions, 3);
    assert.equal(result.rows[0].dismissals, 1);
  });
});

describe("QA TC-160 · AC2 · Responded reflects the presence of a response", () => {
  it("marks Yes with at least one response and No with events only", () => {
    const result = buildRespondentEngagement(
      [response({ respondentId: "responder" })],
      [event({ respondentId: "lurker", type: "impression" })]
    );
    assert.equal(result.rows.find((r) => r.respondentId === "responder")!.responded, true);
    assert.equal(result.rows.find((r) => r.respondentId === "lurker")!.responded, false);
  });
});

describe("QA TC-160 · AC3 · impression and dismissal totals are exact", () => {
  it("counts each event type independently", () => {
    const events: SurveyEvent[] = [];
    for (let i = 0; i < 5; i += 1) events.push(event({ id: i, type: "impression" }));
    for (let i = 5; i < 8; i += 1) events.push(event({ id: i, type: "dismissal" }));
    const result = buildRespondentEngagement([], events);
    assert.equal(result.rows.length, 1);
    assert.equal(result.rows[0].impressions, 5);
    assert.equal(result.rows[0].dismissals, 3);
  });
});

describe("QA TC-160 · AC5 · organizations stay isolated in the All organizations scope", () => {
  it("keeps the same respondent ID in two organizations as two separate rows", () => {
    const result = buildRespondentEngagement(
      [
        response({ respondentId: "shared-user", clientOrgId: "00d-alpha" }),
        response({ respondentId: "shared-user", clientOrgId: "00d-beta", id: 2 }),
      ],
      [
        event({ respondentId: "shared-user", clientOrgId: "00d-alpha", type: "impression" }),
        event({ respondentId: "shared-user", clientOrgId: "00d-beta", type: "impression", id: 2 }),
      ]
    );
    assert.equal(result.rows.length, 2, "no se fusionan respondents de organizaciones distintas");
    const orgs = result.rows.map((r) => r.clientOrgId).sort();
    assert.deepEqual(orgs, ["00d-alpha", "00d-beta"]);
    for (const row of result.rows) assert.equal(row.impressions, 1, "cada org cuenta solo su evento");
  });
});

describe("QA TC-160 · cross-ingest · responses store respondentId lowercased, events store it raw", () => {
  it("merges the same person into one row despite the ingest case mismatch (AC4 holds)", () => {
    // responses.ts:229 guarda respondentId en minusculas; features.ts:328 lo guarda tal cual.
    const result = buildRespondentEngagement(
      [response({ respondentId: "005xx000001abcaaa" })],
      [event({ respondentId: "005Xx000001abcAAA", type: "impression" })]
    );
    assert.equal(result.rows.length, 1, "la normalizacion evita la fila duplicada por diferencia de caso");
    assert.equal(result.rows[0].responded, true);
    assert.equal(result.rows[0].impressions, 1);
  });

  it("shows the respondent ID of whichever source is processed first (responses win)", () => {
    const withResponse = buildRespondentEngagement(
      [response({ respondentId: "005xx000001abcaaa" })],
      [event({ respondentId: "005Xx000001abcAAA" })]
    );
    assert.equal(withResponse.rows[0].respondentId, "005xx000001abcaaa");
    const eventsOnly = buildRespondentEngagement([], [event({ respondentId: "005Xx000001abcAAA" })]);
    assert.equal(eventsOnly.rows[0].respondentId, "005Xx000001abcAAA", "sin response se conserva el caso original");
  });
});

describe("QA TC-160 · unattributed responses are not presented as identified users", () => {
  it("counts responses without respondentId apart instead of creating a row", () => {
    const result = buildRespondentEngagement(
      [
        response({ respondentId: null }),
        response({ respondentId: "   ", id: 2 }),
        response({ respondentId: "real-user", id: 3 }),
      ],
      []
    );
    assert.equal(result.unattributedResponseCount, 2);
    assert.equal(result.rows.length, 1);
    assert.equal(result.rows[0].respondentId, "real-user");
  });

  it("ignores events without a respondent id", () => {
    const result = buildRespondentEngagement([], [event({ respondentId: "" }), event({ respondentId: null as unknown as string, id: 2 })]);
    assert.equal(result.rows.length, 0);
  });
});

describe("QA TC-160 · latest activity is the maximum across both sources", () => {
  it("takes the newest timestamp whether it comes from a response or an event", () => {
    const eventNewer = buildRespondentEngagement(
      [response({ createdAt: "2026-09-01T10:00:00.000Z" })],
      [event({ createdAt: "2026-09-05T10:00:00.000Z" })]
    );
    assert.equal(eventNewer.rows[0].lastActivityAt, "2026-09-05T10:00:00.000Z");
    const responseNewer = buildRespondentEngagement(
      [response({ createdAt: "2026-09-09T10:00:00.000Z" })],
      [event({ createdAt: "2026-09-05T10:00:00.000Z" })]
    );
    assert.equal(responseNewer.rows[0].lastActivityAt, "2026-09-09T10:00:00.000Z");
  });
});

describe("QA TC-160 · AC6 · empty input yields an empty summary, not an error", () => {
  it("returns zero rows and zero unattributed for an empty selection", () => {
    const result = buildRespondentEngagement([], []);
    assert.deepEqual(result.rows, []);
    assert.equal(result.unattributedResponseCount, 0);
  });
});
