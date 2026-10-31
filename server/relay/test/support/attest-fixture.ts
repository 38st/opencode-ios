// App Attest objects for the tests: a test root and intermediate CA, a device key, and attestations and
// assertions laid out as Apple documents them. WebCrypto only, so it runs in workerd and in Node.

const encoder = new TextEncoder();

function concat(...parts: Uint8Array[]): Uint8Array<ArrayBuffer> {
  const out = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
}

const sha256 = async (...parts: Uint8Array[]) => new Uint8Array(await crypto.subtle.digest("SHA-256", concat(...parts)));
export const base64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));

// DER writer.
function tlv(tag: number, ...contents: Uint8Array[]): Uint8Array<ArrayBuffer> {
  const body = concat(...contents);
  const length =
    body.length < 128 ? [body.length] : body.length < 256 ? [0x81, body.length] : [0x82, body.length >> 8, body.length & 255];
  return concat(Uint8Array.from([tag, ...length]), body);
}
const seq = (...items: Uint8Array[]) => tlv(0x30, ...items);
const integer = (bytes: Uint8Array) => tlv(0x02, bytes[0]! & 0x80 ? concat(Uint8Array.of(0), bytes) : bytes);
const octets = (bytes: Uint8Array) => tlv(0x04, bytes);
const bits = (bytes: Uint8Array) => tlv(0x03, Uint8Array.of(0), bytes);
function oid(dotted: string): Uint8Array {
  const [first, second, ...rest] = dotted.split(".").map(Number);
  const out = [first! * 40 + second!];
  for (const part of rest) {
    const groups = [part & 0x7f];
    for (let value = part >> 7; value > 0; value >>= 7) groups.unshift((value & 0x7f) | 0x80);
    out.push(...groups);
  }
  return tlv(0x06, Uint8Array.from(out));
}
const name = (common: string) => seq(tlv(0x31, seq(oid("2.5.4.3"), tlv(0x0c, encoder.encode(common)))));
const generalized = (seconds: number) => tlv(0x18, encoder.encode(new Date(seconds * 1000).toISOString().replace(/[-:T]/g, "").slice(0, 14) + "Z"));

function derSignature(raw: Uint8Array): Uint8Array {
  const half = raw.length / 2;
  const trim = (part: Uint8Array) => {
    let start = 0;
    while (start < part.length - 1 && part[start] === 0) start++;
    return part.subarray(start);
  };
  return seq(integer(trim(raw.subarray(0, half))), integer(trim(raw.subarray(half))));
}

// CBOR writer.
function head(major: number, value: number): Uint8Array {
  if (value < 24) return Uint8Array.of((major << 5) | value);
  if (value < 256) return Uint8Array.of((major << 5) | 24, value);
  return Uint8Array.of((major << 5) | 25, value >> 8, value & 255);
}
type CborIn = Uint8Array | string | number | CborIn[] | { [key: string]: CborIn };
export function cbor(value: CborIn): Uint8Array {
  if (value instanceof Uint8Array) return concat(head(2, value.length), value);
  if (typeof value === "string") {
    const bytes = encoder.encode(value);
    return concat(head(3, bytes.length), bytes);
  }
  if (typeof value === "number") return value >= 0 ? head(0, value) : head(1, -1 - value);
  if (Array.isArray(value)) return concat(head(4, value.length), ...value.map(cbor));
  const entries = Object.entries(value);
  return concat(head(5, entries.length), ...entries.flatMap(([key, item]) => [cbor(key), cbor(item)]));
}

type Curve = "P-256" | "P-384";
type KeyPair = { readonly publicKey: CryptoKey; readonly privateKey: CryptoKey };
interface Issuer {
  readonly keys: KeyPair;
  readonly curve: Curve;
  readonly name: Uint8Array;
}

const CURVE_OID: Record<Curve, string> = { "P-256": "1.2.840.10045.3.1.7", "P-384": "1.3.132.0.34" };
const generate = (curve: Curve) => crypto.subtle.generateKey({ name: "ECDSA", namedCurve: curve }, true, ["sign", "verify"]) as Promise<KeyPair>;

async function certificate(options: {
  subject: Uint8Array;
  publicKey: CryptoKey;
  issuer: Issuer;
  ca: boolean;
  notBefore: number;
  notAfter: number;
  extensions?: Uint8Array[];
}): Promise<Uint8Array> {
  const sha = options.issuer.curve === "P-384" ? "SHA-384" : "SHA-256";
  const algorithm = seq(oid(sha === "SHA-384" ? "1.2.840.10045.4.3.3" : "1.2.840.10045.4.3.2"));
  const extensions = [...(options.extensions ?? [])];
  if (options.ca) extensions.push(seq(oid("2.5.29.19"), tlv(0x01, Uint8Array.of(0xff)), octets(seq(tlv(0x01, Uint8Array.of(0xff))))));
  const tbs = seq(
    tlv(0xa0, integer(Uint8Array.of(2))),
    integer(crypto.getRandomValues(new Uint8Array(8)).map((byte, index) => (index === 0 ? (byte & 0x7f) | 1 : byte))),
    algorithm,
    options.issuer.name,
    seq(generalized(options.notBefore), generalized(options.notAfter)),
    options.subject,
    new Uint8Array((await crypto.subtle.exportKey("spki", options.publicKey)) as ArrayBuffer),
    ...(extensions.length ? [tlv(0xa3, seq(...extensions))] : []),
  );
  const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: sha }, options.issuer.keys.privateKey, tbs));
  return seq(tbs, algorithm, bits(derSignature(raw)));
}

