# M3a implementation and verification

M3a adds the durable write core, draft attachment storage, optimistic reconciliation, permission and question sheets, and transcript polish. Composer, pickers, new-session UI and session-action controls remain M3b work. No commits, pushes, branches, protected design documents, global tools or simulator installations were changed.

## Implementation

- `OCNetworking/WriteEndpoints.swift` covers prompts, interrupt/resume, inbox delivery/cancel, agent/model, commands, shell, session create/rename/delete/fork/compact, revert stage/commit/redo and permission/form replies. Only typed settlement errors count as success; unrelated 404/409 responses still fail. Commands are never retried automatically.
- `OutboxProcessor`, `WriteStore` and `OutboxStore` persist immutable admission bytes before sending, serialize admissions, run preludes, reconcile HTTP/event acknowledgements, retry while connected, and gate launch-old entries behind explicit confirmation. A stale entry also holds newer admissions in that session. An acknowledged create gates its prompts; a lost create response is recovered by probing the original ID. Sends hold a background lease.
- Optimistic prompt/create, rename/delete, approval, delivery and cancellation changes survive older in-flight snapshots. Cancelling a queued prompt first restores its text and inline attachments to the draft. Failed prompts expose Edit and resend with a fresh ID. Confirmed revert boundaries are rechecked before retrying the prelude.
- `DraftStore` archives attributed text, including mention attributes, in GRDB and owns attachment files below Application Support/Drafts/<id>/. It debounces for 300 ms and flushes on scene inactivity/backgrounding. OCSync exposes the shared store for M3b.
- `FeatureApprovals` provides matching-tool cards, a bounded root/child request dock, full permission review, copyable action/resources/directory/save patterns, edit previews and risk tiers. Allow always and high-risk Allow once require injectable device-owner authentication. Replies are store-owned so dismissing an optimistic sheet cannot cancel its request. Reject warns about sibling requests and explains the effect of omitting a note. No automatic approval mode exists.
- `FormRenderer` supports every current field type, custom answers, conditions, defaults, required/constraint validation, review, external completion and optional dismissal reasons.
- Transcript tool groups use Used N Read, Glob, Grep; details are inline. Compact hides empty Turn complete rows. The jump pill omits zero and reserves space below the timeline. Opening or closing a disclosure pauses follow-latest so expanding a group near the bottom keeps the inspected content in view.

## Verification before the review fix

| Command | Result and evidence |
| --- | --- |
| `xcodegen generate` | Passed after adding the approval snapshot target and Face ID usage string. |
| `swift test --package-path Packages/OpencodeKit` | Passed: 180 registered tests, including four expected skips (three sandbox-only live tests and the opt-in host Keychain test). `.build/m3a-swift-final.log`; no compiler warnings. |
| `node --test Tools/mock-llm/*.test.mjs Tools/opencode-sandbox/*.test.mjs Tools/fixture-recorder/*.test.mjs Tools/ui-smoke/*.test.mjs Tools/contract/*.test.mjs` | 21 passed. `.build/m3a-node-final.log`. Isolation-warning scenarios deliberately emit warnings inside temporary test roots. |
| `node Tools/contract/index.mjs` | Passed against V2 2.0.32 and V1 1.19.3. All three Swift live tests passed, including all 15 M3a projection checkpoints. `.build/m3a-contract-final.log`. The final audit has four personal-file activity warnings; see Isolation below. |
| `node Tools/ui-smoke/index.mjs --read-flows-only` | Passed after the disclosure scroll fix: all three approval flows, iPhone read flows and iPad split/portrait flows. `.build/m3a-ui-disclosure.log`; `.build/ui-smoke/ui-1792257909355/`. |
| `node Tools/ui-smoke/index.mjs` | **Passed completely**: 19 iPhone tests plus the iPad read test; zero failures/skips/runtime warnings, and zero compiler/analyzer warnings or build errors. Includes the complete snapshot matrix, rendered 5,000-row/prepend check (1.220 s), app restoration and cleanup. `.build/ui-smoke/ui-1792258240522/{Smoke,iPad}.xcresult`; `.build/m3a-ui-smoke-final.log`. |
| `node Tools/ui-smoke/index.mjs --ipad-only` | Passed: both approval and read tests, zero failures/runtime warnings; all three approval flows, split/portrait captures, app restoration and cleanup. `.build/ui-smoke/ui-1792256379215/Smoke.xcresult`; `.build/m3a-ui-ipad-final.log`. Allow once: **0.145755333 s**. |
| `python3 Tools/design-reference/compare.py` | Passed: 66 D1 comparisons. `.build/design-compare/index.html`. |
| `python3 Tools/design-reference/compare-read.py` | Passed: five refreshed transcript/read comparisons. `.build/design-compare/m2b.html`. |
| `python3 Tools/design-reference/compare-approvals.py` | Passed: 69 comparisons, including all permission/question state baselines and five live UI captures. `.build/design-compare/m3a.html`. |
| `xcodebuild -project Opencode.xcodeproj -scheme Opencode -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/DerivedData build` | Passed on Xcode 27.1, with no compiler warnings. `.build/m3a-build-final.log`. |
| `git diff --check` | Passed. Changes remain uncommitted. |

