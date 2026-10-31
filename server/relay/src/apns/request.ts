// The requests are shared with the plugin's direct mode (server/contracts/src/apns.ts); the relay
// addresses them from a stored device.
import {
  activityRequest as sharedActivityRequest, alertRequest as sharedAlertRequest,
  type AlertPush, type ApnsRequest,
} from "../../../contracts/src/apns.ts";
import type { Device } from "../store.ts";
import type { ActivityState } from "../activity-state.ts";

export { fitsAPNs, type AlertPush, type ApnsRequest } from "../../../contracts/src/apns.ts";

export interface ActivityPush {
  readonly event: "update" | "end";
  readonly state: ActivityState;
  readonly staleAt: number;
  readonly dismissAt?: number;
  readonly priority: 5 | 10;
}

/** A generic alert carrying the envelope (server/contracts/src/apns.ts). */
export function alertRequest(device: Device & { apnsToken: string }, push: AlertPush, now: number): ApnsRequest {
  return sharedAlertRequest({ env: device.env, bundleID: device.bundleID }, device.apnsToken, push, now);
}

export function activityRequest(device: Device, pushToken: string, update: ActivityPush, now: number): ApnsRequest {
  return sharedActivityRequest({ env: device.env, bundleID: device.bundleID }, pushToken, update, now);
}
