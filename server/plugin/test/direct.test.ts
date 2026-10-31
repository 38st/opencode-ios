import { chmod, writeFile } from "node:fs/promises";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { base64url, CONTRACT, type Envelope } from "../contracts/src/index.ts";
import { acquireDirect, directConfig, DirectConfigError, directFromOptions, DirectSender, readKey, type DirectConfig, type DirectOptions } from "../src/direct.ts";
import type { Device } from "../src/registry.ts";
import type { PushService } from "../src/service.ts";
import { startApnsMock, testKey, verifyProviderToken, type ApnsMock } from "./apns-mock.ts";
import { FakeHost, fakeDevice, open, RpcError, startService, until } from "./fakes.ts";

const config = (keyFile: string, overrides: Partial<DirectConfig> = {}): DirectConfig => ({
  keyFile, keyID: "TESTKEY001", teamID: "TEAMID0001", bundleID: "com.example.opencode", environment: "sandbox", ...overrides,
});
const APNS_TOKEN = "ab".repeat(32);
const ACTIVITY_TOKEN = "cd".repeat(40);

let mock: ApnsMock;
let key: Awaited<ReturnType<typeof testKey>>;
const cleanup: (() => unknown)[] = [];
beforeEach(async () => {
  mock = await startApnsMock();
  key = await testKey();
});
afterEach(async () => {
  for (const run of cleanup.splice(0).reverse()) await run();
  await mock.close();
  await key.remove();
});

async function sender(options: DirectOptions = {}, overrides: Partial<DirectConfig> = {}) {
  const direct = await DirectSender.load(config(key.file, overrides), { hosts: mock.hosts, sleep: async () => undefined, ...options });
  cleanup.push(() => direct.close());
  return direct;
}

const device = (overrides: Partial<Device> = {}): Device => ({
  keyID: "kid_direct_000001", transport: "direct", apnsToken: APNS_TOKEN, bundleID: "com.example.opencode", environment: "sandbox",
  devicePublicKey: "", appServerRef: "srv", label: "", prefs: { permission: true, question: true, finished: true, failed: true }, registeredAt: 0, ...overrides,
});
const envelope: Envelope = { v: 1, kid: "kid_direct_000001", kind: "permission", exp: 4_000_000_000, enc: "ZW5j", ct: "Y3Q", extra: "dropped" } as Envelope;
const request = (expiresAt = Math.floor(Date.now() / 1000) + 600) => ({ kind: "permission" as const, priority: 10 as const, collapse: "col_1", thread: "thr_1", expiresAt, envelope });

describe("the apns option", () => {
  test("is optional, defaults to production, and refuses malformed fields", () => {
    expect(directConfig(undefined)).toBeUndefined();
    expect(directConfig({})).toBeUndefined();
    expect(directConfig({ apns: { keyFile: "/Users/Shared/k.p8", keyID: "ABC123DEFG", teamID: "TEAM123456", bundleID: "com.example.app" } })).toEqual({
      keyFile: "/Users/Shared/k.p8", keyID: "ABC123DEFG", teamID: "TEAM123456", bundleID: "com.example.app", environment: "production",
    });
    for (const [apns, field] of [
      ["yes", "apns"],
      [{ keyID: "ABC123DEFG", teamID: "TEAM123456", bundleID: "com.example.app" }, "keyFile"],
      [{ keyFile: "/k.p8", keyID: "short", teamID: "TEAM123456", bundleID: "com.example.app" }, "keyID"],
      [{ keyFile: "/k.p8", keyID: "ABC123DEFG", teamID: "TEAM123456", bundleID: "app" }, "bundleID"],
      [{ keyFile: "/k.p8", keyID: "ABC123DEFG", teamID: "TEAM123456", bundleID: "com.example.app", environment: "dev" }, "environment"],
      [{ keyFile: "/k.p8", keyID: "ABC123DEFG", teamID: "TEAM123456", bundleID: "com.example.app", origin: "https://apns.example.com" }, "origin"],
      [{ keyFile: "/k.p8", keyID: "ABC123DEFG", teamID: "TEAM123456", bundleID: "com.example.app", origin: "http://10.0.0.1:443" }, "origin"],
    ] as const) {
      expect(() => directConfig({ apns })).toThrow(new RegExp(field));
    }
    const local = { keyFile: "/k.p8", keyID: "ABC123DEFG", teamID: "TEAM123456", bundleID: "com.example.app", origin: "http://127.0.0.1:4430/" };
    expect(directConfig({ apns: local })?.origin).toBe("http://127.0.0.1:4430");
  });

  test("readKey accepts a key only its owner can read, and refuses group or other access and non-PEM files", async () => {
    expect(await readKey(key.file)).toBe(key.pem);
    await chmod(key.file, 0o644);
    await expect(readKey(key.file)).rejects.toThrow(/chmod 600/);
    await chmod(key.file, 0o640);
    await expect(readKey(key.file)).rejects.toBeInstanceOf(DirectConfigError);
    await chmod(key.file, 0o600);
    await writeFile(key.file, "not a key");
    await expect(readKey(key.file)).rejects.toThrow(/not a \.p8 key/);
    await expect(readKey(`${key.file}.missing`)).rejects.toThrow(/does not exist/);
  });

  test("a bad configuration is logged without the key and leaves direct mode off", async () => {
    const logs: string[] = [];
    await chmod(key.file, 0o644);
    const options = { apns: { keyFile: key.file, keyID: "TESTKEY001", teamID: "TEAMID0001", bundleID: "com.example.opencode" } };
    expect(await directFromOptions(options, (message) => logs.push(message))).toBeUndefined();
    await chmod(key.file, 0o600);
    await writeFile(key.file, "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----\n");
    expect(await directFromOptions(options, (message) => logs.push(message))).toBeUndefined();
    expect(logs).toEqual([expect.stringMatching(/^direct mode off: .*chmod 600/), "direct mode off: apns.keyFile is not a valid P-256 .p8 key"]);
    expect(logs.join("\n")).not.toContain("PRIVATE KEY");
  });

  test("instances in one process share one sender per configuration until the last releases it", async () => {
    const first = await acquireDirect(config(key.file), { hosts: mock.hosts });
    const second = await acquireDirect(config(key.file), { hosts: mock.hosts });
    expect(second.sender).toBe(first.sender);
    first.release();
    first.release();
    second.release();
    const third = await acquireDirect(config(key.file), { hosts: mock.hosts });
    expect(third.sender).not.toBe(first.sender);
    third.release();
  });
});

