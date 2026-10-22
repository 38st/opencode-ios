# M4 implementation and verification

M4 connects the existing workspace panel to session review, turn diffs, files and the shared composer draft. No branch, global tool, dependency, simulator or runtime was created or changed. SPEC.md, ARCHITECTURE.md and research/ remain unchanged. The orchestrator updated docs/design.md.

## Implementation

- OCModels adds typed VCS responses, review sources/state, shared path mapping, file content/link parsing and line comments. FileDiff keeps integer counts, tolerates unknown status and saturates aggregate counts. The shared integer decoder preserves full-width integer values without a lossy Double conversion.
- OCNetworking adds VCS read/diff/init and an fs.read-only byte response path with Range, If-None-Match, 200/206/304/416 and segment encoding. JSON identity checks remain on other routes; 503 messages reach the UI.
- OCSync owns per-session ReviewModel, FilesModel and per-turn TurnDiffModel instances outside the timeline observation graph. Review source, selected/open files and Reviewed digests persist through GRDB. Migration v4 adds review state and draft comments, retaining v1 reviewed_files and immutable outbox bytes.
- OCRender parses jsdiff and Git patches, reconstructs old/new text, pairs split rows and word differences, collapses context and runs the existing tree-sitter highlighter on concurrent workers. The shared grammar mapping serves both viewers; highlighter caches are bounded by bytes. Malformed patches become raw text.
- OCDesign supplies one UICollectionView renderer for review, file source and inline/full tool diff cards, with native drawing, pinned accordion headers, context expansion, shared horizontal offset, off-main wrapping metrics, scalable gutters, long-press range selection and accessible comment/copy actions.
- FeatureReview provides width-based tree/preview and accordion layouts, source selection, counts, filtering, Reviewed state, current images/binary fallbacks, full turn navigation and comment editing. FeatureFiles adds lazy tree/find, open files, source/Markdown/image/Quick Look views, ranged loading, bounded memory/disk caches, find, links, mentions and copy path.
- Composer comments persist and encode as reference notes/metadata/file parts. Durable admission clears them; commands retain them. Restores recover live annotations. The transcript uses displayText plus comment cards and hides comment file parts.
- File links extend the existing Markdown path: relative/file links survive sanitization, unsupported schemes and image attachments remain stripped, and completed text uses its enclosing message's completion state (text parts have no timestamp). Inline-code paths are linked only after the file lookup succeeds. Find in file prepares every occurrence off the main actor and highlights the current match separately.
- The shared review fixture seeds a separate Git project, feature branch, working changes, scripted edit/create/delete turns and the deterministic 5,000-line rewrite. Existing project fixtures are retained. A separate no-VCS directory exercises initialization.

## Verification

The results below distinguish completed acceptance proofs from the combined regression run’s setup failures.

| Command | Result and evidence |
| --- | --- |
| `xcodegen generate` | Passed. `.build/m4-r1-xcodegen-acceptance.log`. |
| `swift test --package-path Packages/OpencodeKit` | 257 tests, four expected skips, zero failures and no compiler warnings (`.build/m4-r1-swift-acceptance.log`). Existing performance budgets pass. An earlier run under concurrent host load measured 295.73 ms and failed its unchanged 250 ms budget (`.build/m4-r1-swift.log`); the standalone rerun passed. |
| Node test globs from the brief | 32 passed, zero failures/skips. `.build/m4-r1-node-acceptance.log`, including the receipt-read race regression. |
| `node Tools/contract/index.mjs` | Passed all three live Swift tests and existing Node checks against V2 2.1.2 / V1 1.19.3, including M4 endpoints, ranged/ETag reads, comments and projection parity. `.build/m4-r1-contract-acceptance.log`; isolation: `.build/opencode-sandbox/audits/contract-1792608828024/comparison.json`. An earlier run had an interrupt/resume ordering mismatch; both unchanged reruns passed. |
| Official UI capture and five comparison scripts | Full capture passed: 296 official UI captures at 2.0.32, including 112 M4 captures (`.build/m4-r1-design-reference.log`). All five comparisons passed: 66 D1, five M2b, 69 M3a, 216 M3b and 488 M4 pairs (`.build/m4-r1-compare-acceptance.log`, `compare-read-acceptance.log`, `compare-approvals-acceptance.log`, `compare-composer-acceptance.log`, `compare-review-acceptance.log`, each with the `m4-r1-` prefix under `.build/`). |
| Snapshot baselines and iOS regressions | The non-recording run passed ServerSnapshots (5 tests), ReadSnapshots (8), ApprovalSnapshots (3), ComposerSnapshots (7), and the Review changes, turn-card, renderer and comment methods. The final file method stalled under host load above 700 without an assertion failure; the owned run was stopped. Evidence: `.build/m4-r1-snapshots-acceptance.log`. All four ComposerEditorTests subsequently passed, and the harness coverage assertion confirmed each test (`.build/m4-r1-files-and-editor-acceptance.log`, `.build/m4-r1-editor-coverage.log`). The first retry selected no file test because its Swift Testing method filter omitted `()`; the corrected file-only invocation is recorded separately. |
| iPhone app build | Passed with no warnings (`.build/m4-r1-build-acceptance.log`). |
| Full UI smoke including iPad | The complete focused iPad review suite passed all three tests (`.build/m4-r1-ipad-review-final.log`, `ui-1792608092558/Smoke.xcresult`). Four combined full-run attempts stopped during sandbox setup before xcodebuild/UI tests: `.build/m4-r1-ui-full.log`, `.build/m4-r1-ui-full-retry.log`, `.build/m4-r1-ui-full-setup-trace.log`, `.build/m4-r1-ui-full-fourth.log`. The trace locates the timeout in the 5,000-line fixture rewrite's wait and permission-list requests under host load above 200 (subsequently above 700). App code, timeouts and budgets were unchanged; each run cleaned up and passed isolation. |
| `git diff --check` | Passed. `.build/m4-r1-diff-check-final.log`. |

