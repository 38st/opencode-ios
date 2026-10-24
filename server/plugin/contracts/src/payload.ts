import { CONTRACT, isKind, MAX_PLAINTEXT, PAYLOAD_VERSION, type Kind } from "./constants.ts";
import { EnvelopeError } from "./envelope-format.ts";
import { canonicalize } from "./jcs.ts";
import type { Tier } from "./risk.ts";
import { codePointLength, fromUTF8, truncate, utf8 } from "./text.ts";

/** The sealed plaintext (schema/payload.schema.json). Identifiers are never shortened. */
export interface Payload {
  readonly v: number;
  readonly kind: Kind;
  /** The app's own reference for the server, from `registerDevice`. */
  readonly server: string;
  readonly exp: number;
  /** Pending permission requests and forms on this server when the push was sealed. */
  readonly pending: number;
  readonly sessionID?: string;
  readonly rootSessionID?: string;
  readonly title?: string;
  readonly project?: string;
  readonly requestID?: string;
  readonly action?: string;
  readonly summary?: string;
  readonly options?: readonly string[];
  readonly risk?: Tier;
  readonly digest?: string;
  readonly freeText?: boolean;
  readonly reply?: string;
}

const { limits, ellipsis } = CONTRACT.payload;

export const encodePayload = (payload: Payload): Uint8Array => utf8(canonicalize(payload));
const fits = (payload: Payload) => encodePayload(payload).length <= MAX_PLAINTEXT;

function capped(payload: Payload): Payload {
  const cap = (value: string | undefined, limit: number) => (value === undefined ? undefined : truncate(value, limit, ellipsis));
  return {
    ...payload,
    title: cap(payload.title, limits.title),
    project: cap(payload.project, limits.project),
    action: cap(payload.action, limits.action),
    summary: cap(payload.summary, limits.summary),
    options: payload.options?.slice(0, limits.options).map((option) => truncate(option, limits.option, ellipsis)),
  };
}

/**
 * The largest truncation of one text field that fits, or undefined. Lengths below the current one
 * grow monotonically with the kept prefix, so a binary search finds it. Zero removes the field.
 */
function shorten(payload: Payload, field: "summary" | "title" | "project"): Payload | undefined {
  const original = payload[field];
  if (original === undefined) return fits(payload) ? payload : undefined;
  const at = (length: number): Payload => ({ ...payload, [field]: length === 0 ? undefined : truncate(original, length, ellipsis) });
  if (fits(payload)) return payload;
  if (!fits(at(0))) return undefined;
  let low = 0, high = codePointLength(original) - 1;
  while (low < high) {
    const middle = Math.ceil((low + high) / 2);
    if (fits(at(middle))) low = middle;
    else high = middle - 1;
  }
  return at(low);
}

/**
 * Applies the field limits, then frees space in this order until the padded plaintext fits the
 * largest bucket: shorten the summary; drop the options and shorten the summary; drop the summary
 * and shorten the title; drop the title and shorten the project.
 */
export function fitPayload(draft: Payload): { readonly payload: Payload; readonly plaintext: Uint8Array } {
  if (codePointLength(draft.server) > limits.server) throw new RangeError("server reference is too long");
  const base = capped(draft);
  const withoutOptions = { ...base, options: undefined };
  const attempts = [
    () => shorten(base, "summary"),
    () => shorten(withoutOptions, "summary"),
    () => shorten({ ...withoutOptions, summary: undefined }, "title"),
    () => shorten({ ...withoutOptions, summary: undefined, title: undefined }, "project"),
  ];
  for (const attempt of attempts) {
    const payload = attempt();
    if (payload) return { payload, plaintext: encodePayload(payload) };
  }
  throw new RangeError("Payload does not fit the largest padding bucket");
}

const optional = {
  string: ["sessionID", "rootSessionID", "title", "project", "requestID", "action", "summary", "risk", "digest", "reply"],
  boolean: ["freeText"],
} as const;

/** Decodes and checks a plaintext. Unknown keys are ignored and `null` counts as absent. */
export function parsePayload(plaintext: Uint8Array): Payload {
  const fail = (message: string): never => {
    throw new EnvelopeError("payload", message);
  };
  let value: unknown;
  try {
    value = JSON.parse(fromUTF8(plaintext));
  } catch {
    return fail("Plaintext is not UTF-8 JSON");
  }
  if (typeof value !== "object" || value === null || Array.isArray(value)) return fail("Payload must be an object");
  const record = value as Record<string, unknown>;
  const integer = (key: string) => typeof record[key] === "number" && Number.isSafeInteger(record[key]);
  if (!integer("v") || record.v !== PAYLOAD_VERSION) fail("Unsupported payload version");
  if (!isKind(record.kind)) fail("Unknown payload kind");
  if (typeof record.server !== "string") fail("server must be a string");
  if (!integer("exp")) fail("exp must be an integer");
  if (!integer("pending") || (record.pending as number) < 0) fail("pending must be a non-negative integer");
  const present = (key: string) => record[key] !== undefined && record[key] !== null;
  for (const key of optional.string) if (present(key) && typeof record[key] !== "string") fail(`${key} must be a string`);
  for (const key of optional.boolean) if (present(key) && typeof record[key] !== "boolean") fail(`${key} must be a boolean`);
  if (present("options") && (!Array.isArray(record.options) || !record.options.every((item) => typeof item === "string"))) {
    fail("options must be an array of strings");
  }
  return Object.fromEntries(Object.entries(record).filter(([, item]) => item !== null)) as unknown as Payload;
}
