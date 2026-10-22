# Native opencode client for iOS and iPadOS: architecture and implementation plan

*Design proposal, 2026-10-15. It is based on research reports 01 to 07 and on the opencode V2 source at `d0732ea`. The source files read directly were `packages/client/src/solid/connection.ts`, `solid/data.ts`, `packages/app/src/servers/connect/pairing.ts`, `packages/core/src/bus.ts`, `packages/core/src/plugin/host.ts` and `packages/core/src/kv.ts`.*

## 0. Key decisions

1. **Support V2 only.** The minimum is 2.0.10, the first release with the audited contract. Pairing and credential features require 2.0.25 or later. A V1 server gets a dedicated "Upgrade to opencode 2" screen telling the user to run `opencode upgrade` (V1 1.19.0 or later is needed) and then `opencode upgrade --major`.
2. **Build the reliability core first.** Each server gets one `actor ServerConnection`. It owns one SSE stream, a watchdog on received bytes, backoff with jitter, and closes the stream when the app goes to the background. It feeds a MainActor sync engine that runs a **full resync on every `server.connected`**. The engine is ported from `data.ts` and hardened with:
   - event handlers that are safe to apply twice;
   - duplicate removal by `seq`;
   - gap splicing (merging a fresh newest page into the history already loaded; see §2.5);
   - an outbox of unsent prompts that survives app restarts.
3. **Hand-write the models and decode them tolerantly.** An unknown type, an unknown field or a malformed element must never crash the app, end the event stream or drop a page.
4. **Use a GRDB/SQLite cache.** It stores the raw server JSON plus a few indexed columns, so the cache does not depend on the server's schema. Drafts and the outbox are persisted too. The server is always the source of truth.
5. **Push = our opencode plugin + our relay + HPKE-sealed payloads + a Notification Service Extension (NSE).** Approvals never pass through the relay. They go over the direct connection and are checked against a digest of exactly what the user saw.
6. **The MVP (the version that works as a daily driver) is M0 to M5:** about 17 to 20 calendar weeks with 2 iOS engineers and a part-time TypeScript engineer.

## 1. Architecture overview

### 1.1 Targets and modules

**App and extensions** (generated with XcodeGen from `project.yml`)

| Target | Responsibility | Links |
|---|---|---|
| `Opencode` (app; iPhone and iPad; "Designed for iPad" on Mac) | Wires everything together and holds no feature logic. Contains `OpencodeApp`, the `AppDelegate` (APNs token, `UNUserNotificationCenterDelegate`), scene routing and the `AppEnvironment` dependency container. | Everything below |
| `NotificationService` (NSE) | Opens the sealed payload; sets title, body, category, thread and badge; records what was shown. | OCPushCore, OCSecurity, OCShared |
| `Widgets` (WidgetKit) | Live Activity UI, Home and Lock Screen widgets, Control Center controls. | OCActivity, OCShared, OCIntents |
| App Intents | Defined in the `OCIntents` package target (`AppIntentsPackage`) and compiled into both the app and Widgets. `LiveActivityIntent`s run in the app process. | OCSync (in the app), OCShared |
| Later | `NotificationContent` extension (real question buttons, diff preview), `ShareExtension`. | — |

**Local package `OpencodeKit`.** Everything compiles in Swift 6 language mode. Core targets are nonisolated; UI targets default to MainActor.

| Target | Isolation | Responsibility | Depends on |
|---|---|---|---|
| `OCFoundation` | nonisolated | `JSONValue`, lenient decoding helpers, `LossyArray`, `OpencodeID` minting, `SemVer`, `ServerClock`, redacting `os.Logger` categories | — |
| `OCModels` | `Sendable` value types | Wire models (`SessionInfo`, `SessionMessage`, `AssistantContent`, `ToolState`, `InboxItem`, `PermissionRequest`, `FormInfo`, catalogs, `FileDiff`, `Pty`, `ServerInfo`); `ServerEvent`; `APIErrorBody` | OCFoundation |
| `OCNetworking` | actors | `APIClient` with about 60 `Endpoint`s; `SSEParser`; `ServerConnection`; `EndpointResolver`; `ServerProbe`; `PairingService`; `PTYSession`; `DirectActionClient` | OCModels, OCFoundation |
| `OCSecurity` | nonisolated | `KeychainStore`, `CredentialStore`, `BiometricGate`, push key material | OCFoundation, OCModels |
| `OCPersistence` | writer actor | GRDB `CacheStore`, `DraftStore`, `OutboxStore`, migrations | OCModels, GRDB |
| `OCShared` | nonisolated | App Group snapshot (JSON files written atomically), deep-link routes, shared constants | OCFoundation |
| `OCPushCore` | nonisolated | Envelope format, HPKE open, payload schema, canonical digest, risk rules | OCFoundation, OCSecurity |
| `OCSync` | MainActor | `ServerRegistry`, `ServerStore`, `SessionModel`, `TranscriptModel`, event handlers, `ResyncCoordinator`, `OutboxProcessor`, `InboxModel`, `LiveActivityCoordinator` | OCNetworking, OCPersistence, OCSecurity, OCShared, OCPushCore |
| `OCRender` | nonisolated, `@concurrent` | Markdown block pipeline (swift-markdown); unified-diff parser and word diff; tree-sitter highlighting; `TimelineRowBuilder`; `ToolPresenter`s | OCModels |
| `OCDesign` | MainActor | Design system; `MarkdownBlockView` (Textual behind a `MarkdownBlockRenderer` protocol); `CodeBlockView`; `DiffView`; status pills; composer chrome | OCRender |
| `OCActivity` | — | `SessionActivityAttributes`, shared by the app and the widget | OCShared |
| `Feature*` | MainActor | `FeatureServers`, `FeatureInbox`, `FeatureTranscript`, `FeatureComposer`, `FeatureApprovals`, `FeatureReview`, `FeatureFiles`, `FeatureTerminal`, `FeatureSettings` | OCSync, OCDesign, OCRender |

**Rules**
- Extensions never link OCSync or OCNetworking, which keeps the NSE small and fast to start.
- Features never import OCNetworking. They call methods on the stores and the engine.
- Third-party engines sit behind protocols:
  - `MarkdownBlockRenderer` (Textual);
  - `CodeViewer` (a native read-only `UICollectionView` renderer shared by review, files and diff cards; replaced Runestone in M4, whose tree-sitter 0.20 constraint conflicts with swift-tree-sitter 0.10 / tree-sitter 0.25);
  - `TerminalEngine` (SwiftTerm);
  - `TimelineContainer` (`LazyVStack`, or `UICollectionView` as a fallback).

**Dependencies:** GRDB 7, swift-markdown, Textual, SwiftTreeSitter with 13 grammars and SwiftTerm (Runestone dropped in M4). For tests: swift-snapshot-testing and swift-clocks.

### 1.2 Diagram

```
 ┌──────────────────────────── Opencode app process ─────────────────────────────┐
 │ Feature targets (SwiftUI, MainActor): Servers · Inbox · Transcript · Composer │
 │   Approvals · Review · Files · Terminal · Settings ──► OCDesign ──► OCRender  │
 │        │ observe @Observable models / call engine methods                     │
 │        ▼                                                                      │
 │ OCSync (MainActor): ServerRegistry → ServerStore → SessionModel →             │
 │   TranscriptModel → MessageModel → ContentItemModel;                          │
 │   SyncEngine · ResyncCoordinator · OutboxProcessor · InboxModel               │
 │        ▲ EventBatch every 16 ms                 │ Endpoint<T> requests        │
 │        │                                        ▼                             │
 │ OCNetworking (actors): ServerConnection · EndpointResolver · APIClient ·      │
 │   PTYSession · PairingService · ServerProbe · DirectActionClient              │
 │ OCPersistence (GRDB) · OCSecurity (Keychain, Face ID) · OCPushCore · OCShared │
 │ OCModels ◄── OCFoundation                                                     │
 └──────┬─────────────────────────────────────────────────┬──────────────────────┘
        │ HTTP + SSE + WebSocket                          │ App Group JSON + shared Keychain
        │ (LAN / Tailscale / OpenTunnel / custom HTTPS)   ▼
        ▼                                   NotificationService ext   Widgets ext
 opencode V2 server (user's machine)        (HPKE open, rich alert)   (Live Activity,
  /api/*  /api/event  /api/pty/{id}/connect        ▲                   widgets, controls)
  plugin "mobile-push" ─HTTPS─► relay (Cloudflare Worker) ─HTTP/2─► APNs
```

