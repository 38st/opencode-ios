import contract from "../constants.json" with { type: "json" };

/** The shared constants. constants.json is the single source; Swift reads a byte-identical copy. */
export const CONTRACT = contract;

export type Kind = keyof typeof contract.kinds;
export const KINDS = Object.keys(contract.kinds) as Kind[];
export const isKind = (value: unknown): value is Kind =>
  typeof value === "string" && Object.hasOwn(contract.kinds, value);

export type Priority = 5 | 10;
export type InterruptionLevel = "passive" | "active" | "time-sensitive";
export interface KindPolicy {
  readonly alert: string;
  readonly category: string;
  readonly interruptionLevel: InterruptionLevel;
  readonly priority: Priority;
  readonly ttlSeconds: number;
}
export const kindPolicy = (kind: Kind): KindPolicy => contract.kinds[kind] as KindPolicy;

/** The generic alert text the relay shows when the extension cannot decrypt, per kind. */
export const GENERIC_ALERTS: Readonly<Record<Kind, string>> = Object.fromEntries(
  KINDS.map((kind) => [kind, contract.kinds[kind].alert]),
) as Record<Kind, string>;

export const PACKAGE_NAME = contract.names.package;
export const PLUGIN_ID = contract.names.plugin;
export const RPC_ID = contract.names.rpc;
export const DEFAULT_RELAY_URL = contract.relay.defaultURL;
export const HPKE_INFO = contract.hpke.info;
export const PADDING_BUCKETS: readonly number[] = contract.padding.buckets;
export const MAX_PLAINTEXT = Math.max(...contract.padding.buckets) - 1;
export const ENVELOPE_VERSION = contract.envelope.version;
export const PAYLOAD_VERSION = contract.payload.version;
