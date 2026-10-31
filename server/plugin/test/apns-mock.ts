// A local stand-in for APNs, for direct mode: HTTP/2 without TLS on 127.0.0.1, so nothing ever
// reaches Apple. Used by the unit tests and by Tools/push-e2e (Node runs this file directly).
import { chmod, mkdtemp, rm, writeFile } from "node:fs/promises";
import http2 from "node:http2";
import os from "node:os";
import path from "node:path";

export interface ApnsCall {
  readonly path: string;
  readonly deviceToken: string;
  readonly headers: Readonly<Record<string, string>>;
  readonly body: any;
  /** The HTTP/2 session the request arrived on, numbered from 1. */
  readonly session: number;
}

export interface ApnsAnswer {
  readonly status: number;
  readonly reason?: string;
}

/** Records every request, and answers from a per-device-token script, then 200. */
export async function startApnsMock() {
  const calls: ApnsCall[] = [];
  const scripts = new Map<string, ApnsAnswer[]>();
  const sessions = new Map<http2.Http2Session, number>();
  const server = http2.createServer();
  server.on("session", (session) => sessions.set(session, sessions.size + 1));
  server.on("stream", (stream: http2.ServerHttp2Stream, raw: http2.IncomingHttpHeaders) => {
    let text = "";
    stream.setEncoding("utf8");
    stream.on("data", (chunk: string) => (text += chunk));
    stream.on("end", () => {
      const requestPath = String(raw[":path"] ?? "");
      const headers = Object.fromEntries(Object.entries(raw).filter(([name]) => !name.startsWith(":")).map(([name, value]) => [name, String(value)]));
      let body: unknown;
      try {
        body = JSON.parse(text);
      } catch {
        body = text;
      }
      const deviceToken = /^\/3\/device\/(.+)$/.exec(requestPath)?.[1] ?? "";
      calls.push({ path: requestPath, deviceToken, headers, body, session: sessions.get(stream.session!) ?? 0 });
      const answer = scripts.get(deviceToken)?.shift() ?? { status: 200 };
      stream.respond({ ":status": answer.status, "apns-id": "00000000-0000-0000-0000-000000000000", "content-type": "application/json" });
      stream.end(answer.reason ? JSON.stringify({ reason: answer.reason }) : "");
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const origin = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
  return {
    origin,
    /** Both environments point at the mock, as `DirectOptions.hosts`. */
    hosts: { sandbox: origin, production: origin },
    calls,
    sessions: () => sessions.size,
    /** The next answers for a device or push token, in order. */
    script: (token: string, ...answers: ApnsAnswer[]) => void scripts.set(token, answers),
    close: () => new Promise<void>((resolve) => {
      for (const session of sessions.keys()) session.destroy();
      server.close(() => resolve());
    }),
  };
}

export type ApnsMock = Awaited<ReturnType<typeof startApnsMock>>;

const decode = (part: string) => Buffer.from(part, "base64url");

/** Checks a provider token's ES256 signature with the key's public half and returns its header and claims. */
export async function verifyProviderToken(token: string, publicKey: CryptoKey) {
  const [header, claims, signature] = token.split(".");
  if (!header || !claims || !signature) throw new Error("not a JWT");
  const valid = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, publicKey, decode(signature), new TextEncoder().encode(`${header}.${claims}`));
  return { valid, header: JSON.parse(decode(header).toString("utf8")), claims: JSON.parse(decode(claims).toString("utf8")) };
}

/** A throwaway APNs signing key, written as a .p8 file with the given mode (600 by default). */
export async function testKey(mode = 0o600) {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = Buffer.from(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${der.toString("base64").replace(/(.{64})/g, "$1\n").trim()}\n-----END PRIVATE KEY-----\n`;
  const directory = await mkdtemp(path.join(os.tmpdir(), "mobilepush-apns-"));
  const file = path.join(directory, "AuthKey_TESTKEY001.p8");
  await writeFile(file, pem, { mode });
  await chmod(file, mode);
  return { file, pem, publicKey: pair.publicKey, remove: () => rm(directory, { recursive: true, force: true }) };
}