describe("DirectSender against a local APNs", () => {
  test("sends the relay's alert request with a signed provider token, reused across pushes on one connection", async () => {
    let now = 1_800_000_000_000;
    const direct = await sender({ now: () => now });
    expect(await direct.push(device(), request(1_800_000_600))).toEqual({ result: "delivered", attempts: 1 });
    now += 60_000;
    expect(await direct.push(device(), { ...request(1_800_000_600), collapse: "col_2" })).toEqual({ result: "delivered", attempts: 1 });
    const [first, second] = mock.calls;
    expect(first!.path).toBe(`/3/device/${APNS_TOKEN}`);
    expect(first!.headers).toMatchObject({
      "apns-topic": "com.example.opencode",
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-collapse-id": "col_1",
      // The permission kind's TTL caps the push's own expiry.
      "apns-expiration": String(1_800_000_000 + CONTRACT.kinds.permission.ttlSeconds),
      "content-type": "application/json",
    });
    expect(second!.headers["apns-collapse-id"]).toBe("col_2");
    expect(first!.body).toEqual({
      aps: { alert: { body: CONTRACT.kinds.permission.alert }, "mutable-content": 1, category: "OPEN_ONLY", "thread-id": "thr_1", "interruption-level": "time-sensitive", sound: "default" },
      oc: { v: 1, kid: "kid_direct_000001", kind: "permission", exp: 4_000_000_000, enc: "ZW5j", ct: "Y3Q" },
    });
    const token = /^bearer (.+)$/.exec(first!.headers.authorization!)![1]!;
    expect(second!.headers.authorization).toBe(first!.headers.authorization);
    const jwt = await verifyProviderToken(token, key.publicKey);
    expect(jwt).toEqual({ valid: true, header: { alg: "ES256", kid: "TESTKEY001" }, claims: { iss: "TEAMID0001", iat: 1_800_000_000 } });
    expect(mock.sessions()).toBe(1);
    expect(new Set(mock.calls.map((call) => call.session))).toEqual(new Set([1]));

    // After 50 minutes a new token is minted.
    now += CONTRACT.apns.tokenCacheSeconds * 1000;
    await direct.push(device(), request(1_900_000_000));
    const third = /^bearer (.+)$/.exec(mock.calls[2]!.headers.authorization!)![1]!;
    expect(third).not.toBe(token);
    expect((await verifyProviderToken(third, key.publicKey)).claims.iat).toBe(1_800_000_000 + 60 + CONTRACT.apns.tokenCacheSeconds);
  });

  test("retries a 500 with backoff, and maps 410, BadDeviceToken and 429", async () => {
    const delays: number[] = [];
    const direct = await sender({ sleep: async (milliseconds) => void delays.push(milliseconds) });
    mock.script(APNS_TOKEN, { status: 500, reason: "InternalServerError" }, { status: 503 }, { status: 200 });
    expect(await direct.push(device(), request())).toEqual({ result: "delivered", attempts: 3 });
    expect(delays).toEqual([CONTRACT.plugin.retryBaseMilliseconds, CONTRACT.plugin.retryBaseMilliseconds * 2]);
    mock.script(APNS_TOKEN, { status: 410, reason: "Unregistered" });
    expect(await direct.push(device(), request())).toEqual({ result: "gone", attempts: 1 });
    mock.script(APNS_TOKEN, { status: 400, reason: "BadDeviceToken" });
    expect(await direct.push(device(), request())).toEqual({ result: "gone", attempts: 1 });
    mock.script(APNS_TOKEN, { status: 429, reason: "TooManyRequests" });
    expect(await direct.push(device(), request())).toEqual({ result: "throttled", attempts: 1 });
    mock.script(APNS_TOKEN, { status: 400, reason: "BadCollapseId" });
    expect(await direct.push(device(), request())).toEqual({ result: "rejected", attempts: 1 });
  });

  test("an expired provider token is replaced and the push retried", async () => {
    let now = 1_800_000_000_000;
    const direct = await sender({ now: () => now, sleep: async () => void (now += 1000) });
    mock.script(APNS_TOKEN, { status: 403, reason: "ExpiredProviderToken" }, { status: 200 });
    expect(await direct.push(device(), request(1_800_000_600))).toEqual({ result: "delivered", attempts: 2 });
    expect(mock.calls[0]!.headers.authorization).not.toBe(mock.calls[1]!.headers.authorization);
  });

  test("an unreachable APNs is retried and reported as unreachable", async () => {
    const direct = await sender();
    await mock.close();
    expect(await direct.push(device(), request())).toEqual({ result: "unreachable", attempts: CONTRACT.plugin.retries + 1 });
    mock = await startApnsMock();
  });

  test("a device registered for another bundle ID or environment is not sent to", async () => {
    const direct = await sender();
    expect(await direct.push(device({ bundleID: "com.other.app" }), request())).toEqual({ result: "rejected", attempts: 0 });
    expect(await direct.push(device({ environment: "production" }), request())).toEqual({ result: "rejected", attempts: 0 });
    expect(mock.calls).toEqual([]);
  });

  test("sends Live Activity updates to the activity topic", async () => {
    const direct = await sender({ now: () => 1_800_000_000_000 });
    const state = { phase: "running", step: 2, toolGlyph: "shell", startedAt: 1_799_999_000, updatedAt: 1_800_000_000 };
    expect(await direct.activity(ACTIVITY_TOKEN, { ref: "act_1", event: "end", state, staleAt: 1_800_000_300, dismissAt: 1_800_000_900, priority: 10 })).toEqual({ result: "delivered", attempts: 1 });
    const [call] = mock.calls;
    expect(call!.path).toBe(`/3/device/${ACTIVITY_TOKEN}`);
    expect(call!.headers).toMatchObject({ "apns-topic": "com.example.opencode.push-type.liveactivity", "apns-push-type": "liveactivity", "apns-priority": "10", "apns-expiration": "1800000300" });
    expect(call!.headers["apns-collapse-id"]).toBeUndefined();
    expect(call!.body).toEqual({ aps: { timestamp: 1_800_000_000, event: "end", "content-state": state, "stale-date": 1_800_000_300, "dismissal-date": 1_800_000_900 } });
  });
});

