import { readFile } from "node:fs/promises";
import { describe, expect, test } from "vitest";
import { bytesFrom, generateVectors } from "../scripts/generate-vectors.ts";
import {
  base64url,
  bucketFor,
  canonicalize,
  classify,
  fitPayload,
  formDigest,
  formDigestInput,
  hex,
  openEnvelope,
  pad,
  permissionDigest,
  permissionDigestInput,
  sha256,
  unpad,
  utf8,
} from "../src/index.ts";

const load = async (name: string) => JSON.parse(await readFile(new URL(`../vectors/${name}`, import.meta.url), "utf8"));
const [jcs, digest, padding, risk, payload, envelope] = await Promise.all(
  ["jcs.json", "digest.json", "padding.json", "risk.json", "payload.json", "envelope.json"].map(load),
);

test("the committed vectors are exactly what the generator produces", async () => {
  const generated = await generateVectors();
  for (const [name, content] of Object.entries(generated)) {
    expect(await readFile(new URL(`../vectors/${name}`, import.meta.url), "utf8"), name).toBe(content);
  }
});

type Item = Record<string, any> & { name: string };
const each = (items: Item[], run: (item: Item) => unknown, prefix = "") => {
  for (const item of items) test(prefix + item.name, async () => void (await run(item)));
};

describe("jcs", () => {
  each(jcs.cases, (item) => expect(canonicalize(item.input)).toBe(item.canonical));
});

describe("digest", () => {
  each(digest.permissions, async (item) => {
    expect(canonicalize(permissionDigestInput(item.input))).toBe(item.canonical);
    expect(await permissionDigest(item.input)).toBe(item.digest);
    expect(hex(await sha256(utf8(item.canonical)))).toBe(item.digest);
  }, "permission ");
  each(digest.forms, async (item) => {
    expect(canonicalize(formDigestInput(item.input))).toBe(item.canonical);
    expect(await formDigest(item.input)).toBe(item.digest);
  }, "form ");
});

describe("padding", () => {
  each(padding.pad, async (item) => {
    const bytes = bytesFrom(item.input);
    if (item.error) {
      expect(bucketFor(bytes.length)).toBeUndefined();
      expect(() => pad(bytes)).toThrow();
      return;
    }
    const padded = pad(bytes);
    expect(padded.length).toBe(item.length);
    expect(hex(await sha256(padded))).toBe(item.sha256);
    expect(unpad(padded)).toEqual(bytes);
  }, "pad ");
  each(padding.unpad, (item) => {
    const bytes = bytesFrom(item.input);
    if (item.error) expect(() => unpad(bytes)).toThrow();
    else expect(hex(unpad(bytes))).toBe(item.output);
  }, "unpad ");
});

describe("risk", () => {
  each(risk.cases, (item) => expect(classify(item.action, item.resources)).toEqual({ tier: item.tier, rule: item.rule }));
});

describe("payload fitting", () => {
  each(payload.cases, (item) => {
    const fitted = fitPayload(item.draft);
    expect(fitted.payload).toEqual(item.payload);
    expect(new TextDecoder().decode(fitted.plaintext)).toBe(item.plaintext);
    expect(fitted.plaintext.length).toBe(item.bytes);
    expect(bucketFor(item.bytes)).toBe(item.bucket);
  });
});

describe("envelope", () => {
  const keys = new Map<string, { recipientPrivateKey: Uint8Array; senderPublicKey: Uint8Array }>(
    envelope.keyring.map((entry: Item) => [
      entry.kid,
      { recipientPrivateKey: base64url.decode(entry.recipientPrivateKey)!, senderPublicKey: base64url.decode(entry.senderPublicKey)! },
    ]),
  );
  const key = (kid: string) => keys.get(kid);
  each(envelope.valid, async (item) => {
    const opened = await openEnvelope(item.envelope, { now: item.now, key });
    expect(new TextDecoder().decode(opened.plaintext)).toBe(item.plaintext);
    expect(opened.payload).toEqual(JSON.parse(item.plaintext));
  }, "opens ");
  each(envelope.rejections, async (item) => {
    await expect(openEnvelope(item.envelope, { now: item.now, key })).rejects.toMatchObject({ code: item.error });
  }, "rejects ");
});
