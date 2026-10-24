// In-memory stand-ins for the opencode host and an HTTP relay, for the unit tests.
import http from "node:http";
import { base64url, generateKeyPair, openEnvelope, type Envelope, type Opened, type RawKeyPair } from "../contracts/src/index.ts";
import type { Host, HostEvent, HostStorage, Json, RpcDefinition, RpcHandler } from "../src/host.ts";
import { RelayClient } from "../src/relay.ts";
import { definition, handlers } from "../src/rpc.ts";
import { PushService, type ServiceOptions } from "../src/service.ts";
import { createSharedState, type SharedState } from "../src/shared.ts";

/** The KV semantics of core/src/kv.ts: ordered keys, prefix scans with `after` and `limit`. */
export class MemoryStorage implements HostStorage {
  readonly values = new Map<string, Json>();
  async get(key: string) {
    const value = this.values.get(key);
    return value === undefined ? undefined : (structuredClone(value) as Json);
  }
  async set(key: string, value: Json) {
    this.values.set(key, structuredClone(value));
  }
  async remove(key: string) {
    this.values.delete(key);
  }
  async scan(options: { prefix: string; after?: string; limit?: number }) {
    const limit = Math.min(Math.max(options.limit ?? 100, 1), 1000);
    const keys = [...this.values.keys()].filter((key) => key.startsWith(options.prefix) && (options.after === undefined || key > options.after)).sort();
    const entries = keys.slice(0, limit).map((key) => ({ key, value: structuredClone(this.values.get(key)!) as Json }));
    return keys.length > limit ? { entries, next: entries.at(-1)!.key } : { entries };
  }
}

export class RpcError extends Error {
  readonly type: string;
  readonly data: unknown;
  constructor(type: string, message: string, data?: unknown) {
    super(message);
    this.type = type;
    this.data = data;
  }
}

/** How opencode's Promise adapter rejects: with the Effect error itself, a tagged error. */
class TaggedError extends Error {
  readonly _tag: string;
  constructor(tag: string, message: string) {
    super(message);
    this._tag = tag;
  }
}

/** One location's instance: its own event stream, sharing storage and process state with others. */
export class FakeHost implements Host {
  readonly location: { directory: string; project: { directory: string } };
  readonly storage: MemoryStorage;
  /** Sessions by ID; any other ID is a root session without a title, in this host's location. */
  readonly sessions = new Map<string, { title?: string; parentID?: string; directory?: string }>();
  /** Session IDs opencode does not have: `session.get` rejects with its not-found error. */
  readonly missing = new Set<string>();
  /** Session IDs whose `session.get` fails the way a database error would. */
  readonly unavailable = new Set<string>();
  /** `session.get` calls by session ID. */
  readonly lookups = new Map<string, number>();
  readonly permissions = new Map<string, string>();
  definition: RpcDefinition | undefined;
  handlers: Readonly<Record<string, RpcHandler>> | undefined;
  readonly #queue: HostEvent[] = [];
  #wake: (() => void) | undefined;

  constructor(directory = "/work/project", storage = new MemoryStorage()) {
    this.location = { directory, project: { directory } };
    this.storage = storage;
  }

  readonly event = {
    subscribe: (options?: { signal?: AbortSignal }): AsyncIterable<HostEvent> => {
      const queue = this.#queue;
      return {
        [Symbol.asyncIterator]: () => ({
          next: async (): Promise<IteratorResult<HostEvent>> => {
            while (!queue.length) {
              if (options?.signal?.aborted) return { done: true, value: undefined };
              await new Promise<void>((resolve) => {
                this.#wake = resolve;
                options?.signal?.addEventListener("abort", () => resolve(), { once: true });
              });
            }
            return { done: false, value: queue.shift()! };
          },
        }),
      };
    },
  };

  /** When set, `permission.get` waits for it before answering, to interleave events with the read. */
  permissionGate: Promise<void> | undefined;

  readonly permission = {
    get: async ({ sessionID, requestID }: { sessionID: string; requestID: string }) => {
      const found = this.permissions.get(requestID) === sessionID;
      await this.permissionGate;
      if (!found) throw new Error(`Permission request not found: ${requestID}`);
      return { id: requestID, sessionID };
    },
  };

  readonly session = {
    get: async ({ sessionID }: { sessionID: string }) => {
      this.lookups.set(sessionID, (this.lookups.get(sessionID) ?? 0) + 1);
      // The adapter decodes the input first, and session IDs start with "ses" (schema/src/session-id.ts).
      if (!sessionID.startsWith("ses")) throw new TaggedError("SchemaError", `Expected a string starting with "ses", got "${sessionID}"`);
      if (this.missing.has(sessionID)) throw new TaggedError("Session.NotFoundError", `Session not found: ${sessionID}`);
      if (this.unavailable.has(sessionID)) throw new Error("database is locked");
      const { directory, ...rest } = this.sessions.get(sessionID) ?? {};
      return { id: sessionID, location: { directory: directory ?? this.location.directory }, ...rest };
    },
  };

  readonly rpc = {
    register: async (definition: RpcDefinition, handlers: Readonly<Record<string, RpcHandler>>) => {
      this.definition = definition;
      this.handlers = handlers;
      return { dispose: async () => void (this.handlers = undefined) };
    },
  };

