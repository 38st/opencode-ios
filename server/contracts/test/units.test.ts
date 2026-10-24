import { describe, expect, test } from "vitest";
import {
  aadString,
  base64url,
  canonicalize,
  CIPHERTEXT_LENGTHS,
  CONTRACT,
  GENERIC_ALERTS,
  generateKeyPair,
  KINDS,
  kindPolicy,
  MAX_PLAINTEXT,
  openEnvelope,
  sealEnvelope,
  truncate,
  utf8,
} from "../src/index.ts";

describe("base64url", () => {
  test("round-trips every length", () => {
    for (let length = 0; length < 70; length++) {
      const bytes = Uint8Array.from({ length }, (_, index) => (index * 37 + length) % 256);
      expect(base64url.decode(base64url.encode(bytes))).toEqual(bytes);
    }
  });
  test("is strict", () => {
    expect(base64url.decode("AQ==")).toBeUndefined();
    expect(base64url.decode("A+8")).toBeUndefined();
    expect(base64url.decode("A")).toBeUndefined();
    expect(base64url.decode("AR")).toBeUndefined(); // non-zero trailing bits
    expect(base64url.decode("AQ")).toEqual(Uint8Array.of(1));
    expect(base64url.decode("")).toEqual(new Uint8Array(0));
  });
});

describe("text", () => {
  test("truncation counts code points and keeps the ellipsis inside the limit", () => {
    expect(truncate("abcdef", 6)).toBe("abcdef");
    expect(truncate("abcdef", 4)).toBe("abc…");
    expect(truncate("\u{1F600}\u{1F600}\u{1F600}", 2)).toBe("\u{1F600}…");
    expect(truncate("abc", 1)).toBe("…");
    expect(truncate("abc", 0)).toBe("");
  });
  test("lone surrogates become U+FFFD before hashing or serializing", () => {
    expect(canonicalize("a\uD800b")).toBe("\"a�b\"");
    expect(utf8("\uDC00")).toEqual(utf8("�"));
  });
});

describe("constants", () => {
  test("every kind has an alert, a known category and an APNs priority", () => {
    for (const kind of KINDS) {
      const policy = kindPolicy(kind);
      expect(GENERIC_ALERTS[kind]).toBe(policy.alert);
      expect(CONTRACT.categories).toContain(policy.category);
      expect([5, 10]).toContain(policy.priority);
      expect(policy.ttlSeconds).toBeGreaterThan(0);
    }
  });
  test("the APNs category is OPEN_ONLY for every kind; the extension sets the real one", () => {
    expect(CONTRACT.apns.category).toBe("OPEN_ONLY");
    expect(CONTRACT.categories).toContain(CONTRACT.apns.category);
  });
  test("the largest padded ciphertext stays under 3 KB once encoded", () => {
    expect(MAX_PLAINTEXT).toBe(2047);
    expect(Math.max(...CIPHERTEXT_LENGTHS)).toBe(2064);
    expect(Math.ceil((2064 * 4) / 3)).toBeLessThanOrEqual(CONTRACT.envelope.maxEncodedCiphertext);
  });
  test("aad is the version prefix, kind, expiry and key ID", () => {
    expect(aadString("permission", 1800000600, "abcdefghijklmnop")).toBe("oc1|permission|1800000600|abcdefghijklmnop");
  });
});

describe("envelope round trip with random keys", () => {
  test("seals and opens, and a different recipient cannot open it", async () => {
    const device = await generateKeyPair(), plugin = await generateKeyPair(), stranger = await generateKeyPair();
    const plaintext = utf8(canonicalize({ v: 1, kind: "test", server: "s", exp: 2000, pending: 0 }));
    const envelope = await sealEnvelope({ kind: "test", exp: 2000, kid: "kid_0123456789abcdef", plaintext, recipientPublicKey: device.publicKey, sender: plugin });
    const opened = await openEnvelope(envelope, { now: 1000, key: () => ({ recipientPrivateKey: device.privateKey, senderPublicKey: plugin.publicKey }) });
    expect(opened.payload.kind).toBe("test");
    await expect(openEnvelope(envelope, { now: 1000, key: () => ({ recipientPrivateKey: stranger.privateKey, senderPublicKey: plugin.publicKey }) })).rejects.toMatchObject({ code: "authentication" });
  });
});
