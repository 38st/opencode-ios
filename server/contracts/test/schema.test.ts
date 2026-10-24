import { readFile } from "node:fs/promises";
import { Ajv2020 } from "ajv/dist/2020.js";
import { describe, expect, test } from "vitest";

const load = async (path: string) => JSON.parse(await readFile(new URL(`../${path}`, import.meta.url), "utf8"));
// strictRequired would demand that conditional "then" blocks redeclare properties defined at the top level.
const ajv = new Ajv2020({ strict: true, strictRequired: false, allErrors: true });
const envelopeSchema = ajv.compile(await load("schema/envelope.schema.json"));
const payloadSchema = ajv.compile(await load("schema/payload.schema.json"));
const activitySchema = ajv.compile(await load("schema/activity-state.schema.json"));
const envelopes = await load("vectors/envelope.json");
const payloads = await load("vectors/payload.json");

describe("schemas", () => {
  test("every fitted payload vector conforms", () => {
    for (const item of payloads.cases) expect(payloadSchema(item.payload), item.name + JSON.stringify(payloadSchema.errors)).toBe(true);
  });

  test("every valid envelope conforms", () => {
    for (const item of envelopes.valid) expect(envelopeSchema(item.envelope), item.name).toBe(true);
  });

  test("structural rejections fail the envelope schema", () => {
    const structural = envelopes.rejections.filter((item: { error: string }) => item.error === "malformed" || item.error === "unsupportedVersion");
    expect(structural.length).toBeGreaterThan(5);
    for (const item of structural) expect(envelopeSchema(item.envelope), item.name).toBe(false);
  });

  test("a permission payload needs its request fields", () => {
    expect(payloadSchema({ v: 1, kind: "permission", server: "s", exp: 1, pending: 0 })).toBe(false);
    expect(payloadSchema({ v: 1, kind: "test", server: "s", exp: 1, pending: 0, extra: true })).toBe(true);
  });

  test("activity state allows only the coarse fields", () => {
    const state = { phase: "running", step: 3, toolGlyph: "shell", startedAt: 1_800_000_000, updatedAt: 1_800_000_030 };
    expect(activitySchema(state)).toBe(true);
    expect(activitySchema({ ...state, title: "secret" })).toBe(false);
    expect(activitySchema({ ...state, phase: "thinking" })).toBe(false);
  });
});
