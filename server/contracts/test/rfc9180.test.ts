import { readFile } from "node:fs/promises";
import { describe, expect, test } from "vitest";
import { cryptoKeyPair, fromHex, hex, importPrivateKey, importPublicKey, publicKeyFor, suite } from "../src/index.ts";

const vector = JSON.parse(await readFile(new URL("../vectors/rfc9180-a23.json", import.meta.url), "utf8"));

describe("RFC 9180 A.2.3 (auth mode, X25519, ChaCha20-Poly1305)", () => {
  test("derives the published public keys", async () => {
    expect(hex(await publicKeyFor(fromHex(vector.skRm)))).toBe(vector.pkRm);
    expect(hex(await publicKeyFor(fromHex(vector.skSm)))).toBe(vector.pkSm);
    expect(hex(await publicKeyFor(fromHex(vector.skEm)))).toBe(vector.pkEm);
  });

  test("seals the published ciphertexts with the fixed ephemeral key", async () => {
    const sender = await suite.createSenderContext({
      recipientPublicKey: await importPublicKey(fromHex(vector.pkRm)),
      senderKey: await cryptoKeyPair({ privateKey: fromHex(vector.skSm), publicKey: fromHex(vector.pkSm) }),
      info: fromHex(vector.info),
      ekm: await cryptoKeyPair({ privateKey: fromHex(vector.skEm), publicKey: fromHex(vector.pkEm) }),
    });
    expect(hex(new Uint8Array(sender.enc))).toBe(vector.enc);
    for (const item of vector.encryptions) {
      expect(hex(new Uint8Array(await sender.seal(fromHex(item.pt) as Uint8Array<ArrayBuffer>, fromHex(item.aad) as Uint8Array<ArrayBuffer>)))).toBe(item.ct);
    }
  });

  test("opens the published ciphertexts", async () => {
    const recipient = await suite.createRecipientContext({
      recipientKey: await importPrivateKey(fromHex(vector.skRm)),
      enc: fromHex(vector.enc),
      senderPublicKey: await importPublicKey(fromHex(vector.pkSm)),
      info: fromHex(vector.info),
    });
    for (const item of vector.encryptions) {
      expect(hex(new Uint8Array(await recipient.open(fromHex(item.ct) as Uint8Array<ArrayBuffer>, fromHex(item.aad) as Uint8Array<ArrayBuffer>)))).toBe(item.pt);
    }
  });
});
