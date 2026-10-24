import * as base64url from "../../contracts/src/base64url.ts";

const encoder = new TextEncoder();

/** A random secret with a recognisable prefix, so secret scanners can find a leaked one. */
export const randomToken = (prefix: string, bytes = 32): string =>
  prefix + base64url.encode(crypto.getRandomValues(new Uint8Array(bytes)));

export async function sha256Hex(text: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(text)));
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

/** Constant-time comparison of two equal-length hex digests. */
export function sameDigest(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let index = 0; index < a.length; index++) difference |= a.charCodeAt(index) ^ b.charCodeAt(index);
  return difference === 0;
}
