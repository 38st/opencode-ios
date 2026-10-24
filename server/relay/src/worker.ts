import { DurableObject } from "cloudflare:workers";
import { createApp, type RelayDeps } from "./app.ts";
import { FetchSender } from "./apns/fetch-sender.ts";
import { importSigningKey, signProviderToken, TOKEN_LIFETIME, TokenCache, type IssuedToken, type TokenProvider } from "./apns/token.ts";
import { readConfig, type RelayEnvironment } from "./config.ts";
import { hitCounters, type Limiter, type LimitRule } from "./limiter.ts";
import { consoleLogger } from "./log.ts";
import { d1 } from "./sql-d1.ts";
import { Store } from "./store.ts";

export interface Env extends RelayEnvironment {
  readonly DB: D1Database;
  readonly LIMITER: DurableObjectNamespace<RateLimiter>;
  readonly TOKENS: DurableObjectNamespace<ApnsTokenCache>;
}

const seconds = () => Math.floor(Date.now() / 1000);

/** One object per limited key (a device, or a hashed IP address for registration). */
export class RateLimiter extends DurableObject<Env> {
  async hit(rules: LimitRule[], now: number): Promise<boolean> {
    return hitCounters(this.ctx.storage, rules, now);
  }
}

/**
 * The single place provider tokens are minted, so every isolate shares one token and APNs never
 * sees more than one new token per 50 minutes (it refuses updates more often than every 20).
 */
export class ApnsTokenCache extends DurableObject<Env> {
  #cache: TokenCache | undefined;

  async #tokens(): Promise<TokenCache> {
    if (this.#cache) return this.#cache;
    const { apns } = readConfig(this.env);
    const signingKey = await importSigningKey(apns.privateKey);
    const initial = await this.ctx.storage.get<IssuedToken>("token");
    this.#cache = new TokenCache(async (issuedAt) => {
      const token = await signProviderToken(apns, issuedAt, signingKey);
      await this.ctx.storage.put("token", { token, issuedAt });
      return token;
    }, seconds, initial);
    return this.#cache;
  }

  async issued(): Promise<IssuedToken> {
    return (await this.#tokens()).issued();
  }

  async reject(token: string): Promise<void> {
    const tokens = await this.#tokens();
    tokens.reject(token);
    const stored = await this.ctx.storage.get<IssuedToken>("token");
    if (stored?.token === token) await this.ctx.storage.delete("token");
  }
}

class DurableLimiter implements Limiter {
  readonly #namespace: Env["LIMITER"];
  constructor(namespace: Env["LIMITER"]) {
    this.#namespace = namespace;
  }
  hit(key: string, rules: readonly LimitRule[], now: number): Promise<boolean> {
    return this.#namespace.get(this.#namespace.idFromName(key)).hit([...rules], now);
  }
}

/** Keeps the shared token in isolate memory until it would expire. */
function durableTokens(namespace: Env["TOKENS"]): TokenProvider {
  let local: IssuedToken | undefined;
  const stub = () => namespace.get(namespace.idFromName("apns"));
  return {
    async token() {
      if (!local || seconds() - local.issuedAt >= TOKEN_LIFETIME) local = await stub().issued();
      return local.token;
    },
    async reject(token) {
      if (local?.token === token) local = undefined;
      await stub().reject(token);
    },
  };
}

const deps = new WeakMap<Env, RelayDeps>();
function resolve(env: Env): RelayDeps {
  const existing = deps.get(env);
  if (existing) return existing;
  const config = readConfig(env);
  const created: RelayDeps = {
    config,
    store: new Store(d1(env.DB)),
    limiter: new DurableLimiter(env.LIMITER),
    sender: new FetchSender(config.apns),
    tokens: durableTokens(env.TOKENS),
    log: consoleLogger,
    now: seconds,
  };
  deps.set(env, created);
  return created;
}

const app = createApp({
  resolve: (c) => resolve(c.env as Env),
  clientIP: (c) => c.req.header("cf-connecting-ip"),
});

export default { fetch: app.fetch } satisfies ExportedHandler<Env>;
