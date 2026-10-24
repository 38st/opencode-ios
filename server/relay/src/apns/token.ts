import * as base64url from "../../../contracts/src/base64url.ts";
import { CONTRACT } from "../../../contracts/src/constants.ts";

const encoder = new TextEncoder();
/** APNs accepts a provider token for an hour; the relay reuses one for 50 minutes. */
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
export async function signProviderToken(key: ApnsKey, issuedAt: number, signingKey?: CryptoKey): Promise<string> {
  const input = `${part({ alg: "ES256", kid: key.keyID })}.${part({ iss: key.teamID, iat: issuedAt })}`;
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, signingKey ?? (await importSigningKey(key.privateKey)), encoder.encode(input));
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

/** Caches one token per process (Node) or per Durable Object (Workers). */
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

/** The Node provider: one cache in process memory. */
export function localTokenProvider(key: ApnsKey, now: () => number): TokenProvider {
  const signingKey = importSigningKey(key.privateKey);
  const cache = new TokenCache(async (issuedAt) => signProviderToken(key, issuedAt, await signingKey), now);
  return {
    token: async () => (await cache.issued()).token,
    reject: async (token) => cache.reject(token),
  };
}
