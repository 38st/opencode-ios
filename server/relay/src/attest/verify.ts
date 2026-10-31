import { decodeCbor, field, isBytes, type Cbor } from "./cbor.ts";
import { children, expect, parseDer, TAG } from "./der.ts";
import { importKey, parseCertificate, rawSignature, validChain, type Certificate } from "./x509.ts";

/**
 * App Attest verification, following Apple's "Validating apps that connect to your server":
 * an attestation proves a key lives in a genuine device's Secure Enclave and belongs to this app;
 * each later assertion proves a request came from that key.
 */
export type AttestEnvironment = "development" | "production";

export interface AttestedKey {
  /** SubjectPublicKeyInfo of the attested P-256 key. */
  readonly publicKey: Uint8Array;
  /** The `<team ID>.<bundle ID>` the key was attested for. */
  readonly appID: string;
  readonly environment: AttestEnvironment;
}

export class AttestError extends Error {
  override readonly name = "AttestError";
}

/** The App Attest nonce extension in the credential certificate. */
const NONCE_OID = "1.2.840.113635.100.8.2";
const P256 = "1.2.840.10045.3.1.7";
const AAGUID: Record<AttestEnvironment, Uint8Array> = {
  development: new TextEncoder().encode("appattestdevelop"),
  production: Uint8Array.from([...new TextEncoder().encode("appattest"), 0, 0, 0, 0, 0, 0, 0]),
};

const fail = (reason: string): never => {
  throw new AttestError(reason);
};

export async function sha256(...parts: Uint8Array[]): Promise<Uint8Array<ArrayBuffer>> {
  const joined = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    joined.set(part, offset);
    offset += part.length;
  }
  return new Uint8Array(await crypto.subtle.digest("SHA-256", joined));
}

const equal = (a: Uint8Array, b: Uint8Array) => a.length === b.length && a.every((byte, index) => byte === b[index]);
const text = (value: string) => new TextEncoder().encode(value);

/** The authenticator data both objects carry (WebAuthn layout). */
function authenticatorData(bytes: Uint8Array) {
  if (bytes.length < 37) fail("short authenticator data");
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  return { rpIDHash: bytes.subarray(0, 32), counter: view.getUint32(33), rest: bytes.subarray(37) };
}

async function matchingAppID(rpIDHash: Uint8Array, appIDs: readonly string[]): Promise<string> {
  for (const appID of appIDs) if (equal(rpIDHash, await sha256(text(appID)))) return appID;
  return fail("app ID mismatch");
}

export interface AttestationCheck {
  readonly attestation: Uint8Array;
  /** The key ID the app reports: base64 of SHA-256 of the public key point. */
  readonly keyID: Uint8Array;
  readonly clientDataHash: Uint8Array;
  readonly appIDs: readonly string[];
  readonly environment: AttestEnvironment;
  readonly roots: readonly Certificate[];
  /** Unix seconds. */
  readonly now: number;
}

/** Verifies an attestation object and returns the key to store. Throws AttestError on any mismatch. */
export async function verifyAttestation(check: AttestationCheck): Promise<AttestedKey> {
  let object: Cbor;
  try {
    object = decodeCbor(check.attestation);
  } catch {
    return fail("malformed attestation");
  }
  const statement = field(object, "attStmt"), authData = field(object, "authData"), x5c = statement && field(statement, "x5c");
  if (field(object, "fmt") !== "apple-appattest" || !isBytes(authData) || !Array.isArray(x5c) || x5c.length < 2 || !x5c.every(isBytes)) {
    fail("malformed attestation");
  }
  let chain: Certificate[];
  try {
    chain = (x5c as Uint8Array[]).map(parseCertificate);
  } catch {
    return fail("malformed certificate");
  }
  // 1. The credential certificate chains to the pinned App Attest root.
  if (!(await validChain(chain, check.roots, check.now))) fail("untrusted certificate chain");
  const credential = chain[0]!;
  if (credential.curve !== P256) fail("credential key is not P-256");
  // 2–4. The certificate's nonce extension equals SHA-256(authData || clientDataHash).
  const nonce = await sha256(authData as Uint8Array, check.clientDataHash);
  if (!equal(certificateNonce(credential), nonce)) fail("nonce mismatch");
  // 5. The key ID is the SHA-256 of the credential's public key.
  if (!equal(await sha256(credential.publicKey), check.keyID)) fail("key ID mismatch");
  // 6. The RP ID is the hash of the app ID.
  const data = authenticatorData(authData as Uint8Array);
  const appID = await matchingAppID(data.rpIDHash, check.appIDs);
  // 7. A fresh key has never signed anything.
  if (data.counter !== 0) fail("counter is not zero");
  // 8. The AAGUID names the expected environment.
  if (data.rest.length < 18 || !equal(data.rest.subarray(0, 16), AAGUID[check.environment])) fail("wrong environment");
  // 9. The credential ID is the key ID.
  const length = (data.rest[16]! << 8) | data.rest[17]!;
  if (!equal(data.rest.subarray(18, 18 + length), check.keyID)) fail("credential ID mismatch");
  return { publicKey: credential.spki, appID, environment: check.environment };
}

function certificateNonce(certificate: Certificate): Uint8Array {
  const extension = certificate.extensions.get(NONCE_OID) ?? fail("missing nonce");
  try {
    const [tagged] = children(parseDer(extension));
    if (tagged?.tag !== 0xa1) fail("bad nonce");
    return expect(children(tagged!)[0], TAG.octetString).value;
  } catch (error) {
    if (error instanceof AttestError) throw error;
    return fail("bad nonce");
  }
}

export interface AssertionCheck {
  readonly assertion: Uint8Array;
  readonly clientDataHash: Uint8Array;
  readonly key: Pick<AttestedKey, "publicKey" | "appID">;
  /** The counter stored from the last accepted assertion (0 after attestation). */
  readonly counter: number;
}

/** Verifies an assertion and returns its counter, which the caller must store. Throws AttestError. */
export async function verifyAssertion(check: AssertionCheck): Promise<number> {
  let object: Cbor;
  try {
    object = decodeCbor(check.assertion);
  } catch {
    return fail("malformed assertion");
  }
  const signature = field(object, "signature"), authData = field(object, "authenticatorData");
  if (!isBytes(signature) || !isBytes(authData)) return fail("malformed assertion");
  // 1–3. The signature over SHA-256(authenticatorData || clientDataHash) verifies with the stored key.
  const nonce = await sha256(authData, check.clientDataHash);
  const { key, size } = await importKey({ spki: check.key.publicKey, curve: P256 });
  let valid = false;
  try {
    valid = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, rawSignature(signature, size), nonce);
  } catch {
    valid = false;
  }
  if (!valid) fail("bad signature");
  // 4. The RP ID is the app the key was attested for.
  const data = authenticatorData(authData);
  if (!equal(data.rpIDHash, await sha256(text(check.key.appID)))) fail("app ID mismatch");
  // 5. The counter only grows, so a captured assertion cannot be replayed.
  if (data.counter <= check.counter) fail("counter did not increase");
  return data.counter;
}
