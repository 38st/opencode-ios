import * as base64url from "./base64url.ts";
import { CONTRACT, isKind, type Kind } from "./constants.ts";
import { utf8 } from "./text.ts";

/** The `oc` object in the APNs payload. Every field except `ct` and `enc` is visible to the relay. */
export interface Envelope {
  readonly v: number;
  readonly kid: string;
  readonly kind: Kind;
  readonly exp: number;
  readonly enc: string;
  readonly ct: string;
}

/** The failure codes every implementation reports, in the order the checks run. */
export type EnvelopeErrorCode =
  | "malformed"
  | "unsupportedVersion"
  | "expired"
  | "unknownKey"
  | "authentication"
  | "padding"
  | "payload"
  | "mismatch";

export class EnvelopeError extends Error {
  override readonly name = "EnvelopeError";
  readonly code: EnvelopeErrorCode;
  constructor(code: EnvelopeErrorCode, message: string = code) {
    super(message);
    this.code = code;
  }
}

export const KEY_ID = /^[A-Za-z0-9_-]{16,64}$/;
const MAX_EXP = 4_102_444_800; // 2100-01-01T00:00:00Z keeps exp a small, exact integer everywhere.
const { keyBytes, tagBytes, maxEncodedCiphertext } = CONTRACT.envelope;
export const CIPHERTEXT_LENGTHS: readonly number[] = CONTRACT.padding.buckets.map((bucket) => bucket + tagBytes);

const fail = (message: string): never => {
  throw new EnvelopeError("malformed", message);
};

/**
 * Checks the structure without decrypting: the relay and both apps apply the same rules.
 * Any integer version other than 1 is unsupported, whatever shape the rest has.
 */
export function parseEnvelope(value: unknown): Envelope & { readonly encBytes: Uint8Array; readonly ctBytes: Uint8Array } {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return fail("Envelope must be an object");
  const record = value as Record<string, unknown>;
  const { v, kid, kind, exp, enc, ct } = record;
  if (typeof v !== "number" || !Number.isSafeInteger(v)) return fail("v must be an integer");
  if (v !== CONTRACT.envelope.version) throw new EnvelopeError("unsupportedVersion", `Envelope version ${v} is not supported`);
  if (typeof kid !== "string" || !KEY_ID.test(kid)) return fail("kid is invalid");
  if (!isKind(kind)) return fail("kind is unknown");
  if (typeof exp !== "number" || !Number.isSafeInteger(exp) || exp < 0 || exp > MAX_EXP) return fail("exp is invalid");
  if (typeof enc !== "string") return fail("enc must be a string");
  if (typeof ct !== "string" || ct.length > maxEncodedCiphertext) return fail("ct must be a string of at most 3072 characters");
  const encBytes = base64url.decode(enc);
  if (!encBytes || encBytes.length !== keyBytes) return fail("enc must be 32 bytes of base64url");
  const ctBytes = base64url.decode(ct);
  if (!ctBytes || !CIPHERTEXT_LENGTHS.includes(ctBytes.length)) return fail("ct must be a padded bucket plus the tag");
  return { v, kid, kind, exp, enc, ct, encBytes, ctBytes };
}

/** aad = "oc1|kind|exp|kid", binding the fields the relay can see to the ciphertext. */
export const aadString = (kind: Kind, exp: number, kid: string): string => `${CONTRACT.envelope.aadPrefix}|${kind}|${exp}|${kid}`;
export const aadFor = (kind: Kind, exp: number, kid: string): Uint8Array => utf8(aadString(kind, exp, kid));
