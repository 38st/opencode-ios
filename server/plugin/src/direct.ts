import { readFile, stat } from "node:fs/promises";
import http2 from "node:http2";
import os from "node:os";
import path from "node:path";
import {
  activityRequest, alertRequest, apnsPath, deliver, fitsAPNs, importSigningKey, localTokenProvider,
  type ApnsEnvironment, type ApnsTarget, type ApnsRequest, type ApnsResponse, type ApnsSender, type TokenProvider,
} from "../contracts/src/apns.ts";
import { CONTRACT } from "../contracts/src/index.ts";
import type { Device } from "./registry.ts";
import type { ActivityUpdate, Outcome, PushRequest } from "./relay.ts";

/**
 * Direct mode: the plugin sends to Apple with the server owner's own APNs key, so no relay is involved.
 * Configured in the plugin's options:
 *
 *   "plugins": [{ "package": "@opencode-ios/opencode-mobile-push", "options": { "apns": {
 *     "keyFile": "/Users/Shared/opencode/AuthKey_ABC123DEFG.p8", "keyID": "ABC123DEFG", "teamID": "TEAM123456",
 *     "bundleID": "com.example.opencode", "environment": "production" } } }]
 *
 * `keyFile` may also start with `~/`. `environment` defaults to production. `origin`, for local
 * tests only, replaces Apple's hosts with a plain-HTTP/2 APNs stand-in on this machine.
 */
export interface DirectConfig {
  readonly keyFile: string;
  readonly keyID: string;
  readonly teamID: string;
  readonly bundleID: string;
  readonly environment: ApnsEnvironment;
  /** Tests only: an http:// loopback origin that receives the requests instead of Apple. */
  readonly origin?: string;
}

export class DirectConfigError extends Error {
  override readonly name = "DirectConfigError";
}

const field = (value: Record<string, unknown>, name: string, pattern: RegExp, message: string): string => {
  const item = value[name];
  if (typeof item !== "string" || !pattern.test(item)) throw new DirectConfigError(`apns.${name} ${message}`);
  return item;
};

/** The `apns` plugin option, or undefined when direct mode is not configured. */
export function directConfig(options: Readonly<Record<string, unknown>> | undefined): DirectConfig | undefined {
  const value = options?.apns;
  if (value === undefined) return undefined;
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw new DirectConfigError("apns must be an object");
  const record = value as Record<string, unknown>;
  const environment = record.environment ?? "production";
  if (environment !== "sandbox" && environment !== "production") throw new DirectConfigError('apns.environment must be "sandbox" or "production"');
  const keyFile = field(record, "keyFile", /\S/, "must be the path of the .p8 key");
  let origin: string | undefined;
  if (record.origin !== undefined) {
    let url: URL | undefined;
    try {
      url = new URL(String(record.origin));
    } catch {
      url = undefined;
    }
    if (!url || url.protocol !== "http:" || !["127.0.0.1", "localhost", "[::1]"].includes(url.hostname) || url.pathname !== "/" || url.search || url.username) {
      throw new DirectConfigError("apns.origin is for local tests only and must be an http:// origin on this machine");
    }
    origin = url.origin;
  }
  return {
    keyFile: keyFile.startsWith("~/") ? path.join(os.homedir(), keyFile.slice(2)) : keyFile,
    keyID: field(record, "keyID", /^[A-Z0-9]{10}$/, "must be the 10-character key ID"),
    teamID: field(record, "teamID", /^[A-Z0-9]{10}$/, "must be the 10-character team ID"),
    bundleID: field(record, "bundleID", /^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/, "must be the app's bundle ID"),
    environment,
    ...(origin ? { origin } : {}),
  };
}

/** Reads the key, refusing a file that other users can read or write, or that someone else owns. */
export async function readKey(file: string): Promise<string> {
  const info = await stat(file).catch(() => {
    throw new DirectConfigError("apns.keyFile does not exist");
  });
  if (!info.isFile()) throw new DirectConfigError("apns.keyFile is not a file");
  if (info.mode & 0o077) throw new DirectConfigError(`apns.keyFile must be readable only by its owner (chmod 600 ${file})`);
  if (typeof process.getuid === "function" && info.uid !== process.getuid()) throw new DirectConfigError("apns.keyFile must belong to the user running opencode");
  const text = await readFile(file, "utf8");
  if (!/-----BEGIN PRIVATE KEY-----/.test(text)) throw new DirectConfigError("apns.keyFile is not a .p8 key");
  return text;
}

