// The relay's behaviour, written once and run against the Workers runtime (test/workers) and the
// Node entry point (test/node). It talks to the relay and the mock APNs server over fetch only.
import { beforeEach, describe, expect, test } from "vitest";
import * as base64url from "../../../contracts/src/base64url.ts";
import { CONTRACT, KINDS, kindPolicy, type Kind } from "../../../contracts/src/constants.ts";
import type { MockRequest } from "./fixture.ts";

export interface Target {
  /** Calls the relay. `ip` is sent as CF-Connecting-IP and Fly-Client-IP. */
  relay(path: string, init?: RequestInit & { ip?: string }): Promise<Response>;
  readonly mockURL: string;
  readonly bundleID: string;
  /** The protocol the relay's APNs sender uses: fetch in workerd is HTTP/1.1, node:http2 is h2. */
  readonly protocol: "h1" | "h2";
  readonly limits: typeof CONTRACT.limits;
  /** Everything the relay has logged so far. */
  logs(): string[];
}

const hex = (bytes: number) => Array.from(crypto.getRandomValues(new Uint8Array(bytes)), (byte) => byte.toString(16).padStart(2, "0")).join("");
/**
 * A 32-byte APNs token; a prefix picks the mock's reply. Without one the token starts with "0", which no
 * reply prefix does: a fully random token starts with "410" once in 4,096 and would then be Unregistered.
 */
const deviceToken = (prefix = "0") => prefix + hex(32).slice(prefix.length);
const seconds = () => Math.floor(Date.now() / 1000);
let ipCounter = 0;
const freshIP = () => `198.51.100.${(ipCounter = (ipCounter % 250) + 1)}`;

export function envelope(kind: Kind, exp: number, bucket = 512) {
  return {
    v: 1,
    kid: "kid_" + base64url.encode(crypto.getRandomValues(new Uint8Array(12))),
    kind,
    exp,
    enc: base64url.encode(crypto.getRandomValues(new Uint8Array(32))),
    ct: base64url.encode(crypto.getRandomValues(new Uint8Array(bucket + 16))),
  };
}