### 1.3 Repository layout

```
opencode-ios/
  project.yml   App/   Extensions/{NotificationService,Widgets}/
  Packages/OpencodeKit/{Package.swift, Sources/<target>/, Tests/<target>Tests/}
  Fixtures/<server-version>/{rest,sse,ws}/<scenario>.*
  Tools/{fixture-recorder, mock-llm, mock-opencode, spec-watch}
  server/{plugin (TypeScript, npm), relay (Cloudflare Worker), contracts (payload schema, digest vectors, risk rules)}
  .github/workflows/{ci, contract, spec-watch, plugin, relay}.yml
```

## 2. Core engine

### 2.1 Servers, endpoints and credentials

```swift
public struct ServerRecord: Codable, Sendable, Identifiable {
  public let id: ServerID                    // local UUID; opencode has no stable server ID
  public var name: String
  public var endpoints: [EndpointRecord]     // one credential works on all of them
  public var lastInfo: ServerInfoSnapshot?   // version, urls, capabilities, clock offset
  public var options: ServerOptions          // autoConnect, allowInsecureRemote, push
}
public struct EndpointRecord: Codable, Sendable, Identifiable {
  public let id: EndpointID
  public var url: URL
  public var kind: EndpointKind      // .lan, .tailnet, .tunnel, .https, .ssh(profile)
  public var source: EndpointSource  // .pairing, .manual, .discovered
  public var headerNames: [String]   // e.g. Cloudflare Access headers; values live in the Keychain
  public var stats: EndpointStats    // lastSuccess, medianRTT, lastFailure
}
public enum Credential: Codable, Sendable { case pairingToken(String, expiresAt: Date), password(String) }
```

**Keychain**
- One generic-password item per server (`account = ServerID`), with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, in an access group shared with the NSE and the intents.
- The token expiry is parsed from the token itself (`<expiry>.<sig>`). The app warns 5 days ahead.
- There is no refresh endpoint. Any 401 marks the server `.unauthorized` and opens a re-pair sheet.

**Pairing** (`PairingService`)
- Accepts exactly what the reference parser `pairing.ts` accepts:
  - the QR payload `{code, urls}`;
  - `…/auth/connect/<code>` links, pasted, scanned or opened as a universal link;
  - legacy `/connect#…` links, answered with "re-run `opencode pair`";
  - a manual URL plus password.
- It calls `GET <url>/auth/connect/<code>` on every URL at once (`Accept: application/json`, 5 s timeout).
- The code is single-use, so a 401 from any URL means "expired".
- Every URL becomes an endpoint of the same server. The first URL is preferred if it answers within 1 s, as in the reference.

**Endpoint racing** (`actor EndpointResolver`)
- Sends an authenticated `GET /api/info` to every enabled endpoint (timeout 2 s on the LAN, 6 s elsewhere).
- After the first 200, it waits 500 ms for a better-ranked one. The order is lan, then tailnet, then https, then tunnel, then ssh.
- The result carries a diagnosis per endpoint, so the UI can say *why* it failed:
  - `localNetworkDenied`, from `NWPath.unsatisfiedReason`;
  - DNS failure, for example a Pi-hole blocking `*.opentunnel.xyz`;
  - TLS error, timeout, or 401.
- Non-loopback URLs from `/api/info.urls` are added as `.discovered` endpoints.
- It re-races after a failed connect, on every `NWPathMonitor` change, and on foreground when more than 60 s have passed.

**Server clock offset.** The app estimates the server's clock from the `Date` header of `/api/info` (taking the midpoint of the round trip), then refines it with event `created` timestamps. The offset is used for minting IDs (§2.5).

### 2.2 Probe, V1 detection and capabilities

`ServerProbe.probe(endpoint:credential:) -> ProbeOutcome`:

| Response | Outcome |
|---|---|
| `GET /api/info` returns 200 with JSON | `.v2(ServerInfo)`; a version below 2.0.10 gives `.unsupportedV2` |
| 503 with `Retry-After` | `.v2Starting(retryAfter)`, honoured rather than treated as an error |
| 401 with `{"_tag":"UnauthorizedError"}` | `.unauthorized(.v2)` |
| 401 with an empty body, 200 with `text/html`, or 404 | Probe `GET /global/health`. JSON `{healthy, version}` means `.v1(version)`; anything else is `.notOpencode` |

`ServerCapabilities` combines four sources:
- **Version gates:** 2.0.25 for pairing and credentials.
- **Server-reported flags:** `info.capabilities.persistentPty`.
- **Operation set:** parsed once per server version from `GET /openapi.json` and cached in GRDB. It covers experimental routes: `session.log`, `session.wait`, `fs.write` and runtime MCP.
- **Push plugin presence:** `POST /api/rpc/mobilepush/status`; a 404 means the plugin is not installed.

Features check `capabilities` and explain a disabled action inline, for example "needs opencode 2.0.25 or later".

### 2.3 API client and tolerant decoding

```swift
public struct Endpoint<Response: Sendable>: Sendable {
  var method: HTTPMethod, path: String, query: [URLQueryItem] = []
  var scope: Scope                 // .global, .location(LocationRef), .session
  var body: Data? = nil, idempotent: Bool
  var decode: @Sendable (Data, HTTPURLResponse) throws -> Response
}
public actor APIClient { public func send<R>(_ e: Endpoint<R>) async throws(APIError) -> R }
public enum APIError: Error, Sendable {
  case unauthorized, serviceStarting(retryAfter: Duration)
  case server(tag: String, status: Int, body: JSONValue)
  case notOpencode(contentType: String?), transport(URLError), decoding(String), cancelled
}
```

**Request handling**
- **Location scope.** `.location` appends `location[directory]=<abs>`. Responses decode as `Located<T>{location, data}`. Stores key the result under both the canonical directory and the requested one, as `data.ts` does.
- **Authentication.** `Authorization: Basic base64("opencode:<secret>")` is sent preemptively on every request, together with any custom headers.
- **Content-type check before decoding.** V2 answers unknown GET routes with its web app's HTML.
- **Retries.** GETs are retried twice on transport errors. POSTs are never retried automatically; prompts are retried through the outbox with the same ID.
- `fs.read` URLs are built by hand.

**Decoding rules**
1. Ignore unknown keys, and treat `null` the same as an absent key.
2. Every union has a `.unknown(type: String, raw: JSONValue)` case. This covers `SessionMessage`, `AssistantContent`, `ToolState`, `InboxItem`, form fields and MCP status.
3. Arrays of union elements use `LossyArray`. An element that fails to decode becomes `.undecodable(raw, error)` and renders as a fallback row with "View raw JSON".
4. Numbers also accept the strings `"NaN"` and `"Infinity"`.
5. Tool inputs stay `JSONValue` because they are raw model output. Lenient typed views (`ShellInput`, `EditInput`, and so on) read them.
6. When encoding, leave keys out; never send `null`.

**Events are decoded in two stages**
1. Decode `EventHeader {id, type, created?, location?, durable?}`.
2. Switch on `type` and decode `Envelope<Payload>` from the same bytes.

An unknown type becomes `.unknown(header, raw)`. A failed decode becomes `.undecodable(header, raw, error)`. Neither ends the stream.

If an unknown or undecodable **durable** `session.*` event carries a `sessionID`, the engine refetches that session's info and newest page after a 500 ms debounce, because the event may have changed state the client does not model.

`session.status`, `session.idle`, `tui.*` and `session.tool.input.delta` are decoded but never relied on. A CI script compares the `ServerEvent` cases with the `V2Event` union in `packages/client/src/promise/generated/types.ts`.

### 2.4 Event stream: `actor ServerConnection`

