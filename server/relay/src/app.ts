import { Hono, type Context } from "hono";
import { bodyLimit } from "hono/body-limit";
import { CONTRACT, isKind } from "../../contracts/src/constants.ts";
import * as base64url from "../../contracts/src/base64url.ts";
import { EnvelopeError, parseEnvelope } from "../../contracts/src/envelope-format.ts";
import { activityState } from "./activity-state.ts";
import { AttestError, sha256, verifyAssertion, verifyAttestation } from "./attest/verify.ts";
import { deliver, type ApnsSender, type Delivery, type DeliveryResult } from "./apns/delivery.ts";
import { activityRequest, alertRequest, fitsAPNs } from "./apns/request.ts";
import type { TokenProvider } from "./apns/token.ts";
import type { RelayConfig } from "./config.ts";
import { randomToken, sameDigest, sha256Hex } from "./crypto.ts";
import type { Limiter } from "./limiter.ts";
import type { Logger } from "./log.ts";
import { MAX_SENDERS, type Device, type Store } from "./store.ts";
import { apnsEnvironment, base64Bytes, bearer, bundleID, jsonBody, jsonBytes, opaqueID, priority, pushToken, unixSeconds, type Json } from "./validation.ts";

export const RELAY_VERSION = "0.1.0";

export interface RelayDeps {
  readonly config: RelayConfig;
  readonly store: Store;
  readonly limiter: Limiter;
  readonly sender: ApnsSender;
  readonly tokens: TokenProvider;
  readonly log: Logger;
  /** Unix seconds. */
  readonly now: () => number;
}

type Env = { Variables: { deps: RelayDeps } };

export interface AppOptions {
  /** Builds the dependencies for a request; it may cache them per environment. */
  readonly resolve: (c: Context) => RelayDeps | Promise<RelayDeps>;
  /** The caller's IP address, used only, hashed, for the registration rate limit. */
  readonly clientIP: (c: Context) => string | undefined;
}

const error = (c: Context, status: 400 | 401 | 403 | 404 | 409 | 429 | 503, code: string) => c.json({ error: code }, status);
const DEVICE_ID = /^dev_[A-Za-z0-9_-]{22}$/;
const SENDER_ID = /^snd_[A-Za-z0-9_-]{22}$/;
const MAX_ACTIVITY_SECONDS = CONTRACT.activity.maxLifetimeSeconds;
const CHALLENGE = /^atc_[A-Za-z0-9_-]{43}$/;
const CHALLENGE_SECONDS = 300;
/** An App Attest key ID: base64 of a SHA-256 digest. */
const ATTEST_KEY_ID = /^[A-Za-z0-9+/]{43}=$/;
const text = (value: string) => new TextEncoder().encode(value);