## Exit criteria

### 5,000-line diff

The deterministic fixture changes one numeric token on each of 5,000 Swift lines. Package assertions require 10,000 unified rows, 5,000 split rows, and nonempty word/highlight spans on every changed line. Host preparation measured **254.47 ms** (best of three cold runs; slowest **399.93 ms**), below the unchanged 500 ms budget (`.build/performance/m4-diff-host.json`, `.build/m4-r1-swift-acceptance.log`). The UI recorder additionally reports the layout, wrapping, row count and highlighted/word-diff line counts.

The complete iPhone traversal passed in the orchestrator's pre-handoff run: **0.12 ms/s** hitch time, **33.33 ms** longest scrolling frame, **16.67 ms** p95, **174.37 ms** to first rows and **115.08 MiB** physical footprint, with a **239.74 s** bottom-and-back traversal. Evidence: `.build/ui-smoke/ui-1792547649457/attachments/599ACC04-0644-475D-BF7F-434027017F15.json` and that run's `Smoke.xcresult`. This supersedes the earlier 12-swipe measurement, which did not prove complete traversal. The unchanged test requires 10,000 unified rows and 10,000 highlighted/word-diff lines with wrapping on.

The complete iPad review suite passed all three tests with zero failures in 562.98 s (`.build/m4-r1-ipad-review-final.log`, `.build/ui-smoke/ui-1792608092558/Smoke.xcresult`). Both traversals reached the final row and returned to the top, with 5,000 split rows and 10,000 highlighted/word-diff lines:

| iPad split layout | Hitch time (ms/s) | Longest scrolling frame (ms) | p95 (ms) | First rows (ms) | Footprint (MiB) | Traversal (s) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Wrapping on | 3.10 | 60.51 | 16.67 | 164.10 | 109.77 | 114.49 |
| Wrapping off | 4.96 | 45.62 | 16.67 | 185.41 | 107.77 | 121.98 |

Raw evidence: `.build/ui-smoke/ui-1792608092558/ipad-review-scroll.json` and `ipad-review-scroll-nowrap.json` in that directory. The same run passed the regular-width iPad comment proof (`ipad-review-comment-server.json`) and all navigation/Find-button assertions.

Simulator and host measurements do not replace an iPhone 13 Instruments trace.

### A review comment reaches the prompt

The final iPad review suite passed the regular-width comment flow: long-press a changed line, drag to the next line, submit the inline editor, observe the composer chip, send, and verify both the stored server message and the transcript card. Evidence: `.build/ui-smoke/ui-1792608092558/ipad-review-comment-server.json`, that directory's `Smoke.xcresult`, and `.build/m4-r1-ipad-review-final.log`. The stored message contains the absolute sandbox `Sources/Example.swift` path, `startLine: 2`, `endLine: 3`, zero character offsets, the two-line preview, origin `review`, empty displayText, the exact reference note and the server-resolved ranged file part.

The earlier complete focused run passed on both devices and also created a comment from the iPhone Files viewer: `.build/ui-smoke/ui-1792461536284/{review-comment-server,file-comment-server,ipad-review-comment-server}.json`. It checks the exact note/path/range and sent transcript cards, plus origin `file` on iPhone. These are completed UI proofs; they are not a substitute for the combined full regression run that remains blocked during fixture setup.

An earlier regular-width run found the comment submit button below the keyboard-clipped collection viewport. Proper hosting-controller containment and revealing the editor's bottom after viewport changes fixed it; the subsequent touch submission passed.

## Design and source decisions

