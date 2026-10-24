import * as base64url from "./base64url.ts";
import type { Kind } from "./constants.ts";
import { aadFor, EnvelopeError, parseEnvelope, type Envelope } from "./envelope-format.ts";
import { cryptoKeyPair, importPrivateKey, importPublicKey, info, keyPairFrom, suite, type RawKeyPair } from "./hpke.ts";
import { pad, PaddingError, unpad } from "./padding.ts";
import { parsePayload, type Payload } from "./payload.ts";

export interface SealInput {
  readonly kind: Kind;
  readonly exp: number;
  readonly kid: string;
  /** The unpadded plaintext, normally `fitPayload(...).plaintext`. */
  readonly plaintext: Uint8Array;
  readonly recipientPublicKey: Uint8Array;
  readonly sender: RawKeyPair;
  /** Tests and the vector generator only: a fixed ephemeral private key makes the output deterministic. */
  readonly ephemeralPrivateKey?: Uint8Array;
}

/** HPKE auth-mode seal of the padded plaintext, with aad = "oc1|kind|exp|kid". */
export async function sealEnvelope(input: SealInput): Promise<Envelope> {
  return sealPadded({ ...input, plaintext: pad(input.plaintext) });
}

/** Seals bytes that are already padded (or deliberately malformed, for rejection vectors). */
export async function sealPadded(input: SealInput): Promise<Envelope> {
  const context = await suite.createSenderContext({
    recipientPublicKey: await importPublicKey(input.recipientPublicKey),
    senderKey: await cryptoKeyPair(input.sender),
    info,
    ...(input.ephemeralPrivateKey ? { ekm: await cryptoKeyPair(await keyPairFrom(input.ephemeralPrivateKey)) } : {}),
  });
  const ct = new Uint8Array(await context.seal(input.plaintext as Uint8Array<ArrayBuffer>, aadFor(input.kind, input.exp, input.kid) as Uint8Array<ArrayBuffer>));
  return {
    v: 1,
    kid: input.kid,
    kind: input.kind,
    exp: input.exp,
    enc: base64url.encode(new Uint8Array(context.enc)),
    ct: base64url.encode(ct),
  };
}

export interface KeyEntry {
  readonly recipientPrivateKey: Uint8Array;
  /** The plugin's static public key, pinned when the device registered. */
  readonly senderPublicKey: Uint8Array;
}

export interface OpenOptions {
  /** Unix seconds. An envelope is expired once `now >= exp`. */
  readonly now: number;
  readonly key: (kid: string) => KeyEntry | undefined;
}

export interface Opened {
  readonly envelope: Envelope;
  readonly plaintext: Uint8Array;
  readonly payload: Payload;
}

/**
 * Opens an envelope, checking in this order: structure, version, expiry, key, authentication,
 * padding, payload, then that the payload repeats the envelope's kind and expiry.
 */
export async function openEnvelope(value: unknown, options: OpenOptions): Promise<Opened> {
  const envelope = parseEnvelope(value);
  if (options.now >= envelope.exp) throw new EnvelopeError("expired");
  const entry = options.key(envelope.kid);
  if (!entry) throw new EnvelopeError("unknownKey");
  let padded: Uint8Array;
  try {
    const context = await suite.createRecipientContext({
      recipientKey: await importPrivateKey(entry.recipientPrivateKey),
      enc: envelope.encBytes,
      senderPublicKey: await importPublicKey(entry.senderPublicKey),
      info,
    });
    padded = new Uint8Array(await context.open(envelope.ctBytes as Uint8Array<ArrayBuffer>, aadFor(envelope.kind, envelope.exp, envelope.kid) as Uint8Array<ArrayBuffer>));
  } catch (error) {
    throw new EnvelopeError("authentication", error instanceof Error ? error.message : "authentication");
  }
  let plaintext: Uint8Array;
  try {
    plaintext = unpad(padded);
  } catch (error) {
    if (error instanceof PaddingError) throw new EnvelopeError("padding", error.message);
    throw error;
  }
  const payload = parsePayload(plaintext);
  if (payload.kind !== envelope.kind || payload.exp !== envelope.exp) throw new EnvelopeError("mismatch");
  const { v, kid, kind, exp, enc, ct } = envelope;
  return { envelope: { v, kid, kind, exp, enc, ct }, plaintext, payload };
}