Approval timing uses the button handler's monotonic start time and the first matching `session.shell.created` event, rather than XCTest's post-tap idle wait or tool completion. The final full run measured **0.057406084 s (57 ms)**, below the 1 s target, from the iPhone simulator to the local Tools/opencode-sandbox server. The successful iPad run measured 0.145755333 s. This is not a physical-device Wi-Fi measurement. The final iPhone measurement is saved in `.build/ui-smoke/ui-1792258240522/approval-latency.json`.

The snapshot matrix adds 68 images (permission/question states plus the zero/nonzero jump pill) at widths 393 and 820, both themes and accessibility5. It updates 60 affected transcript/tool images. Visual review checked full resources, wrapped labels, validation/review states and button layout. Earlier verification found and fixed an accessibility identifier collision, a 5,000-row test that unintentionally used Compact's new filtering, stale tool baselines and approval fixture sessions disturbing a later read test.

The initial M3a verification incorrectly treated landscape setup as sufficient to expose the iPad connection-status panel. The orchestrator reproduced the failure in two later runs. The review fix below supersedes that conclusion. Both tests still mint a fresh one-use pairing link immediately before connecting; runtime-generated links are included in log redaction and its Node regression check.

An earlier full run passed all iPhone tests but stalled in CoreSimulator's iPad launch bridge under severe host load. Restarting only the task's simulator ended that attempt with Mach error -308 before any iPad test ran (`.build/m3a-ui-smoke-core-simulator.log`). The focused recovery passed; the complete UI command was then rerun.

A later iPad run exposed follow-latest scrolling an expanded tool group out of view when the collapsed group was near the bottom (`.build/m3a-ui-smoke-disclosure-failure.log`). Disclosure interactions now pause following before changing height. The existing expanded-header and visible-child assertions passed on both devices after this application fix.

The installed Xcode/simulator also emitted SDK build-number parsing, debugger-metadata and duplicate WebKit accessibility-class diagnostics in UI-test logs. These are platform diagnostics; Swift compilation has no warnings and the successful result bundles report no runtime warnings. No global tool or runtime changes were made to suppress them.

## Design/source decisions

- The task explicitly replaces the architecture's older “Explored N files” example with “Used N Read, Glob, Grep”. Its requested “Reject” label takes precedence over desktop “Deny”.
- The source's typed form settlement rule also accepts `FormNotFoundError` (404) for the same form ID. Generic 404/409 responses are not swallowed. External form fields require an explicit true completion answer, matching `core/form.ts`.
- `docs/design.md` still describes approvals as disabled before M3. The implementation enables the M3a approvals while retaining the disabled composer. Proposed documentation update: describe the M3a/M3b split and the outbox operation column added by migration v2. SPEC.md, ARCHITECTURE.md and research were left unchanged.
- Xcode 27.0 is not installed, so it cannot be executed here. The implementation retains Swift 6 language mode and the existing 26.4 deployment target; it introduces no 27.1-only syntax or APIs.

