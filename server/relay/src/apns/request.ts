import { CONTRACT, kindPolicy, type Kind } from "../../../contracts/src/constants.ts";
import type { Envelope } from "../../../contracts/src/envelope-format.ts";
import type { Device } from "../store.ts";
import type { ActivityState } from "../activity-state.ts";

export interface ApnsRequest {
  readonly environment: Device["env"];
  readonly deviceToken: string;
  readonly headers: Readonly<Record<string, string>>;
  readonly body: string;
}

export interface AlertPush {
  readonly kind: Kind;
  readonly priority: 5 | 10;
  readonly collapse: string;
  readonly thread: string;
  readonly expiresAt: number;
  readonly envelope: Envelope;
}

/**
 * A generic alert carrying the envelope. Only the six envelope fields are forwarded, so nothing
 * else a sender includes reaches Apple. The category is always OPEN_ONLY: the extension sets the
 * kind's category only after it has opened and classified the envelope, so an alert shown without
 * the extension (crashed, killed, out of time) never offers an action (server/contracts/README.md).
 */
export function alertRequest(device: Device & { apnsToken: string }, push: AlertPush, now: number): ApnsRequest {
  const policy = kindPolicy(push.kind);
  const { v, kid, kind, exp, enc, ct } = push.envelope;
  const aps: Record<string, unknown> = {
    alert: { body: policy.alert },
    "mutable-content": 1,
    category: CONTRACT.apns.category,
    "thread-id": push.thread,
    "interruption-level": policy.interruptionLevel,
  };
  if (policy.interruptionLevel !== "passive") aps.sound = "default";
  return {
    environment: device.env,
    deviceToken: device.apnsToken,
    headers: {
      "apns-push-type": "alert",
      "apns-topic": device.bundleID,
      "apns-priority": String(push.priority),
      // Approvals and replacements expire within minutes, so a phone that comes back online late is not shown a stale request.
      "apns-expiration": String(Math.min(push.expiresAt, now + policy.ttlSeconds)),
      "apns-collapse-id": push.collapse,
    },
    body: JSON.stringify({ aps, oc: { v, kid, kind, exp, enc, ct } }),
  };
}

export interface ActivityPush {
  readonly event: "update" | "end";
  readonly state: ActivityState;
  readonly staleAt: number;
  readonly dismissAt?: number;
  readonly priority: 5 | 10;
}

export function activityRequest(device: Device, pushToken: string, update: ActivityPush, now: number): ApnsRequest {
  const aps: Record<string, unknown> = {
    timestamp: now,
    event: update.event,
    "content-state": update.state,
    "stale-date": update.staleAt,
  };
  if (update.event === "end" && update.dismissAt !== undefined) aps["dismissal-date"] = update.dismissAt;
  return {
    environment: device.env,
    deviceToken: pushToken,
    headers: {
      "apns-push-type": "liveactivity",
      "apns-topic": `${device.bundleID}.push-type.liveactivity`,
      "apns-priority": String(update.priority),
      "apns-expiration": String(update.staleAt),
    },
    body: JSON.stringify({ aps }),
  };
}

export const fitsAPNs = (request: ApnsRequest): boolean => new TextEncoder().encode(request.body).length <= CONTRACT.apns.maxPayloadBytes;
