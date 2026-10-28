# Development tools

The fixture and contract tools require Node 26 and npm, plus Git and the
standard macOS process utilities. Run commands from the repository root. No
global packages, provider keys, or real model calls are needed. Design capture
installs its pinned Playwright dependency and browser locally under `.build`.

## Record fixtures

```sh
node --test Tools/mock-llm/*.test.mjs Tools/opencode-sandbox/*.test.mjs Tools/fixture-recorder/*.test.mjs Tools/ui-smoke/*.test.mjs Tools/contract/*.test.mjs
node Tools/fixture-recorder/index.mjs
# Reproduce one release:
node Tools/fixture-recorder/index.mjs --version 2.0.32
# Debug selected scenarios without replacing the checked-in recording:
node Tools/fixture-recorder/index.mjs --version 2.0.32 --scenario permission-allow --output .build/fixture-debug
```

The default recorder queries npm once, selects the newest stable **2.x** release,
then pins that exact version for the whole recording. `--version` accepts an
exact stable 2.x version. It runs all 20 scenarios (a–q, with separate interrupt
and retry variants), including the fixed `opencode-ai@1.19.3` detection probe.
Fixtures are published to `Fixtures/v2/<version>/` only after every selected
scenario passes. Use `--output` for partial recordings; `manifest.json` lists
omitted scenarios, consumed model calls, script hashes, and file hashes. Each session
scenario includes start/end snapshots of session info, every message page, inbox,
permissions and forms. Pairing, PTY and V1 detection have no session snapshot.

Published fixtures say `/sandbox` wherever the server reported the sandbox run
root (`.build/opencode-sandbox/<version>/<run-id>`), in plain, JSON-escaped and
URL-encoded form, so they never reveal where the checkout lives. The file hashes
in `manifest.json` cover the rewritten bytes. `Tools/fixture-recorder/home-paths.test.mjs`
fails if a tracked file, or an untracked file that is not ignored, contains a home
directory path, and CI runs it on every push. Example paths in docs and screenshots
use `/Users/Shared`.

## Live contracts

```sh
node Tools/contract/index.mjs
node Tools/contract/index.mjs --version 2.0.32
```

This starts the real npm V2 server and the V1 detection server, checks 401/200
authentication, single-use pairing and token authentication, the first SSE event
and a heartbeat within 20 seconds, a prompt and title round trip, PTY echo/resize/
cursor resume/deletion, V1 health detection, and the push plugin live checks (see
"Push (M5a)"). Failures exit nonzero. This is
separate from ordinary `swift test`, which reads checked-in files and skips live cases.

The contract also runs `OCNetworkingLiveTests` through `swift test --filter
OCNetworkingLiveTests`. It supplies `OPENCODE_LIVE_URL`, `OPENCODE_LIVE_PASSWORD`,
`OPENCODE_LIVE_PID` (the authenticated `/api/info.pid`), `OPENCODE_LIVE_VERSION`,
`OPENCODE_LIVE_V1_URL`, and `OPENCODE_LIVE_V1_PASSWORD` in the child environment.
Do not point these variables at an installed or personal server. The live test
verifies Swift probe/clock correction, single-use pairing and token auth,
URLSession delegate delivery of the small first SSE frame within 3 seconds,
40 seconds of heartbeat health, and recovery after SIGSTOP for 60 seconds then
SIGCONT. It prints the measured first-frame latency and connection transitions.
The harness owns cleanup and the isolation audit throughout. Expect roughly two
to three minutes beyond the build. No source checkout is built or executed.

The live sync test also compares the store projection to REST snapshots after a
normal turn and after dropping/reconnecting the stream mid-turn. It supplies
`OPENCODE_LIVE_MOCK_URL` and `OPENCODE_LIVE_DIRECTORY` to that test.

Offline networking tests use the pinned swift-clocks 1.1.1 `TestClock`, fake
transports, and every recorded version under `Fixtures/v2/`. Startup 503 cases
are source-derived mutations of the ready-server fixture because those captures
contain no 503 response. The optional Keychain smoke test requires
`OPENCODE_TEST_KEYCHAIN=1`; unavailable Keychains are skipped.

`.github/workflows/contract.yml` runs manually and nightly at 07:23 UTC on
`xcode-27` with Node 26. It resolves V2 once for both the contract and recorder,
and uploads refreshed fixtures and isolation audits as artifacts. It does not
commit recordings. The minimum-supported V2 matrix described in ARCHITECTURE §6 remains future
work; the networking and read-projection suites run against latest/pinned V2,
with V1 detection checked separately.

## Push (M5a)

