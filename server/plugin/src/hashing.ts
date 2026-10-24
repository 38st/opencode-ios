import { base64url, sha256, utf8 } from "../contracts/src/index.ts";

/** Opaque, per-device IDs for the relay. The device's key ID salts them, so two devices' IDs for one request are unrelated. */
async function opaque(prefix: string, label: string, keyID: string, value: string): Promise<string> {
  const digest = await sha256(utf8(`opencode-ios ${label}|${keyID}|${value}`));
  return prefix + base64url.encode(digest).slice(0, 32);
}

/** apns-collapse-id for a request: the replacement after a reply carries the same one. */
export const collapseForRequest = (keyID: string, requestID: string) => opaque("c", "collapse", keyID, requestID);
/** apns-collapse-id for a session's result, so a later result replaces an earlier one. */
export const collapseForResult = (keyID: string, sessionID: string) => opaque("c", "result", keyID, sessionID);
export const collapseForTest = (keyID: string) => opaque("c", "test", keyID, "test");
/** thread-id: one thread per root session. */
export const threadFor = (keyID: string, rootSessionID: string) => opaque("t", "thread", keyID, rootSessionID);