```swift
public actor ServerConnection {
  public nonisolated let output: AsyncStream<ConnectionOutput>  // .state(ConnectionState) | .events(EventBatch)
  public func start(); public func stop(); public func forceReconnect(_ reason: ReconnectReason)
}
public enum ConnectionState: Sendable, Equatable {
  case idle, resolving, connecting(attempt: Int), connected(EndpointID, since: ContinuousClock.Instant)
  case waiting(attempt: Int, retryAt: ContinuousClock.Instant, failure: ConnectionFailure)
  case suspended, serviceStarting(Duration), unauthorized, incompatible(ProbeOutcome)
}
```

**The connection loop**
1. Resolve an endpoint.
2. Open a data task on a dedicated `URLSession`. A delegate delivers `Data` chunks; the stream is not read byte by byte through `AsyncBytes`.
3. `SSEParser` joins `data:` lines, counts `:` comments as activity, handles CR, LF and CRLF, and skips events larger than 16 MiB.
4. The first frame must be `server.connected`.
5. Events are decoded off the main actor and delivered in batches.

| Parameter | Value | Reference client |
|---|---|---|
| First-frame timeout | 3 s on the LAN, 8 s remote | 2 s |
| Watchdog | 45 s with no byte at all (heartbeat comments count) | 45 s |
| Foreground quiet threshold | 20 s, then forced reconnect | 20 s |
| Backoff | 1 s, doubling with full jitter, capped at 30 s; resets once a connection has lasted 10 s; forced reconnects skip it | fixed 1 s |
| Delivery to the MainActor | every 16 ms; immediately for `permission.*`, `form.*` and `session.execution.*` | 10–16 ms |
| In-memory backlog cap | 20,000 events, then drop them and force a resync | — |

**Failure handling**
- The read loop never waits on the main actor. A slow UI therefore cannot trigger the server's 4,096-frame overflow close.
- A 401 stops the loop (`.unauthorized`).
- A 503 waits for `Retry-After`.
- A denied Local Network permission or a blocked tunnel domain becomes a specific state with a fix-it action.
- The last 50 state changes are kept for the diagnostics screen.

### 2.5 Sync engine

**Stores** (all `@MainActor @Observable final class` in OCSync)

| Store | Holds |
|---|---|
| `ServerRegistry` | Ordered `[ServerStore]`, the merged `InboxModel`, scene-phase and network-path handling |
| `ServerStore` | `connection`, `capabilities`, `projects`, `sessions: [SessionID: SessionModel]`, `running: Set<SessionID>`, `permissions: [SessionID: [PermissionRequest]]`, `forms: [FormOwner: [FormInfo]]` (owner is a session, or `"global"` plus a location), `catalogs: [LocationKey: LocationCatalog]` |
| `SessionModel` | `info`; `status: RunStatus` (`idle`, `running(since)`, `retrying(attempt, at)`, taken from `session.retry.scheduled`); `pending: [InboxItem]`; `transcript: TranscriptModel?` (loaded on demand); a derived `attention`; `lastSeq` |
| `TranscriptModel` | `order: [MessageID]`, `messages: [MessageID: MessageModel]`, `olderCursor`, `loadingOlder` |
| `MessageModel` | For assistant rows, `items: [ContentItemModel]`, keyed by `ContentKey` (`.text(ordinal)`, `.reasoning(ordinal)`, `.tool(callID)`) |
| `ContentItemModel` | The single item a streaming delta changes, so exactly one row re-renders |
| `LocationCatalog` | Agents, models, default model, providers, commands, skills, references, MCP and VCS. Each sits in a `Revalidating<T>` cell that mirrors `createSync()`: at most one load per key in flight, and after an invalidation the reload runs afterwards, so an older response can never overwrite a newer one |

**Applying events.** The handlers port `handleEvent` from `data.ts` case by case, with these changes:

1. **Handlers are safe to apply twice.**
   - `*.started` inserts or updates by `ContentKey`. The ordinal comes from the event; for content loaded over HTTP it is derived per kind.
   - Tool items are keyed by call ID, rows by message ID.
   - Rows the client creates locally reuse the event ID with `evt_` replaced by `msg_`, so the server's copy later replaces them. This covers agent, model and location switches, `synthetic`, `system`, `shell`, `idle` and `compaction`, plus `session.skill.activated`, which the reference does not handle live.
2. **Sequence numbers.** Each session keeps `lastSeq` from `durable.seq`.
   - Events whose `seq` the session has already applied are duplicates and are dropped.
   - Gaps are normal (filtered internal events consume numbers) and are ignored.
   - An older `seq` the session has not seen before (a backwards jump) triggers a refetch of that session. (Clarified 2026-10-17 to match the M2a implementation.)
   - HTTP snapshots carry no `seq`, so `lastSeq` resets after each snapshot.
3. **Deltas** are applied only to rows the client holds; `*.ended` is authoritative. If the client missed an item's `started` event, the item is flagged `joinedMidStream` and shown as "catching up" until `.ended` arrives.
4. Sessions without a loaded transcript receive only session-level effects: status, attention, cost and last activity.
5. **Revert hiding uses positions.** Rows at or after the boundary row's index are hidden. The ID comparison `id >= revert.messageID` is only a fallback when the boundary row is not loaded. The server itself orders by `seq`, so this stays correct even when a client-minted ID is skewed by the phone's clock.
6. Permissions and forms raised in a child session count toward the root session's attention. The engine walks `parentID` and fetches unknown parents.

**Resync on every `server.connected`** (`ResyncCoordinator`)
1. Drain the outbox. The same IDs are reused, and the server admits each ID only once.
2. In parallel:
   - `GET /api/session/active`;
   - `GET /api/project`;
   - `GET /api/session?parentID=null&limit=50`;
   - for each location of a running or open session, `GET /api/permission/request` and `GET /api/form`.
3. For each transcript that is on screen:
   - `GET /api/session/{id}`;
   - the newest page (`limit=50&order=desc`), merged by gap splicing;
   - `GET …/inbox`;
   - the session's permission and form lists.
4. Invalidate all catalogs. Refetch those for the open session's location (the composer needs them); fetch the rest when they are opened.

**Events that arrive during a fetch.** This generalizes the reference's `activeUpdates` and `pendingUpdates`:
- While a snapshot of a set (active sessions, inbox, permissions, forms) is in flight, events keep updating the live model. They are also recorded as an insert/update or a deletion marker per ID, and re-applied once the snapshot lands.
- When a message snapshot lands, rows changed by durable events during the fetch keep their local version, and rows not yet acknowledged by the server are always kept.

**Gap splicing** (for the open transcript)
1. Find the newest local row (one the server has confirmed, not an optimistic placeholder) whose ID appears in the freshly fetched newest page.
2. Replace everything from that row onward with the server's rows, and keep the older local history.
3. With no overlap, fetch up to four older pages looking for one; failing that, reset to the newest page with a fresh `olderCursor`.

Messages deleted by a revert committed while the phone was disconnected disappear naturally, because the splice replaces the tail.

**Optimistic writes and the outbox**
- **ID minting.** `IDMinter` (one per server) produces `ses_` IDs (descending) and `msg_` IDs (ascending) exactly like `Identifier.create`: 12 hex characters of `ms*4096+counter`, then 14 base62 characters. It uses the server-corrected time, and each new `msg_` is forced to sort after the session's newest known message.
- **Creating a session.** The `SessionModel` appears immediately, then `POST /api/session {id, location, agent?, model?}`. Prompts to that session wait for the create to finish. The local session is removed only if the server never acknowledged it.
- **Sending a prompt:**
  1. Write `OutboxEntry {id, serverID, sessionID, prelude, body, createdAt, attempts, state}` to GRDB first. The body is the exact JSON bytes, so a retry is byte-for-byte identical.
  2. Show the row as *sending*.
  3. Run the prelude in the server's order: `POST …/agent` if it differs from `info`, then committing a staged revert if the user confirmed it, then `POST …/model` if it differs. Committing a revert deletes the rows after its boundary, so a model switch made before the commit would be lost. (Corrected 2026-10-21 after M3b.)
  4. Send prompts for one session one at a time, in order.
  5. A 200 or the `session.inbox.enqueued` echo acknowledges the entry.
  6. On a transport error, keep the entry and retry while connected and on every reconnect (the server admits each ID only once).
  7. A resent ID that matches the first admission's session and type returns that first admission, even if the new bytes differ; the server reconciles by ID without comparing payloads. A 409 means the ID collided with another session or type. A 409 or other 4xx marks the row failed, with *Edit and resend*. Exact stored bytes remain the client's retry invariant. (Corrected 2026-10-21 after M3b.)
  8. Entries older than 10 minutes found at launch are never sent automatically; the user is asked.
  9. Sends run inside `beginBackgroundTask`, so leaving the app right after tapping Send does not produce a false error.
