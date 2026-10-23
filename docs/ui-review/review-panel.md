# UI review: Review panel

Part of the [UI review](README.md). 18 bugs and 3 improvements, bugs first, then by severity. Paths under `Packages/OpencodeKit/Sources` are written without that prefix.

| ID | Severity | Finding |
| --- | --- | --- |
| [F15-01](#f15-01) | P2 bug | Reviewed marks are wiped when review is first opened from a turn card, file link or comment chip |
| [F15-02](#f15-02) | P2 bug | Expanding or jumping to a file scrolls past the end of the iPhone accordion, hiding the files above |
| [F15-03](#f15-03) | P2 bug | iPhone Next/Previous step through a different file order than the accordion shows |
| [F15-04](#f15-04) | P2 bug | One file over 20,000 changed lines replaces the whole iPhone file list |
| [F15-06](#f15-06) | P2 bug | VoiceOver can't tell which source is shown, a file's status and counts, or whether it is reviewed |
| [F15-08](#f15-08) | P2 bug | Switching source shows no progress, and a failed switch still changes the saved source |
| [F30-08](#f30-08) | P2 bug | Review sheet: tab bar touches the screen edge, rows use five different leading insets, and the panel clips above the home indicator |
| [F15-07](#f15-07) | P2 bug | Every render re-sorts the file list many times and re-hashes every patch |
| [F28-10](#f28-10) | P2 bug | Loads ignore the known connection state and can spin for about 90 s on an unreachable server |
| [F15-11](#f15-11) | P3 bug | Terminal and Context placeholders are dead ends the panel remembers and restores late |
| [F15-12](#f15-12) | P3 bug | File filter: misaligned rows, no field affordance or clear button, and navigation ignores it |
| [F15-13](#f15-13) | P3 bug | Accordion header polish: counts formatted two ways, jumping chevron, stale Collapse all, Open file on deleted files |
| [F22-12](#f22-12) | P3 bug | Compact review header at accessibility sizes has three different leading edges |
| [F29-09](#f29-09) | P3 bug | Several errors drop the server's reason or give no next step |
| [F29-11](#f29-11) | P3 bug | Change summaries format numbers and statuses differently across Review, the turn card and Files |
| [F31-10](#f31-10) | P3 bug | Review panel details look unfinished: line numbers sit above the code baseline, '−5,000 1/1' runs together, a 6-pt grey divider, and an unstyled 'Filter files' |
| [G08-M2](#g08-m2) | P3 bug | Turn changes vanishes from the source menu as soon as another source is chosen |
| [F15-14](#f15-14) | P3 bug | Error and empty states hide the reason and offer no next step |
| [F15-05](#f15-05) | P2 improvement | Reviewed state is invisible in the iPhone accordion and buried in a per-file menu |
| [F15-10](#f15-10) | P3 improvement | Source labels don't identify the turn or base, and menus don't show the current choice |
| [F27-09](#f27-09) | P3 improvement | Per-session review, files and turn-diff models are never evicted and keep patches, images and file contents after their screens close |

<a id="f15-01"></a>

## F15-01: Reviewed marks are wiped when review is first opened from a turn card, file link or comment chip

*P2 bug · state · effort S · found by review-changes*

- Where: `OCSync/ReviewModel.swift:58`, `OCSync/ReviewModel.swift:69-78`, `OCSync/ReviewModel.swift:115-121`, `OCSync/ReviewModel.swift:185-192`, `FeatureTranscript/TimelineRowView.swift:90` (+3 more)
- Evidence: `ReviewModel.swift:77 choose(): 'persist(); refresh()'. It saves before the model has hydrated.`; `ReviewModel.swift:115-118: 'if !self.restored { if let saved = try await store.cache?.writer.reviewState(...) { if self.presentRequest == nil { self.state = saved.0 }; self.reviewed = saved.1 } }'. Hydration happens only inside refresh().`; `ReviewModel.swift:187 persist(): 'let previous = saving, state = state, reviewed = reviewed'. There is no 'restored' guard, so it captures the empty initial set.` (+2 more)
- What happens: iPhone, session S: mark 3 of 5 files Reviewed under Last turn changes. Relaunch the app, open S, and tap a file in the turn's Changed files card (or a file link in a message, or a comment chip). store.review() creates a fresh ReviewModel, choose()/selectTab() persists its empty `reviewed` set, and the following refresh reads that row back. Switching to Last turn changes now shows 0 of 5 reviewed, and the marks stay gone. Through the file-link path the saved source and open files are also reset to the defaults (Git changes).
- Why it matters: Review progress is lost without any message, on the most common way into review on iPhone. Reviewed marks exist to track progress across visits, and once users see them vanish they stop trusting the feature.
- Fix: Don't persist before hydration. Either load the saved row when ReadStore.review() creates the model, or have choose/selectTab await hydration first. When hydrating, keep in-memory navigation (source, file, tab) over the saved state, union `reviewed` with the saved set, and then save. Add a ReviewStoreTests case: save marks, create a new store, call choose(.turn, file:, present: true), then assert the marks survive.
- Verifier's note: Make persist() a no-op until restored, or merge on hydration: union the saved `reviewed` set with the in-memory one, keep the in-memory navigation, then save. Consider hydrating eagerly when ReadStore.review() creates the model, because panelRequest creates models that are never hydrated.

<a id="f15-02"></a>

## F15-02: Expanding or jumping to a file scrolls past the end of the iPhone accordion, hiding the files above

*P2 bug · layout · effort S · found by review-changes*

- Where: `OCDesign/CodeCollection.swift:91-92`, `OCDesign/CodeCollection.swift:94`, `OCDesign/CodeCollection.swift:104-108`, `OCSync/ReviewModel.swift:73`, `FeatureReview/ReviewScreen.swift:192`
- Evidence: `iphone/review-changes.png: 'Files Changed 7' and '0 of 7 reviewed', but only Sources/Example.swift (expanded) and src/created.ts are visible, and the lower ~60% of the sheet is blank.`; `ipad/ipad-review-changes.png lists the other five files (added.txt, data.json, deleted-by-turn.txt, Large.swift, removed.txt).`; `.build/design-compare/m4-changes-working-light-393-default.png: in server order Sources/Example.swift is 6th of 7. Content is about 6×44 + 88 + 5×24 = 472 pt, less than the ~586 pt viewport, yet the offset is set to origin(5) = 220 pt.` (+1 more)
- What happens: iPhone, Git changes with 7 collapsed files. Tap the 6th header (Sources/Example.swift). The list jumps so that file sits at the top: the five files above disappear, the space below is blank, and there is no scroll indicator until the user drags and the list bounces back. The same happens when tapping a later file in a turn's Changed files card (choose() resets scrollOffsets["accordion"] to 0 and the selected file is scrolled to the top), when Next file targets a later file, and when a saved accordion offset is larger than the current (collapsed) content.
- Why it matters: Files seem to go missing from the list that says 'Files Changed 7'. Users can miss changes or think the review is broken.
- Fix: Clamp every programmatic offset to max(-adjustedContentInset.top, min(y, contentSize.height − bounds.height + adjustedContentInset.bottom)). Better still, use scrollRectToVisible and scroll only when the expanded content would otherwise be off screen.
- Verifier's note: Clamp the offsets at :92, :94 and :108. Better, scroll only when the target header is off-screen.

<a id="f15-03"></a>

## F15-03: iPhone Next/Previous step through a different file order than the accordion shows

*P2 bug · navigation · effort S · found by review-changes*

- Where: `FeatureReview/ReviewScreen.swift:182-192`, `OCSync/ReviewModel.swift:48-53`, `OCSync/ReviewModel.swift:63-68`, `OCSync/ReviewModel.swift:144`, `OCModels/Review.swift:73-86`
- Evidence: `iphone/review-turn-navigation.png: the accordion order is Sources/Example.swift, deleted-by-turn.txt, src/created.ts. After Next then Previous, src/created.ts is expanded while the middle file is still collapsed, so Next skipped it.`; `iphone/review-reviewed.png shows the server order; ipad/ipad-review-turn-navigation.png shows the tree order (Sources/Example.swift, src/created.ts, deleted-by-turn.txt).`; `ReviewScreen.swift:192 'diff(model.files, headers: true)' uses server order, while ReviewModel.swift:65 move() indexes 'orderedFiles' (directories first). UITests/ReviewSmokeTests.swift:132-133 asserts that → from Example.swift selects src/created.ts.`
- What happens: iPhone: open a turn from its Changed files card (Turn changes) and tap Next file. The visually next file (deleted-by-turn.txt) is skipped, the third file expands and the list jumps to it. Pressing Next again jumps back up to the skipped file. There is no position indicator and the wrap-around is silent. The default selection is also the first file in tree order, so Expand all and turn navigation can jump to the middle of the list (see the scroll finding).
- Why it matters: File-by-file review on the phone feels random, and users can miss files they meant to step through.
- Fix: Drive the compact accordion and its Review options menu from model.orderedFiles (the same order the iPad tree and move() use), or make move() follow the displayed order. Show a '2 of 3' position, and offer Previous/Next for every source on iPhone, not only .turn.

<a id="f15-04"></a>

## F15-04: One file over 20,000 changed lines replaces the whole iPhone file list

*P2 bug · functional · effort M · found by review-changes*

- Where: `FeatureReview/ReviewScreen.swift:195-197`, `FeatureReview/ReviewScreen.swift:192`, `FeatureReview/ReviewScreen.swift:20`
- Evidence: `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.changes-too-large-light-393-default.png: only 'Diff too large to render' and 'Render anyway'. No file rows or names.`; `.build/design-compare/m4-changes-too-large-light-393-default.png: the reference keeps every file row and gates per file.`; `ReviewScreen.swift:196 'if !renderLarge && files.contains(where: { $0.changedLines > 20_000 })' checks all files, collapsed ones included. 'renderLarge' is per-view @State.`
- What happens: iPhone (or iPad at accessibility sizes or in a narrow panel). Branch changes include a regenerated package-lock.json (25,000 changed lines) and 12 source files, all collapsed. The whole accordion is replaced by 'Diff too large to render' with no file names. The only way to see the other 12 files is Render anyway, which renders everything, including the lockfile once expanded. After switching tabs the gate comes back.
- Why it matters: Lockfiles and generated files routinely exceed the limit, so a common branch review is blocked on iPhone.
- Fix: Gate per file. Keep the accordion and give an over-limit file a section whose body is a 'Diff too large to render · Render anyway · Open file' row (CodeCell already supports label rows with an Open action). Check only expanded files, and keep the per-path override in ReviewModel.
- Verifier's note: Check only expanded files, and render the gate as that file's section body so the other headers stay visible.
- Also reported as: F36-04 by sweep-review-snapshots

<a id="f15-06"></a>

## F15-06: VoiceOver can't tell which source is shown, a file's status and counts, or whether it is reviewed

*P2 bug · accessibility · effort S · found by review-changes*

- Where: `FeatureReview/ReviewScreen.swift:84`, `FeatureReview/ReviewScreen.swift:89`, `FeatureReview/ReviewScreen.swift:100-116`, `OCDesign/CodeCell.swift:184-186`, `OCDesign/Icon.swift:17`
- Evidence: `ReviewScreen.swift:84 '.accessibilityLabel("Review source")' replaces the visible 'Git changes' label and adds no accessibilityValue.`; `CodeCell.swift:186 'self.toggle.accessibilityLabel = title; self.open.accessibilityLabel = "Open file " + title'. The 'Modified +1 −1' summary is never exposed.`; `ReviewScreen.swift:110 'OCIcon("check")' is accessibilityHidden (Icon.swift:17), and :115 '.accessibilityValue(... ? "Selected" : "")'. Status is shown as bare 'A'/'D' letters (:111), and the totals are two separate Texts (:89).`
- What happens: VoiceOver on iPhone: the source control reads 'Review source, button' whether Git, Branch or Last turn changes are shown. Each accordion header reads 'Sources/Example.swift, Expanded' with no added/removed/modified status or line counts. The totals read 'plus 5,004', 'minus 5,004' as separate items. On iPad a reviewed, added file reads 'created.ts, A, Selected', with no reviewed state and 'A' read as a letter.
- Why it matters: Blind users can't tell which changes they are reviewing or track their review progress. This falls under the M9a VoiceOver pass but needs these specific fixes.
- Fix: Add .accessibilityValue(model.source.title) to the source menu. Label headers like 'Sources/Example.swift, modified, 1 line added, 1 removed', with values such as 'Expanded' or 'Collapsed, reviewed'. Give tree rows .isSelected plus a value such as 'Reviewed, Added'. Combine the totals into a single element: '5,004 lines added, 5,004 removed'.

<a id="f15-08"></a>

## F15-08: Switching source shows no progress, and a failed switch still changes the saved source

*P2 bug · state · effort M · found by review-changes*

- Where: `OCSync/ReviewModel.swift:69-78`, `OCSync/ReviewModel.swift:104-112`, `OCSync/ReviewModel.swift:139-147`, `FeatureReview/ReviewScreen.swift:31-32`, `FeatureReview/ReviewScreen.swift:84`
- Evidence: `ReviewModel.swift:75-77 sets state.source, persists, then calls refresh(). :140 'self.source = selected; self.files = values' runs only on success, and the :147 error path leaves the old source and files in place.`; `ReviewScreen.swift:32 shows the spinner only when '!model.loaded'. :84 labels the menu with model.source.title, the applied source rather than the requested one.`
- What happens: iPhone over a tunnel with Git changes loaded: choose Branch changes on a large repository. For the whole request the sheet still says 'Git changes' and shows the old files with no spinner, so the tap looks ignored. If the branch diff fails (for example 503 'Choose a review base'), a red line appears above the old files and the label still says Git changes. state.source = .branch is already saved, though, so the next foreground or session-event refresh silently switches the list to Branch changes, and the next launch opens on it.
- Why it matters: It is unclear which changes are on screen and whether the switch worked, and the list can change on its own later.
- Fix: Keep a pendingSource. Show its title with a small spinner (or dim the list) while it loads. On failure, revert state.source to the applied source and show an inline retry. Check-mark the current source in the menu.
- Verifier's note: Pull-to-refresh gives no feedback either: CodeCollection.swift:242 calls `parent.refresh(); control.endRefreshing()`, so the spinner stops at once. Keep it, or the pending-source indicator, running until model.loading clears.

<a id="f30-08"></a>

## F30-08: Review sheet: tab bar touches the screen edge, rows use five different leading insets, and the panel clips above the home indicator

*P2 bug · layout · effort S · found by visual-polish-iphone*

- Where: `OCDesign/WorkspacePanel.swift:24-29`, `OCDesign/WorkspacePanel.swift:51`, `FeatureReview/ReviewScreen.swift:177`, `FeatureReview/ReviewScreen.swift:191`, `OCDesign/CodeCell.swift:189` (+2 more)
- Evidence: `iphone/review-changes.png: the segmented track starts at x=0 (pixel column 0 is track colour) and ends at ~315pt. Leading edges: tab text 13pt, '0 of 7 reviewed' 8.7pt, 'Modified' 13pt, file header chevron 16.7pt, 'src/created.ts' chevron 19pt, 'Git changes' icon 23pt. 'Review options' ends 9pt from the right edge.`; `crops/visual-polish-iphone/rlu-bottom.png (crop of review-large-unified.png): the diff is cut off by rounded corners at ~840pt, with a 34pt white band below`; `WorkspacePanel.swift:25-27 'ScrollView(.horizontal) { OCSegmentedControl(…) }' has no horizontal padding, while the placeholder variant at :29 pads by OCSpacing.sm; :51 '.clipShape(RoundedRectangle(cornerRadius: OCRadius.xl))'` (+1 more)
- What happens: iPhone 17 Pro, open the Review sheet from a session. The tabs touch the left screen edge, and each following row starts at a different x. The sheet has no title, only a bare × at the top right; other sheets put a glass × or Cancel at the top left. In a long diff, lines disappear into a rounded corner 34pt above the bottom instead of scrolling under the home indicator.
- Why it matters: The main code-review screen on iPhone looks unfinished and wastes vertical space.
- Fix: Pad the tab strip (contentMargins or 16pt horizontal padding). Use one 16pt leading inset for the source row, the reviewed row and CodeHeader (x: 16). Apply the panel's rounded clip only in the regular-width side panel, and let the diff extend under the bottom safe area in the sheet. Give the sheet the title 'Review' and put the close button in the toolbar, as the other sheets do.
- Verifier's note: Overlaps F31-04 (track padding and contrast) and F30-14 (close control). Fix the shared OCWorkspacePanel once for both sheets.

<a id="f15-07"></a>

## F15-07: Every render re-sorts the file list many times and re-hashes every patch

*P2 bug · performance · effort M · found by review-changes*

- Where: `OCSync/ReviewModel.swift:48-56`, `OCSync/ReviewModel.swift:85-93`, `OCSync/ReviewModel.swift:152`, `FeatureReview/ReviewScreen.swift:94`, `FeatureReview/ReviewScreen.swift:113-115` (+2 more)
- Evidence: `ReviewModel.swift:53 'public var selected: FileDiff? { orderedFiles.first { $0.file == state.selectedFile } ?? orderedFiles.first }'. orderedFiles (:48-51) rebuilds a Dictionary and sorts with a comparator that splits both paths and calls localizedCompare. Nothing is cached.`; `ReviewScreen.swift:140 'model.orderedFiles.firstIndex { $0.file == model.selected?.file }' does a full sort for every element scanned.`; `ReviewScreen.swift:113 and :115 each call model.selected for every visible tree row. reviewedCount (:56) hashes every patch with SHA-256 and formats 32 bytes with String(format:) on every render (ReviewScreen.swift:94/179).`
- What happens: iPad, Branch changes with 400 files, tree hidden, file 300 selected. Rendering the '300/400' counter does about 300 sorts of 400 paths (~3,500 comparisons each) on the main thread, on every render: each Next tap, filter keystroke, selection, and every refresh during an agent run (loading toggles twice per refresh). With the tree visible it is about 2 sorts per visible row per render. These are estimates, not measurements.
- Why it matters: Big branch reviews, a main use case, become laggy or hang the main thread in proportion to the number of changed files.
- Fix: When files change (in refresh), compute orderedFiles, a path→index map and each patch digest once and store them. Make `selected` a lookup, and compute the counter index once per render.
- Also reported as: G15-M3 by verifier G15

<a id="f28-10"></a>

## F28-10: Loads ignore the known connection state and can spin for about 90 s on an unreachable server

*P2 bug · state · effort M · found by states-coverage*

- Where: `OCNetworking/Endpoint.swift:73-103`, `OCNetworking/Endpoint.swift:133-142`, `FeatureReview/ReviewScreen.swift:32`, `OCSync/ReviewModel.swift:122-124`, `FeatureFiles/FilesScreen.swift:214` (+2 more)
- Evidence: `'for attempt in 0...2 { ... catch let error as URLError { ... if endpoint.method == .get && attempt < 2 { continue } ...': immediate retries, no backoff`; `'timeout: TimeInterval = 30', applied as 'URLRequest(..., timeoutInterval: timeout)'`; `No view or model checks 'server.state' before starting a load` (+1 more)
- What happens: The server is black-holed (Tailscale peer offline, tunnel down, LAN host asleep), and the connection is already known to be `.waiting`. Opening Review shows 'Loading changes…'; the session refresh, Home search and the model catalogue each start fresh GETs. Each GET can take up to about 90 s (three 30-second attempts) before an error appears, and file reads 30 s, with no elapsed-time hint and no Cancel. On iPad, a New session screen with no cached projects shows 'Loading projects…' forever next to 'Could not open a project.' and never retries after the server comes back.
- Why it matters: Long, unexplained spinners right when the user most needs a clear 'offline' answer, and the New session screen gets stuck.
- Fix: Check server.state before UI-initiated loads. When the server isn't connected, immediately show cached content plus 'Waiting for \<server>'. Use a shorter timeout and at most one retry for interactive loads. Show 'Still loading… · Cancel' after about 5 s. Give NewSessionView a Try again button and re-run it when the server connects.

<a id="f15-11"></a>

## F15-11: Terminal and Context placeholders are dead ends the panel remembers and restores late

*P3 bug · state · effort S · found by review-changes*

- Where: `FeatureReview/WorkspaceReviewPanel.swift:20`, `FeatureReview/WorkspaceReviewPanel.swift:39`, `OCDesign/WorkspacePanel.swift:18-49`, `OCSync/ReviewModel.swift:28-29`, `OCSync/ReviewModel.swift:58` (+2 more)
- Evidence: `WorkspaceReviewPanel.swift:39 'OCEmptyState("\(tab) will appear here", detail: "Review tools are not available yet.", ...)' uses the page style, unlike the panel-style review states.`; `ReviewModel.swift:58 selectTab persists any tab. :118 restores the saved tab only inside the first refresh, which runs after the Changes tab appears.`; `ReviewModel.swift:28-29 sidebarWidth and sidebarVisible are plain in-memory properties, whereas split, wrap and showAll use @AppStorage (ReviewScreen.swift:13-15). With no loaded session, WorkspacePanel.swift:32-46 shows a mock 'Git changes +0 −0'.`
- What happens: iPhone: tap Terminal and see 'Terminal will appear here / Review tools are not available yet.' They aren't review tools. Close and reopen review: still on the placeholder. After a relaunch the panel opens on Changes, then switches to the saved tab when hydration finishes. iPad: widen or hide the file tree, then open another session or relaunch, and it is back to 240 pt and visible.
- Why it matters: Users land on non-functional screens with misleading copy, the tabs jump on their own, and layout preferences don't stick.
- Fix: Hide or disable Terminal and Context (or label them 'Coming in a later update') until M7/M8. Never save or restore placeholder tabs, and hydrate before the first render. Store the tree width and visibility in @AppStorage. Show a spinner instead of mock counts while the session loads. This revisits docs/design.md: 'Terminal and Context remain placeholders'.
- Also reported as: F19-13 by ipad-shell, F28-14 by states-coverage, F32-14 by design-parity

<a id="f15-12"></a>

## F15-12: File filter: misaligned rows, no field affordance or clear button, and navigation ignores it

*P3 bug · interaction · effort S · found by review-changes*

- Where: `FeatureReview/ReviewScreen.swift:95`, `FeatureReview/ReviewScreen.swift:104-106`, `FeatureReview/ReviewScreen.swift:141-142`, `OCSync/ReviewModel.swift:52`, `OCSync/ReviewModel.swift:63-68`
- Evidence: `crops/review-changes/native-filter.png: 'swift' typed into a field with no border. The Example.swift row has an empty line above the name, so the icon sits high and the name low.`; `crops/review-changes/ref-filter.png: the reference has a bordered field with a search icon and a clear '×'.`; `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.changes-filter-light-393-default.png is identical to the unfiltered screen: there is no filter on iPhone.` (+1 more)
- What happens: iPad: type 'swift' in Filter files. Root-level files gain an empty directory line. Clearing the filter means deleting the text by hand. ←/→ and Previous/Next still walk every file, so the preview can show a file the filter hides, with no row selected. iPhone has no filter at all, even with dozens of files.
- Why it matters: Filtering looks broken, is slow to clear, and doesn't narrow navigation the way users expect.
- Fix: Show the directory line only when it is non-empty, or render 'dir/name' on one line with a muted directory as the reference does. Use OCTextFieldStyle with a magnifier and a clear button. While a filter is active, make move() step through filteredFiles. Add a filter to the compact header.

<a id="f15-13"></a>

## F15-13: Accordion header polish: counts formatted two ways, jumping chevron, stale Collapse all, Open file on deleted files

*P3 bug · consistency · effort S · found by review-changes*

- Where: `FeatureReview/ReviewScreen.swift:89`, `FeatureReview/ReviewScreen.swift:176`, `FeatureReview/ReviewScreen.swift:178-191`, `FeatureReview/ReviewScreen.swift:210`, `FeatureReview/ReviewScreen.swift:229` (+2 more)
- Evidence: `crops/review-changes/iphone-large-header.png: the header totals read '+5,000 −5,000' in colour, while the accordion reads 'Modified +5000 −5000' in grey, ungrouped, and inside the Open file button. The summary at ReviewScreen.swift:210 uses String interpolation.`; `iphone/review-changes.png: '⌄ Sources/Example.swift' vs '› src/created.ts'. chevron-down.svg has a 16×16 viewBox and chevron-right.svg 20×20, so the title shifts about 4 pt when toggled.`; `ReviewScreen.swift:176 'model.state.openFiles.isEmpty ? "Expand all" : "Collapse all"', but openFiles keeps paths from other sources. Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.changes-working-light-820-accessibility5.png: the options block floats in the centre.` (+1 more)
- What happens: (1) Counts are formatted two ways on one screen, and the whole second header row, empty space included, is the Open file button, so tapping near the counts leaves the Changes tab. (2) Expand data.json under Git changes, then switch to Last turn changes: every file is collapsed but the button says Collapse all, and tapping it does nothing visible. (3) A deleted file offers Open file, which leads to 'File not found: removed.txt' and a dead tab in Files. (4) On iPad at accessibility sizes, '0 of 1 reviewed / Review options' is centred mid-panel.
- Why it matters: These are small mismatches, but they make the list look unfinished and cause accidental navigation.
- Fix: Use one number formatter and show the per-file counts as a separate coloured label, as the reference does. Use one chevron asset and rotate it. Derive the Expand/Collapse state from files.contains { isOpen($0.file) }. Hide Open file for deleted files and limit the button to its text. Add .frame(maxWidth: .infinity, alignment: .leading) to the options layout. Consider a darker success shade for micro text; this revisits the OC-2 tokens.

<a id="f22-12"></a>

## F22-12: Compact review header at accessibility sizes has three different leading edges

*P3 bug · visual · effort S · found by a11y-dynamic-type*

- Where: `FeatureReview/ReviewScreen.swift:170-191`
- Evidence: `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.changes-working-light-393-accessibility5.png: '+2 −2' starts ~10pt from the edge, 'Git changes' at ~22pt (ghost-button padding), and '0 of 1 reviewed' / 'Review options' at ~62pt. The Collapse-all icon floats between rows.`; `ReviewScreen.swift:170 is a VStack(spacing: 0) with the default center alignment. The options AnyLayout at :178-191 has no frame(maxWidth: .infinity, alignment: .leading), so it is centered.`
- What happens: iPhone at AX5, open Review → Changes. The source menu, the totals and the 'N of M reviewed' / 'Review options' block don't share an alignment: the options block is centered as a unit, and only the menu label carries button padding.
- Why it matters: The header looks unpolished and its controls are harder to scan in the primary iPhone review screen.
- Fix: Give the options layout .frame(maxWidth: .infinity, alignment: .leading). Give the totals the same horizontal inset as the ghost-button label, and align the expand/collapse button with the first row.
- Also reported as: F36-12 by sweep-review-snapshots

<a id="f29-09"></a>

## F29-09: Several errors drop the server's reason or give no next step

*P3 bug · copy · effort M · found by ux-writing*

- Where: `OCSync/ReviewModel.swift:182`, `FeatureComposer/NewSessionView.swift:152`, `OCSync/ComposerModel.swift:155`, `FeatureFiles/FilesScreen.swift:94`, `OCNetworking/PairingService.swift:15` (+3 more)
- Evidence: `ReviewModel.swift:182: if case .failure = result { self.error = "Request failed" }. Line 147 shows refresh errors through WriteErrorMessage.message(error) instead.`; `NewSessionView.swift:152: when forceRequired is set, the server's WorktreeFailure.message is replaced by “. The server requires resolving the worktree conflict first.”`; `ComposerModel.swift:155: “This prompt cannot be queued”, with no reason and no full stop, raised when shell mode meets Queue delivery` (+3 more)
- What happens: Each of these leaves the user unsure what went wrong or what to do:
  - Create Git repository fails (no permission, git missing): the Changes tab shows only “Request failed”.
  - New worktree from a branch that is already checked out: a generic conflict sentence replaces the server's explanation.
  - Shell mode with Follow-up behavior set to Queue while a run is active, then Send: “This prompt cannot be queued”.
  - A folder listing fails: the tree row becomes a button titled “Failed to list files”.
  - Pasting a plain URL into the pairing-link field: the error mentions a password field that isn't on that screen.
  - Opening a session that isn't cached when its load fails: “Session unavailable” promises cached messages that aren't there and offers no retry.
  - Backgrounding: a toast reports “Could not save drafts before pausing.”
- Why it matters: Users can't fix the problem or tell what to try next. Some messages contradict the screen they appear on.
- Fix: Fix each message:
  - Git init: use WriteErrorMessage.message(failure).
  - Worktree conflict: keep the server's message and add a step, e.g. “Pick another branch or remove that worktree on your computer.”
  - Shell plus Queue: “Shell commands can’t be queued. Send it now or wait for the run to finish.”
  - Folder listing: “Couldn’t list this folder. Tap to retry.”
  - Pairing link: “This isn’t a pairing link. Paste the link from opencode pair, or tap Use password.”
  - Session unavailable: add a Try again button and drop the cached-messages clause.
  - Draft-save toast: say what is at risk and what to do.
- Verifier's note: Overlaps F28-14 (Git init), F28-02 and F28-03 (Session unavailable) and F28-12 (draft toast); fix these together.

<a id="f29-11"></a>

## F29-11: Change summaries format numbers and statuses differently across Review, the turn card and Files

*P3 bug · consistency · effort S · found by ux-writing*

- Where: `FeatureReview/ReviewScreen.swift:89`, `FeatureReview/ReviewScreen.swift:111`, `FeatureReview/ReviewScreen.swift:154`, `FeatureReview/ReviewScreen.swift:162`, `FeatureReview/ReviewScreen.swift:188` (+5 more)
- Evidence: `iphone/review-large-unified.png: “Last turn changes +5,000 −5,000” sits directly above “Modified +5000 −5000 · Open file”`; `iphone/review-comment.png: the turn card says “src/created.ts Created” and “deleted-by-turn.txt Deleted”. review-turn-navigation.png: the accordion says “Added +1 −0”.`; `ReviewScreen.swift:210: the summary is built with plain String interpolation, which skips digit grouping. Its status words are “Added”, “Removed” and “Modified”; the tree uses A/D/M.` (+2 more)
- What happens: In a large turn, the source header reads “+5,000 −5,000” and the file header right below it reads “+5000 −5000”. A new file is “Created” in the turn card, “Added” in the accordion and “A” in the tree. A deleted file is “Deleted”, “Removed” and “D”. Open a text file over 1 MiB in Files and the bar reads “Showing the first 1,048,5xx of 5,242,880” with no unit, while a large image reads “1 MB of 5 MB”. On iPhone, Review options lists “Reviewed Sources/Example.swift”, which reads like a status rather than an action.
- Why it matters: Different numbers and words for the same file make users wonder whether these are different things. Unitless byte counts are unreadable, and the menu items don't say what tapping them does.
- Fix: Format counts with .formatted() in OCDiffInput.summary. Choose one status vocabulary (the desktop's Created/Deleted, or Added/Modified/Deleted) and use it in all three views. Show partial loads with .byteCount (“Showing the first 1 MB of 5 MB”) and use MB throughout. Label the menu items “Mark as reviewed: \<file>” and “Mark as not reviewed: \<file>”, or use checkmarked toggles.

<a id="f31-10"></a>

## F31-10: Review panel details look unfinished: line numbers sit above the code baseline, '−5,000 1/1' runs together, a 6-pt grey divider, and an unstyled 'Filter files'

*P3 bug · visual · effort S · found by visual-polish-ipad*

- Where: `FeatureReview/ReviewScreen.swift:138-140`, `FeatureReview/ReviewScreen.swift:48`, `FeatureReview/ReviewScreen.swift:94-95`, `FeatureFiles/FilesScreen.swift:48`, `FeatureFiles/FilesScreen.swift:81` (+2 more)
- Evidence: `ipad-review-large-split.png (zoom scratch/visual-polish-ipad/large-split-lines.png): line numbers sit about 3pt above the code baseline. Numbers are drawn at 'y: 3' with the bare font, while code uses a paragraph style with 'minimumLineHeight = max(24, ceil(fontSize * 1.65))'`; `ipad-review-large-split.png toolbar (zoom large-split-toolbar.png): '+5,000 −5,000 1/1'. The file counter shares an HStack with spacing OCSpacing.xxs (2pt) and reads as part of the deletion count`; `ipad-review-changes.png: the tree/diff divider is 12px (6pt) of (229,229,229) at x=1412–1423px, and the Files tab has the same bar; the desktop review-light-1180x820.png uses a hairline` (+2 more)
- What happens: iPad landscape, reviewing a diff in split view: the gutter looks misaligned on every line, and the toolbar counter is ambiguous.
- Why it matters: The diff viewer, a core M4 surface, looks less polished than the desktop it copies, and the ambiguous counter can be misread.
- Fix: Draw the gutter numbers with the code's paragraph style, or offset them by lineHeight − font.lineHeight. Separate '1/1' with OCSpacing.sm and muted styling. Draw a hairline divider and keep the existing invisible hit area (`contentShape(... inset(by: -19))`). Use one search-field component (icon plus layer1 fill) in Changes, Files and Home.
- Verifier's note: Track the line-number item under F30-12.

<a id="g08-m2"></a>

## G08-M2: Turn changes vanishes from the source menu as soon as another source is chosen

*P3 bug · navigation · effort S · found by verifier G08*

- Where: `OCSync/ReviewModel.swift:43-47`, `OCSync/ReviewModel.swift:75`, `FeatureReview/ReviewScreen.swift:84`, `FeatureTranscript/TimelineRowView.swift:90`
- Evidence: `ReviewModel.swift:44-45: 'var result = ReviewSource.available(vcs: vcs, session: !sessionID.isEmpty); if case .turn = state.source { result.append(state.source) }'. The turn source is listed only while it is the current state.source.`; `choose(.working) sets state.source = .working (ReviewModel.swift:75), so the next menu render drops the turn.`; `The only way to create a .turn source is tapping a file in a turn card (TimelineRowView.swift:90).`
- What happens: Tap a file in an older turn's Changed files card; Review opens on 'Turn changes'. Choose 'Git changes' from the source menu to compare with the working tree, then open the menu again. It now lists only Git changes, Branch changes and Last turn changes. To get back to that turn, the user has to close Review (a sheet on iPhone), scroll the transcript back to the card and tap a file again.
- Why it matters: Comparing a turn with the working tree or the branch becomes a round trip through the transcript, and users may think the turn view is gone.
- Fix: Remember the most recently opened turn (for example a lastTurnSource field in ReviewState) and keep it in `sources` until another turn is opened. Title it with its turn, as the source-labelling finding suggests.

<a id="f15-14"></a>

## F15-14: Error and empty states hide the reason and offer no next step

*P3 bug · copy · effort S · found by review-changes*

- Where: `FeatureReview/ReviewScreen.swift:31-36`, `FeatureReview/ReviewScreen.swift:41-43`, `OCSync/ReviewModel.swift:127-130`, `OCSync/ReviewModel.swift:147`, `OCSync/ReviewModel.swift:180-182`
- Evidence: `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.changes-error-light-393-default.png: the real message is a red line at the top edge, while the centre shows 'Request failed' with an empty detail and Try again.`; `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.changes-create-failure-light-393-default.png: only 'Request failed', at the top. ReviewModel.swift:182 'if case .failure = result { self.error = "Request failed" }' discards the server's reason.`; `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.changes-empty-last-turn-light-820-default.png: 'No file changes yet / Project changes will appear here' shown for Last turn changes.` (+1 more)
- What happens: (1) First load fails: two disconnected messages appear. (2) Create Git repository fails (for example on permissions): the only text is 'Request failed'. (3) After a successful load, a refresh error stays as a red line above stale files until a later refresh succeeds, with no retry or dismiss besides pull-to-refresh. (4) If the project still lists Git but /vcs keeps returning no provider (plugin failed to start, .git removed), 'Loading changes…' spins forever with no retry. (5) An empty Last turn on iPad says project changes will appear here and offers no 'Show Git changes'.
- Why it matters: Users can't tell what went wrong or what to do next, and can get stuck on a spinner.
- Fix: Put the message in the empty state's detail. Keep the server's message when init fails. Add a retry button to the inline error. Time out awaitingProvider after about 10 s into the no-Git state or a retry. Use source-aware empty copy with a one-tap switch to Git changes.

<a id="f15-05"></a>

## F15-05: Reviewed state is invisible in the iPhone accordion and buried in a per-file menu

*P2 improvement · ux-flow · effort M · found by review-changes*

- Where: `FeatureReview/ReviewScreen.swift:179-189`, `OCDesign/CodeCell.swift:174-187`, `FeatureReview/ReviewScreen.swift:136-147`
- Evidence: `iphone/review-reviewed.png: '1 of 3 reviewed', yet the three collapsed headers look identical.`; `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.changes-reviewed-light-393-default.png`; `ReviewScreen.swift:188 'Button((model.isReviewed(file) ? "Unmark " : "Reviewed ") + file.file)'. ReviewScreen.swift:189 'Review options' is plain text with no menu affordance. CodeHeader.configure has no reviewed parameter.` (+1 more)
- What happens: iPhone: mark Sources/Example.swift reviewed through Review options. The header says '1 of 3 reviewed' but nothing shows which file it is: the file just collapses, like any other collapsed file. To mark a file, the user has to find 'Review options', which doesn't look tappable, and then pick 'Reviewed \<full path>' from one item per file (60 items for 60 files), where the wording reads like a status. On iPad, at panel widths of about 480–580 pt or with a widened tree, the Reviewed switch scrolls out of view with no indicator.
- Why it matters: The feature ARCHITECTURE requires for per-file review effectively can't be used on iPhone, and on narrower iPad panels it is hard to find.
- Fix: Add a check badge and a Reviewed toggle to each accordion header (for example on the Modified/Open file row), and dim or badge reviewed headers. Rename the menu items 'Mark as reviewed' / 'Mark as not reviewed' (or use Toggles), and add 'Mark all reviewed' and 'Clear'. Give Review options an ellipsis icon. On iPad, pin the Reviewed switch outside the scrolling toolbar or move it into the file header.
- Also reported as: F30-07 by visual-polish-iphone, F36-06 by sweep-review-snapshots

<a id="f15-10"></a>

## F15-10: Source labels don't identify the turn or base, and menus don't show the current choice

*P3 improvement · ux-flow · effort M · found by review-changes*

- Where: `OCModels/Review.swift:17-19`, `OCSync/ReviewModel.swift:43-47`, `OCSync/ReviewModel.swift:91-93`, `FeatureReview/ReviewScreen.swift:84`, `FeatureReview/ReviewScreen.swift:144`
- Evidence: `ipad/ipad-review-turn-navigation.png ('Turn changes', 0 of 3) vs ipad/ipad-review-reviewed.png ('Last turn changes', 1 of 3): the same turn's three files.`; `crops/review-changes/ref-filter.png: the reference shows 'Last turn chan… ⌄' with a dropdown chevron. The native control (review-changes.png) has only a branch icon.`; `Review.swift:18 '.turn: "Turn changes"'. ReviewModel.swift:92 marks keys begin with 'source.key'. ReviewScreen.swift:144 the Diff view menu has no checkmarks.`
- What happens: iPad, panel open beside the transcript: tap a file in an older turn's card, then later in another turn's card. Both show just 'Turn changes', with nothing saying which prompt or turn. 'Branch changes' doesn't name its base. The source control looks like a static label, and neither it nor the Diff view menu marks the active option. A file reviewed under Last turn changes shows as unreviewed when the same turn is opened from its card (identical patch).
- Why it matters: The core question 'which changes am I looking at?' goes unanswered, and review marks seem to reset at random.
- Fix: Title turn sources with the turn's position or prompt excerpt ('Turn 3 · Review a small edit'), and the branch source as 'Branch changes vs main'. Add a chevron and use a Picker or checkmarks. Key marks by the resolved turn ID (map lastTurn to its turn) or by path and digest alone. This revisits docs/design.md, which keys marks by source.

<a id="f27-09"></a>

## F27-09: Per-session review, files and turn-diff models are never evicted and keep patches, images and file contents after their screens close

*P3 improvement · performance · effort M · found by ui-performance*

- Where: `OCSync/ReadStore.swift:33-36`, `OCSync/ReviewModel.swift:14-16`, `OCSync/ReviewModel.swift:98-101`, `OCSync/ReviewModel.swift:234-242`, `OCSync/FilesModel.swift:19` (+3 more)
- Evidence: `ReadStore.swift:33-36: the 'reviews', 'turnDiffs', 'fileModels' and 'composers' dictionaries only ever gain entries (ReviewModel.swift:234-242, FilesModel.swift:252-254)`; `ReviewModel.swift:100: disappear() cancels tasks but keeps 'files' (every patch) and 'images' (raw Data). FilesModel.disappear (FilesModel.swift:50-56) keeps 'content', 'children' and 'results'`; `ReadResync.swift:227-236 evicts only the transcript when TranscriptResidency drops a session (at most six are kept). Sources has no memory-warning handling` (+1 more)
- What happens: Over a day on iPad, visit 20 sessions, open Review and Files in each, preview some images and a large log, and scroll long transcripts with many changes cards. All of it stays resident, even though only six transcripts are kept.
- Why it matters: Memory grows steadily over long-lived app sessions, which raises the jetsam risk on iPhone. The transcript residency budget gives a false sense of a bound.
- Fix: In evictTranscript, also evict reviews[id], fileModels[id] and turnDiffs[id:*], keeping only light UI state such as scroll offsets and sidebar width. Drop files, images and content when the viewer count reaches zero. Cap turnDiffs with an LRU. Purge heavy payloads on UIApplication.didReceiveMemoryWarningNotification.
- Also reported as: G14-M1 by verifier G14
