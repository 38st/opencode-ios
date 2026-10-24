/**
 * The relay logs counts and outcomes only: never a token, secret, device or sender ID, IP
 * address, APNs reason text or envelope. The field names below are the complete vocabulary.
 */
export type LogFields = {
  readonly route?: string;
  readonly kind?: string;
  readonly result?: string;
  readonly status?: number;
  readonly count?: number;
};

export type Logger = (event: string, fields?: LogFields) => void;

const allowed = new Set(["route", "kind", "result", "status", "count"]);

/** One JSON line. Unknown fields and values that are not short identifiers or numbers are dropped. */
export function formatLog(event: string, fields: LogFields = {}): string {
  const safe = Object.entries(fields).filter(
    ([key, value]) => allowed.has(key) && (typeof value === "number" || /^[a-z0-9_./-]{1,40}$/i.test(String(value))),
  );
  return JSON.stringify({ event, ...Object.fromEntries(safe) });
}

export const consoleLogger: Logger = (event, fields) => console.log(formatLog(event, fields));
