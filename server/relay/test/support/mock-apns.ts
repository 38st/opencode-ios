// A local stand-in for APNs. It listens twice, sharing one request log: cleartext HTTP/2 (prior
// knowledge) for node:http2, and HTTP/1.1 for workerd's fetch and the control endpoints. It checks
// every request the way APNs would and records it. It never contacts Apple.
//
// Device tokens choose the reply: 410… Unregistered, 400b… BadDeviceToken, 4290… 429,
// 5000… 500, 403e… ExpiredProviderToken; anything else 200.
// Control, on the HTTP/1.1 port: GET /_mock/requests, POST /_mock/reset.
import { createPublicKey, verify, type KeyObject } from "node:crypto";
import http from "node:http";
import http2 from "node:http2";
import net from "node:net";
import type { MockRequest } from "./fixture.ts";

export type { MockRequest };

export interface MockApnsOptions {
  readonly teamID: string;
  readonly keyID: string;
  readonly publicKeyPEM: string;
  readonly bundleIDs: readonly string[];
  readonly now?: () => number;
}

export interface MockApns {
  /** HTTP/1.1: APNs requests and the /_mock control endpoints. */
  readonly url: string;
  /** Cleartext HTTP/2: APNs requests. */
  readonly h2URL: string;
  readonly requests: MockRequest[];
  reset(): void;
  /** Ends every HTTP/2 session, as APNs does with GOAWAY when it rotates connections. */
  dropConnections(): void;
  close(): Promise<void>;
}

const base64url = (text: string) => Buffer.from(text, "base64url");
const json = (text: string) => {
  try {
    return JSON.parse(text) as unknown;
  } catch {
    return undefined;
  }
};