## Isolation

Only Tools/opencode-sandbox launches live opencode processes. The reference clone was read but never executed. The audits verified inherited sandbox profiles and denied-write receipts for both pinned V2 and V1 launches, with successful process cleanup. Earlier personal-root inventories observed changes to `~/.local/share/opencode/log/opencode.log` and `opencode.db-wal`. These were not attributed to sandbox processes; some writers were unattributed and enforcement remained verified. The final complete UI audit observed no such changes.

Earlier contract audit: `.build/opencode-sandbox/audits/contract-1792254078026/comparison.json` (zero failures, enforcement verified, two warning observations). Earlier full UI attempt audit: `.build/opencode-sandbox/audits/ui-1792254255818/comparison.json` (zero failures, enforcement verified, 31 warning observations). These earlier warnings remain in the historical logs; compilation and the successful test bundles have none.

Successful iPad recovery audit: `.build/opencode-sandbox/audits/ui-1792256379215/comparison.json` (zero failures, enforcement verified, six warning observations).

**Final complete UI audit:** `.build/opencode-sandbox/audits/ui-1792258240522/comparison.json` reports enforcement verified, zero failures, **zero warnings**, and no observed personal-root changes.

**Final contract audit:** `.build/opencode-sandbox/audits/contract-1792259248603/comparison.json` reports enforcement verified and zero failures, with **four warning observations**: changes to the personal `~/.cache/opencode` directory, its `models.json`, and two changes to the personal opencode log. Their writers were unattributed. The audit passed under verified enforcement, but the requested blanket warning-free condition could not be achieved for this audit. Other workloads were left running and no warning was suppressed.

The concurrency/module audit found no detached tasks, unsafe isolation annotations, unchecked Sendable declarations in the changed stores, or feature imports of OCNetworking. UI/stores remain MainActor-isolated; persistence, authentication and admission workers own their tasks in actors. Strict-concurrency compilation passes.

## Changed files