export interface DirectOptions {
  /** Tests only: the APNs origins (an http:// origin speaks HTTP/2 without TLS). */
  readonly hosts?: { readonly sandbox: string; readonly production: string };
  readonly sleep?: (milliseconds: number) => Promise<void>;
  readonly now?: () => number;
  readonly retries?: number;
  readonly retryBaseMilliseconds?: number;
}

/** One HTTP/2 session per APNs host, kept open between pushes, as Apple recommends. */
class Http2Sender implements ApnsSender {
  readonly #hosts: { readonly sandbox: string; readonly production: string };
  readonly #sessions = new Map<string, http2.ClientHttp2Session>();
  constructor(hosts: { readonly sandbox: string; readonly production: string }) {
    this.#hosts = hosts;
  }
  #session(origin: string): http2.ClientHttp2Session {
    const existing = this.#sessions.get(origin);
    if (existing && !existing.closed && !existing.destroyed) return existing;
    const session = http2.connect(origin);
    const forget = () => {
      if (this.#sessions.get(origin) === session) this.#sessions.delete(origin);
    };
    session.on("error", forget);
    session.on("close", forget);
    session.on("goaway", forget);
    session.unref();
    this.#sessions.set(origin, session);
    return session;
  }
  send(request: ApnsRequest, providerToken: string): Promise<ApnsResponse> {
    const origin = request.environment === "sandbox" ? this.#hosts.sandbox : this.#hosts.production;
    return new Promise((resolve, reject) => {
      const stream = this.#session(origin).request({
        ":method": "POST",
        ":path": apnsPath(request.deviceToken),
        ...request.headers,
        authorization: `bearer ${providerToken}`,
        "content-type": "application/json",
      });
      let status = 0, text = "";
      stream.setEncoding("utf8");
      stream.setTimeout(10_000, () => stream.close(http2.constants.NGHTTP2_CANCEL));
      stream.on("response", (headers) => (status = Number(headers[":status"])));
      stream.on("data", (chunk: string) => (text += chunk));
      stream.on("error", reject);
      stream.on("close", () => {
        if (!status) return reject(new Error("APNs stream closed without a response"));
        let reason: string | undefined;
        try {
          reason = (JSON.parse(text) as { reason?: string }).reason;
        } catch {
          reason = undefined;
        }
        resolve({ status, ...(reason ? { reason } : {}) });
      });
      stream.end(request.body);
    });
  }
  close(): void {
    for (const session of this.#sessions.values()) session.close();
    this.#sessions.clear();
  }
}

/**
 * Sends the same requests the relay builds (contracts/src/apns.ts), with the same retries as the relay
 * client: a rejection or a network failure is retried up to three times while the push is unexpired.
 * The key never leaves this process; it is not logged and no RPC returns it.
 */
export class DirectSender {
  readonly config: DirectConfig;
  readonly #tokens: TokenProvider;
  readonly #sender: Http2Sender;
  readonly #sleep: (milliseconds: number) => Promise<void>;
  readonly #now: () => number;
  readonly #retries: number;
  readonly #base: number;

  constructor(config: DirectConfig, signingKey: CryptoKey, options: DirectOptions = {}) {
    this.config = config;
    this.#now = options.now ?? Date.now;
    this.#tokens = localTokenProvider(config, Promise.resolve(signingKey), () => Math.floor(this.#now() / 1000));
    this.#sender = new Http2Sender(options.hosts ?? (config.origin ? { sandbox: config.origin, production: config.origin } : CONTRACT.apns.hosts));
    this.#sleep = options.sleep ?? ((milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)));
    this.#retries = options.retries ?? CONTRACT.plugin.retries;
    this.#base = options.retryBaseMilliseconds ?? CONTRACT.plugin.retryBaseMilliseconds;
  }

  /** Reads and imports the key; any failure is a DirectConfigError whose message never contains the key. */
  static async load(config: DirectConfig, options: DirectOptions = {}): Promise<DirectSender> {
    const pem = await readKey(config.keyFile);
    const signingKey = await importSigningKey(pem).catch(() => {
      throw new DirectConfigError("apns.keyFile is not a valid P-256 .p8 key");
    });
    return new DirectSender(config, signingKey, options);
  }

