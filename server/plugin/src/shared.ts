import type { RawKeyPair } from "../contracts/src/index.ts";

export interface PendingRequest {
  readonly kind: "permission" | "question";
  readonly sessionID: string;
  /** The location whose permission or form service holds the request. */
  readonly directory: string;
}

export interface PushedRequest {
  readonly sessionID: string;
  readonly rootSessionID: string;
  /** Devices that received the push and need the replacement. */
  readonly keyIDs: Set<string>;
}

/**
 * How a settled request ended, for the replacement of its alert. Replacements for one request run
 * one at a time on `queue`, and each reads `reply` when it sends, so a reply that arrives while
 * one is waiting or in flight supersedes "cancelled" instead of racing it.
 */
export interface Resolution {
  /** The reply event's answer, or "cancelled" when the server dropped the request without one. */
  reply: string;
  /** Whether `reply` came from a reply event; only then is it final. */
  genuine: boolean;
  /** The session and root the request was pushed under. */
  request: Omit<PushedRequest, "keyIDs"> | undefined;
  /** Each device that received the request's push, and the reply it was last sent. */
  readonly sent: Map<string, string | undefined>;
  queue: Promise<void>;
  /** While set, an inferred "cancelled" waits for the request's own reply event. */
  window: ReturnType<typeof setTimeout> | undefined;
  /** When the request was settled. */
  readonly at: number;
}

/**
 * State shared by every instance of the plugin in this process. opencode runs one instance per
 * location and delivers every location's events to each of them; an instance acts on its own
 * location's events, so the requests, replies and pushes of one location can meet another's here,
 * and the badge needs the server-wide pending count. globalThis also survives a plugin reload.
 */
export interface SharedState {
  /** Event IDs claimed for a push in this process, with the time of the claim. */
  readonly claims: Map<string, number>;
  /** Pending permission requests and forms on the server, by request ID. */
  readonly pending: Map<string, PendingRequest>;
  /** Grace-period timers by request ID, so a reply seen by any instance cancels the push. */
  readonly timers: Map<string, ReturnType<typeof setTimeout>>;
  /** Pending requests that were pushed, for the replacement. */
  readonly pushed: Map<string, PushedRequest>;
  /** Recently settled requests, for their replacements and for pushes still in flight when they settled. */
  readonly resolutions: Map<string, Resolution>;
  /** Running instances by location directory, so an event of a location without one is still settled. */
  readonly locations: Map<string, number>;
  /** Each session's location, from the events that carry one, for the session events that do not. */
  readonly sessionLocations: Map<string, string>;
  /**
   * Sessions whose run started while the plugin was running, and whether it has taken a step. A run
   * that only applied a move or another inbox item has none, and finishes without a push.
   */
  readonly executions: Map<string, boolean>;
  /** The static key pair being created, so concurrent instances create it once. */
  keyCreation: Promise<RawKeyPair> | undefined;
}

export const createSharedState = (): SharedState => ({
  claims: new Map(),
  pending: new Map(),
  timers: new Map(),
  pushed: new Map(),
  resolutions: new Map(),
  locations: new Map(),
  sessionLocations: new Map(),
  executions: new Map(),
  keyCreation: undefined,
});

// Bump the version suffix if SharedState changes shape, so an old instance's object is not reused.
const key = Symbol.for("opencode-ios.mobile-push.shared.v7");

export function sharedState(): SharedState {
  const scope = globalThis as unknown as Record<symbol, SharedState | undefined>;
  return (scope[key] ??= createSharedState());
}
