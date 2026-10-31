import { generateKeyPairSync, verify } from "node:crypto";
import { DatabaseSync } from "node:sqlite";
import { describe, expect, test } from "vitest";
import { CONTRACT } from "../../../contracts/src/constants.ts";
import { activityState } from "../../src/activity-state.ts";
import { createApp } from "../../src/app.ts";
import { mapResponse } from "../../src/apns/delivery.ts";
import { Http2Sender } from "../../src/apns/http2-sender.ts";
import { alertRequest } from "../../src/apns/request.ts";
import { signProviderToken, TokenCache, TOKEN_LIFETIME } from "../../src/apns/token.ts";
import { APPLE_APP_ATTEST_ROOT } from "../../src/attest/apple-root.ts";
import { pemCertificates } from "../../src/attest/x509.ts";
import { ConfigError, readConfig } from "../../src/config.ts";
import { hitCounters, type CounterStorage, type LimitRule } from "../../src/limiter.ts";
import { formatLog } from "../../src/log.ts";
import { clientAddress, parseTrustProxy, startNodeRelay } from "../../src/node-server.ts";
import { SqliteLimiter } from "../../src/sql-sqlite.ts";
import { attestFixture } from "../support/attest-fixture.ts";
import { envelope } from "../support/suite.ts";
import { BUNDLE_ID, KEY_ID, TEAM_ID } from "../support/fixture.ts";
import { startMockApns } from "../support/mock-apns.ts";

const keys = () => {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  return { pem: privateKey.export({ type: "pkcs8", format: "pem" }).toString(), publicKey, spki: publicKey.export({ type: "spki", format: "pem" }).toString() };
};
const env = (pem: string, extra: Record<string, string> = {}) => ({ APNS_TEAM_ID: TEAM_ID, APNS_KEY_ID: KEY_ID, APNS_PRIVATE_KEY: pem, ALLOWED_BUNDLE_IDS: BUNDLE_ID, ...extra });

describe("rate limits with the production values", () => {
  const rules: LimitRule[] = [
    { windowSeconds: 60, max: CONTRACT.limits.alertsPerMinute },
    { windowSeconds: 86_400, max: CONTRACT.limits.alertsPerDay },
  ];
  const memory = (): CounterStorage => {
    const map = new Map<string, number>();
    return {
      get: async (key) => map.get(key) as never,
      put: async (entries) => void Object.entries(entries).forEach(([key, value]) => map.set(key, value)),
      list: async () => new Map(map) as never,
      delete: async (names) => names.filter((name) => map.delete(name)).length,
    };
  };
  const implementations = {
    "Durable Object counters": () => {
      const storage = memory();
      return (now: number) => hitCounters(storage, rules, now);
    },
    "SQLite (Node)": () => {
      const limiter = new SqliteLimiter(new DatabaseSync(":memory:"));
      return (now: number) => limiter.hit("device:x", rules, now);
    },
  };
  for (const [name, make] of Object.entries(implementations)) {
    test(`${name}: 30 a minute and 500 a day`, async () => {
      const hit = make();
      const day = 1_800_028_800; // a UTC day boundary
      let allowed = 0, minute = 0;
      // Fill minute after minute until the day is used up.
      while (allowed < 500) {
        const now = day + minute * 60;
        for (let index = 0; index < 30; index++) {
          if (await hit(now)) allowed++;
        }
        expect(await hit(now + 1)).toBe(false);
        minute++;
      }
      expect(allowed).toBe(500);
      expect(await hit(day + minute * 60)).toBe(false);
      expect(await hit(day + 86_400)).toBe(true);
    });
  }
});