describe("direct devices over RPC", () => {
  const services: PushService[] = [];
  afterEach(async () => {
    for (const service of services.splice(0)) await service.stop();
  });
  async function server(direct?: DirectSender) {
    const harness = await startService(new FakeHost(), direct ? { direct } : {});
    services.push(harness.service);
    return harness.host;
  }
  const registration = async (extra: Record<string, unknown> = {}) => {
    const phone = await fakeDevice();
    return {
      phone,
      input: { transport: "direct", apnsToken: APNS_TOKEN.toUpperCase(), bundleID: "com.example.opencode", environment: "sandbox", devicePublicKey: base64url.encode(phone.keys.publicKey), keyID: phone.keyID, appServerRef: "srv_home_mac", label: "Direct iPhone", ...extra },
    };
  };
  const refused = async (host: FakeHost, input: unknown, field: string, message: RegExp) => {
    const error = await host.call("registerDevice", input).catch((caught: unknown) => caught);
    expect(error).toBeInstanceOf(RpcError);
    expect(error).toMatchObject({ type: "invalid", data: { field } });
    expect((error as Error).message).toMatch(message);
  };

  test("are refused when direct mode is not configured", async () => {
    const host = await server();
    expect((await host.call("status")).direct).toEqual({ available: false });
    await refused(host, (await registration()).input, "transport", /not configured/);
    await refused(host, (await registration({ transport: "pigeon" })).input, "transport", /relay" or "direct/);
  });

  test("must match the configured bundle ID and environment", async () => {
    const host = await server(await sender());
    await refused(host, (await registration({ bundleID: "com.other.app" })).input, "bundleID", /does not match/);
    await refused(host, (await registration({ environment: "production" })).input, "environment", /sandbox/);
    await refused(host, (await registration({ apnsToken: "xyz" })).input, "apnsToken", /hex/);
    expect((await host.call("listDevices")).devices).toEqual([]);
  });

  test("register, report their transport, receive tests and Live Activities, and never expose a key", async () => {
    const host = await server(await sender());
    const status = await host.call("status");
    expect(status.direct).toEqual({ available: true, bundleID: "com.example.opencode", environment: "sandbox" });
    const { phone, input } = await registration();
    const { serverPublicKey } = await host.call("registerDevice", input);
    const { devices } = await host.call("listDevices");
    expect(devices).toEqual([{ keyID: phone.keyID, transport: "direct", label: "Direct iPhone", appServerRef: "srv_home_mac", bundleID: "com.example.opencode", environment: "sandbox", prefs: expect.any(Object), registeredAt: expect.any(Number) }]);

    expect(await host.call("test", { keyID: phone.keyID })).toEqual({ result: "delivered", attempts: 1 });
    const push = mock.calls[0]!;
    expect(push.path).toBe(`/3/device/${APNS_TOKEN}`);
    expect(push.headers).toMatchObject({ "apns-topic": "com.example.opencode", "apns-priority": "10", "apns-push-type": "alert" });
    const opened = await open(push.body.oc as Envelope, phone, serverPublicKey);
    expect(opened.payload).toMatchObject({ kind: "test", server: "srv_home_mac" });

    const activity = { keyID: phone.keyID, activityRef: "act_1", sessionID: "ses_root" };
    const error = await host.call("registerActivity", activity).catch((caught: unknown) => caught);
    expect(error).toMatchObject({ type: "invalid", data: { field: "expiresAt" } });
    const expiresAt = Math.floor(Date.now() / 1000) + 3600;
    expect(await host.call("registerActivity", { ...activity, pushToken: ACTIVITY_TOKEN, expiresAt })).toEqual({ registered: true });
    host.emit({ id: "evt_start", type: "session.execution.started", created: Date.now(), data: { sessionID: "ses_root" } });
    await until(() => mock.calls.length === 2);
    expect(mock.calls[1]!.path).toBe(`/3/device/${ACTIVITY_TOKEN}`);
    expect(mock.calls[1]!.headers["apns-topic"]).toBe("com.example.opencode.push-type.liveactivity");
    expect(mock.calls[1]!.body.aps).toMatchObject({ event: "update", "content-state": { phase: "running", step: 0, toolGlyph: "none" } });

    const outputs = JSON.stringify([status, await host.call("status"), await host.call("listDevices")]);
    for (const secret of [key.pem.split("\n")[1]!, key.file, APNS_TOKEN, ACTIVITY_TOKEN]) expect(outputs).not.toContain(secret);
  });

  test("an APNs 410 removes the registration", async () => {
    const host = await server(await sender());
    const { phone, input } = await registration();
    await host.call("registerDevice", input);
    mock.script(APNS_TOKEN, { status: 410, reason: "Unregistered" });
    expect(await host.call("test", { keyID: phone.keyID })).toEqual({ result: "gone", attempts: 1 });
    expect((await host.call("listDevices")).devices).toEqual([]);
  });

  test("a direct device stays registered but unreachable while direct mode is off", async () => {
    const storage = new FakeHost().storage;
    const on = await startService(new FakeHost("/work/project", storage), { direct: await sender() });
    services.push(on.service);
    const { phone, input } = await registration();
    await on.host.call("registerDevice", input);
    await on.service.stop();
    const off = await startService(new FakeHost("/work/project", storage));
    services.push(off.service);
    expect(await off.host.call("test", { keyID: phone.keyID })).toEqual({ result: "unreachable", attempts: 0 });
    expect((await off.host.call("listDevices")).devices).toHaveLength(1);
  });
});

describe("the relay client", () => {
  test("never follows a redirect, which would carry the send token elsewhere", async () => {
    const { RelayClient } = await import("../src/relay.ts");
    const seen: RequestInit[] = [];
    const client = new RelayClient({ fetch: (async (_url: string, init: RequestInit) => (seen.push(init), Response.json({ result: "delivered" }))) as unknown as typeof fetch });
    const relayDevice = device({ transport: "relay", sendToken: "ocs_test_token_redirect", relayURL: "https://relay.example.com" });
    expect(await client.push(relayDevice, request())).toEqual({ result: "delivered", attempts: 1 });
    expect(seen[0]!.redirect).toBe("error");
  });
});
