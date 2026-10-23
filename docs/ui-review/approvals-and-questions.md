# UI review: Approvals and questions

Part of the [UI review](README.md). 19 bugs and 12 improvements, bugs first, then by severity. Paths under `Packages/OpencodeKit/Sources` are written without that prefix.

| ID | Severity | Finding |
| --- | --- | --- |
| [F13-01](#f13-01) | P2 bug | The same permission request appears 2 to 3 times on the session screen, each copy with its own Allow once |
| [F13-02](#f13-02) | P2 bug | Face ID cancel or failure closes the sheet first, then shows a misleading, sticky, server-wide error; the authenticating, sending and failed states never appear |
| [F13-03](#f13-03) | P2 bug | The approval dock always takes its 240 pt maximum, leaving a ~100 pt blank band above the composer and clipping the card's shadow |
| [F13-09](#f13-09) | P2 bug | VoiceOver: new requests are never announced, there are no headings, and Allow once buttons carry no context |
| [F14-03](#f14-03) | P2 bug | Choice rows show no radio or checkbox when unselected; the only selection cue is a fixed 16 pt check |
| [F14-04](#f14-04) | P2 bug | Custom 'Other' answers lose typed text: multiselect text is dropped unless 'Add answer' is tapped, and re-tapping Other clears a single-choice answer |
| [F14-08](#f14-08) | P2 bug | The review step shows option values instead of the labels the user picked ('unit' for 'Unit tests') |
| [F14-09](#f14-09) | P2 bug | When Review answers fails, nothing changes near the button: errors appear only on fields that may be scrolled out of view |
| [F14-10](#f14-10) | P2 bug | Global forms (sessionID 'global', such as MCP elicitations) are fetched and answerable but never shown anywhere |
| [F25-01](#f25-01) | P2 bug | Reject explanation says “this session’s 0 other pending requests” (and “1 other pending requests”) |
| [F14-07](#f14-07) | P2 bug | VoiceOver doesn't link form controls to their question, and doesn't speak required status or errors |
| [G12-M2](#g12-m2) | P2 bug | VoiceOver focus is stranded after approving or answering, because the focused control and its card are removed with nowhere for focus to go |
| [F13-11](#f13-11) | P3 bug | Reject step: copy says '0 other pending requests', the keyboard hides the Reject button, and the note is easy to lose |
| [F14-13](#f14-13) | P3 bug | Unsupported form fields are a dead end: raw JSON, a repeated error, and a primary button that can never succeed |
| [F25-05](#f25-05) | P3 bug | Question-form number fields reject the decimal comma and show integer answers with grouping (“8,080”) |
| [F25-09](#f25-09) | P3 bug | Labels and sentences are built by concatenation: VoiceOver hears “Copy allow always saves these patterns in this project”; the review menu lists “Reviewed \<path>” as an action |
| [F13-12](#f13-12) | P3 bug | When a request is answered on another device, the open sheet vanishes without explanation; 'Already handled' never shows |
| [F14-11](#f14-11) | P3 bug | Clearing a field never returns it to 'unanswered': an emptied optional text field fails validation and cleared defaults are submitted anyway |
| [F14-14](#f14-14) | P3 bug | Submit and Dismiss close the sheet before the server replies; the sending and failed states never appear and a typed dismiss reason is lost |
| [F13-06](#f13-06) | P2 improvement | The 'Allow always' scope shows a bare pattern such as '*' with no action or project, so users can't tell it approves every future read or edit |
| [F13-08](#f13-08) | P2 improvement | Reject and Allow sit after all content, so a long diff or multi-file patch pushes them screens below the top |
| [F29-04](#f29-04) | P2 improvement | Permission dock and sheet show the raw action id (“Shell”, “edit”, “External_directory”) instead of the desktop's plain-language description |
| [F32-07](#f32-07) | P2 improvement | The approval docks do less than the reference: questions need a sheet and 4 taps, and the permission dock has no Reject |
| [F33-01](#f33-01) | P2 improvement | Requests in other sessions are invisible while you are inside a session, and M5 presence will also suppress their pushes |
| [F13-07](#f13-07) | P2 improvement | Risk tiers mislabel common prompts: a .env read is 'Low risk', while built-in subagent, skill and question requests are 'High risk' and need Face ID |
| [F13-05](#f13-05) | P3 improvement | High risk is shown only by a small badge; the dock shows no tier, and the reason and Face ID requirement are hidden |
| [F14-05](#f14-05) | P3 improvement | Question entry points lead with generic 'Question'/'Questions' text instead of what the agent is asking |
| [F14-12](#f14-12) | P3 improvement | Constraints and formats stay hidden until validation fails, and format fields get a generic multi-line text box |
| [F24-09](#f24-09) | P3 improvement | No haptic feedback anywhere: approvals, sends, errors and the long-press line selection are silent |
| [F38-12](#f38-12) | P3 improvement | Approval sheets repeat their title: "Permission required" twice; Question / Question / Questions |
| [F13-14](#f13-14) | P3 improvement | The dock appears instantly where the user may be tapping, so a stray tap can approve a command |

<a id="f13-01"></a>

## F13-01: The same permission request appears 2 to 3 times on the session screen, each copy with its own Allow once

*P2 bug · ux-flow · effort S · found by approvals-permission*

- Where: `FeatureTranscript/TimelineProjection.swift:41-55`, `FeatureTranscript/TimelineRowView.swift:108-113`, `FeatureTranscript/TimelineRowView.swift:171-173`, `FeatureApprovals/ApprovalDock.swift:18-21`
- Evidence: `iphone/permission-dock.png: identical 'Permission required / Shell / printf ... / Review / Allow once' cards at y≈281-423 pt (transcript) and y≈468-609 pt (dock), separated only by 'Working…'`; `.build/design-compare/m3a-permission-dock.png: the reference shows the request once, in the dock only`; `Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/ReadSnapshots/capture-_-name-height.row-pendingInput-light-393.png: the pendingInput row was designed as a light 'Needs you' marker; with a store present the live app swaps in a full PermissionCard` (+1 more)
- What happens: iPhone, one pending shell request, Compact preset: the transcript tail renders the pendingInput row as a full actionable card, and the dock directly below shows the same card again. With the Detailed or Everything preset (shell and edit rows are separate), or after the user expands the 'Used N…' group, the matching tool row adds a third card through permissionForTool. Each card has its own Review button, Allow once button and sheet.
- Why it matters: About 140 pt of a small screen is spent on a duplicate. It suggests two requests are waiting, and VoiceOver users hear the request and its Allow once button two or three times.
- Fix: Keep the actions in one place (the dock). Render the .pendingInput permission row as the existing non-actionable 'Needs you' marker; it still works as the scroll target for Home's Review. On the matching tool row, show a small 'Waiting for approval' chip instead of a second PermissionCard. Optionally have Home's Review open the sheet directly.
- Verifier's note: Render .pendingInput rows, for permissions and forms alike, as the existing non-actionable 'Needs you' marker; it stays Home's scroll target. This also fixes F14-02. Replacing the inline tool-row card with a chip revisits ARCHITECTURE §3.3, so treat it as a separate decision, not part of this fix.
- Also reported as: F05-01 by timeline-rows, F08-03 by timeline-mechanics, F14-02 by approvals-question, F30-10 by visual-polish-iphone, F32-02 by design-parity, F33-04 by ux-flows-ia

<a id="f13-02"></a>

## F13-02: Face ID cancel or failure closes the sheet first, then shows a misleading, sticky, server-wide error; the authenticating, sending and failed states never appear

*P2 bug · state · effort M · found by approvals-permission*

- Where: `FeatureApprovals/PermissionSheet.swift:119-122`, `OCSync/ApprovalActions.swift:20-35`, `OCSync/ReadStore.swift:26`, `OCSecurity/BiometricGate.swift:11-16`, `FeatureTranscript/SessionScreen.swift:57`
- Evidence: `PermissionSheet.swift:120-121 'store.respondToPermission(request, decision: decision, message: note); dismiss()': the sheet closes before authentication starts`; `'.authenticating', '.sending' and '.failed' are only ever set in ApprovalSnapshots.swift:16-18; no app code assigns them`; `ApprovalActions.swift:25 'catch { self.writeError = "Permission reply was not sent. Review the request and try again." }' catches LAError.userCancel the same way as a network failure` (+1 more)
- What happens: Review > Allow always, or Allow once on a high-risk request. The sheet closes at once and Face ID appears over the session. Tapping Cancel leaves the request in the dock and adds red text above the composer: 'Permission reply was not sent. Review the request and try again.' writeError belongs to the server's ReadStore, so the text also shows in every other session of that server. It clears only after a later successful reply, outbox flush, resync or backgrounding. On a device with no passcode, .deviceOwnerAuthentication fails with passcodeNotSet every time: Allow always and high-risk Allow once can never succeed, and nothing says why.
- Why it matters: A deliberate cancel is reported as a failure, and users without a passcode hit an unexplained dead end. The in-sheet feedback that was designed and snapshot-tested ('Confirm with Face ID or passcode…', 'Sending reply…', 'Reply could not be sent') is dead code.
- Fix: Keep the sheet open: set state to .authenticating, then .sending, and await replyPermission in a store-owned task. Dismiss on success. Return to .review silently on userCancel, appCancel or systemCancel, and show .failed inline for other errors. Pre-check canEvaluatePolicy(.deviceOwnerAuthentication). When no passcode is set, explain it and disable Allow always and high-risk Allow once. Scope the approval error to the request or session instead of the server-wide writeError.
- Verifier's note: Keeping the sheet open revisits the documented optimistic dismissal. The minimal fix: classify the LAError raised by biometricGate.authenticate. Return silently on userCancel, appCancel and systemCancel. For passcodeNotSet or a lockout, show a specific message, and pre-check canEvaluatePolicy so the sheet can say that Allow always and high-risk Allow once need a device passcode. Scope the failure to the request or session instead of the server-wide writeError. Then either wire the authenticating, sending and failed states or delete them and their snapshots.
- Also reported as: F28-04 by states-coverage, F39-01 by privacy-security-ui

<a id="f13-03"></a>

## F13-03: The approval dock always takes its 240 pt maximum, leaving a ~100 pt blank band above the composer and clipping the card's shadow

*P2 bug · layout · effort S · found by approvals-permission*

- Where: `FeatureApprovals/ApprovalDock.swift:16-23`, `OCDesign/Metrics.swift:41`, `FeatureTranscript/SessionScreen.swift:59`
- Evidence: `iphone/permission-dock.png: dock card y≈468-609 pt (141 pt tall), composer surface starts at ≈720 pt (12 pt padding), so the dock frame runs 468 to 708 pt, exactly 240 pt`; `ApprovalDock.swift:23 '}.frame(maxHeight: OCLayout.approvalDockHeight)' on a greedy ScrollView`; `crops/approvals-permission/dock-edge.png: the dock card has no left or top shadow (pixels drop straight to 255), while the identical transcript card has a soft 18 px shadow`
- What happens: iPhone 17 Pro with one short request: an empty band of about 100 pt sits between the dock card and the composer, and the transcript loses the same space (it ends at about 455 pt). The ScrollView's bounds also cut off the raised card's elevation on the sides and top.
- Why it matters: The transcript, which is the context for the decision, shrinks to about 270 pt on iPhone. The blank band and the flat card look like a layout glitch.
- Fix: Size the dock to its content up to the cap, for example `ViewThatFits(in: .vertical) { cards; ScrollView { cards } }.frame(maxHeight: 240)`, or measure the content with onGeometryChange and use `.frame(height: min(content, 240))`. Add `.scrollBounceBehavior(.basedOnSize)`, and add inner padding or `.scrollClipDisabled()` so the shadow isn't clipped.
- Verifier's note: Reuse the composer's content-sized pattern (ComposerDock.swift:59-61: onGeometryChange plus .frame(idealHeight:maxHeight:) and .scrollBounceBehavior(.basedOnSize)) with the cap, and add .scrollClipDisabled() or inner padding for the shadow. F14-01's point about landscape and the keyboard supports a cap relative to the available height.
- Also reported as: F14-01 by approvals-question

<a id="f13-09"></a>

## F13-09: VoiceOver: new requests are never announced, there are no headings, and Allow once buttons carry no context

*P2 bug · accessibility · effort M · planned in M9a · found by approvals-permission*

- Where: `FeatureApprovals/ApprovalDock.swift:14-24`, `FeatureApprovals/ApprovalDock.swift:42`, `FeatureApprovals/ApprovalDock.swift:58-62`, `FeatureApprovals/PermissionSheet.swift:31`, `FeatureApprovals/PermissionSheet.swift:71-81` (+1 more)
- Evidence: `grep: Sources has no AccessibilityNotification, UIAccessibility.post or sensoryFeedback anywhere, and only three .isHeader traits`; `PermissionSheet.swift:73-77 puts the copy button before the values, and its label becomes 'Copy allow always saves these patterns in this project'`; `OCCopy.text only writes to UIPasteboard, with no visual, haptic or spoken confirmation`
- What happens: VoiceOver user, agent blocks on a permission: nothing is announced and there is no haptic; the dock appears silently above the composer. With several cards (or the duplicates in the first finding), VoiceOver reads several identical 'Allow once, button' entries without the command. In the sheet, 'Permission required' and the section titles are not headings. VoiceOver reads 'Action', then 'Copy action, button', then 'shell', and copying gives no confirmation.
- Why it matters: Blind users may not learn that the agent is waiting, and can't tell which request a button approves.
- Fix: Post an announcement when a request arrives (for example 'Permission needed: shell printf…') and add .sensoryFeedback. Mark the titles with .isHeader. Combine each section's title and values into one element with a 'Copy' accessibility action. Give the dock buttons labels such as 'Allow once: shell printf …'. Confirm copies with a short toast or haptic plus an announcement.
- Verifier's note: Besides announcing new requests, give the dock's Allow once an accessibilityLabel that includes the action and first resource. With F13-01 fixed there will be only one such button per request.

<a id="f14-03"></a>

## F14-03: Choice rows show no radio or checkbox when unselected; the only selection cue is a fixed 16 pt check

*P2 bug · design-parity · effort M · found by approvals-question*

- Where: `FeatureApprovals/FormRenderer.swift:111-122`, `FeatureApprovals/FormRenderer.swift:78-81`, `OCDesign/Icon.swift:17`, `OCDesign/Controls.swift:115-123`
- Evidence: `'OCIcon("check", size: 16).opacity(selected ? 1 : 0)'. OCIcon applies a fixed frame, so the check does not scale with Dynamic Type`; `Packages/OpencodeKit/Tests/ApprovalSnapshots/__Snapshots__/ApprovalSnapshots/capture-_-name.question-editing-light-393.png (accessibility5): the selected "Other" and the unselected "Light"/"Dark" have the same white fill and 1 px #CCCCCC border; only a thin tick at the top-left differs (crop: crops/approvals-question/editing-options-zoom.png)`; `.build/design-reference/question-light-393x852.png and .build/design-compare/m3a-question-sheet.png: the desktop dock shows a radio circle on every option` (+1 more)
- What happens: Any agent question on iPhone. Single-choice and multi-choice lists look identical apart from the small helper text. After a tap, the only change is a small tick. At accessibility5 the tick is about one sixth of the label height and sits above the baseline. Yes/No rows behave the same way.
- Why it matters: Users can't tell at a glance what they picked, or whether a list allows several choices. Low-vision users at large text sizes may miss the selection entirely. This departs from the desktop design the app reproduces.
- Fix: Always show an indicator: an empty radio circle (single choice) or square checkbox (multiselect) that fills when selected, sized with @ScaledMetric. Also give the selected row an accent border or tinted background. Consider a segmented control for boolean fields. Scale the switch and raise its off-state contrast.
- Also reported as: F20-05 by design-system, F30-05 by visual-polish-iphone, F32-03 by design-parity, F38-03 by sweep-approval-server-snapshots

<a id="f14-04"></a>

## F14-04: Custom 'Other' answers lose typed text: multiselect text is dropped unless 'Add answer' is tapped, and re-tapping Other clears a single-choice answer

*P2 bug · functional · effort M · found by approvals-question*

- Where: `FeatureApprovals/FormRenderer.swift:50`, `FeatureApprovals/FormRenderer.swift:52`, `FeatureApprovals/FormRenderer.swift:60`, `FeatureApprovals/FormRenderer.swift:104`, `FeatureApprovals/FormRenderer.swift:106` (+2 more)
- Evidence: `The multiselect custom TextField writes only to '@State customText' and has no onSubmit. Only the "Add answer" button copies the text into 'answers', and Review reads 'answers' only`; `Other's selected state for multiselect is 'custom.contains(key)': it is inserted on tap and never removed`; `Single-choice Other runs 'answers[f.key] = .string("")' on every tap` (+2 more)
- What happens: The agent asks a multi-choice question. The user taps Other, types "Use Redis", presses Return (the keyboard closes) and taps Review answers. The review leaves out "Use Redis", or fails with Required if nothing else was picked. Tapping Edit answers recreates the renderer, so the typed text and the open Other field are gone. The Other row also stays checked permanently although nothing is submitted for it. Added custom answers appear as half-width check buttons that delete themselves on tap, with no undo. In a single-choice question, typing "Sepia" under Other and then tapping Other again wipes it.
- Why it matters: The user's own answer is silently lost in the agent's main question flow, and the checked state misleads.
- Fix: Treat pending custom text as part of the answer: add it on Return (onSubmit) and when leaving the editing state. Let Other toggle off. Keep custom text in the parent or in drafts so it survives Review and Back. Don't reset a single-choice value when Other is already selected. Auto-focus the field when Other is chosen (the desktop makes the row itself the input). Render custom answers as selected rows with the isSelected trait and an explicit Remove.

<a id="f14-08"></a>

## F14-08: The review step shows option values instead of the labels the user picked ('unit' for 'Unit tests')

*P2 bug · functional · effort S · found by approvals-question*

- Where: `FeatureApprovals/QuestionSheet.swift:52`, `FeatureApprovals/QuestionSheet.swift:54`, `FeatureApprovals/QuestionSheet.swift:55`
- Evidence: `Packages/OpencodeKit/Tests/ApprovalSnapshots/__Snapshots__/ApprovalSnapshots/capture-_-name.question-review-light-393.png shows "Checks / unit", while the editing snapshot shows the option "Unit tests" selected (Fixtures/source/m3a/form.json: value "unit", label "Unit tests"); crop: crops/approvals-question/review-l393-0.png`; `'answerText' returns 'values.compactMap(\.stringValue).joined(...)' or 'value.stringValue', with no lookup in 'options'`
- What happens: Any session form whose option values differ from their labels (plugin, provider or web-search-provider forms). The review lists internal identifiers such as "unit", "ui" or "light". Question-tool forms are not affected because they use the label as the value.
- Why it matters: The step that exists to confirm answers shows text the user never saw. With opaque values such as IDs, the user can't confirm anything.
- Fix: Map string and multiselect values to their option labels through `field.fields.options`, keeping custom values as typed. Format numbers the same way the field displays them.
- Raised from P3 to P2, the severity of F38-04, which describes the same problem.
- Also reported as: F38-04 by sweep-approval-server-snapshots

<a id="f14-09"></a>

## F14-09: When Review answers fails, nothing changes near the button: errors appear only on fields that may be scrolled out of view

*P2 bug · interaction · effort M · found by approvals-question*

- Where: `FeatureApprovals/QuestionSheet.swift:45`, `FeatureApprovals/FormRenderer.swift:27`, `OCModels/FormValidation.swift:36`
- Evidence: `Packages/OpencodeKit/Tests/ApprovalSnapshots/__Snapshots__/ApprovalSnapshots/capture-_-name.question-invalid-light-393.png: the "Required" errors sit under Theme, Checks and Publish, far above the button. Near the button only the external error shows, and it says "Complete the external step and confirm below." although the "I completed this step" switch is above it (crop: crops/approvals-question/invalid-l393-2.png)`; `The button only sets 'state = ... ? .review : .invalid'. There is no ScrollViewReader, summary or announcement, and OCTextFieldStyle always uses borderStrong, so invalid fields keep their normal border`
- What happens: A form with a required field near the top. The user scrolls down and taps Review answers. The state changes to .invalid, but nothing changes in the visible part of the screen (no message, no scroll), so the tap seems to do nothing. VoiceOver users hear nothing either.
- Why it matters: Users can't find what blocks submission and may give up and dismiss the question.
- Fix: When validation fails, show a summary next to the button ("2 answers need attention") and scroll to and focus the first invalid field, using a ScrollViewReader with IDs keyed by field key. Give invalid controls a danger border, announce the error, and reword the external error to "Open the link, then turn on 'I completed this step'."

<a id="f14-10"></a>

## F14-10: Global forms (sessionID 'global', such as MCP elicitations) are fetched and answerable but never shown anywhere

*P2 bug · functional · effort M · found by approvals-question*

- Where: `OCSync/ReadResync.swift:125`, `OCSync/ReadResync.swift:179`, `OCSync/ApprovalActions.swift:13`, `OCSync/ApprovalActions.swift:72`, `OCSync/ReadStore.swift:197` (+1 more)
- Evidence: `refreshLocationRequests always adds the "global" owner and stores the results in 'forms[.global(location:)]', and EventHandlers does the same for form.created`; `replyForm has its own branch that resolves the directory for global forms`; `Every UI reader uses '.session(...)' keys only: familyForms/ApprovalDock, TimelineProjection, SessionSummary.needsYou and updateAttention. A grep finds no other reader of 'forms'` (+1 more)
- What happens: An MCP server the agent uses asks for input while the user is on the phone. The server creates a global form and the tool waits. The session shows Running indefinitely, and nothing in Home, the session or the dock says something is waiting for the user.
- Why it matters: The agent looks hung, and the user has to go to the computer to find and answer the request.
- Fix: Show global forms: a Needs you entry on Home for each server and location, and a dock card when the open session's location matches. Reuse QuestionSheet, since replyForm already handles global forms. At minimum, include them in the attention counts. M8 covers MCP in general but does not list this.
- Also reported as: G18-M2 by verifier G18

<a id="f25-01"></a>

## F25-01: Reject explanation says “this session’s 0 other pending requests” (and “1 other pending requests”)

*P2 bug · copy · effort S · found by l10n-text*

- Where: `FeatureApprovals/PermissionSheet.swift:47`, `FeatureApprovals/PermissionSheet.swift:102`, `Packages/OpencodeKit/Tests/ApprovalSnapshots/ApprovalSnapshots.swift:17`
- Evidence: `iphone/permission-reject.png (reads: “Rejecting also rejects this session’s 0 other pending requests. Without a note, it ends the turn.”)`; `crops/l10n-text/permission-reject-crop.png`; `PermissionSheet.swift:47 Text("Rejecting also rejects this session’s \(otherRequests) other pending requests. Without a note, it ends the turn.")` (+2 more)
- What happens: iPhone or iPad, one pending permission (the common case): open the permission in the review sheet, then tap Reject. The text above the note field reads “Rejecting also rejects this session’s 0 other pending requests.” With exactly two pending requests it reads “…1 other pending requests”.
- Why it matters: This warning exists to explain a side effect at the moment the user decides to reject. With a count of 0 it describes something that will not happen, and the plural is wrong for 1. The count is interpolated into a long sentence, so it cannot take catalog plural variants either.
- Fix: Show the sibling sentence only when otherRequests > 0, as its own key with plural variants (“Rejecting also rejects %lld other pending request(s) in this session.”). Keep “Without a note, rejecting ends the turn.” as a separate sentence. Add the 0 and 1 cases to ApprovalSnapshots.
- Raised from P3 to P2, the severity of F38-05, which describes the same problem.
- Also reported as: F29-01 by ux-writing, F32-08 by design-parity, F38-05 by sweep-approval-server-snapshots

<a id="f14-07"></a>

## F14-07: VoiceOver doesn't link form controls to their question, and doesn't speak required status or errors

*P2 bug · accessibility · effort M · found by approvals-question*

- Where: `FeatureApprovals/FormRenderer.swift:24`, `FeatureApprovals/FormRenderer.swift:43`, `FeatureApprovals/FormRenderer.swift:50`, `FeatureApprovals/FormRenderer.swift:64`, `FeatureApprovals/FormRenderer.swift:27` (+1 more)
- Evidence: `The title is a separate 'Text(title + (required ? " *" : ""))'`; `TextFields are given only placeholder strings ("Type your answer…", "Type your own answer…", "Number", "Whole number"), and those become their accessibility labels`; `A grep of QuestionSheet, FormRenderer and ApprovalDock finds no accessibilityLabel, Hint, Value, isHeader or announcement; the only modifiers are identifiers, '.contain' on the cards and '.isSelected' on choice rows` (+1 more)
- What happens: VoiceOver on, a form with several text fields. Each field reads "Type your answer…, text field" without its question, and the Form Controls rotor lists identical labels. "Publish preview? *" is read with "star" (or the asterisk is skipped, depending on punctuation verbosity), never "required". When Review answers fails, nothing is announced. "Yes, button" and "No, button" carry no question when reached through controls navigation, and field titles are not headings.
- Why it matters: Blind users can't reliably tell which question they are answering or why submission fails. Answering questions is a P0 flow.
- Fix: Give each control `.accessibilityLabel(title)` and `.accessibilityHint(description)`, or wrap each field in a labelled `.accessibilityElement(children: .contain)` group. Mark titles with `.isHeader`. Speak "required" instead of "*". Expose the error as the control's accessibilityValue or hint. When validation fails, post an announcement or move VoiceOver focus to the first invalid field.
- Also reported as: F21-05 by a11y-voiceover

<a id="g12-m2"></a>

## G12-M2: VoiceOver focus is stranded after approving or answering, because the focused control and its card are removed with nowhere for focus to go

*P2 bug · accessibility · effort S · found by verifier G12*

- Where: `FeatureApprovals/ApprovalDock.swift:60`, `OCSync/ApprovalActions.swift:41`, `FeatureApprovals/ApprovalDock.swift:14`, `FeatureApprovals/PermissionSheet.swift:119`, `FeatureApprovals/QuestionSheet.swift:86`
- Evidence: `ApprovalActions.swift:41-42: replyPermission hides and removes the request optimistically, before the network call. The dock card holding the focused 'Allow once' disappears at once, and so does the whole ApprovalDock when it was the last request (ApprovalDock.swift:14)`; `PermissionSheet.swift:119-122 and QuestionSheet.swift:86-90 dismiss the sheet right after replying. The card whose Review / Answer question button presented it has already been removed, so UIKit cannot restore focus to it`; `grep for AccessibilityFocusState, accessibilityFocused and UIAccessibility.post in Sources and App: no matches` (+1 more)
- What happens: iPhone, VoiceOver on, one shell request in the dock. The user double-taps 'Allow once'. The request is removed immediately, taking the focused button, its card and the dock with it. VoiceOver has no defined next element and typically jumps to the top of the screen or to an arbitrary transcript row, and nothing confirms the approval (see F21-01). Replying from the Review sheet ends the same way, because the sheet dismisses onto a card that no longer exists.
- Why it matters: Approving is the app's most frequent action. After each approval a blind user loses their place, has to find the composer or the next request again, and gets no confirmation that the reply registered.
- Fix: Add an @AccessibilityFocusState in SessionScreen, for example enum { composer, request(id) }. After respondToPermission or respondToForm, from the dock, the inline card or a sheet's onDismiss, move focus to the next pending request's Review button, or else to the prompt editor. Post an 'Allowed once' / 'Rejected' / 'Answers sent' announcement through the announcer proposed in F21-01.

<a id="f13-11"></a>

## F13-11: Reject step: copy says '0 other pending requests', the keyboard hides the Reject button, and the note is easy to lose

*P3 bug · interaction · effort S · found by approvals-permission*

- Where: `FeatureApprovals/PermissionSheet.swift:47`, `FeatureApprovals/PermissionSheet.swift:49-52`, `FeatureApprovals/PermissionSheet.swift:102`, `OCDesign/Surfaces.swift:27-37`
- Evidence: `iphone/permission-reject.png: 'Rejecting also rejects this session’s 0 other pending requests.'`; `crops/approvals-permission/reject-behind-kb.png: the red Reject button is visible only blurred behind the keyboard`
- What happens: With one pending request the copy says '0 other pending requests', and with one sibling it says '1 other pending requests'. While typing the note, Return in the multi-line field inserts a newline and the confirming Reject button is under the keyboard. The user has to dismiss the keyboard or scroll to find it. Swiping the sheet down silently discards the typed note.
- Why it matters: The copy looks broken, and finishing the most deliberate action in the flow takes extra steps.
- Fix: Mention siblings only when N > 0, and pluralise ('also rejects 1 other request'). Put Reject in a pinned bar, the confirmationAction toolbar slot or a keyboard toolbar. Add .scrollDismissesKeyboard(.interactively) and interactiveDismissDisabled(!note.isEmpty).

<a id="f14-13"></a>

## F14-13: Unsupported form fields are a dead end: raw JSON, a repeated error, and a primary button that can never succeed

*P3 bug · functional · effort S · found by approvals-question*

- Where: `FeatureApprovals/FormRenderer.swift:88`, `FeatureApprovals/FormRenderer.swift:24`, `OCModels/FormValidation.swift:34`, `FeatureApprovals/QuestionSheet.swift:45`
- Evidence: `Packages/OpencodeKit/Tests/ApprovalSnapshots/__Snapshots__/ApprovalSnapshots/capture-_-name.question-unsupported-light-393.png: the title falls back to the raw key; the red text "This field needs a newer client. You can dismiss the request with a reason." is followed by a JSON block clipped at accessibility5 and then the same error again ("This field needs a newer client.")`; `In the sheet, "Review answers" stays the primary button, but FormValidation always reports the fallback field as an error`; `Known types with a malformed property ('.undecodable') get the same "newer client" text`
- What happens: A server newer than the app sends a field type the app doesn't know. The user taps Review answers repeatedly and only gets red errors. The real way out is the ghost Dismiss button at the bottom, and answering on the computer is never suggested.
- Why it matters: Users get confused and may not realise they can answer the question on their computer.
- Fix: When any visible field is a fallback: hide Review answers and show one explanation ("This question uses a field this app can't show yet. Answer it in opencode on your computer, or decline it here.") with "Decline with reason…" as the primary action. Put the JSON behind a Details disclosure, don't repeat the error, and word malformed fields differently from unknown types.
- Verifier's note: The external branch has the same dead end. A non-http(s) or unparsable URL shows 'This external URL cannot be opened.' with no confirmation toggle (FormRenderer.swift:83-87), yet FormValidation.swift:35-36 still requires the field to be true, so the form can never be submitted. Handle both in the same fallback.

<a id="f25-05"></a>

## F25-05: Question-form number fields reject the decimal comma and show integer answers with grouping (“8,080”)

*P3 bug · localization · effort S · found by l10n-text*

- Where: `FeatureApprovals/FormRenderer.swift:63`, `OCModels/FormValidation.swift:63`, `FeatureApprovals/QuestionSheet.swift:57`, `OCFoundation/JSONValue.swift:54`
- Evidence: `FormRenderer.swift:75 else { answers[f.key] = Double(value).map(JSONValue.number) ?? .string(value) } (Double("1,5") is nil, so the answer is stored as a string)`; `JSONValue.swift:54-59 doubleValue returns nil for .string`; `FormValidation.swift:64 guard let number = value.doubleValue, number.isFinite else { return "Enter a number." }` (+3 more)
- What happens: Region Germany, France, Spain, Brazil and other comma-decimal locales: the agent asks for a number with minimum 0.5. The user types “1,5” and gets “Enter a number.” while the hint reads “Minimum: 0,5”. Typing “1.000” (German for one thousand) in an integer field is silently accepted as 1. In any locale, an integer answer such as port 8080 or year 2026 appears in “Review your answers” as “8,080” or “2,026”.
- Why it matters: Users in comma-decimal regions cannot answer number questions, or submit a different value from the one they meant without noticing. The review step misrepresents answers.
- Fix: Parse with the current locale (Double(value, format: .number) or an IntegerFormatStyle/FloatingPointFormatStyle parse strategy), falling back to POSIX. Reject or correctly parse grouping in integer fields. Display stored and reviewed values with .number.grouping(.never) and the locale’s decimal separator. Use .numberPad for integer fields, and word the validation hint in the format the parser accepts.

<a id="f25-09"></a>

## F25-09: Labels and sentences are built by concatenation: VoiceOver hears “Copy allow always saves these patterns in this project”; the review menu lists “Reviewed \<path>” as an action

*P3 bug · copy · effort M · found by l10n-text*

- Where: `FeatureApprovals/PermissionSheet.swift:76`, `FeatureReview/ReviewScreen.swift:188`, `FeatureComposer/SessionActions.swift:44`, `FeatureTranscript/SessionScreen.swift:156`, `FeatureReview/WorkspaceReviewPanel.swift:39` (+5 more)
- Evidence: `PermissionSheet.swift:76 OCIconButton("Copy " + title.lowercased(), icon: "copy"). For the title “Allow always saves these patterns in this project”, the accessibility label and iPad pointer tooltip become “Copy allow always saves these patterns in this project” (the button is visible in iphone/permission-sheet.png)`; `ReviewScreen.swift:188 Button((model.isReviewed(file) ? "Unmark " : "Reviewed ") + file.file); UITests/ReviewSmokeTests.swift:153 taps “Reviewed Sources/Example.swift” to mark a file`; `SessionActions.swift:44 "Delete session \"\(title)\"?" + (… " Its subagent sessions will be deleted too." : ""), using ASCII quotes where other copy uses typographic ’` (+1 more)
- What happens: A VoiceOver user on the permission sheet reaches the copy button next to the save patterns and hears “Copy allow always saves these patterns in this project, button”. On iPhone, Review → Review options lists “Reviewed Sources/Example.swift” for a file that is not reviewed (tapping it marks it) and “Unmark …” for files that are.
- Why it matters: VoiceOver labels are confusing, and a menu action reads like a status. Concatenation fixes English word order and lowercases nouns (German capitalizes them), so translators cannot produce correct sentences.
- Fix: Give each copy button an explicit label: “Copy action”, “Copy resources”, “Copy working directory”, “Copy saved patterns”. Make the per-file items Toggles labelled with the file name and a checkmark, like “Show all lines” in the same menu, or use “Mark … as reviewed”. Build each sentence as a single format key, with typographic quotes in the format string.

<a id="f13-12"></a>

## F13-12: When a request is answered on another device, the open sheet vanishes without explanation; 'Already handled' never shows

*P3 bug · state · effort S · found by approvals-permission*

- Where: `FeatureApprovals/ApprovalDock.swift:18-19`, `FeatureApprovals/ApprovalDock.swift:54`, `FeatureTranscript/TimelineRowView.swift:109-110`, `FeatureApprovals/PermissionSheet.swift:53-54`, `FeatureApprovals/PermissionSheet.swift:115-117` (+1 more)
- Evidence: `ApprovalDock.swift:54 attaches '.sheet(isPresented: $show)' to the PermissionCard, and that card leaves the ForEach in the same update that sets .settled (permission.replied removes the request)`; `Packages/OpencodeKit/Tests/ApprovalSnapshots/__Snapshots__/ApprovalSnapshots/capture-_-name.permission-settled-light-393.png shows the designed 'Already handled' state`; `docs/m3b-audit.md:101 notes that optimistic removal dismisses the presenting view`
- What happens: The user opens Review on the phone while the same request is approved or rejected on the desktop, or a sibling request in the session is rejected. The presenting card is removed, the sheet slides away with no message, and any reject note being typed is lost.
- Why it matters: It looks like a glitch, and the user doesn't learn what happened to the request.
- Fix: Present the sheet from a stable owner, such as a SessionScreen-level .sheet(item:) keyed by request id that keeps a snapshot of the request. Then .settled can say 'Approved/Rejected on another device' with a Done button. Alternatively, show a toast when an open request settles.
- Also reported as: F26-03 by swiftui-state

<a id="f14-11"></a>

## F14-11: Clearing a field never returns it to 'unanswered': an emptied optional text field fails validation and cleared defaults are submitted anyway

*P3 bug · functional · effort S · found by approvals-question*

- Where: `FeatureApprovals/FormRenderer.swift:128`, `FeatureApprovals/FormRenderer.swift:74`, `OCModels/FormValidation.swift:12`, `OCModels/FormValidation.swift:39`, `OCModels/FormValidation.swift:53` (+1 more)
- Evidence: `The text binding writes '.string($0)' even for "". A touched-then-emptied optional field therefore counts as answered with "", and validate() applies minLength, pattern and format to it ("Enter an email address.", "Enter at least 3 characters.", "Match the requested format.")`; `The number binding removes the key when the field is emptied, so activeAnswers substitutes 'f.defaultValue'`; `A field activated later by 'when' gets its default only inside activeAnswers, never in 'answers', so its control shows no value`
- What happens: A generic form with an optional "Contact email" (format email). Type one letter, delete it and tap Review answers: "Enter an email address." appears, and the only ways forward are inventing an address or dismissing. An optional number with default 3: clear it, the field shows empty, but the review shows 3 and 3 is sent. A boolean with default true that appears after another answer: neither Yes nor No is highlighted, but the review says Yes.
- Why it matters: Valid forms can't be submitted, and what the review and submission contain differs from what the fields show.
- Fix: Treat "" as unanswered for optional fields by removing the key when the text is emptied, including Other. When a field becomes active, seed `answers` with its default so the control reflects it. Let users clear a default deliberately.

<a id="f14-14"></a>

## F14-14: Submit and Dismiss close the sheet before the server replies; the sending and failed states never appear and a typed dismiss reason is lost

*P3 bug · state · effort M · found by approvals-question*

- Where: `FeatureApprovals/QuestionSheet.swift:86`, `FeatureApprovals/QuestionSheet.swift:40`, `FeatureApprovals/QuestionSheet.swift:67`, `FeatureApprovals/QuestionSheet.swift:82`, `FeatureApprovals/QuestionSheet.swift:26` (+3 more)
- Evidence: `FormSheetState.sending and .failed are never assigned in app code; only ApprovalSnapshots iterates them. send() calls dismiss() straight after respondToForm`; `If the reply fails, replyForm re-adds the form and sets writeError, which shows as red text above the dock (SessionScreen.swift:57)`; `'reason' is sheet @State, and formDrafts is an in-memory dictionary` (+1 more)
- What happens: (1) Offline, the user writes a dismissal reason and taps Dismiss question. The sheet closes, the card returns with "Question reply was not sent…", and reopening shows the editing state with the reason gone. (2) The user fills a long form, opens the external link in Safari, and iOS evicts the app: all answers are gone on return. (3) "Dismiss" (decline, which ends the turn) sits right under Review answers, while the toolbar X "Close" only hides the sheet; both mean "dismiss" in iOS terms. The copy explains only the no-reason case, not that adding a reason lets the agent continue.
- Why it matters: Failure recovery is confusing, typed input is lost, and the consequences of declining are unclear.
- Fix: Keep the sheet open in .sending until replyForm resolves, and show .failed in place; at minimum, restore the reason from a store-owned draft. Persist form drafts and reasons with DraftStore. Rename the button "Decline…" and explain both outcomes ("Without a reason the agent stops; with one it continues using your reason").

<a id="f13-06"></a>

## F13-06: The 'Allow always' scope shows a bare pattern such as '*' with no action or project, so users can't tell it approves every future read or edit

*P2 improvement · copy · effort S · found by approvals-permission*

- Where: `FeatureApprovals/PermissionSheet.swift:43-45`, `FeatureApprovals/PermissionSheet.swift:68`, `OCSync/ApprovalActions.swift:33-34`
- Evidence: `iphone/permission-sheet.png: 'Allow always saves these patterns in this project' above 'printf *'`; `research/01-opencode-server-api.md §9.2: read, glob, grep, edit (write and patch too), webfetch and websearch send save ["*"]; line 368: always stores {action, request.save}, and stores nothing when save is empty`; `ARCHITECTURE.md §3.3 specifies 'Always allow 'git status *' in web-app'`
- What happens: For an edit to one file, V2 sends save ["*"], and the sheet shows a lone '*' under a generic caption. Allow always plus Face ID then auto-approves every future edit in the project; the sheet never says so and never names the project. When save is empty (for example a question request), Allow always is still offered and still asks for Face ID, even though it saves nothing.
- Why it matters: Users may create project-wide auto-approval rules while believing they approved one file or one command.
- Fix: Render each pattern as a sentence with the action and project, for example 'Always allow edit of any file (*) in web-app'. Flag broad patterns ('*' or a bare command prefix). Hide or disable Allow always when save is empty. Put the pattern in the Face ID reason string.
- Verifier's note: Partly a spec gap: follow ARCHITECTURE §3.3's sentence form. Hiding Allow always when save is empty removes a Face ID prompt that saves nothing.
- Also reported as: F39-05 by privacy-security-ui

<a id="f13-08"></a>

## F13-08: Reject and Allow sit after all content, so a long diff or multi-file patch pushes them screens below the top

*P2 improvement · layout · effort S · found by approvals-permission*

- Where: `FeatureApprovals/PermissionSheet.swift:40-42`, `FeatureApprovals/PermissionSheet.swift:59-62`, `FeatureApprovals/PermissionSheet.swift:101-104`, `OCDesign/DiffCardView.swift:32`
- Evidence: `DiffCardView.swift:32 'diff(full: false).frame(height: min(4_800, max(48, CGFloat(patch.components(separatedBy: "\n").count) * 24)))', and PermissionSheet passes expanded: true for every file`; `Packages/OpencodeKit/Tests/ApprovalSnapshots/__Snapshots__/ApprovalSnapshots/capture-_-name.permission-review-light-393.png: about 1,640 pt of content before the buttons, for a 3-line diff at accessibility5`; `.build/design-reference/permission-light-393x852.png: the reference keeps Deny / Allow always / Allow once in a fixed footer`
- What happens: An edit with a 150-line diff renders a 3,600 pt inline preview before Reject and Allow. Each additional file in a patch adds up to 4,800 pt. At accessibility sizes even a tiny request needs about two screens of scrolling.
- Why it matters: Deciding takes a long scroll every time, and the buttons can't be seen while reading the command or diff.
- Fix: Pin the decision bar with `.safeAreaInset(edge: .bottom)`: Reject, Allow always and Allow once, or the note field and Reject in the reject step. Cap the inline previews (first 20 to 30 lines plus 'Show full diff') and collapse every file after the first.
- Verifier's note: Pin the decision bar with .safeAreaInset(edge: .bottom), and cap or collapse the previews. This interacts with F13-10: size the previews from measured heights, then cap them.
- Raised from P3 to P2, the severity of F24-05, which describes the same problem.
- Also reported as: F21-04 by a11y-voiceover, F22-14 by a11y-dynamic-type, F24-05 by touch-gestures-motion

<a id="f29-04"></a>

## F29-04: Permission dock and sheet show the raw action id (“Shell”, “edit”, “External_directory”) instead of the desktop's plain-language description

*P2 improvement · design-parity · effort M · found by ux-writing*

- Where: `FeatureApprovals/ApprovalDock.swift:45`, `FeatureApprovals/PermissionSheet.swift:36`
- Evidence: `.build/design-compare/m3a-permission-dock.png: the desktop shows “Permission required / Modify files, including edits, writes, and patches / sample.txt”; the native card shows “Permission required / Shell / printf …”`; `iphone/permission-dock.png and permission-sheet.png: the card says “Shell”; the sheet's Action field says “shell”`; `ApprovalDock.swift:45 uses Text(request.action.capitalized). NSString capitalization treats only whitespace as a word break, so the high-risk action external_directory (server/contracts/risk-rules.json) renders as “External_directory”.`
- What happens: Any session that asks for permission, on iPhone or iPad. Under “Permission required”, the dock card shows only the capitalised action id (“Shell”, “Edit”, “Webfetch”, “External_directory”). The sheet's Action field shows the lowercase id. The desktop dock describes the action in a sentence instead.
- Why it matters: Approvals are the app's core safety promise. Ids like external_directory (a high-risk tier) or webfetch don't tell a phone user what they are allowing, and Allow once is one tap away. This revisits docs/design.md only in that the sheet shows “the action” as a raw id.
- Fix: Port the desktop's per-action descriptions into one OCModels table, for example edit → “Modify files, including edits, writes, and patches”, and the other actions from the same desktop source. Show the description as the headline in the dock card and the sheet. Keep the raw id as the copyable Action value in the sheet. For unknown actions, fall back to a humanised id (“external directory”) instead of .capitalized.
- Also reported as: F13-13 by approvals-permission

<a id="f32-07"></a>

## F32-07: The approval docks do less than the reference: questions need a sheet and 4 taps, and the permission dock has no Reject

*P2 improvement · design-parity · effort M · found by design-parity*

- Where: `FeatureApprovals/ApprovalDock.swift:64`, `FeatureApprovals/ApprovalDock.swift:58`, `FeatureApprovals/ApprovalDock.swift:42`, `FeatureApprovals/QuestionSheet.swift:22`, `FeatureApprovals/QuestionSheet.swift:45` (+2 more)
- Evidence: `.build/design-compare/m3a-question-sheet.png (reference answers inline: options, Dismiss, Submit ⌘↩)`; `.build/design-compare/m3a-question-review.png`; `iphone/question-sheet.png (nav 'Question', label 'Question', 'Questions', 'Color', 'Which color?')` (+2 more)
- What happens: iPhone, a single-choice question is pending. Native flow: dock 'Answer question', then the sheet, pick 'Blue', 'Review answers', 'Submit answers' (4 taps, 2 screens). The reference takes 2 (pick, Submit). The sheet stacks the nav title 'Question', a second 'Question' label, the form title, the field title and the question. The permission sheet likewise repeats 'Permission required' in the nav bar and as a heading. To reject a permission from the dock: Review, then Reject, then Reject again. The dock's warning icon is text-black, not the warning amber the reference and Home's needs-you glyph use.
- Why it matters: Answering the agent is one of the most frequent actions on a phone, and the extra steps and duplicated headings slow it compared with the desktop. This revisits ARCHITECTURE §3.3's mandatory review step and the dock design in docs/design.md.
- Fix: Render one-field questions directly in the dock card, with options plus Dismiss and Submit, and skip the review step when there is only one visible field. Remove the in-sheet 'Question' and 'Permission required' headings that duplicate the nav title. Add Reject to the permission dock, opening the optional note inline. Tint the warning icon with OCColor.warning.
- Verifier's note: The dock card also never shows what is being asked. It renders only the form's title, which for the question tool is the generic 'Questions' (question-sheet.png). At minimum, show the first visible field's title or description in the card. Keep Allow always out of the dock, because it needs device-owner authentication.
- Also reported as: F14-06 by approvals-question, G07-M1 by verifier G07

<a id="f33-01"></a>

## F33-01: Requests in other sessions are invisible while you are inside a session, and M5 presence will also suppress their pushes

*P2 improvement · ux-flow · effort M · found by ux-flows-ia*

- Where: `FeatureApprovals/ApprovalDock.swift:11-25`, `FeatureTranscript/SessionScreen.swift:31-61`, `OCSync/ReadStore.swift:195-211`, `FeatureServers/ServerRootView.swift:64-71`, `OCDesign/WorkspaceShell.swift:28` (+4 more)
- Evidence: `iphone/home.png (two sessions in Needs you)`; `iphone/transcript-live.png (same run, inside another session: no sign of them)`; `ipad/ipad-portrait.png (Home is only a sheet below 1,100 pt)` (+3 more)
- What happens: iPhone 17 Pro. Home lists 'Question' and 'Permission request' under Needs you (home.png). The user opens another session to watch it stream (transcript-live.png). Nothing on the session screen shows that two agents are blocked: the dock lists only this session's family, the back button has no badge, and Home sits under the navigation stack. On iPad portrait, in Split View, or at accessibility text sizes, Home is a sheet that closes when a session is selected, so it has the same blind spot. Once M5b registers presence, the plugin skips every push (requests included) while the app is in the foreground. The blocked agents then wait until the user happens to go back to Home.
- Why it matters: This breaks SPEC §1's core promise ('without … missing an approval'). The moment a user is watching one run is exactly when another session's request is most likely to be missed, and remote agents sit blocked for minutes.
- Fix: Add one app-wide attention affordance outside Home: a small '2 need you' pill in the session header or above the composer. It opens a sheet listing pending requests across all servers, with inline Allow once and Review, built from SessionSummary.needsYou or the existing ReadStore attention counts. Badge the iPhone back button. Show an in-app banner (OCToast) when a permission or form arrives for a session other than the one on screen. Consider narrowing plugin presence suppression to the session being viewed (Presence already carries sessionID).
- Verifier's note: Drive the pill and the back-button badge from SessionModel.attention summed across servers, excluding the open family, and show an OCToast when a permission or form arrives for another session. Narrowing presence to the viewed session revisits ARCHITECTURE §4's 'no push while the app is open'. On iPad, open-session tabs with attention dots (see the missed finding) cover the same need.

<a id="f13-07"></a>

## F13-07: Risk tiers mislabel common prompts: a .env read is 'Low risk', while built-in subagent, skill and question requests are 'High risk' and need Face ID

*P2 improvement · functional · effort M · found by approvals-permission*

- Where: `OCPushCore/Resources/Contracts/risk-rules.json:13-16`, `OCPushCore/Resources/Contracts/risk-rules.json:43`, `OCPushCore/PermissionRisk.swift:74-81`, `FeatureApprovals/PermissionSheet.swift:34`
- Evidence: `risk-rules.json: '"id": "read-only" … "tier": "low"' has no escalations; '"default": { "id": "unknown-action", "tier": "high" }'`; `research/01-opencode-server-api.md:603: the default V2 ruleset allows everything but asks before reading *.env`; `research/02-opencode-features.md:157: V2 actions include subagent, skill, question, MCP <server>_<tool> and execute, none of which have a rule` (+1 more)
- What happens: With the default Build agent, the most common prompt is a read of `.env`, and the sheet badges it 'Low risk' in amber. A user whose rules ask for subagent, skill or question sees a red 'High risk' and needs Face ID to let the agent launch a subagent or load a skill. Under the M5b push rules, such requests also can never be allowed from a notification.
- Why it matters: The tier is meant to guide fast decisions. Rating sending secrets to the model as low, and benign built-ins as high, teaches users to ignore it.
- Fix: Escalate read, glob and grep for secret-looking paths (.env and .env.* except .env.example, *.pem, id_rsa, .ssh/, .netrc, credentials) to elevated or high. Add explicit tiers for subagent, skill and question, and keep MCP tools high. Give Low a neutral tone. This revisits the shared contract in server/contracts/risk-rules.json and its risk.json vectors, so update both copies.
- Verifier's note: Change server/contracts/risk-rules.json, the app's copy and vectors/risk.json together. The Low and Elevated tones can be separated independently in PermissionSheet.swift:34.
- Also reported as: F39-09 by privacy-security-ui

<a id="f13-05"></a>

## F13-05: High risk is shown only by a small badge; the dock shows no tier, and the reason and Face ID requirement are hidden

*P3 improvement · ux-flow · effort M · found by approvals-permission*

- Where: `FeatureApprovals/PermissionSheet.swift:29-35`, `FeatureApprovals/PermissionSheet.swift:66-70`, `FeatureApprovals/PermissionSheet.swift:104`, `FeatureApprovals/ApprovalDock.swift:41-52`, `FeatureApprovals/ApprovalDock.swift:58-62` (+1 more)
- Evidence: `Packages/OpencodeKit/Tests/ApprovalSnapshots/__Snapshots__/ApprovalSnapshots/capture-_-name.permission-high-risk-light-393.png versus permission-review-light-393.png: for 'git reset --hard HEAD~1' only the badge text and colour change; the buttons are identical`; `iphone/permission-dock.png: the dock card has no tier and no directory`; `iphone/permission-sheet.png: 'Permission required' appears twice (navigation title and content heading)` (+1 more)
- What happens: A `rm -rf build` or `git reset --hard` request looks the same in the dock as `printf`, with a one-tap Allow once; Face ID then appears unannounced. In the sheet, the only cue is the small badge. There is no reason given, Allow once stays the black primary button, Allow always is offered with no extra friction, nothing says Face ID will be required, and the warning glyph stays black for every tier.
- Why it matters: Users decide quickly from the dock, and high-risk commands get no more visual weight than harmless ones.
- Fix: Show the tier on the dock card. In the sheet, replace the duplicate content heading with a tier banner that gives the reason from classify().rule ('Rewrites git history', 'Deletes files'). For high risk: make Allow once neutral and label it 'Allow once (Face ID)', hide Allow always or put it behind a confirmation, and colour the warning glyph by tier (the desktop dock's triangle is amber).
- Verifier's note: The cheapest wins are a tier badge on the dock card and a glyph coloured by tier. classify() already returns the rule id for a one-line reason.
- Also reported as: F20-06 by design-system, F39-06 by privacy-security-ui

<a id="f14-05"></a>

## F14-05: Question entry points lead with generic 'Question'/'Questions' text instead of what the agent is asking

*P3 improvement · ux-flow · effort S · found by approvals-question*

- Where: `FeatureApprovals/ApprovalDock.swift:73`, `FeatureApprovals/ApprovalDock.swift:74`, `FeatureApprovals/ApprovalDock.swift:75`, `FeatureApprovals/QuestionSheet.swift:22`, `FeatureApprovals/QuestionSheet.swift:23` (+1 more)
- Evidence: `iphone/question-sheet.png: the nav title "Question" (y≈100 pt), the label "Question" (166 pt) and the form title "Questions" (204 pt) all come before the field "Color / Which color?" (241–268 pt)`; `The question tool titles every form "Questions" (research/01-opencode-server-api.md:998), so the QuestionCard ('OCLabel("Question")' + 'Text(form.title)' + button) reads "Question / Questions / Answer question" for every agent question`; `.build/design-compare/m3a-question-sheet.png: the desktop dock goes straight from "Question" to "Which color?"` (+1 more)
- What happens: Two subagents each ask something. The dock shows two identical "Question / Questions" cards, and the user has to open each sheet to learn what is being asked. At accessibility sizes the redundant headings push the first option below the fold.
- Why it matters: Questions can't be triaged or understood at a glance, which costs extra taps and space.
- Fix: In QuestionCard, show the first visible field's description (falling back to its title), a "+N more" count when there are several, and a one-line preview of the options. Put the Subagent badge in the label's HStack. In the sheet, drop the inner OCLabel("Question") because the nav bar already says it, and hide form.title when metadata.kind == "question" (for generic forms, use it as the nav title instead).
- Verifier's note: The sheet also inverts the desktop hierarchy: for question-tool fields, the short header (title, e.g. 'Color') is the heading and the actual question (description) is muted (FormRenderer.swift:24-25). The desktop makes the question the bold line.

<a id="f14-12"></a>

## F14-12: Constraints and formats stay hidden until validation fails, and format fields get a generic multi-line text box

*P3 improvement · interaction · effort M · found by approvals-question*

- Where: `FeatureApprovals/FormRenderer.swift:43`, `FeatureApprovals/FormRenderer.swift:47`, `FeatureApprovals/FormRenderer.swift:75`, `OCModels/FormValidation.swift:59`, `OCModels/FormValidation.swift:66` (+1 more)
- Evidence: `Packages/OpencodeKit/Tests/ApprovalSnapshots/__Snapshots__/ApprovalSnapshots/capture-_-name.question-editing-light-393.png: "Checks" (maxItems 2) says "Select all answers that apply", and "Scale" (0.5–2) shows only the placeholder "Number"`; `String fields always use 'TextField(..., axis: .vertical)', with no keyboardType, textContentType, autocapitalization setting or DatePicker for the email, uri, date and date-time formats`; `Numbers are parsed with 'Double(value)', but the review shows 'doubleValue?.formatted()', which follows the locale`
- What happens: A provider form asks for an expiry date-time. The user has to type an ISO 8601 timestamp with a time zone on the default keyboard, and only learns the format from "Enter a date and time with a time zone." An email field auto-capitalizes. Picking all three Checks fails with "Choose at most 2 answers." right after the hint said "all that apply". In a region that uses decimal commas, "1,5" fails with "Enter a number." while the review would print 1.5 as "1,5".
- Why it matters: Avoidable failed attempts and hand-typing of structured values on a phone keyboard.
- Fix: Show constraint hints under the title ("Between 0.5 and 2", "Choose up to 2", "3–80 characters" with a counter), and say "Select up to N" when maxItems is set. Map formats to native input: DatePicker for date and date-time, serialised to yyyy-MM-dd or ISO 8601 with a zone; .emailAddress and .URL keyboards with autocapitalization and autocorrection off; single-line fields. Parse numbers with the locale's FormatStyle and display them the same way everywhere.

<a id="f24-09"></a>

## F24-09: No haptic feedback anywhere: approvals, sends, errors and the long-press line selection are silent

*P3 improvement · interaction · effort M · found by touch-gestures-motion*

- Where: `FeatureApprovals/ApprovalDock.swift:60`, `FeatureApprovals/PermissionSheet.swift:119`, `FeatureComposer/ComposerDock.swift:278`, `OCDesign/CodeCollection.swift:252`, `OCDesign/Controls.swift:111` (+1 more)
- Evidence: `grep for sensoryFeedback, UIFeedbackGenerator, UIImpactFeedbackGenerator, UINotificationFeedbackGenerator and UISelectionFeedbackGenerator: 0 hits in Packages/OpencodeKit/Sources and App`; `ARCHITECTURE §2: 'Persistence, Live Activity updates and haptics watch the models through Observations'`
- What happens: Tap Allow once in the dock and the card just vanishes; a failed reply shows only red text. Send, Stop, answering a question and Reject give no tactile confirmation. Neither does the 0.4 s long-press that starts a diff line selection, which is a custom recognizer and so gets no system haptic. The custom OCToggleStyle (for example 'Reviewed') also lacks the system switch's tick.
- Why it matters: On a phone the user often glances away. A confirmation that an approval or send registered, plus a distinct error buzz, reduces double taps and doubt.
- Fix: Add sparse .sensoryFeedback: .success when a permission or question reply is admitted, .error on reply or send failure (writeError), .impact(weight: .light) on Send/Stop, .selection when a line selection begins and as it extends, and on OCToggleStyle changes. Don't fire on stream deltas, and rely on the system haptics setting.

<a id="f38-12"></a>

## F38-12: Approval sheets repeat their title: "Permission required" twice; Question / Question / Questions

*P3 improvement · consistency · effort S · not verified · found by sweep-approval-server-snapshots*

- Where: `FeatureApprovals/PermissionSheet.swift:31`, `FeatureApprovals/PermissionSheet.swift:104`, `FeatureApprovals/QuestionSheet.swift:22`, `FeatureApprovals/QuestionSheet.swift:78`
- Evidence: `iphone/permission-sheet.png: nav title 'Permission required' with the in-content '⚠ Permission required' directly below`; `iphone/question-sheet.png: 'Question' (nav), '💬 Question', 'Questions' (form title), 'Color', 'Which color?', 'Select one answer' come before the first option`; `Packages/OpencodeKit/Tests/ApprovalSnapshots/__Snapshots__/ApprovalSnapshots/capture-_-name.question-editing-light-393.png: the label and form title stack above every state`
- What happens: Open any permission or question sheet on iPhone.
- Why it matters: About 100–150 pt of duplicate headings push the request details and actions down, which matters most at large text sizes and in the medium sheet height.
- Fix: In the sheets, use the session title as the nav title (or none) and keep the content heading with the risk badge. Or drop the in-content 'Permission required' and 'Question' labels and keep them only in the dock.
- Also reported as: F30-11 by visual-polish-iphone

<a id="f13-14"></a>

## F13-14: The dock appears instantly where the user may be tapping, so a stray tap can approve a command

*P3 improvement · interaction · effort S · plausible, needs a running app to confirm · found by approvals-permission*

- Where: `FeatureApprovals/ApprovalDock.swift:14-24`, `FeatureTranscript/SessionScreen.swift:59`, `FeatureTranscript/SessionTimeline.swift:40-42`
- Evidence: `ApprovalDock.swift:14 'if !requests.isEmpty || !forms.isEmpty { ScrollView … }' has no transition, animation or input guard, and it is driven by permission.asked events`; `iphone/transcript-tools.png: Jump to latest pill at about x 130-272 pt, y 657-698 pt, just above the composer`; `iphone/permission-dock.png: Allow once spans about x 100-193 pt`
- What happens: While watching a live session, the user taps near the bottom of the transcript: a tool row, a file link or the Jump to latest pill. A permission event inserts the dock in the same frame, and the tap lands on Allow once, running a low- or elevated-risk command unreviewed (high risk still gets Face ID). Once the 240 pt dock is sized to its content, its buttons will sit exactly where the pill was.
- Why it matters: An approval UI should not accept a tap meant for something else.
- Fix: Animate the dock in, and ignore taps on its action buttons for about 0.5 to 1 s after a card first appears, as system permission alerts do. Alternatively, require the first tap after the dock appears to be on Review.
- Verifier's note: There is a related path: after Allow once, the approved card is removed optimistically and the next card's Allow once slides into the same position, so a quick second tap approves the next request unseen. Animate insertion and removal, and ignore taps on a card's buttons briefly after it appears or moves.
