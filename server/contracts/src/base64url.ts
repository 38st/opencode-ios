const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
const values = new Map([...alphabet].map((char, index) => [char, index]));

/** RFC 4648 §5 base64url without padding. */
export function encode(bytes: Uint8Array): string {
  let output = "";
  for (let index = 0; index < bytes.length; index += 3) {
    const a = bytes[index]!, b = bytes[index + 1], c = bytes[index + 2];
    output += alphabet[a >> 2]! + alphabet[((a & 3) << 4) | ((b ?? 0) >> 4)]!;
    if (b !== undefined) output += alphabet[((b & 15) << 2) | ((c ?? 0) >> 6)]!;
    if (c !== undefined) output += alphabet[c & 63]!;
  }
  return output;
}

/**
 * Strict decoding: only the base64url alphabet, no padding, and canonical trailing bits.
 * Returns undefined for anything else, so every implementation rejects the same strings.
 */
export function decode(text: string): Uint8Array | undefined {
  if (text.length % 4 === 1) return undefined;
  const bytes = new Uint8Array(Math.floor((text.length * 3) / 4));
  let buffer = 0, bits = 0, offset = 0;
  for (const char of text) {
    const value = values.get(char);
    if (value === undefined) return undefined;
    buffer = (buffer << 6) | value;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      bytes[offset++] = (buffer >> bits) & 255;
    }
  }
  if (bits > 0 && (buffer & ((1 << bits) - 1)) !== 0) return undefined;
  return bytes;
}
