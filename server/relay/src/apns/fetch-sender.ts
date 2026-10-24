import type { RelayConfig } from "../config.ts";
import { apnsPath, type ApnsResponse, type ApnsSender } from "./delivery.ts";
import type { ApnsRequest } from "./request.ts";

/**
 * The Workers sender. Whether a Worker's outbound fetch reaches APNs over HTTP/2 is unverified
 * (README, "HTTP/2 check"); the Node entry point's node:http2 sender is the fallback.
 */
export class FetchSender implements ApnsSender {
  readonly #hosts: RelayConfig["apns"];
  constructor(hosts: RelayConfig["apns"]) {
    this.#hosts = hosts;
  }

  async send(request: ApnsRequest, providerToken: string): Promise<ApnsResponse> {
    const origin = request.environment === "sandbox" ? this.#hosts.sandboxURL : this.#hosts.productionURL;
    const response = await fetch(origin + apnsPath(request.deviceToken), {
      method: "POST",
      headers: { ...request.headers, authorization: `bearer ${providerToken}`, "content-type": "application/json" },
      body: request.body,
      signal: AbortSignal.timeout(10_000),
    });
    const text = await response.text();
    let reason: string | undefined;
    try {
      reason = (JSON.parse(text) as { reason?: string }).reason;
    } catch {
      reason = undefined;
    }
    return { status: response.status, ...(reason ? { reason } : {}) };
  }
}
