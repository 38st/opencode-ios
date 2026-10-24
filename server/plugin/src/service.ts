import path from "node:path";
import { base64url, CONTRACT, fitPayload, kindPolicy, sealEnvelope, type Kind, type Payload } from "../contracts/src/index.ts";
import { activityChange, type ActivityChange, type Phase } from "./activities.ts";
import { collapseForRequest, collapseForResult, collapseForTest, threadFor } from "./hashing.ts";
import type { Host, HostEvent } from "./host.ts";
import { serverKeys } from "./keys.ts";
import { failureSummary, formDetails, parseForm, parsePermission, permissionDetails, type RequestDetails } from "./payloads.ts";
import { RelayClient, type Outcome } from "./relay.ts";
import { keys, Registry, scanAll, type ActivityRegistration, type Device, type Presence } from "./registry.ts";
import { Sessions, type LookupFailure } from "./sessions.ts";
import { sharedState, type PushedRequest, type Resolution, type SharedState } from "./shared.ts";

export interface ServiceOptions {
  readonly host: Host;
  readonly shared?: SharedState;
  readonly relay?: RelayClient;
  /** Unix milliseconds. */
  readonly now?: () => number;
  readonly log?: (message: string) => void;
  /** Tests only; the contract's 3 s otherwise. */
  readonly graceMilliseconds?: number;
  /** Tests only; the contract's 30 s otherwise. */
  readonly activityIntervalMilliseconds?: number;
  /** Tests only; how long after an interrupted run its requests are checked again (2 s). */
  readonly recheckMilliseconds?: number;
  /** Tests only; how long a "cancelled" replacement waits for the request's own reply event (1 s). */
  readonly replyWindowMilliseconds?: number;
}

type Fields = Omit<Payload, "v" | "kind" | "server" | "exp" | "pending">;
type RequestKind = "permission" | "question";
type Mutable<T> = { -readonly [K in keyof T]: T[K] };

const DAY = 86_400_000;
/** Events that settle requests or end a location: handled by any instance when theirs is not running. */
const SETTLING = new Set(["permission.replied", "form.replied", "form.cancelled", "location.shutdown"]);
/**
 * Session events the plugin acts on that opencode 2.1.3 can publish without a location (the bus
 * routes them by session instead, core/src/bus.ts): the session's location places them.
 */
const PLACED_BY_SESSION = new Set([
  "session.execution.started", "session.execution.succeeded", "session.execution.failed", "session.execution.interrupted",
  "session.deleted", "session.retry.scheduled",
]);
const MAX_TRACKED_SESSIONS = 10_000;
const { validSeconds } = CONTRACT.presence;
const { staleSeconds, dismissSeconds } = CONTRACT.activity;
const object = (value: unknown): Record<string, unknown> => (typeof value === "object" && value !== null && !Array.isArray(value) ? (value as Record<string, unknown>) : {});
const stringField = (value: Record<string, unknown>, key: string) => (typeof value[key] === "string" ? (value[key] as string) : undefined);

/** The session an event belongs to, for the event types the plugin reacts to. */
function sessionOf(event: HostEvent): string | undefined {
  const data = object(event.data);
  const id = event.type === "form.created" ? object(data.form).sessionID : data.sessionID;
  return typeof id === "string" ? id : undefined;
}

export class PushService {
  readonly #host: Host;
  readonly #shared: SharedState;
  readonly #relay: RelayClient;
  readonly #now: () => number;
  readonly #log: (message: string) => void;
  readonly #grace: number;
  readonly #activityInterval: number;
  readonly #recheckDelay: number;
  readonly #replyWindow: number;
  readonly #registry: Registry;
  readonly #sessions: Sessions;
  readonly #abort = new AbortController();
  readonly #tasks = new Set<Promise<unknown>>();
  readonly #ownTimers = new Set<string>();
  readonly #timers = new Set<ReturnType<typeof setTimeout>>();
  readonly #activityTimers = new Map<string, ReturnType<typeof setTimeout>>();
  /** Reply windows this instance started, by timer, with their request IDs. */
  readonly #windows = new Map<ReturnType<typeof setTimeout>, string>();
  #activityQueue: Promise<unknown> = Promise.resolve();
  /** Events this instance received: its own location's, another location's by type, and those without one. */
  readonly #seen = { own: 0, other: {} as Record<string, number>, none: 0 };
  #rpc: { dispose(): Promise<void> } | undefined;

