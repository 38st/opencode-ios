import type { ApnsRequest } from "./request.ts";
import type { TokenProvider } from "./token.ts";

export type DeliveryResult = "delivered" | "gone" | "throttled" | "rejected";

export interface ApnsResponse {
  readonly status: number;
  readonly reason?: string;
}

/** Sends one request to APNs with the given provider token. Implementations: fetch (Workers) and node:http2. */
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
  /** APNs's HTTP status, absent when no answer arrived. Logged, as a number only. */
  readonly status?: number;
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
  return { result: mapResponse(response), status: response.status };
}

export const apnsPath = (deviceToken: string) => `/3/device/${deviceToken}`;
