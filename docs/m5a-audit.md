# M5a implementation and verification

M5a is the server side of push: the shared contracts, the opencode plugin, the relay, and the Swift envelope core in `OCPushCore`. Everything runs and is proven on this Mac. No account was created or used: nothing was published to npm, deployed to Cloudflare or Fly.io, or sent to Apple, and the real APNs service was never contacted. The plugin was installed and loaded only inside Tools/opencode-sandbox. No branch, global tool, Swift dependency, simulator or runtime was created or changed. SPEC.md, ARCHITECTURE.md, research/ and docs/design.md are unchanged. docs/roadmap.md was updated at the orchestrator's request (M5a landed, M5b next, and the owner-gated checks). The live server was the newest stable 2.x at the time of each run: **2.1.3** for most of the work and **2.1.4**, released during the review, for the final runs; the brief expected 2.1.2.

## Implementation

- **`server/contracts`** (MIT) is the single source of truth.
  - `constants.json`: names, relay URL, HPKE suite, padding, payload limits, the per-kind alert, category, interruption level, priority and lifetime, the limits, presence and activity timings.
  - `risk-rules.json`: M3a's rules in a portable regular-expression dialect, plus force-push and an explicit `external_directory`.
  - JSON Schemas for the envelope, the sealed payload and the Live Activity state.
  - TypeScript for JCS, digests, padding, payload fitting and HPKE seal/open.
  - `scripts/generate-vectors.ts`, a deterministic generator with `--check`.
  - `README.md` defines every rule normatively.
  - 263 Vitest tests, including RFC 9180 A.2.3, a validator for the portable dialect, M3a compatibility, and time bounds on adversarial inputs.
- **`OCPushCore`** (GPL-3.0-only, part of the app) replaces the placeholder.
  - Base64url, JCS, `PushDigest`, `PushPadding`, `PushEnvelope`/`PushSealing` (CryptoKit `HPKE` in auth mode: open, plus seal for tests), `PushPayload`, `PushContract`.
  - `PermissionRisk`, moved from OCModels with the same API and now driven by the shared rules.
  - The two JSON files are a package resource that `Tools/sync-push-contracts.mjs` copies. A test fails if either copy differs by one byte.
  - Every shared vector runs in Swift Testing: 10 JCS, 13 digest, 18 padding, 68 risk, 8 payload, 8 open and 28 rejection cases, and RFC 9180. A guard test fails if a vector file loses its cases, and timing tests bound every risk rule on adversarial inputs.
  - `OCSecurity/PushKeyStore` keeps one X25519 key per paired server in the Keychain (`AfterFirstUnlockThisDeviceOnly`, configurable access group).
- **`server/plugin`** (MIT, `@opencode-ios/opencode-mobile-push` 0.1.0) is a V2 Promise plugin that ships its TypeScript sources, as opencode's own figma plugin does.
  - The seven `mobilepush` RPC methods.
  - The static key pair, created once in `ctx.storage`.
  - Triggers: the 3 s grace period with a `ctx.permission.get` check, failures, root successes, and replacements.
  - Presence, child-to-root mapping, `sent/<eventID>` claims, three retries, removal on `gone`, and Live Activity throttling.
  - 60 Vitest tests against a fake host and relay.
- **`server/relay`** (MIT) is one Hono app with two entry points.
  - Workers: D1, a `RateLimiter` Durable Object per limited key, and an `ApnsTokenCache` Durable Object that shares the provider token.
  - Node: `node:sqlite` and `node:http2`.
  - Every §4.3 route, with secrets and send tokens stored only as SHA-256 hashes.
  - The APNs request and response mapping, the limits, count-only logs, `GET /v1/health`, D1 migrations, a placeholder `wrangler.toml`, and a disabled App Attest hook.
  - 91 Vitest tests: 33 in workerd and 58 against the Node entry. Both runs send to a mock APNs that checks the JWT, the headers, the size and the collapse and thread IDs.
- **`Tools/push-e2e`**:
  - `plugin-checks.mjs` holds the plugin live checks and the M0 answers. `Tools/contract/index.mjs` also runs them, so the nightly contract covers new opencode releases.
  - `index.mjs` is the local end-to-end, with the relay under `wrangler dev`.
- **CI**: `.github/workflows/plugin.yml` and `relay.yml` run `npm ci` and `npm test` on Ubuntu with Node 26 (the plugin workflow also runs the contracts and `generate-vectors --check`). The existing package-test job runs the Swift vectors. `contract.yml` installs the contracts and the plugin, runs the plugin checks inside the contract, and allows 30 minutes instead of 20.
- **Licences**: an MIT `LICENSE` reading "Copyright (c) 2026 38st" in each server package, `"license": "MIT"` in each `package.json`, a THIRD_PARTY_NOTICES.md section for `@hpke/*` and Hono, and the root README states the MIT licensing.
- **Harness fix**: opencode 2.1.3 rewrote its title prompt, so the scripted model sent the title request down the primary lane and the existing contract timed out waiting for `session.renamed`. `Tools/mock-llm/scenarios.mjs` now recognises both wordings, with a test.

## Verification