- `Packages/OpencodeKit/Sources/FeatureApprovals`: `ApprovalDock.swift`, `FormRenderer.swift`, `PermissionSheet.swift`, `QuestionSheet.swift`.
- `Packages/OpencodeKit/Sources/FeatureTranscript`: `SavedPromptReview.swift`, `SessionScreen.swift`, `SessionTimeline.swift`, `TimelineCollection.swift`, `TimelineRowView.swift`, `ToolRowView.swift`.
- `Packages/OpencodeKit/Sources/OCDesign`: `Metrics.swift`, `TimelineChrome.swift`.
- `Packages/OpencodeKit/Sources/OCModels`: `DraftAttributes.swift`, `FormValidation.swift`, `PermissionRisk.swift`, `WriteInput.swift`.
- `Packages/OpencodeKit/Sources/OCNetworking`: `Endpoint.swift`, `WriteEndpoints.swift`.
- `Packages/OpencodeKit/Sources/OCPersistence`: `DraftFiles.swift`, `LocalStores.swift`, `Schema.swift`.
- `Packages/OpencodeKit/Sources/OCRender`: `TimelineRowBuilder.swift`, `ToolPresenter.swift`.
- `Packages/OpencodeKit/Sources/OCSecurity`: `BiometricGate.swift`.
- `Packages/OpencodeKit/Sources/OCSync`: `ApprovalActions.swift`, `EventHandlers.swift`, `OutboxDrain.swift`, `ReadResync.swift`, `ReadStore.swift`, `SavedPrompt.swift`, `ServerRegistry.swift`, `ServerStore.swift`, `SessionReadActions.swift`, `SessionWriteActions.swift`, `WriteStore.swift`.
- `Packages/OpencodeKit/Tests/ApprovalSnapshots`: `ApprovalSnapshots.swift`.
- `Packages/OpencodeKit/Tests/OCModelsTests`: `FormValidationTests.swift`.
- `Packages/OpencodeKit/Tests/OCNetworkingLiveTests`: `WriteLiveTests.swift`.
- `Packages/OpencodeKit/Tests/OCNetworkingTests`: `WriteEndpointsTests.swift`.
- `Packages/OpencodeKit/Tests/OCPersistenceTests`: `DraftRelaunchTests.swift`.
- `Packages/OpencodeKit/Tests/OCRenderTests`: `TimelineRowBuilderTests.swift`.
- `Packages/OpencodeKit/Tests/OCSyncTests`: `ApprovalTests.swift`, `OutboxDrainTests.swift`, `ReadPerformanceTests.swift`, `WritePathTests.swift`.
- `Packages/OpencodeKit/Tests/ReadSnapshots`: `ReadSnapshots.swift`, `TimelineCollectionTests.swift`.
- `Project, fixtures, tooling and report`: `App/Info.plist`, `Fixtures/source/m3a/form.json`, `Fixtures/source/m3a/permission.json`, `Packages/OpencodeKit/Package.swift`, `Tools/contract/index.mjs`, `Tools/design-reference/compare-approvals.py`, `Tools/opencode-sandbox/process.mjs`, `Tools/ui-smoke/index.mjs`, `Tools/ui-smoke/redaction.test.mjs`, `UITests/ReadSmokeTests.swift`, `docs/m3a-audit.md`, `project.yml`.
- `Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/`: 60 updated PNG baselines.
- `Packages/OpencodeKit/Tests/ApprovalSnapshots/__Snapshots__/`: 68 new PNG baselines.


## M3a review: iPad setup failure

The orchestrator bundles `ui-1792259661332/iPad.xcresult` and `ui-1792260605298/Smoke.xcresult` show the same failure. All three failure hierarchies contain the sandbox's freshly seeded sessions, but no Settings status row. Their recordings show a portrait-width iPad Home sheet, even though XCTest requested landscape. The activity logs show Local Network Continue was found and tapped. This was a presentation bug, not a failed connection, truncated status, stale credential, or a missed three-second explainer window.

Adding the first server replaced the conditional root under the Settings sheet, while the newly created narrow workspace immediately requested its Home sheet. Settings was displaced, removing the status element the test awaited. `ServerRootView` now keeps a stable ZStack presentation host, and `OCWorkspaceShell` defers its Home sheet while Settings or the Local Network explanation is presented. Portrait setup explicitly checks that Settings remains visible after connecting. Instrumented diagnostics confirmed `resolving → connecting → connected`, LAN Healthy, without retries; see `.build/m3a-review/diag2/` for the exported state attachments and `.build/m3a-review/ipad-current.png` for the retained Settings sheet.

Every UI test now starts with `--ui-testing-reset`, scoped to a validated UI-test namespace in DEBUG builds. It removes that test's server records, preference suite (including the Local Network explainer and timeline preset), and all Keychain items in its service before loading. Production records, preferences and credentials are untouched. The reset argument is cleared on the XCTest application after initial launch so a deep-link relaunch preserves the current test's state. Unit tests cover namespace validation, reset idempotence, preference/record isolation, and rejection of production Keychain reset.

The connection pill exposes one accessibility element with the stable `serverConnectionStatus` identifier and a nonlocalized state value. Tests wait for `connected` and require the Local Network explanation after reset. They attach allowlisted current state and transition diagnostics on connection checks and failures, plus a failure screenshot and a credential-redacted accessibility hierarchy. These diagnostics hooks and test preferences are DEBUG-only and enabled only for UI-test namespaces.

