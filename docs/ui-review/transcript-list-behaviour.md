# UI review: Transcript list behaviour

Part of the [UI review](README.md). 9 bugs and 0 improvements, bugs first, then by severity. Paths under `Packages/OpencodeKit/Sources` are written without that prefix.

| ID | Severity | Finding |
| --- | --- | --- |
| [F08-01](#f08-01) | P1 bug | Auto-follow ignores VoiceOver, Switch Control and keyboard scrolling, so during a run the transcript snaps back to the bottom |
| [F08-02](#f08-02) | P2 bug | 'Load earlier messages' appears on every session loaded from the server, even 1–3 message ones, pinned above the list |
| [F08-04](#f08-04) | P2 bug | Opening the keyboard, or a growing prompt, hides the latest messages instead of keeping the bottom in view |
| [F08-05](#f08-05) | P2 bug | Expanded tool groups, diff cards, 'Thinking' and 'Show all' collapse again after the row scrolls away and back |
| [F08-06](#f08-06) | P2 bug | Opening a session at a pending request (Inbox 'Review', deep link) turns auto-follow off and shows 'Jump to latest' while already at the bottom |
| [F08-08](#f08-08) | P2 bug | Reading position is lost when the timeline width or detail level changes (iPad rotation, review panel, Stage Manager, detail menu) |
| [F08-10](#f08-10) | P3 bug | TranscriptModel.replace is quadratic and runs on the main actor on every open and resync |
| [F08-11](#f08-11) | P3 bug | Opening a long session briefly shows the oldest loaded messages, then jumps to the end |
| [F08-13](#f08-13) | P3 bug | Tapping 'Jump to latest' during a fling does nothing, and its count is not a count of new messages |

<a id="f08-01"></a>

## F08-01: Auto-follow ignores VoiceOver, Switch Control and keyboard scrolling, so during a run the transcript snaps back to the bottom

*P1 bug · accessibility · effort M · found by timeline-mechanics*

- Where: `FeatureTranscript/TimelineCollection.swift:131-137`, `FeatureTranscript/TimelineCollection.swift:79-82`, `FeatureTranscript/TimelineCollection.swift:119-124`, `FeatureTranscript/TimelineCollection.swift:157-166`, `FeatureTranscript/SessionTimeline.swift:48-49`
- Evidence: `TimelineCollection.swift:132 'guard !applying, scrollView.isDragging || scrollView.isDecelerating || scrollView.isTracking else { return }': following, atBottom and reachedTop update only during touch drags`; `TimelineCollection.swift:79-82: every contentSize change calls followLatest(), which calls setContentOffset to the bottom 100 ms later`; `No isVoiceOverRunning, accessibilityScroll or VoiceOver focus handling anywhere in Packages/OpencodeKit/Sources or App`
- What happens: VoiceOver is on and the agent is streaming a long answer. The user three-finger-swipes up, or swipes back to earlier rows (VoiceOver scrolls the collection to reveal them). Those scrolls are programmatic, so isDragging, isDecelerating and isTracking are all false. As a result, `following` and `nearBottom` stay true. On the next content growth (each markdown re-parse, roughly 12 per second), sizeChanged calls followLatest and the list jumps back to the bottom. The focused cell scrolls away and may be reused, so VoiceOver focus can be lost. The Jump pill never appears, and reachedTop never pages. The same applies to Switch Control and Voice Control scroll commands and to keyboard-driven scrolling on iPad.
- Why it matters: VoiceOver users cannot read anything above the tail while a run is active. In a primary flow, that is a serious barrier.
- Fix: Wrap the coordinator's own scrolls (scrollLatest, performPending, anchor restore) in a `programmaticScroll` flag. In scrollViewDidScroll, update following, atBottom and reachedTop from geometry whenever that flag is false, not only while dragging. While VoiceOver focus is inside the transcript, suspend auto-follow and post an announcement for new activity instead.
- Verifier's note: Besides a flag for the coordinator's own programmatic scrolls, override accessibilityScroll(_:) in TimelineCollectionView, or implement scrollViewDidEndScrollingAnimation, to recompute following and atBottom from geometry after non-touch scrolls.
- Also reported as: F21-02 by a11y-voiceover

<a id="f08-02"></a>

## F08-02: 'Load earlier messages' appears on every session loaded from the server, even 1–3 message ones, pinned above the list

*P2 bug · functional · effort S · found by timeline-mechanics*

- Where: `OCSync/ReadResync.swift:191-203`, `OCSync/ReadResync.swift:249`, `FeatureTranscript/SessionTimeline.swift:29-32`, `FeatureTranscript/TimelineCollection.swift:136`
- Evidence: `crops/timeline-mechanics/load-earlier-short-sessions.png (crops of transcript-live, permission-dock, subagent and composer-delete: the bar sits above 2–10 message transcripts)`; `ipad/ipad-portrait.png (Fixture child, 2 messages, with the bar)`; `Fixtures/v2/2.0.32/rest/plain-text.json: a 3-row page requested with limit=200 returns a non-null cursor.next. In every fixture, every non-empty message page has next; only empty pages return null` (+1 more)
- What happens: Open any existing session from Home. A 'Load earlier messages' bar (~44 pt) sits under the toolbar, outside the scroll view, although the whole history is already loaded. Tapping it, or any drag that reaches the top (reachedTop at offset ≤ 40), sends a request that returns an empty page. The bar then disappears and the list jumps up about 44 pt, mid-gesture. In long sessions the bar stays pinned on screen throughout, and paging starts only once the user hits the very top.
- Why it matters: A misleading control, permanently lost vertical space on iPhone, a wasted request per session and a layout jump.
- Fix: Treat a page with fewer rows than the requested limit (50) as the start: set olderCursor = nil and isAtStart = true in fetchSplice and loadOlder. Render the control as a header inside the collection with a spinner, and prefetch when the first visible item is within about one screen of the top.
- Verifier's note: Apply the page-size check where the newest page is read and where older pages are fetched in fetchSplice, and in loadOlder. Set isAtStart there as well.
- Also reported as: F04-02 by session-chrome

<a id="f08-04"></a>

## F08-04: Opening the keyboard, or a growing prompt, hides the latest messages instead of keeping the bottom in view

*P2 bug · interaction · effort S · found by timeline-mechanics*

- Where: `FeatureTranscript/TimelineCollection.swift:175-181`, `FeatureTranscript/SessionScreen.swift:52-61`
- Evidence: `TimelineCollection.swift:180 'if previousSize != contentSize { previousSize = contentSize; sizeChanged?() }': only content-size changes trigger follow; changes to the view's own size are ignored`; `No keyboard handling in Packages/OpencodeKit/Sources or App (no keyboardLayoutGuide or keyboard notifications)`; `iphone/composer-queue.png: with the keyboard up (~335 pt), the timeline shrinks to the space above the queue panel and composer`
- What happens: iPhone, idle session, scrolled to the bottom so the end of the agent's reply is visible. The user taps the composer to answer. Keyboard avoidance shrinks the collection by about 300 pt from the bottom. contentSize is unchanged, so no follow runs, and contentOffset is kept, so the last ~300 pt of the reply leave the viewport. Typing several lines grows the editor from 60 to 180 pt and hides more. A write-error line appearing under the timeline does the same.
- Why it matters: Users lose sight of exactly what they are replying to and must scroll while the keyboard is up.
- Fix: In TimelineCollectionView.layoutSubviews, also track bounds.size. When the height shrinks and the view was at the bottom (distance under 80 pt, or following), keep the bottom pinned (offset += oldHeight − newHeight, clamped) right away, without the 100 ms debounce. CodeCollection already reveals the bottom after viewport changes (m4-audit), so the same approach applies.
- Also reported as: F24-06 by touch-gestures-motion

<a id="f08-05"></a>

## F08-05: Expanded tool groups, diff cards, 'Thinking' and 'Show all' collapse again after the row scrolls away and back

*P2 bug · state · effort M · found by timeline-mechanics*

- Where: `FeatureTranscript/TimelineCollection.swift:73-76`, `OCDesign/TimelineChrome.swift:24-28`, `FeatureTranscript/TurnChangesCard.swift:12-15`, `FeatureTranscript/ToolRowView.swift:15-16`, `OCDesign/MarkdownBlockView.swift:59-68` (+1 more)
- Evidence: `TimelineCollection.swift:73-76: a reused cell is configured with 'TimelineHostedRow(...).id(id)'; the new id discards every @State in the row`; `TimelineChrome.swift:24 '@State private var expanded: Bool' is initialised from the detail preset (line 28) and has no external store`; `docs/m4-audit.md:118 notes that StreamingMarkdownView repeated work 'whenever virtualized timeline cells were reused'`
- What happens: In Compact, expand 'Used 3 Read, Glob, Grep' (or a diff card, a 'Thinking' block or a turn's 'Show all'), scroll a couple of screens and come back: it is collapsed. Its cell was reused for another item, and the returning row gets a fresh OCToolChrome. Each reuse also discards the parsed markdown: StreamingMarkdownView lays out a hidden raw-text placeholder, re-parses, then resizes, which can shift content while scrolling up. The shell output model restarts. If a Revert or Fork from the row's context menu fails after the row was reused, the error goes to discarded @State and the alert never shows.
- Why it matters: Users lose the tool output they opened, scroll-up can jitter, and a failed action is silent.
- Fix: Keep row UI state outside the cell: a per-session disclosure store (a Set of expanded row and child IDs) owned by SessionTimeline and passed through the environment, with OCToolChrome taking an optional Binding. Cache parsed MarkdownBlocks per ContentItemModel (keyed by item ID and text hash). Report row action failures through store.writeError.
- Verifier's note: Model the store on the desktop's disclosure map: keys like `${groupKey}:tool:${id}`, reasoning part IDs and `patch:${path}`, held per session and passed to OCToolChrome as an optional Binding.
- Also reported as: F05-03 by timeline-rows, F06-08 by tool-rows-files, F07-14 by tool-rows-exec, F27-04 by ui-performance

<a id="f08-06"></a>

## F08-06: Opening a session at a pending request (Inbox 'Review', deep link) turns auto-follow off and shows 'Jump to latest' while already at the bottom

*P2 bug · ux-flow · effort S · found by timeline-mechanics*

- Where: `FeatureTranscript/SessionTimeline.swift:66-71`, `FeatureTranscript/TimelineCollection.swift:125-130`, `FeatureTranscript/TimelineCollection.swift:170`, `OCSync/SessionSummary.swift:20-27`
- Evidence: `SessionTimeline.swift:70 'control.show(target); nearBottom = false; pendingScrollDone = true'`; `TimelineCollection.swift:170 'func show(_ id: String) { following = false; pendingID = id; ... }'`; `SessionSummary.swift:22-26: Inbox refs carry the permission or form ID as requestID; the matching pendingInput row is always at the end of the timeline`
- What happens: From the Inbox, tap Review on a permission (or follow a link that names the request). scrollToItem(.centeredVertically) for the last row lands at the bottom, but following is false and the pill appears, taking 60 pt. The user taps Allow and the agent resumes, but the transcript no longer follows; new rows only raise the pill count until the user drags to the bottom or taps the pill.
- Why it matters: The core approve-and-watch loop (and M5b's notification route) looks frozen and needs an extra tap.
- Fix: After performPending, measure the distance to the bottom. If it is under the 80 pt threshold, set following = true and call atBottom(true). Pause following only when the target is above the last screen, and resume once the request row disappears if the user has not scrolled.
- Verifier's note: Interacts with F05-01: once permission rows leave the timeline, permission targets disappear. Question and 'error' targets still need this fix.

<a id="f08-08"></a>

## F08-08: Reading position is lost when the timeline width or detail level changes (iPad rotation, review panel, Stage Manager, detail menu)

*P2 bug · ipad · effort M · found by timeline-mechanics*

- Where: `FeatureTranscript/TimelineCollection.swift:94`, `FeatureTranscript/TimelineCollection.swift:105-109`, `FeatureTranscript/TimelineCollection.swift:178-181`, `OCRender/TimelineRowBuilder.swift:44`
- Evidence: `The anchor is captured and restored only inside update() (lines 94 and 105-109), and only when its top-level ID still exists: 'self.ids.firstIndex(of: anchor.id)'`; `layoutSubviews (line 180) reacts only to contentSize and never re-anchors after a bounds change`; `docs/design.md D1.1: opening review narrows the timeline to 450 pt`
- What happens: (a) iPad, scrolled up reading a turn: tap a file in its Changes card. The review panel opens and the timeline narrows from about 740 to 450 pt, so every row re-wraps taller while contentOffset stays the same; the tapped card ends up far below the viewport. Rotation and Stage Manager resizing do the same. (b) Switch Everything to Compact while scrolled up: the first visible row (a tool row) now sits inside a 'group:' row, the anchor lookup returns nil, and no restore happens. The content above collapses, so the viewport lands much later in the session.
- Why it matters: Users lose their place in long transcripts during routine iPad actions and detail changes.
- Fix: Keep a live anchor (first visible item and offset) updated while scrolling. When layoutSubviews sees a width change, restore it after layout. For detail changes, map the anchor to the group whose children contain it, or fall back to the nearest surviving message-level row such as the prompt ID.
- Verifier's note: Resolve the anchor through TimelineRow.children in both directions: a child ID maps to its group, and a group ID maps to its first child.

<a id="f08-10"></a>

## F08-10: TranscriptModel.replace is quadratic and runs on the main actor on every open and resync

*P3 bug · performance · effort S · found by timeline-mechanics*

- Where: `OCSync/TranscriptModel.swift:93-104`, `OCSync/ReadResync.swift:97-99`
- Evidence: `TranscriptModel.swift:98 'for row in rows where !next.contains(row.id)' and :103 'messages = messages.filter { next.contains($0.key) }', where 'next' is a [String]`; `fetchSplice returns the whole local prefix plus the fresh page, so replace receives the entire loaded history`; `renderedFiveThousandRowsAndPrependAnchor builds its model through init and upsert, so this path is never timed`
- What happens: A session whose history was paged back to a few thousand messages (paged rows are cached and restored on the next open). Each open, reconnect or return to the foreground runs refreshSession, then replace. That costs about n²/2 string comparisons twice: roughly 25 M for 5,000 messages, on the main actor, while the user tries to scroll or type.
- Why it matters: A hitch at exactly the moments users return to the app or open a long session; 5,000 rows is the documented budget size.
- Fix: Track membership with a Set (append to `next` and insert into `seen`), filter `messages` with that Set, and skip upsert for rows whose raw JSON is unchanged.

<a id="f08-11"></a>

## F08-11: Opening a long session briefly shows the oldest loaded messages, then jumps to the end

*P3 bug · visual · effort S · found by timeline-mechanics*

- Where: `FeatureTranscript/TimelineCollection.swift:102-112`, `FeatureTranscript/TimelineCollection.swift:157-166`, `FeatureTranscript/TimelineCollection.swift:34`
- Evidence: `The first apply's completion calls 'followLatest()', which waits 'Task.sleep(for: .milliseconds(100))' before scrollLatest, so the collection renders at offset 0 in between`; `Every item uses '.estimated(100)', so the first scrollLatest targets an estimated bottom, and re-measured bottom cells trigger another debounced jump through sizeChanged`; `ARCHITECTURE §3.1 intended 'defaultScrollAnchor(.bottom)'`
- What happens: Tap a session with more than a screen of history. The first 50-message page appears from its top for at least 100 ms (about 6 frames, plus row-build time), then snaps to the bottom, and often makes a second smaller snap once the estimated heights resolve.
- Why it matters: A visible flash and jump on every open of a real session.
- Fix: For the first non-empty apply, scroll to the end synchronously in the completion (layoutIfNeeded, then scrollToItem(last, .bottom), then repeat once after measurement) without the debounce. Alternatively, hide the collection (alpha 0) until it is positioned.

<a id="f08-13"></a>

## F08-13: Tapping 'Jump to latest' during a fling does nothing, and its count is not a count of new messages

*P3 bug · interaction · effort S · found by timeline-mechanics*

- Where: `FeatureTranscript/TimelineCollection.swift:119-120`, `FeatureTranscript/TimelineCollection.swift:168`, `FeatureTranscript/SessionTimeline.swift:40-51`, `OCDesign/TimelineChrome.swift:101`
- Evidence: `scrollLatest: 'guard let view, !applying, !view.isDragging, !view.isDecelerating else { return }', and jumpToLatest calls it directly`; `crops/timeline-mechanics/tools-bottom.png: the pill sits in a band outside the collection, so tapping it never stops a deceleration`; `SessionTimeline.swift:50 'else if unseen == 0 { unseen = 1 }'`
- What happens: Fling up, then tap the pill while the list is still gliding. scrollLatest returns early, and again on the 100 ms retry. nearBottom = true hides the pill, then the next deceleration callback sets following = false and the pill comes back, so the tap is lost. Separately, '(1)' appears when only the last row's text grew. Tool rows, groups, permission cards and rows rebuilt by a detail change all count as 'new'. VoiceOver reads 'Jump to latest (3)' with no unit.
- Why it matters: An unreliable control for getting back to the live output, and a count that misleads.
- Fix: In jumpToLatest, stop deceleration first with `view.setContentOffset(view.contentOffset, animated: false)` and scroll without the guard. Count new messages, or show 'New activity' with no number, and reset the count on detail changes. Label it 'Jump to latest, 3 new messages'.