- **Other optimistic changes**, each applied in the UI before the server answers:
  - a permission reply (a 404 means already settled, which counts as success);
  - a form reply (a 409 "already settled" counts as success);
  - rename, delete and delivery change;
  - cancelling a pending item, which puts its text and attachments back in the composer.
- `POST …/command` takes no ID, so it is never retried automatically.

**Foreground and background**
- **Going to the background:** within a background task, drain the outbox, flush persistence and write the App Group snapshot. Then stop the streams (`.suspended`) and close terminal sockets, keeping their cursors.
- **Becoming active:** start the streams. If the stream was quiet for more than 20 s, force a reconnect. Re-race endpoints if the network path changed or more than 60 s passed.
- **`NWPathMonitor` changes** (debounced 500 ms): re-race endpoints and force a reconnect.
- **Launches caused by a notification action** use `DirectActionClient`: no SSE and no resync.

**Pagination.** The first page holds the 50 newest messages; older pages of 50 load through `cursor.next`. "Jump to start" is a separate `order=asc` query, never combined with a cursor. At most six transcripts stay in memory (least recently used first out); the rest live in the cache.

### 2.6 Persistence: GRDB rather than SwiftData

**Why GRDB 7 over SQLite**
1. **Schema independence.** The server is the source of truth, and its schemas change weekly. Storing raw server JSON plus a few indexed columns keeps the cache unaffected by server changes, because it is read with the same tolerant decoder. SwiftData would need an `@Model` copy of every type and a migration for each server change.
2. **Swift 6 concurrency.** GRDB's `DatabasePool` is `Sendable` and allows concurrent WAL readers, and a background writer actor batches writes. SwiftData's `ModelContext` is not `Sendable`, which pulls persistence onto the main actor.
3. **Predictable bulk work.** Bulk upserts of thousands of rows run inside explicit transactions. FTS5 is available for transcript search later, and tests can use an in-memory database.

**Schema (v1)**

| Table | Columns |
|---|---|
| `server` | `id`, `json` |
| `project` | `server_id`, `id`, `active_at`, `json` |
| `session` | `server_id`, `id`, `parent_id`, `project_id`, `directory`, `title`, `updated_at`, `idle_at`, `viewed_at`, `outcome`, `accessed_at` (for LRU retention), `json` |
| `message` | `server_id`, `session_id`, `id`, `position`, `type`, `complete`, `json` |
| `transcript_window` | `server_id`, `session_id`, `older_cursor`, `fetched_at` |
| `catalog` | `server_id`, `location_key`, `kind`, `fetched_at`, `json` |
| `draft` | `id`, `server_id`, `session_id`, `directory`, `text` (archived `AttributedString`), `attachments_json`, `delivery`, `options_json` (composer options, migration v3), `updated_at` |
| `outbox` | the `OutboxEntry` fields (§2.5), plus `operation` (prompt, create, rename and so on; migration v2) |
| `pty_cursor` | `server_id`, `pty_id`, `cursor` |
| `local_meta` | `server_id`, `session_id`, `pinned`, `hidden`, `muted`, `reviewed_files` |
| `openapi_ops` | `version`, `ops` |
| `cache_migration` | one-time migration markers, such as the import of M1b's server-record JSON file |

**Storage rules**
- **Write-behind.** Writes are debounced by 2 s and also happen at the end of a turn and on backgrounding. Nothing is written per streaming delta.
- **Keep the database out of the App Group.** It lives in the app's own sandbox, because iOS kills a suspended app that holds SQLite locks in a shared container (crash code `0xdead10cc`). Extensions read small, atomically written JSON snapshots in the App Group instead.
- **Retention:** the last 200 sessions or 300 MB, evicting the least recently used.
- **File protection:** `completeUntilFirstUserAuthentication`, which background action handling needs. An option keeps only metadata on the device.

**Drafts**
- Keyed by (server, session), or by (server, directory) for a session not yet created.
- Store the attributed text, with attachment files under `Application Support/Drafts/<id>/`.
- Saved 300 ms after the last edit and whenever the scene becomes inactive.
- Never lost on navigation, crash or session switch.

### 2.7 Concurrency model

- **MainActor:** all `@Observable` stores and SwiftUI. Event handlers are cheap (appending strings, setting dictionary entries).
- **Actors:**
  - `ServerConnection` and `EndpointResolver` (one of each per server);
  - `APIClient`;
  - `OutboxProcessor`;
  - `PersistenceWriter`;
  - `PTYSession` (one per terminal).
- **`@concurrent` functions** (needed because "nonisolated nonsending by default" is enabled, see report 07 §1.6): event decoding, Markdown and diff parsing, highlighting, image downscaling.
- **Data flow:**
  1. Bytes go through the parser inside the connection actor.
  2. Events are decoded in `@concurrent` functions into an `EventBatch: Sendable`.
  3. An `AsyncStream` carries the batches to one MainActor consumer task per server.
  4. The handlers update the models, and SwiftUI views update.

  Persistence, Live Activity updates and haptics watch the models through `Observations` (SE-0475).
- Every task belongs to an actor or a store and is cancelled on `stop()`. There are no detached tasks.

## 3. Features mapped to screens

| Screen | Target | Key behaviour | Main APIs |
|---|---|---|---|
| Server list, pairing, re-pair, endpoint editor, "Upgrade to V2" | FeatureServers | QR scanning with VisionKit `DataScannerViewController`, link paste, or manual entry. Health per endpoint and an "Unencrypted" badge for HTTP. An explanation shown before the Local Network permission prompt. A token-expiry banner. | `/auth/connect`, `/api/info` |
| Inbox (home) | FeatureInbox | Triage across all servers, in four groups (see the note under this table). Each row shows project avatar, title, server/directory chip, status glyph and cost. Blocked rows have a Review button. Swipe actions: mark read (`/view`), pin, hide (local only; V2 has no archive). | session list, `session/active`, permission and form lists |
| Projects, sessions, new session | FeatureInbox | Projects sorted by `time.active`. A directory browser (`fs.list` with an absolute path) followed by `GET /api/location`. Optional new worktree (`POST /api/worktree`). Search by title. | `/api/project`, `/api/session?project=`, `/api/worktree` |
| Transcript | FeatureTranscript | See §3.1 | messages, events, `session.diff`, shell output |
| Composer and pickers | FeatureComposer | See §3.2. The model picker is grouped by provider, with search, a Default badge, image-input and variant badges, and prices. The agent picker shows agents where `mode != subagent && !hidden`, in their colours. The effective model and agent are always read back from the server's `session.model.selected` and `session.agent.selected` events. | prompt, command, shell, interrupt, inbox, `/model`, `/agent` |
| Permission and question sheets | FeatureApprovals | See §3.3 | permission, form |
| Changes and review | FeatureReview | See the note under this table | `session.diff`, `vcs.*`, `revert.*` |
| Files | FeatureFiles | Lazy tree (`fs.list`) and fuzzy find (`fs.find`). Native read-only code viewer with tree-sitter highlighting (byte-bounded, off the main actor). Quick Look for images and PDFs. ETag caching and range reads for large files. "Mention in composer"; open at a line from transcript links. | `fs.*` |
| Terminal | FeatureTerminal | Terminal list per location, rendered with SwiftTerm. WebSocket authenticated with the Basic header; resume with `cursor` (advance by `utf16.count`; the binary `0x00` + JSON frame sets the cursor). Resize with a `PUT` debounced by 150 ms. Key bar with Esc, Tab, Ctrl, arrows, `\|` and `~`. Reconnect on foreground; handle close code 4404. | `pty.*` |
| Settings | FeatureSettings | See the note under this table | integration, mcp, permission/saved, config |

