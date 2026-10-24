import type { Host } from "./host.ts";

export interface SessionSummary {
  readonly title?: string;
  readonly parentID?: string;
  /** The directory of the session's location. */
  readonly directory?: string;
}

/** Why a session could not be read: opencode has no such session, or the read failed and may work later. */
export type LookupFailure = "missing" | "unavailable";

const MAX_DEPTH = 16;
/** MCP elicitations belong to this sentinel owner instead of a session (schema Form.Info). */
export const GLOBAL_OWNER = "global";

/**
 * Rejections that mean the ID will never resolve: opencode's tagged error for an unknown session
 * (core/src/session/error.ts), and the schema error for an ID it cannot decode (session IDs start
 * with "ses", schema/src/session-id.ts). Anything else, such as a database error, may pass.
 */
const FINAL = new Set(["Session.NotFoundError", "SchemaError"]);
function final(error: unknown): boolean {
  const { _tag: tag, name } = (typeof error === "object" && error !== null ? error : {}) as { _tag?: unknown; name?: unknown };
  return FINAL.has(String(tag)) || FINAL.has(String(name));
}

/** Session titles and families, read through `ctx.session.get` (a global, not location-scoped, read). */
export class Sessions {
  readonly #host: Host;
  /** A session's parent never changes, so it is cached for the plugin's lifetime. */
  readonly #parents = new Map<string, string | null>();

  constructor(host: Host) {
    this.#host = host;
  }

  /** The session's title and parent, or undefined if it cannot be read. */
  async summary(sessionID: string): Promise<SessionSummary | undefined> {
    const result = await this.#read(sessionID);
    return typeof result === "string" ? undefined : result;
  }

  /** Reads a session, retrying a failed read once. opencode answering that it has no such session is final. */
  async #read(sessionID: string): Promise<SessionSummary | LookupFailure> {
    if (sessionID === GLOBAL_OWNER) return {};
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const info = (await this.#host.session.get({ sessionID })) as { title?: unknown; parentID?: unknown; location?: { directory?: unknown } } | undefined;
        const parentID = typeof info?.parentID === "string" ? info.parentID : undefined;
        const directory = typeof info?.location?.directory === "string" ? info.location.directory : undefined;
        this.#parents.set(sessionID, parentID ?? null);
        return { ...(typeof info?.title === "string" && info.title ? { title: info.title } : {}), ...(parentID ? { parentID } : {}), ...(directory ? { directory } : {}) };
      } catch (error) {
        if (final(error)) return "missing";
      }
    }
    return "unavailable";
  }

  /**
   * The root of a session's family: requests from a subagent open the transcript of its root.
   * When the family cannot be read, says whether a session in it is missing or a read failed.
   */
  async family(sessionID: string): Promise<{ readonly root: string } | { readonly failure: LookupFailure }> {
    if (sessionID === GLOBAL_OWNER) return { root: GLOBAL_OWNER };
    let current = sessionID;
    for (let depth = 0; depth < MAX_DEPTH; depth++) {
      let parent = this.#parents.get(current);
      if (parent === undefined) {
        const result = await this.#read(current);
        if (typeof result === "string") return { failure: result };
        parent = result.parentID ?? null;
      }
      if (!parent) return { root: current };
      current = parent;
    }
    return { failure: "unavailable" };
  }

  /** The root, or undefined when the family cannot be read; each caller decides how to fall back. */
  async root(sessionID: string): Promise<string | undefined> {
    const family = await this.family(sessionID);
    return "root" in family ? family.root : undefined;
  }
}
