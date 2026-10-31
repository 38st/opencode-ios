# opencode mobile push plugin

An [opencode](https://github.com/anomalyco/opencode) V2 server plugin that notifies the opencode-ios app when a session needs you or finishes. It seals every notification for the device with HPKE, so the relay that forwards it to Apple cannot read it, and it never approves anything: the app answers over its own connection to the server. With your own APNs key it can also send straight to Apple, with no relay ([Direct mode](#direct-mode)).

`@opencode-ios/opencode-mobile-push` is a placeholder name until the package is published.

## Install

Server plugins are installed globally:

```sh
opencode plugin add @opencode-ios/opencode-mobile-push
```

`plugin add` has no scope flag: for a package with a server entry point it always adds it to the global configuration (the first of `opencode.json`, `opencode.jsonc`, `.opencode/opencode.json` and `.opencode/opencode.jsonc` that exists in `~/.config/opencode`, or `$OPENCODE_CONFIG_DIR`, else a new `opencode.json`), installs the package and its dependencies into opencode's package cache, and prints `Plugin "<spec>" installed and added to <path>`. It accepts npm registry specifiers and Git specifiers, not local paths. A Git specifier needs the package at the repository's root, because npm installs no subdirectory of a repository, so this checkout itself cannot be installed that way.

Until the package is on npm, add the directory to `plugins` in a configuration file instead, after `npm ci` in it:

```json
{ "plugins": ["/absolute/path/to/server/plugin"] }
```

opencode reads a local plugin directory in place, with its `node_modules`, and loads `server.ts` without a build step.

## Direct mode

By default each push goes through the relay the device registered with. In direct mode the plugin sends the same requests to APNs itself: the same sealed payload, collapse IDs, priorities, expiry and Live Activity updates, over one HTTP/2 connection per process with a provider token (ES256) reused for 50 minutes. You need:

- an Apple Developer Program membership and an APNs authentication key (`.p8`) with its key ID and your team ID;
- the app built with your own bundle ID, since APNs delivers only to apps your team signs;
- the key file readable only by the user running opencode. The plugin refuses a file with any group or other permission, one owned by another user, or one that is not a PEM private key.

```sh
chmod 600 /Users/Shared/opencode/AuthKey_ABC123DEFG.p8
```

Give the plugin its options with the object form of a `plugins` entry:

```json
{
  "plugins": [{
    "package": "@opencode-ios/opencode-mobile-push",
    "options": { "apns": {
      "keyFile": "/Users/Shared/opencode/AuthKey_ABC123DEFG.p8",
      "keyID": "ABC123DEFG",
      "teamID": "TEAM123456",
      "bundleID": "com.example.opencode",
      "environment": "production"
    } }
  }]
}
```

`environment` is `production` (the default) or `sandbox` for a development build; `keyFile` may start with `~/`. A missing or invalid option leaves direct mode off and logs one line with the reason (`[mobilepush] direct mode off: …`), never the key; relay devices are unaffected. When it loads, the plugin logs `direct mode on` with the environment and bundle ID. `status` then reports `direct: {available: true, bundleID, environment}`, and the app registers with `transport: "direct"`, its APNs device token, bundle ID and environment, which must match the option. The key stays in the plugin's memory: no RPC returns it or its path. A direct device whose option is later removed keeps its registration and is reported `unreachable` until direct mode is back.

`origin` (an `http://` address on this machine) points the plugin at a local APNs stand-in instead of Apple; it exists for `Tools/push-e2e` and is refused for any other host.

The plugin loads once per location (each directory opencode serves). The app detects it by calling `status` and shows the install command when it is missing.

## What it sends

| Event | Push | Rules |
| --- | --- | --- |
| `permission.asked` | `permission` | After a 3-second grace period, only if the request is still pending. A request answered first, at the desk or by an automatic rule, is never pushed. |
| `form.created` | `question` | The same grace period and check. |
| `session.execution.failed` | `failed` | Any session, under its root. |
| `session.execution.succeeded` | `finished` | Root sessions only, and only a run that took a step: opencode also runs an execution to apply a move or another inbox item, and that finishes silently. A run the plugin did not see start is pushed. |
| `permission.replied`, `form.replied`, `form.cancelled` | `resolved` | Only for requests that were pushed: a passive replacement with the same collapse ID, so the alert becomes "Answered on another device". |
| `session.execution.interrupted`, `session.deleted`, `location.shutdown` | `resolved` | With reply `cancelled`, for a pushed permission request the server dropped without an answer. Stop and deletion interrupt a waiting request and opencode then removes it without `permission.replied` (`core/src/permission.ts`), so the plugin asks again with `ctx.permission.get`, at once and, for any the server still holds, 2 seconds later. The replacement then waits 1 second, because the request's own reply can still be on its way (an answer at the desk racing Stop, or the `reject` a closing location publishes for each request, `core/src/location-lifecycle.ts`); a reply that arrives in time is sent instead. Forms need no check: opencode cancels them with `form.cancelled`. |

**Replacements.** A device gets one `resolved` push per pushed request. Replacements for one request are sent one at a time, each with the latest reply, and a device that was already sent that reply gets nothing more, so a reply seen twice, or after a re-check, is not sent again. The exception is a reply that arrives after its `cancelled` replacement went out: it follows that push, under the same collapse ID, so the alert ends on the real answer. A `cancelled` replacement still waiting when the plugin stops is sent at once.

Requests from a child session (a subagent) carry the root session's ID, so the notification opens the transcript the user knows. If the family cannot be read (opencode has no such session, or `ctx.session.get` fails twice), a request or failure is still pushed, with its own session as the root, because a missed approval is worse than a misplaced thread; a `finished` push is skipped, since only a root's success counts. Each device can turn kinds off with `prefs`.

The sealed payload carries the kind, the app's reference for the server, the session and root session IDs, the session title and project folder name, the request ID, action and a summary of at most 300 characters (the command, path or question), the option labels, the risk tier from the shared risk rules, the request's digest, the number of pending requests on the server and the expiry. `server/contracts/README.md` defines the payload, padding, digest and envelope exactly.

**Presence.** While the app is in the foreground it calls `setPresence` every 30 seconds. A heartbeat counts for 45 seconds; while it is valid nothing is pushed to that device except a test push and the replacement for an alert it already received, so an actionable alert never outlives its request. Without a heartbeat the push is sent.

**Delivery.** Each push goes to the relay URL the device registered with, using that device's send token for this server, and never follows a redirect. Network failures, 5xx answers and `rejected` are retried up to three times (after 1, 2 and 4 seconds) while the push is unexpired. `gone`, or a 401 because the app revoked this server, removes the registration. A direct device's push goes to APNs with the same retries: network failures, 5xx and refused provider tokens are retried; 410, `Unregistered` and `BadDeviceToken` are `gone` and remove the registration; 429 is `throttled`. The last result per device is kept for `listDevices`.

**Locations.** opencode runs one instance of the plugin per location (each directory it serves), and in opencode 2.1.3 every instance's `ctx.event.subscribe()` carries every location's events, not only its own (seen live; `core/src/bus.ts` `local()` filters by location only for a subscriber that has a location, and the plugin host subscribes without one). So an instance acts only on events of its own location, where `ctx.permission.get` can find the request, and each event is handled once. One exception keeps alerts from going stale: when no instance of an event's location runs in the process, any instance settles that location's replies and its `location.shutdown`. Some session events, such as `session.execution.*`, arrive without a location (the bus routes them by session instead); the plugin places those by the session's location, learned from the session's other events or read with `ctx.session.get`. Other events without a location are global, and ignored. A `sent/<eventID>` claim in shared storage, taken atomically within the process, also stops a repeated delivery from being pushed twice, including by a second process sharing the store; replacements need no claim, since they record the reply each device was sent. Pending requests, grace timers and resolutions are shared by every instance in the process, and the pending count covers the whole server.

**Live Activities.** An activity follows the root of the session the app registered with `registerActivity`. The root's own events set its phase: `session.execution.started` resets the step count, steps and tools advance it, and the root's success, failure, interruption or deletion ends it. A subagent's events only advance the step count and the tool category, so a subagent starting or finishing never restarts or ends the root's activity. Progress is sent with priority 5 at most every 30 seconds, with the latest state sent when the interval ends. A request in the root or a subagent that is still pending after the grace period shows needs input at once, with priority 10; when the last such request is answered the activity returns to running at once, with priority 5. The end is sent with priority 10. Every update is stale 5 minutes later; the end is dismissed after 15 minutes. The state is coarse because it is not encrypted: phase, step count, a tool category, and two timestamps. While the app is in the foreground it updates its activities itself, and the plugin sends none.

## RPC methods

Clients call `POST /api/rpc/mobilepush/<method>` with `{"input": …}`, on any location (`?location[directory]=…`, or the server's default). `input` is required, `{}` for a method without input; without it opencode answers 400 `rpc.invalid_input`. Storage is global, so a device registered through one location is seen by all.

| Method | Input | Output |
| --- | --- | --- |
| `status` | none | `{package, pluginVersion, rpcVersion, serverPublicKey, devices, direct, instance}`. `direct` is `{available: true, bundleID, environment}` in direct mode, else `{available: false}`. `instance` names this location and counts the events it received |
| `registerDevice` | Relay: `{transport?: "relay", sendToken, relayURL, devicePublicKey, keyID, appServerRef, label?, prefs?}`. Direct: `{transport: "direct", apnsToken, bundleID, environment, devicePublicKey, keyID, appServerRef, label?, prefs?}` | `{serverPublicKey, pluginVersion}`. A direct registration is `invalid` (`field: "transport"`) when direct mode is off, and (`field: "bundleID"` or `"environment"`) when it does not match the option |
| `unregisterDevice` | `{keyID}` | `{removed}` |
| `listDevices` | none | `{devices: [{keyID, transport, label, appServerRef, relayURL (relay) or bundleID and environment (direct), prefs, registeredAt, lastDelivery?}]}` |
| `test` | `{keyID}` | `{result, attempts}` |
| `registerActivity` | `{keyID, activityRef, sessionID}`, plus `{pushToken, expiresAt}` for a direct device | `{registered: true}`. `not_found` if opencode has no such session, or its parent is gone; `unavailable` if the family could not be read, so call again. For a direct device `pushToken` is the activity's APNs push token in hex and `expiresAt` a future Unix time in seconds (capped at 8 hours); a relay device's are ignored, since its relay keeps them |
| `setPresence` | `{keyID, foreground, sessionID?}` | `{validSeconds, heartbeatSeconds}` |

`devicePublicKey` is the device's raw 32-byte X25519 public key (CryptoKit's `rawRepresentation`) in base64url; `serverPublicKey` is the plugin's, in the same form, which the app pins. `relayURL` must be `https`, or `http` on this machine. `apnsToken` and `pushToken` are hex (64 to 400 digits); `environment` is `sandbox` or `production`. Errors come back as HTTP 400 with `{"_tag": "RpcError", "type", "message", "data"}`. The types are `invalid` (`{field}`, the offending field), `not_found` (`{field, retryable: false}`: no device with that `keyID`, or no session with that `sessionID`, so the same call fails again) and `unavailable` (`{field, retryable: true}`: a read the server could not complete, so call again later). No method returns a send token, an APNs token or a private key.

## Storage and the key

Everything is kept in `ctx.storage`, opencode's global key-value store, under this plugin's namespace:

| Key | Contents |
| --- | --- |
| `key/server` | The plugin's static X25519 key pair |
| `device/<keyID>` | A registration, including its send token (relay) or APNs device token (direct) |
| `delivery/<keyID>` | The last delivery result |
| `presence/<keyID>` | The last heartbeat |
| `activity/<keyID>/<ref>` | A registered Live Activity and its last state, with its push token for a direct device |
| `sent/<eventID>` | Deduplication claims, removed after a day |

The key pair is created once, the first time any instance starts. Its private key stays in the store: it is the `kv` table of `opencode.db` in opencode's data directory, not the project, the configuration or the logs. No HTTP route reads that store, the RPC methods return only the public key, and another plugin's `ctx.storage` is confined to its own namespace. Anyone who can read the server's files or run commands on it, including any authenticated API client, can still read it; such a client already controls the machine.

## Development

```sh
npm ci
npm test               # type check and the Vitest unit tests (fake host, relay and a local HTTP/2 APNs)
npm run sync-contracts # after changing server/contracts
```

The package ships its TypeScript sources, as opencode's own plugins do; opencode runs them directly. `contracts/` is a copy of `server/contracts`, kept identical by `npm run sync-contracts` and checked by `test/contracts-copy.test.ts`. The live tests run inside an isolated opencode server through `Tools/opencode-sandbox` (see `Tools/README.md`).

## Licence

MIT, see [LICENSE](LICENSE). The dependencies `@hpke/core`, `@hpke/dhkem-x25519` and `@hpke/chacha20poly1305` (with `@hpke/common`) are MIT-licensed.
