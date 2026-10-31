import { bitString, children, expect, oid, parseDer, TAG, time, type Der } from "./der.ts";

/** The parts of an X.509 certificate (RFC 5280) that chain validation and App Attest read. */
export interface Certificate {
  readonly tbs: Uint8Array;
  readonly signatureAlgorithm: string;
  readonly signature: Uint8Array;
  readonly issuer: Uint8Array;
  readonly subject: Uint8Array;
  readonly notBefore: number;
  readonly notAfter: number;
  /** The SubjectPublicKeyInfo, as WebCrypto imports it. */
  readonly spki: Uint8Array;
  readonly curve: string;
  /** The public key bits: an uncompressed EC point. */
  readonly publicKey: Uint8Array;
  readonly isCA: boolean;
  /** Extension values (the contents of extnValue) by OID. */
  readonly extensions: ReadonlyMap<string, Uint8Array>;
}

const OID = {
  ecPublicKey: "1.2.840.10045.2.1",
  p256: "1.2.840.10045.3.1.7",
  p384: "1.3.132.0.34",
  ecdsaSHA256: "1.2.840.10045.4.3.2",
  ecdsaSHA384: "1.2.840.10045.4.3.3",
  basicConstraints: "2.5.29.19",
} as const;

const CURVES: Record<string, { name: string; size: number }> = { [OID.p256]: { name: "P-256", size: 32 }, [OID.p384]: { name: "P-384", size: 48 } };
const HASHES: Record<string, string> = { [OID.ecdsaSHA256]: "SHA-256", [OID.ecdsaSHA384]: "SHA-384" };

export function parseCertificate(bytes: Uint8Array): Certificate {
  const [tbsElement, algorithm, signature] = children(expect(parseDer(bytes), TAG.sequence));
  const tbs = children(expect(tbsElement, TAG.sequence));
  // The explicit [0] version is present in every v3 certificate.
  const fields = tbs[0]?.tag === 0xa0 ? tbs.slice(1) : tbs;
  const [, , issuer, validity, subject, spki, ...rest] = fields;
  const [notBefore, notAfter] = children(expect(validity, TAG.sequence));
  const [keyAlgorithm, keyBits] = children(expect(spki, TAG.sequence));
  const [keyType, curve] = children(expect(keyAlgorithm, TAG.sequence));
  if (oid(keyType!) !== OID.ecPublicKey) throw new Error("not an EC key");
  const extensions = new Map<string, Uint8Array>();
  const block = rest.find((element) => element.tag === 0xa3);
  for (const extension of block ? children(expect(children(block)[0], TAG.sequence)) : []) {
    const parts = children(expect(extension, TAG.sequence));
    extensions.set(oid(parts[0]!), expect(parts.at(-1), TAG.octetString).value);
  }
  return {
    tbs: tbsElement!.raw,
    signatureAlgorithm: oid(children(expect(algorithm, TAG.sequence))[0]!),
    signature: bitString(signature!),
    issuer: expect(issuer, TAG.sequence).raw,
    subject: expect(subject, TAG.sequence).raw,
    notBefore: time(notBefore!),
    notAfter: time(notAfter!),
    spki: spki!.raw,
    curve: oid(curve!),
    publicKey: bitString(keyBits!),
    isCA: isCA(extensions.get(OID.basicConstraints)),
    extensions,
  };
}

function isCA(value: Uint8Array | undefined): boolean {
  if (!value) return false;
  const [flag] = children(parseDer(value));
  return flag?.tag === TAG.boolean && flag.value[0] === 0xff;
}

const equal = (a: Uint8Array, b: Uint8Array) => a.length === b.length && a.every((byte, index) => byte === b[index]);

/** An ECDSA signature from DER (SEQUENCE of two INTEGERs) to the fixed-size r||s WebCrypto verifies. */
export function rawSignature(der: Uint8Array, size: number): Uint8Array<ArrayBuffer> {
  const parts = children(expect(parseDer(der), TAG.sequence)).map((part) => expect(part, TAG.integer).value);
  if (parts.length !== 2) throw new Error("bad signature");
  const out = new Uint8Array(size * 2);
  parts.forEach((part, index) => {
    let start = 0;
    while (start < part.length - 1 && part[start] === 0) start++;
    const digits = part.subarray(start);
    if (digits.length > size) throw new Error("bad signature");
    out.set(digits, index * size + size - digits.length);
  });
  return out;
}

export async function importKey(certificate: Pick<Certificate, "spki" | "curve">): Promise<{ key: CryptoKey; size: number }> {
  const curve = CURVES[certificate.curve];
  if (!curve) throw new Error("unsupported curve");
  const key = await crypto.subtle.importKey("spki", new Uint8Array(certificate.spki), { name: "ECDSA", namedCurve: curve.name }, false, ["verify"]);
  return { key, size: curve.size };
}

/** Whether `issuer`'s key signed `certificate`. */
export async function signedBy(certificate: Certificate, issuer: Certificate): Promise<boolean> {
  const hash = HASHES[certificate.signatureAlgorithm];
  if (!hash || !equal(certificate.issuer, issuer.subject)) return false;
  try {
    const { key, size } = await importKey(issuer);
    return await crypto.subtle.verify({ name: "ECDSA", hash }, key, rawSignature(certificate.signature, size), new Uint8Array(certificate.tbs));
  } catch {
    return false;
  }
}

/**
 * Validates `chain` (leaf first, then intermediates) up to one of the pinned `roots`: names chain,
 * every signature verifies, every issuer is a CA, and every certificate is valid at `now`.
 */
export async function validChain(chain: readonly Certificate[], roots: readonly Certificate[], now: number): Promise<boolean> {
  if (!chain.length) return false;
  const current = (certificate: Certificate) => certificate.notBefore <= now && now <= certificate.notAfter;
  for (let index = 0; index < chain.length; index++) {
    const certificate = chain[index]!;
    if (!current(certificate)) return false;
    const issuer = chain[index + 1];
    if (issuer) {
      if (!issuer.isCA || !(await signedBy(certificate, issuer))) return false;
      continue;
    }
    for (const root of roots) if (root.isCA && current(root) && (await signedBy(certificate, root))) return true;
    return false;
  }
  return false;
}

export function pemCertificates(pem: string): Uint8Array<ArrayBuffer>[] {
  return [...pem.matchAll(/-----BEGIN CERTIFICATE-----([\s\S]+?)-----END CERTIFICATE-----/g)].map((match) =>
    Uint8Array.from(atob(match[1]!.replace(/\s+/g, "")), (character) => character.charCodeAt(0)),
  );
}