  /** What `status` reports. Never the key or its path. */
  get summary() {
    return { bundleID: this.config.bundleID, environment: this.config.environment };
  }

  /** Whether a device's registration matches the bundle ID and environment this key sends to. */
  matches(target: { readonly bundleID?: string; readonly environment?: string }): boolean {
    return target.bundleID === this.config.bundleID && target.environment === this.config.environment;
  }

  #target(): ApnsTarget {
    return { env: this.config.environment, bundleID: this.config.bundleID };
  }

  push(device: Device, request: PushRequest): Promise<Outcome> {
    if (!device.apnsToken) return Promise.resolve({ result: "rejected", attempts: 0 });
    // A device registered for another app or environment cannot be reached with this configuration.
    if (!this.matches(device)) return Promise.resolve({ result: "rejected", attempts: 0 });
    const token = device.apnsToken;
    return this.#send(() => alertRequest(this.#target(), token, request, Math.floor(this.#now() / 1000)), request.expiresAt);
  }

  activity(pushToken: string, update: ActivityUpdate): Promise<Outcome> {
    return this.#send(() => activityRequest(this.#target(), pushToken, update, Math.floor(this.#now() / 1000)), update.staleAt);
  }

  async #send(build: () => ApnsRequest, expiresAt: number): Promise<Outcome> {
    let attempts = 0;
    let result: Outcome["result"] = "unreachable";
    while (attempts <= this.#retries) {
      if (attempts > 0) {
        await this.#sleep(this.#base * 2 ** (attempts - 1));
        if (this.#now() / 1000 >= expiresAt) break;
      }
      attempts++;
      const request = build();
      if (!fitsAPNs(request)) return { result: "rejected", attempts };
      const delivery = await deliver(this.#sender, this.#tokens, request);
      if (delivery.result !== "rejected") return { result: delivery.result, attempts };
      // No answer at all is a network failure; an answer is APNs refusing this request.
      result = delivery.status === undefined ? "unreachable" : "rejected";
      // Only an expired provider token is worth another try (with a new token); a refused key would be refused again.
      const retryable = delivery.status === undefined || delivery.status >= 500 || (delivery.status === 403 && delivery.reason === "ExpiredProviderToken");
      if (!retryable) return { result, attempts };
    }
    return { result, attempts };
  }

  close(): void {
    this.#sender.close();
  }
}

/**
 * One sender per configuration in this process: opencode runs an instance of the plugin per
 * location, and they share one HTTP/2 connection and one provider token, since APNs refuses
 * provider tokens refreshed too often. The last instance to release it closes the connection.
 */
const senders = new Map<string, { sender: Promise<DirectSender>; users: number }>();

export interface DirectLease {
  readonly sender: DirectSender;
  release(): void;
}

export async function acquireDirect(config: DirectConfig, options: DirectOptions = {}): Promise<DirectLease> {
  const id = JSON.stringify(config);
  let entry = senders.get(id);
  if (!entry) {
    entry = { sender: DirectSender.load(config, options), users: 0 };
    senders.set(id, entry);
    entry.sender.catch(() => senders.delete(id));
  }
  const current = entry;
  current.users++;
  let sender: DirectSender;
  try {
    sender = await current.sender;
  } catch (error) {
    current.users--;
    throw error;
  }
  let released = false;
  return {
    sender,
    release() {
      if (released) return;
      released = true;
      if (--current.users > 0) return;
      if (senders.get(id) === current) senders.delete(id);
      sender.close();
    },
  };
}

/**
 * Direct mode from the plugin's options, or undefined when it is not configured or the
 * configuration is invalid. Failures are logged with their reason only, never the key.
 */
export async function directFromOptions(options: Readonly<Record<string, unknown>> | undefined, log: (message: string) => void, settings: DirectOptions = {}): Promise<DirectLease | undefined> {
  try {
    const config = directConfig(options);
    if (!config) return undefined;
    const lease = await acquireDirect(config, settings);
    log(`direct mode on: sending to APNs ${config.environment} for ${config.bundleID}`);
    return lease;
  } catch (error) {
    const reason = error instanceof DirectConfigError ? error.message : "the APNs key could not be loaded";
    log(`direct mode off: ${reason}`);
    return undefined;
  }
}
