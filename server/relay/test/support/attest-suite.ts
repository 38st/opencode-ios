// App Attest with APP_ATTEST=required, run in workerd (test/workers) and against the Node entry point
// (test/node). The relay trusts only the fixture's test root.
import { describe, expect, test } from "vitest";
import { base64, developmentAAGUID, type AttestDevice, type AttestFixture } from "./attest-fixture.ts";

export interface AttestTarget {
  relay(path: string, init?: RequestInit & { ip?: string }): Promise<Response>;
  readonly fixture: AttestFixture;
  readonly bundleID: string;
}

const sha256 = async (bytes: Uint8Array) => new Uint8Array(await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)));
const hex = (bytes: number) => Array.from(crypto.getRandomValues(new Uint8Array(bytes)), (byte) => byte.toString(16).padStart(2, "0")).join("");
let ipCounter = 0;
const freshIP = () => `192.0.2.${(ipCounter = (ipCounter % 250) + 1)}`;

export function attestSuite(target: () => AttestTarget) {
  const t = () => target();
  const post = (path: string, body: unknown, headers: Record<string, string> = {}) =>
    t().relay(path, { method: "POST", headers: { "content-type": "application/json", ...headers }, body: typeof body === "string" ? body : JSON.stringify(body), ip: freshIP() });

  async function challenge(): Promise<string> {
    const response = await post("/v1/attest/challenge", {});
    expect(response.status).toBe(201);
    return ((await response.json()) as { challenge: string }).challenge;
  }
  async function attestKey(device: AttestDevice, tamper: Parameters<AttestDevice["attest"]>[1] = {}, keyID = device.keyID) {
    const value = await challenge();
    const attestation = await device.attest(await sha256(new TextEncoder().encode(value)), tamper);
    return post("/v1/attest/keys", { keyID, challenge: value, attestation: base64(attestation) });
  }
  async function attested(): Promise<AttestDevice> {
    const device = await t().fixture.device();
    expect((await attestKey(device)).status).toBe(201);
    return device;
  }
  /** A registration body with a fresh challenge, and its assertion headers. */
  async function registration(device: AttestDevice, counter: number, tamper: Parameters<AttestDevice["assert"]>[2] = {}, extra: Record<string, unknown> = {}) {
    const body = JSON.stringify({ apnsToken: "0" + hex(32).slice(1), env: "sandbox", bundleID: t().bundleID, challenge: await challenge(), ...extra });
    const assertion = await device.assert(await sha256(new TextEncoder().encode(body)), counter, tamper);
    return { body, headers: { "x-app-attest-key": device.keyID, "x-app-attest-assertion": base64(assertion) } };
  }
  const error = async (response: Response) => ((await response.json()) as { error?: string }).error;

  describe("App Attest: attestation", () => {
    test("a challenge is single-use and well formed", async () => {
      expect(await challenge()).toMatch(/^atc_[A-Za-z0-9_-]{43}$/);
    });
    test("stores a valid attestation once", async () => {
      const device = await t().fixture.device();
      expect((await attestKey(device)).status).toBe(201);
      const again = await attestKey(device);
      expect(again.status).toBe(409);
    });
    test("refuses tampered attestations", async () => {
      const cases = [
        { untrusted: true },
        { expired: true },
        { appID: "TEAMTEST01.com.example.other" },
        { counter: 1 },
        { aaguid: developmentAAGUID },
        { credentialID: new Uint8Array(32) },
        { clientDataHash: new Uint8Array(32) },
      ];
      for (const tamper of cases) {
        const response = await attestKey(await t().fixture.device(), tamper);
        expect([response.status, await error(response)], JSON.stringify(Object.keys(tamper))).toEqual([401, "attestation_invalid"]);
      }
      const other = await t().fixture.device();
      const mismatched = await attestKey(await t().fixture.device(), {}, other.keyID);
      expect(await error(mismatched)).toBe("attestation_invalid");
    });
    test("refuses unknown, reused and malformed challenges", async () => {
      const device = await t().fixture.device();
      const value = await challenge();
      const attestation = base64(await device.attest(await sha256(new TextEncoder().encode(value))));
      const unknown = await post("/v1/attest/keys", { keyID: device.keyID, challenge: "atc_" + "A".repeat(43), attestation });
      expect([unknown.status, await error(unknown)]).toEqual([401, "challenge_invalid"]);
      expect((await post("/v1/attest/keys", { keyID: device.keyID, challenge: value, attestation })).status).toBe(201);
      const reused = await post("/v1/attest/keys", { keyID: device.keyID, challenge: value, attestation });
      expect(await error(reused)).toBe("challenge_invalid");
      expect((await post("/v1/attest/keys", { keyID: device.keyID, challenge: value, attestation: "%%%" })).status).toBe(400);
      expect((await post("/v1/attest/keys", { keyID: device.keyID, challenge: await challenge(), attestation: base64(new Uint8Array([0xa1, 0x01])) })).status).toBe(401);
    });
  });

  describe("App Attest: registration", () => {
    test("registers with a valid assertion, and counters must grow", async () => {
      const device = await attested();
      const first = await registration(device, 1);
      expect((await post("/v1/devices", first.body, first.headers)).status).toBe(201);
      const replayedBody = await post("/v1/devices", first.body, first.headers);
      expect(await error(replayedBody)).toBe("challenge_invalid");
      const sameCounter = await registration(device, 1);
      expect(await error(await post("/v1/devices", sameCounter.body, sameCounter.headers))).toBe("attestation_invalid");
      const next = await registration(device, 5);
      expect((await post("/v1/devices", next.body, next.headers)).status).toBe(201);
      const lower = await registration(device, 4);
      expect(await error(await post("/v1/devices", lower.body, lower.headers))).toBe("attestation_invalid");
    });
    test("refuses registrations without an assertion or a known key", async () => {
      const response = await post("/v1/devices", { apnsToken: "0" + hex(32).slice(1), env: "sandbox", bundleID: t().bundleID });
      expect([response.status, await error(response)]).toEqual([401, "attestation_required"]);
      const stranger = await t().fixture.device();
      const unknown = await registration(stranger, 1);
      expect(await error(await post("/v1/devices", unknown.body, unknown.headers))).toBe("attest_key_unknown");
    });
    test("refuses assertions over other bytes, for another app, or with a stale challenge", async () => {
      const device = await attested();
      const otherBody = await registration(device, 1, { clientDataHash: new Uint8Array(32) });
      expect(await error(await post("/v1/devices", otherBody.body, otherBody.headers))).toBe("attestation_invalid");
      const otherApp = await registration(device, 2, { appID: "TEAMTEST01.com.example.other" });
      expect(await error(await post("/v1/devices", otherApp.body, otherApp.headers))).toBe("attestation_invalid");
      const edited = await registration(device, 3);
      const tampered = edited.body.replace(/"env":"sandbox"/, '"env":"production"');
      expect(await error(await post("/v1/devices", tampered, edited.headers))).toBe("attestation_invalid");
      const noChallenge = await registration(device, 4, {}, { challenge: undefined });
      expect(await error(await post("/v1/devices", noChallenge.body, noChallenge.headers))).toBe("challenge_invalid");
      const valid = await registration(device, 5);
      expect((await post("/v1/devices", valid.body, valid.headers)).status).toBe(201);
    });
  });
}