**Inbox triage groups**
- **Needs you:** a pending permission or question anywhere in the session family, or a failed session the user has not seen.
- **Running:** a live line with the current step or tool, and elapsed time.
- **Done:** unread, meaning `time.idle > time.viewed`.
- **Recent:** everything else.

**Changes and review**
- A "Changed N files" card at the end of each turn. File names come from the steps' `snapshot.files`; line counts come from `GET /session/{id}/diff?from=<turn>`.
- VCS review of the working tree or the branch.
- Diffs are unified on narrow widths and side by side on wide ones, with word-level highlights and collapsed context.
- A per-file "Reviewed" mark.
- Long-press a line to attach a comment to the next prompt.
- Undo the turn (`revert/stage`) and Redo (`DELETE /revert`). Before the next send, the staged revert is committed after the user confirms.

**Settings**
- **App:** appearance; timeline detail preset (the official app's Compact by default); default follow-up delivery (Steer); notifications per category; app lock; Face ID step-up; storage; diagnostics export with secrets removed.
- **Per server:** endpoints; push status and test push; capabilities.
- **Providers and integrations:** connect with an API key, a device code or a pasted code. An `auto` OAuth flow shows "Finish on your computer" and polls. Accounts are managed through integration connections; `GET /api/credential` is never called.
- **Also:** MCP status and connect (an MCP OAuth sign-in always calls back to 127.0.0.1 on the server, so it must be finished in a browser on that machine); saved permissions; read-only config documents; worktrees; plugins.

### 3.1 Transcript

**Row model.** `TimelineRowBuilder` (OCRender) turns messages into `[TimelineRow]`. Completed turns are frozen and cached; only the open turn is rebuilt. Grouping follows the official detail presets (Everything, Detailed, Compact, Quiet, Messages only). Row kinds:
- `userPrompt`, with a Voice badge when the text follows the official app's `Voice delegation.` format;
- `assistantText(ref)`, `reasoning(ref)`, `tool(ref)`;
- `toolGroup(kind, refs)`, such as "Explored 6 files";
- `subagent(ref, childID)`, `shell`;
- `notice`: agent, model or location switch, synthetic or system message;
- `compaction`, `retry`, `error`, `pendingInput(item)`, `turnEnd(idle, changes)`.

**Tool renderers.** The `ToolPresenter` protocol has `matches`, `summary` and `detail`. A registry falls back to `GenericToolPresenter`. Renderers per tool:

| Tool | Rendering |
|---|---|
| `read`, `glob`, `grep` | Grouped |
| `edit`, `patch` | Diff cards from `metadata.files` |
| `write` | Added-file view built from `input.content` |
| `shell` | Live output by polling `GET /api/shell/{metadata.shellID}/output` every second, but only while the row is visible. An exit or timeout badge even when the status is "completed". "Send to background" calls `/background`. |
| `subagent` | A card that opens the child transcript, with a read-only composer |
| `question` | Hidden while pending; a question-and-answer summary afterwards |
| `skill`, `webfetch` | Compact rows |
| `websearch` | Result links |
| `execute` (CodeMode) | Nested `toolCalls` plus console output |
| MCP `<server>_<tool>` | Generic, with an MCP badge |
| V1 history (`bash`, `task`, `apply_patch`, `todowrite`) | Mapped to the matching renderer |
| Unknown | Name, status, pretty-printed input JSON and text content |

**Streaming performance**
- Each content item is its own `@Observable`, and updates are delivered every 16 ms.
- `StreamingMarkdown` (one per text item):
  - finished blocks are rendered once, cached by hash and drawn as `Equatable` views;
  - only the unfinished tail is re-parsed, off the main actor, at most 12 times a second;
  - unclosed syntax in the tail, such as an open code fence, is closed before parsing.
- Code fences stay plain monospace until closed, then are highlighted asynchronously.
- Tool output longer than 200 lines is folded and opens in a sheet backed by `UITextView`. Images are downsampled with ImageIO.
- The container is a `ScrollView` with a `LazyVStack`:
  - `defaultScrollAnchor(.bottom)`;
  - `onScrollGeometryChange` to track whether the user is near the bottom, with a "Jump to latest (n)" pill otherwise;
  - `ScrollPosition` to keep the position steady when older pages are prepended.
- Budgets, checked with Instruments traces:
  - at most 4 ms of main-thread work per update at 50 tokens/s on an iPhone 13;
  - smooth scrolling through 2,000 rows;
  - under 250 MB for a 5,000-row session.
- If the budgets are missed, switch `TimelineContainer` to `UICollectionView` with `UIHostingConfiguration`.

**Header and selection**
- The header shows context usage and family cost. Context usage is the last assistant step's tokens divided by `limit.context`. Family cost includes children, listed with `parentID=<root>&limit=200`.
- Text selection uses iOS 27's `textSelection` behind `#available`. On iOS 26, a "Select text" sheet backed by `UITextView` stands in.

### 3.2 Composer

**Editor.** An iOS 26 `TextEditor` bound to an `AttributedString`, with a `MentionAttribute` whose values are `.file(path)`, `.agent(name)`, `.skill(id)` and `.reference(name)`. If input-method (IME) problems appear, fall back to a `UITextView` wrapper.

**Triggers**
- **`@`** suggests:
  - files from `fs.find` (debounced 120 ms);
  - subagents, skills and references.

  There are no MCP-resource mentions. V2 accepts only `data:` and `file://` attachment URIs (`packages/core/src/session/prompt.ts`), and the client has no `fs/write` upload fallback for other sources. (Corrected 2026-10-21 after M3b.)
- **`/`** suggests server commands plus client commands:
  - `new`, `undo`, `redo`, `compact`, `fork`, `model`, `agent`, `export`, `init`, `review`;
  - `btw`, which asks a side question through `session.generate` and shows the answer in a sheet.
- **`!`** switches to shell mode (`POST …/shell` with a minted ID).

**Attachments**
- Sources: PhotosPicker, camera, Files, paste, and drag and drop on iPad.
- Images are downscaled to 2,000 px and sent as canonical `data:` URLs, with a 20 MiB cap.
- Warnings appear when the model lacks image or PDF input. V2 sends PDFs only to models that declare PDF input, and drops audio and video (report 02, verification pass).

**Voice.** `SpeechAnalyzer` with `SpeechTranscriber`, primed through `contextualStrings` with file names, agents and the branch. Words still being recognised are greyed out. The result is editable text and is never sent automatically.

**Delivery**
- **Idle:** Send.
- **Running:** Send uses the default follow-up (Steer). The send menu offers:
  - *Queue instead*;
  - *Interrupt and send*: the prompt is admitted with steer, then `interrupt?resume=true` is called, which continues with the pending steered input.
- **Empty composer while running:** the button becomes Stop (`interrupt`).
- **Queue panel** above the composer lists pending items with the statuses `data.ts` uses (starting, steering, queued, stranded), with *Steer now* (`PATCH`) and *Cancel*, which restores the text and attachments.
- The keyboard stays open after sending. With a hardware keyboard, ⌘↩ or Return sends.

### 3.3 Permission and question sheets

**Where a pending request appears**
- Inline on the matching tool row (matched through `source.id`).
- In a dock above the composer, including requests from child sessions.
- As a full sheet.

**The sheet shows**
- the action;
- the **full** resources in monospace, with copy;
- the working directory;
- the edit preview from `metadata.files`;
- the `save` patterns that "Allow always" would store, for example "Always allow `git status *` in web-app";
- the risk tier.

**Buttons**
- **Reject**, with an optional note. The copy warns that rejecting also rejects the session's N other pending requests and, without a note, ends the turn.
- **Allow always**, behind Face ID.
- **Allow once**, the primary button.

The request is removed from the UI as soon as the user replies. A 404 means it was already settled elsewhere.

**Questions (forms).** A generic `FormRenderer` supports:
- string fields (with options: single choice plus "Other");
- multiselect with minimum and maximum;
- number and integer, boolean, and external-URL fields;
- `when` conditions, required-field validation and a review step.

*Dismiss* asks for an optional reason, because dismissing without one ends the turn.

**Silence is never consent.** Nothing is approved automatically. Per-project auto-accept, which the desktop app has, is not offered on the phone in v1.

### 3.4 iPad and Mac

- The layout mirrors the opencode desktop app (changed 2026-10-17; it was three navigation columns plus an inspector):
  - project tabs along the top;
  - the session timeline with the prompt dock as the main column;
  - a review panel on the right with changes and diffs, files, terminal and context;
  - the Home sidebar (project picker, session search, sessions by day, with "Needs you" and "Running" on top) as a collapsible pane.

  Panes collapse on narrow widths, and the iPhone uses the desktop UI's own mobile layout.
- Multiple windows with `WindowGroup(for: SessionRef.self)`, each keeping its own state in `@SceneStorage`.
- A menu bar built with `.commands`:

  | Shortcut | Action |
  |---|---|
  | ⌘N | New session |
  | ⌘↩ | Send |
  | ⌘. | Stop |
  | ⌘K | Switcher |
  | ⌘F | Find |
  | ⌘' | Model |
  | ⌘⇧A | Review the next approval |
  | ⌘1–9 | Sessions |
  | ⌘\ | Sidebar |

- Drag and drop into the composer.
- The same build runs on Apple-silicon Macs as "Designed for iPad".
- Basic column layouts ship with M2 and M3; the polish is M6.

## 4. Push notifications and Live Activities

### 4.1 Flow

1. The plugin running inside the user's opencode server sees an event and seals a payload for each registered device.
2. It sends the sealed payload to the relay (`POST /v1/push`).
3. The relay sends APNs a generic alert carrying the ciphertext.
4. The NSE decrypts it and shows the full notification.
5. When the user taps an action, the app starts in the background and talks to the server **directly**. It re-reads the request, checks the digest and replies.

The relay is never on the reply path.

### 4.2 The opencode plugin

`@<org>/opencode-mobile-push`, written in TypeScript against the V2 plugin API.

**Installation and scope**
- Installed once, globally, with `opencode plugin add` (the exact scope flag is to be verified in M0). The app detects it through the RPC `status` call and shows a copyable command when it is missing.
- One plugin instance runs per location. `ctx.event.subscribe()` only delivers events for that instance's location (`bus.ts`, `local()`), so each session event reaches exactly one instance.
- `ctx.storage` is the global key-value store (`kv.ts`, a global node), so a device registered through any location is visible to all instances.
- Events without a location are ignored. A `sent/<eventID>` key removes the duplicate delivery that `session.moved` produces. Both behaviours are to be confirmed with a two-location test in M0.

**RPC methods** (`mobilepush`)
- `status`;
- `registerDevice({sendToken, relayURL, devicePublicKey, keyID, appServerRef, label, prefs})`, returning `{serverPublicKey, pluginVersion}`;
- `unregisterDevice`;
- `listDevices`, including the last delivery result;
- `test`;
- `registerActivity({keyID, activityRef, sessionID})`;
- `setPresence({keyID, foreground, sessionID?})`.

**Triggers**
- `permission.asked` and `form.created`, after a 3 s grace period. The push is cancelled if the request is answered first, which also skips requests a desktop client accepts automatically.
- `session.execution.failed`.
- `session.execution.succeeded`, for root sessions only.
- When a request is answered (`permission.replied`, `form.replied`, `form.cancelled`), a silent replacement with the same collapse ID reads "Answered on another device".

**Presence.** While the app is in the foreground it sends a heartbeat every 30 s, valid for 45 s. Pushes to a device whose app is open are skipped. If presence is unknown, the push is sent.

**Child sessions.** Requests from a child session carry the root session ID, so the notification opens the right transcript.

**Payload content**
- kind, the app's own reference for the server, session and root session IDs;
- title and project folder name;
- request ID, action, and a summary of at most 300 characters (command, path or question);
- option labels;
- risk tier, from the shared `risk-rules.json`;
- pending count;
- `digest = SHA-256(canonical JSON of {requestID, sessionID, action, resources, save})`;
- expiry.

**Failures.** Up to three retries. When the relay reports `gone`, the registration is removed.

### 4.3 The relay

A Cloudflare Worker built with Hono, using D1 and one Durable Object per device for rate limits. It is open source.

| Method and path | Caller and auth | Body → result |
|---|---|---|
| `POST /v1/devices` | App. App Attest assertion (added in M9) and a per-IP rate limit. | `{apnsToken, env, bundleID}` → `{deviceID, deviceSecret}` |
| `PUT /v1/devices/{id}`, `DELETE /v1/devices/{id}` | App, `deviceSecret` | Token rotation (sent on every launch; repeating it is harmless) and removal |
| `POST /v1/devices/{id}/senders`, `DELETE …/senders/{sid}` | App, `deviceSecret` | One `sendToken` **per paired server**, so unpairing a server revokes only that one |
| `PUT /v1/devices/{id}/activities/{ref}` | App, `deviceSecret` | `{pushToken, expiresAt}` |
| `POST /v1/push` | Plugin, `Bearer sendToken` | `{kind, priority, collapse, thread, expiresAt, envelope}` → `{result: delivered \| gone \| throttled \| rejected}` |
| `POST /v1/activity` | Plugin, `sendToken` | `{ref, event: update \| end, state, staleAt, dismissAt?, priority}` |
| `GET /v1/health` | Public | Status |

**What the relay stores:** token hashes, APNs tokens and Live Activity tokens. It logs counts only.

**The APNs request it builds**
- a **generic** alert ("opencode needs your approval", "A session finished");
- `mutable-content: 1`, so the NSE runs;
- a category per kind;
- `thread-id` set to an opaque hash, and `apns-collapse-id` set to a hash of the request ID;
- interruption level `time-sensitive` for input requests, `active` for results, `passive` for replacements;
- priority 10 or 5, and a short expiration for approvals;
- authentication with an ES256 JWT, cached for 50 minutes.

**Limits:** 30 alerts a minute and 500 a day per device.

**M0 spike:** confirm that a Worker's outbound `fetch` reaches APNs over HTTP/2 (OpenChamber runs its relay on Workers). If it does not, deploy the same Hono app on Fly.io with `node:http2`.

### 4.4 Envelope and encryption

**Keys**
- For each paired server, the app generates an X25519 key pair (`Curve25519.KeyAgreement`). The private key goes in the shared Keychain with `AfterFirstUnlockThisDeviceOnly`.
- The app pins the plugin's static public key, which `registerDevice` returns.

**Sealing**
- **HPKE in auth mode**, which lets the NSE verify the sender:
  - suite `DHKEM(X25519, HKDF-SHA256)`, HKDF-SHA256, ChaCha20-Poly1305;
  - `@hpke/core` in Node, CryptoKit `HPKE` on iOS 17 and later.
- `info = "opencode-ios push v1"`.
- `aad = "oc1|kind|exp|kid"`, which binds the fields the relay can see to the ciphertext.
- The plaintext is padded to 512, 1,024 or 2,048 bytes, and the ciphertext stays under 3 KB, in `oc: {v, kid, kind, exp, enc, ct}`.

Neither the relay nor anyone who knows a device's public key can read or forge the content. Shared test vectors live in `server/contracts/` and run in both the Swift and TypeScript test suites.

### 4.5 Notification Service Extension

1. Find the keys by `kid` and open the envelope.
2. Reject it if it has expired.
3. Set:
   - title, for example "Allow `shell`?";
   - subtitle: session and project;
   - body: the summary;
   - `categoryIdentifier`, from kind and risk tier;
   - `threadIdentifier`: the root session;
   - relevance score;
   - badge: the sum of the per-server pending counts kept in the App Group.
4. Write `shown/<requestID>.json`, holding the digest and summary, to the App Group.

On any failure, the generic text stays and the category becomes `OPEN_ONLY`.

### 4.6 Actions and safe approval semantics

| Category | Actions, in order |
|---|---|
| `PERMISSION` | Open (brings the app forward; first, so Apple Watch Double Tap never approves anything) · Allow once (`.authenticationRequired`) · Reject (`.destructive`) · Reject with note… (text input) |
| `PERMISSION_HIGH_RISK` (`rm -r`, `sudo`, force-push, `external_directory`, …) | Open · Reject |
| `QUESTION` | Open · Answer… (text input, only for a single free-text question) |
| `FINISHED`, `FAILED` | Open · Reply… (text input, `.authenticationRequired`; queued as a prompt) |

**Handling an action** (`NotificationActionHandler`; background launch; at most 30 s)
1. `DirectActionClient` tries the last working endpoint (3 s), then races the others.
2. `GET /api/session/{sid}/permission/{rid}` re-reads the request.
3. Recompute the digest:
   - if it differs, do nothing and post "The request changed. Open the app to review";
   - if the request is gone (404), post "Already handled".
4. `POST …/reply`.
5. On a 204, replace the alert with "Approved" or "Rejected". On failure, post "Couldn't reach your server". Success is never assumed.

There is no "Allow always" outside the app. Every approval made from a notification is recorded in a local audit list in Settings.

### 4.7 Live Activity lifecycle

**Start.** `LiveActivityCoordinator` starts an activity (`pushType: .token`) when the user sends a prompt from the phone. This is a setting, on by default. The static attributes (title and project) are set locally, so pushes never carry them.

**State.** `ContentState = {phase: running | needsInput | retrying | succeeded | failed | interrupted, step, toolGlyph, startedAt, updatedAt}`.

**Updates**
- In the foreground, the app updates the activity itself.
- The push token goes to the relay, and `registerActivity` to the plugin.
- The plugin sends priority-5 updates at most every 30 s, and priority 10 for "needs input" and for the end.
- Each update sets `staleDate` to now plus 5 minutes, so a sleeping laptop shows as stale.

**End.** The final state stays for 15 minutes. Activities older than 7.5 hours are restarted.

**Privacy.** The content state is plaintext to the relay and to Apple, so it stays coarse.

**Buttons:** Open, and Stop (a `LiveActivityIntent` that calls `interrupt`).

### 4.8 What is in the MVP and what comes later

**MVP (M5)**
- plugin, relay, sealed alerts and NSE;
- the four notification categories, with digest-checked actions;
- presence suppression;
- separate senders per server;
- delivery health and "Send test push";
- badge;
- Live Activity for runs started from the phone.

**Later**
- push-to-start activities for runs started at the desk, and a multi-session "+N more" activity;
- a Notification Content extension with real option buttons and a diff preview;
- ID-only mode, where the NSE fetches the details over the direct path;
- the App Attest gate (before public launch);
- quiet hours and per-session mute;
- Apple Watch;
- signed approvals dropped at the relay for when the server is unreachable;
- FCM, for an Android client.

## 5. Security model

**Credentials**
- Stored in the Keychain only: never in `UserDefaults`, URLs, logs, crash reports or the App Group.
- `AfterFirstUnlockThisDeviceOnly`, so they never migrate through iCloud or backups.
- `Authorization` headers are redacted from logs.
- `GET /api/credential`, which returns provider secrets, is never called.

**Face ID**
- An optional app lock on launch and after N minutes in the background (`LAContext(.deviceOwnerAuthentication)`).
- Step-up authentication, on by default, for "Allow always", high-risk approvals, revealing a server password, and removing saved permissions.
- `LADomainState` detects changes to enrolled faces or fingers.

**App Transport Security**
- Only `NSAllowsLocalNetworking = YES`; never `NSAllowsArbitraryLoads`.
- Remote access uses HTTPS: OpenTunnel, `tailscale serve`, or a reverse proxy.

**Plain HTTP on the LAN.** The Basic credential is readable by anyone on the same network. That credential gives full control of the machine, provider secrets included. Mitigations:
- an "Unencrypted" badge on HTTP endpoints;
- on untrusted networks, an HTTPS endpoint wins whenever it answers within the race window;
- an explicit warning for HTTP to a public IP address;
- pairing tokens rather than the server password. Tokens can only be revoked by changing the password, which signs out every device;
- proposals upstream for TLS and per-device tokens.

**Relay threat model**
- *Sees:* APNs tokens, timing, the coarse kind, padded sizes and the server's outgoing IP address.
- *Cannot:*
  - read or forge content (HPKE auth mode with a pinned sender key);
  - approve anything (approvals use the direct path and are digest-checked).
- *Can:*
  - drop or delay pushes, which delivery health makes visible;
  - send generic spam, but only with a stolen send token (rate limits apply, and tokens are revocable per server).
- A leaked APNs key allows generic spam only.

**Approvals from the lock screen**
- The device must be unlocked.
- High-risk requests cannot be approved from a notification, and "always" is never offered there.
- The digest is checked, the APNs expiration is short, and the alert is replaced once the request is resolved.
- Nothing is approved when a timeout expires.
- Open comes first, so Watch Double Tap is safe.
- Every approval is recorded in an audit list.
- Live Activity buttons are limited to Open and Stop.

**Data at rest**
- The cache is under data protection, with an option to keep metadata only.
- The diagnostics export strips prompts and secrets.
- No third-party analytics by default.

**Untrusted input**
- QR and link payloads are validated like the reference parser.
- Deep links never carry credentials.
- Rendered Markdown never loads remote images automatically and never opens a link without a tap.

## 6. Testing strategy

1. **Fixture decoding** (Swift Testing).
   - `Tools/fixture-recorder` records REST bodies, SSE streams and terminal sessions from a real server for about 20 scenarios: each tool, permission, question, subagent, compaction, revert, fork, steer and queue, interrupt, retry, shell and terminal.
   - Tests require zero `.undecodable` results.
   - Mutation passes inject unknown keys, `null`s, `"NaN"` numbers and unknown type names. Known fields must still decode identically, and the stream must keep going.
2. **Projection parity.** Replay each recorded SSE stream through the event handlers, then compare the resulting transcript with the `GET …/message` snapshot taken at the end of the recording. This is the main guard against sync bugs.
3. **Sync engine unit tests**, with a fake transport and swift-clocks. They cover:
   - backoff, the watchdog and the first-frame timeout;
   - the server closing the stream mid-turn after overflow;
   - events arriving during snapshot fetches;
   - gap splicing and outbox retries;
   - 401 and 503 handling, network path changes, background and foreground.
4. **Mock V2 server.** `Tools/mock-opencode` (Bun) replays scripted scenario timelines over real HTTP, SSE and WebSocket, type-checked against the vendored `types.ts` for each server version.
   - XCUITest smoke flows run against it: pair, send, approve, answer, review, terminal.
   - An in-app `ScenarioTransport` plays the same scenario files for SwiftUI previews and for the App Review demo mode.
5. **Snapshot tests** (swift-snapshot-testing, on one pinned simulator). They cover every row type and tool state, the sheets, diff views and inbox rows, in light and dark mode, at the largest Dynamic Type size, at compact and regular widths.
6. **Contract tests in CI** (macOS runner).
   - Install three servers from npm: the oldest supported V2, the latest V2, and V1 1.19.x.
   - Start `opencode serve` with a password and a scripted OpenAI-compatible provider (`Tools/mock-llm`, which streams chunks including tool calls), so runs are deterministic and free.
   - Run the networking and sync suites against them: pairing, prompt, permission, question, revert, fork, terminal, 401, and V1 detection.
   - The same job refreshes the fixtures.
7. **Spec watch** (nightly).
   - Poll npm for new versions of `@opencode/cli`.
   - For a new version, fetch `openapi.json` and `types.ts` at that tag.
   - Run `oasdiff` to detect breaking changes, plus a diff of the event union.
   - Run the contract tests, and open an issue with a summary.
8. **Plugin and relay.**
   - Vitest unit tests, with digest and HPKE vectors shared with Swift.
   - Miniflare tests for the Worker.
   - One end-to-end test through the APNs sandbox to a real device.
9. **Manual soak tests for each release.** An 8-hour streaming session; Wi-Fi to cellular switches; airplane mode; lock and unlock; OpenTunnel; Tailscale; Low Data Mode; the iPhone Duo cover screen.

## 7. Milestones

Sizes are calendar weeks / engineer-weeks.

| Milestone | Scope | Acceptance criteria | Size | Depends on |
|---|---|---|---|---|
| M0 Foundations | XcodeGen project, package skeleton, CI, OCFoundation, fixture recorder, mock LLM, contract harness. Spikes: SSE through OpenTunnel and `tailscale serve`; Worker to APNs over HTTP/2; `LazyVStack` with 2,000 streaming rows; `TextEditor` mentions with IME input. | CI green on Xcode 27; a written go/no-go for each spike | 2 / 4 iOS + 1 TS | — |
| M1 Connection | Server model; pairing (QR, link, manual); Keychain; probe and V1 screen; endpoint racing; `ServerConnection`; foreground/background handling; status UI; diagnostics | Pairing with LAN and tunnel endpoints in under 10 s; survives Wi-Fi/cellular switches and lock/unlock; an 8-hour soak with no stream that looks connected but is dead; a V1 server shows the upgrade screen | 3 / 5 | M0 |
| M2 Read path | All models and events; stores and event handlers; resync, fetch overlays and gap splicing; inbox; project and session lists; transcript and tool renderers; subagent drill-in; pagination; GRDB cache | Projection parity on every fixture; performance budgets met; cached inbox shown within 300 ms of a cold start; offline browsing works | 4 / 8 | M1 |
| M3 Write path | Composer (mentions, slash commands, shell, attachments); steer, queue and stop; queue panel; outbox; drafts; pickers; new session and worktree; rename, delete, fork, compact, undo; in-app permission and question sheets | No prompt or draft lost across kill, relaunch or backgrounding; retries proven not to duplicate prompts; approve or answer round trip under 1 s on the LAN | 4 / 8 | M2 |
| M4 Review and files | Per-turn changes card; diff viewer (unified and split, word diff, highlighting); VCS review; line comments into the prompt; file browser and viewer | A 5,000-line diff scrolls smoothly; a review comment lands in the prompt | 3 / 5 (can run in parallel with M3) | M2 |
| M5 Push and Live Activities | Plugin, relay, HPKE, NSE, notification categories and actions, digest checks, presence, delivery-health UI, Live Activity | From an approval push, "Allow once" on the lock screen runs the tool within 5 s end to end; a tampered digest is refused; no push while the app is open | 4 / 4 iOS + 4 TS (TS work starts during M2) | M3 |
| **MVP** | M0 to M5 | Daily driver on iPhone and iPad | ~17–20 weeks | |
| M6 iPad and system integration | Inspector, menu and shortcuts, multi-window, App Intents, Spotlight, widgets, controls | Shortcuts can run the intents; two sessions open in two windows | 3 / 5 | M3 |
| M7 Terminal | Terminal list, SwiftTerm, key bar, resume, shell output | `vim` and `htop` usable; resuming after backgrounding loses no output | 2 / 3 | M2 |
| M8 Parity | Providers and integrations, MCP, saved permissions, config viewer, worktrees and moving sessions, voice, stats, export, side questions | Every core parity item in report 02 is either covered or explicitly declined | 4 / 6 | M3 |
| M9 Launch | Accessibility, localization groundwork, a performance pass, App Attest, hosted demo server and demo mode, privacy policy, external TestFlight | Passes App Review; at least 99.5 % crash-free sessions in beta | 3 / 5 | all |

**Later:**
- SSH tunnel (Citadel);
- push-to-start and multi-session Live Activities;
- Notification Content extension;
- ID-only push;
- Apple Watch;
- persistent terminals;
- durable-log replay (`session.log`);
- share extension;
- Foundation Models for provisional titles and voice commands.

**Work outside the iOS app**
- the plugin (npm);
- the relay (Workers and D1, APNs key custody, monitoring);
- the hosted demo server for App Review;
- `mock-llm`, `mock-opencode`, `fixture-recorder` and the spec-watch CI;
- an onboarding web page ("Pair your phone", "Enable notifications");
- the privacy policy;
- upstream proposals: a vendor-neutral push target, per-device tokens, Bonjour `_opencode._tcp`, and native TLS.

## 8. Risks and open decisions

### Risks

| Risk | Mitigation |
|---|---|
| The V2 API changes fast (about 6 releases a week, no API version) | Tolerant models with `.unknown` cases; capability gates; daily contract tests against the latest release; spec watch; weekly TestFlight builds |
| A free first-party iOS app from the protocol's owner (its beta already has push through an unpublished plugin, and several servers) | Win on reliability, private and actionable approvals, iPad, and review depth. Support official pairing and OpenTunnel from day one. Render its Voice messages. |
| Push needs a plugin the user must install | One copyable command, detection and guided setup. The app is fully useful without push. Propose an upstream push-target contract. |
| Running the relay (APNs key custody, abuse, cost, Workers HTTP/2) | Open-source relay; M0 spike with a Fly.io fallback; rate limits; App Attest; monitoring and the delivery-health UI |
| OpenTunnel outages and DNS blocking | Endpoint racing across several addresses; LAN and Tailscale fallbacks; specific diagnostics |
| iOS stops the app in the background | Push and Live Activities; fast resync; persisted outbox; background tasks around sends |
| Plain HTTP on the LAN | Badges, preference for HTTPS, warnings, upstream TLS proposal |
| Slow transcripts in long sessions | One observable per content item; frozen blocks and turns; paging; memory eviction; `UICollectionView` fallback; budgets enforced from M2 |
| Pre-1.0 or single-maintainer libraries (Textual, SwiftTerm, Citadel, tree-sitter grammars). Citadel pins a personal fork of swift-nio-ssh; swift-tree-sitter has a stray old 0.25.0 tag that wins under `from:`; TailscaleKit has no privacy manifest (ITMS-91053) | Protocol boundaries, exact version pins, readiness to fork |
| Client-minted IDs on a phone with a wrong clock | Server-corrected, always-increasing IDs; revert hiding by position |
| Pending permissions vanish when the server restarts or runs `location.reload` | Treat notifications as hints; re-check before acting; resync on reconnect |
| App Review (demo access, Local Network permission, guidelines 4.2.x) | Hosted demo server and demo mode; clear permission strings; present the app as a native API client |

### Open decisions for the product owner

1. V2 only (recommended), or also a second protocol layer for V1.
2. Business model: free or paid, and who pays for the relay. Licensing was decided on 2026-10-21: the app is open source under GPL-3.0-only, and the plugin and relay will be MIT-licensed.
3. Default push content: sealed summaries (recommended) or IDs only. Whether the relay may see the kind of notification.
4. The plugin's name and npm scope, and whether to approach Anomaly about a shared push contract or interoperability with the official app.
5. Minimum OS: iOS 26.4 (recommended) or 27.
6. Whether plain HTTP to `*.ts.net` names or public IP addresses is allowed at all.
7. Approvals from the lock screen: on by default with risk tiers (recommended), opt-in, or off.
8. Whether transcripts are cached on the device by default, and for how long.
9. Telemetry: none, or opt-in crash reporting.
10. MVP scope: keep the terminal (M7) and voice (M8) after the MVP as proposed, or pull them in.
11. Whether to allow "Designed for iPad" on Mac at launch.
12. The app's name and branding with respect to the opencode trademark.
13. Android later? If so, keep the relay and plugin platform-neutral (an FCM path).

### Critical files for implementation

Paths under `packages/` refer to github.com/sst/opencode at commit `d0732ea`.

- `research/01-opencode-server-api.md`: the protocol, the event catalogue and the gotchas.
- `packages/client/src/solid/data.ts`: the event handlers, outbox, fetch overlays and pending-status rules to port.
- `packages/client/src/solid/connection.ts`: the stream lifecycle, watchdog and resync timings.
- `packages/app/src/servers/connect/pairing.ts`: pairing parsing and redemption.
- `packages/core/src/plugin/host.ts`, with `packages/core/src/bus.ts` and `packages/core/src/kv.ts`: per-location plugin event scoping and global plugin storage, which the push plugin design relies on.