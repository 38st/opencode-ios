// The APNs requests both senders build: the relay, and the plugin when it sends to Apple itself.
// WebCrypto only, so the same code runs in Workers and in Node.
import * as base64url from "./base64url.ts";
import { CONTRACT, kindPolicy, type Kind } from "./constants.ts";
import type { Envelope } from "./envelope-format.ts";

export type ApnsEnvironment = "sandbox" | "production";

export interface ApnsTarget {
  readonly env: ApnsEnvironment;
  readonly bundleID: string;
}

export interface ApnsRequest {
  readonly environment: ApnsEnvironment;
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
 * the extension (crashed, killed, out of time) never offers an action (README.md).
 */
export function alertRequest(target: ApnsTarget, deviceToken: string, push: AlertPush, now: number): ApnsRequest {
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
    environment: target.env,
    deviceToken,
    headers: {
      "apns-push-type": "alert",
      "apns-topic": target.bundleID,
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
  // Plaintext to Apple: the coarse fields of schema/activity-state.schema.json only.
  readonly state: object;
  readonly staleAt: number;
  readonly dismissAt?: number;
  readonly priority: 5 | 10;
}

export function activityRequest(target: ApnsTarget, pushToken: string, update: ActivityPush, now: number): ApnsRequest {
  const aps: Record<string, unknown> = {
    timestamp: now,
    event: update.event,
    "content-state": update.state,
    "stale-date": update.staleAt,
  };
  if (update.event === "end" && update.dismissAt !== undefined) aps["dismissal-date"] = update.dismissAt;
  return {
    environment: target.env,
    deviceToken: pushToken,
    headers: {
      "apns-push-type": "liveactivity",
      "apns-topic": `${target.bundleID}.push-type.liveactivity`,
      "apns-priority": String(update.priority),
      "apns-expiration": String(update.staleAt),
    },
    body: JSON.stringify({ aps }),
  };
}

export const fitsAPNs = (request: ApnsRequest): boolean => new TextEncoder().encode(request.body).length <= CONTRACT.apns.maxPayloadBytes;
export const apnsPath = (deviceToken: string) => `/3/device/${deviceToken}`;

// Provider tokens.

const encoder = new TextEncoder();
/** APNs accepts a provider token for an hour; senders reuse one for 50 minutes. */
export const TOKEN_LIFETIME = CONTRACT.apns.tokenCacheSeconds;

export interface ApnsKey {
  readonly teamID: string;
  readonly keyID: string;
  readonly privateKey: string;
}

/** Imports Apple's .p8 file: an ECDSA P-256 key in PKCS#8 PEM. */
export async function importSigningKey(pem: string): Promise<CryptoKey> {
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (char) => char.charCodeAt(0));
  return crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

const part = (value: unknown) => base64url.encode(encoder.encode(JSON.stringify(value)));

/** An ES256 JWT with `kid` and `iss`/`iat`. WebCrypto's ECDSA signature is already JWS's r || s form. */
export async function signProviderToken(key: Omit<ApnsKey, "privateKey"> & { readonly privateKey?: string }, issuedAt: number, signingKey?: CryptoKey): Promise<string> {
  const input = `${part({ alg: "ES256", kid: key.keyID })}.${part({ iss: key.teamID, iat: issuedAt })}`;
  const signer = signingKey ?? (await importSigningKey(key.privateKey ?? ""));
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, signer, encoder.encode(input));
  return `${input}.${base64url.encode(new Uint8Array(signature))}`;
}

export interface IssuedToken {
  readonly token: string;
  readonly issuedAt: number;
}

export interface TokenProvider {
  token(): Promise<string>;
  /** Called with a token APNs refused, so only that token is replaced. */
  reject(token: string): Promise<void>;
}

/** One cached provider token, minted again after TOKEN_LIFETIME seconds or when APNs refuses it. */
export class TokenCache {
  readonly #mint: (issuedAt: number) => Promise<string>;
  readonly #now: () => number;
  #current: IssuedToken | undefined;
  #pending: Promise<IssuedToken> | undefined;

  constructor(mint: (issuedAt: number) => Promise<string>, now: () => number, initial?: IssuedToken) {
    this.#mint = mint;
    this.#now = now;
    this.#current = initial;
  }

  async issued(): Promise<IssuedToken> {
    const now = this.#now();
    if (this.#current && now - this.#current.issuedAt < TOKEN_LIFETIME && now >= this.#current.issuedAt) return this.#current;
    this.#pending ??= this.#mint(now).then(
      (token) => {
        this.#current = { token, issuedAt: now };
        this.#pending = undefined;
        return this.#current;
      },
      (error: unknown) => {
        this.#pending = undefined;
        throw error;
      },
    );
    return this.#pending;
  }

  reject(token: string): void {
    if (this.#current?.token === token) this.#current = undefined;
  }
}

/** One provider token per process, from a signing key imported once. */
export function localTokenProvider(key: Omit<ApnsKey, "privateKey">, signingKey: Promise<CryptoKey>, now: () => number): TokenProvider {
  const cache = new TokenCache(async (issuedAt) => signProviderToken(key, issuedAt, await signingKey), now);
  return {
    token: async () => (await cache.issued()).token,
    reject: async (token) => cache.reject(token),
  };
}

// Results.

export type DeliveryResult = "delivered" | "gone" | "throttled" | "rejected";

export interface ApnsResponse {
  readonly status: number;
  readonly reason?: string;
}

/** Sends one request to APNs with the given provider token: fetch (Workers) or node:http2. */
export interface ApnsSender {
  send(request: ApnsRequest, providerToken: string): Promise<ApnsResponse>;
}

/** Unregistered, BadDeviceToken and 410 are gone; 429 is throttled; anything else, network failures included, is rejected. */
export function mapResponse(response: ApnsResponse): DeliveryResult {
  if (response.status === 200) return "delivered";
  if (response.status === 410 || response.reason === "Unregistered" || response.reason === "BadDeviceToken") return "gone";
  if (response.status === 429) return "throttled";
  return "rejected";
}

export interface Delivery {
  readonly result: DeliveryResult;
  /** APNs's HTTP status, absent when no answer arrived. */
  readonly status?: number;
  /** APNs's reason, when it gave one. */
  readonly reason?: string;
}

export async function deliver(sender: ApnsSender, tokens: TokenProvider, request: ApnsRequest): Promise<Delivery> {
  let token: string, response: ApnsResponse;
  try {
    token = await tokens.token();
    response = await sender.send(request, token);
  } catch {
    return { result: "rejected" };
  }
  if (response.status === 403 && (response.reason === "ExpiredProviderToken" || response.reason === "InvalidProviderToken")) {
    await tokens.reject(token);
  }
  return { result: mapResponse(response), status: response.status, ...(response.reason ? { reason: response.reason } : {}) };
}
