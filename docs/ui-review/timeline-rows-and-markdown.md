# UI review: Timeline rows and markdown

Part of the [UI review](README.md). 16 bugs and 3 improvements, bugs first, then by severity. Paths under `Packages/OpencodeKit/Sources` are written without that prefix.

| ID | Severity | Finding |
| --- | --- | --- |
| [F05-02](#f05-02) | P2 bug | Stopping a run, or Interrupt and send, shows a red 'Run failed — Step interrupted' card |
| [F05-05](#f05-05) | P2 bug | Compaction rows are mislabelled: queued says 'Needs you', running is blank, failed says 'Compacting conversation' and hides the error |
| [F05-07](#f05-07) | P2 bug | At accessibility text sizes, the pending-steer controls in the prompt bubble wrap mid-word on iPhone |
| [F21-07](#f21-07) | P2 bug | Transcript never says who is speaking: user prompts and agent replies read the same |
| [F22-06](#f22-06) | P2 bug | Turn changes card mangles file names at accessibility sizes: 'src/example.ts' reads 'sexample.ts' and extensions are truncated |
| [F27-01](#f27-01) | P2 bug | Compaction deltas and every step/tool event re-run an O(history) JSON hash and full transcript re-materialization on the main thread |
| [F27-02](#f27-02) | P2 bug | A pending Steer prompt's row materializes the whole transcript twice on every streamed token |
| [G03-M1](#g03-m1) | P2 bug | Empty reasoning and text parts render as empty 'Thinking' disclosures and blank gaps |
| [F05-04](#f05-04) | P3 bug | Voice delegation prompts show the raw 'Voice delegation.' header and JSON payload under a Voice badge |
| [F05-06](#f05-06) | P3 bug | Reasoning takes two taps through two identical 'Thinking' disclosures, and the expanded thinking is not muted |
| [F05-11](#f05-11) | P3 bug | Fenced code blocks end with an extra blank line and can keep a 'Streaming' badge after the message has ended |
| [F05-12](#f05-12) | P3 bug | 'Show full output' opens long code and logs in a proportional font, titled 'Select text', after the row showed only the first 200 lines |
| [F05-14](#f05-14) | P3 bug | Turn-end rows show a check mark and 'Turn complete' for failed or interrupted turns, carry no time, and still appear in Quiet and Messages only |
| [F32-13](#f32-13) | P3 bug | Every tool group header uses the Read 'glasses' icon, including 'Used 1 Shell', 'Updates' and edit groups |
| [G03-M2](#g03-m2) | P3 bug | Markdown headings below h1 all render the same (16 pt medium), so h2/h3/h4 structure is lost |
| [G15-M1](#g15-m1) | P3 bug | The transcript cache (up to 200 sessions or 300 MB of code and tool output) is not excluded from iCloud and computer backups |
| [F05-10](#f05-10) | P3 improvement | Error and retry rows give no next step: no retry time, no error type, no actions, and a static 'Working…' while the run waits |
| [F24-10](#f24-10) | P3 improvement | Copy buttons in the transcript, permission sheet and Files give no confirmation |
| [F27-07](#f27-07) | P3 improvement | Tool rows rebuild their presentation in body: full-input JSON pretty-printing, JSON round-trips of patches and repeated string splits on every render |

<a id="f05-02"></a>

## F05-02: Stopping a run, or Interrupt and send, shows a red 'Run failed — Step interrupted' card

*P2 bug · copy · effort S · found by timeline-rows*

- Where: `OCRender/TimelineRowBuilder.swift:85`, `OCRender/TimelineRowBuilder.swift:87-89`, `FeatureTranscript/TimelineRowView.swift:113-121`, `FeatureTranscript/TimelineRowView.swift:144-146`, `Packages/OpencodeKit/Tests/OCRenderTests/TimelineRowBuilderTests.swift:17-18`
- Evidence: `Fixtures/v2/2.0.32/snapshots/interrupt.json: assistant step '"finish": "error", "error": {"type": "aborted", "message": "Step interrupted"}' followed by an idle row with outcome "interrupted"`; `Fixtures/v2/2.0.32/snapshots/interrupt-resume.json: the same aborted step, then the steered prompt runs and succeeds`; `'if let error = f.error { append(.init(id: message.id + ":error", kind: .error, text: error.message)) }' with no check of error.type; 'case .error: "Run failed"' on dangerBackground` (+1 more)
- What happens: The user taps Stop while the agent is replying. The timeline shows a red '⚠ Run failed / Step interrupted' card. With long-press Send → Interrupt and send, the red failure card sits in the middle of a turn that then continues successfully with the steered prompt.
- Why it matters: A deliberate user action reads as a crash. Users may think the steer failed, and the red style loses its meaning for real failures.
- Fix: In TimelineRowBuilder, map `error.type == "aborted"` (or a turn whose idle outcome is "interrupted") to a muted notice such as 'Stopped' or 'Interrupted — continued with your new message' instead of `.error`. Keep 'Run failed' and dangerBackground for real failures, and update the row-builder test expectations.
- Verifier's note: Port the desktop's isInterrupted check: a case-insensitive match on 'abort' or 'interrupt' in error.type. That also covers type 'ExecutionInterrupted' ('Context compaction started' in the desktop fixtures) and compaction.interrupted, not only 'aborted'. Show a muted 'Interrupted' notice, or nothing, and update the expectations for interrupt and interrupt-resume.
- Also reported as: F29-02 by ux-writing

<a id="f05-05"></a>

## F05-05: Compaction rows are mislabelled: queued says 'Needs you', running is blank, failed says 'Compacting conversation' and hides the error

*P2 bug · state · effort M · found by timeline-rows*

- Where: `FeatureTranscript/TimelineProjection.swift:51-53`, `FeatureTranscript/TimelineRowView.swift:113-121`, `FeatureTranscript/TimelineRowView.swift:144-146`, `OCRender/TimelineRowBuilder.swift:94-95`, `OCSync/EventHandlers.swift:214-217` (+1 more)
- Evidence: `Queued: 'TimelineRow(id: "pending:" + $0.id, kind: .pendingInput, text: $0.fields.payload.text, badge: "Compaction queued")' together with 'case .pendingInput: "Needs you"'`; `Running: compaction.started inserts '"summary": .string("")', so 'f.summary ?? "Compacting conversation"' gives an empty body, and the badge is the raw lowercase status 'running'`; `Failed: the failed branch rebuilds the row without the summary ('if failed { fields["error"] = p["error"] }'), so the row reads 'Compacting conversation' with a lowercase 'failed' badge, and 'error.message' is never rendered` (+2 more)
- What happens: The user runs /compact while the agent is working. A grey card '⊟ Needs you [Compaction queued]' with an empty body appears. When compaction starts, the card reads 'Compaction [running]' with no text. If it fails, it reads 'Compaction / Compacting conversation [failed]'. In Everything mode the finished summary appears as raw '## Objective / - …' lines.
- Why it matters: 'Needs you' falsely signals that the user must act, a failure gives no reason, and the summary is hard to read.
- Fix: Give queued compaction its own neutral label ('Compaction queued'), with no 'Needs you'. While running, show 'Compacting conversation…' with the streamed summary behind a disclosure. On failure, show 'Compaction failed' in the danger style with f.error?.message. Capitalise or drop the status badges. Render the completed summary with StreamingMarkdownView inside a collapsed 'Summary' disclosure.
- Verifier's note: Match the desktop: error.type 'aborted' maps to 'Session compaction cancelled' and 'compaction.interrupted' to 'interrupted', both without the danger card. Only other failures show the error card.
- Also reported as: F35-09 by sweep-read-snapshots

<a id="f05-07"></a>

## F05-07: At accessibility text sizes, the pending-steer controls in the prompt bubble wrap mid-word on iPhone

*P2 bug · accessibility · effort S · found by timeline-rows*

- Where: `FeatureTranscript/TimelineRowView.swift:52-57`, `FeatureTranscript/TimelineRowView.swift:115-118`, `FeatureComposer/PendingInputPanel.swift:60-70`
- Evidence: `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.pending-steering-light-393-accessibility5.png: 'Pen/ding', 'Mov/e to/queu/e', 'Dele/te'`; `…/capture-_-name-fixedHeight.pending-stranded-dark-393-accessibility5.png: the same breakage`; `scratch/sheets/timeline-rows-3.png` (+1 more)
- What happens: iPhone at accessibility text sizes. The user steers a prompt while the agent runs (or the steer becomes stranded). Inside the bubble, the Pending badge and the Move to queue and Delete buttons are squeezed into about 310 pt, and each label wraps character by character.
- Why it matters: Low-vision users can't read the controls at the moment they need to act, before the steer is delivered. Delete also looks like an ordinary button.
- Fix: Use PendingInputPanel's pattern: under typeSize.isAccessibilitySize, or with ViewThatFits, put the badge on its own line and stack the buttons vertically. Give Delete the danger style.
- Verifier's note: The status-row header has the same unadapted HStack: label plus badge (TimelineRowView.swift:115-118), for example 'Needs you' with 'Compaction queued', or 'Retrying' with 'Attempt 2'. No snapshot covers it with a badge. Apply the same accessibility-size stacking there.
- Also reported as: F09-09 by composer-dock, F10-12 by prompt-editor, F12-03 by session-actions, F22-05 by a11y-dynamic-type, F37-04 by sweep-composer-snapshots

<a id="f21-07"></a>

## F21-07: Transcript never says who is speaking: user prompts and agent replies read the same

*P2 bug · accessibility · effort S · found by a11y-voiceover*

- Where: `FeatureTranscript/TimelineRowView.swift:29`, `FeatureTranscript/TimelineRowView.swift:40`, `FeatureTranscript/TimelineRowView.swift:179`, `FeatureComposer/SessionActions.swift:128`
- Evidence: `TimelineRowView.swift:28-30: every row is .accessibilityElement(children: .contain) with only an identifier, no label`; `User prompts differ only by right alignment and the infoBackground bubble (:40-61). Assistant text is a bare StreamingMarkdownView (:179)`; `iphone/transcript-tools.png ('Run the shell-output fixture scenario.' bubble)` (+1 more)
- What happens: VoiceOver at any detail level, especially 'Messages only'. Swiping through a session reads 'Simplify this review selection', then 'Hello, fixture world!', then the next prompt, with no You/Agent cue. A user's instruction can't be told apart from the agent's prose.
- Why it matters: Users can't follow the conversation or find their own earlier instructions to revert or fork from. Who said what is conveyed visually only (WCAG 1.3.1).
- Fix: Label the row groups: .accessibilityLabel(row.kind == .userPrompt ? "You" : "Agent") on the .contain container, which is spoken on entry, or add a hidden 'You said' / 'Agent' prefix to the first element of each message. Also add .accessibilityAction(named:) for Copy / Revert message / Fork from here, which today live only in the long-press menu.
- Also reported as: F05-08 by timeline-rows, F08-09 by timeline-mechanics

<a id="f22-06"></a>

## F22-06: Turn changes card mangles file names at accessibility sizes: 'src/example.ts' reads 'sexample.ts' and extensions are truncated

*P2 bug · layout · effort S · found by a11y-dynamic-type*

- Where: `FeatureTranscript/TurnChangesCard.swift:37-53`
- Evidence: `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.turn-expanded-light-393-accessibility5.png: the last row reads 'sexample.ts  Created', because the 'src/' prefix is compressed to one gray 's' with no ellipsis. Other rows read 'image.p…  Binary file' and 'removed.t…  Deleted'. Crop: crops/a11y-dynamic-type/turn-expanded-a5-last2.png`; `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.turn-collapsed-light-393-accessibility5.png: 'Binary / file' wraps onto two lines while 'image.p…' is truncated.`
- What happens: AX5, a turn that changed src/example.ts, image.png and removed.txt. Each row is a single HStack: the directory Text (truncationMode .middle), then the name (lineLimit 1), competing with an unconstrained status label ('Binary file', 'Deleted', 'Created') or the counts.

  The status wins the space, so the name loses its extension. The directory shrinks to a single clipped glyph that visually merges into the file name.
- Why it matters: Users can misread which file changed or tap the wrong one. The UI is misleading.
- Fix: At accessibility sizes:
  - Put the status and counts on a second line under the name.
  - Give the name layoutPriority over the status, and use middle truncation so the extension survives.
  - Drop the directory, or move it to its own muted line, when it can't show at least '…/'.
- Also reported as: F36-10 by sweep-review-snapshots

<a id="f27-01"></a>

## F27-01: Compaction deltas and every step/tool event re-run an O(history) JSON hash and full transcript re-materialization on the main thread

*P2 bug · performance · effort L · found by ui-performance*

- Where: `FeatureTranscript/TimelineProjection.swift:20-39`, `OCSync/EventHandlers.swift:218-219`, `OCSync/EventHandlers.swift:88-91`, `OCSync/EventHandlers.swift:108`, `OCSync/StreamingHandlers.swift:52-74` (+3 more)
- Evidence: `TimelineProjection.swift:23-27 walks every message: 'hash.combine(message.fields.raw); for item in message.items { hash.combine(item.id); hash.combine(item.fields.raw) }' (tool fields include full tool input/output), evaluated in body as '.task(id: structure)' (line 33)`; `TimelineProjection.swift:35 'visible.compactMap { transcript.messages[$0]?.value }' rebuilds a SessionMessage (new content arrays and dictionaries) for every message on the main actor before each build; TimelineRowBuilder.swift:25 then deep-compares every frozen turn ('frozen.input == turn')`; `EventHandlers.swift:219 every 'session.compaction.delta' appends to 'row.fields[summary]', a MessageModel.fields mutation the projection observes; the compaction row text comes only from rebuilt TimelineRows` (+3 more)
- What happens: A long session with hundreds of tool calls (about 1 MB of tool JSON) reaches auto-compaction. For the 20-60 s while the summary streams, each delta (up to one per frame) makes TimelineProjection hash the whole transcript, cancel and restart its task, re-materialize every message on the main actor, deep-compare all frozen turns, then diff every row in TimelineCollection. The same walk runs about ten times per step, because every tool call alone triggers four or five field writes, and also on any approval in any session on the server. Scrolling and typing stutter during compaction. Because each delta cancels the in-flight build, the compaction row's text can update in bursts.
- Why it matters: Main-thread cost per update grows with session length, so the longest sessions get the worst jank. This defeats the §3.1 budget of 4 ms per update, which the comment at TimelineProjection.swift:8-9 says the design protects.
- Fix: Replace the JSON hash with cheap revision counters: bump a structureRevision on TranscriptModel when order, items or non-text fields change, and key the task on that revision plus the pending and per-session approval revisions. Stream the compaction summary into a separately observed value, like ContentItemModel.text, that the compaction row reads directly. Pass frozen turns to the builder by id and revision instead of materializing `.value` for every message. Scope permission and form observation to this session.
- Verifier's note: Add the amplifier: stored user messages keep attachments and @-mentioned file contents as base64 files[].data (research/01-opencode-server-api.md:514-516), so every structure hash also walks those megabytes. Keying the task on revision counters bumped in the MessageModel and ContentItemModel setters avoids touching payloads at all.
- Also reported as: F08-12 by timeline-mechanics, F26-09 by swiftui-state

<a id="f27-02"></a>

## F27-02: A pending Steer prompt's row materializes the whole transcript twice on every streamed token

*P2 bug · performance · effort S · found by ui-performance*

- Where: `FeatureTranscript/TimelineRowView.swift:47-52`, `OCSync/SessionModel.swift:33-43`, `OCSync/TranscriptModel.swift:19-23`, `OCSync/TranscriptModel.swift:85`, `FeatureComposer/ComposerDock.swift:18`
- Evidence: `TimelineRowView.swift:49 'pending: store?.sessions[sessionID]?.pendingStatus(row.id) != nil' and line 52 'let status = store.sessions[sessionID]?.pendingStatus(row.id)': two calls per body`; `SessionModel.swift:36 'let messages = transcript?.snapshot ?? []' runs for every non-queued pending user item`; `TranscriptModel.swift:85 'order.compactMap { messages[$0]?.value }'; line 21 'raw.set("text", .string(text))' reads every ContentItemModel.text, so the row starts observing all streaming text` (+1 more)
- What happens: In a long session, the user sends a follow-up while the agent streams, using the default Steer. Until `session.inbox.delivered`, every text or reasoning delta invalidates the pending prompt row at the bottom. Each body pass copies every message, including every content dictionary and its text, twice, and registers observation on thousands of properties. At 50 tokens/s that is up to about 100 full-transcript copies per second on the main thread.
- Why it matters: Streaming stutters and the composer lags right after the user sends a follow-up. The cost grows with history.
- Fix: Derive the pending status from transcript.order and messages[id]?.fields (type and created time) without `.value`, or keep a lastIdleIndex on TranscriptModel that upsert updates. Call it once per body and pass the result to SentPrompt.

<a id="g03-m1"></a>

## G03-M1: Empty reasoning and text parts render as empty 'Thinking' disclosures and blank gaps

*P2 bug · functional · effort S · found by verifier G03*

- Where: `OCRender/TimelineRowBuilder.swift:67-70`, `OCRender/TimelineRowBuilder.swift:43`, `FeatureTranscript/TimelineRowView.swift:174-181`, `OCDesign/MarkdownBlockView.swift:64-68`
- Evidence: `TimelineRowBuilder.swift:67-70: 'case "text": append(.init(id: id, kind: .assistantText, reference: ref))' and 'case "reasoning": append(...)', with no emptiness check even after the item completes`; `MarkdownBlockView.swift:64-68: with no blocks, the view keeps a hidden one-line placeholder 'Text(text.isEmpty ? " " : text).hidden()'`; `opencode desktop: opencode/packages/session-ui/src/timeline/projection.ts:835-839 renderable(): text and reasoning parts are rendered only when 'content.text.trim()' is non-empty` (+3 more)
- What happens: iPhone, Compact (the default), a session on a reasoning model whose reasoning items often finish with no summary text, for example GPT-5-class models through OpenAI or Copilot. In a text-only turn, a 'Thinking' group sits above the answer. Tapping it reveals a nested 'Thinking' disclosure, and tapping that shows nothing. In tool-heavy turns, the expanded 'Used N …' group has empty 'Thinking ›' rows between the tool rows. In Everything, every step shows an expanded, empty Thinking block. A text part that is only whitespace, or only a \<think> block, leaves a ~32-pt blank gap: a hidden one-line placeholder plus the 12-pt row spacing.
- Why it matters: Disclosures that open onto nothing appear in many turns for common reasoning models. This adds noise to the default preset and diverges from both official clients, which skip these parts.
- Fix: In TimelineRowBuilder, skip text and reasoning items whose ModelOutputCleanup-cleaned text is whitespace-only once the item or its message has completed. Keep today's placeholder row only while the item is still open, to avoid layout jumps. The item's time.completed is part of the structure hash, so completion already triggers a rebuild. Add fixture-based tests for an empty reasoning part and a \<think>-only text part.

<a id="f05-04"></a>

## F05-04: Voice delegation prompts show the raw 'Voice delegation.' header and JSON payload under a Voice badge

*P3 bug · functional · effort M · found by timeline-rows*

- Where: `OCRender/TimelineRowBuilder.swift:58-59`, `FeatureTranscript/TimelineRowView.swift:43-50`, `FeatureComposer/SessionActions.swift:109-130`
- Evidence: `research/08-feature-matrix.md:141 (C14, a P1 feature): the prompt text starts with 'Voice delegation.' followed by JSON ('instruction', 'voice', 'transcript_delta')`; `research/02-opencode-features.md:596: desktop and web parse these into Voice messages, and Copy offers the full prompt`; `The only handling is 'badge: f.text.hasPrefix("Voice delegation.") ? "Voice" : nil'; SentPrompt renders the whole 'text' through ComposerInput.restoreText` (+2 more)
- What happens: A user delegates work by voice from the official OpenCode iOS app, then opens the session in this app. The bubble shows a Voice badge followed by 'Voice delegation.' and a JSON object ({"instruction":…, "transcript_delta":[…]}) in accent text.
- Why it matters: The P1 parity feature in SPEC §4.2 ('voice delegations shown as Voice messages') is effectively missing, and these bubbles are long and unreadable.
- Fix: Port the desktop parser (voice-delegation.ts / VoiceHandoff.parse). When the header and JSON parse, show `instruction` as the bubble text with the Voice badge, put the transcript behind a 'Transcript' disclosure, and keep Copy returning the full prompt. Fall back to the raw text when parsing fails, and replace the snapshot fixture with the real format.
- Verifier's note: Follow voice-delegation.ts exactly. Also accept the 'Voice delegation (continued).' header; the badge check misses it today. Strip trailing 'Attached file: `…`' lines before decoding. Fall back to the raw text when `instruction` is empty.

<a id="f05-06"></a>

## F05-06: Reasoning takes two taps through two identical 'Thinking' disclosures, and the expanded thinking is not muted

*P3 bug · interaction · effort S · found by timeline-rows*

- Where: `OCDesign/MarkdownBlockView.swift:27`, `FeatureTranscript/TimelineRowView.swift:174-177`, `OCRender/TimelineRowBuilder.swift:43`, `FeatureTranscript/TimelineRowView.swift:69-70`
- Evidence: `A group made only of reasoning is labelled "Thinking", and the group chrome always uses 'icon: "glasses"'; its child is another 'OCToolChrome("Thinking", icon: "brain", expanded: detail == .everything)'`; `Desktop .build/design-reference/timeline-dark-820x1180.png shows 'Used 1 Thought' for the same reasoning-text scenario`; `iphone/composer-sent.png: the first row is a collapsed 'Updates' group (notices) shown with the explore glasses icon` (+2 more)
- What happens: Compact (the default) or Detailed: a turn that starts with reasoning shows '👓 Thinking ›'. Tapping it reveals a second, collapsed '🧠 Thinking ›', and only a second tap shows the text, in the same full-contrast colour as the answer. When reasoning is grouped with tools, the label never mentions it.
- Why it matters: Extra taps and duplicate labels to read the reasoning. Once open, the reasoning is visually indistinguishable from the answer, and the glasses icon misdescribes reasoning and notice groups.
- Fix: For reasoning-only groups, render the reasoning content directly in the group, or skip the group for a single item. Label groups like the desktop ('Used 1 Thought', or a duration from the reasoning time) and count thoughts in mixed-group labels. Pick the group icon from its content. Set foregroundStyle at the StreamingMarkdownView call sites rather than inside TextualBlockContent, so the muted style applies.
- Verifier's note: Keep the two levels, which match the desktop, but use its labels. A reasoning-only group reads 'Used N Thought(s)'. The child reads 'Thinking' while streaming and 'Thought' plus the duration (time.completed - time.created) afterwards. Move the foregroundStyle out of TextualBlockContent, or make it overridable, so reasoning renders muted.

<a id="f05-11"></a>

## F05-11: Fenced code blocks end with an extra blank line and can keep a 'Streaming' badge after the message has ended

*P3 bug · visual · effort S · found by timeline-rows*

- Where: `OCRender/StreamingMarkdown.swift:70`, `OCRender/StreamingMarkdown.swift:75-76`, `OCDesign/CodeBlockView.swift:20-31`, `OCDesign/CodeBlockView.swift:37-39`, `OCDesign/CodeBlockView.swift:51-63`
- Evidence: `iphone/transcript-live.png: the code block spans 1682–1988 px and the code line 1861–1896 px, leaving 30 pt below the line against a 12 pt padding`; `Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/ReadSnapshots/capture-_-name-height.markdown-light-393.png leaves 66 pt below the last code line, while capture-_-name-height.Exit-2-light-393.png (same CodeBlockView, code without a trailing newline) leaves 23 pt; markdown-dark-820.png shows the same gap`; `swift-markdown's CodeBlock.code keeps the final "\n", which renders as a blank line, adds one to the 'Show full output' count and ends up in the copied code` (+1 more)
- What happens: Every fenced code block in a reply has an empty last line. If the user stops the agent mid-code-block, or the output hits the length limit, the finished message keeps a 'Streaming' badge and unhighlighted code indefinitely.
- Why it matters: Uneven padding in every reply, and a stopped message keeps telling the user it is still streaming.
- Fix: Trim one trailing newline from the code when building the MarkdownBlock (or in CodeBlockView before display, counting and copying). Treat a complete message as closed: `let closed = complete || fence == nil || index != children.count - 1`.
- Also reported as: F35-12 by sweep-read-snapshots

<a id="f05-12"></a>

## F05-12: 'Show full output' opens long code and logs in a proportional font, titled 'Select text', after the row showed only the first 200 lines

*P3 bug · visual · effort M · found by timeline-rows*

- Where: `OCDesign/CodeBlockView.swift:20-21`, `OCDesign/CodeBlockView.swift:30-36`, `OCDesign/CodeBlockView.swift:67`, `OCDesign/TextSelection.swift:36`, `OCDesign/TextSelection.swift:53-57` (+1 more)
- Evidence: `SelectionTextView always sets 'UIFont(name: "Inter-Regular", size: 14)' and wraps text, and the sheet title is always "Select text"`; `The fold keeps 'prefix(200)', the head of the output`; `Shell output uses 'CodeBlockView(…, language: "output")', so long test and build logs go through this path` (+1 more)
- What happens: A 1,500-line test log: the row shows lines 1–200, while the failures are at the end. 'Show full output (1501 lines)' opens a 'Select text' sheet where the log is wrapped in proportional Inter, so aligned columns, tables and indentation break. Tapping the copy icon gives no sign that anything happened.
- Why it matters: Finding and reading failures in long output on a phone is slow and error-prone.
- Fix: Give OCTextSelectionSheet a monospaced mode and a title parameter: show code and output in scaled JetBrains Mono, without soft wrap (or with a wrap toggle), titled 'Output' or the language. For tool output, fold to the last 200 lines with a 'Show earlier lines' control. Briefly swap the copy icon to a check and post a VoiceOver announcement after copying.

<a id="f05-14"></a>

## F05-14: Turn-end rows show a check mark and 'Turn complete' for failed or interrupted turns, carry no time, and still appear in Quiet and Messages only

*P3 bug · consistency · effort S · found by timeline-rows*

- Where: `OCRender/TimelineRowBuilder.swift:90-92`, `FeatureTranscript/TimelineRowView.swift:95-100`, `FeatureTranscript/TimelineRowView.swift:138-140`, `Packages/OpencodeKit/Tests/OCRenderTests/TimelineRowBuilderTests.swift:74-75`
- Evidence: `'OCLabel(row.text, icon: row.files.isEmpty ? "check" : "edit")' is used whatever the outcome, with only a badge for failed or interrupted`; `Empty turn ends are skipped only when 'detail == .compact', so Quiet and Messages only add a separator and 'Turn complete' to every turn (the test expects '[.error, .turnEnd]' for messagesOnly)`; `iphone/subagent.png: a '✓ Turn complete' row with no time` (+1 more)
- What happens: In Detailed, Everything, Quiet or Messages only, a failed turn ends with '✓ Turn complete [Failed]', and in Messages only every turn ends with a separator line. Returning to a session the next day, nothing shows when any prompt was sent or how long a turn took.
- Why it matters: Mixed success and failure signals, extra noise in the two quietest presets, and no time context in long sessions.
- Fix: Pick the icon and label from the outcome ('Turn failed' with a warning icon, 'Stopped'). Skip empty turn ends in Quiet and Messages only, as Compact already does. Add the time and duration to the turn end (for example '2:41 PM · 3 min', from the first prompt's and the idle row's time.created), and insert a day separator when the date changes.

<a id="f32-13"></a>

## F32-13: Every tool group header uses the Read 'glasses' icon, including 'Used 1 Shell', 'Updates' and edit groups

*P3 bug · consistency · effort S · found by design-parity*

- Where: `FeatureTranscript/TimelineRowView.swift:70`, `OCRender/TimelineRowBuilder.swift:43`
- Evidence: `.build/design-compare/m2b-transcript-tools.png (native 'Used 1 Shell' with glasses; reference group headers have no icon)`; `iphone/composer-sent.png ('Updates' with glasses)`; `ipad/ipad-review-reviewed.png ('Used 4 Read, Edit, Write, Shell')` (+1 more)
- What happens: Any transcript in Compact mode. 'Used 1 Shell', 'Used 4 Read, Edit, Write, Shell', 'Updates' (notice-only groups) and reasoning-only groups all start with the glasses icon, which is also the Read row's icon inside the group.
- Why it matters: The icon says 'read' for groups that ran commands or edited files, which muddles the transcript's scan cues. The reference has no group icon.
- Fix: Choose the icon from the group's contents (terminal for shell-only, edit when edits are present, brain for Thinking, glasses only for explore), or drop the group icon as the reference does.
- Also reported as: G17-M2 by verifier G17

<a id="g03-m2"></a>

## G03-M2: Markdown headings below h1 all render the same (16 pt medium), so h2/h3/h4 structure is lost

*P3 bug · design-parity · effort S · found by verifier G03*

- Where: `OCDesign/MarkdownStyles.swift:10-14`, `OCDesign/Typography.swift:28-29`
- Evidence: `MarkdownStyles.swift:12: 'configuration.label.font(configuration.headingLevel == 1 ? OCType.title : OCType.heading)', so only two sizes exist`; `Typography.swift:28-29: title is Inter 20 semibold and heading is Inter 16 medium; the body (line 26) is 14`; `opencode desktop opencode/packages/session-ui/src/components/markdown.css:50-85: h1 17px/600, h2 15px/600, h3 13px medium, h4-h6 13px medium in text-muted, each with its own top and bottom margin`
- What happens: An agent's plan or code-review reply uses '## Summary', '### Changes' and '#### Risks'. On iPhone and iPad all three headings render identically at 16 pt medium, larger than the 14-pt body, with the same 8-pt padding. Only '#' differs, at 20 pt semibold.
- Why it matters: Long structured replies lose their section and subsection hierarchy, which makes them harder to scan on a phone. This also departs from the desktop typography the app reproduces.
- Fix: Map heading levels the way the desktop does, relative to the 14-pt body: h1 17 semibold, h2 15 semibold, h3 13-14 medium, h4-h6 13 medium in OCColor.textMuted. Keep relativeTo text styles so Dynamic Type still scales, and vary the vertical padding by level. Add a ReadSnapshots markdown case with h1-h4.

<a id="g15-m1"></a>

## G15-M1: The transcript cache (up to 200 sessions or 300 MB of code and tool output) is not excluded from iCloud and computer backups

*P3 bug · privacy · effort M · found by verifier G15*

- Where: `OCPersistence/PersistenceWriter.swift:56-58`, `OCPersistence/PersistenceWriter.swift:33`, `OCPersistence/Schema.swift:8-26`
- Evidence: `PersistenceWriter.swift:56-58: applicationSupport() opens Application Support/Opencode/cache.sqlite. Application Support is included in iCloud and computer backups; only Caches and tmp are not`; `grep finds no isExcludedFromBackup or URLResourceValues anywhere in Packages/OpencodeKit/Sources or App`; `Schema.swift:15-18: the same database holds message and transcript_window rows with the full message JSON, including tool output and user-prompt files stored as base64 data (research/01-opencode-server-api.md:514-516)` (+2 more)
- What happens: A user with iCloud Backup on uses the app for a month. Up to 300 MB of cached transcripts, including source code, tool output such as `cat .env`, and attached screenshots, goes into every iCloud backup and comes back on any device restored from it, though the server can serve all of it again. It persists there even after the server is removed (F39-03).
- Why it matters: Code and secrets leave the device in backups the user does not associate with this app, against the project's own privacy claim, and the backups count against iCloud storage. Apple's data storage guidelines expect re-downloadable data to be excluded from backups.
- Fix: Move the regenerable tables (project, session, message, transcript_window, catalog) into a separate SQLite file under Library/Caches, or set isExcludedFromBackup on that file and its -wal and -shm files. Keep server records, drafts and the outbox in the backed-up store. Document this next to the planned metadata-only option (SPEC.md:157).

<a id="f05-10"></a>

## F05-10: Error and retry rows give no next step: no retry time, no error type, no actions, and a static 'Working…' while the run waits

*P3 improvement · ux-flow · effort M · found by timeline-rows*

- Where: `OCSync/EventHandlers.swift:207-209`, `OCRender/TimelineRowBuilder.swift:81-85`, `FeatureTranscript/TimelineRowView.swift:108-122`
- Evidence: `The retry handler stores '"at"' and sets 'session.status = .retrying(attempt:at:)', but no view reads either (grep finds no consumer)`; `research/01-opencode-server-api.md:789: the reference shows 'retrying at …' for session.retry.scheduled`; `Fixtures/v2/2.0.32/sse/retry-429.sse sends 'type: provider.rate-limit, status: 429'; the row shows only the message and 'Attempt 2'` (+2 more)
- What happens: A provider rate-limits the run. The row reads 'Retrying / \<message> / Attempt 2' with no countdown, and 'Working…' sits below it. When a run fails, the row reads 'Run failed / \<message>' and offers nothing to tap; recovery means finding Revert message in the prompt's long-press menu and resending. While the agent waits for a permission, the timeline still says 'Working…'.
- Why it matters: Users can't tell whether to wait or act, and recovering from a failure on the phone takes several hidden steps.
- Fix: Retry row: show 'Retrying in 12 s · attempt 2' from retry.at (a TimelineView countdown), with error.type and status in muted text. Error row: add 'Try again' (revert this turn and resend its prompt with the existing undo and send path) and 'Copy details' (type, status, response body). Map common error types to targeted actions: auth to provider settings, context overflow to Compact. Replace the static 'Working…' with the real state ('Waiting for your approval', 'Retrying in 12 s', elapsed time).

<a id="f24-10"></a>

## F24-10: Copy buttons in the transcript, permission sheet and Files give no confirmation

*P3 improvement · consistency · effort S · found by touch-gestures-motion*

- Where: `OCDesign/CodeBlockView.swift:67`, `OCDesign/CodeBlockView.swift:84`, `FeatureApprovals/PermissionSheet.swift:76`, `FeatureFiles/FilesScreen.swift:132`, `FeatureServers/AddServerView.swift:96` (+1 more)
- Evidence: `OCIconButton("Copy code", icon: "copy") { OCCopy.text(code) }: the icon never changes, with no toast, announcement or haptic`; `Server screens do confirm: Text(copiedPairCommand ? "Copied" : "opencode pair") and Text("Copied \(copied)")`
- What happens: Tap the copy icon on a code block or next to the permission sheet's Resources. Nothing changes on screen, no haptic fires and VoiceOver announces nothing; iOS shows no banner when an app writes to the pasteboard.
- Why it matters: Users tap again or switch apps to check, and the behaviour is inconsistent with the server screens.
- Fix: Have a shared OCCopy button swap its icon to 'check' for about 1.5 s, post a VoiceOver 'Copied' announcement and fire a .success haptic. Use it in CodeBlockView, PermissionContent.copyable and the copy actions.
- Also reported as: F39-13 by privacy-security-ui

<a id="f27-07"></a>

## F27-07: Tool rows rebuild their presentation in body: full-input JSON pretty-printing, JSON round-trips of patches and repeated string splits on every render

*P3 improvement · performance · effort M · found by ui-performance*

- Where: `FeatureTranscript/TimelineRowView.swift:169-172`, `OCRender/ToolPresenter.swift:50-69`, `OCRender/ToolPresenter.swift:96`, `OCModels/WireValue.swift:71-77`, `OCRender/TimelineRowBuilder.swift:74` (+2 more)
- Evidence: `TimelineRowView.swift:169 'ToolRowView(presentation: ToolPresenterRegistry().presentation(item.fields), ...)' runs on every ContentRow render`; `ToolPresenter.swift:53 'value.input = (try? state.input.prettyPrinted()) ?? ""' (a JSONEncoder with sortedKeys). Every presenter pays for it through base() (line 66), even Shell and Write, which then replace or ignore it`; `ToolPresenter.swift:96 'lossy(FileDiff.self)' leads to WireValue.swift:72 'JSONDecoder().decode(T.self, from: JSONEncoder().encode(self))', which re-encodes every patch` (+3 more)
- What happens: Take a visible write tool that created a 100 KB file. Every render pretty-prints the full content through JSONEncoder, and CodeBlockView splits it several times. Renders happen on each cell configure while scrolling, on reconfigure, and on any permission event. Edit rows re-encode and decode all their patches on each render.
- Why it matters: Each tool row spends several milliseconds of main-thread time per render, which adds to scroll and streaming hitches.
- Fix: Memoize ToolPresentation per item, keyed by a fields revision, or compute it off-main in TimelineRowBuilder and pass it with the row. Give presenters a cheap title path. Pretty-print the input lazily, only when the generic details are expanded. Map FileDiff values directly with FileDiff(raw:) instead of the JSON round-trip. Compute the line count and preview once per code string.