  constructor(options: ServiceOptions) {
    this.#host = options.host;
    this.#shared = options.shared ?? sharedState();
    this.#relay = options.relay ?? new RelayClient();
    this.#now = options.now ?? Date.now;
    this.#log = options.log ?? ((message) => console.warn(`[mobilepush] ${message}`));
    this.#grace = options.graceMilliseconds ?? CONTRACT.plugin.graceMilliseconds;
    this.#activityInterval = options.activityIntervalMilliseconds ?? CONTRACT.activity.updateIntervalSeconds * 1000;
    this.#recheckDelay = options.recheckMilliseconds ?? 2000;
    this.#replyWindow = options.replyWindowMilliseconds ?? 1000;
    this.#registry = new Registry(this.#host.storage);
    this.#sessions = new Sessions(this.#host);
  }

  get registry(): Registry {
    return this.#registry;
  }

  /** For `status`: which location this instance serves and the events it has received. */
  get instance() {
    return { location: this.#host.location.directory, events: { own: this.#seen.own, other: { ...this.#seen.other }, none: this.#seen.none } };
  }

  /** Registers the RPC methods and starts consuming this location's events. */
  async start(register: (service: PushService) => Promise<{ dispose(): Promise<void> }>): Promise<void> {
    await this.serverKeys();
    this.#rpc = await register(this);
    this.#track(this.#pruneSent());
    const prune = setInterval(() => this.#track(this.#pruneSent()), DAY / 4);
    (prune as { unref?: () => void }).unref?.();
    this.#abort.signal.addEventListener("abort", () => clearInterval(prune), { once: true });
    const directory = this.#host.location.directory;
    this.#shared.locations.set(directory, (this.#shared.locations.get(directory) ?? 0) + 1);
    this.#abort.signal.addEventListener("abort", () => {
      const running = (this.#shared.locations.get(directory) ?? 1) - 1;
      if (running > 0) this.#shared.locations.set(directory, running);
      else this.#shared.locations.delete(directory);
    }, { once: true });
    void this.#consume();
  }

  async stop(): Promise<void> {
    this.#abort.abort();
    for (const requestID of this.#ownTimers) {
      clearTimeout(this.#shared.timers.get(requestID));
      this.#shared.timers.delete(requestID);
    }
    // A replacement still waiting for a reply event goes out now rather than never.
    for (const [timer, requestID] of this.#windows) {
      clearTimeout(timer);
      const resolution = this.#shared.resolutions.get(requestID);
      if (resolution?.window === timer) this.#flush(requestID, resolution);
    }
    this.#windows.clear();
    for (const timer of [...this.#timers, ...this.#activityTimers.values()]) clearTimeout(timer);
    await this.#rpc?.dispose().catch(() => undefined);
    await Promise.allSettled([...this.#tasks]);
  }

  /** Resolves once every send this service started has finished (tests use it). */
  async settled(): Promise<void> {
    while (this.#tasks.size) await Promise.allSettled([...this.#tasks]);
  }

  serverKeys() {
    return serverKeys(this.#host.storage, this.#shared);
  }

  #track<T>(promise: Promise<T>): Promise<T | undefined> {
    const tracked = promise.catch((error: unknown) => {
      this.#log(`internal error: ${error instanceof Error ? error.name : "unknown"}`);
      return undefined;
    });
    this.#tasks.add(tracked);
    void tracked.finally(() => this.#tasks.delete(tracked));
    return tracked;
  }

  #later(delay: number, run: () => Promise<unknown>): void {
    const timer = setTimeout(() => {
      this.#timers.delete(timer);
      this.#track(run());
    }, delay);
    this.#timers.add(timer);
  }

  async #consume(): Promise<void> {
    try {
      for await (const event of this.#host.event.subscribe({ signal: this.#abort.signal })) {
        if (this.#abort.signal.aborted) break;
        this.#track(this.handle(event));
      }
    } catch (error) {
      if (!this.#abort.signal.aborted) this.#log(`event stream ended: ${error instanceof Error ? error.name : "unknown"}`);
    }
  }

  /**
   * Handles one event. The bookkeeping that ordering depends on (pending requests, cancelling a
   * grace timer, queueing an activity change) runs synchronously before the first await, so
   * events handled concurrently still observe each other in stream order. The one exception is a
   * session event without a location whose session this process has not seen: it waits for a lookup.
   */
  handle(event: HostEvent): Promise<void> {
    const located = event.location?.directory;
    if (!located) this.#seen.none++;
    else if (located === this.#host.location.directory) this.#seen.own++;
    else if (Object.keys(this.#seen.other).length < 64 || event.type in this.#seen.other) this.#seen.other[event.type] = (this.#seen.other[event.type] ?? 0) + 1;
    if (typeof event.id !== "string") return Promise.resolve();
    const data = object(event.data);
    const sessionID = sessionOf(event);
    // The run bookkeeping is synchronous, so a located step is never dropped while its session's
    // location-less `started` waits on a lookup.
    if (sessionID) this.#noteExecution(event.type, sessionID);
    if (sessionID && located) this.#placeSession(sessionID, event.type === "session.moved" ? (stringField(object(data.location), "directory") ?? located) : located);
    if (located) return this.#dispatch(event, located, data);
    // Without a location, only the session events the bus routes by session are placed; any other is global.
    if (!sessionID || !PLACED_BY_SESSION.has(event.type)) return Promise.resolve();
    const placed = this.#shared.sessionLocations.get(sessionID);
    if (placed) return this.#dispatch(event, placed, data);
    // A session first seen this way (one created before this process): ask opencode where it is.
    return this.#sessions.summary(sessionID).then((summary) => {
      if (!summary?.directory) return;
      this.#placeSession(sessionID, summary.directory);
      return this.#dispatch(event, summary.directory, data);
    });
  }

  /**
   * Whether a session's current run has taken a step. `started` resets it; the entry stays after the
   * run ends, so every instance (each receives every event) reads the same answer whenever it gets to
   * the end event, and the next `started` replaces it.
   */
  #noteExecution(type: string, sessionID: string): void {
    const executions = this.#shared.executions;
    if (type === "session.execution.started") {
      executions.delete(sessionID);
      executions.set(sessionID, false);
      if (executions.size > MAX_TRACKED_SESSIONS) executions.delete(executions.keys().next().value!);
    } else if (type === "session.step.started" && executions.get(sessionID) === false) {
      executions.set(sessionID, true);
    }
  }

  #placeSession(sessionID: string, directory: string): void {
    const locations = this.#shared.sessionLocations;
    locations.delete(sessionID);
    locations.set(sessionID, directory);
    if (locations.size > MAX_TRACKED_SESSIONS) locations.delete(locations.keys().next().value!);
  }

  /**
   * Acts on an event of `directory`'s location. Every instance receives every location's events
   * (README, "Locations"), so this instance acts only on its own location's, unless that location
   * has no instance running here and the event only settles requests.
   */
  #dispatch(event: HostEvent, directory: string, data: Record<string, unknown>): Promise<void> {
    if (directory !== this.#host.location.directory && !(SETTLING.has(event.type) && !this.#shared.locations.has(directory))) return Promise.resolve();
    const tasks: Promise<unknown>[] = [];
    switch (event.type) {
      case "permission.asked": {
        const request = parsePermission(data);
        if (request) tasks.push(this.#requestAsked(event, "permission", request.id, request.sessionID, directory, () => permissionDetails(request)));
        break;
      }
      case "form.created": {
        const form = parseForm(data);
        if (form) tasks.push(this.#requestAsked(event, "question", form.id, form.sessionID, directory, () => formDetails(form)));
        break;
      }
      case "permission.replied":
        if (typeof data.requestID === "string") this.#settle(data.requestID, typeof data.reply === "string" ? data.reply : "answered", true);
        break;
      case "form.replied":
      case "form.cancelled":
        if (typeof data.id === "string") this.#settle(data.id, event.type === "form.replied" ? "answered" : "cancelled", true);
        break;
      case "session.execution.succeeded":
      case "session.execution.failed": {
        if (typeof data.sessionID !== "string") break;
        // A run that took no step only applied an inbox item, such as a move: nothing finished.
        if (event.type === "session.execution.succeeded" && this.#shared.executions.get(data.sessionID) === false) break;
        tasks.push(this.#executionEnded(event, data.sessionID, event.type === "session.execution.failed" ? "failed" : "finished", data));
        break;
      }
      case "session.execution.interrupted":
      case "session.deleted":
        // Stop and deletion interrupt a waiting permission request, and opencode then drops it
        // without permission.replied (core/src/permission.ts, the `ensuring` in `assert`). Forms
        // are cancelled with form.cancelled instead (core/src/form.ts, `ask`).
        tasks.push(this.#recheck());
        break;
      case "location.shutdown":
        this.#locationShutdown(directory);
        break;
    }
    const change = activityChange(event.type, data);
    const sessionID = sessionOf(event);
    if (change && sessionID) tasks.push(this.#queueActivity(() => this.#activityEvent(sessionID, change, event)));
    return Promise.all(tasks).then(() => undefined);
  }

  /** Records a claim on an event: `sent/<eventID>` removes a duplicate delivery to a second instance. */
  async #claim(eventID: string): Promise<boolean> {
    if (this.#shared.claims.has(eventID)) return false;
    this.#shared.claims.set(eventID, this.#now());
    if (await this.#host.storage.get(keys.sent(eventID))) return false;
    await this.#host.storage.set(keys.sent(eventID), { at: this.#now() });
    return true;
  }

  async #pruneSent(): Promise<void> {
    const cutoff = this.#now() - DAY;
    for (const [eventID, at] of this.#shared.claims) if (at < cutoff) this.#shared.claims.delete(eventID);
    for (const [requestID, { at }] of this.#shared.resolutions) if (at < this.#now() - 600_000) this.#shared.resolutions.delete(requestID);
    for (const entry of await scanAll(this.#host.storage, "sent/")) {
      const at = object(entry.value).at;
      if (typeof at !== "number" || at < cutoff) await this.#host.storage.remove(entry.key);
    }
  }

  #forget(requestID: string): void {
    this.#shared.pending.delete(requestID);
    const timer = this.#shared.timers.get(requestID);
    if (timer) clearTimeout(timer);
    this.#shared.timers.delete(requestID);
    this.#ownTimers.delete(requestID);
  }

  #requestAsked(event: HostEvent, kind: RequestKind, requestID: string, sessionID: string, directory: string, details: () => Promise<RequestDetails>): Promise<void> {
    this.#shared.pending.set(requestID, { kind, sessionID, directory });
    return (async () => {
      if (!(await this.#claim(event.id))) return;
      // A repeated event for a request already waiting or pushed keeps the existing timer.
      if (!this.#shared.pending.has(requestID) || this.#shared.timers.has(requestID) || this.#shared.pushed.has(requestID)) return;
      // The grace period skips requests answered at the desk, including automatic approvals.
      const timer = setTimeout(() => {
        this.#shared.timers.delete(requestID);
        this.#ownTimers.delete(requestID);
        this.#track(this.#graceEnded(kind, requestID, sessionID, details));
      }, this.#grace);
      this.#shared.timers.set(requestID, timer);
      this.#ownTimers.add(requestID);
    })();
  }

  async #permissionExists(sessionID: string, requestID: string): Promise<boolean> {
    if (typeof this.#host.permission?.get !== "function") return true;
    try {
      await this.#host.permission.get({ sessionID, requestID });
      return true;
    } catch {
      return false;
    }
  }

  async #graceEnded(kind: RequestKind, requestID: string, sessionID: string, details: () => Promise<RequestDetails>): Promise<void> {
    const held = kind !== "permission" || (await this.#permissionExists(sessionID, requestID));
    // opencode publishes permission.replied before it removes the request, so a reply can land
    // while permission.get still finds it: read the shared state again after the await.
    if (!held || !this.#shared.pending.has(requestID)) {
      // Answered, or removed without a reply event (an automatic rule, or Stop).
      this.#forget(requestID);
      return;
    }
    await Promise.all([
      this.#deliverRequest(kind, requestID, sessionID, details),
      this.#queueActivity(() => this.#activityWaiting(sessionID, requestID)),
    ]);
  }

  async #deliverRequest(kind: RequestKind, requestID: string, sessionID: string, details: () => Promise<RequestDetails>): Promise<void> {
    const devices = (await this.#registry.list()).filter((device) => device.prefs[kind]);
    if (!devices.length) return;
    const [summary, root] = await Promise.all([this.#sessions.summary(sessionID), this.#sessions.root(sessionID)]);
    // A request the user must answer goes out even when its family cannot be read, under its own session.
    const rootSessionID = root ?? sessionID;
    const request = await details();
    const fields: Fields = { sessionID, rootSessionID, ...this.#context(summary?.title), requestID, ...request };
    await Promise.all(devices.map(async (device) => {
      const outcome = await this.#send(device, kind, fields, await collapseForRequest(device.keyID, requestID));
      if (outcome?.result !== "delivered") return;
      if (this.#shared.pending.has(requestID)) {
        const pushed = this.#shared.pushed.get(requestID) ?? { sessionID, rootSessionID, keyIDs: new Set<string>() };
        pushed.keyIDs.add(device.keyID);
        this.#shared.pushed.set(requestID, pushed);
      } else {
        // The request was settled while this push was in flight, so this device needs the replacement too.
        this.#replace(requestID, this.#resolution(requestID), { sessionID, rootSessionID, keyIDs: new Set([device.keyID]) });
      }
    }));
  }

  /**
   * Marks a request settled and replaces its alert on the devices that received it. `genuine` is
   * true for a reply event, and false for "cancelled" inferred because the server no longer holds
   * the request.
   */
  #settle(requestID: string, reply: string, genuine: boolean): void {
    this.#forget(requestID);
    const pushed = this.#shared.pushed.get(requestID);
    this.#shared.pushed.delete(requestID);
    this.#track(this.#queueActivity(() => this.#activityAnswered(requestID)));
    this.#replace(requestID, this.#resolution(requestID, reply, genuine), pushed);
  }

  /** The request's resolution. A reply event's answer is final and replaces an inferred "cancelled". */
  #resolution(requestID: string, reply = "cancelled", genuine = false): Resolution {
    const existing = this.#shared.resolutions.get(requestID);
    if (existing) {
      if (genuine) Object.assign(existing, { reply, genuine });
      return existing;
    }
    const created: Resolution = { reply, genuine, request: undefined, sent: new Map(), queue: Promise.resolve(), window: undefined, at: this.#now() };
    this.#shared.resolutions.set(requestID, created);
    return created;
  }

  /**
   * The passive replacement, under the alert's collapse ID. A reply event's answer goes out at
   * once. An inferred "cancelled" first waits for the reply window, because the request's own
   * reply can still be queued (an answer at the desk racing Stop, or the rejections a closing
   * location publishes), and one alert with the real answer is better than two. The replacement
   * ignores presence: an actionable alert must not outlive its request.
   */
  #replace(requestID: string, resolution: Resolution, pushed?: PushedRequest): void {
    if (pushed) {
      resolution.request ??= { sessionID: pushed.sessionID, rootSessionID: pushed.rootSessionID };
      for (const keyID of pushed.keyIDs) if (!resolution.sent.has(keyID)) resolution.sent.set(keyID, undefined);
    }
    if (![...resolution.sent.values()].some((sent) => sent !== resolution.reply)) return;
    if (resolution.genuine) return this.#flush(requestID, resolution);
    if (resolution.window) return;
    const timer = setTimeout(() => {
      this.#windows.delete(timer);
      if (resolution.window === timer) this.#flush(requestID, resolution);
    }, this.#replyWindow);
    resolution.window = timer;
    this.#windows.set(timer, requestID);
  }

  /**
   * Queues a pass that sends the current reply to each device not yet sent it. Passes for one
   * request run one at a time, so a correction follows the push it corrects instead of racing it,
   * and a device gets a second replacement only if the reply changed after the first was sent.
   */
  #flush(requestID: string, resolution: Resolution): void {
    resolution.window = undefined;
    const next = resolution.queue.then(async () => {
      for (const [keyID, sent] of resolution.sent) {
        // Read for each device: a reply event that arrived during an earlier send replaces "cancelled".
        const reply = resolution.reply;
        if (sent === reply || !resolution.request) continue;
        resolution.sent.set(keyID, reply);
        const device = await this.#registry.get(keyID);
        if (!device) continue;
        await this.#send(device, "resolved", { requestID, reply, ...resolution.request }, await collapseForRequest(keyID, requestID), true);
      }
    });
    resolution.queue = next.catch(() => undefined);
    this.#track(next);
  }

  /** Settles every tracked permission request of this location that the server no longer holds. */
  async #recheck(again = true): Promise<void> {
    const directory = this.#host.location.directory;
    let remaining = 0;
    for (const [requestID, entry] of [...this.#shared.pending]) {
      if (entry.kind !== "permission" || entry.directory !== directory) continue;
      const held = await this.#permissionExists(entry.sessionID, requestID);
      // A reply event can settle the request during the read.
      if (!this.#shared.pending.has(requestID)) continue;
      if (held) remaining++;
      else this.#settle(requestID, "cancelled", false);
    }
    // The interrupted run can remove its request just after the event, so look once more.
    if (again && remaining) this.#later(this.#recheckDelay, () => this.#recheck(false));
  }

  /**
   * A location's pending requests end with it (core/src/permission.ts keeps them in memory). As it
   * closes, opencode rejects each permission request and cancels each form
   * (core/src/location-lifecycle.ts), and those replies, in either order, win the reply window.
   */
  #locationShutdown(directory: string): void {
    for (const [requestID, entry] of [...this.#shared.pending]) if (entry.directory === directory) this.#settle(requestID, "cancelled", false);
  }

  async #executionEnded(event: HostEvent, sessionID: string, kind: "finished" | "failed", data: Record<string, unknown>): Promise<void> {
    const root = await this.#sessions.root(sessionID);
    if (kind === "finished") {
      // Only a root's success is pushed, so a session whose family cannot be read is skipped.
      if (!root) this.#log("finished not pushed: the session's family could not be read");
      if (root !== sessionID) return;
    }
    const rootSessionID = root ?? sessionID;
    if (!(await this.#claim(event.id))) return;
    const devices = (await this.#registry.list()).filter((device) => device.prefs[kind]);
    if (!devices.length) return;
    const summary = await this.#sessions.summary(sessionID);
    const failure = kind === "failed" ? failureSummary(data) : undefined;
    const fields: Fields = { sessionID, rootSessionID, ...this.#context(summary?.title), ...(failure ? { summary: failure } : {}) };
    await Promise.all(devices.map(async (device) => this.#send(device, kind, fields, await collapseForResult(device.keyID, sessionID))));
  }

  /** Sends the test push now, regardless of presence and preferences. */
  async sendTest(device: Device): Promise<Outcome> {
    return (await this.#send(device, "test", {}, await collapseForTest(device.keyID), true)) ?? { result: "rejected", attempts: 0 };
  }

  #context(title: string | undefined): Pick<Fields, "title" | "project"> {
    const root = this.#host.location.project?.directory ?? this.#host.location.directory;
    const project = path.basename(root);
    return { ...(title ? { title } : {}), ...(project ? { project } : {}) };
  }

  async #presence(keyID: string): Promise<boolean> {
    const value = object(await this.#host.storage.get(keys.presence(keyID))) as Partial<Presence>;
    return value.foreground === true && typeof value.until === "number" && value.until > this.#now();
  }

  async setPresence(keyID: string, foreground: boolean, sessionID: string | undefined): Promise<void> {
    if (!foreground) return this.#host.storage.remove(keys.presence(keyID));
    const presence: Presence = { foreground, until: this.#now() + validSeconds * 1000, ...(sessionID ? { sessionID } : {}) };
    await this.#host.storage.set(keys.presence(keyID), { ...presence });
  }

  /**
   * Seals one payload for one device and posts it. A device whose app is in the foreground is
   * skipped (its heartbeat is valid for 45 s); unknown presence sends. Returns undefined when
   * nothing was sent.
   */
  async #send(device: Device, kind: Kind, fields: Fields, collapse: string, ignorePresence = false): Promise<Outcome | undefined> {
    if (!ignorePresence && (await this.#presence(device.keyID))) return undefined;
    const recipient = base64url.decode(device.devicePublicKey);
    if (!recipient || recipient.length !== 32) return undefined;
    const policy = kindPolicy(kind);
    const exp = Math.floor(this.#now() / 1000) + policy.ttlSeconds;
    let plaintext: Uint8Array;
    try {
      plaintext = fitPayload({ v: 1, kind, server: device.appServerRef, exp, pending: this.#shared.pending.size, ...fields }).plaintext;
    } catch {
      this.#log(`${kind} payload did not fit`);
      return undefined;
    }
    const envelope = await sealEnvelope({ kind, exp, kid: device.keyID, plaintext, recipientPublicKey: recipient, sender: await this.serverKeys() });
    const thread = await threadFor(device.keyID, fields.rootSessionID ?? fields.sessionID ?? kind);
    const outcome = await this.#relay.push(device, { kind, priority: policy.priority, collapse, thread, expiresAt: exp, envelope });
    await this.#registry.recordDelivery(device.keyID, { kind, result: outcome.result, attempts: outcome.attempts, at: this.#now() });
    if (outcome.result === "gone") await this.#registry.remove(device.keyID);
    return outcome;
  }

  /**
   * Records a Live Activity for a session's root, so one registered with a subagent's ID still
   * follows the run. When the family cannot be read it says why: the caller answers `not_found`
   * for a session opencode does not have, and `unavailable` for a read that failed.
   */
  async registerActivity(keyID: string, activityRef: string, sessionID: string): Promise<"registered" | LookupFailure> {
    const family = await this.#sessions.family(sessionID);
    if ("failure" in family) return family.failure;
    const registration: ActivityRegistration = { keyID, activityRef, sessionID: family.root, registeredAt: this.#now(), step: 0, toolGlyph: "none", phase: "running", waiting: [] };
    await this.#host.storage.set(keys.activity(keyID, activityRef), { ...registration, waiting: [] });
    return "registered";
  }

  /** Live Activity changes read, change and write the stored state, so they run one at a time, in order. */
  #queueActivity(task: () => Promise<void>): Promise<void> {
    const next = this.#activityQueue.then(task);
    this.#activityQueue = next.catch(() => undefined);
    return next;
  }

  async #activitiesFor(sessionID: string) {
    const entries = await scanAll(this.#host.storage, "activity/");
    if (!entries.length) return [];
    // Without the family, an event can still match an activity registered for its own session.
    const root = (await this.#sessions.root(sessionID)) ?? sessionID;
    return entries.flatMap((entry) => {
      const registration = object(entry.value) as unknown as ActivityRegistration;
      return registration.sessionID === root && typeof registration.keyID === "string" ? [{ key: entry.key, registration, own: sessionID === root }] : [];
    });
  }

  /**
   * Progress from the root session sets the phase, and its start resets the step; its end ends the
   * activity. A subagent's events change only the step and the glyph, so a subagent starting or
   * finishing never restarts or ends the root's activity. Progress is sent with priority 5 at most
   * every 30 s, and the latest state goes out when the interval ends.
   */
  async #activityEvent(sessionID: string, change: ActivityChange, event: HostEvent): Promise<void> {
    for (const { key, registration, own } of await this.#activitiesFor(sessionID)) {
      if (change.kind === "end") {
        if (!own) continue;
        clearTimeout(this.#activityTimers.get(key));
        this.#activityTimers.delete(key);
        await this.#host.storage.remove(key);
        await this.#sendActivity({ ...registration, phase: change.phase, waiting: [] }, "end", 10);
        continue;
      }
      const next: Mutable<ActivityRegistration> = { ...registration };
      if (change.glyph) next.toolGlyph = change.glyph;
      if (change.step) next.step = registration.step + 1;
      if (own && change.started) Object.assign(next, { step: 0, toolGlyph: "none", startedAt: event.created ?? this.#now(), waiting: [] });
      // A run waiting for an answer stays "needs input" until every request is answered.
      if (own && change.phase && !next.waiting?.length) next.phase = change.phase;
      await this.#progress(key, next);
    }
  }

  /** A request still pending after its grace period: needs input, sent at once with priority 10. */
  async #activityWaiting(sessionID: string, requestID: string): Promise<void> {
    // An answer that arrived first has already run #activityAnswered, so adding it now would
    // leave the activity waiting for the rest of the run.
    if (!this.#shared.pending.has(requestID)) return;
    for (const { key, registration } of await this.#activitiesFor(sessionID)) {
      const waiting = [...new Set([...(registration.waiting ?? []), requestID])];
      await this.#sendActivity({ ...registration, waiting, phase: "needsInput" }, "update", 10, key);
    }
  }

  /** The last answered request returns the activity to running at once, without waiting for the interval. */
  async #activityAnswered(requestID: string): Promise<void> {
    for (const entry of await scanAll(this.#host.storage, "activity/")) {
      const registration = object(entry.value) as unknown as ActivityRegistration;
      if (!registration.waiting?.includes(requestID)) continue;
      const waiting = registration.waiting.filter((item) => item !== requestID);
      if (waiting.length) await this.#host.storage.set(entry.key, { ...registration, waiting });
      else await this.#sendActivity({ ...registration, waiting, phase: "running" }, "update", 5, entry.key);
    }
  }

  async #progress(key: string, next: ActivityRegistration): Promise<void> {
    const wait = (next.sentAt ?? 0) + this.#activityInterval - this.#now();
    if (wait <= 0) return this.#sendActivity(next, "update", 5, key);
    await this.#host.storage.set(key, { ...next, waiting: [...(next.waiting ?? [])] });
    if (this.#activityTimers.has(key)) return;
    this.#activityTimers.set(key, setTimeout(() => {
      this.#activityTimers.delete(key);
      this.#track(this.#queueActivity(() => this.#flushActivity(key)));
    }, wait));
  }

  async #flushActivity(key: string): Promise<void> {
    const current = object(await this.#host.storage.get(key)) as unknown as ActivityRegistration;
    if (typeof current.keyID === "string") await this.#sendActivity(current, "update", 5, key);
  }

  async #sendActivity(registration: ActivityRegistration, event: "update" | "end", priority: 5 | 10, key?: string): Promise<void> {
    const now = this.#now();
    const stored = { ...registration, waiting: [...(registration.waiting ?? [])] };
    const device = await this.#registry.get(registration.keyID);
    if (!device) {
      if (key) await this.#host.storage.remove(key);
      return;
    }
    // The app updates its own activities while it is in the foreground.
    if (await this.#presence(device.keyID)) {
      if (key) await this.#host.storage.set(key, stored);
      return;
    }
    if (key) await this.#host.storage.set(key, { ...stored, sentAt: now });
    const seconds = Math.floor(now / 1000);
    const state = {
      phase: registration.phase as Phase,
      step: registration.step,
      toolGlyph: registration.toolGlyph,
      startedAt: Math.floor((registration.startedAt ?? registration.registeredAt) / 1000),
      updatedAt: seconds,
    };
    const outcome = await this.#relay.activity(device, {
      ref: registration.activityRef,
      event,
      state,
      staleAt: seconds + staleSeconds,
      ...(event === "end" ? { dismissAt: seconds + dismissSeconds } : {}),
      priority,
    });
    if (outcome.result === "gone" && key) await this.#host.storage.remove(key);
  }
}
