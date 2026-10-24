import { base64url, CONTRACT, codePointLength, KEY_ID, PACKAGE_NAME, RPC_ID } from "../contracts/src/index.ts";
import packageJSON from "../package.json" with { type: "json" };
import type { RpcContext, RpcDefinition, RpcHandler } from "./host.ts";
import { DEFAULT_PREFS, type Device, type Prefs } from "./registry.ts";
import type { PushService } from "./service.ts";

export const PLUGIN_VERSION: string = packageJSON.version;
/** Bumped when a method's input or output changes incompatibly. */
export const RPC_VERSION = 1;

// Inputs are validated by the handlers, so every schema accepts any JSON value. opencode converts
// these JSON Schemas to its own (core/src/rpc.ts) and rejects inputs that fail them.
const any = {};
const method = { input: any, output: any, errors: { invalid: any, not_found: any, unavailable: any } };

export const definition: RpcDefinition = {
  id: RPC_ID,
  methods: {
    status: method,
    registerDevice: method,
    unregisterDevice: method,
    listDevices: method,
    test: method,
    registerActivity: method,
    setPresence: method,
  },
  events: {},
};

class Invalid extends Error {
  readonly field: string;
  constructor(field: string, message: string) {
    super(message);
    this.field = field;
  }
}

const object = (value: unknown): Record<string, unknown> => {
  if (value === undefined || value === null) return {};
  if (typeof value !== "object" || Array.isArray(value)) throw new Invalid("input", "Input must be an object");
  return value as Record<string, unknown>;
};
const text = (input: Record<string, unknown>, field: string, pattern: RegExp, message: string): string => {
  const value = input[field];
  if (typeof value !== "string" || !pattern.test(value)) throw new Invalid(field, message);
  return value;
};
const keyID = (input: Record<string, unknown>) => text(input, "keyID", KEY_ID, "keyID must be 16 to 64 characters of A-Z, a-z, 0-9, _ or -");

/** https for a deployed relay; plain http only on this machine, for development and tests. */
function relayURL(value: unknown): string {
  if (typeof value !== "string") throw new Invalid("relayURL", "relayURL must be a URL");
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new Invalid("relayURL", "relayURL must be a URL");
  }
  const loopback = ["127.0.0.1", "localhost", "[::1]"].includes(url.hostname);
  if (url.protocol !== "https:" && !(url.protocol === "http:" && loopback)) throw new Invalid("relayURL", "relayURL must use https (http only for a relay on this machine)");
  if (url.username || url.password || url.search || url.hash) throw new Invalid("relayURL", "relayURL must not carry credentials, a query or a fragment");
  return url.href.replace(/\/+$/, "");
}

function prefs(value: unknown): Prefs {
  if (value === undefined || value === null) return DEFAULT_PREFS;
  const input = object(value);
  const result = { ...DEFAULT_PREFS };
  for (const name of Object.keys(DEFAULT_PREFS) as (keyof Prefs)[]) {
    if (input[name] === undefined) continue;
    if (typeof input[name] !== "boolean") throw new Invalid(`prefs.${name}`, `prefs.${name} must be a boolean`);
    result[name] = input[name];
  }
  return result;
}

const publicDevice = async (service: PushService, device: Device) => {
  const lastDelivery = await service.registry.lastDelivery(device.keyID);
  return {
    keyID: device.keyID,
    label: device.label,
    appServerRef: device.appServerRef,
    relayURL: device.relayURL,
    prefs: device.prefs,
    registeredAt: device.registeredAt,
    ...(lastDelivery ? { lastDelivery } : {}),
  };
};