const pem = (der: Uint8Array) => `-----BEGIN CERTIFICATE-----\n${base64(der).replace(/.{1,64}/g, "$&\n")}-----END CERTIFICATE-----\n`;

const AAGUID = {
  production: concat(encoder.encode("appattest"), new Uint8Array(7)),
  development: encoder.encode("appattestdevelop"),
};

export interface AttestTamper {
  /** Attest or assert for a different app ID. */
  appID?: string;
  aaguid?: Uint8Array;
  /** A counter other than 0 in an attestation. */
  counter?: number;
  /** Sign the nonce of other client data. */
  clientDataHash?: Uint8Array;
  /** Report a credential ID other than the key ID. */
  credentialID?: Uint8Array;
  /** Issue the credential certificate from a CA the relay does not trust. */
  untrusted?: boolean;
  /** The credential certificate expired yesterday. */
  expired?: boolean;
}

export interface AttestDevice {
  /** Standard base64, as DCAppAttestService reports it. */
  readonly keyID: string;
  attest(clientDataHash: Uint8Array, tamper?: AttestTamper): Promise<Uint8Array>;
  assert(clientDataHash: Uint8Array, counter: number, tamper?: AttestTamper): Promise<Uint8Array>;
}

export interface AttestFixture {
  /** The test root, for APP_ATTEST_TEST_ROOTS. */
  readonly rootPEM: string;
  device(): Promise<AttestDevice>;
}

export async function attestFixture(appID: string): Promise<AttestFixture> {
  const now = Math.floor(Date.now() / 1000), day = 86_400;
  async function authority(common: string, parent?: Issuer): Promise<{ issuer: Issuer; der: Uint8Array }> {
    const keys = await generate("P-384");
    const issuer: Issuer = { keys, curve: "P-384", name: name(common) };
    const der = await certificate({ subject: issuer.name, publicKey: keys.publicKey, issuer: parent ?? issuer, ca: true, notBefore: now - day, notAfter: now + 3650 * day });
    return { issuer, der };
  }
  const root = await authority("Test App Attestation Root CA");
  const intermediate = await authority("Test App Attestation CA 1", root.issuer);
  const stranger = await authority("Untrusted CA");

  return {
    rootPEM: pem(root.der),
    async device() {
      const keys = await generate("P-256");
      const point = new Uint8Array((await crypto.subtle.exportKey("raw", keys.publicKey)) as ArrayBuffer);
      const keyID = await sha256(point);
      const authData = async (tamper: AttestTamper, counter: number) => {
        const view = new DataView(new ArrayBuffer(4));
        view.setUint32(0, counter);
        return concat(await sha256(encoder.encode(tamper.appID ?? appID)), Uint8Array.of(0x40), new Uint8Array(view.buffer));
      };
      return {
        keyID: base64(keyID),
        async attest(clientDataHash, tamper = {}) {
          const credentialID = tamper.credentialID ?? keyID;
          const data = concat(
            await authData(tamper, tamper.counter ?? 0),
            tamper.aaguid ?? AAGUID.production,
            Uint8Array.of(0, credentialID.length),
            credentialID,
            cbor({ "1": 2 }),
          );
          const nonce = await sha256(data, tamper.clientDataHash ?? clientDataHash);
          const issuer = tamper.untrusted ? stranger : intermediate;
          const leaf = await certificate({
            subject: name(base64(keyID)),
            publicKey: keys.publicKey,
            issuer: issuer.issuer,
            ca: false,
            notBefore: now - 2 * day,
            notAfter: tamper.expired ? now - day : now + 30 * day,
            extensions: [seq(oid("1.2.840.113635.100.8.2"), octets(seq(tlv(0xa1, octets(nonce)))))],
          });
          return cbor({ fmt: "apple-appattest", attStmt: { x5c: [leaf, issuer.der], receipt: new Uint8Array(16) }, authData: data });
        },
        async assert(clientDataHash, counter, tamper = {}) {
          const data = await authData(tamper, counter);
          const nonce = await sha256(data, tamper.clientDataHash ?? clientDataHash);
          const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, keys.privateKey, nonce));
          return cbor({ signature: derSignature(raw), authenticatorData: data });
        },
      };
    },
  };
}

export const developmentAAGUID = AAGUID.development;