1. The shared native read-only code/diff renderer replaces ARCHITECTURE's Runestone role. Runestone 0.5.2's tree-sitter 0.20 constraint conflicts with the installed swift-tree-sitter 0.10.0 / tree-sitter 0.25 dependency. No dependency was added.
2. Review layout follows the panel's width: regular at 480 points, split at a 560-point diff column, compact otherwise; accessibility sizes force unified/wrapping. The existing shell width rule and 768-point panel placement remain.
3. iPhone retains the specification's Review panel sheet instead of the desktop Session/Changes/More switcher. Terminal and Context remain placeholders. Native touch targets are at least 44 points; the compact source header has a 40-point minimum and grows for accessibility.
4. Turn-file taps navigate to the review panel/sheet with a specific-turn source instead of expanding inline. “Changed files” defaults on, as SPEC/ARCHITECTURE require, rather than the desktop's off. Binary files receive visible rows, instead of contributing only to the count.
5. Reviewed is an addition required by ARCHITECTURE. Its key includes session/source/path/patch digest, and changing content invalidates the mark. Reviewed compact files collapse.
6. The compact rendering gate is 20,000 changed lines rather than the desktop's 500, so the acceptance fixture renders normally. “Diff too large to render” / “Render anyway” wording remains.
7. V2 comment-editor wording is used at every width. Regular editors appear inline, compact editors in sheets; touch Return inserts a newline, hardware Return submits, Shift-Return inserts and Escape cancels. Plain taps never begin comments.
8. Entirely deleted-side comments omit ranged file parts, use “deleted line(s)” notes plus at most 20 lines of fenced deleted text, and retain `side: deletions` and deleted text in metadata. Mixed selections send their actual new-side range. This avoids the desktop's incorrect current-file slicing for old coordinates.
9. Restored comments have live IDs and annotations rather than inert desktop chips. Shell, client and server commands retain comments for the next prompt; server commands do not send comment files without their notes.
10. File reading adds ranged loading, ETag revalidation and a bounded disk cache beneath the reference's 40-file/20-MiB memory cache. Large text is shown only through a complete UTF-8 line. Media downloads ask above 100 MiB. ARCHITECTURE requests ranges; the desktop has none.
11. Quick Look from a cached local copy replaces desktop web viewers for supported document/media formats. SVG and Mermaid are source text. Audio previews inside diffs and desktop italic preview tabs are out of scope.
12. “Open file” from a diff selects its first changed line rather than opening without a line. “Mention in composer” toolbar/context actions supplement desktop drag-and-drop. Copy path uses the absolute server path.
13. The four diff tints now use the reference green/red values and weak/strong opacities. Header lines are parsed as headers, never additions/deletions.
14. Refresh uses open, foreground, explicit refresh and session/VCS events. Working-tree filesystem watching is not assumed: filesystem.changed is limited to branch files, and the sandbox disables it.
15. No revert/discard controls were added to review; session Undo/Redo remain the M3b actions. Menu-bar commands and diagram rendering remain later work.

16. Wrap lines applies to both native layouts; the desktop always wraps its regular view and exposes the preference only for mobile. The shared 13-grammar tree-sitter highlighter retains the existing node-type heuristics rather than introducing the desktop’s separate tokenizer.
17. Comment notes name the file by its absolute server path ("…regarding lines 2 through 3 of /…/Sources/Example.swift: …"). The desktop uses the path as stored, usually repository-relative. Review paths are repository- or project-relative and file paths are location-relative, so the absolute path is the one name that stays unambiguous for a session in a subdirectory; the ranged `file://` part is absolute in both clients. The wire shape, note wording and metadata fields are otherwise the reference's.
18. The permission sheet's edit preview uses the shared diff view, so its file links open the Files viewer and its lines accept comments for the next prompt. This adds a FeatureApprovals → FeatureFiles dependency, which the module rules allow (features may depend on features; none imports OCNetworking).
19. Only the VCS endpoints turn a 503 with a `message` into a user-facing error. Every other route keeps M1's service-starting handling, including the server's `service_failed` body.
20. Inline-code paths render as code first and become links when the existence check answers. Answers are cached per session for a minute and shared between messages; the desktop also checks asynchronously without blocking the text.
21. The scroll budgets apply to frames while the list is dragged or decelerates. Frames between XCUITest gestures, which include the runner's accessibility queries on the app's main thread, are reported separately and not budgeted. On the simulator, `XCTOSSignpostMetric.scrollingAndDecelerationMetric` reports only a dragging-and-deceleration duration, with no hitch data, so the DEBUG display-link recorder carries the budgets.
22. Turn ends without a changes card keep M2b's row (separator, "Turn complete", outcome badge). A changes card replaces the label, as on the desktop, and keeps the outcome badge for a turn that did not succeed.
23. ⌘F in the Files viewer is a SwiftUI shortcut on its Find button. The code list's UIKit key commands handle only ← and → file navigation.
24. Server 2.1.2 adds `native` reasoning metadata where the d0732ea projection uses `state`. Both are retained for compatibility; this was required by the unchanged live projection-parity check.

