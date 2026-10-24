import { Hono, type Context } from "hono";
import { bodyLimit } from "hono/body-limit";
import { CONTRACT, isKind } from "../../contracts/src/constants.ts";
import { EnvelopeError, parseEnvelope } from "../../contracts/src/envelope-format.ts";
import { activityState } from "./activity-state.ts";
import { deliver, type ApnsSender, type Delivery, type DeliveryResult } from "./apns/delivery.ts";
import { activityRequest, alertRequest, fitsAPNs } from "./apns/request.ts";
import type { TokenProvider } from "./apns/token.ts";
import type { RelayConfig } from "./config.ts";
import { randomToken, sameDigest, sha256Hex } from "./crypto.ts";
import type { Limiter } from "./limiter.ts";
import type { Logger } from "./log.ts";
import { MAX_SENDERS, type Device, type Store } from "./store.ts";
import { apnsEnvironment, bearer, bundleID, jsonBody, opaqueID, priority, pushToken, unixSeconds } from "./validation.ts";

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

const error = (c: Context, status: 400 | 401 | 403 | 404 | 409 | 429 | 501 | 503, code: string) => c.json({ error: code }, status);
const DEVICE_ID = /^dev_[A-Za-z0-9_-]{22}$/;
const SENDER_ID = /^snd_[A-Za-z0-9_-]{22}$/;
const MAX_ACTIVITY_SECONDS = CONTRACT.activity.maxLifetimeSeconds;

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

  app.post("/v1/devices", async (c) => {
    const { config, store, limiter, log, now } = c.get("deps");
    // App Attest gate for M9. While APP_ATTEST is "off" every registration passes; "required"
    // fails closed until verification of the assertion is implemented.
    if (config.appAttest === "required") return error(c, 501, "app_attest_unavailable");
    const ip = await sha256Hex(options.clientIP(c) ?? "unknown");
    if (!(await limiter.hit(`ip:${ip}`, [{ windowSeconds: 3600, max: config.limits.registrationsPerHour }], now()))) {
      return error(c, 429, "rate_limited");
    }
    const body = await jsonBody(c.req.raw);
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
