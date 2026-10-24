/**
 * RFC 8785 JSON Canonicalization Scheme. Strings are first made well-formed (a lone surrogate
 * becomes U+FFFD), because Swift strings cannot hold one. Object members whose value is
 * `undefined` are omitted, as JSON.stringify does.
 */
export function canonicalize(value: unknown): string {
  if (value === null) return "null";
  switch (typeof value) {
    case "boolean":
      return value ? "true" : "false";
    case "number":
      if (!Number.isFinite(value)) throw new TypeError("JCS cannot encode a non-finite number");
      // ECMAScript Number::toString, which RFC 8785 §3.2.2.3 adopts. JSON.stringify(-0) is "0".
      return JSON.stringify(value);
    case "string":
      return JSON.stringify(value.toWellFormed());
    case "object": {
      if (Array.isArray(value)) return `[${value.map((item) => canonicalize(item)).join(",")}]`;
      const entries = Object.entries(value as Record<string, unknown>)
        .filter(([, item]) => item !== undefined)
        .map(([key, item]) => [key.toWellFormed(), item] as const);
      // Default sort compares UTF-16 code units, which is the order RFC 8785 §3.2.3 requires.
      entries.sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
      for (let index = 1; index < entries.length; index++) {
        if (entries[index - 1]![0] === entries[index]![0]) throw new TypeError("JCS cannot encode duplicate keys");
      }
      return `{${entries.map(([key, item]) => `${JSON.stringify(key)}:${canonicalize(item)}`).join(",")}}`;
    }
    default:
      throw new TypeError(`JCS cannot encode ${typeof value}`);
  }
}
