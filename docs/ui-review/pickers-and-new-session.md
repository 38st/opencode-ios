# UI review: Pickers and new session

Part of the [UI review](README.md). 11 bugs and 5 improvements, bugs first, then by severity. Paths under `Packages/OpencodeKit/Sources` are written without that prefix.

| ID | Severity | Finding |
| --- | --- | --- |
| [F11-01](#f11-01) | P1 bug | VoiceOver never announces the chosen project, worktree, agent or variant, and their menus mark no current choice |
| [F11-04](#f11-04) | P2 bug | Model picker hides the session's current model, the server default and search matches behind the stale-model filter |
| [F11-08](#f11-08) | P2 bug | Directory browser: errors land below stale folder lists, cancelled requests show as failures, and the path field hides the current folder |
| [F26-01](#f26-01) | P2 bug | Project order flips on every project.updated, so New session defaults to the wrong project and the iPad tabs reorder |
| [F26-05](#f26-05) | P2 bug | New session never recovers after a reconnect: its errors stay and catalogs and worktrees are not reloaded |
| [F11-05](#f11-05) | P3 bug | Recent models lose their provider, so the same model from two providers appears as identical rows |
| [F11-11](#f11-11) | P3 bug | "No model results" appears while models load, after a failed load, and when no provider is connected |
| [F11-14](#f11-14) | P3 bug | Dark mode: the "Show all models" row sits on a pure black band |
| [F25-10](#f25-10) | P3 bug | Model picker prices put a hard-coded “$” before a locale-formatted number (“$0,15 input”), while other costs use .currency |
| [F28-13](#f28-13) | P3 bug | Pickers and searches say 'no results' while still loading or after a failure |
| [F11-03](#f11-03) | P3 bug | Worktree menu keeps the previous project's worktrees, so a session can start in another project's worktree; failed starts leak new worktrees |
| [F11-06](#f11-06) | P2 improvement | Project and worktree selectors read as static text and never show the actual directory |
| [F11-07](#f11-07) | P2 improvement | New session opens without focusing the prompt, so ⌘N on iPad and + on iPhone need an extra tap before typing |
| [F11-12](#f11-12) | P3 improvement | Branch picker has no Cancel button and no loading, empty or error states, and its list blanks while you type |
| [F11-09](#f11-09) | P3 improvement | Model rows are four lines tall: about six models fit on an iPhone screen, and only one at accessibility sizes |
| [F11-13](#f11-13) | P3 improvement | On iPad the model picker popover points at the middle of the composer instead of the model chip; on iPhone it is always a full-height sheet |

<a id="f11-01"></a>

## F11-01: VoiceOver never announces the chosen project, worktree, agent or variant, and their menus mark no current choice

*P1 bug · accessibility · effort S · found by pickers-new-session*

- Where: `FeatureComposer/NewSessionView.swift:104`, `FeatureComposer/NewSessionView.swift:115`, `FeatureComposer/ComposerDock.swift:194`, `FeatureComposer/ComposerDock.swift:203`, `FeatureComposer/SelectionOptions.swift:11` (+2 more)
- Evidence: `NewSessionView.swift:104 '.accessibilityLabel("Project")' and :115 '.accessibilityLabel("Worktree")' replace the visible text; neither sets accessibilityValue`; `ComposerDock.swift:194 '.accessibilityLabel("Choose agent")' and :203 '.accessibilityLabel("Choose variant")' have no value. The model chip at :198 does add '.accessibilityValue(...)'`; `SelectionOptions.swift: plain 'Button { select(...) }' rows, so no checkmark and no selected trait` (+3 more)
- What happens: With VoiceOver on, open New session (composer-new.png) and swipe through it. The selectors read "Project, button" and "Worktree, button", never "composer-worktree-project" or "Local repository". The dock chips read "Choose agent" and "Choose variant", never "Build" or "Default". Opening the agent or variant menu lists build/plan/reviewer or Default/careful with nothing marked as selected. The "New session" title is plain text, not a header.
- Why it matters: A blind user cannot find out which repository or worktree the agent will run in, or which agent and reasoning variant will be used, before sending. That risks running an agent with write access in the wrong project.
- Fix: Add `.accessibilityValue(...)` with the visible title to the project, worktree, agent and variant controls, as the model chip already does. Alternatively, move "Project" etc. into `.accessibilityHint` and keep the label. Build the four menus with `Picker(selection:)` inside the Menu so they get the system checkmark and the selected trait. Add `.accessibilityAddTraits(.isHeader)` to the "New session" title.
- Verifier's note: Wrap each menu's options in a Picker(selection:) (inline style inside the Menu) to get the native checkmark and the selected trait. Keep the generic labels and add .accessibilityValue(visible title), plus a hint such as "Where the agent runs". Also label the dock's Pending badge (see F11-10).
- Also reported as: F09-07 by composer-dock, F21-03 by a11y-voiceover

<a id="f11-04"></a>

## F11-04: Model picker hides the session's current model, the server default and search matches behind the stale-model filter

*P2 bug · functional · effort S · found by pickers-new-session*

- Where: `OCModels/ComposerPickers.swift:40`, `FeatureComposer/ModelPicker.swift:13`, `FeatureComposer/ModelPicker.swift:16`
- Evidence: `ComposerPickers.swift:40-41 '(showAll || releases[key(model)] == nil || latest.contains(key(model)) || recent.contains(key(model))) && (query.isEmpty || ...)': the effective and default models are not exempt, and the query only searches models that are already visible`; `ModelPicker.swift:13 '@State private var showAll = false': resets every time the picker opens`; `UITests/ComposerSmokeTests.swift:52-57 has to turn on "Show all models" before 'model-mock:mock-vision' exists`
- What happens: Open a session that uses Mock Vision (epoch-zero release date, like a custom or local provider's model) on a device that hasn't sent with it, for example a session started on the desktop. Tap the model chip, which reads "Mock Vision": the list shows only Mock 1 and no row has a checkmark. Search "vision" and you get "No model results". The same happens when the server's default or the session's model is more than about 6 months old or is no longer the newest in its family.
- Why it matters: Users can't see or find the model they're actually using. Custom and local model users must turn on Show all every time, and nothing hints that search skips hidden models.
- Fix: Always include the effective model and the default model in the visible set. When a query is entered, search all enabled models and show stale matches in an "Older models" section or with a badge. Remember Show all per server, or add per-model visibility like the desktop's Manage models.
- Verifier's note: When everything is hidden, show "N older models hidden · Show all" instead of "No model results".

<a id="f11-08"></a>

## F11-08: Directory browser: errors land below stale folder lists, cancelled requests show as failures, and the path field hides the current folder

*P2 bug · functional · effort M · found by pickers-new-session*

- Where: `FeatureComposer/NewSessionView.swift:173`, `FeatureComposer/NewSessionView.swift:174`, `FeatureComposer/NewSessionView.swift:179`, `FeatureComposer/NewSessionView.swift:180`, `FeatureComposer/NewSessionView.swift:193` (+1 more)
- Evidence: `NewSessionView.swift:193 'catch is CancellationError {} catch { self.error = "Could not list directory." }', but APIClient rethrows cancellation as 'APIError.cancelled' (Endpoint.swift:97-99)`; `'entries' is replaced only on success, and the error Text is the last List row (:179)`; `.build/m3b-directory-failure30/F33C3CDD-981E-4A36-8348-B26293D40C5B.png (M3b-era capture; styling code unchanged): the path field is truncated at the tail (".build..."), the background is iOS grouped grey (242,242,247) rather than an OC-2 token, the large title reads "Open project…", and rows are plain text with no folder icons` (+2 more)
- What happens: Tap folders quickly on a slow connection and "Could not list directory." flashes at the bottom. Type a nonexistent path, or browse ~/Documents on a Mac where opencode lacks Full Disk Access: the previous folder's subfolders stay listed and a generic error sits beneath them, off screen in a long listing. Several levels deep, the field still shows the start of the path rather than the folder you are in. Parent directory at "/" produces "/..", then "/../..". An empty folder shows nothing at all, with no loading or empty row.
- Why it matters: Users can't tell where they are or why a folder failed (permission, typo or network), and may open the wrong directory.
- Fix: Use WriteErrorMessage.isCancellation to ignore cancellations. On failure, clear the entries and show WriteErrorMessage.message(error) directly under the path field. Add loading and "No folders" states. Show a breadcrumb or a head-truncated path, disable Parent at "/" and standardise the path. Sort folders by display name, debounce typed paths and add folder icons. Use a plain list with the OC background and an inline title without the ellipsis, as the model picker does.

<a id="f26-01"></a>

## F26-01: Project order flips on every project.updated, so New session defaults to the wrong project and the iPad tabs reorder

*P2 bug · state · effort S · found by swiftui-state*

- Where: `OCSync/EventHandlers.swift:14`, `OCSync/ReadResync.swift:61`, `OCPersistence/PersistenceWriter.swift:92`, `FeatureComposer/NewSessionView.swift:61`, `FeatureServers/ServerRootView.swift:174` (+1 more)
- Evidence: `EventHandlers.swift:14 'projects.removeAll { $0.id == project.id }; projects.append(project)' moves the project that was just updated, which is the most active one, to the end`; `ReadResync.swift:61 resync instead sorts '($0.time.active ?? 0) > ($1.time.active ?? 0)', most recent first; the cache keeps whichever order was last saved`; `NewSessionView.swift:61 'else if let project = server.projects.first { directory = project.canonical; projectID = project.id }'` (+5 more)
- What happens: A server has two or more projects. Start a session in project A. The server emits session.created and then project.updated with A's time.active bumped (as in the recorded 2.0.32 fixture). ReadStore removes A and appends it, so the project just used becomes the last element, while resync and the cache keep a different order. Then tap New session (the iPhone sheet, or the iPad main pane after leaving a session). NewSessionView picks `server.projects.first`, which is some other project, so the composer opens on the wrong directory. The same array drives the iPad project tab strip and Home's project menu, which reorder whenever an event or a resync arrives. The iPad smoke run captured three different tab orders within one minute.
- Why it matters: Users start sessions in the wrong project or worktree, and the per-directory draft they expect is not shown. Tab targets also move between taps.
- Fix: Use one ordering rule. On project.updated, replace the element in place and re-sort by time.active descending, as resync does, or sort where the list is read. Choose New session's default explicitly: the selected project, the last-used directory, or the highest time.active. Give the iPad tab strip a stable order that does not depend on activity.
- Verifier's note: Replace the project in place and keep one sort rule, or sort in a single accessor. Give the tab strip its own stable order. Make New session default to the selected project tab or the last-used directory: today it can also open a project other than the one holding the user's per-directory draft, so that draft looks lost.
- Also reported as: G02-M1 by verifier G02

<a id="f26-05"></a>

## F26-05: New session never recovers after a reconnect: its errors stay and catalogs and worktrees are not reloaded

*P2 bug · state · effort M · found by swiftui-state*

- Where: `FeatureComposer/NewSessionView.swift:54`, `FeatureComposer/NewSessionView.swift:68`, `FeatureComposer/NewSessionView.swift:73`, `OCSync/ReadResync.swift:69`, `OCSync/CatalogSync.swift:59`
- Evidence: `NewSessionView.swift:54-66 '.task { guard directory.isEmpty ... }' sets 'Could not open a project.' on failure and runs once per view`; `NewSessionView.swift:68-75 '.task(id: draftDirectory)' sets 'choicesError = 'Could not load project choices.'' and reruns only when the directory changes`; `ReadResync.swift:69-70 invalidates every catalog but refreshes only the directories of 'openSessions'; CatalogSync.swift:59-66 does the same for catalog events` (+1 more)
- What happens: Open the app while the computer is asleep or off the network. On iPad, NewSessionView is the default main pane. The catalog load fails and 'Could not load project choices.' appears; with no cached projects, 'Loading projects…' spins and 'Could not open a project.' appears. When the server reconnects, neither task runs again. The error stays, and server slash commands, skills, references, the branch label and existing worktrees stay empty (on a first visit the model list does too) until the user changes project or leaves and comes back. Separately, opening a directory that has no project keeps the previous project's worktrees in the Worktree menu, and picking one moves the draft into another project's worktree.
- Why it matters: The default iPad screen looks broken after a common offline start, and stale choices can send work to the wrong place.
- Fix: Re-run directory resolution and the catalog and worktree loads when the server reconnects: include the connection state or `lastStatusSync` in the task ids, or add the new-session directory to resync. Clear the errors on success, and reset `worktrees` whenever `projectID` changes or is empty.
- Verifier's note: Use ReadStore.lastStatusSync, which confirmStatus() sets on every resync, in the task IDs so both loads rerun after a reconnect. Clear both errors on success, and set worktrees = [] before loading or when projectID is empty.

<a id="f11-05"></a>

## F11-05: Recent models lose their provider, so the same model from two providers appears as identical rows

*P3 bug · ux-flow · effort S · found by pickers-new-session*

- Where: `FeatureComposer/ModelPicker.swift:29`, `FeatureComposer/ModelPicker.swift:33`, `OCModels/ComposerPickers.swift:50`, `FeatureComposer/ComposerDock.swift:198`
- Evidence: `Each row shows only 'value.name' and 'Text(value.id)'. The provider appears only as the section title, and the "Recent" section (ComposerPickers.swift:50) mixes providers`; `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.model-picker-light-393-default.png: the Recent row "Mock 1 / mock-1" is identical to the provider-group row, checkmark included`; `docs/design.md says provider names remain in the model picker, but the Recent group drops them`
- What happens: A user who has sent with Claude Sonnet 4.5 through Anthropic and through GitHub Copilot or opencode Zen opens the picker. Recent shows two "Claude Sonnet 4.5" rows whose ids differ at most by punctuation. The dock chip and its VoiceOver value also say only "Claude Sonnet 4.5".
- Why it matters: Picking the wrong row bills a different account, with different limits, and nothing on screen tells the rows apart.
- Fix: In Recent rows, and wherever a display name is shared by more than one enabled provider, show the provider in the subtitle, e.g. "Anthropic · claude-sonnet-4-5". Include the provider in the chip's accessibilityValue, and in the chip text when the name is ambiguous. Provider logos stay omitted, as docs/design.md decides.

<a id="f11-11"></a>

## F11-11: "No model results" appears while models load, after a failed load, and when no provider is connected

*P3 bug · state · effort S · found by pickers-new-session*

- Where: `FeatureComposer/ModelPicker.swift:16`, `FeatureComposer/ModelPicker.swift:22`, `OCSync/Revalidating.swift:8`
- Evidence: `'ComposerPickers.groups(model.catalog.models.value ?? [], ...)' followed by 'if groups.isEmpty { Text("No model results") }'`; `'Revalidating.isLoading' exists but the picker never reads it`
- What happens: In New session, pick a project you haven't opened before and tap "Choose model" before its catalogs arrive, or do it offline: the picker shows only the toggle and "No model results". A fresh opencode server with no provider credentials shows the same message, with no guidance.
- Why it matters: Misleading: users conclude that models are missing or that search is broken.
- Fix: Show a spinner while `isLoading && value == nil`. On failure, show a message and a Retry that calls refreshCatalogs. When no providers are connected, say so: "No models available. Connect a provider in opencode on your computer." Keep "No models match …" for real queries, with a Show all hint.

<a id="f11-14"></a>

## F11-14: Dark mode: the "Show all models" row sits on a pure black band

*P3 bug · visual · effort S · found by pickers-new-session*

- Where: `FeatureComposer/ModelPicker.swift:21`, `FeatureComposer/ModelPicker.swift:22`, `FeatureComposer/ModelPicker.swift:43`
- Evidence: `crops/pickers-new-session/model-picker-dark-toggle-row.png`; `Pixel samples from capture-_-name-fixedHeight.model-picker-dark-393-default.png and -dark-820-default.png: the toggle row is RGB (0,0,0) from x≈45 to 1077 px, while the list and model rows are (22,22,22)`; `Model rows set '.listRowBackground(OCColor.background)' (:43); the Toggle (:21) and the "No model results" row (:22) don't, so they keep the system row background`
- What happens: Dark appearance, iPhone or iPad: open Choose model and a black stripe runs behind "Show all models" with inset edges, unlike the rest of the sheet.
- Why it matters: A visible rendering defect at the top of a frequently used sheet.
- Fix: Add `.listRowBackground(OCColor.background)` to the Toggle and the empty-state row, or apply it to all of the List's content.
- Also reported as: F37-12 by sweep-composer-snapshots

<a id="f25-10"></a>

## F25-10: Model picker prices put a hard-coded “$” before a locale-formatted number (“$0,15 input”), while other costs use .currency

*P3 bug · localization · effort S · found by l10n-text*

- Where: `FeatureComposer/ModelPicker.swift:39`, `FeatureInbox/HomeSessionRow.swift:61`, `FeatureTranscript/SessionScreen.swift:180`
- Evidence: `ModelPicker.swift:39 Text("$\(cost.input.formatted()) input · $\(cost.output.formatted()) output / 1M tokens")`; `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.model-picker-light-393-default.png (“$1 input · $2 output / 1M tokens”)`; `HomeSessionRow.swift:61 and SessionScreen.swift:180 use .formatted(.currency(code: "USD"))`
- What happens: Region Germany: the picker shows “$0,15 input · $0,6 output / 1M tokens”, while Home rows and the session header show “0,00 $”. In a French region the picker shows “$0,15” and the rest of the app shows “0,00 $US”.
- Why it matters: Currency is presented in two styles within the app, and the “$” placement is wrong for most locales. The sentence and the “1M tokens” abbreviation cannot be localized.
- Fix: Format with cost.input.formatted(.currency(code: "USD").precision(.fractionLength(0...3))) inside one key (“%1$@ input · %2$@ output per 1M tokens”), using a CostFormat helper shared with Home and the header.

<a id="f28-13"></a>

## F28-13: Pickers and searches say 'no results' while still loading or after a failure

*P3 bug · state · effort S · found by states-coverage*

- Where: `FeatureComposer/ModelPicker.swift:15-22`, `OCSync/Revalidating.swift:8`, `FeatureComposer/ComposerDock.swift:231`, `FeatureComposer/ComposerDock.swift:309-327`, `FeatureFiles/FilesScreen.swift:100-102` (+3 more)
- Evidence: `ModelPicker: 'ComposerPickers.groups(model.catalog.models.value ?? [], ...)' and then 'if groups.isEmpty { Text("No model results") }'; 'Revalidating.isLoading' is never read`; `@ trigger: suggestions are first built with 'files: []', then a 120 ms sleep and 'findFiles'; meanwhile 'if suggestions.isEmpty { Text("No matching items") }'`; `FilesModel.search failure sets 'self?.error = "Could not search files."', which is rendered only inside 'viewer' (only when a file is open)` (+1 more)
- What happens: Opening the model picker for a project whose catalogue hasn't loaded yet (or failed to load) shows 'No model results'. Typing '@Exa' shows 'No matching items' for the debounce plus the round trip, and keeps showing it if the search fails. The Files filter shows 'No results found' while searching and after a failure, because the failure text goes to the hidden viewer pane. A branch list that failed to load is just empty.
- Why it matters: A false 'nothing exists' answer leads users to choose the wrong model or file, or to give up.
- Fix: Use separate loading rows ('Loading models…', 'Searching…'), empty rows and error rows ('Couldn't load models · Retry'), driven by Revalidating.isLoading and the in-flight search tasks. Show Files search errors in the browser pane.

<a id="f11-03"></a>

## F11-03: Worktree menu keeps the previous project's worktrees, so a session can start in another project's worktree; failed starts leak new worktrees

*P3 bug · state · effort M · found by pickers-new-session*

- Where: `FeatureComposer/NewSessionView.swift:73`, `FeatureComposer/NewSessionView.swift:156`
- Evidence: `'@State private var worktrees' is only assigned at :73, after 'try await server.readPath.refreshCatalogs(draftDirectory)'. That call makes four parallel requests, then MCP, then four more catalog requests one at a time (CatalogSync.swift:16-30)`; `select() at :135 changes directory, projectID and worktree but never clears 'worktrees'; if any catalog request fails, :74 shows "Could not load project choices." and the old list stays`; `start() at :150-157: once createWorktree succeeds, a resolveDirectory failure throws while 'worktree' is still "new" and the list is never refreshed`
- What happens: Pick project A, which has worktrees feature-1 and feature-2, then switch to project B over a slow tunnel, or while one of B's catalog requests fails. The worktree menu still offers feature-1 and feature-2. Choosing one points draftDirectory at A's worktree while the chip still says B, and Send creates the session in A's worktree. Separately: choose New worktree and Send; if resolveDirectory fails after the worktree was created, pressing Send again creates a second worktree and branch.
- Why it matters: The agent can edit a different repository from the one on screen, and retries leave orphaned worktrees and branches on the user's machine.
- Fix: Clear `worktrees` and reset `worktree` to "" whenever projectID changes. Load worktrees in their own task keyed by projectID instead of behind refreshCatalogs, and disable the menu while they load. Once createWorktree succeeds, set `worktree` to the created directory and add it to the list before resolving, so a retry reuses it.
- Verifier's note: Clear worktrees and disable the worktree menu until worktrees(projectID:) has loaded for the current projectID, in a task of its own rather than behind refreshCatalogs.

<a id="f11-06"></a>

## F11-06: Project and worktree selectors read as static text and never show the actual directory

*P2 improvement · ux-flow · effort M · found by pickers-new-session*

- Where: `FeatureComposer/NewSessionView.swift:103`, `FeatureComposer/NewSessionView.swift:111`, `FeatureComposer/NewSessionView.swift:113`, `FeatureComposer/NewSessionView.swift:116`, `FeatureComposer/NewSessionView.swift:97`
- Evidence: `crops/pickers-new-session/iphone-selectors.png vs iphone-chips.png: the selectors are full-contrast text with no chevron, while the dock chips (ComposerChrome.swift:26) and Home's "All projects" picker (HomeView.swift:134) have chevrons`; `.build/design-reference/composer-new-session-light-1440x900.png: the desktop shows a muted "New project ⌄" control`; `'OCLabel(project?.name ?? URL(fileURLWithPath: directory).lastPathComponent, icon: "folder")'; the menu lists 'value.branch ?? lastPathComponent' but the chip shows 'URL(fileURLWithPath: worktree).lastPathComponent'` (+1 more)
- What happens: A first-time iPhone user sees the title, the composer and two plain labels under it, with nothing saying they are tappable or that they decide where the agent runs. Opening a subfolder such as mono/packages/app through Open project… shows the project's name when the project has one, hiding the subfolder. An existing worktree shows its folder name in the chip although the menu listed its branch. A folder without Git reads "Local repository" next to a "No Git" badge. Two projects named "app" can't be told apart in the menu.
- Why it matters: Users don't realise they can change the project or worktree, or they misread where the session will run.
- Fix: Render both selectors as chevron chips with muted text, like OCComposerChoice. Give the row a "Start in" label, or move it above the composer into the empty top third of the iPhone sheet (this revisits the centred-below layout in docs/design.md). Show "project › subdir" when the directory differs from the project root. Use the branch name in both the worktree menu and its chip. Say "This folder" when there is no Git. Add the parent path as a subtitle in the project menu. Scale the glyphs with @ScaledMetric.
- Raised from P3 to P2, the severity of F37-02, which describes the same problem.
- Also reported as: F37-02 by sweep-composer-snapshots

<a id="f11-07"></a>

## F11-07: New session opens without focusing the prompt, so ⌘N on iPad and + on iPhone need an extra tap before typing

*P2 improvement · interaction · effort S · found by pickers-new-session*

- Where: `FeatureComposer/NewSessionView.swift:39`, `OCSync/ComposerModel.swift:216`, `FeatureComposer/PromptEditor.swift:211`, `FeatureServers/ServerRootView.swift:94`
- Evidence: `iphone/composer-new.png: the sheet is open with no caret and no keyboard`; `requestFocus() is only called after a send (ComposerModel.swift:216) or after a restore or mention; nothing in NewSessionView or beginSession requests it`; `UITests/ComposerSmokeTests.swift:33 'type(_:)' taps the editor first` (+1 more)
- What happens: On iPad with a Magic Keyboard, press ⌘N: New session appears and typing does nothing until you touch the prompt. On iPhone, tap +: the sheet appears with the keyboard down and you must tap the box.
- Why it matters: Adds a step to the most common flow and breaks keyboard-only use on iPad.
- Fix: Once draftDirectory resolves, and again after `.id(draftDirectory)` recreates the dock on a project change, call `server.readPath.composer(directory: draftDirectory).requestFocus()`. At minimum do this when the view is opened by ⌘N, + or /new.
- Also reported as: F34-07 by ipad-keyboard-multitasking

<a id="f11-12"></a>

## F11-12: Branch picker has no Cancel button and no loading, empty or error states, and its list blanks while you type

*P3 improvement · interaction · effort S · found by pickers-new-session*

- Where: `FeatureComposer/NewSessionView.swift:118`, `FeatureComposer/NewSessionView.swift:204`, `FeatureComposer/NewSessionView.swift:208`
- Evidence: `'NavigationStack { List(branches, ...) ... .navigationTitle("From branch").searchable(...) }': no toolbar, so no Cancel`; `'do { branches = try await store.branches(...) } catch { branches = [] }': a superseded search throws APIError.cancelled and empties the list; a real failure looks identical to having no branches`; `'Button("from \(branch ?? currentBranch ?? "default")")': a lowercase fragment with a ghost style and no chevron`
- What happens: Choose New worktree and tap "from main". The sheet lists up to 50 branches, has no Cancel (swipe is the only way out) and doesn't mark the current base. The list blanks between keystrokes while searching, and a failed request shows an empty list.
- Why it matters: Choosing a base branch is fiddly, with no feedback, and failures go unnoticed.
- Fix: Add a Cancel button. Mark the current base with a checkmark and offer "Default branch". Add loading, empty and error states. Ignore cancellation errors and debounce the search. Label the trigger "Base branch: main", with a chevron.

<a id="f11-09"></a>

## F11-09: Model rows are four lines tall: about six models fit on an iPhone screen, and only one at accessibility sizes

*P3 improvement · layout · effort M · found by pickers-new-session*

- Where: `FeatureComposer/ModelPicker.swift:27`, `FeatureComposer/ModelPicker.swift:33`, `FeatureComposer/ModelPicker.swift:39`, `OCModels/ComposerPickers.swift:53`
- Evidence: `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.model-picker-dark-393-default.png: each row has a name line, an id line, a badge line and a price line, about 100 pt in total`; `capture-_-name-fixedHeight.model-picker-light-393-accessibility5.png: a single row runs past the bottom of the screen`; `.build/design-reference/composer-model-picker-light-1440x900.png: one-line rows with the name and a Latest badge` (+1 more)
- What happens: A user with Anthropic, OpenAI and OpenRouter connected opens the picker on iPhone and sees about six models per screen; with Larger Text, one per screen.
- Why it matters: Scanning for a model takes far more scrolling than on the desktop, and the badges and prices compete with the names.
- Fix: Put the name and key badges on one line and add a single muted second line ("Provider · $3 / $15 per 1M"). Drop the id line unless it disambiguates. Hide prices when both are 0 and format them with `.currency(code: "USD")`. This revisits the iOS-only badges and prices in docs/design.md.

<a id="f11-13"></a>

## F11-13: On iPad the model picker popover points at the middle of the composer instead of the model chip; on iPhone it is always a full-height sheet

*P3 improvement · ipad · effort S · found by pickers-new-session*

- Where: `FeatureComposer/ComposerDock.swift:72`, `FeatureComposer/ModelPicker.swift:49`, `FeatureComposer/ModelPicker.swift:51`
- Evidence: `ComposerDock.swift:72 '.popover(isPresented: $showModels) { ModelPicker(...).ocSheet().presentationCompactAdaptation(.sheet) }' is attached to the dock's root VStack, not to the model chip button at :196`; `No '.presentationDetents', and '.searchable' has no 'searchFocused'`; `capture-_-name-fixedHeight.model-picker-light-393-default.png: two models in a tall sheet that is mostly empty` (+1 more)
- What happens: In an iPad session, tap "Mock 1 ⌄" at the left of an 800-pt dock: the popover's arrow points at the centre of the dock, away from the tapped chip. After ⌘', typing doesn't filter until the search field is tapped. On iPhone with only a few models, the full-height sheet hides the composer.
- Why it matters: Weak spatial link between control and popover, plus extra taps for keyboard users.
- Fix: Anchor the popover to the model chip; keep the dock as the anchor only for ⌘' and /model. Add `.presentationDetents([.medium, .large])` on iPhone. Focus the search field on open with `.searchFocused`, at least when opened from the keyboard.
