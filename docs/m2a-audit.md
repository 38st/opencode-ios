# M2a completion audit

Audited the M2a checkpoint commit against the original brief. “Checkpoint” describes the tree before this continuation; “Result” describes the completed working tree. No M2b screens, commits, branches, or global tool changes are part of this work.

| Deliverable | Checkpoint | Result | Evidence / completion |
| --- | --- | --- | --- |
| SessionInfo: times, revert, parent, cost, tokens | Done | Done | `OCModels/SessionInfo.swift`, `WireValue.swift`; REST and snapshot decoding |
| Every SessionMessage row | Done | Done | Eleven row cases, unknown and undecodable fallbacks; fixture projection parity |
| AssistantContent and ToolState | Done | Done | Text, reasoning, tool; streaming/running/completed/error; nested tool content |
| Inbox steer/queue, permission requests, all form fields | Done | Done | `InboxItem.swift`, `FormInfo.swift`; six field types, form states, tolerant delivery |
| Project, Location, FileDiff, ShellOutput | Done | Done | Raw-preserving typed models; location remains unwrapped as the server specifies |
| Agent/model/provider rendering catalogs | Done | Done | `Catalogs.swift`, `ReadDetails.swift`; names, colors, variants, capabilities, pricing |
| Every V2 event and payload; nonfatal fallback | Done | Done | 93 fixed discriminators plus open `rpc.*`; source-union comparison passes |
| Lenient tool inputs and V1 aliases, raw JSON retained | Done | Done | `ToolInputs.swift`; all requested tools plus bash/task/apply_patch/todo history |
| Tolerant decoding and lossy union arrays | Partial | Done | Expanded nested-union, REST, snapshot, null/missing, NaN, unknown-key/type and malformed-element checks |
| Session list filters and pagination | Done | Done | `ReadEndpoints.sessions`, cursor drops filter/order parameters |
| Active sessions, projects, location, session info | Done | Done | Typed read endpoints; source-correct envelopes |
| Message pages: desc/asc/cursors | Done | Done | Default newest 50; cursor requests omit order; separate jump-to-start query |
| Inbox, location/session permissions and forms, individual reads | Done | Done | Typed `DataResponse`/`Located` endpoints |
| Diff, shell output, viewed marker | Done | Done | Typed endpoints; viewed accepts empty 204 response |
| GRDB 7 pinned exactly, migration/schema v1 | Done | Done | GRDB **7.8.0**; all eleven specified tables plus import marker; in-memory migration tests |
| PersistenceWriter, CacheStore, DraftStore, OutboxStore | Done | Done | Actor-owned writer; exact outbox bytes; drafts keyed by session/directory |
| Raw JSON plus indexes; tolerant cache reads | Done | Done | Raw JSON round trips, including unknown messages; indexed session/message fields |
| Two-second write-behind, turn-end/background flush | Done | Done | Virtual-clock debounce and no-per-delta write tests; store/registry lifecycle flushes |
| Retention: 200 sessions / 300 MB, LRU | Done | Done | Access timestamps; SQLite used-page budget; count and byte eviction tests |
| App-sandbox database and file protection | Done | Done | Application Support/Opencode/cache.sqlite; iOS completeUntilFirstUserAuthentication for directory/database/WAL/SHM |
| Draft attachment paths and 300 ms/inactive saves | Done | Done | Application Support/Drafts; added virtual-clock debounce and explicit-flush regression |
| M1b JSON server import, protocol preserved | Done | Done | Transactional one-time import; added corrupt-import retry and existing-record preservation test |
| Observable stores and item-level delta observation | Done | Done | ServerStore/ReadStore, SessionModel, TranscriptModel, MessageModel, ContentItemModel; observation test |
| Revalidating catalogs, canonical/requested aliases | Done | Done | Single-flight cells discard invalidated responses; cache-seeded rendering catalogs |
| Idempotent handlers and pending-status rules | Partial | Done | Fixture events replayed twice; explicit queued/starting/stranded/steering coverage; unknown-session lifecycle now updates running set; terminal events preserve optional usage and merge compaction metadata like the projector |
| Duplicate and backwards sequence handling | Partial | Done | First session-creation event now records its sequence; seen sequences drop, unseen backwards sequences refetch, gaps allowed, snapshots reset |
| Held-row deltas, authoritative ends, joinedMidStream | Done | Done | `StreamingHandlers.swift`; held/missing row, duplicate delta, authoritative text/reasoning/tool handling |
| Position-based revert hiding | Done | Done | Boundary index first, ID fallback; disconnected revert and fetch-race tests |
| Child attention and unknown parent fetch | Done | Done | Ancestor walk with cycle guard; child/grandchild permissions and unknown-root tests |
| Unknown/undecodable durable session-event refetch | Partial | Done | True trailing 500 ms debounce, both fallback paths, info plus newest messages, no ephemeral refetch; events during fetch schedule another pass |
| Resync on every server.connected and backlog overflow | Done | Done | M1b extension wiring; outbox, active/project/root reads, scoped requests, open transcripts, catalogs |
| Fetch overlays and deletion markers | Partial | Done | Exact shell/compaction/previous-assistant rows protected instead of last-ten heuristic; worktree info changes also overlaid |
| Gap splice overlap / four older pages / reset | Done | Done | Tests cover all branches and revert while disconnected |
| Newest/older pagination and jump to start | Done | Done | Added explicit asc/no-cursor/limit-50 jump regression; concurrent revert cannot restore deleted rows |
| At most six resident transcripts, LRU/cache restore | Partial | Done | Release victims before awaiting cache I/O; stale concurrent opens cannot reattach evicted windows; concurrent twelve-open regression; one registry-wide budget shared across servers |
| Cache-first projects, sessions, transcripts | Done | Done | Added blocked-network test proving cached projects, session, catalog and transcript are visible before responses |
| Latest stable npm 2.x and every recorded version | Partial | Done | Registry still reports **2.0.32**; networking parser/probe fixture tests now discover all versions instead of hardcoding it |
| Start/end REST snapshots for every session scenario | Partial | Done | Existing 17 session scenarios have all five collections; recorder now follows every message cursor. Pairing/PTY/V1 are explicitly non-session scenarios |
| Zero unknown and undecodable across REST/SSE fixtures | Partial | Done | Added snapshot and nested-union coverage, including delivery/form state/tool results; all fixture streams checked |
| Mutation stream survival and unchanged known fields | Partial | Done | REST/SSE/nested mutation passes; each recorded frame preceded by unknown and malformed frames in incremental parser tests |
| Projection parity for every scenario | Done | Done | Start snapshot + duplicate replay + full end state comparison; 20 scenario files (17 session projections, 3 non-session cases) |
| Sync regression suite required by brief | Partial | Done | New tests strengthen debounce, initial seq, unknown running sessions, distant completion overlays, concurrent/global LRU, cache-first, jump and terminal optional-field rules |
| Persistence test suite required by brief | Done | Done | Migration, write-behind, retention, import; additional draft clock and failed-import retry tests |
| Live normal and interrupted-stream projection parity | Done | Done | `ProjectionLiveTests` through Tools/contract; owned sandbox server and mock only |
| MainActor text-delta micro-benchmark | Done | Done | 1000 deltas, average asserted below 0.5 ms; measurement now printed |

