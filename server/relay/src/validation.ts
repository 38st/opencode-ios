/** Request-body checks. Each returns the clean value or undefined; routes answer 400 on undefined. */

export type Json = Record<string, unknown>;

export const isObject = (value: unknown): value is Json => typeof value === "object" && value !== null && !Array.isArray(value);

/** APNs device and Live Activity push tokens are hex strings (32 bytes today; allow growth). */
export const pushToken = (value: unknown): string | undefined =>
  typeof value === "string" && /^[0-9a-fA-F]{64,400}$/.test(value) && value.length % 2 === 0 ? value.toLowerCase() : undefined;

export const apnsEnvironment = (value: unknown): "sandbox" | "production" | undefined =>
  value === "sandbox" || value === "production" ? value : undefined;

export const bundleID = (value: unknown): string | undefined =>
  typeof value === "string" && /^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/.test(value) && value.length <= 155 ? value : undefined;

/** Opaque IDs the app or plugin chooses: collapse IDs, thread IDs and activity references. */
export const opaqueID = (value: unknown, max = 64): string | undefined =>
  typeof value === "string" && value.length >= 1 && value.length <= max && /^[A-Za-z0-9_-]+$/.test(value) ? value : undefined;

export const unixSeconds = (value: unknown): number | undefined =>
  typeof value === "number" && Number.isSafeInteger(value) && value > 0 && value <= 4_102_444_800 ? value : undefined;

export const priority = (value: unknown): 5 | 10 | undefined => (value === 5 || value === 10 ? value : undefined);

export async function jsonBody(request: Request): Promise<Json | undefined> {
  try {
    const value: unknown = await request.json();
    return isObject(value) ? value : undefined;
  } catch {
    return undefined;
  }
}

/** A JSON object from raw body bytes, for routes that also hash the exact bytes they received. */
export function jsonBytes(bytes: Uint8Array): Json | undefined {
  try {
    const value: unknown = JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes));
    return isObject(value) ? value : undefined;
  } catch {
    return undefined;
  }
}

/** Standard base64 (App Attest key IDs, attestations and assertions), decoded, or undefined. */
export function base64Bytes(value: unknown, maxLength: number): Uint8Array | undefined {
  if (typeof value !== "string" || value.length > maxLength || value.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) return undefined;
  return Uint8Array.from(atob(value), (character) => character.charCodeAt(0));
}

/** The bearer credential from an Authorization header, or undefined. */
export function bearer(header: string | undefined): string | undefined {
  const match = /^Bearer ([A-Za-z0-9_-]{16,200})$/.exec(header ?? "");
  return match?.[1];
}
