// Provider tokens are shared with the plugin's direct mode (server/contracts/src/apns.ts).
import {
  importSigningKey, localTokenProvider as sharedTokenProvider,
  type ApnsKey, type TokenProvider,
} from "../../../contracts/src/apns.ts";

export {
  importSigningKey, signProviderToken, TOKEN_LIFETIME, TokenCache,
  type ApnsKey, type IssuedToken, type TokenProvider,
} from "../../../contracts/src/apns.ts";

/** The Node provider: one cache in process memory. */
export function localTokenProvider(key: ApnsKey, now: () => number): TokenProvider {
  return sharedTokenProvider(key, importSigningKey(key.privateKey), now);
}