Install the three push packages first: `npm ci` in `server/contracts`, `server/plugin` and
`server/relay`. Nothing here creates an account, deploys, or contacts APNs.

```sh
node Tools/sync-push-contracts.mjs --check   # OCPushCore's copies of constants.json and risk-rules.json
node Tools/push-e2e/plugin-checks.mjs        # the plugin live checks; Tools/contract/index.mjs runs them too
node Tools/push-e2e/index.mjs                # the local end-to-end
```

`plugin-checks.mjs` starts a sandbox whose configuration lists this checkout's `server/plugin`, and
a loopback relay that records every call. With the scripted model it proves: the plugin loads and
answers its RPC on two locations; storage is global and namespaced in opencode's `kv` table; a real
permission request is pushed after the grace period, sealed, with the right fields and the digest
of a fresh `GET`; the desktop answer replaces it; an answer inside the grace period and a valid
presence heartbeat suppress it; a root's success and a failure are pushed (opencode publishes both
without a location); a subagent's request carries its root, and its success is not pushed; Stop
replaces a pushed request once; a Live Activity follows a run; a missing session answers
`not_found`; a request in a second location is pushed once although every instance receives every
location's events; `session.moved` sends nothing. A second sandbox installs the plugin with
`opencode plugin add git+file://…` (a Git repository of the package made inside the run directory)
and loads it from the global configuration that command writes. The CLI runs under the same
`sandbox-exec` profile, with its own enforcement receipt. `push-plugin.json` in the audit directory
records the answers.

`index.mjs` adds the relay in the Workers local runtime (`wrangler dev --local`, with local D1 after
`wrangler d1 migrations apply --local`, and both Durable Objects) and the relay's mock APNs server,
with a test ES256 key made for the run. It registers a fake phone at the relay and through the
plugin, drives a real permission request and a real question, and checks the generic alert, the
headers and the envelope at the mock APNs, opens the envelopes with the TypeScript contracts and with
`OCPushCore` (`swift test --filter pushesFromTheEndToEndRunOpenInSwift`, given the capture), refuses
tampered copies, and covers the replacement, presence, an answer inside the grace period, the
relay's rate limit (test mode, 8 alerts a minute) and the `gone` path. It prints the time from the
request's event to the mock APNs. Results, the capture and the Swift log are under
`.build/push-e2e/<run>/`; the run's env file with the test key is deleted at the end. wrangler runs
with its `HOME`, XDG and log directories inside the run (`server/relay/scripts/isolated.mjs`),
telemetry off and no Cloudflare credentials, and the run fails if the account's own wrangler state
changed.

## App push in the simulator (M5b)

```sh
node Tools/push-e2e/index.mjs --simulator # M5a checks, then the app bridge run
node Tools/push-e2e/simulator.mjs        # only the app bridge run
```

The bridge run uses the existing booted **iPhone 17 Pro**, a sandbox with the plugin,
M5a's Node relay adapter and its HTTP/2 mock APNs. Each accepted payload is saved
unchanged and passed to `xcrun simctl push`. It never creates or reconfigures a
simulator. The full `node Tools/ui-smoke/index.mjs` run includes this check after
its normal iPhone and iPad flows, with all simulator-dependent commands serialized.

The DEBUG app driver requires a `ui-` test identity and a loopback control URL.
It substitutes a synthetic APNs token and a loopback relay URL; these overrides
are absent from Release. It inspects the untouched delivered notification first.
A DEBUG NSE invocation marker and non-sensitive log distinguish an extension
launch from an Open-only decryption failure. If necessary, the driver invokes
OCPushCore in the app and schedules the resulting local notification. This bypasses
system NSE launch, while retaining HPKE, the shared Keychain, the protected store
and the category builder. XCUITest attempts the notification action; the fallback
calls the production action handler and bypasses SpringBoard gestures and device
authentication. The report says which path ran.

The changed-request case uses a loopback forwarding proxy: V2 pending requests are
immutable, so it changes the resources in the action's fresh GET. No reply may be
sent. The harness waits for each session to become idle before changing the mock
model's script. Approval timing ends only when the sandbox file has actually
changed. APNs collapse headers are recorded separately because `simctl push` takes
only a payload; local rendered replacements use a stable request identifier.

Evidence is under `.build/push-e2e/ui-push-<run>/`: the live `test.log`, XCTest result
bundle, raw `.apns` files and bridge results, app reports, NSE log and activity probe.
The matching isolation audit is under `.build/opencode-sandbox/audits/`.