## Known issue: the first ⌘F on iPad (carried to M6)

In the original iPad navigation sequence, the first synthesized ⌘F delivers Command down/up to the app, with no F key event or Find action. A second chord works. This is a recorded simulator symptom, not a confirmed diagnosis of physical-keyboard behavior. The application-boundary event trace is under `.build/m4-r1-find-app-events-diagnostics/`; the second-chord trace and assertion are `.build/m4-r1-ipad-find-second-chord.log` and `.build/m4-r1-find-second-chord-diagnostics/`. XCTest's synthesized-event archives contain an `f`/Command request for each chord.

The negative control removed the Find registration. Find remained closed after both chords, with no F event recorded (`.build/m4-r1-ipad-find-negative-control.log`; `.build/m4-r1-find-negative-attachments/F0C04033-316D-4357-96AF-CF6C63DE1DA5.json`). Consequently, a missing app-level F event is insufficient evidence to retry a chord: it could hide a registration defect. The guarded retry and its input receipt were discarded.

The following experiments were tried and reverted. Log names below are under `.build/`, with prefix `m4-r1-ipad-find-` and suffix `.log` unless a full path is given:

| Experiment | Evidence and outcome |
| --- | --- |
| Single chord, responder/command counters and focused view/controller routing | `single`, `diagnostics`, `view`, `focus-owner`, `focus-refresh`; did not resolve the original sequence. |
| UIKit key command, dedicated selector, command registration and SwiftUI bridge | `command`, `dedicated`, `registration`, `bridge`; did not resolve it. |
| Hidden root shortcut, retry of that run, SwiftUI focus and standard UIKit Find action | `root`, `root-retry`, `swiftui-focus`, `standard`, `standard-retry`, `standard-action`; did not resolve it. |
| App-level event tracing and read-only/raw key handling | `app-events`, `readonly-key`, `raw-only`; the first chord still supplied only the modifier at the observed app boundary. |
| Targeting the collection instead of the app; uppercase/typed-constant key forms; held modifiers; plain key and modifier delivery | `element`, `key-capital`, `key-constant`, `held-command`, `key-delivery`, `key-only`, `modifier-key`, `held-focus`; no reliable first-chord fix. |
| Diagnostic plain F, then ⌘J, then ⌘F | `keys`; Find opened, but the extra keystrokes were removed. |
| Second ⌘F | `second-chord`; Find opened after the original first-chord assertion had failed. The retry was removed. |
| Five-second registration delay | `registration-delay`; still failed. The delay was removed. |
| Explicit app activation | `activated`; stalled during onboarding animation-idle waits, before Find. The owned run was stopped and cleaned up; activation was removed. |
| Eager native command registration and SwiftUI focused source wrapper | `eager-command`, `swiftui-focus-bridge`; still failed. |
| Replacing earlier ←/→ navigation with toolbar taps, retaining one ⌘F and the standard-action experiment | `before-arrows` (`ui-1792607884384`); passed. This diagnostic sequence and the native action were reverted; the acceptance test retains hardware arrow navigation. |

All key-event tracing, probes, receipts, debug counters, native Find forwarding, experimental focus handling and test delays/retries were removed. The visible Find button retains its original SwiftUI `keyboardShortcut`. Per the orchestrator's explicit scope decision, M4's iPad navigation test opens Find by tapping that button and still asserts opening, match count, Previous/Next, file browsing and both link forms. One ⌘F check is retained at the very end of iPad navigation, after all M4 assertions, inside `XCTExpectFailure(..., options: .nonStrict())` with a message pointing to this entry. It does not gate M4 acceptance and uses the original five-second assertion timeout. The recorded complete iPad run preceded moving this optional check to the end; its M4 assertions and app code are unchanged. No timeout was increased.

M6 will implement ⌘F as a `.commands` menu item alongside the architecture's menu-and-shortcut work, test the first chord in UI tests, and verify it on a physical iPad with a hardware keyboard. M4 acceptance remains the complete 5,000-line traversal and a review comment reaching the server prompt.

## M4 review round 1

Codex's run stopped at its usage limit before final verification, with the implementation above in the working tree. For M4 only, the user then authorized the orchestrator (Claude) to make the review fixes directly, instead of resuming Codex once its limit reset. The orchestrator reviewed the tree, reran verification, and made these changes:

- **Inline-code file links.** `StreamingMarkdownView` had awaited one uncached `fs.find`/`fs.list` per path-like inline code span before showing any block, and it repeated this whenever virtualized timeline cells were reused.
  - Text now renders immediately, and confirmed paths become links when the answers arrive.
  - `OCModels/InlineCodeLinks.swift` ports the reference's `inlineCodeKind` classifier and its test cases. It skips fenced code and code that is already link text; the old regex turned ``[`Example.swift`](…)`` into a nested link.
  - `FilesModel` answers per session from a 60-second, 512-entry cache. It shares in-flight lookups, runs at most four at once, and offers a synchronous `knownLinks` answer, so reused cells link without flicker.