Review-fix files: `App/OpencodeApp.swift`; `FeatureServers/{AddServerView,ServerRootView,ServerRow,ServerSettingsView,UITestConnectionDiagnostics}.swift`; `OCDesign/WorkspaceShell.swift`; `OCSecurity/SecretStore.swift`; `OCSync/{ServerRegistry,ServerStatus,UITestStorage}.swift`; `Tests/OCSecurityTests/CredentialTests.swift`; `Tests/OCSyncTests/UITestStorageTests.swift`; `UITests/{SmokeTestCase,ReadSmokeTests,ServerSmokeTests}.swift`; this report. Package-relative paths start at `Packages/OpencodeKit/Sources` or `Packages/OpencodeKit/Tests` as appropriate.

No design/protocol disagreement was found in this review fix. No network timeout or retry policy was changed.

### Review verification

- `swift test --package-path Packages/OpencodeKit`: passed, 183 registered tests, four expected skips (three live contracts run separately and the opt-in host Keychain test), no compiler warnings. `.build/m3a-review/swift-final.log`.
- `node --test Tools/mock-llm/*.test.mjs Tools/opencode-sandbox/*.test.mjs Tools/fixture-recorder/*.test.mjs Tools/ui-smoke/*.test.mjs Tools/contract/*.test.mjs`: 21 passed. `.build/m3a-review/node.log`.
- `node Tools/contract/index.mjs`: passed against V2 2.0.32 and V1 1.19.3; three Swift live tests and all 15 M3a projection checkpoints passed. `.build/m3a-review/contract.log`. Audit `contract-1792261016139`: enforcement verified, zero failures, zero warnings.
- Focused `node Tools/ui-smoke/index.mjs --ipad-only`: both tests passed after the fixes, including portrait setup, all approval flows, read/navigation/deep-link flows and cleanup. `.build/ui-smoke/ui-1792261250063/Smoke.xcresult`; `.build/m3a-review/ipad-debug4.log`. Zero compiler/analyzer/runtime warnings; isolation enforcement verified, zero failures and warnings. Allow once: 0.033293459 s.

Debugging runs exposed and resolved a Swift 6 teardown-isolation error, duplicate accessibility children in the connection pill, and the reset argument being reused by XCTest's deep-link relaunch. Failure attachments from those runs verified the new diagnostics path. They precede the required consecutive full-run verification.


## M3a landing: expired pairing link

The harness minted a five-minute, single-use pairing code before `xcodebuild`. In orchestrator run `ui-1792370337998`, the build and preceding read tests delayed `ServerSmokeTests` until approximately 6.5 minutes after issuance. The server correctly rejected the expired code; the first server remained connected and LAN Healthy.

`ServerSmokeTests` now requests `POST /api/pair` with the sandbox's Basic credentials immediately before typing the link. The existing authenticated `api` helper moved from `ReadSmokeTests` to `SmokeTestCase`. Both pre-build pairing calls and the pairing-link environment variable were removed from the iPhone/iPad harness paths. Runtime-link regex redaction and the existing Node regression test remain unchanged; that test already covers a link absent from the environment. The pre-build fixture audit found only persistent session IDs, sandbox-lifetime passwords, URLs, directory and run ID remaining, with no other expiring or single-use value deferred until UI execution.

Verification also exposed a separate legacy-server test assumption: an initial transport timeout settled setup in Settings, and the retry then identified V1 without automatically opening its detail screen. The failure screenshot and diagnostics show the correct `incompatible` state and “Update opencode” row. The test now opens that row if it remains in Settings before checking the upgrade screen; the normal immediate-navigation path still works. No app behavior or timeout was changed, and the keyboard tip was not involved.

Files changed for this fix: `UITests/ServerSmokeTests.swift`, `UITests/ReadSmokeTests.swift`, `UITests/SmokeTestCase.swift`, `Tools/ui-smoke/index.mjs`, and `docs/m3a-audit.md`. No application code, simulator settings, design/specification/research documents, or Git history were changed. No documentation disagreement was found.

