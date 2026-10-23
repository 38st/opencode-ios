# UI review: Session actions and confirmations

Part of the [UI review](README.md). 9 bugs and 3 improvements, bugs first, then by severity. Paths under `Packages/OpencodeKit/Sources` are written without that prefix.

| ID | Severity | Finding |
| --- | --- | --- |
| [F12-02](#f12-02) | P2 bug | Deleting shows 'Opening session…' while the request runs, a late completion pops whatever session is open, and failures leave a sticky server-wide error |
| [G06-M1](#g06-m1) | P2 bug | Undo last message does nothing, and Fork from message lists no prompts, when the last prompt is older than the loaded 50-row page |
| [F12-04](#f12-04) | P2 bug | The prompt-row Revert message / Fork from here menu is shadowed by the text's own Select text / Copy menu |
| [F12-05](#f12-05) | P3 bug | Renaming with an empty title, as the alert suggests, blanks the title everywhere until the server regenerates it |
| [F12-06](#f12-06) | P3 bug | 'N messages reverted' counts internal rows: one Undo shows '4 messages reverted', an unloaded boundary shows '0', and 'Redo last message' restores everything |
| [F12-07](#f12-07) | P3 bug | Prompt-row actions report a user's Cancel as an error, and are offered on unsent outbox prompts, where Revert duplicates the prompt |
| [F12-08](#f12-08) | P3 bug | Undo, Rename and Compact run in view-owned tasks with no progress; leaving mid-Undo stops the agent and reverts nothing |
| [F12-09](#f12-09) | P3 bug | Fork from message sheet: no progress, Cancel doesn't cancel, errors hidden behind the sheet, no empty state, raw wire text, no whole-session fork |
| [F12-13](#f12-13) | P3 bug | With the keyboard up, the Send long-press menu floats about 300 pt above the composer and duplicates the visible Queue button |
| [F12-10](#f12-10) | P3 improvement | Session menu items ignore session state: Undo, Fork and Compact are enabled with no prompts, and Undo silently stops a running agent |
| [F12-12](#f12-12) | P3 improvement | Confirmation sheets on iPad are centred cards of varying widths with a drag grabber, have no Return/Esc keys, and stack Cancel on top at large text |
| [F12-14](#f12-14) | P3 improvement | Delete confirmation copy repeats itself and omits the consequences |

<a id="f12-02"></a>

## F12-02: Deleting shows 'Opening session…' while the request runs, a late completion pops whatever session is open, and failures leave a sticky server-wide error

*P2 bug · state · effort M · found by session-actions*

- Where: `OCSync/SessionWriteActions.swift:41-62`, `FeatureComposer/SessionActions.swift:43-53`, `FeatureTranscript/SessionScreen.swift:57`, `FeatureTranscript/SessionScreen.swift:72-76`, `FeatureTranscript/SessionScreen.swift:79` (+3 more)
- Evidence: `SessionWriteActions.swift:44-45 removes the family from 'sessions' before 'writeAPI().send(WriteEndpoints.delete(id))'`; `SessionScreen.swift:74: 'OCEmptyState(error == nil ? "Opening session…" : "Session unavailable", detail: error ?? "Loading the conversation from your server." …)'`; `SessionWriteActions.swift:60: 'catch { self.writeError = WriteErrorMessage.message(error) … }'. writeError is cleared only in flushWrites (WriteStore.swift:133) or by approval replies` (+1 more)
- What happens: Confirm Delete session on a slow tunnel or with an unreachable server.
  - While waiting: the sheet closes and the screen shows 'Opening session… Loading the conversation from your server.' with the title 'Session', for up to the 30 s request timeout.
  - If the user opens another session meanwhile, the late success runs sessionPath = [] and closes it.
  - On failure: the session reappears, but SessionActions was torn down and rebuilt, so its alert never shows. The only feedback is small red text under the timeline. That text is store-wide (readPath.writeError), so it appears under every session of the server until an unrelated outbox drain or approval clears it.
- Why it matters: A destructive action shows a misleading loading state, can navigate the user out of an unrelated session, and leaves a stale error on every session.
- Fix: Keep the session on screen in a 'Deleting…' state, or pop immediately and report failure in a toast. Only navigate in the completion if the deleted session is still the one displayed. Report delete errors in a dismissible alert or toast scoped to that action, not in the shared writeError.
- Verifier's note: In the completion, check that sessionPath.last?.sessionID is still the deleted id before clearing it, and stop putting delete failures in the shared writeError.

<a id="g06-m1"></a>

## G06-M1: Undo last message does nothing, and Fork from message lists no prompts, when the last prompt is older than the loaded 50-row page

*P2 bug · functional · effort M · found by verifier G06*

- Where: `OCSync/SessionWriteActions.swift:172`, `OCSync/SessionWriteActions.swift:175`, `FeatureComposer/SessionActions.swift:61`, `OCSync/ReadResync.swift:191`, `OCNetworking/ReadEndpoints.swift:56` (+1 more)
- Evidence: `SessionWriteActions.swift:172-175: 'let users = transcript.snapshot.filter { $0.type == "user" }' … 'guard let target else { return }'. Only loaded rows are searched, and when nothing is found it returns with no error`; `ReadEndpoints.messages defaults to limit 50 (ReadEndpoints.swift:56), and fetchSplice loads only the newest page when there is no local window (ReadResync.swift:191-193)`; `research/01-opencode-server-api.md:678: V2 projects one assistant row per step, so a turn of about 50 steps fills the page` (+1 more)
- What happens: Let the agent run a long task from the desktop, about 50 steps or more after the last prompt, then open the session on iPhone. The timeline loads the newest 50 rows and shows "Load earlier messages"; none of them is a user prompt. Tap ··· > Undo last message: nothing happens. There is no interrupt, no revert and no message. Fork from message opens an empty list, and typing / no longer offers /undo or /fork.
- Why it matters: Undo is the main way to recover when an agent goes wrong. It fails silently after exactly the long runs where users most want to roll back, and they can't tell whether anything happened.
- Fix: When no user row is loaded, fetch the newest user message with ReadEndpoints.messages(id, limit: 1, type: "user"); the endpoint already supports `type`. Stage the revert at it, or show an error if the session really has no prompt. Build the fork list from a paged type=user query, and compute hasPrompts from the session rather than from the loaded window.

<a id="f12-04"></a>

## F12-04: The prompt-row Revert message / Fork from here menu is shadowed by the text's own Select text / Copy menu

*P2 bug · interaction · effort S · plausible, needs a running app to confirm · found by session-actions*

- Where: `FeatureTranscript/TimelineRowView.swift:47-51`, `FeatureTranscript/TimelineRowView.swift:62-68`, `FeatureComposer/SessionActions.swift:128`, `OCDesign/TextSelection.swift:11-17`, `docs/design.md:112`
- Evidence: `SentPrompt: 'OCPromptText(styledText).ocSelectableText(input.text)'. On iOS 26, ocSelectableText adds '.contextMenu { Button("Select text"); Button("Copy") }'; on iOS 27 it adds '.textSelection(.enabled)'`; `The row's '.contextMenu { Copy; Revert message; Fork from here }' is attached to the enclosing HStack, so the only area outside the text is the 12 pt (OCSpacing.md) padding ring`; `grep: no UI or snapshot test references 'Revert message' or 'Fork from here'`
- What happens: On iOS 26.4+, long-press the text of an earlier prompt to revert to it. The inner menu (Select text, Copy) appears instead. Revert message and Fork from here appear only if the press lands on the bubble's 12 pt padding. The Spacer beside the bubble is not hit-testable. On iOS 27, long-pressing the text starts text selection instead. VoiceOver focuses the inner Text element, so the row-level actions are probably not exposed at all.
- Why it matters: 'Revert to a message', a core desktop action that design.md says is reachable from the prompt-row menu, is effectively hidden. Users have to repeat Undo once per prompt.
- Fix: Use one menu per prompt. Drop ocSelectableText on SentPrompt and add 'Select text' to the row menu (or move Revert and Fork into the inner menu). Add .accessibilityActions for Revert message and Fork from here. Add a UI test that long-presses the prompt text.
- Also reported as: F05-09 by timeline-rows, F24-07 by touch-gestures-motion, F26-08 by swiftui-state

<a id="f12-05"></a>

## F12-05: Renaming with an empty title, as the alert suggests, blanks the title everywhere until the server regenerates it

*P3 bug · state · effort S · found by session-actions*

- Where: `FeatureComposer/SessionActions.swift:38-42`, `OCSync/SessionWriteActions.swift:29-40`, `OCModels/SessionInfo.swift:9`, `FeatureTranscript/SessionScreen.swift:79`, `FeatureTranscript/SessionScreen.swift:161` (+3 more)
- Evidence: `Alert message: "Leave the title empty to generate a new one."`; `SessionWriteActions.swift:33: 'session.info["title"] = .string(title); pendingTitles[id] = title', applied optimistically even for ""`; `SessionInfo.title returns "" for an empty string; every display uses 'title ?? "Untitled session"', which only catches nil` (+1 more)
- What happens: Choose Rename, clear the field and tap Save. The client writes "" immediately. The inline nav title, the iPad header, and the inbox and sidebar rows go blank, and the delete sheet reads 'Delete session ""?'. This lasts until session.renamed arrives from background title generation, or indefinitely if generation fails or never runs. Whitespace-only input is sent as a real title, and Save stays enabled with the title unchanged.
- Why it matters: Sessions appear nameless in every list and header, so users cannot find or identify them.
- Fix: For empty input, keep the previous title (optionally show 'Generating title…') rather than setting "". Treat empty or whitespace titles as missing wherever they are displayed. Trim input before sending, and disable Save when the title is unchanged.

<a id="f12-06"></a>

## F12-06: 'N messages reverted' counts internal rows: one Undo shows '4 messages reverted', an unloaded boundary shows '0', and 'Redo last message' restores everything

*P3 bug · copy · effort S · found by session-actions*

- Where: `FeatureComposer/ComposerDock.swift:259-270`, `OCSync/TranscriptModel.swift:110-118`, `FeatureComposer/SelectionOptions.swift:42-43`, `OCModels/ComposerSuggestions.swift:48-49`, `OCSync/SessionWriteActions.swift:85-88`
- Evidence: `iphone/composer-revert-confirmation.png ('4 messages reverted' after undoing one prompt, 'Queued with attachment', and its reply)`; `ipad/ipad-composer-revert-confirmation.png`; `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-revert-light-393-default.png shows '0 messages reverted' with Redo` (+1 more)
- What happens: Undo one prompt. The notice reads '4 messages reverted' because it counts user, assistant-step, idle and notice rows; a multi-step agent turn gives larger numbers. When the boundary row is outside the loaded 50-row page (a long turn, or a revert staged on the desktop), it reads '0 messages reverted', although the rows are hidden by the ID fallback and Send asks to discard them. After two Undos, 'Redo last message' (DELETE /revert) brings back both prompts.
- Why it matters: Before the 'Discard reverted messages?' step, users cannot tell how much work they are about to discard, and the Redo label misdescribes what it does.
- Fix: Count reverted user prompts using the same ID fallback as visibleOrder, e.g. '1 prompt and its reply reverted · files restored'. Relabel Redo as 'Restore reverted messages' (or 'Redo all') and update the slash-command descriptions to match.
- Verifier's note: Count user rows whose id is >= the boundary; ID ordering works even when the boundary row isn't loaded.
- Also reported as: F37-14 by sweep-composer-snapshots

<a id="f12-07"></a>

## F12-07: Prompt-row actions report a user's Cancel as an error, and are offered on unsent outbox prompts, where Revert duplicates the prompt

*P3 bug · functional · effort S · found by session-actions*

- Where: `FeatureTranscript/TimelineRowView.swift:130-137`, `FeatureTranscript/TimelineRowView.swift:44-46`, `FeatureComposer/PendingInputPanel.swift:72-81`, `OCSync/DraftReplacement.swift:18-21`, `OCSync/WriteErrorMessage.swift:37` (+3 more)
- Evidence: `TimelineRowView.run: 'if case .failure(let failure) = result { actionError = WriteErrorMessage.message(failure) }'. It has no isCancellation filter, unlike PendingInputPanel.swift:79`; `DraftReplacement: 'guard confirmed else { throw CancellationError() }'; WriteErrorMessage maps that to "The action was cancelled."`; `undo() calls writeRestoredInput(…append: false) before cancelPending, whose guard 'outboxEntries[itemID] == nil' throws requestUnavailable for outbox items, which materializeOutbox puts in session.pending`
- What happens: (1) With text in the composer, choose Revert message on a prompt and tap Cancel in 'Replace your draft?'. An alert appears: 'Could not complete action — The action was cancelled.' (2) On a prompt still in the outbox (badge 'Sending', 'Edit and resend' or 'Waiting for confirmation'), Revert message copies the prompt into the composer, then fails with 'This input is no longer available…'. The outbox copy still sends, so sending the composer duplicates it. Fork from here sends the server a message ID it does not know. (3) The failed-prompt badge says 'Edit and resend', which reads as an action but cannot be tapped; the real button is in the panel above the composer.
- Why it matters: A deliberate cancel produces an error alert, and prompts can be sent twice.
- Fix: Skip WriteErrorMessage.isCancellation failures in TimelineRowView.run. Hide Revert and Fork for rows whose ID is in store.outboxEntries, offering Edit and resend or Discard instead. In undo(), cancel the pending item before replacing the draft. Rename the badge to a state such as 'Not sent'.

<a id="f12-08"></a>

## F12-08: Undo, Rename and Compact run in view-owned tasks with no progress; leaving mid-Undo stops the agent and reverts nothing

*P3 bug · state · effort S · found by session-actions*

- Where: `FeatureComposer/SessionActions.swift:59`, `FeatureComposer/SessionActions.swift:84-96`, `OCSync/SessionWriteActions.swift:170-187`, `OCSync/SessionWriteActions.swift:29-40`, `OCSync/SessionWriteActions.swift:55-62`
- Evidence: `SessionActions: '.onDisappear { task?.cancel() }' and 'guard task == nil else { return }'`; `undo(): interrupt(resume: false), then waitForIdle, then stageRevert, then writeRestoredInput`; `Delete was deliberately moved to a store-owned task ('Optimistic removal dismisses the requesting view, so the store owns this task'), but the other actions were not`
- What happens: Choose Undo last message while the agent runs. The app interrupts the run and then waits for idle, with no spinner and no disabled menu; tapping Undo or Compact again is silently ignored. If the user goes back on iPhone, or picks another session in the iPad sidebar, during the wait, the task is cancelled after the interrupt but before stageRevert: the run is stopped, nothing is reverted, and the prompt is not restored. Rename has the same exposure: leaving right after Save cancels the PATCH, and the optimistic title silently reverts.
- Why it matters: Actions are half-applied or lost, and the user gets no feedback either way.
- Fix: Run undo, redo, rename and compact through store.performWrite, as delete already does. While an action is in flight, show progress (e.g. disable ··· and show an 'Undoing…' notice).

<a id="f12-09"></a>

## F12-09: Fork from message sheet: no progress, Cancel doesn't cancel, errors hidden behind the sheet, no empty state, raw wire text, no whole-session fork

*P3 bug · ux-flow · effort M · found by session-actions*

- Where: `FeatureComposer/SessionActions.swift:54-83`, `FeatureComposer/SessionActions.swift:93-96`, `OCSync/SessionWriteActions.swift:189-194`, `OCModels/ComposerInput.swift:51-60`
- Evidence: `Row action: 'run { let next = try await store.forkFromMessage(...); forking = false; opened(next.id) }'; Cancel only sets 'forking = false'`; `The 'Could not complete action' alert is attached to the same view that presents the fork sheet (SessionActions.swift:54-57)`; `Rows show 'Text(message.fields.text)', the wire text, which includes line-comment notes with absolute paths` (+1 more)
- What happens: Tap a message in 'Fork from message':
  - Nothing visibly happens while the request runs.
  - Tapping Cancel dismisses the sheet, but the fork completes and still navigates to the new session.
  - On failure, error is set on the presenting view, so the alert cannot appear over the sheet and the tap looks ignored.
  - In a session with no prompts, the sheet is an empty list.
  - Commented prompts show their note text.
  - Nothing explains that the fork keeps the history before the chosen message and puts that message in the composer; the row menu's 'Fork from here' suggests the opposite.
  - There is no option to fork the entire session.
- Why it matters: The flow is confusing and can navigate unexpectedly; failures are invisible.
- Fix: While forking, disable the list and show progress. Make Cancel cancel the task. Present errors inside the sheet. Add a ContentUnavailableView for sessions with no prompts. Render ComposerInput.restoreText or displayText instead of the wire text. Add an 'Entire session' row (fork without before) and a one-line explanation of what a fork contains.
- Also reported as: F26-10 by swiftui-state

<a id="f12-13"></a>

## F12-13: With the keyboard up, the Send long-press menu floats about 300 pt above the composer and duplicates the visible Queue button

*P3 bug · interaction · effort S · found by session-actions*

- Where: `FeatureComposer/ComposerDock.swift:209-225`, `FeatureComposer/SelectionOptions.swift:25-33`
- Evidence: `iphone/composer-send-menu.png: the lifted Send preview and menu sit at about y=500 pt over the transcript, while the composer (with an empty Send slot) is about 300 pt lower, roughly the keyboard height`; `The menu's first item 'Queue' repeats the 'Queue' button already visible beside Send`; `Implemented as '.contextMenu { SendOptions(...) }' on the Send button`
- What happens: While the agent runs, type a follow-up (keyboard up) and long-press Send. The keyboard hides and the composer drops to the bottom, but the lifted Send button and its menu ('Queue', 'Interrupt and send') stay where the button was, floating mid-transcript. 'Interrupt and send' has no hardware-keyboard shortcut and no visible hint that it exists.
- Why it matters: The menu looks broken and detached, and its options are hard to discover.
- Fix: Use `Menu { … } primaryAction: { send() }` for a button-anchored menu without a lifted preview. Drop the duplicate alternate item, or keep it and add icons. Add an accessibility action and a shortcut such as ⌥⌘↩ for Interrupt and send.

<a id="f12-10"></a>

## F12-10: Session menu items ignore session state: Undo, Fork and Compact are enabled with no prompts, and Undo silently stops a running agent

*P3 improvement · ux-flow · effort S · found by session-actions*

- Where: `FeatureComposer/SelectionOptions.swift:35-47`, `FeatureComposer/SessionActions.swift:26`, `OCModels/ComposerSuggestions.swift:56-61`, `OCSync/SessionWriteActions.swift:175`, `OCSync/SessionWriteActions.swift:181`
- Evidence: `Only Redo is gated: '.disabled(!canRedo)'`; `The slash list already hides undo, compact and fork when there are no prompts ('hasPrompts') and hides redo without a staged revert`; `undo(): 'guard let target else { return }' (silent no-op); '_ = try await interrupt(sessionID, resume: false)'`
- What happens: In a new or empty session:
  - 'Undo last message' does nothing and says nothing.
  - 'Fork from message' opens an empty sheet.
  - 'Compact session' sends a compaction request.

  While the agent is working, 'Undo last message' (and the row's Revert message) stops the run at once, without a confirmation. Nothing says that file changes are rolled back too, or that the prompt returns to the composer.
- Why it matters: Dead-end menu items, and an unexpected interruption of running work.
- Fix: Pass hasPrompts and running into SessionMenuOptions, matching ComposerCommand.available. Disable Undo, Fork and Compact when there are no prompts. While the agent is running, relabel Undo as 'Stop and undo last message' or confirm first. Add menu subtitles, e.g. 'Restores files and puts the prompt back in the composer'.
- Verifier's note: Don't compute hasPrompts only from the loaded window. Long turns push the last prompt out of the 50-row page, and Undo would then be disabled even though prompts exist (see the missed finding about pagination).

<a id="f12-12"></a>

## F12-12: Confirmation sheets on iPad are centred cards of varying widths with a drag grabber, have no Return/Esc keys, and stack Cancel on top at large text

*P3 improvement · ipad · effort S · found by session-actions*

- Where: `OCDesign/ConfirmationSheet.swift:13-33`, `OCDesign/Surfaces.swift:59`, `docs/design.md:112`
- Evidence: `ipad/ipad-composer-delete.png (card measured at 360 pt wide)`; `ipad/ipad-composer-replace-draft.png (481 pt)`; `ipad/ipad-composer-revert-confirmation.png (about 634 pt)` (+2 more)
- What happens: On iPad landscape, the three confirmations appear as centred cards 360, 481 and about 634 pt wide, each topped by a bottom-sheet grabber. With a hardware keyboard, Return does not confirm and Esc does not cancel, so the user must reach for the screen (for example after Send triggers 'Discard reverted messages?'). At accessibility5 on iPhone, the vertical stack puts Cancel above the destructive button, the reverse of iOS alert order. This revisits design.md's 'Confirmations are sheets sized to their content'.
- Why it matters: The same component looks inconsistent on iPad, keyboard users get friction, and the button order is off-convention.
- Fix: On regular width, use a fixed form width (`.presentationSizing(.form)`, or `.alert` / `.confirmationDialog`) and hide the drag indicator. Add `.keyboardShortcut(.cancelAction)` to Cancel and `.keyboardShortcut(.defaultAction)` to the confirm button. In the vertical layout, put the destructive button first and Cancel last.
- Also reported as: F31-12 by visual-polish-ipad

<a id="f12-14"></a>

## F12-14: Delete confirmation copy repeats itself and omits the consequences

*P3 improvement · copy · effort S · found by session-actions*

- Where: `FeatureComposer/SessionActions.swift:44-45`
- Evidence: `iphone/composer-delete.png: title 'Delete session', body 'Delete session "Renamed composer (fork #1)"?', button 'Delete session'`; `ipad/ipad-composer-delete.png`
- What happens: The title, body and button repeat 'Delete session'. The copy never says the deletion is permanent and happens on the server, or that project files on the computer are not touched. The subagent clause depends on `store.family(...)`, so it is omitted when the children failed to load.
- Why it matters: For an action that cannot be undone, users get no information about what they lose or keep.
- Fix: Title: 'Delete “\<title>”?'. Body: 'The conversation is permanently removed from \<server>. Files in \<project> are not changed.', plus 'Its N subagent sessions are deleted too.' Button: 'Delete'.
- Also reported as: F29-05 by ux-writing