/** The `mobilepush` RPC methods (ARCHITECTURE §4.2). No method returns a send token or the private key. */
export function handlers(service: PushService): Record<string, RpcHandler> {
  const wrap = (run: (input: Record<string, unknown>) => Promise<unknown>): RpcHandler => async (input: unknown, context: RpcContext) => {
    try {
      return await run(object(input));
    } catch (error) {
      if (error instanceof Invalid) throw context.error("invalid", error.message, { field: error.field });
      if (error instanceof NotFound) throw context.error("not_found", error.message, { field: error.field, retryable: false });
      if (error instanceof Unavailable) throw context.error("unavailable", error.message, { field: error.field, retryable: true });
      throw error;
    }
  };
  const registered = async (input: Record<string, unknown>) => {
    const id = keyID(input);
    const device = await service.registry.get(id);
    if (!device) throw new NotFound("keyID", "No device is registered with this keyID");
    return device;
  };
  const serverPublicKey = async () => base64url.encode((await service.serverKeys()).publicKey);

  return {
    status: wrap(async () => ({
      package: PACKAGE_NAME,
      pluginVersion: PLUGIN_VERSION,
      rpcVersion: RPC_VERSION,
      serverPublicKey: await serverPublicKey(),
      devices: (await service.registry.list()).length,
      instance: service.instance,
    })),

    registerDevice: wrap(async (input) => {
      const devicePublicKey = text(input, "devicePublicKey", /^[A-Za-z0-9_-]{43}$/, "devicePublicKey must be a raw X25519 public key in base64url");
      if (base64url.decode(devicePublicKey)?.length !== 32) throw new Invalid("devicePublicKey", "devicePublicKey must be 32 bytes");
      const appServerRef = input.appServerRef;
      if (typeof appServerRef !== "string" || !appServerRef || codePointLength(appServerRef) > CONTRACT.payload.limits.server) {
        throw new Invalid("appServerRef", "appServerRef must be 1 to 128 characters");
      }
      const label = input.label === undefined ? "" : input.label;
      if (typeof label !== "string" || codePointLength(label) > 64) throw new Invalid("label", "label must be at most 64 characters");
      const device: Device = {
        keyID: keyID(input),
        sendToken: text(input, "sendToken", /^[A-Za-z0-9_-]{16,200}$/, "sendToken must be the relay's send token"),
        relayURL: relayURL(input.relayURL),
        devicePublicKey,
        appServerRef,
        label,
        prefs: prefs(input.prefs),
        registeredAt: Date.now(),
      };
      await service.registry.put(device);
      return { serverPublicKey: await serverPublicKey(), pluginVersion: PLUGIN_VERSION };
    }),

    unregisterDevice: wrap(async (input) => ({ removed: await service.registry.remove(keyID(input)) })),

    listDevices: wrap(async () => ({
      devices: await Promise.all((await service.registry.list()).map((device) => publicDevice(service, device))),
    })),

    test: wrap(async (input) => {
      const outcome = await service.sendTest(await registered(input));
      return { result: outcome.result, attempts: outcome.attempts };
    }),

    registerActivity: wrap(async (input) => {
      const device = await registered(input);
      const activityRef = text(input, "activityRef", /^[A-Za-z0-9_-]{1,64}$/, "activityRef must be 1 to 64 characters of A-Z, a-z, 0-9, _ or -");
      const sessionID = text(input, "sessionID", /^[A-Za-z0-9_-]{1,128}$/, "sessionID must be a session ID");
      const outcome = await service.registerActivity(device.keyID, activityRef, sessionID);
      if (outcome === "missing") throw new NotFound("sessionID", "The session or its parent does not exist");
      if (outcome === "unavailable") throw new Unavailable("sessionID", "The session's family could not be read; register the activity again");
      return { registered: true };
    }),

    setPresence: wrap(async (input) => {
      const device = await registered(input);
      if (typeof input.foreground !== "boolean") throw new Invalid("foreground", "foreground must be a boolean");
      const sessionID = input.sessionID === undefined || input.sessionID === null ? undefined : text(input, "sessionID", /^[A-Za-z0-9_-]{1,128}$/, "sessionID must be a session ID");
      await service.setPresence(device.keyID, input.foreground, sessionID);
      return { validSeconds: CONTRACT.presence.validSeconds, heartbeatSeconds: CONTRACT.presence.heartbeatSeconds };
    }),
  };
}

/** A read the server could not complete; the caller may retry. */
class Unavailable extends Error {
  readonly field: string;
  constructor(field: string, message: string) {
    super(message);
    this.field = field;
  }
}

/** Nothing exists for that input, so the same call fails again. */
class NotFound extends Error {
  readonly field: string;
  constructor(field: string, message: string) {
    super(message);
    this.field = field;
  }
}