Verification:

- `node --test Tools/mock-llm/*.test.mjs Tools/opencode-sandbox/*.test.mjs Tools/fixture-recorder/*.test.mjs Tools/ui-smoke/*.test.mjs Tools/contract/*.test.mjs`: 21 passed, zero failures or skips; `.build/m3a-landing-fix/node.log`.
- The first `node Tools/ui-smoke/index.mjs --skip-snapshots` attempt stalled before XCTest launched and was interrupted. Its build result reports success with zero warnings; its isolation audit verified enforcement with zero failures or observations. Evidence: `.build/ui-smoke/ui-1792371737048/Smoke.xcresult`, `.build/m3a-landing-fix/ui-smoke.log`, and the process samples in `.build/m3a-landing-fix/`. This attempt is not counted as a UI pass.
- Retry `ui-1792372605275` passed both read tests and the fresh-pairing checks (two connected servers), then failed the legacy-screen navigation assumption at `ServerSmokeTests.swift:53`. Build and runtime warnings: zero. Allow once: 0.300480209 s. Isolation enforcement verified with zero failures or observations. Bundle: `.build/ui-smoke/ui-1792372605275/Smoke.xcresult`; failure attachments: `.build/m3a-landing-fix/retry-attachments/`.
- With the legacy navigation fix, `ui-1792374177321` passed `testReadScreens` and `testServerFlows`. `testApprovals` could not launch the app because XCTest timed out acquiring a background assertion (`SmokeTestCase.swift:13`); the bundle records that infrastructure failure. Isolation enforcement verified with zero failures; one warning recorded an unattributed modification-time change to `~/.local/share/opencode/log` (no observed writer). Bundle: `.build/ui-smoke/ui-1792374177321/Smoke.xcresult`; log: `.build/m3a-landing-fix/ui-smoke-final.log`.
- Final unchanged `node Tools/ui-smoke/index.mjs --skip-snapshots`: passed (exit 0), all three iPhone UI tests passed, including `ServerSmokeTests`; zero compiler, analyzer or runtime warnings. Allow once: **0.091847917 s**. Bundle: `.build/ui-smoke/ui-1792375137893/Smoke.xcresult`; log: `.build/m3a-landing-fix/ui-smoke-launch-retry.log`. Isolation audit: enforcement verified, protected roots unchanged, zero failures or observations; process cleanup passed. The harness skipped its optional iPad follow-up because the available simulator inventory contained only `iPhone 17 Pro`; no simulator was created or reconfigured.
- `git diff --check`: passed. The requested checks are complete; full snapshot runs and back-to-back full verification remain reserved for the orchestrator. No commit, push or branch was created.

## M3a landing verification

Run by the orchestrator after the expired-pairing-link fix.

- The `opencode-ios iPad` simulator had been removed from the device set, so a full run would have skipped the iPad flow. It was recreated with the model and runtime recorded in the earlier iPad bundles: iPad Air 11-inch (M3), iOS 26.5 (23F77). No other simulator or runtime was changed.
- Two consecutive full `node Tools/ui-smoke/index.mjs` runs passed:
  - `ui-1792385812429`: 19 of 19 iPhone tests and the iPad test passed, with no skips. Allow once took 0.098 s. The isolation audit verified enforcement, with one warning: an unattributed modification-time change to `~/.local/share/opencode/log` at 05:52:57Z.
  - `ui-1792389994472`: 19 of 19 iPhone tests and the iPad test passed, with no skips. Allow once took 0.105 s. The isolation audit verified enforcement, with zero warnings.
- The log warning fell at the same minute and second as the one in the failed run `ui-1792370337998` an hour earlier (00:52:57Z). This points to an hourly writer outside the sandbox.
- No package, app or project file changed after the review verification's `swift test` pass (183 tests), so it was not rerun. `git diff --check` passed.
