import http from "node:http";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";
import { createApp, type RelayDeps } from "./app.ts";
import { Http2Sender } from "./apns/http2-sender.ts";
import { localTokenProvider } from "./apns/token.ts";
import { ConfigError, readConfig, type RelayEnvironment } from "./config.ts";
import { consoleLogger, type Logger } from "./log.ts";
import { migrate, sqlite, SqliteLimiter } from "./sql-sqlite.ts";
import { Store } from "./store.ts";

export interface NodeRelayOptions {
  readonly env: RelayEnvironment;
  /** A file path, or ":memory:". */
  readonly database: string;
  readonly port?: number;
  readonly host?: string;
  /**
   * Where the client IP for the registration limit comes from behind a proxy: "fly" reads
   * Fly-Client-IP, which Fly's edge sets; "forwarded" reads the rightmost X-Forwarded-For entry,
   * the address the one trusted proxy saw. Clients can forge every other entry. Unset uses the
   * socket's address.
   */
  readonly trustProxy?: TrustProxy;
  readonly log?: Logger;
  readonly now?: () => number;
}

export type TrustProxy = "fly" | "forwarded";

export function parseTrustProxy(value: string | undefined): TrustProxy | undefined {
  if (!value) return undefined;
  if (value === "fly" || value === "forwarded") return value;
  throw new ConfigError('TRUST_PROXY must be "fly" or "forwarded"');
}

/** The client IP the registration limit counts, per `trustProxy`. */
export function clientAddress(headers: http.IncomingHttpHeaders, socketAddress: string | undefined, trustProxy: TrustProxy | undefined): string | undefined {
  const header = (name: string) => {
    const value = headers[name];
    return (Array.isArray(value) ? value.at(-1) : value)?.trim();
  };
  if (trustProxy === "fly") return header("fly-client-ip") || socketAddress;
  if (trustProxy === "forwarded") return header("x-forwarded-for")?.split(",").at(-1)?.trim() || socketAddress;
  return socketAddress;
}

export interface NodeRelay {
  readonly url: string;
  close(): Promise<void>;
}

const migrations = fileURLToPath(new URL("../migrations", import.meta.url));

/** The Fly.io fallback: the same Hono app with node:http2 for APNs and node:sqlite for storage. */
export async function startNodeRelay(options: NodeRelayOptions): Promise<NodeRelay> {
  const config = readConfig(options.env);
  const db = new DatabaseSync(options.database);
  db.exec("PRAGMA journal_mode = WAL");
  migrate(db, migrations);
  const now = options.now ?? (() => Math.floor(Date.now() / 1000));
  const sender = new Http2Sender(config.apns);
  const deps: RelayDeps = {
    config,
    store: new Store(sqlite(db)),
    limiter: new SqliteLimiter(db),
    sender,
    tokens: localTokenProvider(config.apns, now),
    log: options.log ?? consoleLogger,
    now,
  };
  const app = createApp({
    resolve: () => deps,
    clientIP: (c) => (c.env as { clientIP?: string }).clientIP,
  });

  const server = http.createServer(async (incoming, outgoing) => {
    try {
      const chunks: Buffer[] = [];
      let size = 0;
      for await (const chunk of incoming as AsyncIterable<Buffer>) {
        size += chunk.length;
        if (size > 64 * 1024) {
          outgoing.writeHead(413, { "content-type": "application/json" }).end('{"error":"too_large"}');
          return;
        }
        chunks.push(chunk);
      }
      const headers = new Headers();
      for (const [name, value] of Object.entries(incoming.headers)) {
        if (typeof value === "string") headers.set(name, value);
        else if (Array.isArray(value)) for (const item of value) headers.append(name, item);
      }
      const method = incoming.method ?? "GET";
      const request = new Request(`http://${incoming.headers.host ?? "relay"}${incoming.url ?? "/"}`, {
        method,
        headers,
        ...(method === "GET" || method === "HEAD" ? {} : { body: Buffer.concat(chunks) }),
      });
      const response = await app.fetch(request, { clientIP: clientAddress(incoming.headers, incoming.socket.remoteAddress, options.trustProxy) });
      outgoing.writeHead(response.status, Object.fromEntries(response.headers));
      outgoing.end(Buffer.from(await response.arrayBuffer()));
    } catch {
      if (!outgoing.headersSent) outgoing.writeHead(500, { "content-type": "application/json" });
      outgoing.end('{"error":"internal"}');
    }
  });
  await new Promise<void>((resolve) => server.listen(options.port ?? 0, options.host ?? "127.0.0.1", resolve));
  const address = server.address() as { port: number };
  return {
    url: `http://${options.host ?? "127.0.0.1"}:${address.port}`,
    async close() {
      sender.close();
      server.closeAllConnections();
      await new Promise<void>((resolve) => server.close(() => resolve()));
      db.close();
    },
  };
}