function checkJWT(authorization: string | undefined, options: MockApnsOptions, key: KeyObject, problems: string[]) {
  const match = /^bearer ([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)$/.exec(authorization ?? "");
  if (!match) return problems.push("authorization is not a bearer JWT"), undefined;
  const [, header, claims, signature] = match as unknown as [string, string, string, string];
  const head = json(base64url(header).toString()) as { alg?: string; kid?: string } | undefined;
  const body = json(base64url(claims).toString()) as { iss?: string; iat?: number } | undefined;
  if (head?.alg !== "ES256") problems.push("JWT alg is not ES256");
  if (head?.kid !== options.keyID) problems.push("JWT kid is not the key ID");
  if (body?.iss !== options.teamID) problems.push("JWT iss is not the team ID");
  const now = options.now?.() ?? Math.floor(Date.now() / 1000);
  if (typeof body?.iat !== "number" || Math.abs(now - body.iat) > 3600) problems.push("JWT iat is missing or more than an hour off");
  const valid = verify("sha256", Buffer.from(`${header}.${claims}`), { key, dsaEncoding: "ieee-p1363" }, base64url(signature));
  if (!valid) problems.push("JWT signature does not verify");
  return match[0].slice("bearer ".length);
}

function check(path: string, headers: Record<string, string>, text: string, options: MockApnsOptions, key: KeyObject) {
  const problems: string[] = [];
  const token = /^\/3\/device\/([0-9a-f]+)$/.exec(path)?.[1] ?? "";
  if (!token) problems.push("path is not /3/device/<hex token>");
  const jwt = checkJWT(headers.authorization, options, key, problems);
  const type = headers["apns-push-type"];
  const topic = headers["apns-topic"] ?? "";
  if (!["5", "10"].includes(headers["apns-priority"] ?? "")) problems.push("apns-priority is not 5 or 10");
  if (!/^\d+$/.test(headers["apns-expiration"] ?? "")) problems.push("apns-expiration is not an integer");
  const bytes = Buffer.byteLength(text);
  if (bytes > 4096) problems.push(`payload is ${bytes} bytes, over 4096`);
  const body = json(text) as { aps?: Record<string, unknown>; oc?: Record<string, unknown> } | undefined;
  const aps = body?.aps;
  if (!aps) problems.push("payload has no aps dictionary");
  if (type === "alert") {
    if (!options.bundleIDs.includes(topic)) problems.push("apns-topic is not an allowed bundle ID");
    const collapse = headers["apns-collapse-id"];
    if (!collapse || Buffer.byteLength(collapse) > 64) problems.push("apns-collapse-id is missing or over 64 bytes");
    if (aps?.["mutable-content"] !== 1) problems.push("mutable-content is not 1");
    if (typeof aps?.["thread-id"] !== "string" || !/^[A-Za-z0-9_-]{1,64}$/.test(aps["thread-id"] as string)) problems.push("thread-id is not opaque");
    if (typeof aps?.category !== "string") problems.push("category is missing");
    if (!["passive", "active", "time-sensitive", "critical"].includes(aps?.["interruption-level"] as string)) problems.push("interruption-level is invalid");
    const alert = aps?.alert as { body?: unknown } | undefined;
    if (typeof alert?.body !== "string") problems.push("alert body is missing");
    const oc = body?.oc;
    if (!oc || Object.keys(oc).sort().join(",") !== "ct,enc,exp,kid,kind,v") problems.push("oc is not exactly the envelope fields");
  } else if (type === "liveactivity") {
    if (!topic.endsWith(".push-type.liveactivity") || !options.bundleIDs.includes(topic.slice(0, -".push-type.liveactivity".length))) {
      problems.push("apns-topic is not <bundle>.push-type.liveactivity");
    }
    if (!["update", "end"].includes(aps?.event as string)) problems.push("event is not update or end");
    if (typeof aps?.timestamp !== "number") problems.push("timestamp is missing");
    if (typeof aps?.["content-state"] !== "object") problems.push("content-state is missing");
    if (typeof aps?.["stale-date"] !== "number") problems.push("stale-date is missing");
  } else problems.push(`apns-push-type ${type} is unexpected`);
  return { token, jwt, body, bytes, problems };
}

const replies: [string, number, string][] = [
  ["410", 410, "Unregistered"],
  ["400b", 400, "BadDeviceToken"],
  ["4290", 429, "TooManyRequests"],
  ["5000", 500, "InternalServerError"],
  ["403e", 403, "ExpiredProviderToken"],
];

export async function startMockApns(options: MockApnsOptions): Promise<MockApns> {
  const key = createPublicKey(options.publicKeyPEM);
  const requests: MockRequest[] = [];

  const handle = (protocol: "h1" | "h2", method: string, path: string, headers: Record<string, string>, text: string) => {
    if (path === "/_mock/requests" && method === "GET") return { status: 200, body: { requests } };
    if (path === "/_mock/reset" && method === "POST") return requests.splice(0), { status: 200, body: {} };
    if (method !== "POST") return { status: 405, body: { reason: "MethodNotAllowed" } };
    const result = check(path, headers, text, options, key);
    const reply = replies.find(([prefix]) => result.token.startsWith(prefix));
    const status = result.problems.length ? 400 : (reply?.[1] ?? 200);
    const reason = result.problems.length ? "MockValidationFailed" : reply?.[2];
    requests.push({ protocol, path, token: result.token, headers, body: result.body, bytes: result.bytes, jwt: result.jwt, problems: result.problems, status });
    return { status, body: reason ? { reason } : undefined };
  };

  const flatten = (raw: Record<string, string | string[] | undefined>) =>
    Object.fromEntries(Object.entries(raw).filter(([name]) => !name.startsWith(":")).map(([name, value]) => [name, Array.isArray(value) ? value.join(",") : (value ?? "")]));

  const h1 = http.createServer((request, response) => {
    let text = "";
    request.setEncoding("utf8");
    request.on("data", (chunk: string) => (text += chunk));
    request.on("end", () => {
      const reply = handle("h1", request.method ?? "GET", request.url ?? "/", flatten(request.headers), text);
      response.writeHead(reply.status, { "content-type": "application/json", "apns-id": crypto.randomUUID() });
      response.end(reply.body === undefined ? "" : JSON.stringify(reply.body));
    });
  });
  const h2 = http2.createServer();
  const sessions = new Set<http2.ServerHttp2Session>();
  h2.on("session", (session: http2.ServerHttp2Session) => {
    sessions.add(session);
    session.on("close", () => sessions.delete(session));
  });
  h2.on("stream", (stream: http2.ServerHttp2Stream, headers: http2.IncomingHttpHeaders) => {
    let text = "";
    stream.setEncoding("utf8");
    stream.on("data", (chunk: string) => (text += chunk));
    stream.on("end", () => {
      const reply = handle("h2", String(headers[":method"]), String(headers[":path"]), flatten(headers as never), text);
      stream.respond({ ":status": reply.status, "content-type": "application/json", "apns-id": crypto.randomUUID() });
      stream.end(reply.body === undefined ? "" : JSON.stringify(reply.body));
    });
  });

  const listen = (server: net.Server) =>
    new Promise<string>((resolve) => server.listen(0, "127.0.0.1", () => resolve(`http://127.0.0.1:${(server.address() as net.AddressInfo).port}`)));
  const [url, h2URL] = [await listen(h1), await listen(h2)];
  return {
    url,
    h2URL,
    requests,
    reset: () => void requests.splice(0),
    dropConnections: () => {
      for (const session of sessions) session.close();
    },
    async close() {
      h1.closeAllConnections();
      for (const session of sessions) session.destroy();
      await Promise.all([new Promise<void>((resolve) => h1.close(() => resolve())), new Promise<void>((resolve) => h2.close(() => resolve()))]);
    },
  };
}
