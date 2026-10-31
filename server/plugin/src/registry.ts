import type { HostStorage, Json } from "./host.ts";

export interface Prefs {
  readonly permission: boolean;
  readonly question: boolean;
  readonly finished: boolean;
  readonly failed: boolean;
}

export const DEFAULT_PREFS: Prefs = { permission: true, question: true, finished: true, failed: true };

/** `relay`: sealed pushes go through the device's relay. `direct`: the plugin sends them to Apple itself (direct.ts). */
export type Transport = "relay" | "direct";

/** One device's registration for this server, keyed by the device's key ID. */
export interface Device {
  readonly keyID: string;
  readonly transport: Transport;
  /** Relay devices only. */
  readonly sendToken?: string;
  /** Relay devices only. */
  readonly relayURL?: string;
  /** Direct devices only: the APNs device token, lowercase hex. */
  readonly apnsToken?: string;
  /** Direct devices only: the app's bundle ID and APNs environment, which match the plugin's `apns` option. */
  readonly bundleID?: string;
  readonly environment?: "sandbox" | "production";
  /** base64url of the device's raw 32-byte X25519 public key. */
  readonly devicePublicKey: string;
  readonly appServerRef: string;
  readonly label: string;
  readonly prefs: Prefs;
  /** Unix milliseconds. */
  readonly registeredAt: number;
}

export interface Delivery {
  readonly kind: string;
  readonly result: string;
  readonly attempts: number;
  /** Unix milliseconds. */
  readonly at: number;
}

export interface Presence {
  readonly foreground: boolean;
  readonly sessionID?: string;
  /** Unix milliseconds after which the heartbeat no longer counts. */
  readonly until: number;
}

export interface ActivityRegistration {
  readonly keyID: string;
  readonly activityRef: string;
  /** The root session the activity follows. */
  readonly sessionID: string;
  readonly registeredAt: number;
  readonly startedAt?: number;
  readonly step: number;
  readonly toolGlyph: string;
  readonly phase: string;
  /** Requests (in the root or a subagent) still pending after their grace period: needs input until empty. */
  readonly waiting?: readonly string[];
  /** Unix milliseconds of the last update sent. */
  readonly sentAt?: number;
  /** Direct devices only: the activity's APNs push token, which the relay keeps for relay devices. */
  readonly pushToken?: string;
  /** Direct devices only: Unix seconds after which the push token is no longer used. */
  readonly expiresAt?: number;
}

// Storage layout (ctx.storage is already namespaced to this plugin):
//   key/server                  the static key pair (keys.ts)
//   device/<keyID>              Device
//   delivery/<keyID>            Delivery: the last delivery result
//   presence/<keyID>            Presence
//   activity/<keyID>/<ref>      ActivityRegistration
//   sent/<eventID>              { at } for deduplication
export const keys = {
  device: (keyID: string) => `device/${keyID}`,
  delivery: (keyID: string) => `delivery/${keyID}`,
  presence: (keyID: string) => `presence/${keyID}`,
  activity: (keyID: string, ref: string) => `activity/${keyID}/${ref}`,
  activities: (keyID: string) => `activity/${keyID}/`,
  sent: (eventID: string) => `sent/${eventID}`,
};

const record = (value: Json | undefined): Record<string, Json> | undefined =>
  typeof value === "object" && value !== null && !Array.isArray(value) ? value : undefined;

export async function scanAll(storage: HostStorage, prefix: string) {
  const entries: { key: string; value: Json }[] = [];
  let after: string | undefined;
  do {
    const page = await storage.scan({ prefix, ...(after ? { after } : {}), limit: 200 });
    entries.push(...page.entries);
    after = page.next;
  } while (after);
  return entries;
}

export class Registry {
  readonly #storage: HostStorage;
  constructor(storage: HostStorage) {
    this.#storage = storage;
  }

  async put(device: Device): Promise<void> {
    await this.#storage.set(keys.device(device.keyID), { ...device, prefs: { ...device.prefs } });
  }

  async get(keyID: string): Promise<Device | undefined> {
    return parseDevice(await this.#storage.get(keys.device(keyID)));
  }

  async list(): Promise<Device[]> {
    return (await scanAll(this.#storage, "device/")).flatMap((entry) => parseDevice(entry.value) ?? []);
  }

  /** Removes the registration and everything kept for it. */
  async remove(keyID: string): Promise<boolean> {
    const existed = (await this.get(keyID)) !== undefined;
    for (const entry of await scanAll(this.#storage, keys.activities(keyID))) await this.#storage.remove(entry.key);
    await this.#storage.remove(keys.presence(keyID));
    await this.#storage.remove(keys.delivery(keyID));
    await this.#storage.remove(keys.device(keyID));
    return existed;
  }

  async recordDelivery(keyID: string, delivery: Delivery): Promise<void> {
    await this.#storage.set(keys.delivery(keyID), { ...delivery });
  }

  async lastDelivery(keyID: string): Promise<Delivery | undefined> {
    const value = record(await this.#storage.get(keys.delivery(keyID)));
    return value && typeof value.result === "string" ? (value as unknown as Delivery) : undefined;
  }
}

const string = (value: Json | undefined): string | undefined => (typeof value === "string" ? value : undefined);

function parseDevice(value: Json | undefined): Device | undefined {
  const item = record(value);
  if (!item) return undefined;
  const fields = ["keyID", "devicePublicKey", "appServerRef"] as const;
  if (!fields.every((field) => typeof item[field] === "string")) return undefined;
  // Registrations stored before direct mode existed have no transport: they are relay devices.
  const transport: Transport = item.transport === "direct" ? "direct" : "relay";
  let route: Partial<Device>;
  if (transport === "relay") {
    const sendToken = string(item.sendToken), relayURL = string(item.relayURL);
    if (!sendToken || !relayURL) return undefined;
    route = { sendToken, relayURL };
  } else {
    const apnsToken = string(item.apnsToken), bundleID = string(item.bundleID);
    const environment = item.environment === "sandbox" || item.environment === "production" ? item.environment : undefined;
    if (!apnsToken || !bundleID || !environment) return undefined;
    route = { apnsToken, bundleID, environment };
  }
  const prefs = record(item.prefs) ?? {};
  return {
    keyID: item.keyID as string,
    transport,
    ...route,
    devicePublicKey: item.devicePublicKey as string,
    appServerRef: item.appServerRef as string,
    label: typeof item.label === "string" ? item.label : "",
    prefs: Object.fromEntries(Object.entries(DEFAULT_PREFS).map(([name, fallback]) => [name, typeof prefs[name] === "boolean" ? prefs[name] : fallback])) as unknown as Prefs,
    registeredAt: typeof item.registeredAt === "number" ? item.registeredAt : 0,
  };
}
