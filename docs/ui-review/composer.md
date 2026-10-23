# UI review: Composer

Part of the [UI review](README.md). 17 bugs and 7 improvements, bugs first, then by severity. Paths under `Packages/OpencodeKit/Sources` are written without that prefix.

| ID | Severity | Finding |
| --- | --- | --- |
| [F09-02](#f09-02) | P1 bug | Edit and resend, then Discard on the failed row, leaves the composer unable to send in that session |
| [F09-01](#f09-01) | P2 bug | Dark mode: the enabled Send/Stop button uses the wrong colour token and looks disabled (2.7:1 glyph) |
| [F22-03](#f22-03) | P2 bug | Hidden-indicator horizontal scrollers push controls off-screen at accessibility sizes (composer variant/model chips, Files viewer actions, tab close buttons) |
| [F28-05](#f28-05) | P2 bug | Background failures are silently dropped: ReadStore.error is never shown, so a failed 'Interrupt and send' interrupt goes unreported |
| [F37-03](#f37-03) | P2 bug | @ and / suggestion list is capped at 220 pt, so accessibility sizes show only about 1.5 suggestions |
| [F37-06](#f37-06) | P2 bug | Capability warning, composer error and 'Edit and resend' label are centred in the editor stack, not leading-aligned |
| [F37-07](#f37-07) | P2 bug | 'Waiting for confirmation' outbox row truncates the prompt to about 20 characters and breaks 'confirmat/ion' at accessibility5 |
| [G05-M1](#g05-m1) | P2 bug | Typing a built-in slash command (/compact, /undo, /new) and tapping Send sends it to the agent as plain text |
| [F09-13](#f09-13) | P2 bug | Attachment imports show no progress, swallow typing, and can be silently cancelled or rejected |
| [F09-04](#f09-04) | P3 bug | Delivery options ignore shell and slash-command modes: Queue dead-ends and Interrupt and send doesn't interrupt |
| [F09-05](#f09-05) | P3 bug | Outbox rows label every text-less entry 'New session', including photo-only prompts and compactions |
| [F24-08](#f24-08) | P3 bug | An icon-only × in the pending-input panel permanently discards unsent prompts, and whole pending sessions, with one tap |
| [F25-08](#f25-08) | P3 bug | Counts and plurals are hand-built: “0 messages reverted”, “Connecting (attempt 0)”, “Last 1 transitions”, and English plural words passed in as arguments |
| [F29-12](#f29-12) | P3 bug | VoiceOver labels misdescribe controls: comment chips, Send vs Queue, permission copy buttons and the review toggle |
| [F21-12](#f21-12) | P3 bug | Composer suggestion list: the active item and the list opening are visual only |
| [F37-11](#f37-11) | P3 bug | Suggestion rows render as separate rounded tiles with notches between them, not one list card |
| [G16-M2](#g16-m2) | P3 bug | The composer freezes silently during shell, server-command and Stop requests: typing is dropped and nothing shows progress |
| [F09-06](#f09-06) | P2 improvement | Queue and outbox rows don't say what state they are in or why a prompt failed |
| [F09-12](#f09-12) | P2 improvement | While a run is active and the prompt has text, there is no touch path to Stop, and Interrupt and send hides behind a long-press |
| [F09-11](#f09-11) | P3 improvement | iPad: the dock and queue panel stretch across the whole pane while messages are capped at 640 pt |
| [F21-14](#f21-14) | P3 improvement | Per-item controls use generic or wrong names, and placeholders are read twice |
| [F22-07](#f22-07) | P3 improvement | Prompt editor keeps a fixed 180pt maximum, so at AX5 only about 2½ lines of the prompt are visible |
| [F27-14](#f27-14) | P3 improvement | savedPrompts sorts and JSON-decodes every outbox body on each access, and the pending panel reads it up to five times per render |
| [F27-12](#f27-12) | P3 improvement | Every keystroke converts and scans the whole prompt about ten times, including a JSON encode of the draft on the main thread |

<a id="f09-02"></a>

## F09-02: Edit and resend, then Discard on the failed row, leaves the composer unable to send in that session

*P1 bug · state · effort S · found by composer-dock*

- Where: `FeatureComposer/PendingInputPanel.swift:51-57`, `OCSync/SessionWriteActions.swift:157-159`, `OCSync/SessionWriteActions.swift:195-199`, `OCSync/ComposerModel.swift:195`, `OCSync/WriteStore.swift:192-213` (+1 more)
- Evidence: `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-failed-light-393-default.png: the failed row puts 'Edit and resend' beside the × Discard button`; `ComposerModel.swift:195 'if let failed = self.options.editingOutboxID { admitted = try await store.editAndResend(failed, input: input, prelude: prelude) }'`; `WriteStore.swift:209 'guard let entry = outboxEntries[id], entry.state == "failed" else { throw WriteStoreError.requestUnavailable }'` (+1 more)
- What happens: A prompt is rejected with a 4xx (for example 401 after a credential change, or 409). The panel shows '\<text> · Edit and resend · ×'. The user taps Edit and resend: the text moves into the composer under a centred 'Edit and resend' label, and the failed row stays. The user taps × to clear the old row. Every Send now calls editAndResend for the discarded ID and fails with 'This input is no longer available. It may already have been handled.' The ID is saved in the draft's options, so the session stays stuck after navigation and relaunch. The label has no Cancel. Only an unrelated restore (Undo on a queued prompt, Undo last message, Fork) clears it.
- Why it matters: Sending is blocked in that session. The error text suggests the prompt may already have been delivered, so the user may believe it was sent.
- Fix: In submit, fall back to sendPrompt when the editingOutboxID entry no longer exists or is no longer failed. In discardOutbox and the acknowledgement paths, clear editingOutboxID on that session's composer. Turn the 'Edit and resend' label into a leading-aligned banner with a Cancel button that clears editingOutboxID. Optionally hide the row's × while its prompt is being edited.
- Verifier's note: Clear editingOutboxID on that session's composer in discardOutbox and whenever the entry is acknowledged or no longer failed. In submit, fall back to sendPrompt when the entry is missing or no longer failed; a failed entry was never delivered, so this cannot send a duplicate. Give the 'Edit and resend' label leading alignment and a Cancel button. Add a ComposerReviewTests case for restore, then discard, then send.

<a id="f09-01"></a>

## F09-01: Dark mode: the enabled Send/Stop button uses the wrong colour token and looks disabled (2.7:1 glyph)

*P2 bug · accessibility · effort S · found by composer-dock*

- Where: `FeatureComposer/ComposerDock.swift:214-220`, `OCDesign/Colors.swift:25-26`, `OCDesign/Resources/Colors.xcassets/oc2-contrast.colorset/Contents.json`
- Evidence: `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-typing-dark-393-default.png: enabled Send is a #5C5C5C fill with a #161616 arrow`; `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-idle-dark-393-default.png: disabled is a #3D3D3D fill and the arrow is barely visible`; `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-stop-dark-393-default.png: Stop uses the same #5C5C5C` (+4 more)
- What happens: Dark appearance, any width. Type a prompt: Send is a #5C5C5C square on the #242424 dock (2.32:1) with a #161616 arrow (2.71:1). With an empty prompt the disabled button is #3D3D3D (1.43:1), so enabled and disabled differ by one grey step, and the enabled button is darker than the official app's own disabled button. Stop (running, empty prompt) uses the same colours. Light mode is fine: #242424 with a white arrow when enabled, a #8F8F8F square when disabled.
- Why it matters: In dark mode the primary action looks unavailable. On iPhone, Return on the touch keyboard inserts a newline, so this button is the only way to send. Both the control and its glyph fail WCAG 1.4.11 (3:1 minimum for non-text contrast).
- Fix: Add an iconButtonContrast token from v2-background-bg-icon-button-contrast (light #242424, dark #DBDBDB). Use it for the Send/Stop fill with the textInverse glyph, which gives 13:1 in dark mode. Draw the disabled state as the same colours at reduced opacity, as the reference does, instead of relying on the plain button style's dimming. Re-record the dark dock snapshots and compare them with m3b-dock-*-dark.
- Verifier's note: Add a new iconButtonContrast token (light #242424, dark #DBDBDB) rather than changing oc2-contrast, which other contrast buttons share. Keep textInverse for the glyph, which gives about 12:1 in dark mode. Draw the disabled state explicitly (the same colours at reduced opacity) instead of relying on the .plain style's dimming. Then re-record the dark dock-* snapshots.
- Also reported as: F20-04 by design-system, F23-02 by contrast-dark-mode, F37-01 by sweep-composer-snapshots, F38-13 by sweep-approval-server-snapshots

<a id="f22-03"></a>

## F22-03: Hidden-indicator horizontal scrollers push controls off-screen at accessibility sizes (composer variant/model chips, Files viewer actions, tab close buttons)

*P2 bug · layout · effort M · found by a11y-dynamic-type*

- Where: `FeatureComposer/ComposerDock.swift:186-207`, `FeatureFiles/FilesScreen.swift:34-45`, `FeatureFiles/FilesScreen.swift:167-174`, `OCDesign/WorkspacePanel.swift:25-27`, `OCDesign/Controls.swift:93`
- Evidence: `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-idle-light-393-accessibility5.png: the selector row reads 'Build · Mock 1 · Defau', with the variant chip hard-clipped at the edge. Every dock-*-393-accessibility5 image shows the same.`; `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.files-markdown-light-393-accessibility5.png: the bar shows 'Mention in compose' cut off. The 'Source' toggle and the tab's × close button, both visible in the -default image, are off-screen. Crop: crops/a11y-dynamic-type/files-markdown-a5-top.png`; `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.files-source-light-393-accessibility5.png: there is no close button for the open Example.swift tab.` (+1 more)
- What happens: iPhone at AX5:

  - **Composer:** the agent/model/variant row is a horizontal ScrollView with hidden indicators. The variant chip is cut to 'Defau'. With a real model name the model chip alone overflows and the variant picker is completely invisible.
  - **Files:** opening README.md shows a cut 'Mention in compose' button and no visible Source/Preview toggle or Cancel. Open-file tabs lose their close buttons.
  - **Review panel:** the tab strip is an OCSegmentedControl with equalWidth: false, which never stacks, so 'Files' is half off-screen next to 'Files Changed N'.

  Nothing indicates that more content exists.
- Why it matters: These controls exist but large-text users can't discover them. The variant shortcut (⇧⌘D) needs a hardware keyboard.
- Fix: At accessibility sizes, stack instead of scrolling horizontally:
  - Composer: one choice per row, or a single 'Agent · Model · Variant' menu.
  - Files viewer: fold Find, Mention, Source/Preview and Cancel into one overflow Menu.
  - OCSegmentedControl: stack it, or switch to a Picker menu, when it isn't equal-width.

  At minimum, show scroll indicators and a trailing fade.
- Also reported as: F18-08 by files-browser, F36-07 by sweep-review-snapshots, F37-10 by sweep-composer-snapshots

<a id="f28-05"></a>

## F28-05: Background failures are silently dropped: ReadStore.error is never shown, so a failed 'Interrupt and send' interrupt goes unreported

*P2 bug · state · effort S · found by states-coverage*

- Where: `OCSync/ReadStore.swift:23`, `OCSync/ReadStore.swift:165-172`, `OCSync/ReadStore.swift:191`, `OCSync/ReadStore.swift:222`, `OCSync/ComposerModel.swift:197` (+2 more)
- Evidence: `'owned': 'catch { self?.error = "Could not refresh server data." }'`; `grep: no view in Feature* or App reads 'readPath.error' or 'store.error' from ReadStore (only 'writeError' is shown)`; `interruptAfterAdmission runs '_ = try await self.interrupt(sessionID, resume: true)' inside 'owned {}'` (+1 more)
- What happens: On a flaky connection, long-press Send → 'Interrupt and send'. The steer is admitted, but the follow-up interrupt POST fails. The store records 'Could not refresh server data.', which no view displays, so the agent keeps running its current step and the user is never told. The same silence covers event-driven session refetches after a sequence gap (the transcript may be missing rows), catalog refreshes after config or credential events, and cache saves.
- Why it matters: An explicit user action quietly fails, and repairs that keep data correct can fail with no sign. Even if it were shown, the stored message describes the wrong problem.
- Fix: Surface ReadStore.error through a per-server, non-blocking banner with Retry, and give each owned operation its own message. Send the interrupt failure to the composer, for example 'Sent, but the current run could not be interrupted · Stop'.

<a id="f37-03"></a>

## F37-03: @ and / suggestion list is capped at 220 pt, so accessibility sizes show only about 1.5 suggestions

*P2 bug · accessibility · effort S · not verified · found by sweep-composer-snapshots*

- Where: `FeatureComposer/ComposerDock.swift:236-245`
- Evidence: `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-context-light-393-accessibility5.png: the list is 220 pt tall, only '@docs' is fully visible, and '@review / Review the' is cut through its glyphs`; `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-commands-dark-393-accessibility5.png`; `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-context-dark-820-accessibility5.png and capture-_-name-fixedHeight.dock-commands-light-820-accessibility5.png: about 2.3 rows on iPad` (+2 more)
- What happens: At accessibility5 on iPhone or iPad, the user types '@' or '/'. Each row grows to about 150 pt (a label plus a two-line description), but the list stays 220 pt tall.
- Why it matters: Users with large text must scroll a tiny window one item at a time to pick a file, agent or command. The half-cut row looks broken.
- Fix: Scale the cap with Dynamic Type, either with @ScaledMetric or as a fraction of the available height (for example 45%). Limit descriptions to one line at accessibility sizes, and align the row icon to the first text baseline.

<a id="f37-06"></a>

## F37-06: Capability warning, composer error and 'Edit and resend' label are centred in the editor stack, not leading-aligned

*P2 bug · layout · effort S · not verified · found by sweep-composer-snapshots*

- Where: `FeatureComposer/ComposerDock.swift:109`, `FeatureComposer/ComposerDock.swift:111`, `FeatureComposer/ComposerDock.swift:144-146`, `FeatureComposer/ComposerDock.swift:160`
- Evidence: `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-attachment-light-820-default.png: the warning spans x 167–652 pt, centred in the 16–804 pt dock, while the chip text starts at 32 pt and the prompt at 34 pt`; `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-attachment-light-393-default.png: the warning starts at x 48 pt against 32 and 34 pt for the chip and prompt`; `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-attachment-dark-820-accessibility5.png` (+1 more)
- What happens: The user attaches a file the selected model cannot read. The same centring applies to any composer error (line 160) and to the 'Edit and resend' heading shown while editing a failed prompt (line 111).
- Why it matters: On iPad the warning floats mid-dock like centred body copy, detached from the attachment it refers to. On iPhone it sits 14–16 pt right of the chip and the prompt.
- Fix: Use VStack(alignment: .leading, spacing: 0) for editorContent, or give these Texts .frame(maxWidth: .infinity, alignment: .leading). Use the editor's text inset (12 pt plus 5 pt line-fragment padding) so warning, error, revert notice and prompt share one leading edge.

<a id="f37-07"></a>

## F37-07: 'Waiting for confirmation' outbox row truncates the prompt to about 20 characters and breaks 'confirmat/ion' at accessibility5

*P2 bug · layout · effort S · not verified · found by sweep-composer-snapshots*

- Where: `FeatureComposer/PendingInputPanel.swift:46-58`, `FeatureComposer/PendingInputPanel.swift:62-68`
- Evidence: `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-confirmation-light-393-default.png: 'Review the saved prom…' sits beside a two-line 'Waiting for / confirmation', Send and ×`; `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-confirmation-light-393-accessibility5.png and capture-_-name-fixedHeight.dock-confirmation-dark-393-accessibility5.png: 'Waiting / for / confirmat / ion'`; `PendingInputPanel.swift:54 'Text("Waiting for confirmation").font(OCType.micro)' has no muted colour, unlike 'Sending' at line 50. Controls share one HStack (line 65) even at accessibility sizes.`
- What happens: On iPhone, after a relaunch, OutboxDrain marks an old saved prompt as needsConfirmation and the panel shows it above the composer.
- Why it matters: Users cannot tell which prompt they are being asked to send, and at large text sizes the status breaks inside a word. The two outbox states are also styled inconsistently: muted for 'Sending', primary for 'Waiting'.
- Fix: Move the state to a muted second line under the prompt text (or a badge), and keep only Send and Discard at the trailing edge. At accessibility sizes, stack the controls with ViewThatFits.

<a id="g05-m1"></a>

## G05-M1: Typing a built-in slash command (/compact, /undo, /new) and tapping Send sends it to the agent as plain text

*P2 bug · functional · effort S · found by verifier G05*

- Where: `FeatureComposer/ComposerDock.swift:214`, `FeatureComposer/ComposerDock.swift:278-284`, `FeatureComposer/ComposerDock.swift:328-338`, `OCSync/ComposerModel.swift:185-196`, `OCSync/ComposerModel.swift:246-251`
- Evidence: `ComposerModel.swift:185 '} else if let command = self.serverCommand(input.text) {'. serverCommand (:246-251) matches only names in catalog.commands, the server's commands. Typed client commands (new, undo, redo, compact, fork, model, agent) therefore fall through to 'store.sendPrompt' (:196).`; `Client commands run only through ComposerDock.select(_:) (:328-338), reached by tapping a row or by hardware Return/Tab (:367). The Send button (:214) calls send() → model.submit without checking the open command list.`; `docs/design.md:73: touch Return inserts a newline, so on a touch keyboard tapping the row is the only way to run these commands.` (+1 more)
- What happens: iPhone, touch keyboard, a session with earlier prompts. Type '/compact'. The list shows '/compact · Summarize the session to reduce context size' highlighted. Tap the Send arrow, as for any message. submit() finds no server command named 'compact', so it sends the user message '/compact' to the agent, which answers or acts on its own reading of it, and no compaction happens. '/undo' reaches the agent as an instruction it may carry out itself, for example by reverting files. '/new' and '/model' send text instead of opening a new session or the model picker.
- Why it matters: Built-in commands seem not to work on iPhone. Each attempt costs a model turn, and the agent may take actions the user meant the app to perform.
- Fix: In send() or submit(), when the trimmed text is exactly '/\<name>' for a client command available in the current context, run it through the same path as select(_:) instead of sending. Alternatively, while the command list is open with rows, make Send accept the highlighted row as hardware Return does. Optionally confirm before sending a '/word' that matches no command.

<a id="f09-13"></a>

## F09-13: Attachment imports show no progress, swallow typing, and can be silently cancelled or rejected

*P2 bug · interaction · effort M · found by composer-dock*

- Where: `FeatureComposer/ComposerDock.swift:76-92`, `FeatureComposer/ComposerDock.swift:154`, `FeatureComposer/ComposerDock.swift:160`, `FeatureComposer/ComposerDock.swift:173-185`, `FeatureComposer/ComposerDock.swift:355-360` (+6 more)
- Evidence: `ComposerModel.swift:122 'busy = true; defer { busy = false }' wraps AttachmentProcessing.prepare and storeAttachment; setText has 'guard !busy' (:73); PromptEditor.swift:88 has 'guard parent.enabled else { return false }'`; `ComposerDock.swift:390 'action?.cancel(); action = Task { … catch is CancellationError {} … }' is shared by the photo, file, paste and drop imports and by stop()`; `AttachmentProcessing.swift:24 rejects anything over 20 MiB before the 2,000 px downscale, and ComposerMedia.read checks the file size first` (+1 more)
- What happens:
  - Pick several iCloud or 48 MP photos: the picker closes and nothing appears until each has downloaded and been downscaled.
  - Keys typed while each item processes are rejected silently.
  - Pasting an image, or pressing Esc or ⌘. (Stop), during the import cancels the remaining items with no message.
  - A ProRAW photo or large panorama is refused with 'Each attachment must be 20 MiB or smaller.', although it would be downscaled anyway. That error stays under the editor until the next send.
  - With text already in the draft, + > Commands appends ' /', which never opens the command list because the trigger only matches a draft that starts with '/'. None of the + items focus the editor.
- Why it matters: The dock seems unresponsive, typed characters and chosen attachments are lost without notice, and one menu item does nothing.
- Fix:
  - Insert a placeholder chip with a spinner for each selected item immediately; replace it, or mark it failed, when processing ends.
  - Keep the editor editable during processing and block only Send.
  - Run imports in their own queue instead of cancelling the shared action task.
  - For images, check the size after downscaling.
  - Clear the error when the draft changes.
  - Make Commands replace an empty draft or open the command list directly, and call requestFocus() after + actions.
- Verifier's note: From F10-13: busy also covers the network wait of shell and server commands (SessionWriteActions.swift:19-28), so typing is dropped there too. Snapshot the draft at send time and keep the editor editable, blocking only Send. The '+ > Commands' item is tracked in F10-07.
- Also reported as: F10-13 by prompt-editor

<a id="f09-04"></a>

## F09-04: Delivery options ignore shell and slash-command modes: Queue dead-ends and Interrupt and send doesn't interrupt

*P3 bug · functional · effort S · found by composer-dock*

- Where: `FeatureComposer/ComposerDock.swift:210-213`, `FeatureComposer/ComposerDock.swift:221-225`, `OCModels/ComposerSuggestions.swift:113-118`, `OCSync/ComposerModel.swift:155`, `OCSync/ComposerModel.swift:183-197`
- Evidence: `ComposerSuggestions.swift:116 'if shell && delivery == .queue { return .unqueueable }', which leads to ComposerModel.swift:155 'error = "This prompt cannot be queued"'`; `ComposerDock.swift:210 hides the inline alternate in shell mode, but the context menu at :221-225 has no shell check`; `ComposerModel.swift:197 'if interrupt { store.interruptAfterAdmission(...) }' appears only in the prompt branch; the shell branch (:184) and the server-command branch (:185-192) ignore the interrupt flag` (+1 more)
- What happens: With a run active:
  (a) Follow-up behavior is set to Queue. In shell mode, type 'npm test' and tap Send: the result is 'This prompt cannot be queued'. The inline Steer button is hidden in shell mode, so the only way out is the hidden long-press.
  (b) With the default Steer setting, long-pressing Send in shell mode offers 'Queue', which always fails with the same message.
  (c) 'Interrupt and send' with a shell command or a server slash command such as '/check foo' runs it without interrupting the run.
- Why it matters: Controls the UI offers either fail with an error about an action the user didn't choose, or quietly do something other than their label.
- Fix: Deliver shell commands as steer regardless of the Queue preference, or show the inline alternate in shell mode. Build SendOptions per mode: hide Queue for shell commands. For shell and server commands, either hide Interrupt and send or implement it by calling interrupt(resume: true) once the request is accepted. If an error is still needed, word it as 'Shell commands can't be queued. Send now?' with an action.
- Verifier's note: Leave Queue out of SendOptions in shell mode. Deliver shell commands as steer whatever the Queue preference is, or show the inline Steer alternate in shell mode. For shell and server commands, either implement Interrupt and send by calling interrupt(resume: true) after the request is accepted, or hide it.

<a id="f09-05"></a>

## F09-05: Outbox rows label every text-less entry 'New session', including photo-only prompts and compactions

*P3 bug · copy · effort S · found by composer-dock*

- Where: `FeatureComposer/PendingInputPanel.swift:48`, `OCSync/SavedPrompt.swift:14-18`, `OCNetworking/WriteEndpoints.swift:55-58`, `OCSync/SessionWriteActions.swift:195-196`
- Evidence: `PendingInputPanel.swift:48 'Text(item.text.isEmpty ? "New session" : item.text)'; queue rows show 'Attachments' for the same case (:38)`; `SavedPrompt.swift:16-17 decodes the outbox body as PromptInput and falls back to an empty string. A compact body is only {id, delivery}, and an attachment-only prompt has empty text.`; `SessionWriteActions.swift:196 restoreFailedPrompt requires 'entry.operation == "prompt"'` (+1 more)
- What happens: Offline or on a slow link, send a photo-only prompt or run /compact (Compact session). The panel shows 'New session · Sending'. If the compaction is later rejected with a 4xx, the row becomes 'New session · Edit and resend · ×'. Tapping Edit and resend fails with 'This input is no longer available. It may already have been handled.'
- Why it matters: Users think a stray session is being created, and the recovery button on a failed compaction can never succeed.
- Fix: Label rows by SavedPrompt.operation and payload: create → 'New session', compact → 'Compact session', a prompt with no text → '1 image' or 'Attachments', matching queueRow. Offer Edit and resend only when operation is "prompt"; offer Retry or Discard for the other operations.

<a id="f24-08"></a>

## F24-08: An icon-only × in the pending-input panel permanently discards unsent prompts, and whole pending sessions, with one tap

*P3 bug · interaction · effort S · found by touch-gestures-motion*

- Where: `FeatureComposer/PendingInputPanel.swift:42`, `FeatureComposer/PendingInputPanel.swift:43`, `FeatureComposer/PendingInputPanel.swift:57`, `OCSync/WriteStore.swift:192`, `FeatureTranscript/SavedPromptReview.swift:26`
- Evidence: `iphone/composer-queue.png: Steer · ↶ (Undo, restores to the composer) · × (Remove, restore: false) side by side, 4 pt apart`; `OCIconButton("Discard", icon: "outline-xmark") { run { try await store.discardOutbox(item.id) } }`; `For a failed 'create', discardOutbox removes the session and all of its outbox entries` (+1 more)
- What happens: A prompt fails to send, or a new-session create fails. The row shows 'Edit and resend' and a ×. Tapping the ×, which means close or dismiss elsewhere in the app, immediately and irreversibly deletes the typed prompt. For a failed create it deletes the pending session and every saved prompt in it. In queue rows, × (delete) sits 4 pt from ↶ (restore).
- Why it matters: One mis-tap loses typed work, with no confirmation and no undo.
- Fix: Use a destructive-tinted trash icon or a text 'Discard' button with a confirmation dialog. Spell out 'Discard session and saved prompts' for creates, or show a short Undo toast. Move Remove away from Undo, for example into a ··· menu.
- Verifier's note: The strongest cases are Discard on a needs-confirmation create and the pending-steer Delete in the transcript (TimelineRowView.swift:56). Add an Undo toast or a confirmation there.

<a id="f25-08"></a>

## F25-08: Counts and plurals are hand-built: “0 messages reverted”, “Connecting (attempt 0)”, “Last 1 transitions”, and English plural words passed in as arguments

*P3 bug · copy · effort M · found by l10n-text*

- Where: `FeatureComposer/ComposerDock.swift:261`, `FeatureComposer/ComposerDock.swift:266`, `FeatureTranscript/TurnChangesCard.swift:23`, `OCRender/TimelineRowBuilder.swift:43`, `OCRender/TimelineRowBuilder.swift:91` (+4 more)
- Evidence: `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-revert-light-393-default.png shows “0 messages reverted” (a revert is staged but its boundary message is not in the loaded transcript, so revertedCount returns 0)`; `iphone/diagnostics.png shows “Connecting (attempt 0)”; the retry detail counts from 1 ("Attempt \(count)")`; `ComposerDock.swift:261 Text("\(revertedCount) \(revertedCount == 1 ? "message" : "messages") reverted") becomes the key "%lld %@ reverted", whose %@ is an untranslatable String; TurnChangesCard.swift:23 has the same shape` (+3 more)
- What happens: Open a session that has a staged revert before the transcript page containing its boundary loads: the composer header reads “0 messages reverted”. After a first launch, open Settings, a server, then Connection diagnostics: the list shows “Connecting (attempt 0)”.
- Why it matters: Some of this copy is wrong today. None of it can be translated: Russian, Polish and Arabic need several plural forms, and a separately interpolated “message”/“messages” word cannot agree with its number.
- Fix: Use one key per phrase with the count as its argument and plural variants, or ^[\(count) message](inflect: true). Show “Messages reverted” when the count is unknown. Number attempts from 1. Format durations with Duration.formatted(.units(width: .narrow)).

<a id="f29-12"></a>

## F29-12: VoiceOver labels misdescribe controls: comment chips, Send vs Queue, permission copy buttons and the review toggle

*P3 bug · accessibility · effort S · found by ux-writing*

- Where: `FeatureComposer/ComposerDock.swift:126`, `FeatureComposer/ComposerDock.swift:212`, `FeatureComposer/ComposerDock.swift:219`, `FeatureApprovals/PermissionSheet.swift:76`, `FeatureTranscript/SessionScreen.swift:49` (+1 more)
- Evidence: `ComposerDock.swift:126: the line-comment chip's × is OCIconButton("Remove attachment"), which also becomes its pointer tooltip through .help`; `ComposerDock.swift:211-212: the alternate button is titled Queue or Steer, with accessibilityHint “Send without interrupting” in both cases. Line 219: the main button's label is always “Send”, although it steers while a run is active.`; `PermissionSheet.swift:76: the copy button label is built as “Copy ” + title.lowercased(), giving “Copy allow always saves these patterns in this project”` (+2 more)
- What happens: VoiceOver, in a running session with text typed:
  - The alternate button reads “Queue, button, Send without interrupting”, and the arrow reads “Send”. A steer doesn't interrupt either, so the user can't tell what the two buttons do differently.
  - The × on a review comment chip reads “Remove attachment”.
  - The permission sheet's last copy button reads a whole sentence.
  - The review control is called “Review panel” on iPhone and “Toggle review” on iPad.
- Why it matters: VoiceOver users can't choose between steering and queueing before they send, and hear the wrong object names in primary flows.
- Fix: Fix each label:
  - Main button while running: label “Send”, value “Steers into the current run” (or “Queues…”, per the setting).
  - Alternate button hint: “Sends after the current run finishes” for Queue, and “Sends to the agent now without stopping it” for Steer.
  - Comment chip ×: “Remove comment”.
  - Permission sheet copy buttons: explicit short labels such as “Copy patterns”.
  - Review control: one name on both devices (“Review panel”, with value open or closed).

<a id="f21-12"></a>

## F21-12: Composer suggestion list: the active item and the list opening are visual only

*P3 bug · accessibility · effort S · found by a11y-voiceover*

- Where: `FeatureComposer/ComposerDock.swift:241`, `FeatureComposer/ComposerDock.swift:362`, `FeatureComposer/PromptEditor.swift:215`
- Evidence: `ComposerDock.swift:241: .background(index == active ? OCColor.hover : OCColor.background) is the only marker of the active item; there is no .isSelected`; `ComposerDock.swift:362-368: Up / Down / Tab / Return drive 'active' and select(suggestions[active]) while focus stays in the text view, and nothing is announced`; `suggestionIcon (:250-257) is the only cue for agent / skill / reference` (+1 more)
- What happens: iPad with a hardware keyboard and VoiceOver. Typing '@ex' opens the list silently. Pressing Down moves the grey highlight to '@explore' but VoiceOver says nothing, so Return inserts an item the user never heard. Touch users aren't told that suggestions appeared above the editor, and an agent such as '@explore' isn't identified as an agent.
- Why it matters: Referencing files, agents and commands, a central composer feature, is guesswork for VoiceOver users.
- Fix: Announce 'N suggestions' when the list opens and the active item's label when it changes. Add .isSelected to the active row, and include the kind in its label ('explore, agent').

<a id="f37-11"></a>

## F37-11: Suggestion rows render as separate rounded tiles with notches between them, not one list card

*P3 bug · visual · effort S · not verified · found by sweep-composer-snapshots*

- Where: `FeatureComposer/ComposerDock.swift:240-246`
- Evidence: `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-context-dark-393-default.png: each row has its own ~12-pt corners. At x=16.5 pt the darker background shows through for about 16 pt at every row boundary (y≈52, 96–112, 140–156, 184–200 pt).`; `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-context-light-393-default.png and capture-_-name-fixedHeight.dock-commands-dark-820-default.png`; `scratch/sheets/sweep-composer-snapshots-suggestion-row-notches.png (contrast-boosted crop)` (+1 more)
- What happens: The user types '@' or '/', in either theme.
- Why it matters: The list reads as a stack of loose cards with seams at both edges, and the active highlight runs edge to edge, unlike the desktop list.
- Fix: Clip the scroll content once to RoundedRectangle(cornerRadius: OCRadius.dock). Give rows plain rectangular backgrounds (or none), and draw the active highlight as an inset rounded rectangle. Add the hairline border, and apply .compositingGroup() before .ocElevation(.floating) so a single shadow is drawn.

<a id="g16-m2"></a>

## G16-M2: The composer freezes silently during shell, server-command and Stop requests: typing is dropped and nothing shows progress

*P3 bug · state · effort S · found by verifier G16*

- Where: `OCSync/ComposerModel.swift:161-168`, `OCSync/ComposerModel.swift:183-192`, `FeatureComposer/ComposerDock.swift:154`, `FeatureComposer/ComposerDock.swift:184`, `FeatureComposer/ComposerDock.swift:207` (+4 more)
- Evidence: `ComposerModel.submit sets 'busy = true' (161) and keeps it until its Task ends. .stop calls store.interrupt (166-168), shell mode calls store.shell (184), and server slash commands call store.command (192). All are direct POSTs, not outbox writes, with a 30 s request timeout and no retry.`; `PromptEditor.Coordinator: 'guard parent.enabled else { return false }' (PromptEditor.swift:88), with enabled = model.loaded && !model.busy (ComposerDock.swift:154), so keystrokes are silently rejected.`; `busy only disables controls (ComposerDock.swift:184, 207, 220). Grep finds no spinner or label bound to busy in FeatureComposer.`
- What happens: The server is slow or unreachable, or a session still looks running while offline (F28-01). The user taps Stop, or sends `!git status` or `/review`. For up to 30 s the keyboard stays up but typed characters don't appear, and the + menu, model chips and Send/Stop do nothing. Nothing says a request is in progress. Then a red error appears in the dock.
- Why it matters: The app looks frozen in the most-used control, and users retype, tap repeatedly or force-quit.
- Fix: While a network-bound action runs, show a progress state in the dock ('Stopping…' or 'Running command…' with a spinner on the send button), and dim the editor instead of silently dropping keystrokes. Use a shorter timeout for interactive POSTs. When the server is known to be offline, fail fast with 'Waiting for \<server>' instead of waiting out the timeout.

<a id="f09-06"></a>

## F09-06: Queue and outbox rows don't say what state they are in or why a prompt failed

*P2 improvement · ux-flow · effort M · found by composer-dock*

- Where: `FeatureComposer/PendingInputPanel.swift:23`, `FeatureComposer/PendingInputPanel.swift:46-58`, `OCSync/OutboxDrain.swift:77-84`, `FeatureTranscript/SavedPromptReview.swift:6-49`, `FeatureTranscript/TimelineRowView.swift:45`
- Evidence: `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-failed-light-393-default.png: 'Review the saved prompt… | Edit and resend | ×' with no 'not sent' or error indicator`; `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-confirmation-light-393-default.png: 'Waiting for confirmation' in body colour, while 'Sending' is muted`; `iphone/composer-queue.png: a single queued row with no 'Queued' label (the 'N queued' header appears only above 3 rows)` (+2 more)
- What happens: When a prompt fails (for example 400 'model does not support PDF input', 401 or 409), the panel shows only the prompt text and an 'Edit and resend' button. The timeline badge also reads 'Edit and resend', an action name, as if it were a status. A prompt still unsent 10 minutes after it was saved shows 'Waiting for confirmation' at the next launch; this reads as waiting on the server when it is waiting for the user. One to three queued follow-ups appear as unlabelled bordered cards above the composer.
- Why it matters: Users can't tell queued from failed from stale input, or learn why a prompt failed, so they resend without fixing the cause.
- Fix: Give each row a leading status:
  - 'Queued'.
  - 'Sending…' with a spinner.
  - 'Not sent' in the danger tone, with the server's reason (keep the 4xx message on the outbox entry).
  - 'Not sent yet · saved 12 min ago' with a 'Send now' action.
  Always show a small 'Queued' header. Reuse the SavedPromptReview copy, or delete that dead view. In the timeline, use a 'Not sent' badge instead of the action text. This revisits the state labels listed in docs/design.md.
- Verifier's note: Store the 4xx message on the outbox entry and show it on the failed row. A needsConfirmation entry also blocks every newer prompt in that session (OutboxDrain.swift:42, WriteStore.swift:178-185), so newer rows keep saying 'Sending' although nothing is being sent. Label those rows as waiting behind the saved prompt. Either reuse SavedPromptReview's copy or delete that unused view.
- Also reported as: F04-14 by session-chrome, F29-10 by ux-writing, F37-08 by sweep-composer-snapshots

<a id="f09-12"></a>

## F09-12: While a run is active and the prompt has text, there is no touch path to Stop, and Interrupt and send hides behind a long-press

*P2 improvement · ux-flow · effort S · found by composer-dock*

- Where: `FeatureComposer/ComposerDock.swift:209-226`, `FeatureComposer/SelectionOptions.swift:25-33`, `FeatureComposer/PromptEditor.swift:215-217`
- Evidence: `iphone/composer-send-menu.png: the long-press menu offers only Queue and Interrupt and send`; `iphone/composer-queue.png: Stop appears only when the prompt is empty`; `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-alternate-light-393-default.png: an arrow button and 'Queue', with nothing saying that Send will steer` (+1 more)
- What happens: The agent is running the wrong command and the user has half-written a follow-up. To stop without sending they must delete or cut the draft so that Stop appears; mention tokens are lost if they paste it back. 'Interrupt and send' exists only behind a long-press, with no visual hint. The visible button names the other mode ('Queue'), so nothing explains that tapping Send injects the text into the running turn.
- Why it matters: On iPhone a runaway run can't be stopped quickly without losing the draft, and the key delivery modes are hard to discover.
- Fix: Add Stop as the first item in the Send context menu, and expose Stop and Interrupt and send as accessibility actions. Alternatively, show a small Stop button next to the alternate delivery button whenever a run is active. Turn the alternate button into a menu with a chevron ('Queue ▾': Queue / Interrupt and send / Stop), and add a one-time tip explaining Steer versus Queue. This revisits docs/design.md, which shows Stop only for an empty composer and puts Interrupt and send behind a long-press.
- Verifier's note: Add Stop to the header session-actions menu while a run is active, as the desktop's running menu does. Also make Stop the first item in the Send context menu and expose it as an accessibility action.

<a id="f09-11"></a>

## F09-11: iPad: the dock and queue panel stretch across the whole pane while messages are capped at 640 pt

*P3 improvement · ipad · effort S · found by composer-dock*

- Where: `FeatureTranscript/SessionScreen.swift:58-61`, `FeatureTranscript/TimelineCollection.swift:38`, `OCDesign/Metrics.swift:35`, `FeatureComposer/ComposerDock.swift:72-74`
- Evidence: `ipad/ipad-composer-queue.png: landscape with the sidebar open, the queue card and dock are about 875 pt wide while the transcript column is 640 pt (about 130 pt inset on each side)`; `.build/design-reference/composer-idle-light-1180x820.png and composer-queue-light-1180x820.png: the reference composer spans x 229–950 (722 pt), centred, with the queue row joined to it`; `.build/design-reference/composer-idle-light-1440x900.png: still 722 pt wide` (+1 more)
- What happens: On iPad in landscape, the placeholder starts at the pane edge and Send sits about 850 pt away. With the sidebar collapsed on a 13-inch iPad the dock is about 1,340 pt wide. A queue row's Steer, ↶ and × buttons sit far from its text. From code reading: the model picker popover is anchored to the whole dock, so its arrow points at the dock rather than the model chip.
- Why it matters: The composer doesn't line up with the conversation it belongs to, and the eye travels a long way between text and controls.
- Fix: Constrain the pending panel, approval dock and composer to the reference's 720 pt (or OCLayout.readable plus padding) and centre them. Join the queue rows to the composer surface as the reference does. Anchor the model popover to the model chip by moving .popover onto the button or setting an attachmentAnchor.
- Verifier's note: Constrain PendingInputPanel, ApprovalDock and ComposerDock to about 720 pt and centre them. Move .popover(isPresented: $showModels) onto the model chip button.
- Also reported as: F05-13 by timeline-rows, F19-12 by ipad-shell, F31-05 by visual-polish-ipad

<a id="f21-14"></a>

## F21-14: Per-item controls use generic or wrong names, and placeholders are read twice

*P3 improvement · accessibility · effort S · found by a11y-voiceover*

- Where: `FeatureComposer/ComposerDock.swift:126`, `FeatureComposer/ComposerDock.swift:150`, `OCDesign/ComposerChrome.swift:92`, `FeatureFiles/FilesScreen.swift:40`, `FeatureFiles/FilesScreen.swift:246` (+2 more)
- Evidence: `ComposerDock.swift:126: line-comment chips use OCIconButton("Remove attachment", …), which calls model.removeComment`; `ComposerChrome.swift:92: 'Remove attachment' carries the file name only as a hint. FilesScreen.swift:40: 'Close tab' doesn't name the file`; `PendingInputPanel.swift:42-43: a queued prompt offers 'Undo' (restores it to the composer) and 'Remove'` (+4 more)
- What happens: With two attachments and one line comment, VoiceOver reads 'Remove attachment, button' three times (with hints off), and one of them actually deletes a review comment. An empty composer reads 'Ask anything, / for commands, @ for context…' and then 'Prompt, text field'.
- Why it matters: Destructive buttons have ambiguous targets, and speech is redundant.
- Fix: Name the item: 'Remove comment on Example.swift lines 2-3', 'Remove photo.jpg', 'Close Example.swift', 'Edit queued prompt' / 'Delete queued prompt'. Hide visual placeholders from accessibility and expose them as the field's hint. Label images with their file name.

<a id="f22-07"></a>

## F22-07: Prompt editor keeps a fixed 180pt maximum, so at AX5 only about 2½ lines of the prompt are visible

*P3 improvement · layout · effort S · found by a11y-dynamic-type*

- Where: `OCDesign/ComposerChrome.swift:9-10`, `FeatureComposer/PromptEditor.swift:51-54`, `OCDesign/ComposerChrome.swift:59-68`, `FeatureComposer/ComposerDock.swift:148-152`, `FeatureComposer/ComposerDock.swift:245`
- Evidence: `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-typing-light-393-accessibility5.png: the third line 'existing behavior.' is cut through its descenders at exactly 180pt, directly above the selector row. Crop: crops/a11y-dynamic-type/dock-typing-a5-top.png`; `ComposerChrome.swift:61 sets minimumLineHeight = UIFontMetrics(.body).scaledValue(for: 20), about 62pt at AX5. (180 − 16 − 8) / 62 ≈ 2.5 lines.`; `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-context-light-393-accessibility5.png: the 220pt suggestion list (ComposerDock.swift:245) shows 1½ suggestions.`
- What happens: AX5 on iPhone or iPad, type or paste a prompt of 4 or more lines.

  - **Editor cap:** the editor stops growing at the documented 180pt (docs/design.md:68, '60–180-point editor'), but each line is now ~62pt. Only 2½ lines show, the last one clipped, with no scroll indicator. The cap applies even on iPad, where there is plenty of room.
  - **Suggestions:** the @ and / list is capped at 220pt, which fits about one item.
  - **Placeholder jump:** the placeholder uses OCType.small (footnote-relative, 44pt at AX5), while typed text is body-relative 40.5pt with 62pt lines, so the text jumps when typing starts.
- Why it matters: Large-text users can't review what they typed before sending. This revisits the fixed point range in docs/design.md.
- Fix:
  - Scale editorMinimum and editorMaximum with @ScaledMetric(relativeTo: .body), or set the maximum to about 4–5 scaled line heights plus insets. Cap it at roughly 35–40% of the available height.
  - Scale the 220pt suggestion cap the same way, and hide descriptions at accessibility sizes.
  - Draw the placeholder with the editor's own font and paragraph style.
- Verifier's note: Scale the maximum (and the 220pt suggestion cap) with @ScaledMetric, but clamp to a fraction of the available height (about 35%). The gain is mainly on iPad, or on iPhone without the keyboard.
- Also reported as: F37-13 by sweep-composer-snapshots

<a id="f27-14"></a>

## F27-14: savedPrompts sorts and JSON-decodes every outbox body on each access, and the pending panel reads it up to five times per render

*P3 improvement · performance · effort S · found by ui-performance*

- Where: `OCSync/SavedPrompt.swift:14-19`, `FeatureComposer/PendingInputPanel.swift:15-27`, `FeatureTranscript/TimelineRowView.swift:44-47`
- Evidence: `SavedPrompt.swift:15-16 'outboxEntries.values.sorted { ... }.map { entry in let input = try? JSONDecoder().decode(PromptInput.self, from: entry.body)'`; `PendingInputPanel.swift:16 and 19: 'rows', read three times in body, and 'saved', read up to twice, each call store.savedPrompts`; `TimelineRowView.swift:44: every user-prompt row calls it once per render, and those rows re-render on every transcript insertion because line 47 reads transcript.messages` (+1 more)
- What happens: Send a prompt with three photos over a flaky connection. While it shows Sending or Edit and resend, every PendingInputPanel render decodes all outbox bodies up to five times, and each visible prompt row decodes them again whenever a message is inserted.
- Why it matters: While attachment-heavy prompts are pending or failed, the main thread spikes in proportion to the attachment size.
- Fix: Cache decoded SavedPrompt summaries (id, text, state) in ReadStore whenever outboxEntries changes, decoding only the text field, and read the list once per body.
- Also reported as: G05-M2 by verifier G05

<a id="f27-12"></a>

## F27-12: Every keystroke converts and scans the whole prompt about ten times, including a JSON encode of the draft on the main thread

*P3 improvement · performance · effort M · found by ui-performance*

- Where: `FeatureComposer/ComposerDock.swift:43`, `FeatureComposer/ComposerDock.swift:57-71`, `FeatureComposer/ComposerDock.swift:153-155`, `FeatureComposer/ComposerDock.swift:209-222`, `OCModels/ComposerSuggestions.swift:9-28` (+6 more)
- Evidence: `ComposerDock.swift:43 'trigger' is a computed property: a String conversion, a UTF-16 array copy, two regexes, and an O(n) offset per mention. Body reads it three or four times (lines 57, 71, and twice at 155)`; `ComposerModel.swift:52 'blank' trims String(text.characters), and deliveryControls reads it up to five times (ComposerDock.swift:210-222)`; `PromptEditor.swift:41 'if Self.attributed(view.attributedText) != text' rebuilds an AttributedString, with a JSONDecoder per mention (line 60), on every update; textViewDidChange does it again (line 112)` (+1 more)
- What happens: Paste a 40 KB stack trace into the prompt and keep typing a question below it. Before SwiftUI and TextKit even lay it out, each keystroke runs about ten full-text conversions and scans, two regex passes, an AttributedString equality check and a JSON encode of the whole draft.
- Why it matters: Keystroke latency grows linearly with prompt length. This becomes noticeable with pasted logs, which are common in coding prompts.
- Fix: Read trigger and blank once per body into local constants, and scan only the text before the caret. In updateUIView, skip the round trip from native text to AttributedString by checking a revision counter that the coordinator sets. Move snapshot encoding into the debounced save, encoding inside the DraftStore actor after its 300 ms delay.
- Also reported as: F10-14 by prompt-editor
