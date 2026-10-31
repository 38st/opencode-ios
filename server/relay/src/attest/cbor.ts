/**
 * The CBOR subset App Attest uses (RFC 8949): unsigned and negative integers, byte and text
 * strings, arrays and maps, all with definite lengths. Anything else is refused.
 */
export type Cbor = number | Uint8Array | string | Cbor[] | Map<Cbor, Cbor>;

export class CborError extends Error {
  override readonly name = "CborError";
}

const MAX_DEPTH = 8;
const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false });

export function decodeCbor(bytes: Uint8Array): Cbor {
  let offset = 0;
  const take = (count: number): Uint8Array => {
    if (count > bytes.length - offset) throw new CborError("truncated");
    const slice = bytes.subarray(offset, offset + count);
    offset += count;
    return slice;
  };
  const argument = (info: number): number => {
    if (info < 24) return info;
    const size = info === 24 ? 1 : info === 25 ? 2 : info === 26 ? 4 : info === 27 ? 8 : 0;
    if (!size) throw new CborError("unsupported length");
    let value = 0;
    for (const byte of take(size)) value = value * 256 + byte;
    if (!Number.isSafeInteger(value)) throw new CborError("integer too large");
    return value;
  };
  const item = (depth: number): Cbor => {
    if (depth > MAX_DEPTH) throw new CborError("too deep");
    const [head] = take(1);
    const major = head! >> 5, length = argument(head! & 31);
    switch (major) {
      case 0:
        return length;
      case 1:
        return -1 - length;
      case 2:
        return take(length).slice();
      case 3:
        return decoder.decode(take(length));
      case 4: {
        if (length > bytes.length - offset) throw new CborError("truncated");
        return Array.from({ length }, () => item(depth + 1));
      }
      case 5: {
        if (length > bytes.length - offset) throw new CborError("truncated");
        const map = new Map<Cbor, Cbor>();
        for (let index = 0; index < length; index++) map.set(item(depth + 1), item(depth + 1));
        return map;
      }
      default:
        throw new CborError("unsupported type");
    }
  };
  const value = item(0);
  if (offset !== bytes.length) throw new CborError("trailing bytes");
  return value;
}

/** A text-keyed map entry, or undefined. */
export const field = (value: Cbor, key: string): Cbor | undefined => (value instanceof Map ? value.get(key) : undefined);
export const isBytes = (value: Cbor | undefined): value is Uint8Array => value instanceof Uint8Array;
