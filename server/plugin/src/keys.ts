import { base64url, generateKeyPair, type RawKeyPair } from "../contracts/src/index.ts";
import type { HostStorage, Json } from "./host.ts";
import type { SharedState } from "./shared.ts";

const KEY = "key/server";

function parse(value: Json | undefined): RawKeyPair | undefined {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return undefined;
  const privateKey = typeof value.privateKey === "string" ? base64url.decode(value.privateKey) : undefined;
  const publicKey = typeof value.publicKey === "string" ? base64url.decode(value.publicKey) : undefined;
  return privateKey?.length === 32 && publicKey?.length === 32 ? { privateKey, publicKey } : undefined;
}

/**
 * The plugin's static X25519 key pair, which devices pin as the HPKE sender key.
 *
 * It lives in `ctx.storage`, opencode's global key-value store (the `kv` table of opencode.db
 * in the data directory), under this plugin's namespace. No HTTP route reads that store, the
 * RPC methods return only the public key, and another plugin's `ctx.storage` is confined to its
 * own namespace. Anything with access to the server's files or shell can still read it.
 *
 * It is created once: instances in one process share the creation, and every use rereads the
 * store, so a second server process sharing the store converges on whichever key was stored.
 */
export async function serverKeys(storage: HostStorage, shared: SharedState): Promise<RawKeyPair> {
  const stored = parse(await storage.get(KEY));
  if (stored) return stored;
  shared.keyCreation ??= (async () => {
    const existing = parse(await storage.get(KEY));
    if (existing) return existing;
    const created = await generateKeyPair();
    await storage.set(KEY, {
      v: 1,
      privateKey: base64url.encode(created.privateKey),
      publicKey: base64url.encode(created.publicKey),
      createdAt: Date.now(),
    });
    return parse(await storage.get(KEY)) ?? created;
  })().finally(() => {
    shared.keyCreation = undefined;
  });
  return shared.keyCreation;
}