What the simulator cannot show, so only a signed build on a device can: `simctl push`
delivers an alert payload but does not launch the Notification Service Extension (the
decrypted alert comes from the DEBUG renderer above), it cannot deliver an ActivityKit
update (`NSPOSIXErrorDomain 14`), and it issues no APNs device token (the driver
substitutes one; Live Activity push tokens do arrive and are registered with the local
relay and plugin). Real APNs delivery, lock-screen latency, device-owner authentication
for Allow once and remote Live Activity updates need the owner's team.

## Isolation and lifecycle

`opencode-sandbox/index.mjs` launches only
`npx -y @opencode/cli@<version> serve --hostname 127.0.0.1 --port <free-port>`
(or `npx -y opencode-ai@1.19.3 serve` for detection). It invokes npm's npx entry
point through the active Node executable. It never runs a preinstalled opencode
or anything from the reference checkout. Ports 49374 and 49375 are excluded.

Each run lives under `.build/opencode-sandbox/<version>/<run-id>/`. HOME, all XDG
roots/search paths, temp directories, Git config, npm config/prefix/cache,
opencode config/model-catalog/database paths and scratch project are sandboxed.
The npm download cache is shared **only within that sandbox version**. The child
environment is built from an allowlist, with a private PATH containing Node and
system utilities. Inherited credentials, config overrides, shell startup hooks,
SSH settings, telemetry exporters, and Node flags are not passed through.

The source at `d0732ea` establishes these controls:

- `packages/cli/src/server-process.ts`: foreground `serve` skips service
  registration, service config, and remote tunnels. No service/LaunchAgent
  commands are invoked. A random password is supplied on every launch.
- `packages/cli/src/services/updater.ts`: `OPENCODE_DISABLE_AUTOUPDATE=1`;
  V2 config also sets `update: "disable"`, V1 sets `autoupdate: false`.
- `packages/util/src/observability/otlp.ts`: absent OTEL exporter endpoint disables
  remote logging/tracing. The environment omits all inherited OTEL values and
  additionally sets `OTEL_SDK_DISABLED=true` and `DO_NOT_TRACK=1`.
- `packages/schema/src/config.ts`: `share: "disabled"`. V1 also gets
  `OPENCODE_DISABLE_SHARE=1`. Project/Claude config discovery, model fetches,
  watchers, LSP, formatters, and warming are disabled.
- Persistent PTY daemon execution is blocked by an `OPENCODE_PTY_BIN` path to a
  nonexistent sandbox file. Tests use ordinary `/api/pty`, which is owned by the
  foreground server, and explicitly delete each PTY. Inherited optional native
  library overrides are cleared; bundled assets resolve inside the npm sandbox.

On npm 12, only the selected opencode package is allowed to run its install-time
script, which installs its npm-distributed binary inside this sandbox. This is
a child-only setting, not a change to global npm configuration.

Every started subprocess has an owned process group. Cleanup sends TERM, then
KILL if needed, and verifies no group remains; it also tracks descendant groups
such as PTYs. This runs on success, failure, SIGINT, SIGTERM, and SIGHUP. Normal
server shutdown writes `cleanup.json` in the run directory. SIGKILL cannot be
handled. Keep the launcher in the foreground and stop it with Ctrl-C.

Every recorder/contract run saves before/after path and nanosecond-mtime listings
(depth two) for the user's four opencode directories and `~/Library/LaunchAgents`
under `.build/opencode-sandbox/audits/`. Changes attributed to a unique external
writer are warnings; sandbox writes fail. Unattributed changes are warnings only after every sandbox launch has verified enforcement. The tool
never restores or edits the user's files. macOS `sandbox-exec` additionally
denies writes to those five roots; this is not a general-purpose security
boundary for arbitrary untrusted tool scripts.

For manual API work:

```sh
node Tools/opencode-sandbox/index.mjs --version 2.0.32
# Detection only:
node Tools/opencode-sandbox/index.mjs --v1
```

The manual launcher prints the URL, per-run password, mock URL and scratch path
as a one-line handoff. Recorder/contract logs and artifacts redact credentials.
The launcher stays in the foreground until interrupted, then cleans up.

## Scripted model

`mock-llm/server.mjs` serves the provider path confirmed in
`packages/ai/src/providers/openai-compatible.ts` and
`packages/ai/src/protocols/openai-compatible-chat.ts`: **POST
`/v1/chat/completions`**, using OpenAI Chat SSE (not Responses). It sends role,
text, `reasoning_content`, indexed tool-call argument fragments, finish reason,
usage-only chunks and `[DONE]`. It also supports non-streamed chat completions.
Usage includes input/output/total, cached input and reasoning tokens.

