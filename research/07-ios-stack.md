# Native iOS/iPadOS client for opencode: the recommended technology stack

*Research report 07. Research date: 2026-10-15.*

**Scope.** This report covers the Apple-platform technology choices for a production-quality Swift/SwiftUI client of the opencode server. Two sibling reports go deeper on related topics, and this report relies on them rather than repeating them:

- `01-opencode-server-api.md` documents the opencode protocol.
- `03-mobile-clients-landscape.md` compares connectivity and push architectures.

## How this was researched

**Sources**

- Apple developer documentation, fetched directly (including Apple's documentation JSON).
- WWDC session pages and Apple release notes.
- GitHub repositories and their release metadata, queried through the GitHub API on 2026-10-15.
- opencode source code at tag `v1.19.1` and on the `dev` branch (which is the V2 line).
- The local toolchain: Xcode 27.0 (27A266a), Apple Swift 6.4 and the iOS 27.0 SDK.

**Conventions**

- Statements marked "(SDK)" were checked against the `.swiftinterface` files and headers of that local SDK.
- "Latest release" and "last push" dates are as of 2026-10-15.
- The first draft tagged as "unverified" the items that only a web search could settle, because none was possible. The verification pass of 2026-10-15 resolved every one of them (see the table at the end). Items that are still open now carry [unconfirmed: …].
- [estimate] marks projections.
- Recommendations without a citation are this report's own engineering judgement.

**Caveat about verification.** The session's shared web-search budget ran out partway through. After that point, facts were checked against known primary URLs, the GitHub API and the local SDK instead of by searching.

---

## Summary: the recommended stack

| Area | Recommendation | Main alternative | Main risk |
|---|---|---|---|
| Platform | Deployment target **iOS/iPadOS 26.4**. Build with **Xcode 27** (iOS 27 SDK, Swift 6.4, Swift 6 language mode). UI targets default to MainActor isolation. iOS 27 features sit behind `#available`. | Require iOS 27 if v1 ships after mid-2027 | Liquid Glass and other iOS 27 SDK behaviour changes are mandatory |
| API layer | **Hand-written** Codable models for sessions, messages, events and the PTY, decoded tolerantly, plus a thin typed request layer over URLSession. swift-openapi-generator 1.14.1 is used only as a contract-diff tool and, optionally, for long-tail endpoints from a preprocessed spec. | Generator for everything | The opencode API is young and changes often; its spec has no discriminators and is strict about unknown keys |
| Event stream | One SSE stream per server, handled by an actor with: a watchdog, reconnect with jitter, a full resync on every `server.connected`, and batched updates to the main actor | mattt/EventSource 1.5.1 parser | The stream does not replay missed events, so every disconnect is a possible gap |
| Terminal transport | `URLSessionWebSocketTask` with Basic auth (or a ticket), cursor resume and resize over HTTP `PUT` | Network framework `NWConnection` / `NetworkConnection` | The socket dies when the app is suspended |
| Background | Do not stream while backgrounded. Use APNs (alert, Live Activity and widget pushes) through a server-side plugin and a hosted relay. | `BGContinuedProcessingTask` for runs the user explicitly starts (experiment only) | Needs a server-side companion and a hosted service |
| Discovery, ATS | Pairing first: QR code or link → `/auth/connect/{code}` → 30-day token. Set `NSAllowsLocalNetworking`. Remote access uses HTTPS (OpenTunnel, `tailscale serve`). | Bonjour (V1 `--mdns` or a companion plugin) | Plain HTTP on the LAN exposes the Basic-auth credential |
| Markdown | A **block pipeline**: parse with swift-markdown 0.9.0 off the main actor, freeze finished blocks, re-render only the open tail. Blocks are rendered with **Textual 0.5.0** behind a protocol. | LiYanan2004/MarkdownView 3.0.0 (has a streaming reader); Lakr233/MarkdownView 4.8.3 (UIKit) | Pre-1.0 libraries |
| Code and diffs | **tree-sitter** (swift-tree-sitter 0.10.0 plus grammar SPM packages). **Runestone 0.5.2** as the file viewer. A custom renderer for unified diffs. | HighlightSwift (highlight.js); CodeEditorView | Runestone releases rarely; the Neon highlighter wrapper has not had a release since 2024 |
| Terminal | **SwiftTerm v1.99.0** | libghostty-vt (engine only) | None significant |
| Transcript | `ScrollView` + `LazyVStack`, one `@Observable` model per message, `defaultScrollAnchor(.bottom, for: .sizeChanges)` and scroll-geometry tracking | `UICollectionView` + `UIHostingConfiguration` | Lazy stacks can jump when row heights vary |
| Composer | iOS 26 `TextEditor` bound to `AttributedString`, with a custom mention attribute and a formatting definition | `UITextView` (TextKit 2) wrapper | Edge cases with input methods (IME) and selection |
| Voice | `SpeechAnalyzer` + `SpeechTranscriber` with `contextualStrings`; `DictationTranscriber` as the fallback | WhisperKit (now `argmax-oss-swift` 1.1.1) | Limited coverage of locales and devices |
| System integration | Notification Service Extension that decrypts sealed payloads; Live Activities (push tokens and push-to-start); actionable notifications; push-updated widgets and controls; App Intents; Spotlight; Handoff; Keychain with `AfterFirstUnlockThisDeviceOnly`; optional Face ID | Pushes that carry only an ID (ntfy style); Local Push Connectivity on the LAN | Running and securing the relay; Live Activity update budgets |
| iPad, Mac, visionOS | Fully resizable multi-window iPad app. On Mac: "Designed for iPad". On visionOS: the compatible iPad app. | Mac Catalyst later | The app will look and feel like an iPad app on the Mac |
| SSH | v1.x: a **Citadel 0.12.1** tunnel (local listener + `direct-tcpip`), ed25519 or Secure Enclave P-256 keys, host keys trusted on first use | swift-nio-ssh 0.15.0 directly | Small maintainer base and a forked swift-nio-ssh underneath; the tunnel dies when the app is suspended |
| Tailscale | v1: the **official Tailscale app** + `tailscale serve`. Later: optional embedded **TailscaleKit** (libtailscale). | Cloudflare Tunnel or ngrok over HTTPS | Embedded tsnet has no tagged releases; one App Store precedent so far (Tunnelless, 2026-08; §7) |
| Tooling | **XcodeGen 2.46.0** (synced folders) + one local SPM package. Swift Testing, swift-snapshot-testing 1.19.6, a few XCUITest smoke tests. GitHub Actions `xcode-27` runners. Xcode Cloud or fastlane 2.241.1 for TestFlight. | Tuist 4.x; a plain project with buildable folders | XcodeGen lags behind the Xcode 27 project format |
| On-device AI | Foundation Models only for provisional titles, parsing voice commands and an optional TL;DR; never on the critical path | Private Cloud Compute model (iOS 27; eligibility rules apply) | Depends on device, region and settings; 4K-token context |

**Top risks** (the full register is in §10):

1. **The opencode API is in transition** (V1 is frozen, V2 releases about 6 times a week).
2. **Push needs infrastructure outside the app.**
3. **iOS will not keep a live stream open in the background.**
4. **LAN traffic is plain HTTP.**
5. **Several key libraries are pre-1.0 or maintained by one person.**

---

## 0. Facts about the server that drive the client design

`01-opencode-server-api.md` is the authority on the protocol. The points below are the ones that decide stack choices.

### Two release lines

- **V1** (npm `opencode-ai`, latest v1.19.1 on 2026-10-15) has a frozen API.
- **V2** (npm `@opencode/cli`, 2.0.0 on 2026-09-11, 2.0.30 on 2026-10-15) is on the default branch. It is a rewrite: every route is under `/api/*`, and it has no HTTP compatibility layer for V1 (01 §1, §12.1).
- GitHub Releases list only V1 versions. V2 exists only as git tags: `v2.0.30` is a tag, and the API's "latest release" is v1.19.1 (GitHub API, https://github.com/anomalyco/opencode/tags).

**Decision: build against V2, at least 2.0.10.** That is the version from which the contract only grew. Detect V1 servers and tell the user to upgrade (01 §1, §12.3).

### Transport and authentication

- The server speaks plain HTTP/1.1 and has no TLS of its own.
- Authentication is HTTP Basic with the username `opencode`. The password is the server password or a **30-day pairing token** obtained from `GET /auth/connect/{code}`. The `?auth_token=` query parameter is also accepted (01 §2.5, §2.7).
- The QR code from `opencode pair` contains `{"code": "...", "urls": [...]}`, which can include a LAN URL and an **OpenTunnel** HTTPS URL (01 §2.7).
- **V2 has no mDNS** (01 §2.8). V1 had `--mdns`. In v1.19.1 it publishes a Bonjour `_http._tcp` service named `opencode-<port>` on the host `opencode.local` (https://github.com/anomalyco/opencode/blob/v1.19.1/packages/opencode/src/server/mdns.ts). Enabling it also makes the server listen on `0.0.0.0` (https://github.com/anomalyco/opencode/blob/v1.19.1/packages/opencode/src/cli/network.ts).
- The health and version endpoint is `GET /api/info` (V2) or `GET /global/health` (V1).

### Events

V2 has one global stream, `GET /api/event` (01 §7.1):

- Frames are SSE `data:` lines only. There are no `id:` lines, so `Last-Event-ID` does not work.
- A `: heartbeat` comment arrives every 15 s.
- The first event is always `server.connected`.
- Nothing is replayed after a disconnect.
- If a subscriber falls more than 4,096 frames behind, the server closes that stream.
- Text deltas are batched every 100 ms (01 §7.5).

V1 is similar, with two differences:

- It sends `server.heartbeat` events every 10 s.
- It sets `Cache-Control: no-cache, no-transform`, `X-Accel-Buffering: no` and `X-Content-Type-Options: nosniff`.

Source: https://github.com/anomalyco/opencode/blob/v1.19.1/packages/opencode/src/server/routes/instance/httpapi/handlers/event.ts

### Terminals

- PTYs are created, resized (`PUT {size:{rows,cols}}`) and deleted over REST.
- `GET /api/pty/{id}/connect` opens a WebSocket. Authentication is a Basic header or a single-use ticket valid for 60 s. A `cursor` parameter resumes output (01 §8).
- Server-to-client output is sent as text frames. There is one binary control frame: byte `0x00` followed by `{cursor}`.
- The cursor counts UTF-16 code units.
- Close code 4404 means the session was not found or has exited.

Sources: 01 §8.3 and https://github.com/anomalyco/opencode/blob/v1.19.1/packages/core/src/pty/protocol.ts

### The OpenAPI document

**V2.** I checked the `dev` document. Its SHA-256 matches both `research/opencode-openapi.json` and the copy at tag `v2.0.30` (prefix `3fcd666b597b746b`). My counts are from https://github.com/anomalyco/opencode/blob/dev/packages/protocol/openapi.json:

- OpenAPI 3.1.0, 118 paths, 285 schemas.
- 368 `anyOf`, **0 `oneOf`, 0 `discriminator`**.
- 496 `additionalProperties: false` and opaque event payloads (01 §10.3).

**V1** (v1.19.1, https://github.com/anomalyco/opencode/blob/v1.19.1/packages/sdk/openapi.json):

- 162 paths, 472 schemas, 173 `anyOf`, 1 `oneOf`, 0 discriminators.
- The message `Part` union is an `anyOf` of 12 schemas. The `Event` union is an `anyOf` of 89 variants. `GlobalEvent.payload` defines its unions inline.

### Push

The server sends no push notifications. Plugins get an `event` hook, for example for `session.idle` and `permission.asked` (https://opencode.ai/docs/plugins/), so push notifications need a plugin plus a relay. `03-mobile-clients-landscape.md` §5 compares the designs.

---

## 1. Platform baseline

### 1.1 Where iOS stands in October 2026

**iOS 27 releases**

- iOS and iPadOS 27.0 shipped on 2026-09-14, and 27.0.1 on 2026-09-28 (https://support.apple.com/en-us/100100).
- 27.1 has shipped only for the iPhone Duo. Build 24A94425 (2026-10-12) is the Duo's day-one update, and iPhone19,4 (the Duo) is the only device it lists (https://github.com/littlebyteorg/appledb/blob/main/osFiles/iOS/24x%20-%2027.x/24A94425.json; https://en.wikipedia.org/wiki/IOS_27). Apple's own update pages do not list 27.1 yet (https://support.apple.com/en-us/100100; https://support.apple.com/en-us/149076).
- 27.2 beta 4 was out by 2026-10-13 (https://www.macworld.com/article/3237296/ios-27-2-beta-is-out-now-skipping-over-ios-27-1.html).
- Swift 6.4.1 was tagged on 2026-10-14 (https://github.com/swiftlang/swift-testing tags).

**iOS 26**

- The latest iOS 26 release is 26.7.1 (2026-09-28). iOS 18.7.10 still receives security fixes (https://support.apple.com/en-us/100100).

**Devices**

- iOS 27 supports the iPhone 11 and later, so **no iPhones were dropped**.
- iPadOS 27 **drops the A12 iPads**: iPad Air (3rd generation), iPad mini (5th generation), iPad (8th generation), 11-inch iPad Pro (1st generation) and 12.9-inch iPad Pro (3rd generation). This list comes from comparing the device lists at https://support.apple.com/en-us/100100.

**New form factor**

- The foldable **iPhone Duo** has a 5.4-inch outer screen and a 7.6-inch inner screen. Pre-orders open 2026-10-16 and sales start 2026-10-23 (https://gizmodo.com/iphone-duo-2000808898).
- The SDK has related APIs: WidgetKit `isDynamicIslandLimitedInWidth` and SwiftUI `sceneAccessory` (SDK).

**Xcode**

- Xcode 27 requires macOS Tahoe 26.6 or later on Apple silicon (https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes).

### 1.2 Adoption

| Source | Date | iOS 27 | iOS 26 | iOS 18 and older |
|---|---|---|---|---|
| Apple, iPhones that used the App Store (https://developer.apple.com/support/app-store/) | 2026-06-07 | – | 79% (86% of devices from the last four years) | about 21% |
| Apple, iPads | 2026-06-07 | – | 68% (79% of four-year-old devices) | – |
| TelemetryDeck, apps that use its SDK (https://telemetrydeck.com/survey/apple/iOS/majorSystemVersions/) | end of Sept 2026 | 16.3% | 74.6% | about 9% |
| iOSRef, StatCounter web traffic, cumulative (https://iosref.com/ios-usage) | 2026-10-12 | 4.4% | 76.8% cumulative | 93.1% cumulative |

**Notes on the data**

- **Apple has not yet published an iOS 27 figure.** Its February figure for iOS 26 was 66% (https://www.macrumors.com/2026/02/13/apple-shares-ios-26-adoption-stats/).
- **StatCounter-based numbers undercount new iOS versions**, because of how Safari reports its version (https://appleinsider.com/articles/26/01/12/ios-26-adoption-isnt-record-breaking-but-reports-of-extremely-low-rates-are-flawed).
- **TelemetryDeck minor versions:** 26.6 is 51.2%, 26.5 is 17.6% and 27.0 is 16.4% (https://telemetrydeck.com/survey/apple/iOS/minorSystemVersions/).

**What each minimum would exclude**

- **An iOS 26 minimum excludes about 9% of users today.** By April 2027 it would exclude about 5–7% [estimate].
- **An iOS 27 minimum excludes 84–95% of users today.** By April 2027 it would still exclude about 25–35% of general users, or 10–20% of developers [estimate].

### 1.3 Deployment target: recommendation

**Recommendation:** set the minimum to **iOS/iPadOS 26.4** and build with Xcode 27 against the iOS 27 SDK.

**Why 26.4 rather than 26.0**

- Every device that runs iOS 26 can update to 26.4, so the higher minimum only excludes people who have not updated. That is about 4–5% of users, not 1–2%. In TelemetryDeck's data for the week of 2026-09-28, iOS 26.3 is about 2.3% of all devices and 26.0–26.2 together about 2.2%, computed from the JSON files behind https://telemetrydeck.com/survey/apple/iOS/minorSystemVersions/ and https://telemetrydeck.com/survey/apple/iOS/majorSystemVersions/ (corrected 2026-10-15).
- It brings Foundation Models `tokenCount(for:)` (26.4).
- Apple's Foundation Models update notes for February 2026 list a new on-device model in 26.4, with better instruction following and tool calling, and improved guardrails that block less benign content (https://developer.apple.com/documentation/updates/foundationmodels).
- 26.4 also fixes SwiftUI not surfacing the latest `.userActivity` as the current activity (163136831), which Handoff in §5.5 relies on (https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26_4-release-notes). Of the other APIs added in 26.1–26.4, the one this app would use is `tabViewBottomAccessory(isEnabled:content:)` (26.1), which lets the "agent running" mini bar in §1.8 appear only while a run is active (SDK search for `iOS 26.1` to `iOS 26.4` availability).
- In 26.4, custom adapters (`SystemLanguageModel.Adapter`) are deprecated, and they are obsoleted in 27.0 (SDK).

**Why not iOS 27**

- It excludes most users today.
- It permanently locks out A12 iPads.
- Plan to move to iOS 27 around the iOS 28 launch (September 2027) [estimate].

**What you give up by not requiring iOS 27.** These iOS 27 APIs need `#available` wrappers (all verified in the SDK):

- `Text` now supports real interactive text selection with `.textSelection(.enabled)` (https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes).
- Swipe actions work in any container, including `LazyVStack` rows (`swipeActionsContainer()`, iOS 27).
- Toolbar minimization APIs (`toolbarMinimizationBehavior`).
- `ToolbarOverflowMenu` and `visibilityPriority`, which help on the iPhone Duo's cover screen.
- `TabRole.prominent`.
- `AsyncImage(request:)`, which can send an `Authorization` header.
- In Foundation Models: Private Cloud Compute, image attachments and `reasoningLevel`.

### 1.4 What building with the iOS 27 SDK changes, whatever the deployment target

- **The Liquid Glass opt-out stops working.** Apple's documentation says: "The system ignores this key when you build for iOS 27 or later" (https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility).
- **A launch screen is required.** "Apps that don't include a launch screen are rejected when the App Store begins accepting apps built with the 27.0 SDK" (iOS 27 release notes).
- **The scene-based life cycle is required.** "Apps built with the latest SDK must adopt the scene-based life cycle or they fail to launch" (iOS 27 release notes).
- **`@State` is now a macro.** It is "largely source compatible", but some code that assigns an `@State` in `init` alongside an inline initial value no longer compiles. The new behaviour back-deploys to OS versions aligned with iOS 17 (iOS 27 release notes).
- **`canOpenURL:` is deprecated** (iOS 27 release notes).

### 1.5 App Store SDK requirements

- **Since 2026-04-28,** uploads must be built with Xcode 26 or later against the iOS 26 SDK (https://developer.apple.com/news/upcoming-requirements/).
- **No Xcode 27 requirement has been announced.** Apple's past pattern suggests about April 2027 [estimate].

Building with Xcode 27 from day one avoids a forced migration later.

### 1.6 Swift 6.4 and strict concurrency

**Status**

- Swift 6.4 shipped on 2026-09-15 with Xcode 27 (https://www.swift.org/blog/whats-new-in-swift-september-2026/; WWDC26 "What's new in Swift", https://developer.apple.com/videos/play/wwdc2026/262/).

**New features that matter for app code**

- `anyAppleOS` availability.
- `weak let`, so a `Sendable` class can hold a weak reference.
- A warning for errors thrown from a `Task` that nothing handles.
- `await` inside `defer`.
- `withTaskCancellationShield`, which needs the iOS 27 runtime.
- Swift Testing gains issue severity, `Test.cancel` and XCTest interop (https://www.infoq.com/news/2026/09/swift-6-4-released/).

**The new-project template defaults are not what you want.** New Xcode 27 app projects default to the **Swift 5** language mode. I checked the local Xcode 27 templates:

- `Base_ProjectSettings` sets `SWIFT_VERSION = 5.0`, `SWIFT_APPROACHABLE_CONCURRENCY = YES` and `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`.
- `App Base` sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- Only the SwiftUI Document App template uses Swift 6.0.

**An Xcode detail to watch.** In the local `Swift.xcspec`, `SWIFT_APPROACHABLE_CONCURRENCY` has a `Condition` that holds only when `EFFECTIVE_SWIFT_VERSION` is 4, 4.2 or 5. In swift-build, which Xcode 27 uses, a `Condition` only decides whether an option adds arguments to the compiler command line. It does not change the setting's value (https://github.com/swiftlang/swift-build/blob/main/Sources/SWBCore/SpecImplementations/PropertyDomainSpec.swift), and this setting adds no arguments of its own. Two settings default to its value and have no `Condition`:

- `SWIFT_UPCOMING_FEATURE_NONISOLATED_NONSENDING_BY_DEFAULT`
- `SWIFT_UPCOMING_FEATURE_INFER_ISOLATED_CONFORMANCES`

So in the Swift 6 language mode, `SWIFT_APPROACHABLE_CONCURRENCY = YES` should still turn both features on. This was read from the spec and the swift-build source, not observed in a build (corrected 2026-10-15). **Set both upcoming features explicitly anyway** and check the build log for the `-enable-upcoming-feature` flags.

**Recommended settings**

```yaml
# XcodeGen settings for app / UI targets
IPHONEOS_DEPLOYMENT_TARGET: "26.4"
SWIFT_VERSION: "6.0"                      # Swift 6 language mode on the 6.4 compiler
SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor
SWIFT_UPCOMING_FEATURE_NONISOLATED_NONSENDING_BY_DEFAULT: YES
SWIFT_UPCOMING_FEATURE_INFER_ISOLATED_CONFORMANCES: YES
SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY: YES
SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY: YES
```

**Package layout and concurrency**

- Put networking (the HTTP client, SSE, PTY and SSH) in SPM targets that keep the default `nonisolated` isolation and use `.swiftLanguageMode(.v6)`.
- Make models `Sendable` value types.
- Keep mutable connection state in an `actor` (reconnect state, backoff, cursors).
- **Mark heavy work `@concurrent`:** JSON decoding of large payloads, Markdown parsing, diff parsing and syntax highlighting. Under "nonisolated nonsending by default", a nonisolated async function runs on its caller's actor, which is often the main actor.
- Platform tags in `Package.swift`: `.iOS(.v26)` needs swift-tools-version 6.2, and `.iOS(.v27)` needs 6.4.

### 1.7 SwiftUI and Observation for a streaming app

**Data model**

- Use `@Observable` (iOS 17+) **per message and per streaming part**.
- The store keeps an ordered array of message IDs plus a dictionary of models. A token appended to one message then invalidates one row, not the list.

**Batching updates**

- Batch events off the main actor and flush them to it in groups. The reference opencode client flushes every 10–16 ms (01 §7.7).
- Throttle re-layout of the *streaming Markdown tail* separately, to about 10–20 Hz. V2 already batches deltas every 100 ms.

**Side effects**

- Use the `Observations` async sequence (SE-0475, Swift 6.2, iOS 26 runtime) for side effects such as Live Activity updates and haptics (https://github.com/swiftlang/swift-evolution/blob/main/proposals/0475-observed.md).
- It is transactional and may skip intermediate values. That is fine for UI side effects but wrong for logging deltas.
- SE-0506 (iOS 27) adds `withContinuousObservation` for synchronous change events. It is rarely needed here (https://github.com/swiftlang/swift-evolution/blob/main/proposals/0506-advanced-observation-tracking.md).

**Profiling**

- Profile with the SwiftUI performance instrument introduced at WWDC25 (https://developer.apple.com/videos/play/wwdc2025/256/).

### 1.8 Liquid Glass and the WWDC 2026 UI changes

**iOS 26 baseline APIs** (SDK):

- `glassEffect`, `GlassEffectContainer` and `glassEffectID`. For example, use `glassEffectID` to morph between the microphone and send buttons.
- The `.glass` and `.glassProminent` button styles.
- `ToolbarSpacer`.
- `tabBarMinimizeBehavior` and `tabViewBottomAccessory`, which suit a mini bar showing that an agent is running.
- `Tab(role: .search)`.
- `scrollEdgeEffectStyle`.
- `safeAreaBar(edge: .bottom)`, which lets the composer take part in the scroll edge effect.

**iOS 27 changes**

- Glass diffuses complex content more and gets darker edges.
- A continuous Liquid Glass transparency slider replaces the iOS 26.1 Clear/Tinted switch. No public API reads the slider (https://www.macrumors.com/2026/06/10/how-liquid-glass-is-changing-in-ios-27/; https://www.macrumors.com/how-to/ios-27-tone-down-liquid-glass-transparency/).
- New toolbar minimization APIs and `TabRole.prominent`, for example for a "New session" tab (https://swiftwithmajid.com/2026/06/08/what-is-new-in-swiftui-after-wwdc26/).

**Guidance**

- Use system bars and controls.
- Keep glass off message content.
- Honour Reduce Transparency, Increase Contrast and Reduce Motion.
- Test both ends of the iOS 27 slider.

### Alternatives and risks

**Alternatives**

- Make iOS 27 the minimum if v1 ships after about June 2027.
- Make iOS 26.0 the minimum for maximum reach.

**Risks**

- Supporting both iOS 26 and 27 means two code paths for text selection, swipe actions and authenticated images.
- The `@State` macro may break some code.
- XcodeGen's lag on the Xcode 27 project format (§8).

---

## 2. Networking

### 2.1 The recommendation in brief

The networking layer has four parts:

- **REST:** a hand-written `OpencodeAPI` package over `URLSession`.
- **Events:** one SSE event-stream actor per server.
- **Terminal:** one WebSocket per open terminal.
- **Connectivity:** a reachability and resync engine, driven by `scenePhase` and `NWPathMonitor`.

Generated code is optional and never on the hot path.

### 2.2 Generated client versus hand-written client

**What swift-openapi-generator offers.** The latest release is 1.14.1 (2026-10-14), with runtime 1.13.1 and the URLSession transport 1.3.2, all Apache-2.0 (https://github.com/apple/swift-openapi-generator).

- It supports OpenAPI 3.0.3 and 3.1.0.
- `anyOf` produces "a wrapper struct", and `allOf` produces a wrapper struct.
- With a discriminator, `oneOf` "children must be a reference to an object schema".
- `security` schemes and `tags` are not supported, so authentication goes in a `ClientMiddleware`.
- Source: https://github.com/apple/swift-openapi-generator/blob/main/Sources/swift-openapi-generator/Documentation.docc/Articles/Supported-OpenAPI-features.md

**Why it fits opencode badly.** I verified each failure mode in the runtime source:

- **Strict decoding.** For `additionalProperties: false`, generated decoders call `ensureNoAdditionalProperties`. It throws "Additional properties are disabled, but found … unknown keys" (https://github.com/apple/swift-openapi-runtime/blob/main/Sources/OpenAPIRuntime/Conversion/CodableExtensions.swift). opencode marks almost every object this way (01 §10.3), so **any field the server adds breaks decoding**.
- **Unions decoded by trial.** opencode expresses unions as `anyOf` without discriminators. The generated wrapper decodes every branch and throws `failedToDecodeAnySchema` if none match. If you rewrite them to `oneOf` + `discriminator`, an unknown type throws `unknownOneOfDiscriminator` (https://github.com/apple/swift-openapi-runtime/blob/main/Sources/OpenAPIRuntime/Conversion/ErrorExtensions.swift). In both cases, one new message-part type fails decoding of the whole transcript page.
- **Events and WebSockets are not described.** V2 event payloads are opaque strings in the spec. WebSockets are described as `GET` returning a boolean (01 §10.2).
- **The API moves fast.** Releases arrive about 6 times a week, and the spec carries no API version (01 §12).

**Recommendation**

- Hand-write the domain models: sessions, the message and content types, tool state, inbox items, permissions, forms, models, agents, the event envelope and the events.
- Each union is an enum with a custom `Decodable` that switches on `type`, ignores unknown keys and maps unknown types to `.unknown(type: String, raw: JSONValue)`.
- Hand-write about 60 typed endpoint functions, the parity set suggested by 01 §10.4.
- Treat opencode's generated TypeScript (`packages/client/src/promise/generated/types.ts`, per 01 §10.4) as the canonical reference.

**Where the generator still helps**

- **As a contract check.** In CI, download the spec for each new opencode release, diff it against the pinned copy, and regenerate (with the CLI, ahead of time) into a scratch target. A failed build or a diff signals an API change worth reviewing.
- **For long-tail catalog endpoints, optionally.** Generate them from a **preprocessed** spec (the steps are in 01 §10.4):
  - strip `additionalProperties:false`;
  - turn `anyOf` unions into `oneOf` + `discriminator`;
  - drop `prefixItems` and `not`;
  - use `namingStrategy: idiomatic` and a `filter` limited to the operations you need.

  Use the CLI rather than the build plugin, and check the output in: 142 operations and 285 schemas make the plugin slow to build [estimate].

### 2.3 Consuming SSE on iOS

**Transport options**

- **`URLSession.bytes(for:)`** with a small incremental SSE parser. It must handle `data:` lines, `:` comments, blank-line boundaries and CRLF.
- **mattt/EventSource 1.5.1** (MIT, 2026-08-17). It is spec-compliant, supports `AsyncSequence` over `URLSession.bytes`, and includes automatic reconnect (https://github.com/mattt/EventSource). **Use only its parser.** The reconnect policy belongs in your actor, because a reconnect must trigger an app-level resync.
- **OpenAPIRuntime's `asDecodedServerSentEvents()`.** It parses `id`, `event`, `data` and `retry`, skips comments and has **no reconnection** (https://github.com/apple/swift-openapi-runtime/blob/main/Sources/OpenAPIRuntime/EventStreams/ServerSentEventsDecoding.swift).
- **swift-openapi-urlsession**, which streams response bodies on iOS 15+ with 16 KiB / 32 KiB watermarks (https://github.com/apple/swift-openapi-urlsession/blob/main/Sources/OpenAPIURLSession/URLSessionTransport.swift).

Other options: launchdarkly/swift-eventsource 3.4.0 (Apache-2.0) and Recouse/EventSource 0.1.9 (MIT) (GitHub).

**Session configuration**

- Use a dedicated `URLSession` for the stream.
- Set `timeoutIntervalForRequest` well above the heartbeat interval, for example 60 s.
- Always send `Authorization` preemptively, because opencode does not challenge on every route (01 §2.5).

**Buffering.** opencode sends `Content-Type: text/event-stream` and `X-Content-Type-Options: nosniff` (01 §7.1). Developers report that URLSession holds back the first 512 bytes of a response body for content sniffing unless the type is, for example, `application/json` or `application/octet-stream` (https://developer.apple.com/forums/thread/64875). Whether `text/event-stream` or `nosniff` also turns this off is [unconfirmed: no Apple documentation or engineer statement found; checked that forum thread and two web searches]. The first V2 event, `server.connected`, is small, so measure how long it takes to arrive on a device before relying on the 2 s expectation in §2.4.

**Gotcha:** `AsyncBytes.lines` (`AsyncLineSequence`) drops empty lines, which hides SSE event boundaries. Apple does not document this, but several projects reproduced it in 2026 (https://github.com/LaughingJackalope/macos-skills/pull/2; https://github.com/s-e-r-n/door-into-summer/pull/15; https://github.com/Ichigo3766/Open-Relay/issues/219). It happens to work with V2 because each event is a single `data:` line, but parse properly anyway.

**Decoding in two stages.** First decode the envelope (`id`, `type`, `created`, `location`, `durable`). Then decode `data` for that type, inside an `@concurrent` function. Keep unknown types as raw JSON and log them.

### 2.4 Reconnection and resync engine

Mirror the reference client (01 §7.7–7.8) in an `EventStreamSession` actor. It has these states:

- `idle → connecting → connected(since:) → waiting(backoff) → suspended`

**Connect and resync**

- Probe `GET /api/info` first.
- Expect `server.connected` within about 2 s.
- **Every `server.connected` triggers a full resync:**
  - `GET /api/session/active`;
  - for the open session: its latest message page, inbox, pending permissions and forms;
  - catalogs.
- Record events that arrive during the fetches and replay them over the snapshots, because "event then GET" is safe but the reverse is not (01 §7.6).

**Detecting a dead stream and reconnecting**

- **Watchdog:** abort after 45 s with no bytes. Heartbeats arrive every 15 s in V2 and every 10 s in V1.
- **Backoff:** start at 1 s with full jitter, capped at 30 s while the server is unreachable.
- **Forced reconnect without backoff:**
  - on `NWPathMonitor` path changes;
  - on `scenePhase == .active` if the stream has been quiet for more than 20 s.

**While running**

- Drop deltas for parts you have not loaded; the matching `*.ended` event or the next fetch fills the gap (01 §7.5).
- Key tool calls by `id`, text by `ordinal`, and assistant rows by `assistantMessageID`.
- De-duplicate by event `id`.
- **When the app enters the background,** close the stream yourself. Treat the next `server.connected` as a full resync.

**Later option.** `GET /api/experimental/session/{id}/log?after=<seq>` replays durable events per session. It is experimental and not used by the first-party apps, so keep it behind a capability flag (01 §7.9).

### 2.5 The terminal over WebSocket

**Recommendation:** use `URLSessionWebSocketTask`.

**Connecting**

- Authenticate with a Basic `Authorization` header on the upgrade request. Native clients may skip the ticket.
- Fall back to a ticket from `POST /api/pty/{id}/connect-token` with `x-opencode-ticket: 1` (single use, 60 s).
- Send `location[directory]`, plus `cursor` to resume (01 §8.2).

**Frames**

- Output arrives as text frames.
- One binary frame, `0x00` followed by `{cursor}`, sets the absolute cursor.
- Advance the cursor by `text.utf16.count` for each text frame (01 §8.3).
- Input is sent as text frames.

**Resizing**

- Resize is a debounced `PUT /api/pty/{id}` with `{size}`. It is not a WebSocket message.

**Settings and health**

- Set `maximumMessageSize` explicitly, for example 4 MiB. Apple's page documents the setting but not its default (https://developer.apple.com/documentation/foundation/urlsessionwebsockettask/maximummessagesize). Replay frames are at most 64 KiB of characters each.
- Send `sendPing` about every 20 s to detect dead sockets.

**Closing and resuming**

- Close code 1000 means the process exited.
- Close code 4404 means the session was not found or has exited.
- After an abnormal close, check that the PTY still exists, then reconnect with the last cursor. The server keeps 2 MiB of output (01 §8.3).

**Alternatives**

- Network framework WebSocket support (`NWProtocolWebSocket`, or the iOS 26 Swift `NetworkConnection` API, available per the SDK). It gives finer control but has no ATS or cookie integration.
- Starscream 4.0.8 (Apache-2.0). Its last release was in March 2024, so avoid it (https://github.com/daltoniam/Starscream).

### 2.6 What iOS allows in the background

**The practical answer:** while the app is suspended, nothing streams. Plan on pushes and Live Activities.

**`beginBackgroundTask`**

- Lets you finish an in-flight request, such as sending a prompt.
- The time granted is not guaranteed. Apple DTS says to expect about 30 s on current systems and warns that the figure has changed before (https://developer.apple.com/forums/thread/85066).

**Background (silent) pushes**

- Apple: "don't try to send more than two or three per hour".
- Delivery is "not guaranteed".
- The app has "30 seconds" to run.
- The held push is discarded if the user force-quits the app.
- Source: https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app

They are useful for opportunistic cache refreshes, not for state that must arrive.

**`BGAppRefreshTask` and `BGProcessingTask`.** These run opportunistically and are not real-time.

**`BGContinuedProcessingTask`** (iOS/iPadOS 26). Availability elsewhere is inconsistent: the Objective-C header marks it unavailable on macOS, Mac Catalyst and visionOS, but Apple's Swift documentation lists Mac Catalyst 26.0.

- It "starts in the foreground" and should run "only in response to someone's action".
- It must report progress.
- The system shows it in a Live Activity, where the user can cancel it.
- It may be terminated under resource pressure, and tasks showing "minimal or no progress" are terminated first.
- In the background it "can also use the network".
- Closing the app from the app switcher cancels it without notice.
- Sources: https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask; https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados

A "follow this agent run" task could report progress from the run's todo or tool steps. However, progress is often unknown. Apple's WWDC25 guidance asks that each task start from an explicit user action, have a clear and immediate goal, and make measurable progress, and it warns that unexpected work may get the task cancelled (https://developer.apple.com/videos/play/wwdc2025/227/). An open-ended agent run meets the first condition but not obviously the other two. App Review's view of such use is [unconfirmed: no guideline or published review decision mentions this task type]. **Prototype it behind a flag; do not build on it.** iOS 27 adds `.backgroundTask(.processingTask(_:))` in SwiftUI and an async `submitTaskRequest(_:)` (SDK).

**Background URLSession.** It supports uploads and downloads only, not streaming.

**Local Push Connectivity** (`NEAppPushProvider`)

- It keeps a connection to the server on configured Wi-Fi networks (by SSID) and posts local notifications, with APNs as the fallback.
- It needs the `app-push-provider` Network Extension entitlement, which you request through a form (https://developer.apple.com/documentation/networkextension/local-push-connectivity).
- Home Assistant uses it for LAN pushes (https://companion.home-assistant.io/docs/notifications/notification-local/).
- **Recommendation:** a possible v2 feature for privacy-focused users on a LAN, not v1.

### 2.7 Discovery: pairing first, Bonjour optional

**Primary: pairing**

- Scan the `opencode pair` QR code. Use VisionKit `DataScannerViewController` (iOS 16, SDK) or AVFoundation.
- Or accept a pasted `…/auth/connect/{code}` link.
- Try every URL in the payload in parallel, then exchange the code for a token (01 §2.7).
- Store a multi-endpoint server record (LAN, OpenTunnel, Tailscale) and try the endpoints in order of preference, as 03 §4.3 recommends.

**Optional: Bonjour.** V2 does not advertise itself on the network.

- For V1 servers started with `--mdns`, browse `_http._tcp` and keep services whose names start with `opencode-`. Their host is `opencode.local`, so several machines can collide; resolve each service to its IP address (v1.19.1 `mdns.ts`).
- For V2, a companion plugin could advertise a service of our own, such as `_opencode._tcp` [design proposal].
- Use `NWBrowser` or the iOS 26 Swift `NetworkBrowser` (SDK).
- Declare the service type in `NSBonjourServices`, for example `_http._tcp` and/or `_opencode._tcp`, plus `NSLocalNetworkUsageDescription`.
- No multicast entitlement is needed, provided you browse only service types declared in `NSBonjourServices`. The entitlement is required for arbitrary service types or for browsing all types (https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

**Local network privacy** (TN3179, same URL)

- Every Bonjour operation needs the permission.
- So do outgoing TCP connections to LAN addresses, which means a LAN URL from a QR code also triggers the prompt.
- **VPN interfaces such as Tailscale do not count as the local network.**
- There is no API to query or trigger the prompt.
- If the permission is still undetermined while the app is in the background, the attempt is denied silently.
- The simulator does not enforce it, so test on a device.

**Detecting denial**

- For `NWBrowser`: the `.waiting` state with `kDNSServiceErr_PolicyDenied`.
- For TCP: `currentPath?.unsatisfiedReason == .localNetworkDenied`.
- Explain the permission before the first LAN connection.

### 2.8 App Transport Security

**`NSAllowsLocalNetworking = YES`** (https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)

- It lets ATS connect to "unqualified domains, `.local` domains, and IP addresses using IPv4 or IPv6".
- Since iOS 17, "ATS no longer allows connections to IP addresses by default", so this key is required.

That covers:

- plain HTTP to LAN IP addresses;
- Tailscale `100.x.y.z` addresses;
- MagicDNS short names;
- `*.local` names.

**CIDR exceptions.** `NSExceptionDomains` accepts IP addresses and CIDR ranges since iOS 17. An exception for a domain name does not cover the same host reached by IP, and vice versa (https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsexceptiondomains).

**Tailscale MagicDNS names (`*.ts.net`).** These are fully qualified names, so ATS requires HTTPS.

- **Preferred:** HTTPS through `tailscale serve <port>`. It uses Let's Encrypt certificates, requires HTTPS to be enabled for the tailnet, and machine names appear in public Certificate Transparency logs (https://tailscale.com/kb/1153/enabling-https; https://tailscale.com/kb/1312/serve).
- **Otherwise:** an `NSExceptionDomains` entry for `ts.net` with `NSIncludesSubdomains` and `NSExceptionAllowsInsecureHTTPLoads`.

**Other hosts**

- OpenTunnel and other HTTPS endpoints need no exception.
- Do **not** ship `NSAllowsArbitraryLoads`. Apple requires a justification for it during App Store review, and it weakens security (https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloads). The same applies to `NSExceptionAllowsInsecureHTTPLoads`, which the `ts.net` exception above uses (https://developer.apple.com/documentation/security/preventing-insecure-network-connections).
- Plain-HTTP custom domains are unsupported by design. Users can put them behind HTTPS.

**Security note.** Basic authentication over plain HTTP sends the credential in the clear on the LAN.

- Prefer pairing tokens, which are revoked by changing the server password, over the server password.
- Show an "unencrypted" badge on HTTP endpoints.
- Steer remote use to HTTPS paths.

**Scope of ATS.** It is enforced by the URL Loading System (URLSession). Apple says it doesn't apply to lower-level interfaces such as Network framework or CFNetwork, where the app takes responsibility for connection security (https://developer.apple.com/documentation/security/preventing-insecure-network-connections). That it also covers `URLSessionWebSocketTask` is [unconfirmed: Apple's ATS and WebSocket task pages don't say so; it follows from the task belonging to URLSession]. Don't treat the Network framework gap as a loophole.

### Alternatives and risks

**Alternatives**

- **Generate all models with the generator** after preprocessing: faster to start, more brittle.
- **Use a third-party SSE client's built-in reconnection:** simpler, but it skips the app-level resync.

**Risks**

- **API churn.** Mitigate with contract tests against several server versions and a minimum-version check via `/api/info`.
- **Live-only events.** Mitigate with the resync engine.
- **LAN traffic is plain HTTP.**
- **The local network prompt.** If the user denies it, LAN access fails silently.

---

## 3. Rendering

### 3.1 Streaming Markdown

| Library | Latest (date) | License | Minimum OS | How it works | Streaming support | Notes |
|---|---|---|---|---|---|---|
| **Textual** (gonzalezreal/textual) | 0.5.0 (2026-06-15) | MIT | iOS 18 | SwiftUI `Text` rendering pipeline. Parses Markdown with Foundation's `AttributedString` parser, or a custom `MarkupParser`. | Nothing streaming-specific documented | Successor to MarkdownUI. Native text selection, math, syntax highlighting, tables. Pre-1.0. (https://github.com/gonzalezreal/textual) |
| swift-markdown-ui | 2.4.1 (2024-10-13) | MIT | – | – | – | "Maintenance mode — new development in Textual" (repo description). **Avoid.** |
| **MarkdownView** (LiYanan2004) | 3.0.0 (2026-07-05) | MIT | iOS 16 | Native SwiftUI views over swift-markdown (CommonMark) | `StreamingMarkdownReader`: "incremental parsing", "background document parsing" | LaTeX via a package trait. Continuous selection via `MarkdownText`. (https://github.com/LiYanan2004/MarkdownView) |
| **MarkdownView** (Lakr233) | 4.8.3 tag (2026-10-08); the last GitHub release object is 4.1.7 (2026-07-16), and the details in this row were read at 4.1.7 (corrected 2026-10-15) | MIT | iOS 16 | Pure UIKit/AppKit | "Designed for streaming": updates are throttled and views reused | "Not a full-spec CommonMark renderer". Its own lexer covers about 25 language families. Math via SwiftMath. Used in the FlowDown app. (https://github.com/Lakr233/MarkdownView) |
| `AttributedString(markdown:)` (Foundation) | iOS 15+ | – | – | Foundation parser | – | SwiftUI `Text` renders inline styling only. Block structure arrives as `PresentationIntent`, which you must lay out yourself. |
| swiftlang/swift-markdown | 0.9.0 (2026-09-21) | Apache-2.0 | – | cmark-gfm parser and syntax tree | Parser only | The parser to build your own renderer on |

**Recommendation: a block pipeline rather than relying on one library.**

1. Keep the raw text of each streaming part in its model. Apply deltas there.
2. Off the main actor (`@concurrent`), split the text into top-level blocks with swift-markdown.
3. Treat every block except the last as **frozen**. Render each once, cache the result by content hash, and mark the views `Equatable`.
4. Re-parse only the **open tail block**, at most every 50–100 ms.
5. Before parsing, "heal" partial syntax. For example, close an unterminated code fence, emphasis marker or table row, so half-written Markdown renders cleanly.
6. Render each block type separately:
   - **Paragraphs, headings, lists and quotes:** Textual (`StructuredText` / `InlineText`).
   - **Code fences:** a custom `CodeBlockView` with a monospace font, horizontal scrolling, a copy button and a language label. Highlighting runs asynchronously once the fence closes.
   - **Tables:** a horizontally scrolling `Grid`.
   - **Math:** SwiftMath.
7. Put the renderer behind a `MarkdownBlockRenderer` protocol. If the SwiftUI route misses performance targets on long answers, swap in Lakr233/MarkdownView (UIKit) for message bodies. LiYanan2004's `StreamingMarkdownReader` is a quick-start alternative.

**Text selection**

- On iOS 27, `Text` with `.textSelection(.enabled)` supports real interactive selection (iOS 27 release notes). Textual also advertises native selection.
- On iOS 26, add a "Select text" sheet backed by `UITextView`.

### 3.2 Keeping long streams smooth

- **Coalesce in two stages.** Events flush to the main actor about every 16 ms. Markdown tail re-layout runs at about 10–20 Hz. V2 deltas already arrive every 100 ms (01 §7.5).
- **Never re-render finished messages.** Use stable IDs, `Equatable` rows, and no `GeometryReader` per row.
- **Measure** with the SwiftUI instrument. WWDC25 says SwiftUI "improved scheduling of user interface updates on iOS" and that "nested scrollviews with lazy stacks" now load lazily (https://developer.apple.com/videos/play/wwdc2025/256/).
- **Fold very long tool outputs** behind "Show more". Render them as plain monospaced text, with no Markdown.

### 3.3 Syntax highlighting

| Option | Version (date) | License | Engine | Status |
|---|---|---|---|---|
| **tree-sitter/swift-tree-sitter** (formerly ChimeHQ/SwiftTreeSitter) | 0.10.0 (2026-03-18) | BSD-3 | tree-sitter (core v0.27.1, 2026-10-08, MIT) | Active. Grammars ship SPM manifests, for example `tree-sitter-typescript` (`Package.swift`) and alex-pinkus/tree-sitter-swift 0.7.3. Pin `exact: "0.10.0"`: a stray `0.25.0` tag (2025-06-02, 14 commits behind 0.10.0) wins SwiftPM resolution under `from:` (`gh api repos/tree-sitter/swift-tree-sitter/compare/0.10.0...0.25.0`). |
| Neon (now `slsrepo/Neon`, redirected from ChimeHQ/Neon) | 0.6.0 (2024-01-13); commits until 2026-08 | BSD-3 | Connects tree-sitter to TextKit | No release in nearly three years |
| Highlightr | 2.3.0 (2025-06-18) | MIT | highlight.js via JavaScriptCore | README: "As of 2026, Highlightr is no longer actively maintained" |
| HighlightSwift | v1.1.0 (2024-06-25) | MIT | highlight.js via JavaScriptCore; "50+ common languages" | Slow-moving |
| Splash | 0.16.0 (2021-06-14) | MIT | Swift-only grammar | Stale |
| Lakr233/MarkdownView's built-in lexer | 4.1.7 (latest tag 4.8.3) | MIT | Approximate lexer; "tens of microseconds" per block | Only useful inside that library |

All rows are from the GitHub repositories listed.

**Recommendation**

- Use **tree-sitter** for the file viewer, diffs and *completed* chat code blocks.
- Ship a curated set of about 15–20 grammars: TS/JS, Python, Go, Rust, Swift, Kotlin, Java, C/C++, C#, Ruby, PHP, Bash, JSON, YAML, TOML, HTML/CSS, SQL, Markdown and Dockerfile.
- Write a small highlight-query-to-attributes mapper instead of depending on Neon.
- While a code block is streaming, show plain monospace text.
- Measure binary growth for each grammar before adding the long tail. Sizes vary widely: the WebAssembly builds attached to each grammar's latest GitHub release range from about 10 KB (JSON) and 0.2 MB (Go) to 1.4 MB (TypeScript, TSX), 3.3 MB (C++) and 5.1 MB (C#) (`gh api repos/tree-sitter/tree-sitter-<lang>/releases/latest`). Native arm64 sizes are [unconfirmed: the grammar projects don't publish them, and measuring needs a build].

### 3.4 Code viewer and editor

**Recommendation: Runestone 0.5.2** (2026-03-25, MIT; https://github.com/simonbs/Runestone).

- iOS UIKit text view built on tree-sitter, with line numbers and invisible characters.
- Built "to be fast", using tree-sitter's incremental parsing and AvalonEdit's line tree.
- Use it in read-only mode, wrapped in `UIViewRepresentable`, with the same grammars as §3.3.
- Light editing can come later.

**Alternatives**

- **CodeEditorView** (mchakravarty): Apache-2.0, SwiftUI, for "iOS, visionOS, and macOS". Last tag 0.16.0; active in October 2026.
- **STTextView 2.4.1** (2026-09-08): TextKit 2 with iOS support. **Licensed under GPL-3.0 or a commercial license** (its `LICENSE.md`), so use it only with a commercial licence.
- **CodeEditSourceEditor 0.15.2** (2025-09, MIT): macOS only. Its `Package.swift` declares only `.macOS(.v13)`, and its README offers SwiftUI and AppKit APIs (https://github.com/CodeEditApp/CodeEditSourceEditor/blob/0.15.2/Package.swift) (corrected 2026-10-15).

**Risk.** Runestone has a single maintainer and releases rarely. Keep it behind a `CodeViewer` protocol.

### 3.5 Diffs

**What the server provides.** opencode returns unified patch text for file diffs. In V1 this is `SnapshotFileDiff {file, patch, additions, deletions, status}` (v1.19.1 spec). For V2, see 01 §6.8. So the client parses diffs rather than computing them.

**Rendering approach**

1. Parse unified hunks into rows: context, addition and deletion.
2. Pair deletions with additions and compute **word-level highlights** with Swift's `CollectionDifference` (`difference(from:)`) on token arrays.
3. Syntax-highlight each side with tree-sitter on the hunk text, plus a little context.
4. Lay out by width:
   - **iPhone and compact widths:** unified view.
   - **iPad and regular widths:** side-by-side, from one row model with left and right cells, so both sides scroll together.
5. Collapse unchanged regions, and use a shared horizontal scroll for each hunk.
6. Render fixed-height monospaced rows in a `LazyVStack`. For very large diffs (thousands of lines), switch to `UICollectionView`.

### 3.6 Terminal

**Recommendation: SwiftTerm v1.99.0** (2026-10-08, MIT; https://github.com/migueldeicaza/SwiftTerm).

- UIKit and AppKit front ends.
- ANSI, 256-colour and TrueColor.
- Mouse events and a selection engine.
- Sixel, iTerm2 and Kitty image protocols.
- Optional Metal rendering.
- Used in Secure ShellFish, La Terminal and CodeEdit.

**Wiring**

- WebSocket text frames go to `feed`.
- `TerminalViewDelegate.send` writes WebSocket text frames.
- Debounce the `PUT` resize when the size changes.
- On iPhone, add an accessory bar (Esc, Ctrl, Tab, arrow keys).

**Alternatives**

- **libghostty-vt.** The Ghostty repository ships a C API (`include/ghostty/vt.h`) and an example that consumes an XCFramework built with `zig build -Demit-lib-vt` from Swift (https://github.com/ghostty-org/ghostty). It is a terminal engine only, so you would write the renderer.
- **xterm.js in a WKWebView.** It has more overhead and weaker keyboard integration.

### 3.7 LaTeX and Mermaid

**LaTeX: ship in v1, natively.**

- **SwiftMath 1.7.3** (2025-08, MIT): a Swift port of iosMath, used by Lakr233/MarkdownView. LiYanan2004/MarkdownView's `LaTeX` package trait, on by default, also pulls in SwiftMath (from 1.7.3) on iOS and macOS (https://github.com/LiYanan2004/MarkdownView/blob/3.0.0/Package.swift).
- **iosMath 2.5.0** (2026-07, MIT).
- **LaTeXSwiftUI 2.0.0** (2026-04, MIT): an alternative. It renders with MathJax through MathJaxSwift, which runs MathJax in JavaScriptCore without WebKit, and draws the resulting SVG with SwiftDraw (https://github.com/colinc86/LaTeXSwiftUI; https://github.com/colinc86/MathJaxSwift).

**Mermaid: v1.1, on demand.**

- Bundle mermaid.js offline and render it in the iOS 26 SwiftUI `WebView`/`WebPage` (https://developer.apple.com/videos/play/wwdc2025/256/; `_WebKit_SwiftUI` in the SDK).
- Render only after a tap on "Render diagram", then cache a snapshot image.
- A native renderer now exists but is young. lukilabs/beautiful-mermaid-swift 1.0.4 (2026-04-27, MIT, iOS 15+) draws six diagram types (flowchart, state, sequence, class, ER and XY charts) in pure Swift with an ELK layout port, and has one contributor (https://github.com/lukilabs/beautiful-mermaid-swift). Keep mermaid.js as the full-coverage path (corrected 2026-10-15).

### 3.8 Transcript container and bottom anchoring

**Recommendation:** `ScrollView` + `LazyVStack` with stable IDs. Pin it to the bottom with these APIs (SDK):

- `defaultScrollAnchor(.bottom, for: .initialOffset)` to open at the bottom.
- `defaultScrollAnchor(.bottom, for: .sizeChanges)` to stay at the bottom as content grows. The `for:` roles need iOS 18.
- `onScrollGeometryChange` (iOS 18) to track an `isNearBottom` flag.
- `ScrollPosition` to call `scrollTo(edge: .bottom)` programmatically.

**"Stick to bottom unless the user scrolls up"**

- Auto-scroll only while `isNearBottom` is true.
- Otherwise show a "Jump to latest" pill with an unread count.

**Other details**

- Load history newest-first and prepend older pages when the user reaches the top.
- Keep the scroll position stable when prepending. If anchoring misbehaves, use the `UICollectionView` fallback.
- On iOS 27, use row swipe actions in the lazy stack (`swipeActionsContainer`) for copy, retry and fork.
- Avoid the "inverted list" trick, because the iOS 18 scroll anchors make it unnecessary.

**Fallback.** If profiling shows scroll jumps or memory growth with long, variable-height transcripts, use `UICollectionView` with a compositional list layout, a diffable data source and `UIHostingConfiguration` cells. Then manage bottom anchoring yourself with `contentOffset` adjustments. Community reports of `LazyVStack` jumps exist. In one, rows of unknown height made the scroll position jump when scrolling up, and giving the rows a fixed height cured it (https://github.com/kean/Nuke/issues/721). Decide by measuring.

### Alternatives and risks

**Alternatives** are listed in each table.

**Risks**

- **Young libraries.** Textual is pre-1.0 and Runestone releases rarely. Hide both behind protocols.
- **Grammar binary size.**
- **No text selection on iOS 26.** It needs a workaround.

---

## 4. Input

### 4.1 Composer with @mentions and slash commands

**Recommendation:** the iOS 26 `TextEditor(text: $attributedText, selection: $selection)` (WWDC25 session 280, https://developer.apple.com/videos/play/wwdc2025/280/).

**Mention tokens**

- Define a custom `CodableAttributedStringKey`, for example `MentionAttribute` whose value is `.file(path)` or `.agent(name)`.
- Restrict editing with an `AttributedTextFormattingDefinition`, so users cannot apply bold or other arbitrary styles.
- Use an `AttributedTextValueConstraint` to style the tokens.
- Insert and replace tokens with `text.transform(updating: &selection) { … }`, which keeps the selection valid.

**Triggers**

- On each text or selection change, scan back from the caret to the nearest `@` or `/` at a word boundary.
- Show suggestions in a panel above the composer:
  - files from the server's file search (V2 `/api/fs/find`; V1 `/find/file`);
  - agents (`/api/agent`);
  - commands (`/api/command`).
- Handle ↑ ↓ Tab and Return with `onKeyPress` when a hardware keyboard is attached.
- SwiftUI's `textInputSuggestions` is **macOS-only** (`@available(iOS, unavailable)`, SDK), so you need your own panel.

**Sending**

- Map tokens onto the V2 prompt body `{text, files[{uri}], agents, skills, delivery}` (01 §5.3).

**Placement**

- Dock the composer with `safeAreaBar(edge: .bottom)`. Apple lists "`@FocusState` doesn't work in `safeAreaBar`" as a known issue in the iOS 26.1 release notes (158720838), and no later notes through 27.0 mark it fixed, so test composer focus early (https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26_1-release-notes).
- Put the buttons in a `GlassEffectContainer`, and use `glassEffectID` to morph between the microphone and send buttons.

**Fallback.** A `UITextView` (TextKit 2) in `UIViewRepresentable` gives exact control over:

- marked text from input methods (IME);
- `keyCommands`;
- `pasteConfiguration`;
- `NSTextAttachment` chips.

Switch to it if `TextEditor` misbehaves with IME input or undo. Whether it does is [unconfirmed: Apple's iOS 26.x and 27.0 release notes list no open `TextEditor` IME or undo issue, only an undo-stack bug with several `TextEditor` views that iOS 26 fixed (83650197); a GitHub issue search found no reports].

### 4.2 Attachments

**Pickers**

- **`PhotosPicker`.** The picker is "system-rendered UI", and Apple lists "availability of PHLivePhoto objects without library access" among its benefits (https://developer.apple.com/documentation/photosui/phpickerviewcontroller). No photo-library prompt is needed in practice.
- **`.fileImporter` / `UIDocumentPickerViewController`.** Use security-scoped URLs.
- **Camera.** Use `UIImagePickerController` wrapped for SwiftUI, or AVFoundation for a custom camera (`NSCameraUsageDescription`).
- **QR codes and text.** Use VisionKit `DataScannerViewController` (iOS 16; not on Mac Catalyst, SDK).

**Paste and drag**

- `PasteButton` avoids the paste permission prompt. Reading `UIPasteboard` programmatically triggers it.
- Drag and drop on iPad and Mac uses `.dropDestination(for:)` with `Transferable` types: images, PDF, text and file URLs.

**Processing**

- Downscale large images with ImageIO, for example to a 2048 px longest side.
- Convert HEIC to JPEG or PNG.
- Check that the model accepts the attachment type (model metadata, 01 §6.4).
- Send inline attachments as `data:` URIs, as the reference client does (01 §7.7).

### 4.3 On-device speech-to-text

**Recommendation:** `SpeechAnalyzer` (an actor, iOS 26) with `SpeechTranscriber`.

**Availability and models**

- `SpeechTranscriber.isAvailable` depends on "the device's hardware and capabilities".
- `supportedLocales` and `installedLocales` tell you which locales work. Models download through `AssetInventory`.
- Where `SpeechTranscriber` is unavailable, use `DictationTranscriber`, which is "compatible with older devices".
- Source: https://developer.apple.com/documentation/speech/speechtranscriber

**Vocabulary**

- `AnalysisContext.contextualStrings` exists (SDK). Feed it project file names, symbols and agent names to improve accuracy on code identifiers.

**iOS 27 additions**

- `CaptureInputSequenceProvider` and `AssetInputSequenceProvider` (SDK).

**UX**

- Show volatile results greyed out in the composer, and replace them on finalisation.
- A "voice command" mode can route short utterances through Foundation Models (§9).

**Permissions**

- `NSMicrophoneUsageDescription` is required.
- `SpeechAnalyzer` appears to need only microphone permission. Apple's WWDC25 sample requests only microphone access (https://developer.apple.com/videos/play/wwdc2025/277/). Firefox for iOS does the same in its `SpeechAnalyzer` engine, while its `SFSpeechRecognizer` engine also requests speech-recognition authorization (https://github.com/mozilla-mobile/firefox-ios/blob/main/BrowserKit/Sources/QuickAnswersKit/Backend/SpeechService/SpeechAnalyzerEngine.swift). Apple's `SpeechAnalyzer` documentation names no authorization step. Include `NSSpeechRecognitionUsageDescription` anyway, because the `SFSpeechRecognizer` fallback needs it.

**Alternative:** WhisperKit, now `argmaxinc/argmax-oss-swift` v1.1.1 (2026-10-08, MIT). It covers more languages and offers model choice, at the cost of large model downloads (https://github.com/argmaxinc/argmax-oss-swift).

### 4.4 iPad hardware keyboard and menu bar

**Menu bar.** In iPadOS 26, "every app on iPad gets its own menu bar". Apple's guidance: order menu items by how often they're used, "assign keyboard shortcuts to the most commonly performed actions", and dim inactive items rather than hiding them (WWDC25 session 208, https://developer.apple.com/videos/play/wwdc2025/208/). Build it with `.commands` / `CommandMenu`.

**Suggested shortcuts**

| Shortcut | Action |
|---|---|
| ⌘↩ | Send |
| ⇧↩ | New line |
| Return | Send, when a hardware keyboard is attached |
| ⌘N | New session |
| ⌘K | Session and file switcher |
| ⌘. or Esc | Interrupt |
| ⌘1–9 | Switch tabs or sessions |
| ⌘F | Find in transcript |
| ⌘\ | Toggle sidebar |
| ⌘⇧A | Review pending approval |

**Focus.** Use `@FocusState` and `.focusable`.

### Alternatives and risks

- `UITextView` is the composer fallback, and WhisperKit the voice fallback.
- **Locale coverage:** `SpeechTranscriber` locale support varies.
- **Paste prompts:** prefer `PasteButton`.

---

## 5. System integration

### 5.1 Push notifications (APNs) for a self-hosted server

**The constraint.** The APNs `.p8` key belongs to the app's developer, and the opencode server runs on the user's machine. So pushes need:

- a **server-side opencode plugin**, using the `event` hook (https://opencode.ai/docs/plugins/);
- a **hosted relay**.

`03-mobile-clients-landscape.md` §5 compares the designs. The iOS side of the recommended design:

**Pairing**

- Pairing installs per-device keys.
- The plugin seals each payload to the device with **HPKE**. CryptoKit `HPKE` is available from iOS 17 (SDK).

**Relay and APNs**

- The relay sends an `alert` push with generic text, the ciphertext and `mutable-content: 1`.
- A **Notification Service Extension** decrypts it with a key in the shared Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) and fills in the title and body.

**Pattern for privacy-focused users.** ntfy's upstream relay forwards only "the message ID… in the `X-Poll-ID` header" and shows "New message". The device then fetches the content from the user's own server (https://docs.ntfy.sh/config/).

**APNs parameters** (https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)

- **Push types:**
  - `alert`: priority 10 for permission requests, 5 for "run finished";
  - `liveactivity`;
  - `widgets` (topic suffix `.push-type.widgets`);
  - `controls`;
  - `background`: priority 5 only.
- **Payload limit:** 4 KB.
- **`apns-collapse-id`:** at most 64 bytes. Use one per session, so progress pushes replace each other.
- **`apns-expiration`:** keep it short for permission requests, which become stale.

### 5.2 Live Activities

**Starting and updating**

- Start a Live Activity when the user sends a prompt from the app, with `pushType: .token`.
- Register `pushTokenUpdates` with the relay.
- The plugin then sends `liveactivity` updates when the step or tool changes, when a permission is requested, and when the run ends.

**Push-to-start**

- Register `pushToStartTokenUpdates` so the plugin can start a Live Activity for runs started from the desktop.
- This is impossible on 17.1 and earlier. "For devices running iOS 18 and iPadOS 18, you can send different APNs payloads to start a Live Activity to listen to updates on a push token or a channel ID."
- Broadcast channels (`PushType.channel`, iOS 18, SDK) cannot start an activity.
- Source: https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications

**Update budget**

- Priority 10 updates count against a budget; priority 5 updates do not.
- Use priority 5 for routine progress and 10 for "needs approval" and "finished".
- Add `NSSupportsLiveActivitiesFrequentUpdates`, and read `frequentPushesEnabled`, because users can turn frequent updates off (same page).

**Limits** (https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)

- Data can't exceed "a combined size of 4 KB".
- An activity is "active for up to eight hours", and stays on the Lock Screen for "a maximum of 12 hours".

**Approve and deny buttons**

- Live Activities "can contain SwiftUI buttons and toggles" through App Intents.
- These "don't perform actions in CarPlay" (same page).
- Use them for Approve and Deny when a permission is pending.

**iOS 26 additions**

- `request(…style:alertConfiguration:start:)` supports scheduled starts and styles (SDK).

**Content.** Keep the content coarse: session title, current tool, elapsed time and progress through the todo list.

### 5.3 Actionable notifications (approve or deny from the notification)

**Category design**

| Action | Option | Notes |
|---|---|---|
| "Allow once" | `.authenticationRequired` | Requires the device to be unlocked |
| "Reject" | `.destructive` | |
| "Reply" | `UNTextInputNotificationAction` | For question and form answers |

Keep "Always allow" inside the app, behind Face ID. The action options are `UNNotificationActionOption…` in the SDK headers.

**Handling the action**

- The action arrives in `userNotificationCenter(_:didReceive:)` and is sent back **over the direct path**: LAN, Tailscale or OpenTunnel. It never goes through the relay (03 §5).
- If the server is unreachable, post a failure notification with an "Open app" action.

**Interruption level**

- Use the `timeSensitive` level for permission requests (`UNNotificationInterruptionLevelTimeSensitive`, SDK). It needs the time-sensitive notifications entitlement.

### 5.4 Widgets and Control Center

**Widgets**

- Show active sessions, pending approvals and the last result.
- They can be interactive through App Intents.
- From iOS 26 they can be **updated by push** (`WidgetPushHandler`, SDK; `widgets` push type).
- Share data through an App Group store.

**Control Center controls** (`ControlWidget`, iOS 18; `ControlPushHandler`, SDK)

- "New prompt"
- "Voice prompt"
- "Review pending approval"

### 5.5 App Intents, Shortcuts, Siri, Spotlight and Handoff

**App Intents**

- Model `Server`, `Project` and `Session` as `AppEntity`. Make sessions `IndexedEntity` so Spotlight can find them.
- Intents:
  - `SendPromptIntent(project, text)`;
  - `GetSessionStatusIntent`;
  - `ReviewPendingApprovalIntent`, which opens the app and requires authentication;
  - `OpenSessionIntent`.
- Expose them through `AppShortcutsProvider`.
- The same intents drive widgets, controls, Live Activity buttons and the Action button.
- iOS 27 adds `LongRunningIntent.performBackgroundTask`, `SyncableEntity` and `RelevantEntities` (SDK).
- Siri's Apple Intelligence features work with app intents that adopt a schema from Apple's App schema domains, and Apple says to adopt a schema only where an action genuinely matches its domain (https://developer.apple.com/documentation/appintents/making-actions-and-content-discoverable-by-apple-intelligence; https://developer.apple.com/documentation/appintents/app-schema-domains). No domain covers sending a prompt to a coding agent, so design the intents to be useful in Shortcuts, App Shortcuts and Spotlight.

**Spotlight**

- Index session titles and summaries with Core Spotlight. Deep-link with `opencode-ios://server/{id}/session/{id}`.

**Handoff**

- Publish an `NSUserActivity` for each open session, with the `.userActivity` modifier, so work continues on iPad or Mac.
- Use `webpageURL` only for an HTTPS endpoint, such as OpenTunnel. The V2 web app has a session route, `/server/{base64 of the server URL}/session/{id}` (https://github.com/anomalyco/opencode/blob/dev/packages/app/src/shell/routes/routes.tsx; `sessionHref` in `packages/app/src/shell/routes/session.ts`).

### 5.6 Keychain and Face ID

**Keychain**

- Store each server's credential (pairing token or password) as a generic-password item with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, in a Keychain access group shared with the Notification Service Extension, widgets and intents. "AfterFirstUnlock" lets notification actions and extensions work while the phone is locked. "ThisDeviceOnly" keeps credentials out of backups and iCloud.
- Sync the server *list* (URLs and names, no secrets) through iCloud key-value storage, if wanted.

**Wrapper choice**

- Write a thin wrapper of your own over the Security framework, or use **Valet 5.1.1** (2026-09-09, Apache-2.0, maintained; https://github.com/square/Valet).
- KeychainAccess's last release was v4.2.2 in 2021 (https://github.com/kishikawakatsumi/KeychainAccess).

**Face ID**

- Offer an optional app lock with `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` and `NSFaceIDUsageDescription`.
- Require biometry before high-risk actions: "Always allow", bash commands that match dangerous patterns, and revealing credentials.
- For SSH signing keys, use `SecAccessControl` with `.biometryCurrentSet` or `.userPresence`.
- `LADomainState` (iOS 18, SDK) detects biometric enrollment changes.
- iOS 18's system-wide "Require Face ID" app lock (https://support.apple.com/guide/iphone/lock-or-hide-an-app-iph00f208d05/ios) complements, but does not replace, an in-app lock for specific actions.

### 5.7 iPad multi-window and Stage Manager

**Windows**

- Use `WindowGroup(for: SessionRef.self)` with `openWindow(value:)`, so each session can have its own window.
- Keep per-window UI state in `@SceneStorage`.
- Name each window after its session. WWDC25 guidance: give each window a descriptive name, use window controls in line with the toolbar, and make resizing "non-destructive" (WWDC25 session 208).

**Full-screen opt-out is deprecated**

- `UIRequiresFullScreen` is deprecated in iPadOS 26.
- Its replacements are `UISceneSizeRestrictions` and `prefersInterfaceOrientationLocked`.
- Source: https://developer.apple.com/documentation/bundleresources/information-property-list/uirequiresfullscreen

**Layout**

- Use a three-column `NavigationSplitView`: servers/projects → sessions → transcript.
- On regular widths, add an inspector for diffs and files.
- Collapse cleanly to a stack in compact widths and on the iPhone Duo's cover screen.
- The scene life cycle is required with the iOS 27 SDK anyway (§1.4).

### 5.8 Mac and visionOS

**Mac: ship "Designed for iPad" on Apple silicon Macs.** It needs no extra target. It is on by default: the App Store makes compatible iOS apps available on Apple silicon Macs unless you opt out in App Store Connect (https://developer.apple.com/documentation/apple-silicon/running-your-ios-apps-in-macos; https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-of-iphone-and-ipad-apps-on-macs-with-apple-silicon).

- Live Activities and ActivityKit are unavailable on macOS (`@available(macOS, unavailable)` in the SDK).
- `BGContinuedProcessingTask` is marked unavailable on macOS and Mac Catalyst in its Objective-C header. An iPad app running on a Mac should not expect it either. The macOS 27 SDK's `BackgroundTasks.tbd` exports `BGTaskScheduler`, `BGProcessingTask` and `BGAppRefreshTask` for Mac Catalyst but no `BGContinuedProcessingTask` classes (`MacOSX.sdk/System/Library/Frameworks/BackgroundTasks.framework/BackgroundTasks.tbd`), although Apple's documentation page lists Mac Catalyst 26.0. Gate the feature at run time.
- Move to Mac Catalyst only if Mac users ask for it. opencode already ships its own desktop app (`packages/desktop`) and web UI, so a native Mac client is low priority.

**visionOS: ship the compatible iPad app.**

- The visionOS 27 SDK has **no ActivityKit**, and `BGContinuedProcessingTask` is unavailable there.
- WidgetKit, Speech, FoundationModels, AppIntents and LocalAuthentication do exist (local `xros` SDK).
- A native visionOS target would be cheap for the SwiftUI views, but adds testing cost with little benefit. Not in v1.

### Alternatives and risks

**Alternatives**

- Pushes that carry only an ID (ntfy style).
- Local Push Connectivity on the LAN.
- Polling through background refresh, which is not reliable.

**Risks**

- **The relay:** operating cost, abuse protection, key rotation, and an accurate App Privacy label. Apple counts data as collected when it leaves the device and you can access it for longer than it takes to serve the request in real time, so assess what the relay stores, such as device tokens and pairing records, against that definition (https://developer.apple.com/app-store/app-privacy-details/) (corrected 2026-10-15).
- **Live Activity budgets.**
- **Unlocked Keychain items:** items accessible after first unlock are readable while the device is locked, an accepted trade-off.

---

## 6. SSH port forwarding inside the app

**Recommendation for v1.x, not v1.0:** an in-app tunnel built on **Citadel 0.12.1**.

- Citadel: 2026-04-04, MIT, last push 2026-06-12, about 390 stars.
- It is built on a fork of swift-nio-ssh, not on **apple/swift-nio-ssh 0.15.0** (2026-07-28, Apache-2.0). Citadel 0.12.1 pins `github.com/Wellz26/swift-nio-ssh` 0.3.4..<0.4.0, a contributor's fork of the author's own fork, Joannis/swift-nio-ssh (https://github.com/orlandos-nl/Citadel/blob/0.12.1/Package.swift) (corrected 2026-10-15). The apple/swift-nio-ssh notes below describe the upstream design; the fork also has the Secure Enclave key initializer.
- Sources: https://github.com/orlandos-nl/Citadel; https://github.com/apple/swift-nio-ssh

### What each library provides

**swift-nio-ssh**

- "Direct and reverse TCP port forwarding".
- "Modern cryptographic primitives only: Ed25519 and ECDSA over the major NIST curves (P256, P384, P521)…, AES-GCM…, x25519". There is no RSA.
- `NIOSSHPrivateKey(secureEnclaveP256Key:)` exists on Darwin (https://github.com/apple/swift-nio-ssh/blob/main/Sources/NIOSSH/Keys%20And%20Signatures/NIOSSHPrivateKey.swift).

**Citadel adds**

- An async client.
- `createDirectTCPIPChannel` for forwarding.
- Remote port forwarding, jump hosts and SFTP.
- RSA, DH group 14 and AES-CTR for older servers.
- An OpenSSH private-key parser with bcrypt KDF and `aes128-ctr`/`aes256-ctr` encryption (https://github.com/orlandos-nl/Citadel/blob/main/Sources/Citadel/OpenSSHKey.swift).
- Its README example uses `hostKeyValidator: .acceptAnything()` with the warning "it's insecure". **Never ship that.**

### Design

**Tunnel**

1. Open one SSH connection to the host.
2. Start a SwiftNIO listener (NIOTransportServices) on `127.0.0.1:<ephemeral port>`.
3. Pair each accepted connection with a `direct-tcpip` channel to `127.0.0.1:<opencode port>` on the remote machine.
4. Point URLSession and the WebSocket at `http://127.0.0.1:<local port>`. This is an IP literal, so `NSAllowsLocalNetworking` covers it. TN3179 defines the local network as networks on broadcast-capable interfaces, and loopback has no `BROADCAST` flag (`ifconfig lo0` shows `UP,LOOPBACK,RUNNING,MULTICAST`), so no local network prompt is expected (https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

**Lifecycle**

- Send keepalives.
- When the app goes to the background, the tunnel dies. On returning to the foreground, rebuild the tunnel first, then reconnect the event stream and resync.

### Keys

- **Default:** ed25519 generated with CryptoKit (`Curve25519.Signing`). Show the `ssh-ed25519 …` line to copy into `authorized_keys`.
- **Option:** a non-exportable **Secure Enclave P-256** key (`ecdsa-sha2-nistp256`).
- **Import:** OpenSSH keys through Citadel's parser.
- Store keys in the Keychain with access control (§5.6).
- **Host keys:** trust on first use, show the SHA256 fingerprint, pin it per host and warn loudly if it changes.

### Alternatives

| Option | Status |
|---|---|
| Use swift-nio-ssh directly | More code to write; no RSA |
| libssh2 wrappers: Shout (0.5.7, last push 2024), SwiftSH (0.1.2, 2021), NMSSH (2.3.1, 2018) | Stale |
| Blink Shell's stack | GPL-3.0, so unusable in a closed-source app |

### Risks

- **Citadel has a small maintainer base.** Pin versions and wrap it behind a `Tunnel` protocol. Its SSH layer is a personal fork of swift-nio-ssh (see above), so review that fork's changes on every upgrade.
- **The tunnel dies when the app is suspended.**
- **Users must already have SSH access** to the host.

---

## 7. Tailscale

### Recommendation for v1

Support the **official Tailscale iOS app**, combined with **`tailscale serve`** on the developer's machine:

- **HTTPS with a valid certificate on `*.ts.net`, so no ATS exceptions are needed.**
- **opencode can stay bound to `127.0.0.1`**, because Serve forwards to it. The port is 49374 for the managed service, or the port of `serve` (01 §2.3).
- Serve requires HTTPS to be enabled for the tailnet (https://tailscale.com/kb/1312/serve). Serve proxies through Go's `httputil.ReverseProxy` (https://github.com/tailscale/tailscale/blob/main/ipn/ipnlocal/serve.go), which flushes `text/event-stream` responses immediately and passes WebSocket upgrades through (`flushInterval` and `handleUpgradeResponse` in https://github.com/golang/go/blob/master/src/net/http/httputil/reverseproxy.go). Still test it end to end.

Also accept plain `http://100.x.y.z:port` (covered by `NSAllowsLocalNetworking`) for users who bind to `0.0.0.0`.

**Reachability.** Detect it with `GET /api/info`. On failure, show "Is Tailscale connected?" with a link that opens the Tailscale app.

### Later option: embedded TailscaleKit (libtailscale)

**What it is**

- A C library that "embeds Tailscale into a process… entirely from userspace". BSD-3, last push 2026-10-14, **no tagged releases** (https://github.com/tailscale/libtailscale).
- Its Swift framework, TailscaleKit, is "Swift 6 compliant". It is an Xcode project, not yet a Swift package; SwiftPM support is an open pull request (https://github.com/tailscale/libtailscale/pull/55) (corrected 2026-10-15).
- It requires Xcode 16.1 or later and builds frameworks with `make ios`, so it needs the Go toolchain.
- The README says the iOS framework without simulator slices "is suitable for app-store submissions". An open pull request reports that uploads fail with ITMS-91053 because no slice carries a privacy manifest, and adds one (https://github.com/tailscale/libtailscale/pull/57) (corrected 2026-10-15).

**How it works**

- Nodes are authorized with an auth key or interactive login (the `browseToURL` flow).
- URLSession traffic goes through a **local SOCKS5 proxy**: `URLSessionConfiguration.proxyVia(node)` sets `ProxyConfiguration(socksv5Proxy:)` with credentials (iOS 17+).
- Sources: https://github.com/tailscale/libtailscale/blob/main/swift/README.md; https://github.com/tailscale/libtailscale/blob/main/swift/TailscaleKit/URLSession%2BTailscale.swift

**Why it might be worth it**

- It does not need the Tailscale app, so it coexists with a corporate VPN (iOS allows one VPN at a time).

**Device counts**

- Each install becomes a tailnet device.
- The Personal plan is free "for up to 6 users" with "unlimited user devices" (https://tailscale.com/pricing).

**App Store**

- Guideline 5.4 governs "apps offering VPN services". They "must utilize the NEVPNManager API and may only be offered by developers enrolled as an organization" (https://developer.apple.com/app-store/review/guidelines/).
- An in-process tsnet node offers no system VPN, so 5.4 should not apply. **A precedent exists.** Tunnelless (Indiagram LLC, released 2026-08-31 for iPhone, iPad and Mac) runs a userspace tailnet node inside the app behind a local SOCKS5 proxy, with no VPN profile and no Tailscale app (https://apps.apple.com/us/app/tunnelless/id6805551069). Its developer says it is built on TailscaleKit (https://github.com/tailscale/libtailscale/pull/57) (corrected 2026-10-15).
- Guideline 4.2.3(i) says an app "should work on its own without requiring installation of another app to function" (same guidelines URL). The v1 plan should satisfy it, because the official Tailscale app is only one of several connection paths.

**Risks**

- Binary size, memory and battery cost of the Go runtime. One bound on size: the whole Tunnelless app is 23.4 MB (`fileSizeBytes` from https://itunes.apple.com/lookup?id=6805551069). Memory and battery costs are [unconfirmed: no published measurements in the libtailscale README, issues or pull requests, or in the App Store listing].
- The node dies when the app is suspended.
- There are no releases to pin.
- App Review risk, as above.

### Other tunnels

- **Cloudflare Tunnel or Access, and ngrok:** HTTPS URLs. They may need custom headers, such as Access service tokens, so support per-endpoint custom headers (03 §4).
- **OpenTunnel** is opencode's own zero-config HTTPS path (01 §2.7).

---

## 8. Project setup and tooling

### 8.1 Project generation

**Recommendation: XcodeGen 2.46.0** (2026-07-16, MIT; already installed locally; https://github.com/yonaskolb/XcodeGen).

- `project.yml` is easy for people and agents to edit as text.
- Use `syncedFolder` sources (Xcode 16 synchronized folders, supported since 2.44.0). Adding a file then needs no regeneration and causes no `pbxproj` churn.
- Package traits are supported (2.46.0).
- **Caveat:** the unreleased "Next Version" adds an `xcode27_0` project format (`objectVersion = 110`). It also fixes missing `dstPath` values that made "Xcode 27.2 project conversion … fail" (CHANGELOG, https://github.com/yonaskolb/XcodeGen/blob/HEAD/CHANGELOG.md). Pin the version, add the generated `.xcodeproj` to `.gitignore`, generate it in a bootstrap script and in CI, and upgrade when 2.47 ships.

**Alternatives**

- **Tuist 4.x** (CLI under MIT; the `server/` directory is MPL-2.0; 4.214 canaries were released daily as of 2026-10-15; https://github.com/tuist/tuist). It is more powerful, with caching and a module graph, but needs mise to install and adds a dependency on its paid server features.
- **A plain Xcode project with buildable folders.** It is the simplest, but targets, settings and extensions still live in `project.pbxproj`, which agents edit unreliably.

### 8.2 Modules

Use one local SPM package, `OpencodeKit`, with these targets:

| Target | Contents | Isolation |
|---|---|---|
| `OCModels` | Domain models and tolerant decoding | nonisolated |
| `OCClient` | REST, SSE and PTY clients, plus the resync engine | nonisolated, actors |
| `OCTunnel` | SSH and, later, Tailscale | nonisolated |
| `OCRender` | Markdown blocks, highlighting, diffs | nonisolated, `@concurrent` |
| `OCDesign` | Design system, Liquid Glass components | MainActor |
| Feature targets | `SessionsFeature`, `TranscriptFeature`, `ComposerFeature`, `TerminalFeature`, `SettingsFeature` | MainActor |
| `OCShared` | App Group store and Keychain, used by the extensions | – |

**XcodeGen targets:**

- the app;
- `NotificationService` (Notification Service Extension);
- `Widgets` (widgets, Live Activities and controls);
- optionally `IntentsExtension`.

**Rules**

- Extensions link only `OCShared` and `OCModels`.
- Keep macro-heavy dependencies to a minimum, because swift-syntax builds are slow.

### 8.3 Testing

**Unit tests: Swift Testing** (Swift 6.4 adds issue severity, `Test.cancel` and XCTest interop).

**Snapshot tests: swift-snapshot-testing 1.19.6** (2026-09-21, MIT; works inside `@Test` functions with `assertSnapshot`; https://github.com/pointfreeco/swift-snapshot-testing).

- Pin one simulator device and OS for references. Locally only the iOS 26.5 runtime is installed. Either standardise on it or install the iOS 27 runtime, then keep CI identical.
- Optional extras:
  - SnapshotPreviews v0.20.0 (now at `getsentry/SnapshotPreviews`, MIT), which snapshots Xcode previews;
  - AccessibilitySnapshot 0.13.1 (Apache-2.0).

**Protocol tests**

- Replay recorded SSE streams and WebSocket sessions through a `URLProtocol` stub. Cover reconnects, `server.connected` resyncs and overflow closes.
- Control time in backoff and watchdog tests with swift-clocks 1.1.1 (MIT).

**Contract tests**

- In CI on macOS, start real `opencode serve` instances: the minimum supported V2, the latest V2 and one V1 build, so the upgrade prompt is tested too.
- Run the client's API suite against each.

**UI tests:** a handful of XCUITest smoke flows (pair, send a prompt, approve, open a terminal) against the mock server.

### 8.4 CI and distribution

**CI**

- **GitHub Actions** with `runs-on: xcode-27`, a public preview image. Since 2026-09-16 it runs macOS 27 (https://github.com/actions/runner-images/issues/14404).
- Older images are `macos-26` with Xcode 26.6 as the default (https://github.com/actions/runner-images).

**Delivery**

- **Xcode Cloud** for archiving and TestFlight. Membership includes 25 compute hours a month. More costs $49.99 a month for 100 hours, $99.99 for 250, $399.99 for 1,000 and $3,999.99 for 10,000 (https://developer.apple.com/xcode-cloud/).
- **Or fastlane 2.241.1** (2026-10-15, MIT, active) with an App Store Connect API key.

**TestFlight** (https://developer.apple.com/testflight/)

- Up to 100 internal and 10,000 external testers.
- The first external build needs Beta App Review.
- Public links are available.
- Builds expire after 90 days. The TestFlight page doesn't say so, but App Store Connect Help does (https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview).

**App Review**

- Provide "an active demo account or fully-featured demo mode" and "enable backend services" (https://developer.apple.com/app-store/review/guidelines/). In practice, run a demo opencode V2 server behind HTTPS (OpenTunnel or your own domain), with a pairing link in the review notes and a capped model budget.
- Guideline 4.2.7 (remote desktop clients) covers apps that mirror specific software from a host, and requires those to connect only to a user-owned computer over the local network (https://developer.apple.com/app-store/review/guidelines/). A client that renders the server's API natively should not fall under it, but how reviewers treat the terminal view is [unconfirmed: no guideline text or published review decision covers API clients].
- 03 §4.4 has a full checklist.

### Risks

- **XcodeGen and Xcode 27 format drift.**
- **Snapshot flakiness across OS versions:** pin one simulator.
- **Xcode Cloud hours:** 25 hours goes quickly with UI tests, so keep heavy tests on GitHub Actions.

---

## 9. On-device AI: Apple's Foundation Models framework

**Availability**

- iOS, iPadOS, macOS and visionOS 26+ (watchOS from 27).
- Apple Intelligence devices only: iPhone 15 Pro and later, M1 or later iPads and Macs, and iPad mini (A17 Pro).
- Apple Intelligence must be turned on, the language must be supported, and it is not available in mainland China.
- Sources: https://support.apple.com/en-us/121115; SDK.

**Models** (https://machinelearning.apple.com/research/introducing-third-generation-of-apple-foundation-models)

- **AFM 3 Core:** about 3B parameters.
- **AFM 3 Core Advanced:** 20B sparse.
- **Private Cloud Compute model:** "much bigger", with a 32K-token context and reasoning levels.

**On-device context**

- 4,096 tokens on iOS 26.
- On iOS 27, the WWDC26 sample prints `contextSize` 8192, but Apple's PCC article still says 4K (https://developer.apple.com/videos/play/wwdc2026/241/).
- **Budget for 4K and read `contextSize` at runtime.**

**Private Cloud Compute for third-party apps** (iOS 27, `PrivateCloudComputeLanguageModel`, confirmed in the SDK)

- Requires the Small Business Program, fewer than 2 million first-time downloads, and the `com.apple.developer.private-cloud-compute` entitlement.
- Each user has a daily quota, and the API reports `quotaLimitReached`.
- Sources: https://developer.apple.com/private-cloud-compute/; https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute

**Limits**

- `rateLimited` errors occur "only… if your app is running in the background".
- Guardrails can be `.default` or `.permissiveContentTransformations`.
- The acceptable-use requirements apply (https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/).
- Custom adapters were deprecated in 26.4 and are obsoleted in 27.0 (SDK).

**Uses for this app**

| Use | Verdict |
|---|---|
| **Provisional or offline session titles** | Build it. opencode already titles sessions on the server with its `small_model` (https://opencode.ai/docs/config/). Use on-device titles only before the server's title arrives or when the server is offline. |
| **Voice-command parsing** | Build it. Map `SpeechTranscriber` text into a `@Generable` enum: approve, deny, stop, new session, switch session, switch model, open file. Send everything else as a prompt. Keep a keyword grammar as the fallback. |
| **TL;DR of long tool output or diffs** | Optional. 4K tokens is roughly 12–16 KB of English and less of code, so you must chunk the input. Always show deterministic summaries first: diffstat, exit code, first error lines. |
| **Notification and Live Activity text** | Don't. Text produced in the background is rate-limited, and extension support is [unconfirmed: the iOS 27 SDK marks no Foundation Models API unavailable to extensions, and one developer reports it working in a widget extension (https://developer.apple.com/forums/thread/840737), but Apple has said nothing]. Use templates, or let the server's model write the text. |

**Degrading gracefully**

- Put the model behind one capability service with four states: on-device, PCC, server, none.
- Hide AI features when nothing is available.
- Handle both `GenerationError` (iOS 26) and `LanguageModelError` (iOS 27).

---

## 10. Consolidated risk register

| # | Risk | Likelihood and impact | Mitigation |
|---|---|---|---|
| 1 | The opencode API changes (V2 releases about 6 times a week; V1 frozen; the spec carries no API version) | High, high | Hand-written tolerant models with `.unknown` cases. Minimum-version check via `/api/info`. Contract tests against several server versions. Spec diffs in CI. |
| 2 | Push needs a plugin and a hosted relay (operations, security, privacy) | Certain, medium | Open-source the relay. Seal payloads with HPKE. Rate-limit per device. Offer an ID-only mode. Send actions over the direct path. |
| 3 | No streaming in the background | Certain, medium | Pushes and Live Activities. Fast resync on returning to the foreground. Possibly a `BGContinuedProcessingTask` experiment. |
| 4 | Plain HTTP on the LAN exposes the credential | Medium, high | Pairing tokens. An "unencrypted" badge. Prefer OpenTunnel or Tailscale Serve over HTTPS. |
| 5 | The local network prompt is denied or missed | Medium, medium | Explain before the first LAN connection. Detect `.localNetworkDenied`. Offer the Tailscale or OpenTunnel paths. |
| 6 | Pre-1.0 or single-maintainer libraries (Textual, Runestone, Citadel, Neon, TailscaleKit) | Medium, medium | Protocol boundaries. Pinned versions. Be ready to fork. |
| 7 | iOS 27 SDK behaviour changes (Liquid Glass mandatory, `@State` macro, scene life cycle, launch screen) | Certain, low | Start on Xcode 27. Test on iOS 26 and 27 devices. |
| 8 | XcodeGen lags the Xcode 27 project format | Medium, low | Pin the version and watch for 2.47. Switching to Tuist or a plain project is cheap if needed. |
| 9 | Live Activity budgets and limits (4 KB, 8–12 h) | Medium, low | Priority 5 for routine updates. Coarse state only. End the activity on idle. |
| 10 | Transcript performance on very long sessions | Medium, medium | Per-message models, frozen blocks, paging. `UICollectionView` as the fallback. |
| 11 | Foundation Models availability is fragmented | Certain, low | Optional features only, with deterministic fallbacks. |
| 12 | App Review (demo server, local network, possibly embedded Tailscale) | Medium, medium | A hosted demo server. Clear permission strings. Keep embedded Tailscale out of v1. |
| 13 | Competition from the official opencode iOS app (TestFlight beta announced 2026-10-08, per 03) | Certain, product risk | Out of scope for the stack. Differentiate on iPad, approvals and push. |

## 11. Open questions

**Protocol and transport**

- Does `tailscale serve` pass SSE through unbuffered, and does it proxy WebSocket upgrades? The source says yes (§7); test with opencode V2.
- Do OpenTunnel and corporate proxies keep long-lived SSE connections open? Test idle timeouts against the 15 s heartbeat.

**Apple platform behaviour**

- The exact behaviour of `defaultScrollAnchor(.bottom, for: .sizeChanges)` when the user has scrolled up. Prototype it on device.
- Whether `SpeechAnalyzer` requires speech-recognition authorization (the evidence in §4.3 says microphone permission only), and which locales `SpeechTranscriber` supports on iOS 27.
- Whether URLSession delays the first SSE bytes for content sniffing (§2.3).
- The real-world Live Activity update budget with `NSSupportsLiveActivitiesFrequentUpdates`.
- Whether Foundation Models works in app extensions (one developer reports it working in a widget; §9), and the on-device context size on iOS 27 for each model variant.

**App Review**

- App Review's position on apps that embed libtailscale. Tunnelless is one approved example (§7).
- Whether App Review accepts `BGContinuedProcessingTask` used to follow an agent run.

**Tooling**

- When XcodeGen will release Xcode 27 project-format support (2.47).
- Whether Runestone gets a 0.6 or 1.0 release.

---

## Appendix A. Info.plist keys, entitlements and capabilities

### Info.plist keys for the app target

| Key | Value or purpose |
|---|---|
| `UILaunchScreen` | Required with the iOS 27 SDK |
| `UIApplicationSceneManifest` | The scene life cycle is required |
| `NSAppTransportSecurity` | `NSAllowsLocalNetworking = YES`. Optionally `NSExceptionDomains` for `ts.net` if you allow plain HTTP to MagicDNS names. |
| `NSLocalNetworkUsageDescription` | Needed for LAN URLs and Bonjour |
| `NSBonjourServices` | Only if browsing: `_http._tcp` (V1 `--mdns`) and/or `_opencode._tcp` (our own plugin) |
| `NSCameraUsageDescription` | QR pairing and photo attachments |
| `NSMicrophoneUsageDescription` | Voice input |
| `NSSpeechRecognitionUsageDescription` | Safe to include. Needed for the `SFSpeechRecognizer` fallback. |
| `NSFaceIDUsageDescription` | App lock and step-up authentication |
| `NSSupportsLiveActivities` | `YES` |
| `NSSupportsLiveActivitiesFrequentUpdates` | `YES` |
| `UIBackgroundModes` | `remote-notification` (background pushes). Apple's material names no `UIBackgroundModes` value for `BGContinuedProcessingTask`. |
| `BGTaskSchedulerPermittedIdentifiers` | Only for `BGContinuedProcessingTask` experiments. List identifiers prefixed with the bundle ID; a wildcard form, `<bundle ID>.<context>.*`, is allowed (`BGTaskRequest.h` in the SDK; https://developer.apple.com/videos/play/wwdc2025/227/). Background GPU use also needs the `com.apple.developer.background-tasks.continued-processing.gpu` entitlement (SDK). |

### Entitlements and capabilities

| Item | Notes |
|---|---|
| `aps-environment` | Push Notifications |
| App Groups | Shared store for the app and its extensions |
| Keychain Sharing | One access group for the app and its extensions |
| `com.apple.developer.usernotifications.time-sensitive` | Time-sensitive permission alerts |
| Live Activities broadcast | Only if you use channels. Enabled on developer.apple.com, not in Xcode. |
| `com.apple.developer.networking.networkextension` (`app-push-provider`) | Only for Local Push Connectivity. Must be requested. |
| `com.apple.developer.private-cloud-compute` | Only if PCC is used |

### Extensions

- Notification Service Extension
- Widget extension (widgets, Live Activities, controls)
- Optionally an App Intents extension

## Appendix B. Library versions checked on 2026-10-15 (GitHub API)

| Library | Latest | Date | License | Notes |
|---|---|---|---|---|
| apple/swift-openapi-generator | 1.14.1 | 2026-10-14 | Apache-2.0 | |
| apple/swift-openapi-runtime | 1.13.1 | 2026-10-15 | Apache-2.0 | |
| apple/swift-openapi-urlsession | 1.3.2 | 2026-09-30 | Apache-2.0 | |
| mattt/EventSource | 1.5.1 | 2026-08-17 | MIT | |
| launchdarkly/swift-eventsource | 3.4.0 | 2026-09-29 | Apache-2.0 | |
| Recouse/EventSource | 0.1.9 | 2026-08-27 | MIT | |
| daltoniam/Starscream | 4.0.8 | 2024-03-07 | Apache-2.0 | Stale |
| gonzalezreal/textual | 0.5.0 | 2026-06-15 | MIT | iOS 18+ |
| gonzalezreal/swift-markdown-ui | 2.4.1 | 2024-10-13 | MIT | Maintenance mode |
| LiYanan2004/MarkdownView | 3.0.0 | 2026-07-05 | MIT | |
| Lakr233/MarkdownView | 4.8.3 (tag) | 2026-10-08 | MIT | The last GitHub release object is 4.1.7 (2026-07-16); SwiftPM resolves tags (corrected 2026-10-15) |
| swiftlang/swift-markdown | 0.9.0 | 2026-09-21 | Apache-2.0 | |
| tree-sitter/swift-tree-sitter | 0.10.0 | 2026-03-18 | BSD-3 | A stray, older `0.25.0` tag outranks it in SwiftPM; pin exactly |
| tree-sitter/tree-sitter | v0.27.1 | 2026-10-08 | MIT | |
| slsrepo/Neon (formerly ChimeHQ) | 0.6.0 | 2024-01-13 | BSD-3 | |
| simonbs/Runestone | 0.5.2 | 2026-03-25 | MIT | |
| raspu/Highlightr | 2.3.0 | 2025-06-18 | MIT | Unmaintained per README |
| appstefan/HighlightSwift | v1.1.0 | 2024-06-25 | MIT | |
| JohnSundell/Splash | 0.16.0 | 2021-06-14 | MIT | Stale |
| krzyzanowskim/STTextView | 2.4.1 | 2026-09-08 | GPL-3.0 or commercial | |
| mchakravarty/CodeEditorView | tag 0.16.0 | pushed 2026-10-05 | Apache-2.0 | |
| CodeEditApp/CodeEditSourceEditor | 0.15.2 | 2025-09-16 | MIT | |
| migueldeicaza/SwiftTerm | v1.99.0 | 2026-10-08 | MIT | |
| ghostty-org/ghostty (libghostty-vt) | tag v1.3.1 | – | MIT | |
| mgriebling/SwiftMath | 1.7.3 | 2025-08-03 | MIT | |
| kostub/iosMath | 2.5.0 | 2026-07-13 | MIT | |
| colinc86/LaTeXSwiftUI | v2.0.0 | 2026-04-03 | MIT | |
| argmaxinc/argmax-oss-swift (WhisperKit) | v1.1.1 | 2026-10-08 | MIT | |
| orlandos-nl/Citadel | 0.12.1 | 2026-04-04 | MIT | Depends on the Wellz26/swift-nio-ssh fork (0.3.x), not apple/swift-nio-ssh |
| apple/swift-nio-ssh | 0.15.0 | 2026-07-28 | Apache-2.0 | |
| tailscale/libtailscale (TailscaleKit) | no releases or tags | pushed 2026-10-14 | BSD-3 | Xcode project, no SwiftPM yet (PR #55) |
| yonaskolb/XcodeGen | 2.46.0 | 2026-07-16 | MIT | |
| tuist/tuist | 4.214.0 canaries | 2026-10-15 | MIT (CLI) | |
| pointfreeco/swift-snapshot-testing | 1.19.6 | 2026-09-21 | MIT | |
| getsentry/SnapshotPreviews | v0.20.0 | 2026-10-08 | MIT | |
| cashapp/AccessibilitySnapshot | 0.13.1 | 2026-09-17 | Apache-2.0 | |
| pointfreeco/swift-clocks | 1.1.1 | 2026-08-27 | MIT | |
| fastlane/fastlane | 2.241.1 | 2026-10-15 | MIT | |
| square/Valet | 5.1.1 | 2026-09-09 | Apache-2.0 | |
| kishikawakatsumi/KeychainAccess | v4.2.2 | 2021-03-01 | MIT | Stale |
| anomalyco/opencode | v1.19.1 (V1 GitHub release); v2.0.30 (tag) | 2026-10-15 | MIT | |

## Verification pass (2026-10-15)

This pass resolved the 31 claims the first draft tagged as unverified, plus the legend line that explained the tag. The ATS claim held two statements, so it gets two rows (9a, 9b). Outcomes: **19 verified, 5 corrected, 8 unconfirmed, 0 removed.** Rows U1–U8 log untagged errors and additions found on the way. Rows S1–S6 check claims that the product spec and architecture took from this report.

Method: SDK interfaces and headers in the local Xcode 27.0 (27A266a), `xcodegen --version` (2.46.0), the GitHub API through `gh api`, Apple's documentation JSON (`https://developer.apple.com/tutorials/data/documentation/<path>.json`), direct fetches of primary pages, and seven web searches. Nothing was built.

`$SDK` below stands for `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk`.

| # | Claim (short) | Outcome | Evidence (URL, SDK path or command) |
|---|---|---|---|
| 0 | Legend line for the "unverified" tag | Updated; not a claim | – |
| 1 | iOS 27.1 shipped only for the iPhone Duo (§1.1) | VERIFIED | appledb `osFiles/iOS/24x - 27.x/24A94425.json` (only iPhone19,4) and `deviceFiles/iPhone/iPhone19,4.json` (iPhone Duo) in https://github.com/littlebyteorg/appledb; https://en.wikipedia.org/wiki/IOS_27; https://www.macworld.com/article/3237296/ios-27-2-beta-is-out-now-skipping-over-ios-27-1.html |
| 2 | Apple reduced guardrail false positives in 26.4 (§1.3) | VERIFIED | https://developer.apple.com/documentation/updates/foundationmodels (February 2026 entries) |
| 3 | `SWIFT_APPROACHABLE_CONCURRENCY` does not apply in the Swift 6 mode (§1.6) | CORRECTED: its `Condition` only gates the option's own command-line arguments, of which it has none; the two dependent features still follow its value | `/Applications/Xcode.app/Contents/SharedFrameworks/SwiftBuild.framework/Versions/A/PlugIns/SWBBuildService.bundle/Contents/PlugIns/XCBSpecifications.ideplugin/Contents/Resources/Swift.xcspec` (lines 565–571, 906, 925); https://github.com/swiftlang/swift-build/blob/main/Sources/SWBCore/SpecImplementations/PropertyDomainSpec.swift (lines 333, 1404–1406) |
| 4 | `text/event-stream` and `nosniff` stop URLSession's sniffing buffer (§2.3) | UNCONFIRMED | https://developer.apple.com/forums/thread/64875 (512-byte buffer; only `application/json` and `application/octet-stream` reported to avoid it); two web searches |
| 5 | `AsyncBytes.lines` may skip empty lines (§2.3) | VERIFIED; wording tightened to "drops" | https://github.com/LaughingJackalope/macos-skills/pull/2; https://github.com/s-e-r-n/door-into-summer/pull/15; https://github.com/Ichigo3766/Open-Relay/issues/219 |
| 6 | `beginBackgroundTask` grants about 30 s (§2.6) | VERIFIED | https://developer.apple.com/forums/thread/85066 (Apple DTS) |
| 7 | App Review's view of `BGContinuedProcessingTask` for agent runs (§2.6) | UNCONFIRMED; Apple's usage guidance added | https://developer.apple.com/videos/play/wwdc2025/227/; https://developer.apple.com/app-store/review/guidelines/ (no entry) |
| 8 | `NSAllowsArbitraryLoads` needs an App Review justification (§2.8) | VERIFIED | https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloads |
| 9a | ATS does not apply to Network framework (§2.8) | VERIFIED | https://developer.apple.com/documentation/security/preventing-insecure-network-connections |
| 9b | ATS covers `URLSessionWebSocketTask` (§2.8) | UNCONFIRMED | Same page and https://developer.apple.com/documentation/foundation/urlsessionwebsockettask say nothing explicit |
| 10 | Binary size per tree-sitter grammar (§3.3) | UNCONFIRMED; WASM sizes added as a guide | `gh api repos/tree-sitter/tree-sitter-<lang>/releases/latest` (asset sizes) |
| 11 | CodeEditSourceEditor "appears to be macOS-oriented" (§3.4) | CORRECTED: macOS only | https://github.com/CodeEditApp/CodeEditSourceEditor/blob/0.15.2/Package.swift |
| 12 | Engine behind LiYanan2004/MarkdownView's `LaTeX` trait (§3.7) | VERIFIED; resolved: SwiftMath | https://github.com/LiYanan2004/MarkdownView/blob/3.0.0/Package.swift |
| 13 | LaTeXSwiftUI's rendering engine (§3.7) | VERIFIED; resolved: MathJax in JavaScriptCore (MathJaxSwift), SVG drawn by SwiftDraw | https://github.com/colinc86/LaTeXSwiftUI; https://github.com/colinc86/MathJaxSwift |
| 14 | No mature native Mermaid renderer is known (§3.7) | CORRECTED: beautiful-mermaid-swift 1.0.4 exists, young and partial | https://github.com/lukilabs/beautiful-mermaid-swift; `gh api repos/lukilabs/beautiful-mermaid-swift/releases` |
| 15 | Community reports of `LazyVStack` jumps (§3.8) | VERIFIED | https://github.com/kean/Nuke/issues/721 |
| 16 | `TextEditor` misbehaves with IME input or undo (§4.1) | UNCONFIRMED | iOS 26.x and 27.0 release notes (https://developer.apple.com/documentation/ios-ipados-release-notes); `gh api search/issues` |
| 17 | Whether `SpeechAnalyzer` needs speech-recognition authorization (§4.3) | VERIFIED, indirectly: microphone permission only | https://developer.apple.com/videos/play/wwdc2025/277/; Firefox for iOS `SpeechAnalyzerEngine.swift` versus `SFSpeechRecognizerEngine.swift` (https://github.com/mozilla-mobile/firefox-ios); https://developer.apple.com/documentation/speech/speechanalyzer |
| 18 | How far Siri's language features use these intents (§5.5) | VERIFIED; resolved: only intents that adopt an App schema | https://developer.apple.com/documentation/appintents/app-schema-domains; https://developer.apple.com/documentation/appintents/making-actions-and-content-discoverable-by-apple-intelligence |
| 19 | Whether the web UI deep-links to sessions (§5.5) | VERIFIED; resolved: yes | https://github.com/anomalyco/opencode/blob/dev/packages/app/src/shell/routes/routes.tsx |
| 20 | iOS 18's "Require Face ID" app lock (§5.6) | VERIFIED | https://support.apple.com/guide/iphone/lock-or-hide-an-app-iph00f208d05/ios |
| 21 | "Designed for iPad" is on by default (§5.8) | VERIFIED | https://developer.apple.com/documentation/apple-silicon/running-your-ios-apps-in-macos |
| 22 | Whether an iPad app on a Mac gets `BGContinuedProcessingTask` (§5.8) | VERIFIED; resolved: no | `MacOSX.sdk/System/Library/Frameworks/BackgroundTasks.framework/BackgroundTasks.tbd` (no `BGContinuedProcessing*` exports); `$SDK/System/Library/Frameworks/BackgroundTasks.framework/Headers/BGTask.h:127` |
| 23 | Whether relay privacy claims survive App Review (§5 risks) | CORRECTED: replaced with Apple's App Privacy definition of "collect" | https://developer.apple.com/app-store/app-privacy-details/ |
| 24 | Loopback triggers no local network prompt (§6) | VERIFIED, from TN3179's definition | https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy; `ifconfig lo0` |
| 25 | Whether `tailscale serve` passes SSE and WebSockets unbuffered (§7) | VERIFIED from source | https://github.com/tailscale/tailscale/blob/main/ipn/ipnlocal/serve.go; https://github.com/golang/go/blob/master/src/net/http/httputil/reverseproxy.go |
| 26 | No App Store precedent for an embedded tsnet node (§7 and summary table) | CORRECTED: Tunnelless, released 2026-08-31 | https://apps.apple.com/us/app/tunnelless/id6805551069; https://itunes.apple.com/lookup?id=6805551069; https://github.com/tailscale/libtailscale/pull/57 |
| 27 | Size, memory and battery cost of the Go runtime (§7) | UNCONFIRMED; a size bound added | https://itunes.apple.com/lookup?id=6805551069 (23.4 MB); libtailscale issues and pull requests |
| 28 | TestFlight builds expire after 90 days (§8.4) | VERIFIED | https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview |
| 29 | Guideline 4.2.7 should not apply to an API client (§8.4) | UNCONFIRMED; guideline scope summarized | https://developer.apple.com/app-store/review/guidelines/ |
| 30 | Whether Foundation Models works inside an extension (§9) | UNCONFIRMED | `$SDK/System/Library/Frameworks/FoundationModels.framework/Modules/FoundationModels.swiftmodule/arm64e-apple-ios.swiftinterface` (no extension restrictions); https://developer.apple.com/forums/thread/840737 |
| 31 | Info.plist rules for `BGContinuedProcessingTask` (Appendix A) | VERIFIED; resolved | `$SDK/System/Library/Frameworks/BackgroundTasks.framework/Headers/BGTaskRequest.h:161-164` and `BGTaskScheduler.h:76-90`; https://developer.apple.com/videos/play/wwdc2025/227/ |
| U1 | A 26.4 minimum excludes "about 1–2%" of users (§1.3) | CORRECTED: about 4–5% | TelemetryDeck JSON for the week of 2026-09-28, linked from https://telemetrydeck.com/survey/apple/iOS/minorSystemVersions/ and https://telemetrydeck.com/survey/apple/iOS/majorSystemVersions/ |
| U2 | Citadel is built on apple/swift-nio-ssh 0.15.0 (§6, summary table) | CORRECTED: it pins the Wellz26/swift-nio-ssh fork, 0.3.x | https://github.com/orlandos-nl/Citadel/blob/0.12.1/Package.swift; `gh api repos/Wellz26/swift-nio-ssh` |
| U3 | Lakr233/MarkdownView's latest version is 4.1.7 (§3.1, §3.3, Appendix B) | CORRECTED: tags reach 4.8.3 (2026-10-08) | `gh api repos/Lakr233/MarkdownView/tags` |
| U4 | Pinning swift-tree-sitter 0.10.0 (§3.3, Appendix B) | ADDED: a stray, older 0.25.0 tag wins SwiftPM resolution | `gh api repos/tree-sitter/swift-tree-sitter/compare/0.10.0...0.25.0` |
| U5 | TailscaleKit is a Swift package (§7) | CORRECTED: an Xcode project; SwiftPM support is an open pull request | https://github.com/tailscale/libtailscale/tree/main/swift; https://github.com/tailscale/libtailscale/pull/55 |
| U6 | TailscaleKit is "suitable for app-store submissions" (§7) | CORRECTED: needs a privacy manifest (ITMS-91053) | https://github.com/tailscale/libtailscale/pull/57 |
| U7 | `safeAreaBar` composer with `@FocusState` (§4.1) | ADDED: known issue 158720838, with no fix listed through 27.0 | https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26_1-release-notes |
| U8 | 26.4 `.userActivity` fix (§1.3); guideline 4.2.3(i) (§7); justification for `NSExceptionAllowsInsecureHTTPLoads` (§2.8) | ADDED | https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26_4-release-notes; https://developer.apple.com/app-store/review/guidelines/; https://developer.apple.com/documentation/security/preventing-insecure-network-connections |
| S1 | Versions: Textual 0.5.0, swift-markdown 0.9.0, Runestone 0.5.2, SwiftTerm 1.99.0, Citadel 0.12.1, GRDB 7.x, swift-snapshot-testing 1.19.6, swift-openapi-generator 1.14.1, XcodeGen 2.46.0 | VERIFIED. GRDB is v7.11.1 (2026-06-18). Pre-1.0: Textual, swift-markdown, Runestone, Citadel. One main maintainer: Textual, Runestone (3 commits since January 2025), SwiftTerm, Citadel, GRDB, XcodeGen. Team-backed: swift-markdown and swift-openapi-generator (Apple), swift-snapshot-testing (Point-Free) | `gh api repos/<owner>/<repo>/releases/latest`; commit authors since 2025-10-15 via `gh api "repos/<owner>/<repo>/commits?since=2025-10-15T00:00:00Z"`; `xcodegen --version` |
| S2 | Building with the iOS 27 SDK makes Liquid Glass, a launch screen and the scene life cycle mandatory | VERIFIED | https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility; https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes (168247372, 141837548) |
| S3 | iOS 26.4 is the right minimum | CORRECTED: defensible but thinly justified. The only 26.4 gains are Foundation Models `tokenCount(for:)`, the 26.4 model and guardrails (all optional features) and a `.userActivity` fix, at a cost of about 4–5% of users. Adoption: iOS 26 74.6% and iOS 27 16.3% (TelemetryDeck, end of September); iOS 27 4.4% (StatCounter via iOSRef, 2026-10-12); Apple has published no iOS 27 figure | SDK search for `iOS 26.4` availability; https://developer.apple.com/support/app-store/; https://iosref.com/ios-usage; rows 2 and U1 |
| S4 | `BGContinuedProcessingTask` (iOS 26), `SpeechAnalyzer` and `SpeechTranscriber` (iOS 26), `TextEditor` bound to `AttributedString` with custom attributes (iOS 26), `Observations` (SE-0475), CryptoKit HPKE (iOS 17), `textSelection` in iOS 27, push-to-start | VERIFIED. Notes: push-to-start needs iOS 17.2; the iOS 27 `textSelection` change is new behaviour for apps built with the iOS 27 SDK, not a new API | `$SDK/System/Library/Frameworks/BackgroundTasks.framework/Headers/BGTask.h:127`; `Speech.swiftinterface` lines 226–228 and 344–346 (`anyAppleOS 26`); `SwiftUI.swiftinterface:3893-3896`; `SwiftUICore.swiftinterface:11929, 12233`; `$SDK/usr/lib/swift/Observation.swiftmodule/arm64e-apple-ios.swiftinterface:142-143`; `CryptoKit.swiftinterface:669-670`; `ActivityKit.swiftinterface:127-132`; iOS 27 release notes (79770704) |
| S5 | An app can embed Tailscale without the Tailscale app, a precedent exists, and guideline 4.2.3(i) bars requiring another app | VERIFIED | Rows 26 and U6; https://github.com/tailscale/libtailscale/blob/main/swift/README.md; https://developer.apple.com/app-store/review/guidelines/ |
| S6 | A Cloudflare Worker's `fetch` can reach APNs over HTTP/2 | VERIFIED in practice; Cloudflare does not document it | https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns (HTTP/2 required); https://github.com/binochoi/native-push-sender (README: APNs works on Workers but not with Node's HTTP/1.1 `fetch`); https://github.com/akshitkrnagpal/edgepush (`packages/server/src/push/apns.ts`) |