Each Verify command ran once more, in order, after the last review fix, with fresh logs under `.build/m5a/` (prefix `r2-`). The live server was the newest stable 2.x at the time of each run: 2.1.3 for the runs before the review and 2.1.4 (contract) and 2.1.4 (end-to-end) afterwards, with V1 1.19.3 for detection. The earlier full pass before the review is under the `final-` prefix.

| Command | Result and evidence |
| --- | --- |
| `xcodegen generate` | Passed. `.build/m5a/final-1-xcodegen.log` (the project definition did not change in the review fixes). |
| `swift test --package-path Packages/OpencodeKit` | 283 tests passed with zero failures and no compiler warnings. Five expected skips: four live tests that need the contract's environment, and `pushesFromTheEndToEndRunOpenInSwift`, which needs the end-to-end's capture. `.build/m5a/r2-swift-test.log`. |
| The brief's Node test globs | 37 passed, zero failures or skips, including the mock's 2.1.3 title test and the home-path test over the new untracked files. `.build/m5a/r2-node.log`. |
| `npm test` in `server/contracts` | Type check, then 263 tests passed, including the time bounds on adversarial inputs. `node scripts/generate-vectors.ts --check`: vectors current (`.build/m5a/r2-vectors-check.log`). `.build/m5a/r2-npm-contracts.log`. |
| `npm test` in `server/plugin` | Type check, then 60 tests passed, including the byte-for-byte check of the vendored contracts. `.build/m5a/r2-npm-plugin.log`. |
| `npm test` in `server/relay` | Both type checks, then 33 tests in workerd and 58 against the Node entry passed, through `scripts/isolated.mjs`, which found the account's wrangler state unchanged. `.build/m5a/r2-npm-relay.log`. |
| `node Tools/sync-push-contracts.mjs --check` | OCPushCore's copies are current; the Swift test also checks the bytes. `.build/m5a/r2-sync-check.log`. |
| `node Tools/contract/index.mjs` | Passed against V2 2.1.4: every existing Node and Swift live check, then the 16 push plugin checks (configuration install, then `opencode plugin add`). `.build/m5a/r2-contract.log`; isolation `.build/opencode-sandbox/audits/contract-1792794497742/comparison.json`, five launches verified, zero failures and observations. |
| `node Tools/push-e2e/index.mjs` | Passed every check below against V2 2.1.4, and the guard found the account's wrangler state unchanged. `.build/m5a/r2-push-e2e.log`; results, the Swift capture and `swift.log` in `.build/push-e2e/1792794711651/`; isolation `.build/opencode-sandbox/audits/push-e2e-1792794711652/comparison.json`, verified, zero failures and observations. |
| `xcodebuild -project Opencode.xcodeproj -scheme Opencode -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/DerivedData build` | BUILD SUCCEEDED with no warnings. The app embeds `OpencodeKit_OCPushCore.bundle/Contracts/{constants,risk-rules}.json`. `.build/m5a/r2-xcodebuild.log`. |
| `node Tools/ui-smoke/index.mjs`, full run with the iPad flow, twice in a row | Passed twice in a row on the final code (`ui-1792799286576`, then `ui-1792812358922`): iPhone 41 of 41 and iPad 4 of 5 with the known ⌘F expected failure, zero skips, each time. One earlier attempt after the review failed an iPad hit test under a load spike. Logs `.build/m5a/final-7-ui-smoke-r2-{b,c}.log`; see "UI smoke runs" below. |
| `git diff --check` | Clean for the tracked changes, and `git diff --no-index --check` is clean for each of the 133 new files. Run after the last edit of this audit. |

What the end-to-end proved:

- The relay ran in workerd under `wrangler dev --local`, with local D1 and both Durable Objects.
- A fake phone registered at the relay and through the plugin RPC, with CryptoKit-format raw X25519 keys.
- A real permission request and a real question reached the mock APNs as generic alerts. The mock found no problem with the JWT, the headers, the size or the IDs. The category was `OPEN_ONLY`, `mutable-content` was 1, and the interruption level and priority were the kind's.
- Both envelopes opened with the TypeScript contracts, and the digests matched a fresh `GET`.
- `OCPushCore` opened all four captured pushes in Swift (permission, replacement, finished, question), recomputed both digests and refused copies with an altered ciphertext or expiry. In TypeScript, a changed request no longer matched the digest.
- The desktop answer replaced the alert under the same collapse ID, and the session's success arrived as `finished`.
- Nothing was sent for a request answered inside the grace period, and nothing (request or result) while the presence heartbeat was valid.
- The relay answered `throttled` once the device's one-minute window was full, without contacting APNs. APNs 410 became `gone`, and the plugin removed that registration.
- The relay's 21 log lines carried only its six fields, and its output held no token, secret or envelope.

### UI smoke runs

Each full `node Tools/ui-smoke/index.mjs` run waited for the one-minute load average to fall below 60 before starting (`.build/m5a/ui-run.sh`; the attempt table shows the waits). Every run was against the sandbox's default 2.x of the moment, with the mock LLM fix in place. A run is the iPhone stage (41 XCUITest cases, including the four snapshot suites) followed by the iPad stage (5 cases, one of them the known ⌘F expected failure).

