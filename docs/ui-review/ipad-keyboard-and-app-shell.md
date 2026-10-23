# UI review: iPad, keyboard and app shell

Part of the [UI review](README.md). 10 bugs and 4 improvements, bugs first, then by severity. Paths under `Packages/OpencodeKit/Sources` are written without that prefix.

| ID | Severity | Finding |
| --- | --- | --- |
| [F19-01](#f19-01) | P1 bug | In portrait and other narrow iPad widths, New session stays hidden under the Home sheet (the + looks dead, and ⌘N opens Home) |
| [F19-02](#f19-02) | P2 bug | Project tabs only filter the Home list: tapping one changes nothing on screen when Home is collapsed, and New session ignores the chosen project |
| [F19-03](#f19-03) | P2 bug | Rotating or resizing turns the open Home sidebar into a modal sheet over the session |
| [F34-06](#f34-06) | P2 bug | Unwrapped code and diffs can't be scrolled sideways with a trackpad or mouse |
| [F34-04](#f34-04) | P2 bug | Pasting or dropping several images onto the prompt keeps only one |
| [F19-14](#f19-14) | P3 bug | Pane cards don't match: Home and New session have square corners, and the sidebar card starts 44 pt below the others |
| [F34-11](#f34-11) | P3 bug | Filter fields: Files ↑/↓ highlight doesn't scroll; Review's filter and Add server ignore Return |
| [F34-14](#f34-14) | P3 bug | ⌘N works before any server is saved and opens an empty sheet at compact widths |
| [F34-05](#f34-05) | P3 bug | Drops onto the prompt text bypass the composer's drop handling |
| [F34-09](#f34-09) | P3 bug | ⌘' opens a model picker that can't be driven from the keyboard |
| [F19-05](#f19-05) | P2 improvement | Opening review pins the timeline at 450 pt and squeezes the panel below its 480-pt layout on 11-inch iPads and in portrait |
| [F19-10](#f19-10) | P2 improvement | Below 1,100 pt, Home is only a centred form sheet, even on a 13-inch iPad in portrait |
| [F34-10](#f34-10) | P2 improvement | Most spec shortcuts are missing or need the prompt focused, and none appear in the menu bar or ⌘ overlay |
| [F19-11](#f19-11) | P3 improvement | Project tabs reorder with server activity and lack the desktop tab's avatar, close button and +; the pane toggles show no open or closed state |

<a id="f19-01"></a>

## F19-01: In portrait and other narrow iPad widths, New session stays hidden under the Home sheet (the + looks dead, and ⌘N opens Home)

*P1 bug · ux-flow · effort S · found by ipad-shell*

- Where: `OCDesign/WorkspaceShell.swift:54`, `OCDesign/WorkspaceShell.swift:58`, `FeatureServers/ServerRootView.swift:151`, `FeatureServers/ServerRootView.swift:82`, `FeatureInbox/HomeView.swift:113` (+1 more)
- Evidence: `WorkspaceShell.swift:58-61: '.onChange(of: selectionID) { _, next in if next == nil { homeOpen = true } else if !wide { homeOpen = false } }'`; `WorkspaceShell.swift:54: the Home sheet is shown while 'homeOpen && !wide && allowsPresentation', and wide means width >= 1,100 pt`; `ServerRootView.swift:154: in regular width, beginSession only sets 'sessionPath = []'. Nothing closes the sheet, and the + in the Home header (HomeView.swift:113) calls beginSession.` (+2 more)
- What happens: iPad Air 11-inch in portrait (820 pt). The same applies at 834 and 1,024 pt portrait, in 678–981 pt Split View and in Stage Manager windows under 1,100 pt. At launch, Home is presented as a sheet over the New session screen. Tapping + in the Home header leaves the sheet on screen with an unchanged list. Either the selection was already nil, so nothing changes, or it becomes nil, which re-asserts homeOpen = true. Either way the New session composer behind the sheet stays hidden. With a session open and Home closed, ⌘N clears the selection, and the onChange presents the Home sheet over the composer it just opened.
- Why it matters: Starting a session is the app's core action. On iPads held in portrait, the visible New session button appears to do nothing until the user discovers they must swipe the sheet away.
- Fix: Only auto-open Home when it is the inline sidebar. When the selection becomes nil at a narrow width, close the sheet: `if next == nil { homeOpen = wide } else if !wide { homeOpen = false }`. Because + with an already-nil selection triggers no change, also pass a newSessionRequest UUID into OCWorkspaceShell (as reviewRequest is passed) that sets homeOpen = false when !wide. Add a portrait + and ⌘N case to ComposerSmokeTests.
- Verifier's note: Close the narrow-width sheet on every explicit navigation from Home, not through onChange(of: selectionID). Tapping the session that is already open (same SessionRef.id), or Review for the request already shown, also changes nothing and leaves the sheet up. Setting homeOpen = wide on a nil selection also stops the creation-failure path from showing Home over the restored prompt in portrait (ServerRootView.swift:82-86 sets sessionPath = []). A one-shot request, such as a dismiss-Home UUID passed the same way reviewRequest is, sent from selectSession and newSession, covers all three cases.
- Also reported as: F34-02 by ipad-keyboard-multitasking, F40-03 by navigation-state-restoration

<a id="f19-02"></a>

## F19-02: Project tabs only filter the Home list: tapping one changes nothing on screen when Home is collapsed, and New session ignores the chosen project

*P2 bug · functional · effort M · found by ipad-shell*

- Where: `OCDesign/WorkspaceShell.swift:84`, `FeatureServers/ServerRootView.swift:50`, `FeatureServers/ServerRootView.swift:156`, `FeatureComposer/NewSessionView.swift:61`, `FeatureInbox/HomeView.swift:50`
- Evidence: `ipad/ipad-session-list.png: Home's project picker (whose ID the tabs share) is set to composer-worktree-project, while the New session screen beside it targets 'project · Local repository'`; `WorkspaceShell.swift:84: 'Button { selection = project.id }' is the tab's only action. selectedProject is read only by HomeView (the recent filter, the picker label and the session fetch).`; `NewSessionView.swift:61: 'else if let project = server.projects.first { directory = project.canonical; ... }'. ServerRootView.swift:160 '.id(server.id)' keeps that choice when the tab changes.` (+1 more)
- What happens: iPad in landscape with Home collapsed (as in ipad-review-changes.png), or in portrait with the Home sheet closed. Tap the review-project tab. The main column, review panel and composer stay on the current session. In light mode the tab doesn't even highlight (see the active-tab finding), so nothing on screen changes. The next time Home is opened, its Today list is quietly filtered to review-project. With no session open, tapping a tab leaves the New session screen on its first project, and + still starts the session in the most recently active project rather than the selected tab.
- Why it matters: A row of tabs along the top reads as the way to switch projects, as on the desktop, but these tabs neither navigate nor scope new work. A session can start in a different repository from the tab the user picked unless they notice the small selector under the composer.
- Fix: Give each tab a real destination: open that project's most recent root session, or a New session screen scoped to it, in the main column, and keep setting the Home filter. Pass the selected project to NewSessionView through a new parameter. Don't reuse the failure-recovery `directory:` parameter, which also sets the 'Failed to create session' error. Include the project in the view's .id so the screen re-targets when the tab changes.
- Also reported as: F31-03 by visual-polish-ipad, F40-08 by navigation-state-restoration

<a id="f19-03"></a>

## F19-03: Rotating or resizing turns the open Home sidebar into a modal sheet over the session

*P2 bug · state · effort M · found by ipad-shell*

- Where: `OCDesign/WorkspaceShell.swift:54`, `OCDesign/WorkspaceShell.swift:62`, `OCDesign/WorkspaceShell.swift:20`, `FeatureServers/ServerRootView.swift:45`, `OCDesign/WorkspaceShell.swift:65`
- Evidence: `ipad/ipad-portrait.png: taken immediately after rotating from ipad-split.png (Home sidebar open, subagent session open). The Home sheet covers the session.`; `UITests/ReadSmokeTests.swift:94-97: screenshot('ipad-split'), then rotate(to: .portrait), then screenshot('ipad-portrait')`; `docs/m4-audit.md:144 saw the portrait Home sheet 'finish dismissing' after rotation, but treated it as a test race and changed only the test` (+2 more)
- What happens: Four cases. (1) Landscape, Home open, a session selected: rotate to portrait and the Home sheet slides up over the transcript, then dismisses. (2) The same with no session selected: the sheet stays over the New session screen. (3) Reasoned from code: shrink a regular window to Slide Over or a 1/3 Split View (compact), then widen it to a 1/2 split (678 pt). OCWorkspaceShell is recreated with homeOpen = true, so Home is presented as a sheet over the open session, and the review panel's open state is lost. (4) Review was open beside the timeline, the window narrows below 768 pt and the user opens review as a sheet, then the window widens again: reviewOpen and reviewSheet are both true, so the review shows inline and in a sheet at the same time.
- Why it matters: Rotation and resizing are routine on iPad. Each time, a modal covers the work the user was looking at, and their pane choices reset.
- Fix: Keep separate state for the inline sidebar and the narrow-width sheet. Present the sheet only from an explicit toggle (or at launch with no selection), never as a side effect of a width change. For example, derive `sheetVisible = homeSheet && !wide`, where only the toggle sets homeSheet. Initialise the shell with homeInitiallyOpen = sessionPath.isEmpty, and hold the shell's state in the parent or in @SceneStorage so a size-class flip doesn't reset it. When the width moves from narrow to wide and reviewSheet is true, close the sheet and set reviewOpen = true.
- Verifier's note: Besides separating the sidebar state from the sheet state: either use OCWorkspaceShell at every iPad width and keep the NavigationStack for the phone idiom only, or lift homeOpen and reviewOpen (plus the timeline anchor) into ServerRootView or @SceneStorage. Then a compact/regular crossing also keeps review open, the transcript position and the prompt focus (F34-13). Start with Home closed when a session is selected.
- Also reported as: F26-04 by swiftui-state, F34-03 by ipad-keyboard-multitasking, F34-13 by ipad-keyboard-multitasking, F40-04 by navigation-state-restoration

<a id="f34-06"></a>

## F34-06: Unwrapped code and diffs can't be scrolled sideways with a trackpad or mouse

*P2 bug · interaction · effort S · found by ipad-keyboard-multitasking*

- Where: `OCDesign/CodeCollection.swift:43`, `OCDesign/CodeCollection.swift:265`, `OCDesign/CodeCollection.swift:279`
- Evidence: `CodeCollection.swift:43-44  'let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.horizontal(_:)))': allowedScrollTypesMask is never set, and its default accepts no scroll events, so two-finger trackpad and mouse-wheel scrolls never reach this recognizer`; `CodeCollection.swift:265  'return !parent.wrap && abs(velocity.x) > abs(velocity.y)': the horizontal offset is applied by hand, because the collection view scrolls only vertically`; `The same renderer backs Review, the Files viewer and the transcript diff cards (DiffCardView.swift:76)`
- What happens: iPad with a Magic Keyboard trackpad and Wrap lines turned off (in Settings or the Diff view menu). A two-finger swipe left or right over a long line does nothing. Only click-and-drag scrolls it, and holding the click too long starts the 0.4-second long-press comment gesture.
- Why it matters: Reviewing wide diffs with a trackpad, a core iPad scenario, is awkward and feels broken.
- Fix: Set pan.allowedScrollTypesMask = .continuous (or .all) and handle scroll translation in horizontal(_:) the same way as touch.
- Verifier's note: Set allowedScrollTypesMask = .all so discrete Shift-wheel scrolls work too. The velocity check in gestureRecognizerShouldBegin still applies to scroll pans.
- Also reported as: G09-M1 by verifier G09

<a id="f34-04"></a>

## F34-04: Pasting or dropping several images onto the prompt keeps only one

*P2 bug · functional · effort S · found by ipad-keyboard-multitasking*

- Where: `FeatureComposer/PromptEditor.swift:82`, `FeatureComposer/ComposerDock.swift:157`, `FeatureComposer/ComposerDock.swift:389`, `FeatureComposer/ComposerMedia.swift:13`, `OCSync/ComposerModel.swift:121`
- Evidence: `PromptEditor.swift:84  'parent.pasteAttachment(item.itemProvider); item.setNoResult()': the paste delegate's transform runs once for each pasted or dropped item`; `ComposerDock.swift:157  'pasteAttachment: { provider in run { try await importProvider(provider) } }'`; `ComposerDock.swift:390  'action?.cancel(); action = Task { ... }'` (+2 more)
- What happens: The user copies three photos and presses ⌘V in the prompt, or drags three photos from Photos in Split View onto the prompt text. Each item starts its own run() task, which cancels the previous one, and the overlapping imports reach addAttachment while the first image is still being downscaled and stored, so they are discarded. One chip appears and no error is shown. Dropping the same photos on the dock's toolbar strip keeps all three.
- Why it matters: Attachments go missing silently, so the agent receives fewer images than the user sent, and the result depends on exactly where the drop lands.
- Fix: Send paste and drop providers to one sequential import queue (a pending list drained by a single task) instead of one run() per item. Have addAttachment wait or queue instead of returning when busy, and report any item that is skipped.

<a id="f19-14"></a>

## F19-14: Pane cards don't match: Home and New session have square corners, and the sidebar card starts 44 pt below the others

*P3 bug · consistency · effort S · found by ipad-shell*

- Where: `FeatureComposer/NewSessionView.swift:53`, `FeatureInbox/HomeView.swift:78`, `FeatureInbox/HomeView.swift:60`, `FeatureTranscript/SessionScreen.swift:78`, `OCDesign/WorkspaceShell.swift:46`
- Evidence: `crops/ipad-shell/pane-corners.png: zoomed pixel crops`; `In ipad-session-list.png, the New session card's left edge is at x = 544 px on every row from its top (a square corner). In ipad-transcript-live.png, the session card's edge goes from 569 to 545 px over 20 px (a 10-pt radius). The sidebar card's edge is at x = 16 px on every row (square).`; `Only SessionScreen.swift:78 and WorkspacePanel.swift:51 clip to OCRadius.xl; NewSessionView.swift:53 and HomeView.swift:78 only set a background` (+1 more)
- What happens: iPad landscape with Home open: switch between a session and New session and the main card's corners change from rounded to square. The sidebar card always has square corners, and its top edge sits one header-height below the main card's.
- Why it matters: A small defect, but the shell reads as three unrelated surfaces rather than the desktop's matching 10-pt cards.
- Fix: Apply the card treatment once in OCWorkspaceShell: background plus clipShape(RoundedRectangle(cornerRadius: OCRadius.xl)) on the sidebar, main and panel slots. Then drop the per-screen clips. Either move the Home header inside the sidebar card or give the main and panel headers the same top inset.
- Also reported as: F31-08 by visual-polish-ipad

<a id="f34-11"></a>

## F34-11: Filter fields: Files ↑/↓ highlight doesn't scroll; Review's filter and Add server ignore Return

*P3 bug · interaction · effort S · found by ipad-keyboard-multitasking*

- Where: `FeatureFiles/FilesScreen.swift:85`, `FeatureFiles/FilesScreen.swift:88`, `FeatureReview/ReviewScreen.swift:95`, `FeatureServers/AddServerView.swift:61`
- Evidence: `FilesScreen.swift:85-86  '.onKeyPress(.upArrow/.downArrow) { resultIndex = ... }' drives a ScrollView/LazyVStack (FilesScreen.swift:88-104) that has no ScrollViewReader`; `The composer's suggestion list does follow its highlight: ComposerDock.swift:247 'scroll.scrollTo(suggestions[next].id)'`; `ReviewScreen.swift:95  'TextField("Filter files", text: $model.filter)' has no onSubmit or onKeyPress` (+1 more)
- What happens: On the iPad Files tab, the user filters for 'swift' and presses ↓ past the visible rows. The highlight moves off-screen, and Return opens a file they can't see. In Review's sidebar, ↓ and Return do nothing after typing a filter. In Add server, pressing Return after the password does nothing; the user has to tap Connect.
- Why it matters: Small but constant friction in keyboard-driven flows, and the filter fields don't behave the same way.
- Fix: Wrap the Files results in a ScrollViewReader and scrollTo(model.results[resultIndex].path). Give Review's filter the same ↑/↓/Return handling (calling model.select). In Add server, add .onSubmit { connectTapped() } with .submitLabel(.go) on the last field and .next chaining on the others.

<a id="f34-14"></a>

## F34-14: ⌘N works before any server is saved and opens an empty sheet at compact widths

*P3 bug · state · effort S · found by ipad-keyboard-multitasking*

- Where: `FeatureServers/ServerRootView.swift:94`, `FeatureServers/ServerRootView.swift:154`, `FeatureServers/ServerRootView.swift:157`
- Evidence: `ServerRootView.swift:93-95  'Button("New session", action: beginSession).keyboardShortcut("n", modifiers: .command).hidden()' sits on the root ZStack, including the empty-servers onboarding branch`; `ServerRootView.swift:154  'else { creatingSession = true }', and ServerRootView.swift:157 'if let server = registry.servers.first(...) ?? registry.servers.first { NewSessionView(...) }', which renders nothing when no server exists`
- What happens: An iPad in a compact window, or an iPhone with a keyboard, before any server is added: ⌘N presents a sheet with no content, only Cancel and the drag indicator. With Settings open, ⌘N may also clear the open session behind the sheet.
- Why it matters: A confusing blank modal during first run.
- Fix: Disable the hidden command when registry.servers is empty or a modal is presented. In M6, move it into a .commands item with a .disabled condition.

<a id="f34-05"></a>

## F34-05: Drops onto the prompt text bypass the composer's drop handling

*P3 bug · interaction · effort M · plausible, needs a running app to confirm · found by ipad-keyboard-multitasking*

- Where: `FeatureComposer/PromptEditor.swift:26`, `FeatureComposer/PromptEditor.swift:85`, `FeatureComposer/ComposerDock.swift:66`, `FeatureComposer/ComposerDock.swift:90`, `FeatureFiles/FilesScreen.swift:133`
- Evidence: `FilesScreen.swift:133  '.draggable(ComposerInput.absolute(entry.path, directory: model.directory))' (a plain String)`; `PromptEditor.swift:26  the pasteConfiguration accepts plainText, image, pdf and fileURL, so the UITextView's own drop interaction accepts text`; `PromptEditor.swift:85  '} else { item.setDefaultResult() }': plain text is inserted as is` (+2 more)
- What happens: iPad in landscape with Files open in the review panel. The user long-presses a file row and drops it on the prompt text, which covers most of the dock. The text view's built-in drop takes it and inserts the absolute path as plain text, with no @mention chip and no file part sent. Dropped on the toolbar strip, the same row becomes a mention, or, if the outer onDrop wins, a text attachment named 'Attachment'. A .swift file dragged from the Files app onto the text has its whole contents pasted inline; dropped on the toolbar, it is attached.
- Why it matters: The desktop's 'drag a file into the prompt' gesture gives inconsistent results, and a long file can flood the prompt.
- Fix: Give file rows their own Transferable with a custom UTType and handle it in the paste delegate by calling mentionFile. Treat file-backed providers (a suggestedName or file representation) as attachments there too, and insert plain text only for text snippets. Replace the two stacked handlers with one dropDestination whose isTargeted tints the dock border, and return false when nothing could be imported.
- Verifier's note: First check which SwiftUI handler wins when .dropDestination and .onDrop are stacked on the same view. If .onDrop wins, the mention path at :66 never runs, and toolbar drops of Files rows become 'Attachment' text files.

<a id="f34-09"></a>

## F34-09: ⌘' opens a model picker that can't be driven from the keyboard

*P3 bug · interaction · effort M · plausible, needs a running app to confirm · found by ipad-keyboard-multitasking*

- Where: `FeatureComposer/ComposerDock.swift:72`, `FeatureComposer/ComposerDock.swift:378`, `FeatureComposer/ModelPicker.swift:20`, `FeatureComposer/ModelPicker.swift:49`, `FeatureComposer/ComposerDock.swift:374`
- Evidence: `ModelPicker.swift:49  '.searchable(text: $query, prompt: "Search models")' with no searchFocused and no onSubmit(of: .search); the rows are plain Buttons in a List without selection (ModelPicker.swift:20-26)`; `ComposerDock.swift:72  '.popover(isPresented: $showModels)'; the prompt keeps its priority Esc and Return commands (PromptEditor.swift:215-222)`; `ComposerDock.swift:374-375  'case .escape: if model.options.shell { ... } else if running { stop() }'`
- What happens: iPad with a keyboard: ⌘' shows the picker, but the search field isn't focused, ↑/↓ don't move through models, and Return doesn't choose one, so the user has to reach for the screen. If the prompt stays first responder under the popover (popovers don't normally resign it), typed letters edit the hidden prompt, and pressing Esc to close the picker reaches the prompt instead, which stops a running agent.
- Why it matters: The model shortcut is a dead end for keyboard users and risks interrupting a run.
- Fix: Focus the search field when the picker appears (searchFocused), choose the first match on .onSubmit(of: .search), and use List(selection:) for ↑/↓ and Return. Resign the prompt, or suspend its key commands, while the picker is open, and bind Esc to dismiss the picker.
- Verifier's note: Also have handleKey(.escape) return false when it does nothing, or drop the priority Esc command while the picker is presented, so Esc can reach the popover.

<a id="f19-05"></a>

## F19-05: Opening review pins the timeline at 450 pt and squeezes the panel below its 480-pt layout on 11-inch iPads and in portrait

*P2 improvement · layout · effort M · found by ipad-shell*

- Where: `OCDesign/WorkspaceShell.swift:30`, `OCDesign/WorkspaceShell.swift:31`, `OCDesign/WorkspaceShell.swift:49`, `OCDesign/Metrics.swift:40`, `FeatureReview/ReviewScreen.swift:29` (+1 more)
- Evidence: `WorkspaceShell.swift:31: 'let panelWidth = max(OCLayout.inspector, available - OCLayout.timelineWithReview)'. The timeline always gets exactly 450 pt, and there is no divider to drag.`; `Panel widths computed with Home open: 395 pt at 1,133 pt (iPad mini, landscape), 442 at 1,180 (iPad Air 11), 456 at 1,194, 472 at 1,210 (iPad Pro 11). In portrait, where Home is a sheet: 324 at 798, 346 at 820, 360 at 834. All are below the 480-pt regular layout in ReviewScreen.swift:29 and FilesScreen.swift:32.`; `docs/m4-audit.md:154 records the 442-pt squeeze at 1,180 pt: 'no file tree, no split, and a unified diff'` (+1 more)
- What happens: iPad Air 11-inch in landscape with Home open, which is the launch default. Tap the review toggle. The panel is 442 pt wide, so Changes falls back to the accordion with no file list and no split diff, Files becomes separate screens, and line comments open in a sheet instead of inline. In portrait (820 pt) a 346-pt panel sits beside the 450-pt transcript, and both are cramped. On a 13-inch iPad with Home closed, the transcript stays at 450 pt while review takes 892 pt, and the split can't be rebalanced.
- Why it matters: Review is a main reason to use the iPad layout, yet on the most common iPads it opens in its phone layout. This revisits docs/design.md, which says the timeline 'starts at' 450 pt although nothing lets users change it.
- Fix: When review opens beside an inline Home and the panel would be under 480 pt, collapse Home, and restore it when review closes. Add a draggable, resettable divider between timeline and panel: at least 360 pt for the timeline and 480 pt for the panel, with the width saved as the review file sidebar's width is. Add a way to expand review over the timeline. In portrait below about 930 pt, open review as a full-height overlay on the main column instead of a 346-pt column.

<a id="f19-10"></a>

## F19-10: Below 1,100 pt, Home is only a centred form sheet, even on a 13-inch iPad in portrait

*P2 improvement · ipad · effort M · found by ipad-shell*

- Where: `OCDesign/Metrics.swift:38`, `OCDesign/WorkspaceShell.swift:28`, `OCDesign/WorkspaceShell.swift:55`, `OCDesign/WorkspaceShell.swift:66`, `OCDesign/Surfaces.swift:57`
- Evidence: `Metrics.swift:38: 'workspaceWide: CGFloat = 1_100'. WorkspaceShell.swift:28 also turns off the inline sidebar at every accessibility text size.`; `ipad/ipad-portrait.png: a Home sheet of about 580 x 650 pt in the middle of an 820 x 1,180-pt screen, showing about five rows, with the rest dimmed`; `docs/design.md:14 maps the shell to the desktop's shell/{mobile-drawer,mobile-panel-drawer}.tsx, which slide in from the edge rather than appearing as a centred dialog`
- What happens: A 13-inch iPad in portrait (1,024–1,032 pt), a 12.9-inch 2/3 Split View (981 pt), or a 1,000-pt Stage Manager window. Home can't sit beside the session, even though 1,024 − 256 still leaves 736 pt for the transcript. The Home toggle opens a centred modal instead. At accessibility text sizes the same happens on a 1,366-pt landscape screen, and review also becomes a form sheet about 580 pt wide.
- Why it matters: Switching sessions means opening and closing a modal each time, and the modal shows only a few rows. This revisits docs/design.md's rule that Home 'opens as a sheet' at narrower iPad widths.
- Fix: Show Home inline whenever the width minus the sidebar leaves at least about 700 pt and review is closed; collapse it automatically when review needs the room. Where Home has to overlay, use a full-height leading drawer (sidebar width, a scrim, tap outside to close), like the desktop's mobile drawer and iPadOS overlay sidebars, instead of a form sheet. Present the review sheet with .presentationSizing(.page) or as a full-height overlay.
- Also reported as: F31-13 by visual-polish-ipad

<a id="f34-10"></a>

## F34-10: Most spec shortcuts are missing or need the prompt focused, and none appear in the menu bar or ⌘ overlay

*P2 improvement · ipad · effort L · planned in M6 · already known · found by ipad-keyboard-multitasking*

- Where: `App/OpencodeApp.swift:10`, `FeatureComposer/PromptEditor.swift:221`, `FeatureServers/ServerRootView.swift:94`, `OCDesign/WorkspaceShell.swift:42`, `FeatureFiles/FilesScreen.swift:169` (+2 more)
- Evidence: `OpencodeApp.swift:10-24: the WindowGroup has no .commands, so the iPadOS 26 menu bar contains no app menus`; `PromptEditor.swift:221  'UIKeyCommand(input: input, modifierFlags: flags, action: #selector(handleKey))' has no title or discoverabilityTitle, so ↩, ⌘↩, ⌘., ⌘', ⇧⌘D and ⌘U never appear in the ⌘ overlay, and they work only while the prompt is first responder`; `Spec table (ARCHITECTURE.md:541-553): ⌘K, ⌘⇧A, ⌘1–9 and ⌘\ don't exist. ⌘F exists only on the Files viewer's Find button, whose first-chord failure is recorded in docs/m4-audit.md:88-112` (+3 more)
- What happens: iPad with a Magic Keyboard, an agent running, and the user has just tapped a diff line, which makes the code view first responder (CodeCollection.swift:202). Now ⌘. doesn't stop, ⌘' doesn't open the picker, ⌘\ doesn't toggle Home and ⌘1 doesn't switch sessions. Holding ⌘ or opening the menu bar shows almost nothing from the app. Approvals, in the dock or the sheet, have no keyboard path at all.
- Why it matters: Keyboard users can't find the shortcuts or rely on them, which undercuts the iPad pitch.
- Fix: As planned for M6: add CommandMenu and CommandGroup entries in OpencodeApp that use focusedSceneValue to reach the active session and composer (⌘N, ⌘↩, ⌘., ⌘', ⇧⌘D, ⌘U, ⌘F, ⌘K, ⇧⌘A, ⌘1–9, ⌘\, ⇧⌘R). In the meantime, give the editor's UIKeyCommands titles and bind Esc to close the Review and Home sheets.

<a id="f19-11"></a>

## F19-11: Project tabs reorder with server activity and lack the desktop tab's avatar, close button and +; the pane toggles show no open or closed state

*P3 improvement · design-parity · effort M · found by ipad-shell*

- Where: `OCSync/ReadResync.swift:61`, `FeatureServers/ServerRootView.swift:174`, `OCDesign/WorkspaceShell.swift:85`, `OCDesign/WorkspaceShell.swift:34`, `OCDesign/WorkspaceShell.swift:39` (+1 more)
- Evidence: `crops/ipad-shell/tab-order.png: the same four tabs appear in six different orders. Within one ReadSmokeTests run, 'project' moves from last (ipad-transcript-live.png) to first (ipad-split.png).`; `ReadResync.swift:61 sorts projects by time.active, which is bumped while a project is in use; ties fall back to Dictionary order`; `.build/design-reference/timeline-light-1180x820.png: a desktop tab is the project avatar, the title and ×, followed by a + button. The native tabs use a generic folder icon (WorkspaceShell.swift:85), have no close and no +, and list every project on the server.` (+1 more)
- What happens: While an agent works in another project, that project's tab jumps to the front and shifts the tab the user was reaching for. A server with 20 projects shows 20 folder-icon tabs in a strip with hidden scroll indicators. A project chosen in Home that sits off-screen isn't scrolled into view, and two servers holding the same repository show two identical tabs. The Home and review toggles look the same whether their panes are open or closed.
- Why it matters: Tabs that move around can't be used by position or muscle memory, and the strip duplicates Home's project picker instead of behaving like the desktop's tabs.
- Fix: Keep a user-ordered list of open project tabs: opened from Home or a + button, closed with ×, reordered by dragging, and saved per server so the order is stable. Use OCProjectAvatar, as the Home rows do. Cap the tab width with middle truncation, scroll the selected tab into view, and add the server name when titles collide. Swap the toggle icons to the -full and -partial variants, or give them the pressed background the desktop uses, and animate the panes with OCMotion.panel while honouring Reduce Motion. (The ⌘-backslash shortcut for Home is already planned for M6.)