- **Highlighting.** `CodeHighlighter` walked the syntax tree with `Node.child(at:)`, which is linear in the index (quadratic over a large file's top-level children), and created a node-type `String` per node.
  - It now walks with a `TreeCursor` and classifies each grammar symbol once. Highlighting the 5,000-line diff fell from about 340 ms to 120 ms.
  - The preparation test applies the unchanged 500 ms budget to the best of three cold runs on distinct patches.
- **503 handling** is scoped to the VCS endpoints (`Endpoint.reports503Message`). Every other route keeps M1's `serviceStarting` mapping for the server's `service_starting`, `service_stopping` and `service_failed` bodies, and a test pins it.
- **Horizontal scrolling** with wrapping off now stops at the widest visible line (measured during off-main section preparation) and decelerates at UIScrollView's normal rate. Previously the text could be dragged off-screen without limit.
- **The file cache** stores entries per server. Removing a server deletes its cached contents. UI tests keep the cache inside their namespace, which their reset already removes.
- **Turn ends.** M4 had replaced M2b's turn-end row with plain text and dropped the outcome badge (for example "Failed"). That changed row heights and broke M2's `renderedFiveThousandRowsAndPrependAnchor` in every run. Turn ends without a changes card keep M2b's row again; a changes card keeps the badge when the turn did not succeed.
- **Prompt rows** decode their comments once per render, and the note and mention patterns are compiled once.
- **Scroll measurement.**
  - The DEBUG recorder applies the longest-frame budget to frames while the list moves, and reports idle frames separately (`longestIdleFrameMilliseconds`); idle frames between gestures include XCUITest's own accessibility queries on the app's main thread.
  - The traversal flicks at 20,000 points per second from coordinates computed once, reads the position every third flick, and attaches each traversal's duration. The earlier traversal made the full UI run take 91 minutes.
- **UI-test robustness.** Home realizes rows lazily, and the review fixture adds sessions, so earlier rows sink below the fold (one run also crossed midnight).
  - Every test that opens a session from Home uses `homeSessionRow`, which scrolls the identified Home list.
  - The read flow scrolls back to the top before using the project picker. Assertions are unchanged.
- **`ReviewSnapshots`** creates its window from the connected scene, which removes a deprecation warning.
- **⌘F in the Files viewer** moved to a SwiftUI keyboard shortcut on the visible Find button. The code list's UIKit ⌘F command and press handling never fired on iPad, and could hide the key from SwiftUI. The code list keeps ← and → for file navigation.
- **The iPad review setup** closes Settings and waits for it to dismiss before rotating, as the other suites do. Rotating first had left Settings covering Home.

### Follow-up verification fixes

- Live verification against server 2.1.2 exposed a protocol extension beyond the d0732ea reference: `session.reasoning.started` and `.ended` carry opaque `native` metadata. Two full contract runs reproduced a projection mismatch for that field (`.build/m4-r1-contract.log`, `.build/m4-r1-contract-retry.log`). The captured stream and snapshot in `.build/opencode-sandbox/audits/contract-1792604352808/reasoning-wire.json` confirm the payload. The existing reducer now retains `native` alongside legacy `state`, with a start/delta/end/null/snapshot regression test. The original live parity assertion remains unchanged; the contract also saves a redacted reasoning capture for future failures.
- Scheduled CI run `39563448265` exposed a receipt-read race in `verifyEnforcement`: the bootstrap had created its receipt but had not finished writing JSON. Missing or syntactically incomplete/invalid JSON now returns “not yet verified” to the existing bounded retry loop. A complete receipt still must match the child PID, token, profile digest and protected roots and attest that the canary write was denied. The new regression test replays partial writes using a real enforced bootstrap proof and rejects complete mismatches for every checked field. The Node suite passes all 32 tests (`.build/m4-r1-node-acceptance.log`).
- The first resumed iPad run confirmed Settings dismissal but exposed a second rotation race: the portrait Home sheet could finish dismissing after the test checked its presence. `homeSessionRow` now reopens Home through its visible toolbar control when the list is absent. The original row and review assertions remain intact.
- Snapshot review found that the existing Approval/Read capture helpers waited before mounting their asynchronous diff views, recording empty previews. Diff-containing captures now use the existing rendering host, mount before waiting, and capture prepared rows. Other captures retain their existing setup. ReviewSnapshots now applies the app theme, and a visible image test pattern replaces the one-pixel white fixture so image rendering can actually be inspected. The first fresh recording passed all five snapshot methods (`.build/m4-r1-review-record-second.log`, `.build/m4-r1-review-record-second.xcresult`). All 488 images were inspected using the 48 contact sheets and manifest under `.build/m4-snapshot-review/final/`. That inspection prompted centering the loading indicator, anchoring the large-diff toolbar at the top, and stacking compact review/turn-card header information at accessibility sizes. Sent-comment fixtures now use a scrolling transcript container, avoiding a clipped first comment at accessibility5. The initial comparison generation produced 488 pairs (`.build/m4-r1-compare-review-initial.log`). The targeted older-baseline recording changed exactly 82 images: 24 permission previews, 48 edit/patch tool previews, four standalone diff cards, and six Settings screens with the new preferences. Before/after images were reviewed under `.build/m4-r1-final-baseline-review/` and `.build/m4-r1-old-baseline-review/`; the inventory is `.build/m4-r1-baseline-changes.json`. Every `rowKinds` image, including all four turn-end images, remains byte-identical to the committed M2b baseline. No unrelated baseline was changed. The final recording again passed all five ReviewSnapshots methods (488 images, 221.82 s; `.build/m4-r1-record-final.log`). Its 78 changes from the first inspection were checked on the ten sheets under `.build/m4-r1-review-final-changes/`. The older helpers report record-mode issues by design; the non-recording verification determines their pass/fail result. The official comparison exposed a remaining empty-state mismatch: review now extends `OCEmptyState` with a centered panel presentation using the reference’s 13-point text, 20-point icon, 24-point top/160-point bottom spacing and Git icon. Existing page empty states retain their layout. Recording the 160 Changes states changed 56 intended images, all inspected on the ten before/after sheets under `.build/m4-r1-centered-empty-review/`. One incidental loading-placeholder recording was rejected and its prior image baseline restored. The first non-recording check caught two asynchronous captures before readiness; the unchanged rerun passed all 160 images (`.build/m4-r1-centered-empty-retry.log`). No timeout was increased. The final older-baseline inventory remains 82 images, with every `rowKinds` image unchanged.

### Landing fixes

Codex reached its usage limit again during final verification, so under the same M4-only authorization the orchestrator made the last fixes and ran the landing verification.

- **Diff snapshots waited a fixed 350 ms.** `DiffView` publishes plain rows and then highlighted rows, so under host load a capture could record an empty or unhighlighted diff. One committed baseline, `tool-apply_patch-streaming-light-393`, had been recorded empty; its replacement is byte-identical to the matching `tool-patch-streaming` image. A DEBUG-only `DiffPreparation` counter now tracks in-flight preparations, and the Read and Review snapshot helpers wait for it to settle (at most 2 s for a start, then 15 s).
- **The review image snapshot** could capture "Loading…". `changesStates` now waits for the image or its error before capturing.
- **`Tools/ui-smoke` truncated the results JSON.** The process helper keeps only the last 24,000 characters of output, and M4's tests grew the `xcresulttool` test tree beyond that, so a fully passing run failed while parsing it. The harness now reads it with `execFile` and a 64 MiB buffer.
- **iPad Home and rotation race.** The first full run to reach the iPad stage failed `testReadScreens`, `testLargeDiffScroll` and `testReviewNavigation`, while `testReviewAndFiles` passed in the same run. In the failures Home was still open, which squeezed the 1,180-point landscape window's review panel to 442 points: no file tree, no split, and a unified diff. The screenshots were drawn sideways, taken mid-rotation. The suites rotated and then toggled Home on a one-time `exists`/`isHittable` check, so under load a tap could land before rotation finished or be decided on a stale state.
  - `toggleHome` and `toggleReview` now report `open` or `closed` as their accessibility value, matching what is visible (the sidebar or the narrow-width Home sheet; the review panel or its sheet). VoiceOver users get the same state.
  - `SmokeTestCase.rotate(to:)` waits up to 15 s for the app window's aspect to match the orientation. `setHome(open:)` taps only when the value differs and waits up to 10 s for the target. If the value still hasn't changed, it re-taps once, logs it, and asserts. Every rotation and Home toggle in the Read, Composer and Review suites uses them, and `homeSessionRow` no longer reopens Home itself.
  - No other timeout or retry changed.
- **Host load.** Other projects' test suites kept load averages between 25 and 500 throughout. Under that load, one full run failed the large-diff scroll on a single 12-second frame and the composer flow on a non-JSON API response; a later run failed on a 136 ms frame. These budgets were not changed.

#### Landing runs

After these fixes, `swift test`, the Node tests (32 of 32), the app build (no warnings), build-for-testing and `git diff --check` passed. Each full `node Tools/ui-smoke/index.mjs` run below waited for the one-minute load average to fall below 60 (at most 20 minutes) before starting. Loads are the 1/5/15-minute averages.

| Attempt | Run directory | Load at start | Load at end | Result |
| --- | --- | --- | --- | --- |
| 1 | `ui-1792632135684` | 193.75 / 211.78 / 249.44 (waited 20 min) | 104.17 / 76.12 / 71.24 | Failed: iPhone `testReadScreens`, the live session's transcript still empty after 15 s |
| 2, run 1 | `ui-1792636238573` | 56.15 / 99.02 / 88.33 | 7.34 / 9.06 / 10.86 | Passed |
| 2, run 2 | `ui-1792640804636` | 7.34 / 9.06 / 10.86 | 4.18 / 7.37 / 12.79 | Failed: iPad `testComposerQueueAndSessionActions` |
| 3, run 1 | `ui-1792647969990` | 3.51 / 6.44 / 11.98 | 3.55 / 4.44 / 5.03 | Passed |
| 3, run 2 | `ui-1792652435553` | 3.55 / 4.44 / 5.03 | 3.37 / 4.26 / 4.82 | Passed |

Attempt 3 is the two consecutive passing runs, both including the iPad stage.

- **Attempt 1** ran under heavy load from other projects. That test passed in every other iPhone stage.
- **Attempt 2, run 2** ran at low load. From 29 s into the test, while typing the server URL on the add-server form and before any session or M4 screen was open, XCUITest reported "App animations complete notification not received" for 37 consecutive actions, waiting 60 s each. The scripted response timed out on the server, so the queued message was delivered before the test could choose Steer. The iPad software keyboard was on screen. The only endless animation in the app is the running indicator in `TimelineChrome` (pre-M4). Every other iPad run, attempts 2 and 3 included, recorded zero such waits in every test. This is recorded as an unexplained simulator idle stall; no timeout was changed.
- Each passing run recorded one unattributed personal opencode log write per hour at hh:14:21; enforcement was verified and nothing was suppressed.

## Isolation

Only Tools/opencode-sandbox launches opencode. The source reference is read-only and was never built, installed or run. The no-Git fixture initially resolved to the enclosing checkout because native project discovery ignores Git's ceiling. An empty marker stopped that lookup but made vcs.init reject the fixture. The replacement adds optional read and file-existence denials for the enclosing checkout's `.git`/`.hg` to the disposable sandbox profile, while keeping Git's ceiling at the sandbox root. The fixture asserts its resolved project directory before exercising writes. Existing projects and Git metadata are not modified. The read denial alone did not hide `fs.exists` on macOS; the dedicated `file-test-existence` denial is covered by a native sandbox test. The fourth contract run successfully initialized Git, then exposed the documented transient empty provider, now awaited by the contract. Its isolation audit (`contract-1792461207698/comparison.json`) verified enforcement with zero failures or observations. The passing focused UI run (`ui-1792461536284/comparison.json`) verified enforcement and zero failures, with five unattributed observations: the personal cache directory and models.json changed at 01:59:40Z, and the personal log changed at 01:59:49Z, 02:00:40Z and 02:00:41Z. These were not suppressed. The resumed verification aggregate is `.build/m4-r1-isolation-summary.json`: 51 completed audits, all with verified enforcement and zero failures, including the official design capture. Fourteen unattributed observations were retained: nine LaunchAgents/factory-marker observations at 15:25:48Z, 15:25:54Z and 15:26:12Z; two LaunchAgents/fleet-nightly observations at 18:43:53Z; and personal log writes at 17:14:21.165Z, 18:14:21.200Z and 19:14:21.267Z. These observed timestamps differ from the brief’s known :52:57 writer; no attribution was inferred and no warning was suppressed. The final passing contract and official design capture had no observations.

Xcode 27.1 is installed; 27.0 cannot be executed here. Swift 6 and iOS/iPadOS 26.4 are retained, with no intentionally 27.1-only syntax or API.

## Proposed documentation updates

### docs/design.md

Replace the M4 Changes/Files placeholders with: “The workspace review panel receives the selected server/session and shared composer. Review uses a 480-point panel breakpoint; its changed-file sidebar is 240 points by default (200–480, resizable/resettable/collapsible). Split requires 560 points of diff column. Compact review is one virtualized accordion. Files uses a lazy tree and source/media viewer, separate screens at compact widths. Both use the shared native code renderer and comment selection. Review stays beside the timeline when the existing shell rule permits and uses a sheet otherwise. Terminal and Context remain later milestones. Wrap lines and Changed files default on. Reviewed marks are native additions; tool and turn diffs open the shared viewer.”

### ARCHITECTURE.md

Document the UICollectionView read-only CodeViewer in place of Runestone, byte-bounded shared highlighting, v4 review state/draft comments, ranged ETag file caching and side-aware deleted-line comment encoding. Keep module dependency boundaries and the M4 acceptance budgets unchanged.

### research/01-opencode-server-api.md

- VCS diff/status paths are repository-root-relative and restricted to the requested location; session diff/revert/step snapshot paths are project-root-relative; fs paths and ordinary tool paths are location-relative. Strip the session subpath and use the project location for outside-location reads; never send parent segments.
- session.diff takes optional from/to/context with no location. Omitted bounds resolve to the latest whole turn; omitted context requests full patches. Running steps compare the working copy; missing/off snapshots return an empty array. Record typed 400/404 and UnknownError/ref failures.
- jsdiff and Git patches differ in headers. Snapshot binary patches are empty; VCS binary patches contain a Binary files chunk. Header-only budget truncation requires a context=3 retry; rename is delete+add.
- VCS routes use location wrappers. Branch diff with omitted base uses the default branch, not vcs.base. Preserve 503 messages; provider/arrays/base may be empty until plugin activation, and vcs.branch.updated requires refresh. vcs.init rebuilds location and emits worktree.updated.
- fs.read is raw bytes with guessed Content-Type, weak ETag, Last-Modified, no-cache/no-transform, Accept-Ranges, 304/206/416, no server size cap, and a wildcard path encoded segment by segment. Do not apply JSON response validation to this one route.
- fs.list returns direct children, directories first with trailing slash, includes dot/ignored files and drops symlinks. fs.find is fuzzy/ranked, excludes hidden/ignored files, caches its index for up to ten seconds and takes type/limit.
- filesystem.changed does not report ordinary working-tree edits. Use step end, idle, VCS/revert/worktree events, foreground/open and pull-to-refresh.

## Changed files

Paths below are relative to `Packages/OpencodeKit/Sources/` unless another root is shown.

- **Models and transport:** `OCModels/{Review,FileContent,InlineCodeLinks,LineComment,ComposerInput,DraftAttributes,SessionInfo,WireValue,EventPayloads}.swift`; `OCNetworking/{ReviewEndpoints,ComposerEndpoints,Endpoint,ReadEndpoints}.swift`.
- **Persistence and store-owned state:** `OCPersistence/{FileCache,ReviewPersistence,DraftFiles,LocalStores,Schema}.swift`; `OCSync/{FilesModel,ReviewModel,ComposerModel,ComposerReadActions,ReadStore,ServerRegistry,SessionWriteActions,StreamingHandlers}.swift`.
- **Rendering:** `OCRender/{CodeSearch,DiffDocument,DiffRows,FileLanguage,WordDiff,CodeHighlighter,StreamingMarkdown,TimelineRow,TimelineRowBuilder}.swift`; `OCDesign/{CodeCell,CodeCollection,CodeEditorCell,CommentTextView,DiffFrameRecorder,DiffView,FileLinks,LineCommentEditor,Colors,Controls,DiffCardView,Feedback,FileIcon,Metrics,MarkdownBlockView,WorkspacePanel,WorkspaceShell}.swift` and the eight diff color assets.
- **Feature integration:** `FeatureReview/{ReviewScreen,WorkspaceReviewPanel}.swift`, `FeatureFiles/FilesScreen.swift`, `FeatureTranscript/{TurnChangesCard,SessionScreen,TimelineRowView,ToolRowView}.swift`, `FeatureComposer/{ComposerDock,PromptEditor,SessionActions}.swift`, `FeatureApprovals/PermissionSheet.swift`, `FeatureInbox/HomeView.swift`, `FeatureServers/{ServerRootView,ServerSettingsView}.swift`.
- **Package and snapshot tests:** `Tests/OCModelsTests/{InlineCodeLinksTests,ReviewTests}.swift`, `Tests/OCNetworkingTests/ReviewEndpointsTests.swift`, `Tests/OCRenderTests/{DiffTests,MarkdownTests}.swift`, `Tests/OCSyncTests/{FilesModelTests,ReviewStoreTests,ReadStoreTests}.swift`, `Tests/OCNetworkingLiveTests/WriteLiveTests.swift`, `Tests/ReviewSnapshots/ReviewSnapshots.swift`, `Tests/ApprovalSnapshots/ApprovalSnapshots.swift`, `Tests/ReadSnapshots/{ReadSnapshots,HomeRowSnapshots}.swift`, plus the reviewed baselines described above.
- **App test/build wiring:** root `UITests/{ReviewSmokeTests,SmokeTestCase,ReadSmokeTests,ComposerSmokeTests}.swift`, `project.yml`, and `Packages/OpencodeKit/Package.swift`.
- **Fixtures and tools:** root `Fixtures/source/m4/` (five small patches and the image fixture), `Tools/review-fixture/index.mjs`, `Tools/contract/{index.mjs,review-fixture.test.mjs}`, `Tools/design-reference/{index.mjs,review.mjs,compare-review.py}`, `Tools/ui-smoke/index.mjs`, and `Tools/opencode-sandbox/{index.mjs,profile.mjs,process.mjs,isolation.test.mjs}`.
- **Audit:** root `docs/m4-audit.md`. No protected document was edited by this implementation. A concurrent change to `docs/design.md` was preserved, as noted above.