export function createApp(options: AppOptions) {
  const app = new Hono<Env>();

  app.use("*", bodyLimit({ maxSize: 16 * 1024, onError: (c) => c.json({ error: "too_large" }, 413) }));

  app.get("/v1/health", async (c) => {
    try {
      await options.resolve(c);
      return c.json({ status: "ok", version: RELAY_VERSION });
    } catch {
      return c.json({ status: "misconfigured", version: RELAY_VERSION }, 503);
    }
  });

  app.use("/v1/*", async (c, next) => {
    c.set("deps", await options.resolve(c));
    await next();
  });

  /** The device for `:id`, if the Authorization header carries its secret. */
  async function device(c: Context<Env>): Promise<Device | undefined> {
    const id = c.req.param("id") ?? "";
    const secret = bearer(c.req.header("authorization"));
    const hash = await sha256Hex(secret ?? "");
    if (!secret || !DEVICE_ID.test(id)) return undefined;
    const found = await c.get("deps").store.device(id);
    return found && sameDigest(hash, found.secretHash) ? found : undefined;
  }

  /** The sender and its device for a Bearer send token. */
  async function sender(c: Context<Env>) {
    const token = bearer(c.req.header("authorization"));
    if (!token) return undefined;
    const { store } = c.get("deps");
    const found = await store.senderByTokenHash(await sha256Hex(token));
    const owner = found && (await store.device(found.deviceID));
    return found && owner ? { sender: found, device: owner } : undefined;
  }

  /** Counts a request against the caller's hashed IP address. */
  async function withinLimit(c: Context<Env>, scope: string, max: number): Promise<boolean> {
    const { limiter, now } = c.get("deps");
    const ip = await sha256Hex(options.clientIP(c) ?? "unknown");
    return limiter.hit(`${scope}:${ip}`, [{ windowSeconds: 3600, max }], now());
  }

  /**
   * With App Attest required, a registration carries the key ID and an assertion in headers, and a
   * fresh challenge in its body. The assertion signs the exact body bytes, so it binds the challenge,
   * the APNs token and the bundle ID. Returns the refusal, or undefined when the request may proceed.
   */
  async function assertionRefusal(c: Context<Env>, raw: Uint8Array, body: Json | undefined) {
    const { config, store, log, now } = c.get("deps");
    const keyID = c.req.header("x-app-attest-key"), assertion = base64Bytes(c.req.header("x-app-attest-assertion"), 4096);
    if (!keyID || !ATTEST_KEY_ID.test(keyID) || !assertion) return error(c, 401, "attestation_required");
    const challenge = body?.challenge;
    if (typeof challenge !== "string" || !CHALLENGE.test(challenge) || !(await store.consumeChallenge(challenge, now()))) {
      return error(c, 401, "challenge_invalid");
    }
    const key = await store.attestKey(keyID);
    if (!key) return error(c, 401, "attest_key_unknown");
    try {
      if (key.appID !== `${config.apns.teamID}.${String(body?.bundleID)}`) throw new AttestError("bundle ID mismatch");
      const counter = await verifyAssertion({
        assertion,
        clientDataHash: await sha256(raw),
        key: { publicKey: base64url.decode(key.publicKey) ?? new Uint8Array(), appID: key.appID },
        counter: key.counter,
      });
      if (!(await store.advanceAttestCounter(keyID, counter, now()))) throw new AttestError("counter replayed");
    } catch (failure) {
      if (!(failure instanceof AttestError)) throw failure;
      log("attest.refused", { route: "devices" });
      return error(c, 401, "attestation_invalid");
    }
    return undefined;
  }

  app.post("/v1/attest/challenge", async (c) => {
    const { config, store, now } = c.get("deps");
    if (config.appAttest.mode === "off") return error(c, 404, "not_found");
    if (!(await withinLimit(c, "attest", config.limits.registrationsPerHour * 3))) return error(c, 429, "rate_limited");
    const challenge = randomToken("atc_"), current = now();
    await store.createChallenge(challenge, current + CHALLENGE_SECONDS, current);
    return c.json({ challenge, expiresAt: current + CHALLENGE_SECONDS }, 201);
  });

  /** Stores a newly attested key. The attestation's client data is the challenge's UTF-8 bytes. */
  app.post("/v1/attest/keys", async (c) => {
    const { config, store, log, now } = c.get("deps");
    if (config.appAttest.mode === "off") return error(c, 404, "not_found");
    const body = await jsonBody(c.req.raw);
    const keyID = typeof body?.keyID === "string" && ATTEST_KEY_ID.test(body.keyID) ? body.keyID : undefined;
    const challenge = typeof body?.challenge === "string" && CHALLENGE.test(body.challenge) ? body.challenge : undefined;
    const attestation = base64Bytes(body?.attestation, 12_000);
    if (!keyID || !challenge || !attestation) return error(c, 400, "invalid_request");
    if (!(await store.consumeChallenge(challenge, now()))) return error(c, 401, "challenge_invalid");
    let attested;
    try {
      attested = await verifyAttestation({
        attestation,
        keyID: base64Bytes(keyID, 44)!,
        clientDataHash: await sha256(text(challenge)),
        appIDs: config.appAttest.appIDs,
        environment: config.appAttest.environment,
        roots: config.appAttest.roots,
        now: now(),
      });
    } catch (failure) {
      if (!(failure instanceof AttestError)) throw failure;
      log("attest.refused", { route: "attest" });
      return error(c, 401, "attestation_invalid");
    }
    const created = await store.createAttestKey({ keyID, publicKey: base64url.encode(attested.publicKey), appID: attested.appID, counter: 0 }, now());
    if (!created) return error(c, 409, "key_exists");
    log("attest.key_created", { route: "attest" });
    return c.json({ keyID }, 201);
  });

  app.post("/v1/devices", async (c) => {
    const { config, store, log, now } = c.get("deps");
    if (!(await withinLimit(c, "ip", config.limits.registrationsPerHour))) return error(c, 429, "rate_limited");
    const raw = new Uint8Array(await c.req.arrayBuffer());
    const body = jsonBytes(raw);
    if (config.appAttest.mode === "required") {
      const refusal = await assertionRefusal(c, raw, body);
      if (refusal) return refusal;
    }
    const apnsToken = pushToken(body?.apnsToken), env = apnsEnvironment(body?.env), bundle = bundleID(body?.bundleID);
    if (!apnsToken || !env || !bundle) return error(c, 400, "invalid_request");
    if (!config.bundleIDs.has(bundle)) return error(c, 403, "bundle_not_allowed");
    const deviceID = randomToken("dev_", 16), deviceSecret = randomToken("ocd_");
    await store.createDevice({ id: deviceID, secretHash: await sha256Hex(deviceSecret), apnsToken, env, bundleID: bundle }, now());
    log("device.created", { route: "devices" });
    return c.json({ deviceID, deviceSecret }, 201);
  });

  app.put("/v1/devices/:id", async (c) => {
    const found = await device(c);
    if (!found) return error(c, 401, "unauthorized");
    const body = await jsonBody(c.req.raw);
    const apnsToken = pushToken(body?.apnsToken);
    const env = body?.env === undefined ? found.env : apnsEnvironment(body.env);
    if (!apnsToken || !env) return error(c, 400, "invalid_request");
    const { store, log, now } = c.get("deps");
    await store.updateDeviceToken(found.id, apnsToken, env, now());
    log("device.updated", { route: "devices" });
    return c.json({ deviceID: found.id });
  });

  app.delete("/v1/devices/:id", async (c) => {
    const found = await device(c);
    if (!found) return error(c, 401, "unauthorized");
    const { store, log } = c.get("deps");
    await store.deleteDevice(found.id);
    log("device.deleted", { route: "devices" });
    return c.body(null, 204);
  });

  app.post("/v1/devices/:id/senders", async (c) => {
    const found = await device(c);
    if (!found) return error(c, 401, "unauthorized");
    const { store, log, now } = c.get("deps");
    if ((await store.countSenders(found.id)) >= MAX_SENDERS) return error(c, 409, "too_many_senders");
    const senderID = randomToken("snd_", 16), sendToken = randomToken("ocs_");
    await store.createSender({ id: senderID, deviceID: found.id }, await sha256Hex(sendToken), now());
    log("sender.created", { route: "senders" });
    return c.json({ senderID, sendToken }, 201);
  });

  app.delete("/v1/devices/:id/senders/:sid", async (c) => {
    const found = await device(c);
    if (!found) return error(c, 401, "unauthorized");
    const sid = c.req.param("sid");
    if (!SENDER_ID.test(sid)) return error(c, 400, "invalid_request");
    const { store, log } = c.get("deps");
    await store.deleteSender(found.id, sid);
    log("sender.deleted", { route: "senders" });
    return c.body(null, 204);
  });

  app.put("/v1/devices/:id/activities/:ref", async (c) => {
    const found = await device(c);
    if (!found) return error(c, 401, "unauthorized");
    const ref = opaqueID(c.req.param("ref"));
    const body = await jsonBody(c.req.raw);
    const token = pushToken(body?.pushToken), expiresAt = unixSeconds(body?.expiresAt);
    const { store, log, now } = c.get("deps");
    const current = now();
    if (!ref || !token || !expiresAt || expiresAt <= current) return error(c, 400, "invalid_request");
    const stored = await store.putActivity(found.id, ref, { pushToken: token, expiresAt: Math.min(expiresAt, current + MAX_ACTIVITY_SECONDS) }, current);
    if (!stored) return error(c, 409, "too_many_activities");
    log("activity.registered", { route: "activities" });
    return c.body(null, 204);
  });

  app.post("/v1/push", async (c) => {
    const auth = await sender(c);
    if (!auth) return error(c, 401, "unauthorized");
    const body = await jsonBody(c.req.raw);
    const kind = body?.kind, level = priority(body?.priority), collapse = opaqueID(body?.collapse), thread = opaqueID(body?.thread);
    const expiresAt = unixSeconds(body?.expiresAt);
    if (!isKind(kind) || !level || !collapse || !thread || !expiresAt) return error(c, 400, "invalid_request");
    let envelope;
    try {
      envelope = parseEnvelope(body?.envelope);
    } catch (failure) {
      if (failure instanceof EnvelopeError) return error(c, 400, "invalid_envelope");
      throw failure;
    }
    if (envelope.kind !== kind || envelope.exp !== expiresAt) return error(c, 400, "invalid_envelope");
    const { config, store, limiter, sender: apns, tokens, log, now } = c.get("deps");
    const current = now();
    const reply = (result: DeliveryResult, status?: number) => {
      log("push", { kind, result, ...(status === undefined ? {} : { status }) });
      return c.json({ result });
    };
    if (expiresAt <= current) return reply("rejected");
    const target = auth.device;
    if (!target.apnsToken) return reply("gone");
    const rules = [
      { windowSeconds: 60, max: config.limits.alertsPerMinute },
      { windowSeconds: 86_400, max: config.limits.alertsPerDay },
    ];
    if (!(await limiter.hit(`device:${target.id}`, rules, current))) return reply("throttled");
    const request = alertRequest({ ...target, apnsToken: target.apnsToken }, { kind, priority: level, collapse, thread, expiresAt, envelope }, current);
    if (!fitsAPNs(request)) return reply("rejected");
    const delivery: Delivery = await deliver(apns, tokens, request);
    if (delivery.result === "gone") await store.updateDeviceToken(target.id, null, target.env, current);
    await store.touchSender(auth.sender.id, current);
    return reply(delivery.result, delivery.status);
  });

  app.post("/v1/activity", async (c) => {
    const auth = await sender(c);
    if (!auth) return error(c, 401, "unauthorized");
    const body = await jsonBody(c.req.raw);
    const ref = opaqueID(body?.ref), level = priority(body?.priority), staleAt = unixSeconds(body?.staleAt);
    const event = body?.event === "update" || body?.event === "end" ? body.event : undefined;
    const state = activityState(body?.state);
    const dismissAt = body?.dismissAt === undefined ? undefined : unixSeconds(body.dismissAt);
    if (!ref || !level || !staleAt || !event || !state || (body?.dismissAt !== undefined && !dismissAt)) return error(c, 400, "invalid_request");
    const { config, store, limiter, sender: apns, tokens, log, now } = c.get("deps");
    const current = now();
    const reply = (result: DeliveryResult, status?: number) => {
      log("activity", { result, ...(status === undefined ? {} : { status }) });
      return c.json({ result });
    };
    const activity = await store.activity(auth.device.id, ref);
    if (!activity || activity.expiresAt <= current) return reply("gone");
    const rules = [
      { windowSeconds: 60, max: config.limits.activityUpdatesPerMinute },
      { windowSeconds: 86_400, max: config.limits.activityUpdatesPerDay },
    ];
    if (!(await limiter.hit(`activity:${auth.device.id}`, rules, current))) return reply("throttled");
    const request = activityRequest(auth.device, activity.pushToken, { event, state, staleAt, priority: level, ...(dismissAt ? { dismissAt } : {}) }, current);
    if (!fitsAPNs(request)) return reply("rejected");
    const delivery = await deliver(apns, tokens, request);
    if (delivery.result === "gone" || (event === "end" && delivery.result === "delivered")) await store.deleteActivity(auth.device.id, ref);
    await store.touchSender(auth.sender.id, current);
    return reply(delivery.result, delivery.status);
  });

  app.notFound((c) => c.json({ error: "not_found" }, 404));
  app.onError((failure, c) => {
    console.error(JSON.stringify({ event: "error", name: failure.name }));
    return c.json({ error: "internal" }, 500);
  });
  return app;
}
