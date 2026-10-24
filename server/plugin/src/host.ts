/**
 * The parts of opencode's V2 Promise plugin context that this plugin uses
 * (packages/plugin/src/promise/plugin.ts). Declared structurally, so the plugin has no runtime
 * dependency on @opencode/plugin and loads against any host that provides these members.
 */
export type Json = null | boolean | number | string | Json[] | { [key: string]: Json };

/** A server event as the Promise API delivers it: the encoded wire form. */
export interface HostEvent {
  readonly id: string;
  readonly type: string;
  readonly created?: number;
  readonly data?: unknown;
  readonly location?: { readonly directory?: string; readonly workspaceID?: string };
}

export interface StorageEntry {
  readonly key: string;
  readonly value: Json;
}

/** `ctx.storage`: the global key-value store (core/src/kv.ts), namespaced to this plugin's ID. */
export interface HostStorage {
  get(key: string): Promise<Json | undefined>;
  set(key: string, value: Json): Promise<void>;
  remove(key: string): Promise<void>;
  scan(options: { readonly prefix: string; readonly after?: string; readonly limit?: number }): Promise<{
    readonly entries: readonly StorageEntry[];
    readonly next?: string;
  }>;
}

export interface RpcMethod {
  readonly input: object;
  readonly output: object;
  readonly errors?: Readonly<Record<string, object>>;
}

export interface RpcDefinition {
  readonly id: string;
  readonly methods: Readonly<Record<string, RpcMethod>>;
  readonly events: Readonly<Record<string, never>>;
}

export interface RpcContext {
  readonly signal?: AbortSignal;
  /** Builds a declared error; the handler returns or throws it. */
  readonly error: (type: string, message: string, data?: unknown) => unknown;
}

export type RpcHandler = (input: unknown, context: RpcContext) => Promise<unknown>;

export interface Host {
  readonly location: { readonly directory: string; readonly project?: { readonly directory?: string } };
  readonly options?: Readonly<Record<string, unknown>>;
  readonly event: { subscribe(options?: { readonly signal?: AbortSignal }): AsyncIterable<HostEvent> };
  readonly storage: HostStorage;
  /** Rejects when the request is no longer pending in that session. */
  readonly permission: { get(input: { readonly sessionID: string; readonly requestID: string }): Promise<unknown> };
  readonly session: { get(input: { readonly sessionID: string }): Promise<unknown> };
  readonly rpc: {
    register(definition: RpcDefinition, handlers: Readonly<Record<string, RpcHandler>>): Promise<{ dispose(): Promise<void> }>;
  };
}