```sh
node Tools/mock-llm/server.mjs
# Use its printed loopback URL:
curl -X POST http://127.0.0.1:PORT/admin/scenario \
  -H 'Content-Type: application/json' -d '{"name":"read-glob-grep"}'
curl http://127.0.0.1:PORT/admin/state
```

`scenarios.mjs` contains ordered primary calls. Each call accepts `deltas`
(`text`, `reasoning`, optional `delayMs`), `tools` (`name`, `arguments` or explicit
`argumentDeltas`), `finishReason`, `usage`, `delayMs`, or an `error` (`status`,
`message`, optional `retryAfter`). The admin selector also accepts
`{name, script: {calls: [...]}}`. Active calls prevent scenario replacement.
Exhausting a script is an error, never an implicit successful response.
Title, summary and compaction requests are classified from the source's prompt
templates and answered on separate deterministic lanes. Admin state lists the
consumed script indexes, kind, model, streaming flag, completion/cancellation/
error status, available tools, remaining calls and unexpected requests.

The V2 tool is named **`subagent`**, not `task`; the fixture uses the source's
name. It creates and verifies a real child session through the scripted model.

## The iPad workspace flow

```sh
node Tools/ui-smoke/index.mjs --workspace-only                # every workspace test on the iPad
node Tools/ui-smoke/index.mjs --workspace-test testTwoWindows # one of them
```

The full run's iPad stage includes `WorkspaceSmokeTests`, which the iPhone stage skips. It
presses these menu shortcuts as synthesized hardware keys: ⌘1, ⌘2, ⌥⌘↓, ⌥⌘↑, ⌥⇧⌘↓, ⌥⇧⌘↑
(with the composer focused), ⌘\, ⇧⌘R, ⌘N, ⌘K, ⌘., ⌘', ⇧⌘D, ⌘U, ⇧⌘A and ⇧⌘N; `ReviewSmokeTests`
presses ⌘F. ⌘3–⌘9 share ⌘1 and ⌘2's path and are not pressed, and ⌘↩ is not pressed because the
simulator does not deliver Return chords (see below). It drives the ⌘K switcher from the
keyboard, opens the next approval, shows two sessions in two windows (restoring both
after a relaunch), opens a third with ⇧⌘N, and drags a Files row onto the composer. Only under a
`ui-` test identity, the DEBUG app exposes a `windowInventory` element (every window's
sessions and the key window), a `commandTrace` element (commands counted where they are
dispatched, so a test proves that one key press ran one action), a `workspaceCommands`
element (the menu commands the menu bar enables). A fresh `--ui-testing-reset` launch asks
iPadOS to close windows an earlier test left open; the simulator keeps them in the app
switcher, so the tests check windows by the sessions they show. What the test saw of the windows is attached and copied next to the result bundle
as `finding-*`. The iPad simulator drops the key of the first chord after a launch, so each
flow first sends ⌘J, which no command owns; `testReviewNavigation` checks that first chord
itself. XCUITest on this simulator delivers no Return chord or Escape, neither to the menu bar
nor to a focused text view or field, so the composer flow runs Send from the switcher and the
switcher flow opens an entry with a typed newline; ⌘↩, Return and Escape in the editor and the
switcher are covered by unit tests instead. Deep links go through
`XCUIDevice.shared.system.open`, because `XCUIApplication.open` relaunches the app and would
drop the window that is not on screen.
The iPhone stage's `SwitcherSmokeTests` opens the switcher from Home's toolbar button and the
context sheet from the session header.

## Server UI smoke and snapshots (M1b)

```sh
xcodegen generate
node Tools/ui-smoke/index.mjs
# Optional exact V2 release, or just the live UI flows:
node Tools/ui-smoke/index.mjs --version 2.0.32 --skip-snapshots
```

