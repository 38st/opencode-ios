import { CipherSuite, HkdfSha256 } from "@hpke/core";
import { Chacha20Poly1305 } from "@hpke/chacha20poly1305";
import { DhkemX25519HkdfSha256, HkdfSha256 as KemHkdfSha256, X25519 } from "@hpke/dhkem-x25519";
import { HPKE_INFO } from "./constants.ts";
import { utf8 } from "./text.ts";

/**
 * DHKEM(X25519, HKDF-SHA256), HKDF-SHA256, ChaCha20-Poly1305. The X25519 and ChaCha20 code is
 * pure JavaScript, so sealing does not depend on the host runtime's WebCrypto curve support.
 */
export const suite = new CipherSuite({
  kem: new DhkemX25519HkdfSha256(),
  kdf: new HkdfSha256(),
  aead: new Chacha20Poly1305(),
});
export const info = utf8(HPKE_INFO);
const primitives = new X25519(new KemHkdfSha256());

/** Raw 32-byte X25519 keys: CryptoKit's `rawRepresentation`, RFC 7748 encoding. */
export interface RawKeyPair {
  readonly privateKey: Uint8Array;
  readonly publicKey: Uint8Array;
}

const exact = (buffer: ArrayBuffer): Uint8Array => {
  const bytes = new Uint8Array(buffer);
  if (bytes.length !== 32) throw new Error(`Expected a 32-byte key, got ${bytes.length}`);
  return bytes.slice();
};

export const importPrivateKey = (raw: Uint8Array): Promise<CryptoKey> => suite.kem.deserializePrivateKey(raw);
export const importPublicKey = (raw: Uint8Array): Promise<CryptoKey> => suite.kem.deserializePublicKey(raw);

export async function publicKeyFor(privateKey: Uint8Array): Promise<Uint8Array> {
  return exact(await primitives.serializePublicKey(await primitives.derivePublicKey(await importPrivateKey(privateKey))));
}

export async function keyPairFrom(privateKey: Uint8Array): Promise<RawKeyPair> {
  if (privateKey.length !== 32) throw new Error("An X25519 private key is 32 bytes");
  return { privateKey: privateKey.slice(), publicKey: await publicKeyFor(privateKey) };
}

export async function generateKeyPair(): Promise<RawKeyPair> {
  const pair = await suite.kem.generateKeyPair();
  return {
    privateKey: exact(await suite.kem.serializePrivateKey(pair.privateKey)),
    publicKey: exact(await suite.kem.serializePublicKey(pair.publicKey)),
  };
}

export interface CryptoKeyPairLike {
  readonly privateKey: CryptoKey;
  readonly publicKey: CryptoKey;
}

export async function cryptoKeyPair(pair: RawKeyPair): Promise<CryptoKeyPairLike> {
  return { privateKey: await importPrivateKey(pair.privateKey), publicKey: await importPublicKey(pair.publicKey) };
}
