import { CONTRACT, type Envelope, type Kind } from "../contracts/src/index.ts";
import type { Device } from "./registry.ts";

export type PushResult = "delivered" | "gone" | "throttled" | "rejected" | "unreachable";

export interface PushRequest {
  readonly kind: Kind;
  readonly priority: 5 | 10;
  readonly collapse: string;
  readonly thread: string;
  readonly expiresAt: number;
  readonly envelope: Envelope;
}

export interface ActivityUpdate {
  readonly ref: string;
  readonly event: "update" | "end";
  readonly state: Readonly<Record<string, string | number>>;
  readonly staleAt: number;
  readonly dismissAt?: number;
  readonly priority: 5 | 10;
}

export interface Outcome {
  readonly result: PushResult;
  readonly attempts: number;
}

export interface RelayOptions {
  readonly fetch?: typeof fetch;
  readonly sleep?: (milliseconds: number) => Promise<void>;
  readonly now?: () => number;
  readonly retries?: number;
  readonly retryBaseMilliseconds?: number;
}

/**
 * Posts to a device's relay with its send token. Network failures, 5xx answers and `rejected`
 * are retried up to three times with exponential backoff while the push is still unexpired.
 * A 401 means the app revoked this server's sender, which the plugin treats as `gone`.
 */
export class RelayClient {
  readonly #fetch: typeof fetch;
  readonly #sleep: (milliseconds: number) => Promise<void>;
  readonly #now: () => number;
  readonly #retries: number;
  readonly #base: number;

  constructor(options: RelayOptions = {}) {
    this.#fetch = options.fetch ?? fetch;
    this.#sleep = options.sleep ?? ((milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)));
    this.#now = options.now ?? Date.now;
    this.#retries = options.retries ?? CONTRACT.plugin.retries;
    this.#base = options.retryBaseMilliseconds ?? CONTRACT.plugin.retryBaseMilliseconds;
  }

  push(device: Device, request: PushRequest): Promise<Outcome> {
    return this.#post(device, "/v1/push", request, request.expiresAt);
  }

  activity(device: Device, update: ActivityUpdate): Promise<Outcome> {
    return this.#post(device, "/v1/activity", update, update.staleAt);
  }

  async #post(device: Device, path: string, body: unknown, expiresAt: number): Promise<Outcome> {
    let result: PushResult = "unreachable";
    let attempts = 0;
    while (attempts <= this.#retries) {
      if (attempts > 0) {
        await this.#sleep(this.#base * 2 ** (attempts - 1));
        if (this.#now() / 1000 >= expiresAt) break;
      }
      attempts++;
      try {
        // A relay URL may carry a path prefix (a relay behind a reverse proxy), so append rather than resolve.
        const response = await this.#fetch(device.relayURL.replace(/\/+$/, "") + path, {
          method: "POST",
          headers: { authorization: `Bearer ${device.sendToken}`, "content-type": "application/json" },
          body: JSON.stringify(body),
          signal: AbortSignal.timeout(10_000),
        });
        if (response.status === 401) return { result: "gone", attempts };
        if (response.status >= 500) {
          result = "unreachable";
          continue;
        }
        if (!response.ok) return { result: "rejected", attempts };
        const answer = (await response.json()) as { result?: string };
        if (answer.result === "delivered" || answer.result === "gone" || answer.result === "throttled") {
          return { result: answer.result, attempts };
        }
        result = "rejected";
      } catch {
        result = "unreachable";
      }
    }
    return { result, attempts };
  }
}