## Scope and design findings

- §2.5 says both “drop seq <= lastSeq” and “a sequence going backwards triggers resync.” These conflict for an unseen older sequence. The implementation drops previously seen sequences and refetches for an unseen backwards sequence; snapshots reset sequence tracking.
- §2.6's schema omits the access timestamp needed for LRU and a durable one-time import marker. The implementation adds `session.accessed_at` and `cache_migration`.
- The 300 MB budget measures allocated SQLite pages excluding free pages and evicts cache sessions; drafts, outbox and server records are retained. This is a cache budget, not permission to discard unsent user data, and transient WAL/file overhead can exceed it.
- The source projector updates `time.idle` at execution completion without also advancing `time.updated`; handlers follow the source.
- The broad location-envelope rule has a source exception: GET /api/location returns Location directly, while location-scoped list/read responses use Located.
- Optimistic composer actions, notification/App Group snapshots and terminal UI remain later-milestone work. M2a supplies persistence, prompt outbox draining and read/event hooks; it does not add M2b screens.

## Verification

Logs are in `.build/m2a-completion/` (ignored build artifacts).

| Command | Result |
| --- | --- |
| `swift test --package-path Packages/OpencodeKit` | **130 tests pass**; live and optional Keychain tests skipped in this fast run. All 60 fixture files / 418 SSE frames decode without unknown or undecodable values. All 20 scenario files pass projection checks. |
| `node --test Tools/mock-llm/*.test.mjs Tools/opencode-sandbox/*.test.mjs Tools/fixture-recorder/*.test.mjs Tools/ui-smoke/*.test.mjs Tools/contract/*.test.mjs` | **15 pass** |
| `node Tools/contract/check-events.mjs <reference>/packages/client/src/promise/generated/types.ts` | **93 fixed events plus rpc.* match**; reference read as text only |
| `node Tools/contract/index.mjs` | **Pass** on 2.0.32 / V1 1.19.3; normal and interrupted projection parity, watchdog recovery, process cleanup and isolation |
| `node Tools/ui-smoke/index.mjs` | **Pass**: manual V2, pairing link, wrong-password repair, V1 upgrade flow, all 44 snapshot comparisons, screenshots, app install/launch, cleanup and isolation. Earlier attempts were interrupted by another simulator app taking focus; the final run passed with explicit activation/readiness checks. |
| `xcodebuild -project Opencode.xcodeproj -scheme Opencode -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/DerivedData build` | **BUILD SUCCEEDED** on the final source |
| `git diff --check` | **Pass** |

