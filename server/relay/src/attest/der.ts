/** A DER reader (X.690) for the parts of X.509 that App Attest needs. Definite lengths only. */
export interface Der {
  readonly tag: number;
  /** The contents octets. */
  readonly value: Uint8Array;
  /** The whole element, header included. */
  readonly raw: Uint8Array;
}

export class DerError extends Error {
  override readonly name = "DerError";
}

export const TAG = { boolean: 0x01, integer: 0x02, bitString: 0x03, octetString: 0x04, oid: 0x06, utcTime: 0x17, generalizedTime: 0x18, sequence: 0x30 } as const;

/** Reads one element at `offset`. */
export function readDer(bytes: Uint8Array, offset = 0): Der {
  if (bytes.length - offset < 2) throw new DerError("truncated");
  const tag = bytes[offset]!;
  if ((tag & 0x1f) === 0x1f) throw new DerError("multi-byte tags are not supported");
  let length = bytes[offset + 1]!, header = 2;
  if (length & 0x80) {
    const count = length & 0x7f;
    if (count < 1 || count > 3 || bytes.length - offset < 2 + count) throw new DerError("bad length");
    length = 0;
    for (let index = 0; index < count; index++) length = length * 256 + bytes[offset + 2 + index]!;
    header += count;
  }
  const end = offset + header + length;
  if (end > bytes.length) throw new DerError("truncated");
  return { tag, value: bytes.subarray(offset + header, end), raw: bytes.subarray(offset, end) };
}

/** Reads `bytes` as exactly one element. */
export function parseDer(bytes: Uint8Array): Der {
  const element = readDer(bytes);
  if (element.raw.length !== bytes.length) throw new DerError("trailing bytes");
  return element;
}

/** The elements inside a constructed element. */
export function children(element: Der): Der[] {
  if (!(element.tag & 0x20)) throw new DerError("not constructed");
  const items: Der[] = [];
  for (let offset = 0; offset < element.value.length; ) {
    const item = readDer(element.value, offset);
    items.push(item);
    offset += item.raw.length;
  }
  return items;
}

export function expect(element: Der | undefined, tag: number): Der {
  if (!element || element.tag !== tag) throw new DerError(`expected tag ${tag}`);
  return element;
}

export function oid(element: Der): string {
  const bytes = expect(element, TAG.oid).value;
  if (!bytes.length) throw new DerError("empty OID");
  const parts: number[] = [];
  let value = 0;
  for (const byte of bytes) {
    value = value * 128 + (byte & 0x7f);
    if (!(byte & 0x80)) {
      parts.push(value);
      value = 0;
    }
  }
  const [first = 0, ...rest] = parts;
  const head = first < 80 ? [Math.floor(first / 40), first % 40] : [2, first - 80];
  return [...head, ...rest].join(".");
}

/** The bits of a BIT STRING with no unused bits. */
export function bitString(element: Der): Uint8Array {
  const value = expect(element, TAG.bitString).value;
  if (value[0] !== 0) throw new DerError("unused bits in BIT STRING");
  return value.subarray(1);
}

export function time(element: Der): number {
  const text = new TextDecoder().decode(element.value);
  const match =
    element.tag === TAG.utcTime ? /^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(text) : element.tag === TAG.generalizedTime ? /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(text) : null;
  if (!match) throw new DerError("bad time");
  const [, y, mo, d, h, mi, s] = match.map(Number) as number[];
  const year = element.tag === TAG.utcTime ? (y! < 50 ? 2000 + y! : 1900 + y!) : y!;
  return Date.UTC(year, mo! - 1, d!, h!, mi!, s!) / 1000;
}
