# Evaluation of grapeot/opencode_ios_client for opencode-ios

*Written 2026-10-16. Evaluated commit `a4c5e51` on `master` (the merge of PR #214, pushed 2026-10-17 00:12 UTC). The repository was shallow-cloned read-only into `scratchpad/src/grapeot-ios`. Nothing was built, run, or opened in Xcode. Nothing in this repository was changed.*

All paths below are relative to the root of the cloned repository unless they start with `research/`, `ARCHITECTURE.md` or `SPEC.md`, which refer to our project.

---

## 1. Verdict in brief

**Do not fork it. Borrow a handful of self-contained pieces under MIT attribution, and use the rest as a source of UX ideas and regression cases.**

- **Protocol:** the app speaks only the V1 HTTP API. Its V2 plan exists only as a document. That plan converts V2 responses into V1-shaped models, and it depends on events that current V2 servers never deliver to clients. It also waits for two server features that V2 removed (todos) or does not have (archive writes).
- **Architecture:** a single `@Observable` `AppState` god object (5,637 lines with its extensions), one active server at a time, one in-memory transcript, UserDefaults persistence, and Swift 5 language mode. That conflicts with ARCHITECTURE.md at every layer that matters. Our M1a networking core is already more robust than theirs.
- **MVP gaps:** it has none of the things our MVP is built around: pairing, push, a persisted outbox, a diff viewer, syntax highlighting, a cross-server inbox, Live Activities or a terminal.
- **What it does well:** visionOS, an in-app SSH tunnel, voice, a careful IME-aware composer, link and path hygiene, model-output normalization, and a large Swift Testing suite. Its PR history is a valuable record of real-world race conditions.

**Worth borrowing:** the SSH tunnel (`Services/SSHTunnelManager.swift`, `Services/SSHKeyManager.swift`), the composer's IME logic (`Views/Chat/ChatComposerTextView.swift`), the link and path resolvers (`Utils/WorkspaceLinkResolver.swift`, `Utils/PathNormalizer.swift`), fence-aware cleanup of leaked `<think>` tags (`Views/Chat/MessageRowView.swift`), the activity-text debounce (`Controllers/ActivityTracker.swift`) and the simulator test-runner scripts (`scripts/lib_simulator.sh`).

---

## 2. Repository facts

| Item | Value |
|---|---|
| Repository | github.com/grapeot/opencode_ios_client, "Native iOS client for OpenCode. AI coding agent on your phone" |
| Stars / forks / watchers | 266 / 53 / 2 |
| License | MIT, "Copyright (c) 2026 grapeot". The LICENSE file was only added on 2026-08-26 (PR #157) |
| Created / last push | 2026-02-12 / 2026-10-17 00:12 UTC (very active: about 1 to 5 merged PRs a day in October) |
| Default branch | `master`. Other branches: `design/f2-session-orientation` (June 2026 session-list design work, 4 ahead and 258 behind) and `gh-pages` |
| Open issues | 2: #169 (V2 support) and #158 (questions about voice and Markdown) |
| Open PRs | 1: #8 "add dynamic model effort selection" by xiang-lee, opened 2026-03-11, idle since 2026-05-02 |
| Totals | 11 issues (9 closed); 203 PRs (193 merged); 677 commits on `master` |
| Releases | One GitHub release, `v1.0.0` (2026-07-31). Issue #169 cites TestFlight "V1.0 Build 27, 12 Sep 26"; PR #189 (2026-09-30) bumped to build 29 "for App Store upload" |
| Contributors | grapeot 671 commits, xiang-lee 4, jeromexlee 1, guyq1997 1. In practice a single maintainer who merges their own PRs |
| Languages (bytes) | Swift 2,166,012; Python 46,846; JavaScript 34,569; Shell 33,041; CSS 22,879; HTML 1,916 (repository about 22 MB, including screenshots under `outputs/`) |
| Distribution | The README links a public TestFlight (`testflight.apple.com/join/2cWrmPVq`, app name "OpenCode Remote"). No App Store listing was found: an iTunes lookup of bundle ID `com.grapeot.OpenCodeClient` (US storefront) returned 0 results on 2026-10-16, and a search for "OpenCode Remote" did not list it |
| Platforms | iOS/iPadOS 17.0+, native visionOS 26.0+, one target and one bundle ID |
| Sibling project | grapeot/opencode_android_client (Kotlin, MIT, 96★), also V1-only (a code search finds no `/api/event`) |

---

## 3. What the product is

The PRD (`docs/OpenCode_iOS_Client_PRD.md`, in Chinese) frames the app around **reviewing what the agent writes**, mainly Markdown documents, with code diffs as a secondary concern. The README lists chat with streaming, tool calls and reasoning; a file tree; Markdown and image preview; a code view; settings with Basic auth, an SSH tunnel, theme and voice transcription; and an optional quota display.

Beyond the README, the code also contains:

- **Car Mode** (iPhone only): a hands-free voice loop with spoken replies, confirmations and typed Maps actions.
- **"Client capabilities"**: the agent can ask the phone to run a Health Quantification export (`docs/features/client_capabilities/`).
- **Voice-first input mode** and a "focus" layout.
- **A provider quota pill** fed by a separate "AI Usage Dashboard" service.
- **English and Simplified Chinese** localization.

Several of these features are tied to the maintainer's own setup:

- The voice token "currently ships with the AI Builders course" (owner, issue #158).
- Car Mode hard-codes the model `openai/gpt-5.6-sol-fast`.
- The capability feature targets the maintainer's Health Quantification app.

Most living docs are in Chinese: the PRD, RFC, `WORKING.md`, `tests.md`, `lessons.md` and `design.md`. The V2 compatibility spec is in English.

---

## 4. Code map

### 4.1 Size and layout

One Xcode project (`OpenCodeClient/OpenCodeClient.xcodeproj`, not XcodeGen) with an app target, a unit-test target and a UI-test target. There are no local Swift packages and no modules.

| Area | Path | Swift lines |
|---|---|---|
| App state (god object plus 13 extensions) | `OpenCodeClient/OpenCodeClient/AppState*.swift` | 5,637 (`AppState.swift` alone 1,734) |
| Chat views | `OpenCodeClient/OpenCodeClient/Views/Chat/` | 7,130 (`ChatTabView.swift` 2,251; `MessageRowView.swift` 1,015) |
| Other views | `Views/*.swift` (files, settings, hosts, sessions, model shortlist, web preview) | 3,907 |
| UI-test fixtures compiled into the app | `Views/Support/` | 2,465 |
| Car Mode view | `Views/Car/` | 756 |
| Services (API, SSE, SSH, voice, quota) | `Services/` | 2,632 (`APIClient.swift` 1,011; `SSHTunnelManager.swift` 770; `SSEClient.swift` 316) |
| Utilities | `Utils/` | 2,246 |
| Models | `Models/` | 1,855 (`Message.swift` 896) |
| Support (localization table, ID minting) | `Support/` | 1,591 (`L10n.swift` 1,527) |
| Stores | `Stores/` | 796 |
| Controllers (static helpers) | `Controllers/` | 339 |
| Root view and app entry | `ContentView.swift`, `OpenCodeClientApp.swift` | 979 |
| **App total** | 96 files | **30,333** |
| Unit tests (Swift Testing) | `OpenCodeClientTests/`, 33 files | 17,767 (807 `@Test` cases) |
| UI tests (XCUITest) | `OpenCodeClientUITests/`, 19 files | 3,477 (78 tests) |

The non-Swift parts are:

- `scripts/` (about 1,100 lines of shell and Python, including `v2_contract_check.py`);
- `ui_driver/` (about 1,000 lines of Python);
- `web_preview_shell/` (about 2,400 lines, a harness for the HTML preview);
- `docs/` (about 7,000 lines);
- minified JavaScript under `OpenCodeClient/OpenCodeClient/Resources/WebPreview/`.

### 4.2 Architecture pattern

The app uses **plain SwiftUI with Observation**: no TCA, no per-screen view models and no module boundaries.

- `AppState` (`@Observable @MainActor final class`, `AppState.swift` line 43) owns almost everything:
  - host profiles, the connection and SSE lifecycle;
  - sessions, the current session's messages, permissions and questions;
  - models, agents, drafts, voice and Car Mode;
  - quotas, deep links and file-tree state.
- Six small `@Observable` stores (`Stores/`) hold fields that `AppState` forwards through computed properties.
- The "controllers" in `Controllers/` are static helper enums.
- Views receive `AppState` directly.
- The RFC states the design plainly: one `AppState` holds global state (`docs/OpenCode_iOS_Client_RFC.md` §4).

### 4.3 Swift language mode and concurrency

These are the build settings in `OpenCodeClient.xcodeproj/project.pbxproj`:

| Setting | Value |
|---|---|
| `SWIFT_VERSION` | `5.0` (Swift 5 language mode) |
| `SWIFT_DEFAULT_ACTOR_ISOLATION` | `MainActor` (app target) |
| `SWIFT_APPROACHABLE_CONCURRENCY` | `YES` |
| `SWIFT_STRICT_CONCURRENCY` | not set, so checking is minimal in Swift 5 mode |
| `IPHONEOS_DEPLOYMENT_TARGET` | 17.0 |
| `XROS_DEPLOYMENT_TARGET` | 26.0 |
| `LastUpgradeCheck` | 2610 |

Signs of how far the code is from Swift 6 strictness:

- There are 6 `@unchecked Sendable` types in app code.
- Event payloads travel as `[String: AnyCodable]` wrapping `Any`, and `[String: Any]` appears at 35 sites.
- The NIO handler in `SSHTunnelManager.swift` (around line 715) carries a comment admitting that "Swift 6 strict concurrency still flags the capture".

Moving to Swift 6 language mode would be a project of its own.

### 4.4 Networking

**V1 only.** `Services/APIClient.swift` calls these V1 routes:

- **Health and projects:** `GET /global/health`, `/project`, `/project/current`.
- **Sessions:**
  - `GET`/`POST /session`, `GET`/`PATCH`/`DELETE /session/{id}`;
  - `GET /session/{id}/message?limit=`;
  - `POST /session/{id}/prompt_async`, plus `POST /session/{id}/message` with a `format` schema for Car Mode;
  - `POST /session/{id}/abort`, `GET /session/status`.
- **Permissions and questions:**
  - `GET /permission`, `POST /session/{id}/permissions/{pid}`;
  - `GET /question`, `POST /question/{id}/reply` and `/reject`.
- **Catalogs:** `/config/providers`, `/provider`, `/agent`.
- **Diffs and todos:** `/session/{id}/diff`, `/session/{id}/todo`.
- **Files:** `/file`, `/file/content`, `/find/file`, `/file/status`.
- **History:** `/session/{id}/fork`, `/session/{id}/revert`.

**Requests**

- All requests go through `URLSession.shared` with a preemptive Basic auth header.
- Any non-2xx status throws.
- Responses are decoded without a content-type check. That is the root cause of the opaque error in #169: a V2 server answers unknown GETs with its web app's HTML and status 200.

**The SSE stream** (`Services/SSEClient.swift`)

- It reads V1's global stream `GET /global/event` through `URLSession.shared.bytes(for:)`.
- A detached task then re-yields **every byte** through an `AsyncThrowingStream<UInt8>`. PR #208 moved this forwarding off the main actor because, in the code's own comment, "fast global event streams otherwise fall seconds behind the server".
- The parser handles LF and CRLF but not a bare CR. It skips `:` comments and joins `data:` lines.
- Frames that fail to decode are dropped silently (`try?`).
- Each handler re-serializes the `Any` dictionary with `JSONSerialization` and decodes it a second time with `JSONDecoder`.

**Reconnect and resync** (`AppState+SSE.swift`)

- The loop backs off exponentially (2^n seconds, capped at 30 s) with no jitter, and resets on any received event. A 401 or 403 pauses it.
- Every (re)connect runs `bootstrapSyncCurrentSession`, which reloads messages, pending requests and statuses.
- The "watchdog" checks every 5 s. After 20 s of silence it runs one REST reconciliation; it **never tears down** a silent stream. A dead socket is only noticed through URLSession's default 60 s request timeout.
- Session status is also **polled every 30 s** while a session list is on screen (`SessionStatusRefresh` in `Views/SessionListView.swift`).
- The app disconnects SSE and the SSH tunnel on `didEnterBackground`, and runs `restoreConnectionFlow` on `willEnterForeground` (`ContentView.swift` lines 369–383). There is no `NWPathMonitor` handling.

**Event handling**

- Handlers run on the main actor and **await REST calls inline**: `loadMessages()` and `loadSessionDiff()` on turn end or on thin payloads. Live updates therefore queue behind network round trips in an unbounded buffer.
- Only the open session's transcript is held and updated. Other sessions receive status and metadata only.

**Optimistic sends**

- `msg_` IDs are minted on the client from the phone's clock (`Support/OrderedServerID.swift`, PR #147).
- A failed send stays inline as a "failed" row with its text kept.
- There is no persisted outbox.

**Paging**

- The first page holds 20 messages (`messagePageSize`, `AppState.swift` line 1159).
- "Load more" re-fetches the whole window with a larger `limit`, because V1 has no cursor.

### 4.5 State management and persistence

**UserDefaults** holds:

- host profiles;
- drafts per host and session;
- the selected model per session and the model shortlist;
- read state (`lastViewedAt`, `failedAt`, per-source acknowledgements);
- step timings and Car Mode sessions;
- SSH configuration and **SSH known hosts**.

**The Keychain** holds passwords, the voice token and the SSH private key. It uses `KeychainHelper.swift`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and no access group.

There is **no database**, no transcript cache, no offline history and no outbox that survives a relaunch.

### 4.6 Rendering

**Chat Markdown**

- MarkdownUI 2.4.1 (grapeot's fork that adds visionOS) renders each text part, and re-parses it on every delta (`Views/Chat/MessageRowView.swift`).
- Text without Markdown syntax renders as plain `Text`.
- Above 12,000 characters a message falls back to a preview.
- Relative images in Markdown load through the server's file API (`Utils/MarkdownImageResolver.swift`, `Utils/WorkspaceMarkdownImageProvider.swift`).

**Syntax highlighting:** none anywhere. The file viewer's `CodeView` (`Views/FileContentView.swift` around line 303) is monospaced lines with line numbers in a `LazyVStack`.

**Markdown files** have two renderers:

- native MarkdownUI;
- a `WKWebView` "web preview" (`Views/MarkdownWebPreviewView.swift`, `Resources/WebPreview/`) built from markdown-it 14.2.0, Temml (LaTeX to MathML) and a DOMPurify 3.4.10 allowlist.

The web preview:

- supports HTML inside Markdown, SVG and styled cards;
- uses a non-persistent data store;
- blocks navigation and bridges link taps to Swift.

However, it **allows http(s) images and sets no Content-Security-Policy**, so remote images load automatically.

**Transcript container**

- It is a `ScrollView` around a **non-lazy `VStack`**, with a `ForEach` over every loaded turn, `defaultScrollAnchor(.bottom)` and a per-session `.id` (`ChatTabView.swift` lines 885–1071).
- Tool calls are grouped into a two-column grid of half-width tiles: file operations become file cards and the rest merge into "N tool calls" (`Views/Chat/ToolCardClassifier.swift`).
- Reasoning appears as collapsible "thinking" cards.

**Diffs: none are rendered.**

- `GET /session/{id}/diff` is fetched into `FileStore.sessionDiffs`, but no view reads that field.
- The PRD (§4.3.3, line 370) says session diffs are deliberately not shown because the API "may return an empty array in some edge cases".
- The "N files changed" patch card only opens the files.
- Tool rows show the command input and the raw output.
- The file tree colours files by git status.

### 4.7 Terminal, voice, notifications and the rest

**Terminal:** none.

**Notifications:**

- None: `UserNotifications` is not imported anywhere.
- `docs/features/push_notifications/research.md` recommends a separate always-on service that turns SSE into APNs pushes, but nothing was built.
- There are no Live Activities, widgets, App Intents or background tasks.

**Voice:**

- VoiceFlowKit 0.4.0 (`grapeot/voiceflow`) streams PCM16 audio over a WebSocket to AI Builder Space's realtime transcription (`gpt-realtime` or `gpt-live-transcribe`).
- It needs a token that is only available through a paid course.
- Users can edit a prompt and a list of terms that bias recognition.
- A voice-first mode keeps the software keyboard down and offers a system paste control.

**Car Mode** (`AppState+CarMode.swift`, `Views/Car/CarModeView.swift`, `Services/CarSpeechOutputService.swift`):

- Replies are spoken with `AVSpeechSynthesizer`.
- It depends on V1 structured output (`format: json_schema`), which V2 ignores according to their own V2 doc.
- It hard-codes a model.

**Other features:**

- host profiles with JSON import and export, but only one active host at a time;
- a session tree with child sessions;
- archive and unarchive (V1 only), rename, delete, fork from a message;
- "edit from here" (revert, then put the prompt back in the composer);
- a model shortlist built from the server catalog;
- an agent picker checked against `/agent`;
- a context sheet with tokens, cache read and write, cost and decode throughput;
- a status line with rounds, tool calls, tokens, cache hit rate and time since the last prompt;
- a todo panel (V1 only) and receipt cards for background subagents;
- photo attachments through `PhotosPicker`;
- deep links of the form `opencode://session/<id>`;
- a text-selection sheet.

### 4.8 iPad, visionOS, accessibility and localization

**iPad**

- At regular width the app lays out a custom `HStack` of fixed-width panes: sessions, file preview, then chat (`ContentView.swift` lines 139–191).
- A "Focus" preference forces the phone layout (`Utils/EffectiveLayout.swift`).
- There is no `NavigationSplitView`, inspector, menu-bar commands or keyboard shortcuts. The only key command is Shift+Return in the composer.

**visionOS**

- It is a native build of the same target (device family 7), with a default window of 2000 × 1188.
- A separate window shows image previews (`OpenCodeClientApp.swift`).
- The SSH tunnel is disabled on visionOS.

**Accessibility:** some labels, `@ScaledMetric` sizes for the status dots, and Reduce Motion respected by the "breathing" running indicator.

**Localization:** a hand-written `L10n` enum with about 458 keys in English and Simplified Chinese (`Support/L10n.swift`), not String Catalogs.

### 4.9 Tests, tooling and CI

**Tests**

- 807 Swift Testing cases cover decoding, URL and path handling, the SSE lifecycle, host lifecycle, message reconciliation, session indicators, Car Mode, voice and layouts. These are substantial and careful.
- 78 XCUITests are driven by launch-argument fixtures. Those fixtures (2,465 lines under `Views/Support/`) are **compiled into the shipping app**, and most of them are not behind `#if DEBUG`.
- One opt-in live test, `ReadToolCardIntegrationTests.swift` (enabled with `OPENCODE_INTEGRATION_TESTS=1`), needs a real server **and a real model**.
- `scripts/v2_contract_check.py` (405 lines) checks V2 wire shapes against a running V2 server, without a model.

**Tooling**

- `scripts/lib_simulator.sh` pins one simulator UDID per repository, probes it with a 15 s screenshot, and warns when machine load is high.
- `scripts/test_unit.sh` and `scripts/test_ui.sh` use a dedicated `-derivedDataPath` and run build-for-testing followed by test-without-building.
- `ui_driver/` is a Python CLI over `simctl` and `xcodebuild`.
- "Tier 4" screenshot QA has an agent judge fixture screenshots (`docs/tests.md`, `skills/ui_test_tasks.md`).

**CI:** there is no `.github/workflows`. An Xcode Cloud manifest exists (`OpenCodeClient.xcodeproj/xcshareddata/xcodecloud/manifest.json`), probably for TestFlight builds.

### 4.10 Dependencies and licenses

| Dependency | Version | License | Notes |
|---|---|---|---|
| Citadel (orlandos-nl) | 0.12.0, up to next major | MIT | SSH client |
| swift-nio-ssh (Joannis fork) | 0.3.5 | Apache-2.0 | Personal fork, "to be archived once Apple … merges"; the same risk is noted in our ARCHITECTURE.md §8 |
| swift-nio, swift-crypto, swift-asn1, swift-atomics, swift-collections, swift-log, swift-system | various | Apache-2.0 | Transitive |
| BigInt (attaswift) | 5.7.0 | MIT | Transitive (Citadel) |
| swift-markdown-ui (grapeot fork) | exactly 2.4.1-visionos.1 | MIT | Upstream is in maintenance mode; its author moved to Textual, which we chose |
| NetworkImage (grapeot fork) | exactly 6.0.1-visionos.1 | MIT | |
| swift-cmark | 0.7.1 | BSD-style (cmark); GitHub reports NOASSERTION | Transitive |
| **VoiceFlowKit (grapeot/voiceflow)** | exactly 0.4.0 | **None. The repository has no LICENSE file, so all rights are reserved** | Needs an AI Builder Space token |
| markdown-it (bundled) | 14.2.0 | MIT | `Resources/WebPreview/markdown-it.min.js` |
| Temml (bundled) | — | MIT; `Temml.woff2` is a clone of a KaTeX font (KaTeX fonts use the SIL Open Font License; verify before reuse) | `Resources/WebPreview/` |
| DOMPurify (bundled) | 3.4.10 | Apache-2.0 or MPL-2.0 | `Resources/WebPreview/purify.min.js` |

---

## 5. V2 status

1. **Issue #169** (opened 2026-09-26 by a user, with a precise root-cause analysis) is still open. The maintainer replied the same day: "We are working on support for both server generations. There is no build yet, and no date to promise. If you rely on this app, do not upgrade that server to OpenCode 2 yet."

2. **The V2 work is documentation only.** PRs #171 and #172 (2026-09-26) and #190 (2026-09-30) produced `docs/v2_server_compatibility.md` (375 lines). Its status line reads: "waiting for the server to reach feature parity before client implementation. The app code is not changed." It was measured on v2.0.18 with no model turn: "A live token frame was not captured".

3. **The design is a translation layer:**
   - keep the V1 models;
   - add a `ServerGeneration` probe and a `V2Mapper`;
   - branch every `APIClient` method on the server generation;
   - translate each V2 event into the V1 property dictionaries and feed the existing V1 handlers.

   The doc says "Do not add a second session or message type."

4. **The implementation is gated on two server features:** an archive write route and todo routes or events. Our research shows V2 **removed the todo tool and API** (`research/01-opencode-server-api.md` line 677, citing `v1-migration.bun.ts:901`) and has no archive operation (matrix row B8). The gate, as written, will not open.

5. **The spec contradicts our source audit of V2 2.0.30 (`d0732ea`):**
   - **Busy and idle state.** The spec derives busy/idle and turn-end reconciliation from `session.status` and `session.idle`. Those events are declared but **never emitted** (`research/01-opencode-server-api.md` line 834).
   - **Message refresh.** The spec reloads messages on `session.message.content.updated`. That event is **filtered out of the public stream** (line 713).
   - **Events it ignores:**
     - `session.execution.started`, `.succeeded` and `.interrupted`;
     - `session.step.*` and `session.tool.*`;
     - `session.retry.scheduled`;
     - the inbox events;
     - the durable `seq`.
   - **Missing features:**
     - prompts are sent without `delivery`, so there is no steer or queue;
     - there is no pairing;
     - permissions and forms are listed per session rather than per location.

6. **Neither grapeot app has V2 code.** No V2 branch exists, and the Android sibling has none either.

7. **A downstream fork did implement the spec.** DeputyFifeofMayberry/fife_code ("FifeCode", created 2026-10-09, 74 commits ahead on `dev`) added:
   - `Services/ServerGeneration.swift`, `Services/V2Mapper.swift` (829 lines) and `Services/APIClient+V2.swift`;
   - V2 translation in `AppState+SSE.swift`;
   - about 1,600 lines of tests against saved response bodies from 2.0.26;
   - English translations of the docs, CI and a TestFlight pipeline.

   Its own `docs/TECH_DEBT.md` lists "live verification pending" as high priority (TD-4). Its event switch handles the same events as the spec, so on current servers:
   - busy/idle comes only from polling `GET /api/session/active`;
   - tool rows appear only after reloads.

   **This is the realistic result of forking: a V1-shaped app with V2 behind a lossy shim.**

---

## 6. Comparison with our design

### 6.1 What they have that we lack or rank lower

Rows refer to `research/08-feature-matrix.md`.

| Their feature (where) | Our row and priority | Assessment |
|---|---|---|
| Native visionOS from the same target, with an image-preview window (`OpenCodeClientApp.swift`) | L4, P2 ("Designed for iPad") | Shows that native visionOS is cheap, but it needed forks of MarkdownUI and NetworkImage. Keep P2 |
| In-app SSH tunnel with an on-device Ed25519 key, trust-on-first-use host keys, a hard failure on key mismatch and a copyable `ssh -R` command (`Services/SSHTunnelManager.swift`) | A8, P2 | Shipping and tested; the best reference for A8 (see §6.2) |
| Car Mode: hands-free loop, short spoken replies, confirmation before side effects, Maps actions | J3 P1, J4 P2 | Its UX contract is worth reading (RFC §10.2: conclusion first, 8–12 s, no Markdown or URLs). Its mechanism (V1 structured output, hard-coded model) does not port |
| Voice-first composer: no automatic keyboard, a system paste control, a reviewable draft (`docs/features/focus_voice_input/design.md`) | J1 P1, D1 P0 | A small toggle we do not have; cheap to add |
| User-editable recognition prompt and terms list (Settings, VoiceFlowKit) | J2 P2 (automatic hints only) | Add a manual terms field next to our automatic `contextualStrings` |
| File preview docked inside the iPhone chat with the composer still live; left-edge swipe closes it (PRs #159, #164) | G5 P1 (we planned sheets) | Good for "read the file while you dictate about it". Consider it for FeatureFiles |
| Markdown documents as first-class content: HTML inside Markdown, SVG, MathML maths, relative images loaded through the server | C10 P1, C11 P1, G5 P1 | Their main use case is document review. Temml (LaTeX to MathML) is a light route to LaTeX |
| Status-line metrics: decode throughput, cache hit rate, rounds and tool counts, time since the last prompt (PRs #165, #185, #192) | E10 P1, C15 P1 | Throughput and cache hit rate are not in our matrix. Cheap once usage events are modelled |
| Provider quota pill (for example a 5-hour window) from an external dashboard | Not in the matrix (E11 P2 is history) | Not in the V2 API and needs a separate service. Note it only |
| Session status dot with subtree roll-up, a count of active descendants, and "syncing" instead of a guess (`docs/features/session_row_indicator/design.md`) | B1/B2/B11 P0 | Same goal as our inbox groups, with more refined rules. Learn from it |
| Receipt cards for completed background subagents (`Views/Chat/TaskNotificationCardView.swift`) | B11 P0, C3 P0 | V2 delivers synthetic messages. A receipt card that opens the child session is a nice touch |
| Model-output cleanup: leaked `<think>` tags, whitespace-only parts, literal `\uXXXX` escapes | Not in the matrix (C1/C2 P0 cover rendering) | Matters for local models (Qwen and others). Cheap; port it |
| English and Simplified Chinese | X4 P2 | They are ahead; keep P2 |
| Host profile JSON import and export | Not in the matrix | Pairing by QR code covers most of it; skip |
| Agent asks the phone to run a local action (Health export) | Out of scope | Skip |

The overlaps where both apps have the feature (fork from a message, "edit from here" / revert, model favourites, cross-block text selection, archive) give us no new information. They match rows B12, D10/E8, E1, C13 and B8.

### 6.2 Components worth reusing or learning from

**A. Copy and adapt (MIT; keep the notice; see "License obligations" below)**

1. **SSH tunnel**, for A8 (P2, after the MVP).

   *Files:*
   - `OpenCodeClient/OpenCodeClient/Services/SSHTunnelManager.swift`:
     - the trust-on-first-use host-key validator, lines 88–120;
     - connect, loopback `NWListener`, Citadel `direct-tcpip` channel and the `NIOToNWConnectionHandler` bridge, lines 380–740;
     - connection-generation tokens that cancel stale attempts.
   - `Services/SSHKeyManager.swift`: on-device Ed25519 key and OpenSSH public-key encoding. It **fails closed** when the Keychain is locked at launch, which was the fix for issue #161.
   - Tests in `OpenCodeClientTests/ConnectionTests.swift`.

   *Adapt:*
   - make it Swift 6 clean (the NIO handler capture and `ListenerWait`);
   - listen on a **random** loopback port instead of the fixed 4096, because any app on the device can connect to a loopback port while the tunnel is up; still require the opencode credential;
   - move known hosts out of UserDefaults;
   - support imported user keys and direct forwarding to the dev host (their model assumes a relay machine that the dev host reaches with `ssh -R`);
   - plug it into our `EndpointResolver` as `EndpointKind.ssh(profile)`;
   - route the terminal WebSocket through the tunnel as well.

2. **IME-aware composer logic**, for D1 in M3.

   *Files:* `Views/Chat/ChatComposerTextView.swift` (309 lines):
   - `ChatComposerKeyAction`;
   - `ChatComposerSendGate`, which never sends while IME marked text is pending;
   - `IMEAwareTextView`, with a Shift+Return key command and software-keyboard suppression for voice-first input;
   - tests in `OpenCodeClientTests/AIBuilderVoiceTests.swift`.

   *Use:* this is the reference for the `UITextView` fallback in ARCHITECTURE.md §3.2. The send-gate rule applies even if we keep `TextEditor`.

3. **Link and path safety**, for C12 and G5 (M2 to M4), in OCRender.

   *Files:*
   - `Utils/WorkspaceLinkResolver.swift`: classifies a link as external, workspace file, fragment or rejected, and blocks `javascript:`, `data:` and encoded `..` traversal. Tests in `OpenCodeClientTests/WorkspaceLinkResolverTests.swift`.
   - `Utils/PathNormalizer.swift`: stack-based `..` folding, `a/` and `b/` diff prefixes, `#anchor` and `:line:col` suffixes, repeated percent-decoding. Tests in `ModelsTests.swift`.

   *Adapt:* V2 uses absolute paths plus a `location` directory.

4. **Model-output normalization**, for C1/C2 in M2, in the OCRender text pipeline.

   *Files:*
   - `Views/Chat/MessageRowView.swift` lines 356–435 (`normalizedText`): fence-aware removal of leaked `<think>` blocks and whitespace-only parts.
   - `Models/Message.swift` lines 8–83 (`DisplayTextDecoder.decodeJSONUnicodeEscapes`).
   - Tests in `RenderingTests.swift`; the reasoning is in `docs/lessons.md` §18–19.

5. **Activity-line debounce**, for the inbox "Running" line (B1) and Live Activity step text.

   *Files:* `Controllers/ActivityTracker.swift` (`debounceDelay`, a 2.5 s window; `docs/lessons.md` §12).

6. **Test-runner tooling**, for our scripts in `Tools/`.

   *Files:*
   - `scripts/lib_simulator.sh`: a pinned simulator per repository, a 15 s screenshot probe and a load warning;
   - `scripts/test_unit.sh` and `scripts/test_ui.sh`: a dedicated DerivedData folder, then build-for-testing followed by test-without-building;
   - `scripts/lib_test_observability.sh`.

   *Why:* several agents build our project at once (M1b right now), so `build.db` lock errors and wedged simulators will hit us too.

   *Note:* `timeout` comes from GNU coreutils and is not on a stock Mac.

**B. Learn from (ideas, not code)**

7. **Status-dot rules** (`docs/features/session_row_indicator/design.md`; `SessionIndicator` and `SessionIndicatorPresentation` in `AppState.swift`; `Views/SessionListView.swift`):
   - priority: needs you, then an unacknowledged failure, then running (breathing), then unread;
   - roll-up over the subagent tree, with a count of active descendants;
   - unknown state shown as "syncing", never as idle;
   - status confirmations expire after 60 s;
   - steady under Reduce Motion.

   Apply these to FeatureInbox rows, but drive them from V2's server-side `time.viewed` and `outcome` rather than their phone-clock heuristics.

8. **Markdown documents** (`Views/MarkdownWebPreviewView.swift`, `Utils/MarkdownImageResolver.swift`, `Resources/WebPreview/`):
   - relative images fetched through the server's file API;
   - MathML for LaTeX;
   - sanitized HTML inside Markdown.

   If we ever use a web view for this, add a Content-Security-Policy and block remote images, as ARCHITECTURE.md §5 requires.

9. **Throughput metric:** `StepTiming` in `Stores/MessageStore.swift` computes output tokens over the window from the first to the last visible token. That excludes prefill and tool time. Use it for the E10 details sheet.

10. **Edge cases for our M2 and M3 sync tests**, taken from their PR history:

    | PR | Edge case |
    |---|---|
    | #203 | Stale message snapshot applied after a session switch |
    | #200 | Connection cancellation not scoped to its connection |
    | #199 | Host switch not isolated from the previous transport |
    | #195 | Session deleted on the server while open |
    | #210 | Acknowledged parent-row reminders reappearing |
    | #188 | Duplicated voice bubbles; auto-follow while streaming |
    | #184 | Scroll offset leaking between sessions |
    | #147 | Deterministic IDs plus inline send failure |
    | #145 | Leaked thinking and whitespace parts |
    | #161 | A locked Keychain at launch must never regenerate keys |
    | #175 | Trailing slash in the base URL |

11. **App Transport Security:** the maintainer reports that ATS blocks plain HTTP to Tailscale's 100.64.0.0/10 addresses even with `NSAllowsLocalNetworking`. Their workaround is an `NSExceptionDomains` entry for `ts.net` (issue #32, `OpenCodeClient/Info.plist`). This feeds open decision 6 in SPEC.md. It comes from the maintainer and was not tested here.

**License obligations.** The MIT license requires that "the above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software". For anything we copy or closely adapt:

- **Each file:** add a header such as `// Adapted from grapeot/opencode_ios_client (MIT), <path> at a4c5e51. Copyright (c) 2026 grapeot.`
- **Repository:** add the full MIT text to a third-party notices file.
- **App:** list it on the acknowledgements screen, because we ship binaries.
- **Version:** take code from current HEAD, because the LICENSE file only arrived on 2026-08-26.
- **Bundled JavaScript** keeps its own licenses: markdown-it (MIT), Temml (MIT, with a KaTeX-derived font) and DOMPurify (Apache-2.0 or MPL-2.0).
- **Never copy from VoiceFlowKit:** it has no license.
- **Docs:** reusing ideas and designs creates no obligation, but copying their documentation text does.

### 6.3 Weaknesses and bugs we already avoid

| Their problem | Our design (ARCHITECTURE.md) |
|---|---|
| V1 only. The V2 plan relies on events V2 never sends (`session.status`, `session.idle`, `session.message.content.updated`) and waits for features V2 dropped | V2-only, built from the source audit; busy/idle comes from `session.execution.*` plus `GET /api/session/active` |
| HTML decoded as JSON, giving an opaque error (#169) | Content-type check before decoding; V1/V2 probe; upgrade screen |
| SSE bytes forwarded one at a time through an async stream; events decoded twice; undecodable frames dropped silently; no bare-CR handling; no first-frame check | Delegate delivers `Data` chunks; `SSEParser` handles CR, LF and CRLF; two-stage decoding with `.unknown` and `.undecodable`; first-frame timeout |
| The "watchdog" never reconnects a silent stream; backoff has no jitter; status is polled every 30 s anyway | 45 s byte watchdog that forces a reconnect; full-jitter backoff; quiet-on-return reconnect; no polling |
| Event handlers await REST calls inside the stream loop on the main actor | The read loop never waits on the main actor; events arrive in batches every 16 ms; backlog cap with a forced resync |
| One active server; switching hosts disconnects | One `ServerConnection` per server; one inbox across servers |
| Only the open session is live; "load more" re-fetches the whole window | Session-level effects for every session; cursor paging and gap splicing |
| No persistence beyond UserDefaults; no offline cache; no outbox | GRDB cache of raw JSON, drafts, an outbox with idempotent IDs |
| Transcript is a non-lazy `VStack`, MarkdownUI re-parses on every delta, and the whole array is observed | `LazyVStack` with one observable per content item, frozen blocks, performance budgets |
| No syntax highlighting; no diff viewer at all | tree-sitter highlighting, a custom diff view, the Changes card |
| Permission card cuts patterns to 2 lines (`Views/Chat/PermissionCardView.swift`); no full command, no reject with a note, no step-up auth | Full-resource sheet, reject with a note, "always" patterns shown, Face ID for "always" |
| Remote images load in the Markdown web preview (no CSP) | Never auto-load remote images |
| No push at all | Plugin, relay, sealed payloads, Notification Service Extension |
| Fixed loopback port for the SSH tunnel | If adopted: random port and our credential checks (§6.2) |
| 2.5k lines of UI-test fixtures compiled into the shipping app | Fixtures live in test targets and Tools |
| Unlicensed and paid-backend voice dependency; personal-workflow features | On-device `SpeechAnalyzer`; no vendor dependency |
| Swift 5 mode, `Any` payloads, `@unchecked Sendable` | Swift 6 language mode from day one, typed `Sendable` models |
| No CI | CI plus nightly contract tests against real V2 servers with a deterministic mock LLM |

### 6.4 Would forking beat continuing our codebase?

No, on every axis the task asked about.

- **Protocol layer.**
  - *Surviving code:* none. Every request, model, event handler and most chat views are shaped around V1: `Part` objects, `message.part.delta`, `/global/event`, `prompt_async`, `/question`.
  - *The V2 route:* their own route to V2 is a translation shim. It keeps the V1 data model and gives up V2's strengths: steer and queue, the inbox, durable `seq`, pairing, generic forms and execution events.
  - *Downstream evidence:* FifeCode shows what that shim produces: about 1,750 new source lines and 1,600 test lines for a client that still is not verified against a live server.

- **Architecture fit with ARCHITECTURE.md.** Our design has:
  - one `actor ServerConnection` per server;
  - MainActor stores split by server, session, transcript, message and content item;
  - a GRDB cache and an outbox;
  - feature modules that never import networking;
  - extensions (the Notification Service Extension and widgets) that share an App Group.

  Theirs has one god object, one connection, one transcript, no database and no package boundaries. Fitting our design into their app is a rewrite from the state layer down.

- **Swift 6 strictness.** They are in Swift 5 mode with minimal checking, `Any`-typed payloads, `@unchecked Sendable` and a known NIO capture issue. Our package already compiles in Swift 6 mode with `NonisolatedNonsendingByDefault`. A fork would add a migration project.

- **Test coverage.** 807 Swift Testing cases plus 78 UI tests is a lot, but they test V1 behaviour and the `AppState` structure, so most would be rewritten or deleted along with the protocol layer. Their only live test needs a real model and they have no CI. Our harness already runs real V2 servers with a deterministic mock LLM and recorded fixtures.

- **Code quality.** The code is careful about races: generation tokens, request-ownership snapshots and revision guards appear throughout. It is also sprawling:
  - `ChatTabView.swift` is 2,251 lines;
  - test hooks live in production views (`ContentView.swift` refers to UI-test fixtures 21 times);
  - most docs are in Chinese;
  - several features exist for one person's workflow.

- **Features versus our MVP.** A fork would give us early visionOS, SSH and voice, all of which are P2 or after the MVP for us. It would give us none of the P0 items: V2, pairing, push, outbox, diffs, highlighting, a cross-server inbox or approvals with full context.

- **Dependencies and intellectual property.**
  - VoiceFlowKit has no license and would have to be removed.
  - MarkdownUI is in maintenance mode.
  - Citadel pins a personal NIO fork.
  - The iOS 17 baseline conflicts with our iOS 26.4 plan (`TextEditor` with `AttributedString`, `SpeechAnalyzer`).

- **Cost.** Roughly a quarter of their 30,000 lines does not depend on the protocol: SSH, path and link utilities, layout, file views, design tokens and localization. Nearly all of that quarter is wired into `AppState`. Replacing their networking, models, state and chat views would cost more than finishing M1b and M2 on our base, and it would throw away a codebase that already passes our M1a acceptance work.

**Decision: continue our codebase.**

---

## 7. Recommended actions

1. **Now (M1b and M2):**
   - Add the edge cases in §6.2 item 10 to the sync-engine test plan.
   - Port the model-output normalization (§6.2 item 4) and the link and path resolvers (§6.2 item 3) into OCRender, with attribution.
2. **Inbox (M2):** adopt the status-dot rules (§6.2 item 7) and the activity-text debounce (§6.2 item 5) on top of V2's server-side unread state.
3. **Composer (M3):** port the IME send gate and Shift+Return handling (§6.2 item 2), and add a voice-first toggle plus a manual recognition-terms list in M8.
4. **Files and review (M4):** prototype the docked file preview on iPhone; load relative Markdown images through `fs.read`.
5. **Tooling (any time):** copy the simulator-pinning and dedicated-DerivedData approach into our test scripts. Concurrent agents make it relevant immediately.
6. **After the MVP (A8):** build the SSH endpoint from their tunnel code, with the adaptations listed in §6.2 item 1.
7. **Attribution:** the first time any code is copied, add a third-party notices file and an acknowledgements entry.
8. **Watch:** issue #169 and the FifeCode fork. Once grapeot ships V2, it becomes a direct open-source competitor with an existing audience (266 stars, a public TestFlight). Our reliability, push and review features are the counter.

---

## 8. Corrections for our research (not applied, because the project is read-only for this task)

- **`research/03-mobile-clients-landscape.md`, §2.3 (grapeot row):**
  - "File tree, diffs, model picker, voice transcription": the app has **no diff viewer**. Diffs are fetched but never displayed, and the PRD defers them.
  - Voice transcription requires a token from a paid course.
  - Last activity was 2026-10-17 (UTC), not 2026-10-14.
  - Add the FifeCode fork: V2 through the translation shim, not verified live.
- **`research/08-feature-matrix.md`, row A8:** the reference is right, but their model is SSH to a relay machine that the dev host reaches with `ssh -R`. It uses a device-generated Ed25519 key and trust on first use, not direct SSH to the dev host with the user's own keys.

---

## Appendix: sources and method

- **GitHub API calls (`gh api`):**
  - repository metadata, languages, contributors, releases, tags, branches;
  - issues #169, #158 and #32; PR #8 and the 80 most recent PRs;
  - the branch comparison for `design/f2-session-orientation`;
  - dependency repositories, including VoiceFlowKit's license and README;
  - the forks list and the FifeCode comparison, plus its `docs/v2_server_compatibility.md`, `docs/TECH_DEBT.md` and `AppState+SSE.swift`.
- **App Store:** the iTunes Search and Lookup APIs (US storefront), 2026-10-16.
- **Files read in the clone:**
  - `README.md`, `AGENTS.md`, `LICENSE`;
  - in `docs/`: `README.md`, `v2_server_compatibility.md`, `lessons.md`, `tests.md`, parts of `OpenCode_iOS_Client_RFC.md` and `OpenCode_iOS_Client_PRD.md`, and `features/{session_row_indicator, push_notifications, background_task_notification, client_capabilities, focus_voice_input}`;
  - the Xcode project's build settings and `Package.resolved`;
  - `Services/{SSEClient, APIClient, SSHTunnelManager, SSHKeyManager}.swift`, `AppState.swift` and `AppState+SSE.swift`, plus parts of `AppState+Messages.swift`;
  - `Stores/MessageStore.swift`, `Models/{Message, HostProfile}.swift`, `Utils/{KeychainHelper, PathNormalizer, WorkspaceLinkResolver, EffectiveLayout}.swift`, `Support/OrderedServerID.swift`;
  - views: `Views/Chat/{ChatComposerTextView, PermissionCardView, ToolCardClassifier, PatchPartView, MessageRowView, ChatTabView}.swift` (parts) and `Views/{MarkdownWebPreviewView, FileContentView}.swift` (parts);
  - `ContentView.swift`, `OpenCodeClientApp.swift`, `Info.plist`;
  - `scripts/lib_simulator.sh`, `ui_driver/README.md`, `Resources/WebPreview/*` (headers only).
- **Our project (read only):** `SPEC.md`, `ARCHITECTURE.md`, `research/03-mobile-clients-landscape.md` (the grapeot entries), `research/08-feature-matrix.md` (§1), `research/01-opencode-server-api.md` (event emission and todo sections), and the package layout under `Packages/OpencodeKit/`.
- **Line counts** come from `wc -l` over the clone. Test counts come from grepping `@Test` and `func test`.