The harness uses only `opencode-sandbox` and the scripted model, creates a fresh
single-use link with `POST /api/pair`, and runs `xcodebuild test` on iPhone 17 Pro
(iOS 26.5). `TEST_RUNNER_OPENCODE_UI_*` environment variables carry the sandbox
URLs, passwords and link into XCUITest. Only an isolated test identifier reaches
the app's launch environment; the tests type the connection inputs through the UI.
A full run first runs the unit and snapshot tests once (`Units.xcresult`, `units.log`), then
the UI tests. When UI tests fail, their stage runs the failed tests again together, up to
twice, on the same build (`xcodebuild test-without-building` with an `-only-testing:` for each,
into `Smoke-attempt-2.xcresult` and `test-attempt-2.log`, and so on); a test passes when any
attempt passes or ends in an expected failure. Before each retry the fault proxy's faults are
cleared and the no-Git review fixture loses the repository a failed attempt may have created;
other server state stays, so a retried test sees the sessions and messages its earlier attempt
left. UI stages pass `-test-timeouts-enabled YES`, so a test that hangs fails at its
`executionTimeAllowance` (600 seconds when it sets none) and is retried like any other failure.
A crash during a test is that test's failure and is retried. A failure that belongs to no
failed test (a test runner lost outside any test, a summary that disagrees with the result
tree, an unknown result) fails the stage without a retry. The tool
retries itself because Xcode's `-retry-tests-on-failure` does not:
since Xcode 26 a failure in an async test whose class sets `continueAfterFailure = false`
relaunches the test runner, which drops the retry (a known Xcode issue). A
regression still fails every attempt; a burst of load on a shared host no longer fails the
whole run. The large-diff scroll test logs its worst frame but never fails on it; its hitch
rate, first rows and memory checks still fail the test. Snapshot tests never retry, because a snapshot test records a
missing reference image and would pass on its next attempt; any stage that adds or changes a
file under a `__Snapshots__` folder fails and prints `RECORDED <file>`. A test that passed on
a later attempt prints `RETRIED <test> (attempt n of 3)`; one that failed every attempt prints
`FAILED <test> (3 of 3)` and fails the stage. `retried.json` next to the result bundles lists
both per stage. A test that passed on a later attempt contributes only that attempt's
screenshots, findings and measurements, such as the approval latency and the review scroll
metrics; if that attempt attached none, the stage's checks for them fail. The test's own
checks are not isolated the same way: a retried `testReviewAndFiles` can match the comment
message its failed attempt sent, because the session and the text are the same on every
attempt. The full run's last
stage, the simulator push tests (`Tools/push-e2e/simulator.mjs`), runs its one test once with no
retry; the snapshot check covers it too.
Debug builds use a separate JSON file and Keychain service for each test run.
Production storage is not reset. UI tests use XCTest because XCUITest requires it;
package and snapshot tests use Swift Testing.

It covers manual V2, pairing-link V2, wrong-password re-pairing, and the V1 upgrade
screen. The `.xcresult` and redacted log live under `.build/ui-smoke/`. Screenshots
are exported to `.build/screenshots/`, including onboarding, server list, both
connection forms, re-pairing, details, diagnostics, local network and update. A final
install and launch leaves the app on the booted simulator. Sandbox cleanup and
before/after isolation audits run even on failure.

`ServerSnapshots` compares 110 checked-in images: 44 connection-state images in
both appearances at accessibility size 5 and 402-/768-point widths, 60 full-screen
images across phone and iPad sizes, two component sheets, two expanded-Home sidebar images, and two native-toolbar regression images. The
snapshot library is pinned to 1.18.7. Run it independently with:

```sh
xcodebuild -project Opencode.xcodeproj -scheme Opencode \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .build/DerivedData -parallel-testing-enabled NO \
  -only-testing:ServerSnapshots test
```

Missing references are recorded and fail the first run. Review the PNGs under
`Packages/OpencodeKit/Tests/FeatureServersTests/__Snapshots__/` before re-running.
Ordinary `swift test` uses no network, runs the sync tests with fake connections
and virtual clocks, and skips live networking and iOS-only image comparisons.

## Design references (D1)

`node Tools/design-reference/index.mjs --version 2.0.32` seeds real V2 sessions using the fixture mock, signs into the UI served by that sandbox, and captures desktop, both iPad orientations, and iPhone in light/dark. Playwright and Chromium remain under `.build`; no installed browser profile or installed OpenCode is used. See `docs/design.md` for snapshot recording, import scripts, and `.build/design-compare/index.html` generation.

Every V1/V2 server, including npx, runs under macOS `sandbox-exec`. The profile denies `file-write*` in the real user's OpenCode config/data/state/cache directories and LaunchAgents, including resolved symlink destinations. Before starting npx, an in-sandbox bootstrap must fail to write a disposable canary covered by the same profile. A PID-, nonce- and profile-digest-bound receipt proves the check; restrictions inherit to all descendants. A missing/invalid receipt or successful canary write aborts the launch. Audits retain proof after process cleanup and fail if any launch lacks it.

Before/after snapshots still compare mtimes. `lsof` samples identify writable descriptors, process groups and change intervals. Changes attributed to sandbox processes always fail. With verified enforcement on every launch, unattributed writes are warnings naming the path and time; unique external writers are named too. OpenCode.app may independently modify models.json, storage/ and its databases. Missing enforcement, a failed denied-write check or an inspection failure still fails the run.
