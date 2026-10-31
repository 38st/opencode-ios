# Push relay

The relay holds the APNs key and turns the plugin's sealed envelopes into APNs requests. It never sees notification content: the plugin encrypts every payload for the device (`server/contracts`), and approvals never pass through the relay.

It is a [Hono](https://hono.dev) app with two entry points that share every route:

- `src/worker.ts`: Cloudflare Workers, with D1 for storage and Durable Objects for rate limits and the shared APNs provider token. APNs requests use `fetch`.
- `src/node.ts`: Node 24 or later, with `node:sqlite` for storage and rate limits and `node:http2` for APNs. This is the fallback if a Worker's `fetch` cannot reach APNs over HTTP/2 (see "HTTP/2 check").

## Routes

| Method and path | Caller and auth | Body → result |
| --- | --- | --- |
| `POST /v1/attest/challenge` | App, only with `APP_ATTEST=required` (404 otherwise). Per-IP limit (60 an hour) | `{}` → 201 `{challenge, expiresAt}`. Single use, valid 5 minutes |
| `POST /v1/attest/keys` | App, only with `APP_ATTEST=required` | `{keyID, challenge, attestation}` → 201 `{keyID}`, or 409 if the key is already stored |
| `POST /v1/devices` | App. Per-IP limit (20 an hour). With `APP_ATTEST=required`, the `x-app-attest-key` and `x-app-attest-assertion` headers and a `challenge` in the body | `{apnsToken, env: "sandbox" \| "production", bundleID, challenge?}` → 201 `{deviceID, deviceSecret}` |
| `PUT /v1/devices/{id}` | App, `Authorization: Bearer <deviceSecret>` | `{apnsToken, env?}` → 200 `{deviceID}`. Sent on every launch; repeating it is harmless |
| `DELETE /v1/devices/{id}` | App, device secret | → 204. Removes the device, its senders and its activities |
| `POST /v1/devices/{id}/senders` | App, device secret | → 201 `{senderID, sendToken}`. One per paired server, at most 32 |
| `DELETE /v1/devices/{id}/senders/{sid}` | App, device secret | → 204. Revokes that server only |
| `PUT /v1/devices/{id}/activities/{ref}` | App, device secret | `{pushToken, expiresAt}` → 204. At most 16 live activities; at most 8 hours ahead |
| `POST /v1/push` | Plugin, `Authorization: Bearer <sendToken>` | `{kind, priority, collapse, thread, expiresAt, envelope}` → 200 `{result: "delivered" \| "gone" \| "throttled" \| "rejected"}` |
| `POST /v1/activity` | Plugin, send token | `{ref, event: "update" \| "end", state, staleAt, dismissAt?, priority}` → 200 `{result}` |
| `GET /v1/health` | Public | 200 `{status: "ok", version}`, or 503 `{status: "misconfigured"}` |

Invalid bodies are 400, a missing or wrong secret or token is 401 (the same answer whether the device exists or not), a disallowed bundle ID is 403, a full sender or activity list is 409, the registration limit is 429 and bodies over 16 KB are 413.

### App Attest

Off by default. With `APP_ATTEST=required` a device registers in three steps, each with a fresh challenge:

1. `POST /v1/attest/challenge`, then `DCAppAttestService.attestKey` with SHA-256 of the challenge's UTF-8 bytes as the client data hash. `POST /v1/attest/keys` sends the key ID and the attestation (standard base64). The relay checks the chain to Apple's App Attestation root (pinned in `src/attest/apple-root.ts`), the nonce extension, the app ID (`<team ID>.<bundle ID>` for an allowed bundle ID), the AAGUID for `APP_ATTEST_ENVIRONMENT`, a zero counter and the key ID, then stores the public key.
2. `POST /v1/attest/challenge` again, and a `POST /v1/devices` body that carries that challenge.
3. `generateAssertion` over SHA-256 of the exact body bytes, sent as `x-app-attest-key` (the key ID) and `x-app-attest-assertion` (base64). The relay checks the signature, the app ID against the body's bundle ID, and that the counter is higher than the last one it accepted.

Refusals are 401 with `attestation_required` (headers missing or malformed), `challenge_invalid` (unknown, used or expired challenge), `attest_key_unknown` (no stored key with that ID) or `attestation_invalid` (any check failed, including a replayed counter or an edited body). Verification uses WebCrypto only, so it runs the same on Workers and Node. Only `POST /v1/devices` is gated; the device secret authenticates every later request.

`POST /v1/push` checks that `envelope` is a well-formed v1 envelope whose `kind` and `exp` equal the request's `kind` and `expiresAt`. It forwards only the six envelope fields, so nothing else a sender adds reaches Apple. An envelope that has already expired is `rejected` without contacting APNs.

### The APNs request

| | Alerts (`/v1/push`) | Live Activities (`/v1/activity`) |
| --- | --- | --- |
| `apns-push-type` | `alert` | `liveactivity` |
| `apns-topic` | the device's bundle ID | `<bundle ID>.push-type.liveactivity` |
| `apns-priority` | 10, or 5 for `resolved` | 5 for progress, 10 for needs-input and the end |
| `apns-expiration` | `min(expiresAt, now + lifetime of the kind)`: 10 minutes for approvals, questions and replacements | `staleAt` |
| `apns-collapse-id` | the plugin's hash of the request ID | — |
| Payload | `aps`: the kind's generic `alert.body`, `mutable-content: 1`, `category: "OPEN_ONLY"`, the plugin's opaque `thread-id`, its `interruption-level`, and `sound: "default"` unless passive. `oc`: the envelope | `aps`: `timestamp`, `event`, `content-state`, `stale-date`, and `dismissal-date` on `end` |

The category is always `OPEN_ONLY`, for every kind. The Notification Service Extension sets the kind's category only after it has opened and classified the envelope, so an alert shown without it offers no action (`server/contracts/README.md`, "Categories and actions fail closed"). The kind table (alert text, interruption level, priority and lifetime, and the category the extension sets) is in `server/contracts/constants.json` and its README. Live Activity state must be exactly the coarse fields of `server/contracts/schema/activity-state.schema.json`, because it travels in plaintext.

Provider tokens are ES256 JWTs (`kid` = key ID, `iss` = team ID, `iat`), reused for 50 minutes. On Workers one Durable Object (`ApnsTokenCache`) mints them, so every isolate shares one token and APNs never sees more than one new token in 50 minutes; it refuses updates more often than every 20. On `ExpiredProviderToken` or `InvalidProviderToken` the refused token is dropped and the next request mints a new one.

### Results

| APNs answer | Result | Relay action |
| --- | --- | --- |
| 200 | `delivered` | |
| 410, `Unregistered`, `BadDeviceToken` | `gone` | Clears the device's APNs token; pushes stay `gone` until the app sends a new one with `PUT` |
| 429 | `throttled` | |
| anything else, or no answer within 10 s | `rejected` | |

The relay's own limits also answer `throttled`, without contacting APNs: 30 alerts a minute and 500 a day per device, and 30 Live Activity updates a minute and 2,000 a day per device. On Workers each limited key is its own Durable Object (`RateLimiter`); on Node they are rows in SQLite. Both use fixed windows.

### What the relay stores and logs

D1 (or SQLite) holds, per device: the SHA-256 of its secret, its APNs token (or nothing once gone), its environment and bundle ID; per sender, the SHA-256 of its send token; and per live activity, its push token and expiry. With App Attest, per key: its ID, public key, app ID and last assertion counter, and unused challenges until they expire. `migrations/` creates the tables.

Logs are one JSON line per event with only `event`, `route`, `kind`, `result`, `status` (APNs's numeric HTTP status, when it answered) and `count`. They never contain a token, secret, ID, IP address, APNs reason or envelope; `src/log.ts` drops anything else, and both test runs check the captured logs.

On Workers, `wrangler.toml` keeps Workers Logs for these lines and turns off invocation logs and traces, which record request URLs (with device and sender IDs and activity references) and client IPs. `wrangler tail` streams the same request metadata live to whoever runs it, so use it only to diagnose.

## Running it locally

```sh
npm ci
npm test          # type checks, then the suite in workerd (Miniflare) and against the Node entry point
npm run dev       # wrangler dev, fully local: D1 and Durable Objects are simulated in .wrangler/
```

`npm test` and `npm run dev` go through `scripts/isolated.mjs`, which gives wrangler and workerd a `HOME`, `XDG_CONFIG_HOME` and log directory under this package's `.wrangler/`, turns telemetry off, drops any Cloudflare credentials from the environment, and fails the run if the account's own wrangler state (`~/.wrangler`, `~/Library/Preferences/.wrangler`) changed. `npm test` runs `test/support/suite.ts` twice: in the Workers runtime through `@cloudflare/vitest-plugin`, and against `src/node.ts` over HTTP. Both send to `test/support/mock-apns.ts`, a local APNs stand-in that verifies the JWT signature and claims, every header, the 4 KB payload limit, and the collapse and thread IDs, and answers by device-token prefix (`410…`, `400b…`, `4290…`, `5000…`, `403e…`). Test keys are generated for each run.

`node Tools/push-e2e/index.mjs` (from the repository root) also runs this Worker under `wrangler dev --local`, after `wrangler d1 migrations apply --local`, between the sandboxed opencode server with the plugin and the same mock APNs (see `Tools/README.md`, "Push (M5a)").

### Configuration

| Variable | Meaning |
| --- | --- |
| `APNS_TEAM_ID`, `APNS_KEY_ID` | The Apple Developer team ID and the APNs key's ID (placeholders in `wrangler.toml`) |
| `APNS_PRIVATE_KEY` | The `.p8` key (PKCS#8 PEM). A secret; never commit it |
| `ALLOWED_BUNDLE_IDS` | Comma-separated bundle IDs devices may register with |
| `APP_ATTEST` | `off` (default) or `required`: registration then needs an App Attest assertion (see "App Attest") |
| `APP_ATTEST_ENVIRONMENT` | `production` (default; TestFlight and App Store builds) or `development` (builds signed for development). Picks the AAGUID attestations must carry |
| `APNS_SANDBOX_URL`, `APNS_PRODUCTION_URL` | Test overrides; Apple's hosts by default |
| `RELAY_TEST_MODE`, `RELAY_TEST_LIMITS` | Tests only: with `RELAY_TEST_MODE=1`, JSON overriding the limits, for example `{"alertsPerMinute":3}`. Unknown names, values that are not positive integers, and limits without test mode are configuration errors |
| `APP_ATTEST_TEST_ROOTS` | Tests only: with `RELAY_TEST_MODE=1`, PEM roots that replace Apple's, so the suites can sign attestations. A configuration error without test mode |
| `PORT`, `HOST`, `RELAY_DATABASE` | Node only: the listening address and the SQLite file (`relay.sqlite` by default, which holds APNs tokens and secret hashes) |
| `TRUST_PROXY` | Node only, for the registration limit behind a proxy: `fly` reads `Fly-Client-IP`, which Fly's edge sets; `forwarded` reads the rightmost `X-Forwarded-For` entry, the address one trusted proxy saw. Clients can forge every other entry, so unset uses the connection's address |

## Deploying (for the owner)

Nothing here has been run: it needs the owner's Cloudflare account and APNs key.

1. Create an APNs authentication key in the Apple Developer account (Keys, "Apple Push Notifications service"), and note its key ID and the team ID.
2. `npx wrangler login`
3. `npx wrangler d1 create opencode-push-relay`, and put the printed `database_id` in `wrangler.toml`.
4. `npx wrangler d1 migrations apply opencode-push-relay --remote`
5. In `wrangler.toml`, replace `APNS_TEAM_ID`, `APNS_KEY_ID` and `ALLOWED_BUNDLE_IDS`. Choose a route or custom domain (`workers_dev` is off).
6. `npx wrangler secret put APNS_PRIVATE_KEY < ~/Downloads/AuthKey_<KEYID>.p8`, reading the key from wherever Apple's download landed. Keep the `.p8` outside this checkout (this repository is public and its working tree is committed often; `server/.gitignore` also ignores `*.p8` and `*.pem` as a second guard), and delete the download once the secret is stored.
7. `npx wrangler deploy`, then check `GET /v1/health`.
8. Put the relay's URL in `server/contracts/constants.json` (`relay.defaultURL`) and run the contract sync.

### HTTP/2 check

APNs accepts only HTTP/2. Whether a Worker's outbound `fetch` negotiates it with Apple is unverified. After deploying, register a real device and send one alert:

1. In a development build, register with `env: "sandbox"` and the device's APNs token, then create a sender.
2. `POST /v1/push` with a test envelope. The app's "Send test push" (M5b) does this through the plugin.
3. `delivered` with the notification shown means the Worker works. `rejected` with no notification means it does not; the push's log line in `wrangler tail` carries APNs's `status`, absent when no answer arrived.

If the Worker cannot reach APNs, run the Node entry point instead, for example on Fly.io, with a persistent volume for the database:

```sh
RELAY_DATABASE=/data/relay.sqlite TRUST_PROXY=fly PORT=8080 node src/node.ts
```

with `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_PRIVATE_KEY` and `ALLOWED_BUNDLE_IDS` set as secrets. No Fly.io configuration is included.

## Licence

MIT, see [LICENSE](LICENSE). Hono is MIT-licensed.