  emit(event: Omit<HostEvent, "location"> & { location?: HostEvent["location"] | null }): void {
    const { location, ...rest } = event;
    this.#queue.push({ ...rest, ...(location === null ? {} : { location: location ?? { directory: this.location.directory } }) } as HostEvent);
    this.#wake?.();
  }

  async call(method: string, input?: unknown): Promise<any> {
    const handler = this.handlers?.[method];
    if (!handler) throw new Error(`RPC ${method} is not registered`);
    return handler(input, { error: (type, message, data) => new RpcError(type, message, data) });
  }
}

export interface RelayCall {
  readonly path: string;
  readonly token: string | undefined;
  readonly body: any;
  /** When the relay received the call and when it answered (`performance.now()`). */
  readonly received: number;
  answered?: number;
}

/** A scripted answer; `delay` holds it back, in milliseconds. */
export interface RelayAnswer {
  readonly status: number;
  readonly body?: unknown;
  readonly delay?: number;
}

/** A relay that records each call and answers from a per-token script, then "delivered". */
export async function startFakeRelay() {
  const calls: RelayCall[] = [];
  const scripts = new Map<string, RelayAnswer[]>();
  const server = http.createServer((request, response) => {
    let text = "";
    request.on("data", (chunk) => (text += chunk));
    request.on("end", () => {
      const token = /^Bearer (.+)$/.exec(request.headers.authorization ?? "")?.[1];
      const call: RelayCall = { path: request.url ?? "", token, body: JSON.parse(text || "null"), received: performance.now() };
      calls.push(call);
      const reply: RelayAnswer = (token && scripts.get(token)?.shift()) || { status: 200, body: { result: "delivered" } };
      const answer = () => {
        call.answered = performance.now();
        response.writeHead(reply.status, { "content-type": "application/json" }).end(JSON.stringify(reply.body ?? {}));
      };
      if (reply.delay) setTimeout(answer, reply.delay);
      else answer();
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const url = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
  return {
    url,
    calls,
    pushes: () => calls.filter((call) => call.path === "/v1/push"),
    activities: () => calls.filter((call) => call.path === "/v1/activity"),
    /** The next answers for a send token, in order. */
    script: (token: string, ...answers: RelayAnswer[]) => void scripts.set(token, answers),
    close: () => new Promise<void>((resolve) => server.close(() => resolve())),
  };
}

export type FakeRelay = Awaited<ReturnType<typeof startFakeRelay>>;

/** A phone: one key pair per paired server, and the sender token the relay gave it. */
export interface FakeDevice {
  readonly keyID: string;
  readonly keys: RawKeyPair;
  readonly sendToken: string;
}

let deviceCounter = 0;
export async function fakeDevice(): Promise<FakeDevice> {
  deviceCounter++;
  return {
    keyID: `kid_device_${String(deviceCounter).padStart(8, "0")}`,
    keys: await generateKeyPair(),
    sendToken: `ocs_test_token_${String(deviceCounter).padStart(8, "0")}`,
  };
}

export async function register(host: FakeHost, relay: FakeRelay, device: FakeDevice, extra: Record<string, unknown> = {}) {
  return host.call("registerDevice", {
    sendToken: device.sendToken,
    relayURL: relay.url,
    devicePublicKey: base64url.encode(device.keys.publicKey),
    keyID: device.keyID,
    appServerRef: "srv_home_mac",
    label: "Test iPhone",
    ...extra,
  }) as Promise<{ serverPublicKey: string; pluginVersion: string }>;
}

/** Opens an envelope the way the app's extension will. */
export async function open(envelope: Envelope, device: FakeDevice, serverPublicKey: string, now = Math.floor(Date.now() / 1000)): Promise<Opened> {
  return openEnvelope(envelope, {
    now,
    key: (kid) => (kid === device.keyID ? { recipientPrivateKey: device.keys.privateKey, senderPublicKey: base64url.decode(serverPublicKey)! } : undefined),
  });
}

export interface Harness {
  readonly host: FakeHost;
  readonly service: PushService;
  readonly shared: SharedState;
  /** Retry delays the relay client asked for (it does not actually wait in tests). */
  readonly delays: number[];
}

export async function startService(host: FakeHost, options: Partial<ServiceOptions> & { shared?: SharedState } = {}): Promise<Harness> {
  const shared = options.shared ?? createSharedState();
  const delays: number[] = [];
  const relay = new RelayClient({ sleep: async (milliseconds) => void delays.push(milliseconds) });
  const service = new PushService({ graceMilliseconds: 60, activityIntervalMilliseconds: 150, replyWindowMilliseconds: 100, log: () => undefined, relay, ...options, host, shared });
  await service.start((started) => host.rpc.register(definition, handlers(started)));
  return { host, service, shared, delays };
}

/** Polls until the condition holds, or fails after the timeout. */
export async function until(condition: () => boolean | Promise<boolean>, timeout = 3000): Promise<void> {
  const deadline = Date.now() + timeout;
  while (!(await condition())) {
    if (Date.now() > deadline) throw new Error("Timed out waiting for a condition");
    await sleep(10);
  }
}

export const sleep = (milliseconds: number) => new Promise((resolve) => setTimeout(resolve, milliseconds));