describe("provider tokens", () => {
  test("are ES256 JWTs APNs can verify", async () => {
    const { pem, publicKey } = keys();
    const token = await signProviderToken({ teamID: TEAM_ID, keyID: KEY_ID, privateKey: pem }, 1_800_000_000);
    const [header, claims, signature] = token.split(".") as [string, string, string];
    expect(JSON.parse(Buffer.from(header, "base64url").toString())).toEqual({ alg: "ES256", kid: KEY_ID });
    expect(JSON.parse(Buffer.from(claims, "base64url").toString())).toEqual({ iss: TEAM_ID, iat: 1_800_000_000 });
    expect(verify("sha256", Buffer.from(`${header}.${claims}`), { key: publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(signature, "base64url"))).toBe(true);
  });

  test("are cached for 50 minutes, shared by concurrent callers, and replaced only when refused", async () => {
    let now = 1_800_000_000, minted = 0;
    const cache = new TokenCache(async (issuedAt) => `token-${++minted}-${issuedAt}`, () => now);
    const [a, b] = await Promise.all([cache.issued(), cache.issued()]);
    expect(a).toEqual(b);
    expect(minted).toBe(1);
    now += TOKEN_LIFETIME - 1;
    expect((await cache.issued()).token).toBe(a.token);
    now += 1;
    const renewed = await cache.issued();
    expect(renewed.token).not.toBe(a.token);
    cache.reject(a.token);
    expect((await cache.issued()).token).toBe(renewed.token);
    cache.reject(renewed.token);
    expect((await cache.issued()).token).not.toBe(renewed.token);
    expect(TOKEN_LIFETIME).toBe(3000);
  });
});

describe("APNs", () => {
  test.each([
    [200, undefined, "delivered"],
    [410, "Unregistered", "gone"],
    [410, undefined, "gone"],
    [400, "BadDeviceToken", "gone"],
    [429, "TooManyRequests", "throttled"],
    [400, "DeviceTokenNotForTopic", "rejected"],
    [403, "ExpiredProviderToken", "rejected"],
    [413, "PayloadTooLarge", "rejected"],
    [500, "InternalServerError", "rejected"],
    [503, "ServiceUnavailable", "rejected"],
  ] as const)("%i %s is %s", (status, reason, result) => {
    expect(mapResponse({ status, ...(reason ? { reason } : {}) })).toBe(result);
  });

  test("approvals expire within their lifetime and passive alerts are silent", () => {
    const device = { id: "dev_x", secretHash: "", apnsToken: "ab".repeat(32), env: "sandbox" as const, bundleID: BUNDLE_ID };
    const now = 1_800_000_000;
    const approval = alertRequest(device, { kind: "permission", priority: 10, collapse: "c", thread: "t", expiresAt: now + 86_400, envelope: envelope("permission", now + 86_400) }, now);
    expect(approval.headers["apns-expiration"]).toBe(String(now + 600));
    const resolved = alertRequest(device, { kind: "resolved", priority: 5, collapse: "c", thread: "t", expiresAt: now + 60, envelope: envelope("resolved", now + 60) }, now);
    expect(resolved.headers["apns-expiration"]).toBe(String(now + 60));
    expect(JSON.parse(resolved.body).aps).not.toHaveProperty("sound");
  });

  test("the HTTP/2 sender reconnects after the server closes its session", async () => {
    const { pem, spki } = keys();
    const mock = await startMockApns({ teamID: TEAM_ID, keyID: KEY_ID, publicKeyPEM: spki, bundleIDs: [BUNDLE_ID] });
    const sender = new Http2Sender({ teamID: TEAM_ID, keyID: KEY_ID, privateKey: pem, sandboxURL: mock.h2URL, productionURL: mock.h2URL });
    const token = await signProviderToken({ teamID: TEAM_ID, keyID: KEY_ID, privateKey: pem }, Math.floor(Date.now() / 1000));
    const device = { id: "dev_x", secretHash: "", apnsToken: "ab".repeat(32), env: "sandbox" as const, bundleID: BUNDLE_ID };
    const now = Math.floor(Date.now() / 1000);
    const request = alertRequest(device, { kind: "test", priority: 10, collapse: "c", thread: "t", expiresAt: now + 60, envelope: envelope("test", now + 60) }, now);
    try {
      expect((await sender.send(request, token)).status).toBe(200);
      mock.dropConnections();
      await new Promise((resolve) => setTimeout(resolve, 50));
      expect((await sender.send(request, token)).status).toBe(200);
      expect(mock.requests.map((item) => [item.protocol, item.problems.length])).toEqual([["h2", 0], ["h2", 0]]);
    } finally {
      sender.close();
      await mock.close();
    }
  });
});

describe("Live Activity state", () => {
  const state = { phase: "needsInput", step: 4, toolGlyph: "question", startedAt: 1_800_000_000, updatedAt: 1_800_000_030.5 };
  test("accepts exactly the coarse fields", () => {
    expect(activityState(state)).toEqual(state);
    for (const bad of [{ ...state, title: "x" }, { ...state, phase: "thinking" }, { ...state, toolGlyph: "pencil" }, { ...state, step: -1 }, { ...state, step: 1.5 }, { ...state, startedAt: "now" }, { phase: "running" }, null, []]) {
      expect(activityState(bad)).toBeUndefined();
    }
  });
});

describe("configuration", () => {
  test("defaults to Apple's hosts and the contract's limits", () => {
    const config = readConfig(env("pem"));
    expect(config.apns.sandboxURL).toBe("https://api.sandbox.push.apple.com");
    expect(config.apns.productionURL).toBe("https://api.push.apple.com");
    expect(config.limits).toEqual(CONTRACT.limits);
    expect(config.appAttest).toMatchObject({ mode: "off", environment: "production", appIDs: [`${TEAM_ID}.${BUNDLE_ID}`] });
    expect(config.appAttest.roots).toHaveLength(1);
    expect([...config.bundleIDs]).toEqual([BUNDLE_ID]);
  });
  test("accepts test limits only in test mode, and only valid ones", () => {
    const limits = JSON.stringify({ alertsPerMinute: 3 });
    expect(() => readConfig(env("pem", { RELAY_TEST_LIMITS: limits }))).toThrow(/RELAY_TEST_MODE/);
    expect(readConfig(env("pem", { RELAY_TEST_MODE: "1", RELAY_TEST_LIMITS: limits })).limits.alertsPerMinute).toBe(3);
    for (const bad of ["{", "[]", JSON.stringify({ alertsPerHour: 3 }), JSON.stringify({ alertsPerDay: 0 }), JSON.stringify({ alertsPerDay: 1.5 }), JSON.stringify({ alertsPerDay: "9" })]) {
      expect(() => readConfig(env("pem", { RELAY_TEST_MODE: "1", RELAY_TEST_LIMITS: bad }))).toThrow(ConfigError);
    }
    expect(readConfig(env("pem", { RELAY_TEST_MODE: "1" })).limits).toEqual(CONTRACT.limits);
  });

  test("behind a proxy, the client address is Fly-Client-IP or the rightmost X-Forwarded-For entry", () => {
    const headers = { "fly-client-ip": "203.0.113.5", "x-forwarded-for": "198.51.100.66, 192.0.2.10" };
    expect(clientAddress(headers, "10.0.0.1", "fly")).toBe("203.0.113.5");
    expect(clientAddress(headers, "10.0.0.1", "forwarded")).toBe("192.0.2.10");
    expect(clientAddress(headers, "10.0.0.1", undefined)).toBe("10.0.0.1");
    expect(clientAddress({}, "10.0.0.1", "fly")).toBe("10.0.0.1");
    expect(parseTrustProxy(undefined)).toBeUndefined();
    expect(parseTrustProxy("fly")).toBe("fly");
    expect(() => parseTrustProxy("1")).toThrow(ConfigError);
  });

  test("refuses a missing key or an unknown App Attest mode", () => {
    expect(() => readConfig({ APNS_TEAM_ID: TEAM_ID, APNS_KEY_ID: KEY_ID })).toThrow(ConfigError);
    expect(() => readConfig(env("pem", { APP_ATTEST: "maybe" }))).toThrow(ConfigError);
    expect(() => readConfig(env("pem", { APP_ATTEST_ENVIRONMENT: "staging" }))).toThrow(ConfigError);
  });
  test("pins Apple's App Attest root unless test mode supplies one", async () => {
    const { roots } = readConfig(env("pem")).appAttest;
    const fingerprint = new Uint8Array(await crypto.subtle.digest("SHA-256", pemCertificates(APPLE_APP_ATTEST_ROOT)[0]!));
    expect(Buffer.from(fingerprint).toString("hex")).toBe("1cb9823ba28ba6ad2d33a006941de2ae4f513ef1d4e831b9f7e0fa7b6242c932");
    expect(roots[0]!.isCA).toBe(true);
    const fixture = await attestFixture(`${TEAM_ID}.${BUNDLE_ID}`);
    expect(() => readConfig(env("pem", { APP_ATTEST_TEST_ROOTS: fixture.rootPEM }))).toThrow(/RELAY_TEST_MODE/);
    expect(readConfig(env("pem", { RELAY_TEST_MODE: "1", APP_ATTEST_TEST_ROOTS: fixture.rootPEM })).appAttest.roots).toHaveLength(1);
    expect(() => readConfig(env("pem", { RELAY_TEST_MODE: "1", APP_ATTEST_TEST_ROOTS: "not a certificate" }))).toThrow(ConfigError);
  });
  test("health reports a configuration it cannot use", async () => {
    const app = createApp({ resolve: () => { throw new ConfigError("APNS_PRIVATE_KEY is not set"); }, clientIP: () => undefined });
    const response = await app.fetch(new Request("http://relay/v1/health"));
    expect(response.status).toBe(503);
    expect(await response.json()).toMatchObject({ status: "misconfigured" });
  });
  test("with App Attest required and Apple's root, registration without an assertion fails closed", async () => {
    const relay = await startNodeRelay({ env: env(keys().pem, { APP_ATTEST: "required" }), database: ":memory:" });
    try {
      const response = await fetch(`${relay.url}/v1/devices`, { method: "POST", body: JSON.stringify({ apnsToken: "ab".repeat(32), env: "sandbox", bundleID: BUNDLE_ID }) });
      expect(response.status).toBe(401);
      expect(await response.json()).toEqual({ error: "attestation_required" });
    } finally {
      await relay.close();
    }
  });
});

test("log lines keep only the allowed fields and short identifiers", () => {
  const line = formatLog("push", { kind: "permission", result: "delivered", status: 200, ...({ token: "secret" } as object) });
  expect(JSON.parse(line)).toEqual({ event: "push", kind: "permission", result: "delivered", status: 200 });
  expect(JSON.parse(formatLog("push", { kind: "x".repeat(41) }))).toEqual({ event: "push" });
});
