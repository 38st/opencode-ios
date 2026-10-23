# UI review: Session screen

Part of the [UI review](README.md). 9 bugs and 6 improvements, bugs first, then by severity. Paths under `Packages/OpencodeKit/Sources` are written without that prefix.

| ID | Severity | Finding |
| --- | --- | --- |
| [F21-01](#f21-01) | P1 bug | No VoiceOver announcements anywhere: approvals, run end/failure, inline errors and copy feedback arrive silently |
| [F04-01](#f04-01) | P1 bug | At accessibility text sizes, fixed session chrome leaves the iPhone transcript only ~13–130 pt |
| [F04-03](#f04-03) | P2 bug | A deleted or missing session leaves the screen stuck on "Opening session… Loading the conversation from your server." |
| [F04-04](#f04-04) | P2 bug | Subagent screen is labelled "read only" but its menus still offer Undo, Compact, Delete and Revert |
| [F04-05](#f04-05) | P2 bug | No route from a subagent to its parent when opened directly, and iPad's "Back to parent" is an unlabelled floating text button |
| [F04-07](#f04-07) | P2 bug | Header shows the raw model ID, not the composer's model name, and long IDs collapse the header into a 4–6 line stack |
| [F28-03](#f28-03) | P2 bug | A session that is not cached yet opens to a blank timeline: the loading state never appears and an empty session has no empty state |
| [F04-09](#f04-09) | P2 bug | Session-screen errors stick after recovery, overwrite each other, and show other sessions' failures |
| [F04-06](#f04-06) | P3 bug | VoiceOver never speaks the session cost, and the header and detail menu are announced without context |
| [F04-08](#f04-08) | P2 improvement | iPhone session chrome uses ~190 pt before the first message while the nav bar's trailing area sits empty |
| [F04-10](#f04-10) | P3 improvement | Session menus are confusingly split: a "Compact" filter sits beside "Compact session", and inapplicable actions stay enabled |
| [F04-12](#f04-12) | P3 improvement | Context and cost round to "0%" and "$0.00", and an empty "Context —" badge is shown |
| [F27-08](#f27-08) | P3 improvement | Session header scans every message and regroups every session, twice per render |
| [F21-13](#f21-13) | P3 improvement | Counts and session metadata are read as unlabeled fragments ('+3', '−2', '1/7', 'Build', 'mock-1', 'Compact') |
| [F27-13](#f27-13) | P3 improvement | SessionScreen builds a new OCFileLinks on every render, invalidating every Markdown block and tool row that reads it |

<a id="f21-01"></a>

## F21-01: No VoiceOver announcements anywhere: approvals, run end/failure, inline errors and copy feedback arrive silently

*P1 bug · accessibility · effort M · found by a11y-voiceover*

- Where: `FeatureTranscript/SessionScreen.swift:57`, `OCSync/ApprovalActions.swift:25`, `FeatureApprovals/ApprovalDock.swift:14`, `FeatureTranscript/TimelineRowView.swift:109`, `FeatureTranscript/TimelineCollection.swift:198` (+1 more)
- Evidence: `grep for UIAccessibility.post / AccessibilityNotification / announce / AccessibilityFocusState in Packages/OpencodeKit/Sources and App: zero matches`; `Feedback.swift:37 OCToast: .accessibilityAddTraits(.updatesFrequently) (a polling hint for the focused element, not a live region)`; `ServerDetailView.swift:144: Text("Copied \(copied)").accessibilityAddTraits(.updatesFrequently)` (+4 more)
- What happens: iPhone, VoiceOver on. The user sends a prompt and stays in the composer or reads earlier output. The agent asks for shell permission. A PermissionCard appears in the transcript and in the ApprovalDock above the composer, and VoiceOver says nothing. Nothing is spoken either when the run finishes ('Working…' vanishes) or fails ('Run failed' row), when the composer shows 'Could not search files.', when the permission sheet switches to 'Reply could not be sent' or 'Already handled', when Add server shows its error banner, or after 'Copy code' / 'Copy session link'. Only the .alert-based errors are announced.
- Why it matters: The core loop is waiting for the agent and answering it. A blind user gets no signal that the agent is blocked on them, has finished or has failed, and has to keep sweeping the screen. Error and copy feedback is also silent. Push (M5b) targets the background case, not the open session.
- Fix: Add an OCDesign announcer that posts AccessibilityNotification.Announcement, with high priority for approvals. Call it when ApprovalDock gains a request ('Permission needed: Shell'), when a session stops running ('Run finished' / 'Run failed'), when inline error strings change (composer, session, review, files, add-server, sheet failed/settled), and after every copy ('Copied'). Replace .updatesFrequently on OCToast and the 'Copied' text with an announcement. Optionally post .layoutChanged with the dock's Review button when a request arrives while focus is in the composer.
- Verifier's note: Announce changes to store.writeError (SessionScreen.swift:57) and the sheet's .settled state ('Already handled'), not the sheet's .failed/.sending/.authenticating states, which production never sets. Use AccessibilityNotification.Announcement with high priority when a request arrives.

<a id="f04-01"></a>

## F04-01: At accessibility text sizes, fixed session chrome leaves the iPhone transcript only ~13–130 pt

*P1 bug · accessibility · effort M · found by session-chrome*

- Where: `FeatureTranscript/SessionScreen.swift:31-61`, `FeatureTranscript/SessionScreen.swift:163-166`, `FeatureTranscript/SessionTimeline.swift:29-32`
- Evidence: `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-idle-light-393-accessibility5.png (composer measures 252 pt tall at AX5, versus 108 pt at the default size)`; `crops/session-chrome/ax-heights.txt (AX5: header HStack would need 620 pt, so the VStack is used: header 252 pt, toolbar 69 pt, Load earlier wraps to 2 lines at 114 pt; AX3: header 198 pt)`; `iphone/transcript-tools.png (at default size the transcript already starts at about 253 pt)` (+1 more)
- What happens: iPhone 17 Pro (874 pt), Larger Text at AX5, any session. The nav bar, SessionHeader, the Compact/…/Review row and "Load earlier messages" sit in a fixed VStack above the TimelineCollection. None of them scrolls or collapses. The header falls back to one label per line (~252 pt), the toolbar row is ~69 pt, "Load earlier messages" wraps to ~114 pt, and the composer is ~276 pt including padding and has layoutPriority(1). Of the 724 pt between the nav bar and the home indicator, ~711 pt is fixed chrome, leaving ~13 pt for the transcript (~127 pt without the Load earlier bar; ~190 pt at AX3). With the keyboard up the transcript gets nothing. No snapshot or UI test renders SessionScreen at accessibility sizes.
- Why it matters: Low-vision users cannot read the agent's output, which is the screen's main purpose. Older 667-pt iPhones are worse.
- Fix: At accessibility sizes, move the header metadata and the detail/actions controls into the navigation bar (icon-only toolbar menus) or make them the first rows of the collection so they scroll away. Replace the HStack→VStack switch with a wrapping flow layout. Render Load earlier as a list row. Add a SessionScreen snapshot at 393×852 for default and accessibility5.
- Also reported as: F22-01 by a11y-dynamic-type

<a id="f04-03"></a>

## F04-03: A deleted or missing session leaves the screen stuck on "Opening session… Loading the conversation from your server."

*P2 bug · state · effort S · found by session-chrome*

- Where: `FeatureTranscript/SessionScreen.swift:72-76`, `FeatureTranscript/SessionScreen.swift:86-93`, `OCSync/EventHandlers.swift:36-41`, `OCSync/ReadResync.swift:110-115`, `OCSync/ReadStore.swift:58`
- Evidence: `OCEmptyState(error == nil ? "Opening session…" : "Session unavailable", detail: error ?? "Loading the conversation from your server.", icon: "bubble-5") { EmptyView() }`; `session.deleted: sessions.removeValue(forKey: id); openSessions.remove(id) …`; `refreshSession catches SessionNotFoundError 404, removes the session and returns without throwing, so open() succeeds and error = nil`
- What happens: (a) A session is open on iPhone or iPad and gets deleted from the desktop. The session.deleted event removes it from sessions, SessionScreen falls into the else branch, and it shows "Opening session…" indefinitely, because no task re-runs. (b) Opening a copied session link (or a future push) for a session that was deleted: the 404 is swallowed, open() returns normally, error is nil, and the screen is stuck the same way. (c) Offline, opening an uncached session shows "Session unavailable" with the detail "Could not refresh this session. Cached messages are shown when available.", although nothing is cached. The empty state's action slot is EmptyView, so there is no Retry or Back.
- Why it matters: Users wait on a session that no longer exists, and nothing says it was deleted. On iPad, a root session has no back control at all.
- Fix: Expose an observable removed state from ReadStore (deletedSessions or a 404 marker). Render "This session was deleted" with a "Back to sessions" action that calls deleted(). Give the unavailable state a Retry button and copy that does not promise cached messages.
- Also reported as: F08-07 by timeline-mechanics, F28-02 by states-coverage, F40-07 by navigation-state-restoration

<a id="f04-04"></a>

## F04-04: Subagent screen is labelled "read only" but its menus still offer Undo, Compact, Delete and Revert

*P2 bug · consistency · effort S · found by session-chrome*

- Where: `FeatureTranscript/SessionScreen.swift:46-47`, `FeatureComposer/SelectionOptions.swift:35-46`, `FeatureComposer/SessionActions.swift:25-37`, `FeatureTranscript/TimelineRowView.swift:62-67`, `FeatureComposer/ComposerDock.swift:51-56`
- Evidence: `iphone/subagent.png (the "…" session-actions menu sits directly beside "Subagent · read only")`; `ipad/ipad-subagent.png`; `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.session-menu-light-393-default.png` (+1 more)
- What happens: Open a subagent from its card. The composer is replaced by "Subagent sessions are read only. Send prompts to the parent session." The "…" menu still lists Rename, Fork from message, Compact session, Undo last message, Redo last message and Delete session. Long-pressing the subagent's prompt still offers Revert message and Fork from here. These write to the child session: Undo reverts the subagent's file edits and Delete removes it, possibly while the parent run still depends on it.
- Why it matters: The UI contradicts itself, and destructive actions on a screen that claims to be read only can break a running parent or lose the subagent record.
- Fix: When session.info.parentID != nil, hide or disable Undo, Redo, Compact, Delete and Rename in SessionMenuOptions and Revert message in the prompt context menu. Keep Copy link, Select text and Fork (into a new root).
- Also reported as: F12-01 by session-actions

<a id="f04-05"></a>

## F04-05: No route from a subagent to its parent when opened directly, and iPad's "Back to parent" is an unlabelled floating text button

*P2 bug · navigation · effort S · found by session-chrome*

- Where: `FeatureComposer/ComposerDock.swift:51-56`, `OCSync/SessionSummary.swift:20-27`, `FeatureServers/ServerRootView.swift:54-56`, `FeatureServers/ServerRootView.swift:181`
- Evidence: `iphone/subagent.png (read-only dock text with no action; header does not name the parent)`; `ipad/ipad-subagent.png ("Back to parent" centred in the grey chrome, level with the sidebar's Home/server/+/settings row; card top moves from 84 pt to 128 pt compared with ipad-transcript-tools.png)`; `ipad/ipad-portrait.png` (+1 more)
- What happens: Home › Needs you › Review on a family whose pending permission, question or unseen failure belongs to the subagent. reviewRef targets the child, and the path is replaced with [child]. On iPhone the back button goes to Home. On iPad sessionPath.count == 1, so "Back to parent" is not shown. The dock tells the user to "Send prompts to the parent session" but offers no link, and the header never names the parent. When it does appear (iPad, via Open agent), it is a text-only ghost button with no chevron or parent title, floating outside the card, and it pushes the card down 44 pt. The child's first message, written by the parent agent, also renders as the user's own blue bubble.
- Why it matters: To continue the work, users must go back to Home and find the parent. On iPad the control reads like a title rather than navigation.
- Fix: Add an "Open parent session" button to the read-only dock and the session menu that calls openRoot(parentID), or pushes the parent onto the stack. Show a "in \<parent title>" breadcrumb in the header. On iPad, render a leading "‹ \<parent title>" control inside the card header. Optionally label the first prompt as from the parent agent.
- Also reported as: F19-06 by ipad-shell, F31-07 by visual-polish-ipad, F33-08 by ux-flows-ia, F40-05 by navigation-state-restoration

<a id="f04-07"></a>

## F04-07: Header shows the raw model ID, not the composer's model name, and long IDs collapse the header into a 4–6 line stack

*P2 bug · layout · effort M · found by session-chrome*

- Where: `FeatureTranscript/SessionScreen.swift:174`, `FeatureTranscript/SessionScreen.swift:163-166`, `FeatureTranscript/SessionScreen.swift:173`, `FeatureComposer/ComposerDock.swift:197`
- Evidence: `iphone/transcript-tools.png (header "mock-1", composer "Mock 1")`; `iphone/composer-sent.png (header "mock-vision", composer "Mock Vision")`; `iphone/composer-revert-confirmation.png ("Reviewer mock-vision careful Pending Context 0% $0.00" measures 365.7 pt, within 4 pt of the 370 pt available on a 402-pt phone)` (+2 more)
- What happens: The header prints model.id, and the agent ID run through .capitalized. The dock shows ComposerPickers.displayName, so a real server shows "claude-sonnet-4-5-20250929" above a dock reading "Claude Sonnet 4.5". Measured widths: "Build claude-sonnet-4-5-20250929 high Context 12% $1.23" needs 378 pt, "Build claude-opus-4-1-20250805 high Pending Context 12% $12.34" needs 431 pt, and the fixture's own Reviewer line needs 366 pt. Available width is 361 pt on 393-pt iPhones and 370 pt on 402-pt ones. When the line overflows, ViewThatFits switches to one label per line: ~148 pt instead of 49 pt, at default text size. It flips live when the user picks a model and "Pending" appears, shoving the transcript down ~100 pt.
- Why it matters: The same screen names the model two ways, and on common configurations the header grows by ~100 pt, shifting the layout mid-task.
- Fix: Resolve the ModelInfo the header already looks up for the context limit and show displayName; use the catalog name for the agent. Replace the all-or-nothing HStack/VStack switch with a wrapping flow layout, or a single line where the model truncates. Drop the header's Pending badge, since the dock already shows it.
- Also reported as: F11-10 by pickers-new-session, F25-04 by l10n-text, F29-07 by ux-writing

<a id="f28-03"></a>

## F28-03: A session that is not cached yet opens to a blank timeline: the loading state never appears and an empty session has no empty state

*P2 bug · state · effort M · found by states-coverage*

- Where: `OCSync/ReadResync.swift:216-225`, `FeatureTranscript/SessionScreen.swift:52-55`, `FeatureTranscript/SessionScreen.swift:92`, `FeatureTranscript/SessionTimeline.swift:20`, `OCSync/TranscriptModel.swift:74-84`
- Evidence: `ReadStore.open: 'session.transcript = TranscriptModel(messages: cached?.messages ?? [], ...)' runs before 'refreshSession', so the transcript is non-nil and empty`; `SessionScreen: 'if let transcript = session.transcript { SessionTimeline(...) } else { ... ProgressView("Loading conversation…") ... }', so the spinner shows only during the local cache read`; `TranscriptModel has no loaded or loading flag; SessionTimeline 'rows' start as '[]' and are built asynchronously`
- What happens: Open a session that was never opened on this device (fresh install, created on the desktop, or evicted from the cache), over a tunnel. The space between the header and the composer stays empty until the network fetch returns: seconds on a tunnel, and up to about 90 s if the server is unreachable. Then the content pops in. If the fetch fails, the only feedback is red 'Could not refresh this session. Cached messages are shown when available.' under an empty timeline, with no Try again. A session that really has no messages looks the same as one that is loading. Large cached transcripts also show blank while their rows are being built.
- Why it matters: Users cannot tell 'loading', 'empty' and 'failed' apart in the most-used screen. A blank screen reads as broken or as an empty session.
- Fix: Give TranscriptModel a load state (cached, loading, loaded, failed). Show a spinner or skeleton while the transcript is empty and loading; 'No messages yet' when it is loaded and empty; and an inline error with Try again when it is empty and the load failed. Reword the error when nothing is cached.

<a id="f04-09"></a>

## F04-09: Session-screen errors stick after recovery, overwrite each other, and show other sessions' failures

*P2 bug · state · effort S · found by session-chrome*

- Where: `FeatureTranscript/SessionScreen.swift:56-57`, `FeatureTranscript/SessionScreen.swift:86-98`, `OCSync/WriteStore.swift:133-135`, `OCSync/ApprovalActions.swift:25`, `OCSync/SessionWriteActions.swift:60`
- Evidence: `catch { self.error = "Could not refresh this session. Cached messages are shown when available." } … catch { self.error = "Could not mark this session read." }`; `if let error = server.readPath.writeError { Text(error)… } (writeError is one string for the whole server)`
- What happens: Open a session while offline or before the connection is up, which is common right after launch. Red text "Could not refresh this session…" appears above the composer. When the connection returns, resync refreshes the open session and new messages stream in, but error is only cleared by a re-run of .task(id: sessionID), so the red text stays. The concurrent markViewed task writes "Could not mark this session read." into the same variable, replacing the useful message, and is not retried until idle changes or the app is backgrounded, so the session stays unread. Separately, the server-wide writeError ("Permission reply was not sent…", a failed delete) from another session appears in red in every session on that server.
- Why it matters: Stale or unrelated errors make a healthy session look broken, and teach users to ignore red text.
- Fix: Keep refresh and mark-read failures in separate state. Clear the refresh error on the next successful refresh of the session, retry markViewed silently on reconnect, and scope writeError per session or show it as a dismissible toast with Retry.
- Raised from P3 to P2, the severity of F28-06, which describes the same problem.
- Also reported as: F26-13 by swiftui-state, F28-06 by states-coverage

<a id="f04-06"></a>

## F04-06: VoiceOver never speaks the session cost, and the header and detail menu are announced without context

*P3 bug · accessibility · effort S · found by session-chrome*

- Where: `FeatureTranscript/SessionScreen.swift:180-181`, `FeatureTranscript/SessionScreen.swift:173-174`, `FeatureTranscript/SessionScreen.swift:43-44`
- Evidence: `Text(…cost.formatted(.currency(code: "USD"))).accessibilityLabel("Family cost") with no accessibilityValue, so the label replaces the amount`; `OCLabel(TimelineDetail(rawValue: detail)?.title ?? "Compact", icon: "sliders") has no accessibilityLabel`; `iphone/transcript-tools.png`
- What happens: With VoiceOver on any session, swiping through the header reads "Build", "mock-1", "Context 0%", "Family cost". The dollar amount is never spoken. The agent and model are bare words, and "Build" sounds like an action. The detail menu is read as "Compact", with no hint that it is the timeline-detail filter.
- Why it matters: Blind users cannot learn what a session costs, and must guess what the header items and the toolbar control mean.
- Fix: Use .accessibilityLabel("Cost including subagents").accessibilityValue(costString). Label the other items "Agent, Build" and "Model, Claude Sonnet 4.5", or combine the header into one element with a full sentence. Give the menu .accessibilityLabel("Timeline detail").accessibilityValue(current preset).

<a id="f04-08"></a>

## F04-08: iPhone session chrome uses ~190 pt before the first message while the nav bar's trailing area sits empty

*P2 improvement · layout · effort M · found by session-chrome*

- Where: `FeatureTranscript/SessionScreen.swift:33-51`, `FeatureTranscript/SessionScreen.swift:79`, `FeatureTranscript/SessionTimeline.swift:29-32`
- Evidence: `iphone/transcript-tools.png (measured: nav bar ends at 116 pt, header at 165 pt, toolbar row at 209 pt, Load earlier at 253 pt; transcript visible from 253 to 708 pt, about 52% of 874 pt)`; `iphone/transcript-live.png`; `.build/design-reference/timeline-light-393x852.png (desktop mobile layout: title row plus tabs, about 95 pt)` (+1 more)
- What happens: Every iPhone session stacks four bars: the inline nav bar (back button and title only), the agent/model/context/cost line, a row holding just Compact, … and the Review toggle, and Load earlier messages. Agent and model are repeated in the composer below. None of these bars collapses while scrolling.
- Why it matters: About 6 fewer transcript lines on every screen of the app's main view, where the desktop's mobile layout spends half as much.
- Fix: Put "…" (holding the detail presets, Copy link, Select text and the session actions) and Review as trailing toolbar items; SPEC §5 already says review opens "from the toolbar". Show agent · model · context · cost as a navigation subtitle or a second line of a principal toolbar item, or collapse it on scroll. Move Load earlier into the list. This reclaims ~90–130 pt. Not covered by docs/design.md.
- Also reported as: F30-02 by visual-polish-iphone, F31-09 by visual-polish-ipad, F32-10 by design-parity

<a id="f04-10"></a>

## F04-10: Session menus are confusingly split: a "Compact" filter sits beside "Compact session", and inapplicable actions stay enabled

*P3 improvement · interaction · effort S · found by session-chrome*

- Where: `FeatureTranscript/SessionScreen.swift:35-44`, `FeatureComposer/SelectionOptions.swift:35-46`, `OCModels/ComposerSuggestions.swift:56-60`, `FeatureServers/ServerSettingsView.swift:26-34`, `ARCHITECTURE.md:414`
- Evidence: `iphone/transcript-tools.png (toolbar reads "Compact" next to "…")`; `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.session-menu-light-393-default.png ("Compact session")`; `@AppStorage("timelineDetail") private var detail`
- What happens: The row's only labelled control reads "Compact" (or "Everything") right beside a "…" menu containing "Compact session", which summarises the conversation. The control is actually a display filter. The five presets have no descriptions (Quiet hides tools, thinking and shell; Messages only leaves prose). "Copy session link" (silent, no confirmation) and "Select text" (the whole-transcript selection on iOS 26) live in this filter menu rather than "…". The choice silently rewrites the app-wide default for every session, while Settings › App has no timeline-detail entry although SPEC §3 lists one. In "…", Undo, Compact and Fork stay enabled in an empty session even though the slash list hides them.
- Why it matters: Users can confuse viewing with compacting, miss Select text, and change every session's display without knowing it.
- Fix: Make it an icon-only "View options" button, or label it "View: Compact", with a "Timeline detail" header and a one-line description per preset. Move Copy link (with a "Copied" confirmation) and Select text into "…". Add the preset to Settings › App. Disable Undo, Compact and Fork when there are no visible prompts, as the slash list does.
- Also reported as: F12-11 by session-actions, F29-06 by ux-writing, F33-13 by ux-flows-ia

<a id="f04-12"></a>

## F04-12: Context and cost round to "0%" and "$0.00", and an empty "Context —" badge is shown

*P3 improvement · copy · effort S · found by session-chrome*

- Where: `FeatureTranscript/SessionScreen.swift:148-157`, `FeatureTranscript/SessionScreen.swift:179-181`
- Evidence: `iphone/composer-queue.png ("Context —")`; `iphone/composer-sent.png ("Context —")`; `fraction.formatted(.percent.precision(.fractionLength(0))) and .formatted(.currency(code: "USD"))`
- What happens: A session that has used 4k tokens of a 1M-token context shows "Context 0%", and a $0.004 session shows "$0.00", both of which read as nothing used. During the first turn, or when the catalog lacks a context limit, the header shows a bordered "Context —" badge. The badge styling makes "Context 0%" look like a tag rather than a meter.
- Why it matters: Cost and context are the header's only live metrics, and both are wrong at the low end where cheap models live.
- Fix: Show "\<1%" for 0 \< fraction \< 0.01, and "\<$0.01" or three decimals below a cent. Hide the context item until it is known. Consider a small ring, or "12% of 200k" in a tap popover and the accessibility value.

<a id="f27-08"></a>

## F27-08: Session header scans every message and regroups every session, twice per render

*P3 improvement · performance · effort S · found by ui-performance*

- Where: `FeatureTranscript/SessionScreen.swift:141-157`, `FeatureTranscript/SessionScreen.swift:163-166`, `FeatureTranscript/SessionScreen.swift:172-181`, `OCSync/SessionReadActions.swift:65-74`
- Evidence: `SessionScreen.swift:149 'session.transcript?.order.reversed().compactMap { session.transcript?.messages[$0]?.fields }.first { ... }': the eager compactMap copies and observes every message's fields`; `SessionScreen.swift:163-166 'ViewThatFits { HStack { labels }; VStack { labels } }' builds 'labels' twice, so 'usage' and the family cost at line 180 each run twice per render`; `family() regroups all sessions (SessionReadActions.swift:67), so the header observes every session's info`
- What happens: A 2,000-message session with running subagents. The header re-renders on each of this session's step and usage events, on every compaction delta, and on every step of any other session on the server. Each render walks the full transcript twice and regroups all sessions twice.
- Why it matters: This avoidable O(history + sessions) main-thread work runs on frequent events and adds to streaming jank.
- Fix: Use a lazy reverse search, such as `order.reversed().lazy.compactMap{...}.first(where:)`, or keep the latest usage on SessionModel. Compute agent, model, usage and cost once before ViewThatFits. Read the family cost from a cached children index.

<a id="f21-13"></a>

## F21-13: Counts and session metadata are read as unlabeled fragments ('+3', '−2', '1/7', 'Build', 'mock-1', 'Compact')

*P3 improvement · accessibility · effort S · found by a11y-voiceover*

- Where: `FeatureTranscript/SessionScreen.swift:173`, `FeatureTranscript/SessionScreen.swift:43`, `OCDesign/DiffCardView.swift:112`, `FeatureTranscript/TurnChangesCard.swift:26`, `FeatureReview/ReviewScreen.swift:140` (+1 more)
- Evidence: `SessionScreen.swift:173-174: agent and model are bare Texts ('Build', 'mock-1')`; `SessionScreen.swift:35-43: the timeline menu is labelled only by the current detail ('Compact'), though it also holds Copy session link and Select text`; `DiffCardView.swift:112-117, TurnChangesCard.swift:26-27, ReviewScreen.swift:89 and :162: separate Text("+N") and Text("−N") elements` (+3 more)
- What happens: VoiceOver in a session reads 'Build', 'mock-1', 'Context 0%', 'Family cost', then 'Compact, pop-up button'. A turn card takes three stops: '3 Changed files', 'plus 2', 'minus 2'. The review toolbar's '1/7' is read literally or as a fraction.
- Why it matters: Common status information costs extra swipes and guesswork.
- Fix: Combine and label. Make SessionHeader one element ('Agent Build, model mock-1, context 0%, cost $0.00'). Read counts as '2 additions, 2 deletions' and the position as 'File 1 of 7'. Label the timeline menu 'Timeline options' with the detail level as its value.

<a id="f27-13"></a>

## F27-13: SessionScreen builds a new OCFileLinks on every render, invalidating every Markdown block and tool row that reads it

*P3 improvement · performance · effort S · plausible, needs a running app to confirm · found by ui-performance*

- Where: `FeatureTranscript/SessionScreen.swift:77`, `FeatureTranscript/SessionScreen.swift:101-119`, `OCDesign/FileLinks.swift:4-24`, `OCDesign/MarkdownBlockView.swift:16-33`, `FeatureTranscript/ToolRowView.swift:17`
- Evidence: `SessionScreen.swift:77 injects 'fileLinks' into the environment, and the fileLinks getter (lines 101-119) builds a new struct of eight closures each time`; `OCFileLinks (FileLinks.swift:4-20) is not Equatable, so each new value counts as a change`; `SessionScreen's body reads session.info (title, idle stamp, directory), which step and usage events mutate (EventHandlers.swift:91, 108)` (+2 more)
- What happens: During a run, each step.started, step.ended and usage.updated event re-runs SessionScreen.body. The new OCFileLinks propagates, and every visible StreamingMarkdownView, TextualBlockContent and ToolRowView re-evaluates; the tool rows also recompute their presentation.
- Why it matters: Every visible block re-renders several times per step, wasting main-thread time during streaming.
- Fix: Create the OCFileLinks once per session and inject that stable instance, for example from @State set in .task(id: sessionID) or a value cached on FilesModel. Alternatively, make OCFileLinks Equatable by an owner identity such as the store and sessionID.
- Verifier's note: Drop the presentation-recompute part of the scenario; the cost is re-running the reader bodies and installing a new OpenURLAction per Markdown block.
