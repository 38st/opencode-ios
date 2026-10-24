import { CONTRACT } from "./constants.ts";

const buckets = CONTRACT.padding.buckets;
const marker = CONTRACT.padding.marker;

export class PaddingError extends Error {
  override readonly name = "PaddingError";
}

/** The smallest bucket that holds the plaintext and its marker byte, or undefined when none does. */
export const bucketFor = (length: number): number | undefined => buckets.find((bucket) => length + 1 <= bucket);

/** ISO/IEC 7816-4 padding: the plaintext, one 0x80 byte, then zero bytes up to the bucket size. */
export function pad(plaintext: Uint8Array): Uint8Array {
  const bucket = bucketFor(plaintext.length);
  if (bucket === undefined) throw new PaddingError(`Plaintext of ${plaintext.length} bytes exceeds the largest bucket`);
  const padded = new Uint8Array(bucket);
  padded.set(plaintext);
  padded[plaintext.length] = marker;
  return padded;
}

export function unpad(padded: Uint8Array): Uint8Array {
  if (!buckets.includes(padded.length)) throw new PaddingError("Padded length is not a bucket size");
  let index = padded.length - 1;
  while (index >= 0 && padded[index] === 0) index--;
  if (index < 0 || padded[index] !== marker) throw new PaddingError("Padding marker is missing");
  return padded.slice(0, index);
}
