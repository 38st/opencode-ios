const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false });

export const utf8 = (text: string): Uint8Array => encoder.encode(text.toWellFormed());
export const fromUTF8 = (bytes: Uint8Array): string => decoder.decode(bytes);

/** Lengths and truncation count Unicode code points (Swift `unicodeScalars`, JavaScript string iteration). */
export const codePointLength = (text: string): number => {
  let count = 0;
  for (const _ of text) count++;
  return count;
};

/** Keeps at most `limit` code points. A cut string ends with the ellipsis, which counts toward the limit. */
export function truncate(text: string, limit: number, ellipsis = "…"): string {
  if (codePointLength(text) <= limit) return text;
  if (limit <= 0) return "";
  const points = Array.from(text);
  return points.slice(0, Math.max(0, limit - codePointLength(ellipsis))).join("") + ellipsis;
}

export const hex = (bytes: Uint8Array): string => Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");

export function fromHex(text: string): Uint8Array {
  if (!/^(?:[0-9a-f]{2})*$/.test(text)) throw new Error("Invalid hex");
  const bytes = new Uint8Array(text.length / 2);
  for (let index = 0; index < bytes.length; index++) bytes[index] = Number.parseInt(text.slice(index * 2, index * 2 + 2), 16);
  return bytes;
}

export const sha256 = async (bytes: Uint8Array): Promise<Uint8Array> =>
  new Uint8Array(await crypto.subtle.digest("SHA-256", bytes as Uint8Array<ArrayBuffer>));