| Attempt | Run directory | Load at start | Load at end | Result |
| --- | --- | --- | --- | --- |
| Before the review, 1 | `ui-1792679330645` | 124.42 / 161.58 / 155.83 (waited 20 min, cap) | 149.05 / 158.03 / 154.89 | Failed in sandbox setup: a fetch to the V2 server timed out before any test ran (`.build/m5a/final-7-ui-smoke-1.log`) |
| Before the review, 2 | `ui-1792680649038` | 232.04 / 215.11 / 199.68 (waited 20 min, cap) | 265.86 / 234.46 / 209.27 | The same setup timeout (`final-7-ui-smoke-2.log`) |
| Before the review, 3, run 1 | `ui-1792681491437` | 53.65 / 120.03 / 167.30 (waited 12 min) | 7.21 / 7.73 / 10.20 | Passed: iPhone 41 of 41, iPad 4 passed and the expected ⌘F failure (`final-7-ui-smoke-3.log`) |
| Before the review, 3, run 2 | `ui-1792686092151` | 5.47 / 7.28 / 9.93 | — | Void: the session running it ended during the iPhone stage (`final-7-ui-smoke-4.log`); its audit holds only `before.json` |
| After the review, 1 | `ui-1792794798386` | 4.02 / 7.83 / 12.70 | 4.49 / 7.14 / 9.36 | iPhone 41 of 41 passed. iPad: `testReadScreens` failed, "Failed to determine hittability of homeSession-… Button: Activation point invalid", while the host load rose to 77 from other projects during that stage; the other three passed and ⌘F was the expected failure (`final-7-ui-smoke-r2-a.log`). Its audit verified both launches with zero failures; it recorded 35 unattributed observations in the owner's own `~/.local/share/opencode` (`opencode.db`, its WAL, the log) and `~/.cache/opencode/models.json` between 22:54:54Z and 23:01:49Z, the owner's own `opencode serve --service` at work; nothing was suppressed. |
| After the review, 2, run 1 | `ui-1792799286576` | 4.08 / 6.73 / 9.10 | 4.21 / 4.85 / 5.76 | Passed: iPhone 41 of 41, iPad 4 passed and the expected ⌘F failure (`final-7-ui-smoke-r2-b.log`). Its audit verified both launches with zero failures and recorded 429 warnings, all in the owner's own opencode directories while the owner was using opencode: 424 unattributed writes to `~/.local/share/opencode/{opencode.db,opencode.db-wal,log,auth.json,storage/session_diff}`, `~/.cache/opencode/models.json` and `~/.config/opencode/AGENTS.md` between 23:54:54Z and 01:03:26Z, and five writes to the database attributed to the external `opencode` PID 32480, the owner's `opencode serve --service`. Nothing was suppressed. |
| After the review, 2, run 2 | `ui-1792812358922` | 6.37 / 5.81 / 5.63 | 6.15 / 6.72 / 7.71 | Passed: iPhone 41 of 41, iPad 4 passed and the expected ⌘F failure (`final-7-ui-smoke-r2-c.log`). Its audit verified both launches with zero failures and recorded 43 unattributed warnings in the owner's own `~/.local/share/opencode` (the database, its WAL and the log) and `~/.cache/opencode/models.json` between 03:26:00Z and 03:56:53Z; nothing was suppressed. |

Attempt 2 after the review is the two consecutive passing runs on the final code, both including the iPad stage. No approval snapshot changed: none of the snapshots' requests (`edit`, `git reset --hard HEAD~1`) has a different tier under the shared rules, and `git status` shows no changed or new image under `Tests/*/__Snapshots__` after the runs.

## End-to-end measurements

Times run from the moment the harness saw the request's event on the SSE stream to the moment the in-process mock APNs had recorded the request. They include the plugin's 3,000 ms grace period, the plugin, the relay in workerd and the ES256 signing. Each is one sample; the polling resolution is 25 ms.

| Path | Final run | All passing runs | Evidence |
| --- | ---: | ---: | --- |
| Permission request → mock APNs, through the plugin and the relay in workerd | 3,038 ms | 3,038–3,158 ms | `.build/m5a/r2-push-e2e.log`, `final-5-push-e2e.log`, `push-e2e-2.log`, `push-e2e-3.log` |
| Question → mock APNs | 3,020 ms | 3,009–3,033 ms | the same logs |
| Desktop answer → replacement at the mock APNs | 32 ms | 26–59 ms | the same logs |
| Permission request → the plugin's push at a recording relay (no relay, no APNs) | 2,995 ms | 2,992–3,017 ms | `.build/m5a/r2-contract.log`, `final-4-contract.log` and the `plugin-checks-*.log` runs |

Beyond the grace period, the plugin and relay add roughly 0.01–0.16 s, the most when the host load was near 99. A replacement needs no grace period. These are local numbers. A real APNs delivery and the Notification Service Extension add time that only a device can measure (docs/roadmap.md, "Not yet verified").

## M0 answers (opencode 2.1.3 and 2.1.4)