export function relaySuite(target: () => Target) {
  const t = () => target();
  const json = (body: unknown) => ({ method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
  const mock = async (): Promise<MockRequest[]> => ((await (await fetch(`${t().mockURL}/_mock/requests`)).json()) as { requests: MockRequest[] }).requests;

  async function register(token = deviceToken(), ip = freshIP()) {
    const response = await t().relay("/v1/devices", { ...json({ apnsToken: token, env: "sandbox", bundleID: t().bundleID }), ip });
    expect(response.status).toBe(201);
    return (await response.json()) as { deviceID: string; deviceSecret: string };
  }
  const withSecret = (secret: string, init: RequestInit = {}) => ({ ...init, headers: { ...(init.headers as Record<string, string>), authorization: `Bearer ${secret}` } });
  async function addSender(device: { deviceID: string; deviceSecret: string }) {
    const response = await t().relay(`/v1/devices/${device.deviceID}/senders`, withSecret(device.deviceSecret, { method: "POST" }));
    expect(response.status).toBe(201);
    return (await response.json()) as { senderID: string; sendToken: string };
  }
  function pushBody(kind: Kind = "permission", overrides: Record<string, unknown> = {}) {
    const exp = seconds() + 300;
    return { kind, priority: kindPolicy(kind).priority, collapse: "c_" + hex(8), thread: "t_" + hex(8), expiresAt: exp, envelope: envelope(kind, exp), ...overrides };
  }
  async function push(sendToken: string, body: unknown = pushBody()) {
    const response = await t().relay("/v1/push", withSecret(sendToken, json(body)));
    return { status: response.status, body: (await response.json()) as { result?: string; error?: string } };
  }
  async function setup(token?: string) {
    const device = await register(token);
    return { device, sender: await addSender(device) };
  }

  beforeEach(async () => {
    await fetch(`${t().mockURL}/_mock/reset`, { method: "POST" });
  });

  describe("health and routing", () => {
    test("GET /v1/health is public", async () => {
      const response = await t().relay("/v1/health");
      expect(response.status).toBe(200);
      expect(await response.json()).toMatchObject({ status: "ok" });
    });
    test("unknown routes are 404", async () => {
      const response = await t().relay("/v1/nothing");
      expect(response.status).toBe(404);
    });
  });

  describe("POST /v1/devices", () => {
    test("registers a device and returns its ID and secret", async () => {
      const { deviceID, deviceSecret } = await register();
      expect(deviceID).toMatch(/^dev_[A-Za-z0-9_-]{22}$/);
      expect(deviceSecret).toMatch(/^ocd_[A-Za-z0-9_-]{43}$/);
    });
    test("rejects invalid tokens, environments, bundles and bodies", async () => {
      const ip = freshIP();
      const post = (body: unknown) => t().relay("/v1/devices", { ...json(body), ip });
      expect((await post({ apnsToken: "xyz", env: "sandbox", bundleID: t().bundleID })).status).toBe(400);
      expect((await post({ apnsToken: deviceToken(), env: "staging", bundleID: t().bundleID })).status).toBe(400);
      expect((await post({ apnsToken: deviceToken(), env: "sandbox", bundleID: "com.example.other" })).status).toBe(403);
      expect((await t().relay("/v1/devices", { method: "POST", body: "{", ip })).status).toBe(400);
    });
    test("refuses oversized bodies", async () => {
      const response = await t().relay("/v1/devices", { ...json({ padding: "x".repeat(20_000) }), ip: freshIP() });
      expect(response.status).toBe(413);
    });
    test("limits registrations per IP address", async () => {
      const ip = "203.0.113.77";
      const attempt = () => t().relay("/v1/devices", { ...json({ apnsToken: deviceToken(), env: "sandbox", bundleID: t().bundleID }), ip });
      for (let index = 0; index < t().limits.registrationsPerHour; index++) expect((await attempt()).status).toBe(201);
      expect((await attempt()).status).toBe(429);
      expect((await t().relay("/v1/devices", { ...json({ apnsToken: deviceToken(), env: "sandbox", bundleID: t().bundleID }), ip: "203.0.113.78" })).status).toBe(201);
    });
  });

  describe("device secrets", () => {
    test("PUT rotates the token, repeatedly, only with the device secret", async () => {
      const device = await register();
      const put = (secret: string, id = device.deviceID) => t().relay(`/v1/devices/${id}`, withSecret(secret, { ...json({ apnsToken: deviceToken() }), method: "PUT" }));
      expect((await put(device.deviceSecret)).status).toBe(200);
      expect((await put(device.deviceSecret)).status).toBe(200);
      expect((await put("ocd_" + "A".repeat(43))).status).toBe(401);
      expect((await put(device.deviceSecret, "dev_" + "B".repeat(22))).status).toBe(401);
      expect((await t().relay(`/v1/devices/${device.deviceID}`, { ...json({ apnsToken: deviceToken() }), method: "PUT" })).status).toBe(401);
    });
    test("DELETE removes the device and every sender", async () => {
      const { device, sender } = await setup();
      expect((await t().relay(`/v1/devices/${device.deviceID}`, withSecret(device.deviceSecret, { method: "DELETE" }))).status).toBe(204);
      expect((await push(sender.sendToken)).status).toBe(401);
      expect((await t().relay(`/v1/devices/${device.deviceID}`, withSecret(device.deviceSecret, { method: "DELETE" }))).status).toBe(401);
    });
    test("a sender is revoked alone", async () => {
      const device = await register();
      const first = await addSender(device), second = await addSender(device);
      expect((await push(first.sendToken)).body.result).toBe("delivered");
      const removed = await t().relay(`/v1/devices/${device.deviceID}/senders/${first.senderID}`, withSecret(device.deviceSecret, { method: "DELETE" }));
      expect(removed.status).toBe(204);
      expect((await push(first.sendToken)).status).toBe(401);
      expect((await push(second.sendToken)).body.result).toBe("delivered");
    });
  });

  describe("device secrets on every device route", () => {
    const other = () => register();
    const wrong = "ocd_" + "W".repeat(43);

    test("POST …/senders needs this device's secret", async () => {
      const device = await register(), stranger = await other();
      const post = (headers: Record<string, string>) => t().relay(`/v1/devices/${device.deviceID}/senders`, { method: "POST", headers });
      expect((await post({})).status).toBe(401);
      expect((await post({ authorization: `Bearer ${wrong}` })).status).toBe(401);
      expect((await post({ authorization: `Bearer ${stranger.deviceSecret}` })).status).toBe(401);
      expect((await post({ authorization: `Bearer ${device.deviceSecret}` })).status).toBe(201);
    });

    test("DELETE …/senders/:sid needs this device's secret and never reaches another device's sender", async () => {
      const device = await register(), stranger = await other();
      const sender = await addSender(device);
      const remove = (id: string, secret?: string) =>
        t().relay(`/v1/devices/${id}/senders/${sender.senderID}`, { method: "DELETE", headers: secret ? { authorization: `Bearer ${secret}` } : {} });
      expect((await remove(device.deviceID)).status).toBe(401);
      expect((await remove(device.deviceID, wrong)).status).toBe(401);
      expect((await remove(device.deviceID, stranger.deviceSecret)).status).toBe(401);
      // Under its own ID the other device's request succeeds but touches only its own senders.
      expect((await remove(stranger.deviceID, stranger.deviceSecret)).status).toBe(204);
      expect((await push(sender.sendToken)).body.result).toBe("delivered");
    });

    test("PUT …/activities/:ref needs this device's secret", async () => {
      const device = await register(), stranger = await other();
      const put = (headers: Record<string, string>) =>
        t().relay(`/v1/devices/${device.deviceID}/activities/act_auth`, { ...json({ pushToken: deviceToken(), expiresAt: seconds() + 600 }), method: "PUT", headers: { "content-type": "application/json", ...headers } });
      expect((await put({})).status).toBe(401);
      expect((await put({ authorization: `Bearer ${wrong}` })).status).toBe(401);
      expect((await put({ authorization: `Bearer ${stranger.deviceSecret}` })).status).toBe(401);
      expect((await put({ authorization: `Bearer ${device.deviceSecret}` })).status).toBe(204);
    });

    test("POST /v1/activity needs a send token", async () => {
      const { device } = await setup();
      const body = { ref: "act_x", event: "update", state: { phase: "running", step: 1, toolGlyph: "none", startedAt: seconds(), updatedAt: seconds() }, staleAt: seconds() + 300, priority: 5 };
      const post = (headers: Record<string, string>) => t().relay("/v1/activity", { ...json(body), headers: { "content-type": "application/json", ...headers } });
      expect((await post({})).status).toBe(401);
      expect((await post({ authorization: "Bearer ocs_" + "A".repeat(43) })).status).toBe(401);
      expect((await post({ authorization: `Bearer ${device.deviceSecret}` })).status).toBe(401);
      expect(await mock()).toEqual([]);
    });

    test("a device holds at most 32 senders and 16 live activities", async () => {
      const device = await register();
      for (let index = 0; index < 32; index++) await addSender(device);
      const extra = await t().relay(`/v1/devices/${device.deviceID}/senders`, withSecret(device.deviceSecret, { method: "POST" }));
      expect(extra.status).toBe(409);
      const put = (ref: string) => t().relay(`/v1/devices/${device.deviceID}/activities/${ref}`, withSecret(device.deviceSecret, { ...json({ pushToken: deviceToken(), expiresAt: seconds() + 600 }), method: "PUT" }));
      for (let index = 0; index < 16; index++) expect((await put(`act_${index}`)).status).toBe(204);
      expect((await put("act_16")).status).toBe(409);
      expect((await put("act_3")).status).toBe(204);
    });
  });

  describe("POST /v1/push", () => {
    test("sends APNs a generic alert carrying exactly the envelope", async () => {
      const { device, sender } = await setup();
      const body = pushBody("permission");
      const before = seconds();
      expect(await push(sender.sendToken, { ...body, envelope: { ...body.envelope, extra: "dropped" } })).toEqual({ status: 200, body: { result: "delivered" } });
      const [request] = await mock();
      expect(request?.problems).toEqual([]);
      expect(request?.protocol).toBe(t().protocol);
      expect(request?.headers).toMatchObject({
        "apns-push-type": "alert",
        "apns-topic": t().bundleID,
        "apns-priority": "10",
        "apns-collapse-id": body.collapse,
      });
      const expiration = Number(request?.headers["apns-expiration"]);
      expect(expiration).toBeLessThanOrEqual(body.expiresAt);
      expect(expiration).toBeLessThanOrEqual(seconds() + kindPolicy("permission").ttlSeconds);
      expect(expiration).toBeGreaterThan(before);
      expect(request?.body).toEqual({
        aps: {
          alert: { body: "opencode needs your approval" },
          "mutable-content": 1,
          category: "OPEN_ONLY",
          "thread-id": body.thread,
          "interruption-level": "time-sensitive",
          sound: "default",
        },
        oc: body.envelope,
      });
      expect(device.deviceSecret).not.toContain(request!.token);
    });

    test.each(KINDS)("maps the %s kind to its alert, interruption level and priority, always with category OPEN_ONLY", async (kind) => {
      const { sender } = await setup();
      const body = pushBody(kind);
      expect((await push(sender.sendToken, body)).body.result).toBe("delivered");
      const [request] = await mock();
      const policy = kindPolicy(kind);
      const aps = (request?.body as { aps: Record<string, unknown> }).aps;
      // Fail closed: only the extension, after opening and classifying the envelope, may offer actions.
      expect(aps).toMatchObject({ alert: { body: policy.alert }, category: "OPEN_ONLY", "interruption-level": policy.interruptionLevel });
      expect("sound" in aps).toBe(policy.interruptionLevel !== "passive");
      expect(request?.headers["apns-priority"]).toBe(String(policy.priority));
    });

    test("needs a valid send token", async () => {
      const { device } = await setup();
      expect((await t().relay("/v1/push", json(pushBody()))).status).toBe(401);
      expect((await push("ocs_" + "A".repeat(43))).status).toBe(401);
      expect((await push(device.deviceSecret)).status).toBe(401);
      expect(await mock()).toEqual([]);
    });

    test("validates the request and the envelope", async () => {
      const { sender } = await setup();
      const body = pushBody("question");
      const invalid = [
        { ...body, kind: "promo" },
        { ...body, priority: 7 },
        { ...body, collapse: "has spaces" },
        { ...body, thread: "x".repeat(65) },
        { ...body, expiresAt: "soon" },
        { ...body, envelope: { ...body.envelope, ct: "+" } },
        { ...body, envelope: { ...body.envelope, v: 2 } },
        { ...body, envelope: { ...body.envelope, kind: "permission" } },
        { ...body, envelope: { ...body.envelope, exp: body.expiresAt + 1 } },
      ];
      for (const item of invalid) expect((await push(sender.sendToken, item)).status).toBe(400);
      expect(await mock()).toEqual([]);
    });

    test("does not send an envelope that has already expired", async () => {
      const { sender } = await setup();
      const exp = seconds() - 1;
      expect((await push(sender.sendToken, pushBody("finished", { expiresAt: exp, envelope: envelope("finished", exp) }))).body.result).toBe("rejected");
      expect(await mock()).toEqual([]);
    });

    test("Unregistered (410) is gone until the app sends a new token", async () => {
      const { device, sender } = await setup(deviceToken("410"));
      expect((await push(sender.sendToken)).body.result).toBe("gone");
      expect((await push(sender.sendToken)).body.result).toBe("gone");
      expect((await mock()).length).toBe(1);
      await t().relay(`/v1/devices/${device.deviceID}`, withSecret(device.deviceSecret, { ...json({ apnsToken: deviceToken() }), method: "PUT" }));
      expect((await push(sender.sendToken)).body.result).toBe("delivered");
    });

    test("BadDeviceToken is gone, 429 is throttled and other failures are rejected", async () => {
      for (const [prefix, result] of [["400b", "gone"], ["4290", "throttled"], ["5000", "rejected"], ["403e", "rejected"]] as const) {
        const { sender } = await setup(deviceToken(prefix));
        expect((await push(sender.sendToken)).body.result).toBe(result);
      }
    });

    test("reuses one provider token and replaces it after APNs refuses it", async () => {
      const first = await setup(), second = await setup();
      for (let index = 0; index < 3; index++) expect((await push(first.sender.sendToken)).body.result).toBe("delivered");
      expect((await push(second.sender.sendToken)).body.result).toBe("delivered");
      const tokens = new Set((await mock()).map((request) => request.jwt));
      expect(tokens.size).toBe(1);
      const refused = await setup(deviceToken("403e"));
      expect((await push(refused.sender.sendToken)).body.result).toBe("rejected");
      expect((await push(first.sender.sendToken)).body.result).toBe("delivered");
      const requests = await mock();
      expect(requests.at(-1)?.jwt).not.toBe(requests.at(-2)?.jwt);
    });

    test("limits alerts per device per minute without contacting APNs", async () => {
      const { sender } = await setup(), other = await setup();
      for (let index = 0; index < t().limits.alertsPerMinute; index++) expect((await push(sender.sendToken)).body.result).toBe("delivered");
      expect((await push(sender.sendToken)).body.result).toBe("throttled");
      expect((await mock()).length).toBe(t().limits.alertsPerMinute);
      expect((await push(other.sender.sendToken)).body.result).toBe("delivered");
    });
  });

  describe("Live Activities", () => {
    const state = { phase: "running", step: 2, toolGlyph: "shell", startedAt: seconds() - 60, updatedAt: seconds() };
    async function withActivity(token = deviceToken()) {
      const { device, sender } = await setup();
      const ref = "act_" + hex(8);
      const response = await t().relay(`/v1/devices/${device.deviceID}/activities/${ref}`, withSecret(device.deviceSecret, { ...json({ pushToken: token, expiresAt: seconds() + 3600 }), method: "PUT" }));
      expect(response.status).toBe(204);
      return { device, sender, ref };
    }
    const update = (sendToken: string, body: Record<string, unknown>) => t().relay("/v1/activity", withSecret(sendToken, json(body)));

    test("sends a liveactivity push with the coarse state", async () => {
      const { sender, ref } = await withActivity();
      const staleAt = seconds() + CONTRACT.activity.staleSeconds;
      const response = await update(sender.sendToken, { ref, event: "update", state, staleAt, priority: 5 });
      expect(await response.json()).toEqual({ result: "delivered" });
      const [request] = await mock();
      expect(request?.problems).toEqual([]);
      expect(request?.headers).toMatchObject({ "apns-push-type": "liveactivity", "apns-topic": `${t().bundleID}.push-type.liveactivity`, "apns-priority": "5" });
      expect((request?.body as { aps: Record<string, unknown> }).aps).toMatchObject({ event: "update", "content-state": state, "stale-date": staleAt });
    });

    test("end dismisses the activity and forgets its token", async () => {
      const { sender, ref } = await withActivity();
      const dismissAt = seconds() + CONTRACT.activity.dismissSeconds;
      const end = await update(sender.sendToken, { ref, event: "end", state: { ...state, phase: "succeeded" }, staleAt: seconds() + 300, dismissAt, priority: 10 });
      expect(await end.json()).toEqual({ result: "delivered" });
      expect(((await mock())[0]?.body as { aps: Record<string, unknown> }).aps["dismissal-date"]).toBe(dismissAt);
      const after = await update(sender.sendToken, { ref, event: "update", state, staleAt: seconds() + 300, priority: 5 });
      expect(await after.json()).toEqual({ result: "gone" });
    });

    test("refuses state beyond the coarse fields, unknown references and stale registrations", async () => {
      const { device, sender, ref } = await withActivity();
      expect((await update(sender.sendToken, { ref, event: "update", state: { ...state, title: "secret" }, staleAt: seconds() + 300, priority: 5 })).status).toBe(400);
      expect((await update(sender.sendToken, { ref, event: "pause", state, staleAt: seconds() + 300, priority: 5 })).status).toBe(400);
      expect(await (await update(sender.sendToken, { ref: "act_unknown", event: "update", state, staleAt: seconds() + 300, priority: 5 })).json()).toEqual({ result: "gone" });
      const past = await t().relay(`/v1/devices/${device.deviceID}/activities/act_old`, withSecret(device.deviceSecret, { ...json({ pushToken: deviceToken(), expiresAt: seconds() - 1 }), method: "PUT" }));
      expect(past.status).toBe(400);
      expect(await mock()).toEqual([]);
    });

    test("limits activity updates per device per day", async () => {
      const { sender, ref } = await withActivity();
      for (let index = 0; index < t().limits.activityUpdatesPerDay; index++) {
        expect(await (await update(sender.sendToken, { ref, event: "update", state, staleAt: seconds() + 300, priority: 5 })).json()).toEqual({ result: "delivered" });
      }
      expect(await (await update(sender.sendToken, { ref, event: "update", state, staleAt: seconds() + 300, priority: 5 })).json()).toEqual({ result: "throttled" });
    });
  });

  test("logs carry counts and outcomes, never tokens, IDs or content", async () => {
    const { device, sender } = await setup();
    const body = pushBody("question");
    await push(sender.sendToken, body);
    const failing = await setup(deviceToken("5000"));
    await push(failing.sender.sendToken);
    const text = t().logs().join("\n");
    expect(text).toContain('"event":"push"');
    expect(text).toContain('"result":"rejected","status":500');
    for (const secret of [device.deviceID, device.deviceSecret, sender.senderID, sender.sendToken, body.envelope.ct, body.envelope.kid, body.collapse, body.thread]) {
      expect(text).not.toContain(secret);
    }
    expect(text).not.toMatch(/[0-9a-f]{64}/);
  });
}