The delta benchmark measured **6.95 microseconds per item** on the MainActor (1000 deltas; asserted average below 0.5 ms). npm's newest stable 2.x remains **2.0.32**, so no additional version needed recording. The existing session snapshots contain at most eight rows, so none was truncated by the former 200-row recorder limit.

Environment observations: the owned test runner inherited background scheduling, which stalled swift-clocks' background yields; clearing that policy on owned runner processes restored normal execution. Xcode changed externally during verification (a CoreSimulator service version mismatch interrupted one build); fresh processes report **Xcode 27.1 / 27A9275**, and the final build and fast suite pass. No toolchain or simulator installation/configuration was changed by this task. The smoke test now explicitly activates this app and waits for its add-server sheet.

Isolation comparison: the before/after metadata inventory of the four personal opencode directories and `~/Library/LaunchAgents` has **zero changed paths**. Every completed sandbox harness also reports successful cleanup and an unchanged isolation audit. These inventories are depth-two path/mtime comparisons, not proof against unrelated concurrent writes: the user's OpenCode desktop app may independently change its own files. Only Tools/opencode-sandbox launched opencode, through pinned npx packages and sandboxed paths; the reference clone was never executed.

No M2a implementation or verification items remain. No commit was created.

## Changed files in this continuation

- `Packages/OpencodeKit/Sources/OCModels/MCPStatus.swift`
- `Packages/OpencodeKit/Sources/OCSync/EventHandlers.swift`
- `Packages/OpencodeKit/Sources/OCSync/ReadResync.swift`
- `Packages/OpencodeKit/Sources/OCSync/ReadStore.swift`
- `Packages/OpencodeKit/Sources/OCSync/ServerRegistry.swift`
- `Packages/OpencodeKit/Sources/OCSync/ServerStore.swift`
- `Packages/OpencodeKit/Sources/OCSync/StreamingHandlers.swift`
- `Packages/OpencodeKit/Sources/OCSync/TranscriptResidency.swift`
- `Packages/OpencodeKit/Tests/OCModelsTests/WireModelTests.swift`
- `Packages/OpencodeKit/Tests/OCModelsTests/WireMutationTests.swift`
- `Packages/OpencodeKit/Tests/OCNetworkingTests/HTTPProbeTests.swift`
- `Packages/OpencodeKit/Tests/OCNetworkingTests/SSEParserTests.swift`
- `Packages/OpencodeKit/Tests/OCNetworkingTests/TestSupport.swift`
- `Packages/OpencodeKit/Tests/OCPersistenceTests/PersistenceTests.swift`
- `Packages/OpencodeKit/Tests/OCSyncTests/ReadRegressionTests.swift`
- `Packages/OpencodeKit/Tests/OCSyncTests/ReadStoreTests.swift`
- `Tools/README.md`
- `Tools/fixture-recorder/scenarios.mjs`
- `Tools/fixture-recorder/snapshots.test.mjs`
- `UITests/ServerSmokeTests.swift`
- `docs/m2a-audit.md`