Each answer was proven live in the sandbox by `Tools/push-e2e/plugin-checks.mjs` (`push-plugin.json` in each run's audit directory), first on 2.1.3 and again on 2.1.4 in the final contract run, and agrees with the d0732ea source unless noted.

1. **Install command and scope.** The command is `opencode plugin add <npm or Git specifier>`, with no scope flag. For a package with a server entry point it always writes the global configuration (the first existing `opencode.json`, `opencode.jsonc`, `.opencode/opencode.json` or `.opencode/opencode.jsonc` in the global configuration directory, `~/.config/opencode` or `$OPENCODE_CONFIG_DIR`, else a new `opencode.json`). It installs the package and its dependencies into opencode's package cache and prints `Plugin "<spec>" installed and added to <path>`. Local paths are refused.
   - A Git specifier needs the package at the repository's root, because npm installs no subdirectory. The live check builds such a repository inside the run directory, installs it with `git+file://…`, and a server started on that configuration loads it.
   - The other install is a configuration entry naming the directory, `"plugins": ["/abs/path/server/plugin"]`. opencode reads the directory in place, with its `node_modules`, and runs `server.ts` without a build step.
2. **One instance per location, and which events it sees.**
   - One instance runs per location: `status` reports a different `instance.location` for each of two directories, and the log shows a load at each location's boot.
   - Unlike ARCHITECTURE §4.2 and the reading of `core/src/bus.ts`, **every instance's `ctx.event.subscribe()` carries every location's events**. A turn in the second location appeared in the first instance's `other` counters, including `permission.asked`. `local()` filters only for a subscriber that has a Location service, and the Promise adapter subscribes from the plugin's own runtime context.
   - This broke the first live run. The first location's instance claimed the second location's `permission.asked`, its `ctx.permission.get` looked in its own location's permission service, found nothing, and dropped the push. Each instance now acts only on events of its own location (decision 3).
   - Also unlike the reading of the source, some session events reach the stream **without a location**: `session.execution.started`, `session.execution.succeeded` and `session.usage.updated` in a live turn. The bus routes them by session in a side table (`core/src/bus.ts`, `prepareRoutes`) and does not add the location to the public event. The plugin ignored events without a location, so `finished` and `failed` pushes, the re-check after Stop and the Live Activity's start and end never happened; the unit tests' fake host had always supplied a location. The plugin now places such an event by its session's location (decision 3), and the live checks prove each of those paths.
3. **`ctx.storage` is global.** A device registered through one location is listed by the other's instance. Storage is the `kv` table of the sandbox's `opencode.db`, under `plugin:006d006f00620069006c00650070007500730068:` (each UTF-16 unit of `mobilepush` as four hex digits, `core/src/plugin/host.ts`). The live check read the table: `key/server`, `device/…`, `delivery/…`, `activity/…` and `sent/…`, all under that prefix.
4. **`session.moved`.** It reached both instances; its `location` was the old one, and its `data` had `sessionID`, `location`, `projectID` and `subpath`. Since every event reaches every instance anyway, a duplicate is avoided by acting only on the event's own location; the `sent/<eventID>` claim also stops a repeated delivery, including to a second process sharing the store. The plugin pushes nothing for `session.moved`, and the live check confirms no push followed it.
5. **Plugin API shapes** (review item 5):
   - `ctx.permission.get({sessionID, requestID})` and `ctx.session.get({sessionID})` take these inputs. They answer with the endpoint's `data` member already unwrapped: the Promise adapter returns the `data` property of a `{data}` success schema (`packages/plugin/src/promise/adapter.ts`, `compileEndpoint`), so `title` and `parentID` are read directly. A wrong shape would have dropped every push (the grace check) or every root; both proofs passed.
   - Events arrive as `{id, type, created, data, location: {directory, workspaceID?}}`.
   - `rpc.register` accepts `{}` JSON Schemas.
   - Calls are `POST /api/rpc/mobilepush/<method>?location[directory]=…` with `{"input": …}`, answering `{"output": …}`. `input` is required even for a method without one: without it opencode answers 400 `rpc.invalid_input`, "Expected JSON value", although research/01 §5.15 lists it as optional.
   - Declared errors come back as 400 `{"_tag": "RpcError", "type", "message", "data"}`.
6. **"Session not found" keeps its tag.** Effect 4.0.1's `runPromise` rejects with the squashed error itself. A throwaway probe plugin, loaded only in a sandbox, caught `ctx.session.get`'s rejection for an unknown `ses_…` ID: `_tag` and `name` were `"Session.NotFoundError"`, its own keys `_tag` and `sessionID`, and its message empty. So matching the message would never have worked. An ID without the `ses` prefix rejects with `_tag: "SchemaError"` and the message `Expected a string starting with "ses"`. Live, `registerActivity` answered `not_found` with `{field: "sessionID", retryable: false}` for both. No other mapping was needed.
7. **A real permission request is pushed, sealed and correct.** The live check opened the envelope with the device key and compared every payload field. That includes the session title read through `ctx.session.get`, the risk tier and a digest equal to that of a fresh `GET`. A wrong input shape would have dropped the push silently.

## Design and source decisions

Each item is a difference from ARCHITECTURE.md §4 (or §1.1), or a choice it leaves open. Where the source and ARCHITECTURE disagree, the source wins.

1. **The APNs category is always `OPEN_ONLY`** (the orchestrator's decision, review 1). ARCHITECTURE §4.3 asks for "a category per kind". The relay sends `OPEN_ONLY` for every kind, and only the Notification Service Extension sets the kind's category, after it has opened, checked and classified the envelope. An alert shown without the extension, or after it fails, offers no action. `server/contracts/README.md`, "Categories and actions fail closed", states the rules.
2. **A subagent's pending request sets the root's Live Activity to needs-input** after the grace period (the orchestrator's ruling, review 2): the run is blocked on the user either way. A subagent's other events only advance the step count and the tool category, so a subagent starting or finishing never restarts or ends the root's activity.
3. **Each instance acts only on events of its own location.** This replaces ARCHITECTURE §4.2's "each session event reaches exactly one instance", which is not true for 2.1.3 (M0 answer 2). Every instance receives every event, counts it, and acts only when the event's location is its own. For a session event published without a location, the location is the session's: learned from its other events (`session.created`, inbox and step events, a move's destination), or read with `ctx.session.get`, which returns it. That location's `ctx.permission.get` finds the request, each event is handled once, and Live Activity steps are counted once. One exception keeps alerts from going stale: when no instance of the event's location is running in the process, any instance settles that location's replies and its `location.shutdown`. Other events without a location are global, and ignored.
4. **No scope flag** for `opencode plugin add`: it always installs server plugins globally (M0 answer 1). Until the package is on npm, the documented install is a configuration entry naming `server/plugin`.
5. **Requests the server drops without a reply are replaced too.** Stop and session deletion interrupt a waiting permission request, and opencode then removes it without `permission.replied` (`core/src/permission.ts`, the `ensuring` in `assert`).
   - On `session.execution.interrupted` or `session.deleted`, the plugin asks again with `ctx.permission.get`, at once and, for requests still held, 2 s later. It replaces a pushed request it no longer finds as `cancelled`. Live, Stop on a pushed request published no `permission.replied`, and the device got exactly one `cancelled` replacement.
   - A closing location rejects each pending request before it publishes `location.shutdown` (`core/src/location-lifecycle.ts`).
   - Forms need no check, since opencode cancels them with `form.cancelled`.
6. **Replacements are serialised per request** (review 3, E1).
   - An inferred `cancelled` waits a 1 s reply window, so a reply still on its way (a desk answer racing Stop, or the shutdown rejections) is sent instead.
   - Replacements for one request run one at a time and read the latest reply when they send. A device gets a second replacement only when the reply changed after the first went out.
   - A `cancelled` still waiting when the plugin stops is sent at once.
   - Replacements, and test pushes, ignore presence: an actionable alert must not outlive its request. ARCHITECTURE only says pushes to an open app are skipped.
7. **The family fallback.** When the family cannot be read (opencode has no such session, or `ctx.session.get` fails twice), a request or failure is pushed under its own session, because a missed approval is worse than a misplaced thread; `finished` is skipped. `registerActivity` answers `not_found` (`retryable: false`) for a missing session or parent and `unavailable` (`retryable: true`) for a failed read. ARCHITECTURE lists no errors.
8. **`finished` needs a step.** opencode applies a move through the session's inbox as an execution with no model call (`session.execution.started`, `session.inbox.delivered`, `session.moved`, `session.execution.succeeded`, seen live), which the plugin first pushed as "A session finished". It now pushes `finished` only for a run that took a `session.step.started`, or one that began before the plugin was running. Failures are always pushed.
9. **The question digest** covers `{formID, sessionID, title, fields: [{key, type, title, description, options: [{value, label}]}]}`. ARCHITECTURE defines only the permission digest, `{requestID, sessionID, action, resources, save}`, where an absent or `null` `save` is `[]`.
10. **JCS, and the lone surrogate.** The contract only hashes integers within ±(2⁵³ − 1), so Swift needs no ECMAScript number formatting, and both languages refuse anything beyond that range alike (`Number.isSafeInteger`; a range check in Swift, since `abs(Int64.min)` would trap). A lone surrogate, which JSON can carry but no Swift string can hold, never produces a disagreement: TypeScript replaces it with U+FFFD before hashing, where strict RFC 8785 would reject it, and Swift's `JSONDecoder` refuses the whole document, so the app never reads such a request and computes no digest. It fails closed.
11. **The shared risk rules differ from M3a only where they must.**
    - Force-push with options before `push` is high: `git -C repo push --force` and `git -c core.sshCommand=ssh push origin +HEAD:main`. M3a's `git\s+push` missed both.
    - `external_directory` is an explicit high rule; it was already high as an unknown action.
    - Word boundaries are ASCII. ICU counts non-ASCII letters as word characters, so M3a's `\brm\b` missed `ärm`.
    - Whitespace is the ECMAScript set, and `{line}` excludes the Unicode line separators.
    - U+0085 is in `{ws}`: ICU's `\s` matched it on iOS, ECMAScript's does not, and the first version of the shared set left it out.
    - Joined resources over 8,192 UTF-16 code units are `high` with rule `too-long` before any pattern runs, and the force-push pattern's quantified parts cannot overlap (a `{ws}+{tok}+` group; lookaheads keep the first group from consuming `push` and both groups from running past a later `git`, so one `git` start costs a bounded scan; `download-to-pipe` likewise never scans past a later `curl` or `wget`). The first version, `{cmd}*{ws}push{cmd}*{ws}…`, backtracked catastrophically: about 12 s on an 11 KB command with many `git x push` tokens, on the main actor twice per render of the permission sheet. Timing tests in both languages run every rule on adversarial inputs at the cap.
    - The approval snapshots' requests (`edit` → elevated, `git reset --hard` → high) classify as before.
12. **Payload limits and truncation**: server reference 128 code points, title 100, project 60, action 64, summary 300, at most 8 options of 40. Display text is cut by code points with an ellipsis inside the limit; identifiers are never cut. Padding is ISO/IEC 7816-4 to 512, 1,024 or 2,048 bytes; the ciphertext is at most 2,064 bytes, 2,752 base64url characters.
13. **Relay limits.** Each limited key is its own `RateLimiter` Durable Object, with fixed windows: 30 alerts a minute and 500 a day per device, as ARCHITECTURE says. Added: 30 Live Activity updates a minute and 2,000 a day per device, and 20 registrations an hour per IP. ARCHITECTURE says one Durable Object per device.
    - One `ApnsTokenCache` Durable Object mints the provider token, so every isolate shares one token for 50 minutes.
    - `POST /v1/push` checks the envelope and forwards only its six fields. An expired envelope is `rejected` without contacting APNs.
    - `TRUST_PROXY` (`fly` or `forwarded`) chooses the client address on Node.
14. **Relay logs** are one JSON line per event with only `event`, `route`, `kind`, `result`, `status` and `count`. `wrangler.toml` keeps Workers Logs and turns off invocation logs and traces, which record URLs (with IDs) and client IPs.
15. **App Attest** is a disabled hook: `APP_ATTEST=required` answers 501 until M9 implements the check.
16. **OCPushCore depends on OCModels directly**, for `PermissionRequest` and `FormInfo`. ARCHITECTURE §1.1 lists OCFoundation and OCSecurity, and OCSecurity already depended on OCModels. FeatureApprovals now imports OCPushCore for `PermissionRisk`; feature targets may import it.
17. **Push keys**: Keychain service `app.opencode.push-keys`, accounts `server.<uuid>` and `key.<kid>`. A `kid` is 16 random bytes in base64url (22 characters). Concurrent `key(for:)` calls for one server share one creation through an in-flight task, so no key is orphaned, and `pin` fails for a server without a key instead of creating one. M5b passes the App Group's access group.
18. **Where the plugin's private key lives**: in `ctx.storage`, which is the `kv` table of `opencode.db` in opencode's data directory. It is not in the project, the configuration or the logs. No HTTP route reads that store, the RPC methods return only the public key, and another plugin's `ctx.storage` is confined to its own namespace. Anyone who can read the server's files or run commands on it can still read it; such a client already controls the machine.

## Placeholder names and where they live

Each is one constant; the copies are byte-for-byte checked.

| Placeholder | The constant | Also touched by a rename |
| --- | --- | --- |
| npm package `@opencode-ios/opencode-mobile-push` | `server/contracts/constants.json` `names.package` | `server/plugin/package.json` `name` (a test checks it equals the constant) and its regenerated `package-lock.json`; the copies made by `npm run sync-contracts` (`server/plugin/contracts/constants.json`) and `node Tools/sync-push-contracts.mjs` (`OCPushCore/Resources/Contracts/constants.json`); the install commands in `server/plugin/README.md` |
| Plugin and RPC ID `mobilepush` | `names.plugin` and `names.rpc` | the same two copies; the storage namespace derives from it (existing devices would need registering again); the RPC route in `server/plugin/README.md` |
| Relay URL `https://relay.example.invalid` | `relay.defaultURL` | the same two copies; step 8 of `server/relay/README.md`, "Deploying" |
| Generic alert strings | `kinds.<kind>.alert` | the same two copies; nothing else (the relay and the vectors read the constant) |
| Relay name `opencode-push-relay` and its D1 database | `server/relay/wrangler.toml` `name` and `database_name` | the deploy steps in `server/relay/README.md`; `Tools/push-e2e/index.mjs` (the local migration) |
| Apple and Cloudflare placeholders `TEAMID0000`, `KEYID00000`, `com.example.opencode`, the all-zero `database_id` | `server/relay/wrangler.toml` | none |
| Keychain service `app.opencode.push-keys` | `OCSecurity/PushKeyStore.swift` | none |

## Isolation

Only Tools/opencode-sandbox launched opencode: the servers, and `opencode plugin add` through `sandboxedCLI`. The CLI runs under the same `sandbox-exec` profile and denied reads as the server, with its own enforcement receipt. The plugin was loaded only through the sandbox's configuration, or installed into the sandbox's own configuration and cache. Nothing reached the owner's opencode installation, configuration, plugins, data or running service. The d0732ea source was only read.

Every audit from this phase verified enforcement for every launch and recorded zero failures and zero observations. That covers the final contract after the review (`contract-1792794497742`, five launches) and its end-to-end (`push-e2e-1792794711652`), the contract runs on 2.1.3 and 2.1.2 for the mock fix (`contract-1792692082898`, `contract-1792692272425`), the earlier full pass (`contract-1792677323215`, `push-e2e-1792677621190`) and the standalone plugin checks (`push-plugin-1792677074574`, three launches including the CLI). It also covers the debugging probes run through the sandbox (`push-debug-…`, `locations-debug-…`, `move-debug-…`, `title-debug-…`, `title-capture-…`, `tag-probe-…`).

One audit failed by design: `push-plugin-1792675892709`. The `plugin add` CLI and the server launched after it shared the run root's enforcement receipt, which the bootstrap creates exclusively, so the server's launch could not verify. The audit found no file change. The CLI now writes its receipt in its own directory.

The throwaway debugging scripts and the probe plugin stayed in the session's scratch directory, outside the repository. The UI smoke audits verified enforcement for every launch with zero failures; their warnings are the owner's own `opencode serve --service` (PID 32480) and the owner's own opencode use writing to the owner's data, cache and configuration directories during the runs, listed per run under "UI smoke runs". The brief's hourly :52:57 writer was not observed in these runs; the writes came at other times.

The relay ran under `wrangler dev` in `server/relay`, with its D1 and Durable Object state, logs and env file in `.build/push-e2e/<run>/`. Telemetry was off (`WRANGLER_SEND_METRICS=false`), Cloudflare credentials were removed from its environment, and the env file with the run's throwaway APNs test key was deleted at the end. Its APNs requests went only to the mock on 127.0.0.1.

**wrangler touched the account's own wrangler state** (found in review). The first end-to-end runs inherited the real `HOME`, and wrangler keeps its global configuration under `~/Library/Preferences/.wrangler` on macOS. `metrics.json` there was modified at 09:34:34 local time on 2026-10-22, when the first `wrangler dev` recorded `bannerLastShown: "4.148.0"` after printing its telemetry banner, and an empty `registry/` directory (wrangler's dev registry) was created at 09:34:35 and last modified at 10:01:33. `logs/` was untouched since May, and `~/.wrangler` does not exist. No metrics were sent: every invocation had `WRANGLER_SEND_METRICS=false`, which wrangler 4.148 reads before the saved preference (`getMetricsConfig`), and its dispatcher returns before any request when metrics are disabled. `metrics.json`'s `bannerLastShown` and the empty `registry/` were the only writes. Nothing in that folder was modified or deleted afterwards; the orchestrator reported it to the owner. The fix: every wrangler and workerd run from this repository (`npm test` and `npm run dev` in `server/relay`, and the end-to-end) goes through `server/relay/scripts/isolated.mjs`, which points `HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME` and `WRANGLER_LOG_PATH` inside the package's `.wrangler/` or the run's directory, turns telemetry off, hides the banner and drops Cloudflare credentials. A guard snapshots the mtimes of `~/.wrangler` and `~/Library/Preferences/.wrangler` before and after each relay test run and each end-to-end, and fails on any change; the CI workflows inherit it through the npm scripts.

Xcode 27.1 is installed; 27.0 cannot be run here. Swift 6, the 26.4 deployment target and the existing settings are unchanged, with no 27.1-only syntax or API.

## Proposed documentation updates

### ARCHITECTURE.md

- §4.2, installation and scope: replace "the exact scope flag is to be verified in M0" with `opencode plugin add <npm or Git specifier>`, no scope flag, always the global configuration; a Git specifier needs the package at the repository's root; a directory in `plugins` loads in place.
- §4.2, locations: replace "`ctx.event.subscribe()` only delivers events for that instance's location … so each session event reaches exactly one instance" with: every instance receives every location's events; the plugin acts on an event only in the instance of its location (a settling event also elsewhere when that location has no running instance); a session event without a location, such as `session.execution.*`, belongs to its session's location; `sent/<eventID>` stops repeated deliveries.
- §4.2, triggers: add the `cancelled` replacement for a pushed permission request that Stop, deletion or a closing location drops without `permission.replied` (re-check with `ctx.permission.get`, a 1 s reply window, one serialised replacement per request), that replacements ignore presence, and that `finished` needs a run that took a step (a move is applied as a step-less execution).
- §4.2, RPC: add `registerActivity`'s `not_found` and `unavailable` errors, the error body (`RpcError`, 400) and the required `input`.
- §4.2, payload: add the question digest (decision 9), `freeText`, `reply` and `options`, and point at `server/contracts/README.md` for the exact definitions.
- §4.3: "a category per kind" becomes "category `OPEN_ONLY` for every kind; the NSE sets the kind's category after opening the envelope". "One Durable Object per device" becomes one `RateLimiter` per limited key plus the `ApnsTokenCache`; add the Live Activity and registration limits.
- §4.5 and §4.6, the action handler rules to carry into M5b: a notification action with no `shown/<requestID>.json` behaves as Open only; the handler classifies the re-read request with the shared rules and never trusts the payload's risk tier.
- §1.1: OCPushCore depends on OCFoundation, OCModels and OCSecurity.

### docs/design.md

- Line 60, M3a approvals: the risk tier now comes from `OCPushCore/PermissionRisk.swift`, driven by the shared `risk-rules.json`, not `OCModels/PermissionRisk.swift`, which no longer exists.

### research/01-opencode-server-api.md

- §5.15: `input` is required (`{}` for a method without input), and a declared plugin error is `{"_tag": "RpcError", "type", "message", "data"}` with status 400.
- Plugins: in 2.1.3 a Promise plugin's `ctx.event.subscribe()` carries every location's events; `ctx.session.get` and `ctx.permission.get` return the unwrapped `data`; a missing session rejects with `_tag: "Session.NotFoundError"`, a malformed ID with `_tag: "SchemaError"`; `ctx.storage` is the `kv` table under `plugin:<hex>:`.
- Events: `session.execution.*` and `session.usage.updated` reach the stream without a `location` (the bus routes them by session); a closing location publishes `permission.replied` (`reject`) for each pending request and `form.cancelled` for each form before `location.shutdown`; `session.moved` carries the old location.
- Auxiliary model calls: 2.1.3's title prompt begins "You name conversations so the user can find them later".

## Changed files

Paths are from the repository root.

- **New, server (MIT):**
  - `server/.gitignore`.
  - `server/contracts/`:
    - `LICENSE`, `README.md`, `package.json`, `package-lock.json`, `tsconfig.json`;
    - `constants.json`, `risk-rules.json`, `schema/{envelope,payload,activity-state}.schema.json`;
    - `src/{base64url,constants,digest,envelope-format,envelope,hpke,index,jcs,padding,payload,risk,text}.ts`, `scripts/generate-vectors.ts`;
    - `vectors/{jcs,digest,padding,risk,payload,envelope,rfc9180-a23}.json`;
    - `test/{rfc9180,risk-rules,schema,units,vectors}.test.ts`.
  - `server/plugin/`:
    - `LICENSE`, `README.md`, `package.json`, `package-lock.json`, `tsconfig.json`;
    - `server.ts`, `src/{activities,hashing,host,keys,payloads,plugin,registry,relay,rpc,service,sessions,shared}.ts`, `scripts/sync-contracts.ts`;
    - `contracts/`, the synced copy of the contracts' JSON files and `src/`;
    - `test/{fakes.ts,service.test.ts,rpc.test.ts,contracts-copy.test.ts}`.
  - `server/relay/`:
    - `LICENSE`, `README.md`, `package.json`, `package-lock.json`, `tsconfig.json`, `tsconfig.node.json`, `wrangler.toml`, `vitest.{workers,node}.config.ts`;
    - `scripts/isolated.mjs` (wrangler and workerd confined to the package, with the guard on the account's wrangler state);
    - `migrations/0001_init.sql`;
    - `src/{app,activity-state,config,crypto,limiter,log,node,node-server,sql-d1,sql-sqlite,store,validation,worker}.ts`, `src/apns/{delivery,fetch-sender,http2-sender,request,token}.ts`;
    - `test/support/{fixture,mock-apns,suite}.ts`, `test/workers/{global-setup,setup,relay.test}.ts`, `test/node/{relay,units,entry}.test.ts`.
- **New, Swift:**
  - `Packages/OpencodeKit/Sources/OCPushCore/{Base64URL,CanonicalJSON,PermissionRisk,PushContract,PushDigest,PushEnvelope,PushPadding,PushPayload}.swift` and `Resources/Contracts/{constants,risk-rules}.json`;
  - `Packages/OpencodeKit/Sources/OCSecurity/PushKeyStore.swift`;
  - `Packages/OpencodeKit/Tests/OCPushCoreTests/{VectorTests,PushCoreTests,PushEndToEndTests}.swift` and `Tests/OCSecurityTests/PushKeyStoreTests.swift`.
- **New, tools, CI and docs:** `Tools/sync-push-contracts.mjs`, `Tools/push-e2e/{support,plugin-checks,index}.mjs`, `.github/workflows/{plugin,relay}.yml`, `docs/m5a-audit.md`.
- **Changed:**
  - `Packages/OpencodeKit/Package.swift`: OCPushCore depends on OCModels and copies its contract resources; the OCPushCoreTests target; FeatureApprovals depends on OCPushCore.
  - `Sources/FeatureApprovals/PermissionSheet.swift` and `Sources/OCSync/ApprovalActions.swift`: import OCPushCore.
  - `Tools/contract/index.mjs`: runs the plugin checks.
  - `Tools/mock-llm/{scenarios.mjs,server.test.mjs}`: the 2.1.3 title prompt, committed ahead of the rest as 653be30 (`fix(mock-llm): recognise the opencode 2.1.3 title prompt`).
  - `Tools/README.md`, `.github/workflows/contract.yml`, `README.md`, `THIRD_PARTY_NOTICES.md` and `docs/roadmap.md`.
- **Deleted:** `Packages/OpencodeKit/Sources/OCModels/PermissionRisk.swift` (moved to OCPushCore) and `Packages/OpencodeKit/Sources/OCPushCore/Placeholder.swift`.

SPEC.md, ARCHITECTURE.md, research/, docs/design.md, AGENTS.md and CLAUDE.md are unchanged.
