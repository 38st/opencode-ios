# UI review: Home

Part of the [UI review](README.md). 17 bugs and 3 improvements, bugs first, then by severity. Paths under `Packages/OpencodeKit/Sources` are written without that prefix.

| ID | Severity | Finding |
| --- | --- | --- |
| [F28-01](#f28-01) | P1 bug | Connection loss is invisible outside Settings: Home and the session screen keep looking live while offline |
| [F03-01](#f03-01) | P2 bug | New session ignores the project picked in Home or in the iPad project tabs |
| [F03-02](#f03-02) | P2 bug | Deep links and New session silently change Home's server filter; removing the selected server leaves a stale filter labelled 'All servers' |
| [F03-04](#f03-04) | P2 bug | Pinning does not keep a session at the top; it stays in its original day group |
| [F03-05](#f03-05) | P2 bug | 'Hidden sessions' is an invisible mode that replaces all of Home, and hiding a session drops its requests from Needs you |
| [F03-07](#f03-07) | P2 bug | The iPad Home sidebar never highlights the open session |
| [F03-08](#f03-08) | P2 bug | In the iPad landscape sidebar, the server switcher always truncates to 'All s…' or '127….', and no menu or tab shows the current choice |
| [F03-14](#f03-14) | P2 bug | Empty and no-result states use the unscoped list, so a project or server with no sessions shows a blank page |
| [F28-09](#f28-09) | P2 bug | Home errors render below the fold, and 'Pull to try again' clears the error without retrying |
| [F33-03](#f33-03) | P2 bug | Home and the timeline don't say what the agent is doing or waiting for: blocked runs read '1 running' and 'Working…' |
| [F03-09](#f03-09) | P2 bug | Home rows read poorly with VoiceOver and large text: full paths spoken, status glyph silent, mid-word breaks, glyphs that don't scale |
| [F03-12](#f03-12) | P2 bug | Pin, Hide and Mark read are swipe-only, and their dark-mode labels have 1.9–2.7:1 contrast |
| [F26-11](#f26-11) | P2 bug | Home rebuilds every session summary 4 + (number of day sections) times per render |
| [G02-M2](#g02-m2) | P3 bug | Home's 'Load older sessions' shows on every scope even when nothing older exists |
| [F03-06](#f03-06) | P3 bug | Cancelled requests are shown as errors, and each row action cancels the previous one |
| [F40-13](#f40-13) | P3 bug | iPad Home forgets search, Hidden sessions and scroll every time it is hidden, and never marks the open session |
| [G02-M3](#g02-m3) | P3 bug | Mark read cannot clear a Needs you row whose failure belongs to a subagent |
| [F03-10](#f03-10) | P2 improvement | Row subtitles spend their line on 'Server · /absolute/path' and never say what is blocked or running |
| [F24-13](#f24-13) | P3 improvement | On iPhone, Home puts New session and Settings in the top-right corner |
| [F25-11](#f25-11) | P3 improvement | Home day headers hard-code “Today”/“Yesterday”, always show the year, and don’t update at midnight |

<a id="f28-01"></a>

## F28-01: Connection loss is invisible outside Settings: Home and the session screen keep looking live while offline

*P1 bug · state · effort M · found by states-coverage*

- Where: `FeatureInbox/HomeSessionRow.swift:15-22`, `OCSync/ServerStore.swift:144-151`, `OCSync/WriteStore.swift:99-109`, `OCSync/ReadResync.swift:34-56`, `FeatureTranscript/SessionTimeline.swift:35` (+7 more)
- Evidence: `crops/states-coverage/home-rows-syncing-icons.png (this is how every idle row looks when its server is not connected: a bare grey refresh glyph with no text)`; `Packages/OpencodeKit/Tests/FeatureServersTests/__Snapshots__/ServerRowTests/allStatesAtLargestDynamicType.retrying-light-402.png (the honest 'Retrying in 12s · Attempt 3 · reason' status exists, but only in Settings)`; `HomeSessionRow: 'if case .connected = item.server.state { return .idle }; return .syncing' (VoiceOver reads 'Syncing')` (+3 more)
- What happens: iPhone; the laptop running opencode is asleep or the tunnel is down, so the server is in `.waiting` (Retrying in 12s). Home: every idle row shows the same small grey refresh glyph with no label, and sessions that were running stay in 'Running' with the breathing green dot. Session screen: the cached transcript, the 'Working…' row and the Stop button stay up indefinitely. A prompt sent now shows 'Sending' on its bubble and in the queue panel, with no 'waiting for connection'. The `.incompatible`, `.serviceStarting` and `.suspended` states are just as invisible. Reconnect and the retry countdown are only in Settings → server.
- Why it matters: SPEC makes an 'honest connection state instead of a stream that only looks alive' a P0 and a key selling point. Today users cannot tell live data from saved data. They wait on agents that may already have finished or be blocked, and they assume prompts are being delivered.
- Fix: Add a shared connection banner built on OCBanner and ServerStatus, at the top of Home (per disconnected server) and in the session header. Example text: 'Offline · showing saved messages · Retrying in 12s · Reconnect now'; 'Needs re-pairing · Pair again'; 'Update opencode'. While a server is not connected: show its running indicators as last known (no breathing, label 'Last seen running'); replace the 'Working…' row with 'Waiting for server…'; label pending prompts 'Waiting for connection'. Add status dots to the server switcher. Post VoiceOver announcements when the connection state changes.
- Verifier's note: The banner does not need an unauthorized case, because that state already auto-presents re-pair. It should also cover a server that is connected but whose last resync failed (see the first missed item), otherwise 'Connected' can still hide stale running and permission state.
- Also reported as: F02-01 by servers-management, F03-03 by home-inbox, F33-02 by ux-flows-ia

<a id="f03-01"></a>

## F03-01: New session ignores the project picked in Home or in the iPad project tabs

*P2 bug · functional · effort S · found by home-inbox*

- Where: `FeatureServers/ServerRootView.swift:156-161`, `FeatureServers/ServerRootView.swift:151-155`, `FeatureComposer/NewSessionView.swift:54-61`
- Evidence: `ipad/ipad-session-list.png: the Home project picker reads 'composer-worktree-project' while the New session pane beside it targets 'project'`; `ServerRootView.swift:158 'NewSessionView(server: server, directory: recoveredDirectory)': selectedProject is never passed`; `NewSessionView.swift:55-61 'guard directory.isEmpty ... else if let project = server.projects.first { directory = project.canonical; projectID = project.id }'`
- What happens: iPad landscape: choose 'composer-worktree-project' in Home's project picker, or tap its project tab (the tabs bind the same selectedProject). The New session pane next to it still targets 'project' and never updates: NewSessionView keeps its identity (.id(server.id)) and seeds its directory only once, from server.projects.first (the most recently active project). On iPhone, pick a project and tap '+': the sheet opens on server.projects.first, not the picked project.
- Why it matters: The first prompt starts the agent in a different repository unless the user notices the small project chip under the composer. This breaks SPEC §4.1, which promises 'start a session in a chosen project'.
- Fix: Pass Home's selection to new sessions. Derive the target server from selectedProject's server prefix, and give NewSessionView that project's ID and canonical directory through a new initialProject parameter. Don't reuse directory:, which also sets 'Failed to create session. Your prompt has been restored.' On iPad, key the pane's identity on server plus project, or re-seed it when selectedProject changes and the draft is empty.
- Verifier's note: Agree: add an initialProject parameter instead of reusing directory:, because the initialDirectory path sets the 'Failed to create session' error. projects.first is also unstable (see the missed project-order issue), which makes today's default project unpredictable too.
- Also reported as: F11-02 by pickers-new-session, F32-05 by design-parity, F33-05 by ux-flows-ia

<a id="f03-02"></a>

## F03-02: Deep links and New session silently change Home's server filter; removing the selected server leaves a stale filter labelled 'All servers'

*P2 bug · state · effort S · found by home-inbox*

- Where: `FeatureServers/ServerRootView.swift:147`, `FeatureServers/ServerRootView.swift:153`, `FeatureInbox/HomeView.swift:27`, `FeatureInbox/HomeView.swift:52`, `FeatureInbox/HomeView.swift:109`
- Evidence: `ipad/ipad-transcript-live.png shows the switcher as 'All s…'. After ReadSmokeTests opens opencodeios://server/<id>/session/<id> links, ipad-transcript-tools.png and ipad-split.png show '127….'`; `ipad/ipad-composer-new.png shows 'Co…' after ComposerSmokeTests used links and ⌘N. No UI test taps serverSwitcher; ServerSmokeTests.swift:21 only checks that it exists.`; `routeLink: 'selectedServer = id; selectedProject = nil'` (+2 more)
- What happens: Two servers, Home on 'All servers' with a project picked. Open a session from a link (with M5b this will be every notification tap), or press +/⌘N while a session on server A is open. Home now shows only server A, the project filter is cleared, and B's day groups vanish. Second case: select server A, then remove A in Settings. The switcher text falls back to 'All servers', but selectedServer still holds A's ID. The project menu is empty, no day groups render, only the cross-server Needs you and Running rows remain, and the empty-state text is suppressed. Likewise, if the selected project disappears, the picker shows 'All projects' but the list still filters by it.
- Why it matters: Sessions seem to disappear without any user action. To recover, the user must choose 'All servers', which the label says is already selected.
- Fix: Track the new-session and deep-link target server separately. The m3b rule 'New session retains the active session's server' can read the open session directly, so only the switcher writes Home's filter. Reset selectedServer and selectedProject when their server or project no longer exists, using onChange of the registry.servers IDs and server.projects.
- Also reported as: F19-08 by ipad-shell, F26-14 by swiftui-state, F40-11 by navigation-state-restoration, G01-M1 by verifier G01

<a id="f03-04"></a>

## F03-04: Pinning does not keep a session at the top; it stays in its original day group

*P2 bug · functional · effort S · found by home-inbox*

- Where: `FeatureInbox/HomeView.swift:44`, `FeatureInbox/HomeView.swift:57`, `FeatureInbox/HomeView.swift:70`, `FeatureInbox/HomeView.swift:162`, `FeatureInbox/HomeSessionRow.swift:56`
- Evidence: `The sort 'if a.meta.pinned != b.meta.pinned { return a.meta.pinned }' runs first, then 'ForEach(days) { recent.filter { Calendar.current.isDate(date($0), inSameDayAs: day) } }' regroups everything by day`; `research/08-feature-matrix.md B9: the TUI has a 'Pinned' group and Cursor has a 'Pinned' section`; `No Pinned section exists anywhere in Sources (grep for pinned finds only the sort, the badge and the swipe action)`
- What happens: Swipe right on a session last active nine days ago and tap Pin. It gets a 'Pinned' badge but stays under 'Oct 13, 2026', below all newer days; pinning only moves it to the top of that one day.
- Why it matters: Pin is one of the three specified swipe actions, yet it does not make a session easier to reach.
- Fix: Add a 'Pinned' section after Needs you and Running. It holds pinned sessions that are not in triage, in activity order. Exclude them from the day groups, and drop the redundant badge in that section.
- Also reported as: F33-10 by ux-flows-ia

<a id="f03-05"></a>

## F03-05: 'Hidden sessions' is an invisible mode that replaces all of Home, and hiding a session drops its requests from Needs you

*P2 bug · state · effort S · found by home-inbox*

- Where: `FeatureInbox/HomeView.swift:37`, `FeatureInbox/HomeView.swift:104`, `FeatureInbox/HomeView.swift:63`, `FeatureInbox/HomeView.swift:66`, `FeatureInbox/HomeSessionRow.swift:55`
- Evidence: `'guard showHidden == item.meta.hidden else { continue }' sits inside 'all', which feeds Needs you, Running, the day groups and the empty state`; `'Toggle("Hidden sessions", isOn: $showHidden)' sits in the server switcher menu, and nothing else on screen reflects it`; `Rows have no Hidden badge; the only badges are Pinned, running and Unread`
- What happens: Turn on 'Hidden sessions' in the server menu. The header, section titles and rows look the same as before, but only hidden sessions are listed; with none hidden, the screen says 'Your sessions will appear here'. In normal mode, hide a session and let its agent ask a permission or a question: the request never appears under Needs you, so the agent waits until the user happens to open that session.
- Why it matters: Users conclude their sessions are gone, and blocked work can drop out of triage.
- Fix: Make the mode visible: a banner or chip 'Showing hidden sessions · Done', an empty state 'No hidden sessions', and a Hidden badge on rows. Keep hidden sessions that need the user under Needs you, or show a row such as '1 hidden session needs you'. Move the toggle out of the server menu, for example to a 'Hidden (N)' row at the end of the list.
- Also reported as: F33-09 by ux-flows-ia

<a id="f03-07"></a>

## F03-07: The iPad Home sidebar never highlights the open session

*P2 bug · ipad · effort S · found by home-inbox*

- Where: `FeatureInbox/HomeView.swift:22`, `FeatureInbox/HomeView.swift:155`, `FeatureInbox/HomeSessionRow.swift:32`, `FeatureServers/ServerRootView.swift:46`, `FeatureServers/ServerRootView.swift:181`
- Evidence: `ipad/ipad-transcript-live.png: 'Live transcript' is open in the main column, and its sidebar row has the same white (255,255,255) background as the rows around it (pixel-sampled)`; `ipad/ipad-split.png: two identical 'Fixture conversation' rows, and neither is marked as the parent of the open subagent`; `HomeView takes no selection input; sessionPath.last?.id is passed only to OCWorkspaceShell`
- What happens: iPad landscape: open any session from the sidebar, then scroll the sidebar or open a subagent. Nothing shows which row is on screen.
- Why it matters: Basic sidebar orientation is missing; the desktop app and iPadOS sidebars both highlight the current item. VoiceOver also gets no selected trait.
- Fix: Pass the open SessionRef (its root, for subagents) into HomeView. Give that row a selected background (OCColor.pressed, as OCListRow does) and .accessibilityAddTraits(.isSelected), and scroll it into view when the selection changes.
- Also reported as: F19-09 by ipad-shell, F31-01 by visual-polish-ipad, F34-08 by ipad-keyboard-multitasking

<a id="f03-08"></a>

## F03-08: In the iPad landscape sidebar, the server switcher always truncates to 'All s…' or '127….', and no menu or tab shows the current choice

*P2 bug · layout · effort S · found by home-inbox*

- Where: `FeatureInbox/HomeView.swift:100-112`, `OCDesign/WorkspaceShell.swift:87-89`, `OCDesign/Resources/Colors.xcassets/oc2-layer1.colorset/Contents.json`
- Evidence: `ipad/ipad-inbox.png ('All s…'), ipad-split.png ('127….'), ipad-composer-new.png ('Co…')`; `Packages/OpencodeKit/Tests/FeatureServersTests/__Snapshots__/DesignScreenTests/screens.workspace-home-light-1180x820.png and .build/design-compare/ipad-home-sidebar-light.png show the same truncation`; `The server and project menu items are plain Buttons with no checkmark, and '.accessibilityLabel("Switch server")' has no value` (+1 more)
- What happens: In landscape, Home is the fixed 256-pt sidebar. The grid icon, 'Home', the server menu and two 44-pt buttons don't fit, so the server name is cut to 3–5 characters. Opening the menu doesn't help: neither the server items nor the project items carry a checkmark. In light mode the selected project tab looks the same as the others, and VoiceOver reads only 'Switch server'.
- Why it matters: On iPad the user can't tell which server Home is filtered to, which also makes the silent filter changes in the deep-link finding hard to notice or undo.
- Fix: In narrow containers, move the server choice out of the header. Either fold it into the project picker, which is already sectioned by server ('All servers', then 'All projects' and the projects for each server), or show it as a full-width row under the project picker. Use a Picker or checkmarked items in both menus, and add .accessibilityValue with the current name. Give the selected tab a colour that differs from backgroundDeep in light mode, and mark no tab while Home shows 'All projects'.
- Also reported as: F19-07 by ipad-shell, F25-03 by l10n-text, F31-06 by visual-polish-ipad, F32-12 by design-parity, F38-06 by sweep-approval-server-snapshots

<a id="f03-14"></a>

## F03-14: Empty and no-result states use the unscoped list, so a project or server with no sessions shows a blank page

*P2 bug · state · effort S · found by home-inbox*

- Where: `FeatureInbox/HomeView.swift:65`, `FeatureInbox/HomeView.swift:139`
- Evidence: `'if all.isEmpty { Text(search.isEmpty ? "Your sessions will appear here" : "No matching sessions") }': 'all' ignores selectedServer and selectedProject, while the day groups use 'recent'`; `.build/design-reference/sidebar-light-393x852.png: the reference changes the placeholder to 'Search sessions in project' when a project is selected; Home always says 'Search sessions'`; `The search TextField has no clear button`
- What happens: Pick a project or server that has no sessions, or search for a word that matches only other projects. Home shows the filters and then nothing: no message and no 'New session in \<project>' action. On first launch after pairing, while the first sync runs, Home shows 'Your sessions will appear here' in 13-pt muted text, with no loading indicator or action. Clearing a search means deleting it character by character.
- Why it matters: Blank screens look like failures, and new users get no obvious next step.
- Fix: Compute empty states from the scoped lists. Show 'No sessions in \<project>' with a New session button, 'Loading sessions…' until the first resync completes, and 'No matching sessions in \<project>' for searches. Add a clear button and a placeholder that names the scope.
- Raised from P3 to P2, the severity of F28-08, which describes the same problem.
- Also reported as: F28-08 by states-coverage

<a id="f28-09"></a>

## F28-09: Home errors render below the fold, and 'Pull to try again' clears the error without retrying

*P2 bug · state · effort S · found by states-coverage*

- Where: `FeatureInbox/HomeView.swift:73-80`, `FeatureInbox/HomeView.swift:81-92`, `FeatureInbox/HomeView.swift:167-177`, `OCSync/ServerRegistry.swift:261-263`
- Evidence: `iphone/home.png (the list runs past the bottom of the screen, which is where the error row would be)`; `'if let error { Text(error)... }' is the last row of the List, after the day sections and 'Load older sessions'`; `'.refreshable { error = nil; await registry.refresh() }': refresh() only force-reconnects each server and returns at once; it does not re-run the scoped '.task'` (+1 more)
- What happens: With more than a screenful of sessions, 'Could not refresh sessions. Pull to try again.' and swipe failures ('Could not save the change. Try again.') are appended under the last session, so they are never seen. If the user does pull, the message is cleared and every server's event stream is torn down and reconnected, but the failed search or project listing is not retried. With 'All servers' selected, one unreachable server (which can take up to about 90 s to fail) blocks search results and 'Load older sessions' for every server after it.
- Why it matters: Failures are invisible, and the advertised recovery doesn't recover. Multi-server users lose search whenever one machine is off.
- Fix: Show Home errors in a banner pinned at the top, with a Retry that re-runs the failed operation. Make pull-to-refresh await the scope listing (as well as the resync). List servers concurrently with a TaskGroup and report failures per server inline.

<a id="f33-03"></a>

## F33-03: Home and the timeline don't say what the agent is doing or waiting for: blocked runs read '1 running' and 'Working…'

*P2 bug · ux-flow · effort M · found by ux-flows-ia*

- Where: `FeatureInbox/HomeSessionRow.swift:43-45`, `FeatureInbox/HomeSessionRow.swift:55-67`, `OCSync/SessionSummary.swift:10-13`, `FeatureInbox/HomeView.swift:63-64`, `FeatureTranscript/TimelineCollection.swift:198` (+1 more)
- Evidence: `iphone/home.png (Needs-you rows: warning glyph + '1 running' + absolute path + '$0.00' + Review; no request text or type)`; `iphone/permission-dock.png ('Working…' shown while the run is blocked on approval)`; `ARCHITECTURE §3: 'Running: a live line with the current step or tool, and elapsed time' (not implemented; the row shows only 'N running')` (+1 more)
- What happens: On iPhone Home, a session blocked on a permission shows a warning icon next to '1 running'. The row never says whether it is a permission, a question or a failure, or what is being asked (for example 'Allow shell: printf …'). Review navigates into the session and scrolls to a card, which needs another tap. Inside, the timeline says 'Working…' while the agent is waiting on the user. Running rows show only 'N running': no current tool or step and no elapsed time. Rows also carry a middle-truncated absolute path, '$0.00' and no relative time.
- Why it matters: Triage means opening each session. The most glanceable surface contradicts itself (warning plus 'running'), which slows the approval loop the app is built around. The vocabulary also diverges from the planned notification and Live Activity phases (needsInput).
- Fix: Needs-you rows: replace 'N running' with a one-line summary from the pending request ('Wants to run `printf …`', 'Asks: Which color?', 'Run failed: Step interrupted'), and add an inline Allow once for non-high-risk permissions. Running rows: current tool or step and elapsed time. Show 'Waiting for you' instead of 'Working…' when the session has a pending request. Show the project and branch plus a relative time instead of the full path, and hide a zero cost.
- Also reported as: F04-11 by session-chrome, F08-14 by timeline-mechanics

<a id="f03-09"></a>

## F03-09: Home rows read poorly with VoiceOver and large text: full paths spoken, status glyph silent, mid-word breaks, glyphs that don't scale

*P2 bug · accessibility · effort M · found by home-inbox*

- Where: `FeatureInbox/HomeSessionRow.swift:33`, `FeatureInbox/HomeSessionRow.swift:43`, `FeatureInbox/HomeSessionRow.swift:65`, `OCDesign/TimelineChrome.swift:81`, `OCDesign/TimelineChrome.swift:91` (+1 more)
- Evidence: `Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/ReadSnapshots/capture-_-name-height.home-needs-you-light-393.png: the title breaks as 'implementatio / n'; home-failed-light-393.png breaks it as 'implementati / on'`; `In the same AX5 snapshots the status glyphs measure 10 pt (warning, failed) and 6 pt (running and unread dots) next to text about 44 pt tall`; `TimelineChrome.swift:91 attaches the status label to an OCIcon whose Image is '.accessibilityHidden(true)' (Icon.swift:17)` (+1 more)
- What happens: VoiceOver on a Needs you row speaks 'Question, Studio Mac · /Users/\<name>/2.1.2/199efe6b/project' with the full, untruncated path, then '1 running, $0.00, button'. It very likely says nothing like 'Needs you', 'Failed' or 'Syncing', because the glyph carrying that label is hidden; a failed session is announced only as 'Unread'. Every Review button appears in the rotor as just 'Review'. At AX5 on iPhone the avatar keeps its column, so long words break mid-word, while the status glyphs stay 6–12 pt.
- Why it matters: Blind users can't triage efficiently, and low-vision users can't see a row's status. In light mode the secondary line fails WCAG 1.4.3.
- Fix: Give the primary button an explicit label (title, status, project, server) and put cost and path in the value or hint. Expose the status on a view that isn't hidden. Label each Review button 'Review \<title>'. Scale the glyphs with @ScaledMetric. At accessibility sizes, put the avatar above the text or drop it. Use textMuted (6.69:1) for the subtitle; this revisits a docs/design.md token choice. M9a plans accessibility in general, not this specific work.
- Also reported as: F20-11 by design-system, F21-06 by a11y-voiceover, F22-13 by a11y-dynamic-type, F35-04 by sweep-read-snapshots, F35-07 by sweep-read-snapshots

<a id="f03-12"></a>

## F03-12: Pin, Hide and Mark read are swipe-only, and their dark-mode labels have 1.9–2.7:1 contrast

*P2 bug · interaction · effort S · found by home-inbox*

- Where: `FeatureInbox/HomeView.swift:157-163`
- Evidence: `Swipe tints: Mark read uses .tint(OCColor.accent), Hide .tint(OCColor.textMuted), Pin .tint(OCColor.info). Their dark values #A2BCFF, #AEAEAE and #7698FD give white labels 1.88:1, 2.22:1 and 2.73:1.`; `Transcript rows, file rows and the composer have a .contextMenu (TimelineRowView.swift:62, FilesScreen.swift:130, ComposerDock.swift:221); Home rows have none`; `UITests/ReadSmokeTests.swift:33: 'A full swipe commits immediately in the narrow iPad sidebar.'`
- What happens: Nothing on a row hints that it can be swiped, and long-press or a right-click with the iPad pointer does nothing. Mark read is offered on rows that are already read, and does nothing silently when time.idle is nil. Hide removes the row with no undo; unhiding needs the hidden-sessions toggle described in the 'Hidden sessions' finding. In dark mode the white swipe labels sit on pale tints.
- Why it matters: Core triage actions are hard to discover, partly unreadable in dark mode, and easy to trigger by accident in the narrow sidebar.
- Fix: Add a .contextMenu with Open, Review, Mark read (only when unread), Pin or Unpin, Hide with an undo toast, Rename and Delete. Show Mark read in the swipe actions only on unread rows. Pick swipe tints that keep at least 4.5:1 against white in both appearances, for example the light-mode accent and info values.
- Also reported as: F24-14 by touch-gestures-motion

<a id="f26-11"></a>

## F26-11: Home rebuilds every session summary 4 + (number of day sections) times per render

*P2 bug · performance · effort M · found by swiftui-state*

- Where: `FeatureInbox/HomeView.swift:32`, `FeatureInbox/HomeView.swift:63`, `FeatureInbox/HomeView.swift:70`, `OCSync/SessionSummary.swift:28`, `OCSync/SessionReadActions.swift:65`
- Evidence: `HomeView.swift:63-71 evaluates 'all' for Needs you, Running, 'all.isEmpty', 'days' (through 'recent'), and once more for each day in 'recent.filter'`; `SessionSummary.swift:28-30: each summary calls 'server.readPath.family(session.id)', and SessionReadActions.swift:65-67 groups every session by parent on each call`; `HomeView.swift:43-47: the sort comparator recomputes 'activity', which maps the family, on every comparison`
- What happens: A user has many sessions, say 150 roots plus subagents over 20 days. Each HomeView render runs `all` about 24 times. Each run builds 150 summaries, each of which scans every session to build its family, then sorts with comparators that rebuild the family maps. Home re-renders on step start and end, cost, status and running-set changes in any session. It is always visible in the iPad sidebar and stays mounted under a pushed session on iPhone.
- Why it matters: Each render does roughly days × roots × sessions work, causing periodic main-thread hitches while agents run.
- Fix: Compute `let all = …` once per body and derive the sections and day groups from it with a single Dictionary(grouping:). Build a parent-to-children index once per render, or in ReadStore, instead of once per summary, and compute activity once before sorting.
- Verifier's note: Compute all once per body, as the finding suggests, and build a parent index once. Also: ServerRootView's body reads server.sessions and the open session's info through panelRequest and failedCreationDirectory, and HomeView takes closures that defeat SwiftUI's diffing. So every sessions-dictionary or info change re-runs HomeView's body. Move those reads into child views.
- Also reported as: F03-11 by home-inbox, F27-03 by ui-performance

<a id="g02-m2"></a>

## G02-M2: Home's 'Load older sessions' shows on every scope even when nothing older exists

*P3 bug · functional · effort S · found by verifier G02*

- Where: `FeatureInbox/HomeView.swift:73-76`, `FeatureInbox/HomeView.swift:84-88`, `OCSync/SessionReadActions.swift:61-63`, `OCSync/ReadResync.swift:35`
- Evidence: `iphone/session-list.png: project 'project' with 4 day-group sessions ends with 'Load older sessions'`; `ipad/ipad-session-list.png: composer-worktree-project with 2 sessions shows 'Load older sessions'`; `Fixtures/v2/2.0.32/rest/subagent.json entry 9: GET /api/session returns 1 session with cursor.next set. This is the same cursor behaviour as F04-02.`
- What happens: Pick any project, run a search, or just open Home. listSessions (or the resync's rootCursor) gets a non-null next for any non-empty page, so `!cursors.isEmpty` keeps the button visible. Tapping it fetches an empty page and the button disappears, then comes back on the next scope change.
- Why it matters: A misleading control suggests hidden history in every scope and costs a wasted tap and request; users can't tell whether they have seen everything.
- Fix: Treat a page with fewer rows than the requested limit as the end: return nil from listSessions and leave rootCursor nil when page.data.count \< limit. This matches the fix for the transcript's olderCursor in F04-02.

<a id="f03-06"></a>

## F03-06: Cancelled requests are shown as errors, and each row action cancels the previous one

*P3 bug · interaction · effort S · found by home-inbox*

- Where: `FeatureInbox/HomeView.swift:91`, `FeatureInbox/HomeView.swift:167-169`, `FeatureInbox/HomeView.swift:93`, `OCNetworking/Endpoint.swift:97-99`
- Evidence: `HomeView.swift:91 'catch is CancellationError {} catch { self.error = "Could not refresh sessions. Pull to try again." }'`; `Endpoint.swift:97-99 maps both CancellationError and URLError.cancelled to APIError.cancelled, so the first catch never matches a cancelled request`; `HomeView.swift:168 'action?.cancel(); action = Task { ... }' is one task shared by Mark read, Hide, Pin and Load older sessions, and :93 '.onDisappear { action?.cancel() }' cancels it when Home disappears`
- What happens: Type 'auth', pause about 0.3 s so the debounced request starts, then type 'z'. .task(id:) cancels the request, and the red 'Could not refresh sessions. Pull to try again.' appears under the short result list until the next request completes. Over a tunnel, full-swipe Mark read on two rows within one round trip: the first request is cancelled, that row stays unread, and 'Could not save the change. Try again.' flashes. On iPhone, opening a session right after a swipe cancels the write through onDisappear.
- Why it matters: False error messages appear during normal typing, and triage actions are dropped without notice.
- Fix: Treat APIError.cancelled (or Task.isCancelled) as cancellation at both catch sites. Run row actions through the store-owned ReadStore.performWrite (WriteStore.swift:13, which exists because 'actions can remove the view that initiated them') or through per-session tasks, so later actions or leaving Home cannot cancel them.
- Verifier's note: Use WriteErrorMessage.isCancellation(error) at both catch sites.
- Also reported as: F26-12 by swiftui-state

<a id="f40-13"></a>

## F40-13: iPad Home forgets search, Hidden sessions and scroll every time it is hidden, and never marks the open session

*P3 bug · state · effort M · found by navigation-state-restoration*

- Where: `FeatureInbox/HomeView.swift:15-21`, `FeatureInbox/HomeView.swift:81-92`, `OCDesign/WorkspaceShell.swift:46`, `OCDesign/WorkspaceShell.swift:54-56`, `FeatureInbox/HomeSessionRow.swift:23-31`
- Evidence: `search, showHidden, cursors and loadedScope are HomeView @State. The sidebar is inserted with 'if homeOpen && wide', and the narrow sheet is rebuilt on every presentation.`; `'.task(id:)' resets 'cursors = [:]; loadedScope = false' on each appearance and refetches the first page, which also resets rootCursor`; `ipad/ipad-transcript-live.png: the open 'Live transcript' row has no selected state in the sidebar`
- What happens: Narrow iPad: open the Home sheet, search 'auth' and open a result. Reopening Home shows an empty search and a list scrolled back to the top. Turn on Hidden sessions, open a hidden session and return: the toggle is off again. On iPhone, tap 'Load older sessions' a few times, open a session and go Back. Pagination restarts from page 2, so the next taps refetch pages already on screen and appear to do nothing. In the iPad sidebar, nothing shows which session is open in the main column.
- Why it matters: Triage across many sessions means redoing searches and paging, and on iPad there is no 'you are here' cue.
- Fix: Move Home's query, hidden toggle, pagination cursors and scroll anchor into a long-lived HomeModel owned by ServerRootView, or put search and hidden in @SceneStorage. Refresh only when the filter key changes. Pass the selected SessionRef into HomeView and render that row as selected, with a background and the .isSelected trait.

<a id="g02-m3"></a>

## G02-M3: Mark read cannot clear a Needs you row whose failure belongs to a subagent

*P3 bug · functional · effort S · found by verifier G02*

- Where: `FeatureInbox/HomeView.swift:158`, `OCSync/SessionSummary.swift:11-12`, `OCSync/SessionReadActions.swift:9-18`, `FeatureInbox/HomeSessionRow.swift:16`
- Evidence: `SessionSummary.swift:11 'failed: family.contains { $0.info.outcome == "failed" && $0.unread }': any family member counts`; `HomeView.swift:158 'markViewed(item.session.id)' marks only the root; markViewed posts /view for one session`
- What happens: A subagent fails and the user has already viewed the parent, for example on the desktop. Home lists the parent under Needs you with the failed glyph but no Unread badge, because that badge reads only the root. Swiping Mark read marks the root viewed; the failed child stays unread, so the row stays under Needs you with no feedback. Only Review, which opens the child, clears it.
- Why it matters: The triage dismiss gesture silently fails for subagent failures, so rows linger in Needs you.
- Fix: Make Mark read mark every unread family member viewed, at least the failed ones (for example ReadStore.markFamilyViewed(root)), and offer it only when the family has something unread.

<a id="f03-10"></a>

## F03-10: Row subtitles spend their line on 'Server · /absolute/path' and never say what is blocked or running

*P2 improvement · visual · effort M · found by home-inbox*

- Where: `FeatureInbox/HomeSessionRow.swift:43`, `FeatureInbox/HomeSessionRow.swift:57`, `OCSync/SessionSummary.swift:16`, `ARCHITECTURE.md:389`, `ARCHITECTURE.md:401`
- Evidence: `iphone/home.png: 'Studio Mac · /Users/<name>/2.1.2/199efe6b/project' on every row, although only one server is connected`; `ipad/ipad-inbox.png: middle truncation cuts through the server name and separator ('127.0.0.1 ·…6b/project')`; `ipad/ipad-portrait.png: the full absolute path on every row` (+2 more)
- What happens: Every row repeats the server name (even with one server) and the user's home directory, and in the 256-pt sidebar the middle truncation can remove the server name entirely. Needs you rows say '1 running' but not whether a permission, a question or a failure is waiting. Running rows say 'N running' instead of the live step or tool and the elapsed time that ARCHITECTURE §3 specifies.
- Why it matters: The facts needed to triage at a glance are missing, while most of the visible line is noise.
- Fix: Subtitle: the project name, plus the worktree or branch when the location isn't the project root. Show the server name as a separate label that doesn't truncate, and only when more than one server is registered. Write the home directory as '~' wherever a path is shown. Needs you rows get a line such as 'Permission · bash npm install', 'Question · Which database?' or 'Failed · \<error>'. Running rows show the current tool or step and the elapsed time. Keep the full path in the context menu or accessibility hint. This revisits ARCHITECTURE's 'server/directory chip'.
- Also reported as: F03-13 by home-inbox, F30-03 by visual-polish-iphone, F39-10 by privacy-security-ui

<a id="f24-13"></a>

## F24-13: On iPhone, Home puts New session and Settings in the top-right corner

*P3 improvement · layout · effort M · found by touch-gestures-motion*

- Where: `FeatureInbox/HomeView.swift:95`, `FeatureInbox/HomeView.swift:113`, `FeatureTranscript/SessionScreen.swift:49`
- Evidence: `iphone/home.png: + centred at ≈(327, 84) pt and the gear at ≈(376, 84) pt on a 402×874 pt screen; search field at ≈148 pt`; `iphone/transcript-tools.png: Review panel button at ≈(364, 187) pt`
- What happens: Using an iPhone 17 Pro one-handed, starting a session (the main Home action) and opening Review both mean reaching the top-right corner. Search is also at the top.
- Why it matters: The most frequent actions sit in the hardest-to-reach region of a 6.3-inch screen. iOS 26 apps such as Mail and Notes moved compose to a bottom toolbar.
- Fix: At compact width, put Settings (leading) and New session (trailing) in a bottom toolbar and use .searchable, which iOS 26 places at the bottom on iPhone. Keep the desktop-style header on iPad. This revisits docs/design.md, which reproduces the desktop sidebar header on iPhone.

<a id="f25-11"></a>

## F25-11: Home day headers hard-code “Today”/“Yesterday”, always show the year, and don’t update at midnight

*P3 improvement · localization · effort S · found by l10n-text*

- Where: `FeatureInbox/HomeView.swift:57`, `FeatureInbox/HomeView.swift:71`, `FeatureInbox/HomeView.swift:178`
- Evidence: `HomeView.swift:179-181 if Calendar.current.isDateInToday(day) { return "Today" } … return day.formatted(date: .abbreviated, time: .omitted)`; `iphone/home.png (“Today” header)`; `HomeView has no timer or day-change trigger; the headers are recomputed only when observed data changes`
- What happens: An iPad left on Home overnight with idle servers keeps yesterday’s sessions under “Today” until something re-renders the list. Older headers read “Oct 20, 2026” even within the current year.
- Why it matters: Day labels can be wrong, and the hard-coded words bypass the system’s localized relative dates.
- Fix: Use a DateFormatter with doesRelativeDateFormatting = true, or Date.FormatStyle with month and day, adding the year only when it differs from the current one. Re-render on .NSCalendarDayChanged or significant time changes, or with a TimelineView scheduled for the next midnight.
