# UI review: Tool rows

Part of the [UI review](README.md). 20 bugs and 8 improvements, bugs first, then by severity. Paths under `Packages/OpencodeKit/Sources` are written without that prefix.

| ID | Severity | Finding |
| --- | --- | --- |
| [F06-01](#f06-01) | P1 bug | Every file-tool row is followed by a duplicate bold line repeating its subtitle; for Glob/Grep it is a fake file link |
| [F06-02](#f06-02) | P2 bug | Write rows show an 'Added file' badge while streaming, while awaiting approval, in red after failing, and for overwrites |
| [F06-03](#f06-03) | P2 bug | Edit/Patch rows fall back to escaped raw JSON whenever metadata.files is absent (awaiting approval, failed, rejected) |
| [F06-04](#f06-04) | P2 bug | V2 Patch rows never show which files they touch: the collapsed row reads only 'Patch' |
| [F07-01](#f07-01) | P2 bug | Background shell/subagent and composer-shell completion notices print raw \<shell>/\<subagent> protocol text and never show Open agent |
| [F07-02](#f07-02) | P2 bug | Finished user shells re-poll the live output file: false red 'Could not load shell output.' and head-of-file instead of the saved output |
| [F07-03](#f07-03) | P2 bug | Backgrounded shells and subagents look finished: no running state, frozen output, model-only instructions shown |
| [F07-04](#f07-04) | P2 bug | Shell output folds to its first 200 lines, so live output stops moving and the final result is hidden |
| [F07-05](#f07-05) | P2 bug | Subagent row expands into its prompt labelled 'json' and a raw \<subagent sessionID=…> result; tapping the row doesn't open the agent |
| [F07-06](#f07-06) | P2 bug | Tool output never wraps; at accessibility sizes an iPhone shows about 15 characters per line |
| [F07-07](#f07-07) | P2 bug | In Detailed mode, opening a tool group expands every child, dumping JSON input and full output for each Read/Grep/Webfetch |
| [F07-08](#f07-08) | P2 bug | Questions summary lists all questions then all answers, losing which answer belongs to which question |
| [G04-M2](#g04-m2) | P2 bug | Images returned by tools are discarded: reading a screenshot shows only 'Image read successfully' |
| [F06-05](#f06-05) | P2 bug | Inline diff card height is raw patch line count × 24pt: blank band for real patches, clipped inner scroller at larger text |
| [G04-M1](#g04-m1) | P2 bug | Agent shell rows that finish while on screen keep the last polled buffer, dropping the command's final output |
| [F06-09](#f06-09) | P3 bug | Tool errors render in full under collapsed rows and are repeated inside the expanded output |
| [F07-09](#f07-09) | P3 bug | Tool status presentation: error text shown twice, 'Exit 0' badge on every success, signal kills look successful |
| [F06-07](#f06-07) | P3 bug | Tool paths are shown raw: Edit/Write subtitles tail-truncate away the file name; Read rows wrap whole absolute paths |
| [F06-13](#f06-13) | P3 bug | Tool row icon and chevron are vertically misaligned and fixed-size |
| [F07-13](#f07-13) | P3 bug | ANSI colour codes in shell and CodeMode output are shown as raw escape text |
| [F06-06](#f06-06) | P3 improvement | In the default Compact preset, opening an Edit row reveals a second, collapsed diff card; tapping its file name navigates away |
| [F06-10](#f06-10) | P3 improvement | Glob/Grep summary text is cryptic: '/' default, raw '.', no zero or truncated counts, files called 'matches' |
| [F06-11](#f06-11) | P3 improvement | Explore rows render the tool name in the same muted style as the path, and file tools use two different header layouts |
| [F06-12](#f06-12) | P3 improvement | Expanded Read/Glob/Grep content is raw: redundant JSON input, unwrapped plain text, and result paths that can't be opened |
| [F07-10](#f07-10) | P3 improvement | Tool group labels reuse row titles, producing 'Used 2 Read, General' or the whole shell command as the header |
| [F07-11](#f07-11) | P3 improvement | Webfetch, skill and todo rows dump raw JSON input and unformatted output instead of a compact summary |
| [F06-14](#f06-14) | P3 improvement | Running and streaming tools have no activity cue: a static grey badge, and nothing at all inside collapsed groups |
| [F07-12](#f07-12) | P3 improvement | MCP and CodeMode rows: raw server_tool names, 'Completed · MCP' on every call, empty boxes for nested calls |

<a id="f06-01"></a>

## F06-01: Every file-tool row is followed by a duplicate bold line repeating its subtitle; for Glob/Grep it is a fake file link

*P1 bug · functional · effort S · found by tool-rows-files*

- Where: `FeatureTranscript/ToolRowView.swift:31-33`, `FeatureTranscript/SessionScreen.swift:77`, `FeatureTranscript/SessionScreen.swift:104-106`, `OCSync/FilesModel.swift:153-166`, `OCModels/Review.swift:44-50` (+2 more)
- Evidence: `iphone/transcript-tools.png`; `ipad/ipad-transcript-tools.png`; `crops/tool-rows-files/iphone-tools-crop.png (Read row text at y~282pt, duplicate at ~332pt, next row at ~382pt: each tool takes ~100pt instead of ~50pt)` (+4 more)
- What happens: iPhone 17 Pro and iPad, light mode, default Compact preset. Expand 'Used 3 Read, Glob, Grep'. Each child row is followed by a second 44pt row in medium-weight primary text repeating its subtitle: 'sample.txt', '/ pattern=*.txt · (1 match)', '. pattern=original · (1 match)'. The duplicate is indented differently from both the icon and the title.

  Tapping the Grep line calls fileLinks.open(". pattern=original · (1 match)"). FilesModel.openLink finds no match, and ReviewPath accepts the string as a location-relative path. The Files viewer then opens (a sheet on iPhone) with a new tab titled '. pattern=original · (1 match)' and the error 'File not found: . pattern=original · (1 match)'.

  Tapping the Glob line: '/ pattern=…' is treated as an absolute path outside the project, so ReviewPath returns nil. Only FilesModel.error is set, and the review panel's saved tab is persisted as Files. On iPhone the tap appears to do nothing, or it reopens Files on an unrelated earlier file. On iPad the panel jumps to the Files tab.

  A Read of a directory (V2 read lists directories) tries to open the directory as a file. On Edit and Write rows the path appears a second time, and a third time when expanded (once in the DiffCardView header). VoiceOver gets two stops per row; the second is an unexplained button that repeats the subtitle.
- Why it matters: This is the most visible defect in the primary reading flow. Every exploration or edit group is twice as tall and visually noisy. Glob/Grep rows present a fake link that leads to bogus tabs, errors or a dead tap. VoiceOver users hear every subtitle twice.
- Fix: Delete ToolRowView.swift:31-33. Add a ToolPresentation.path (the raw input path), set only by Read (file targets), Edit and Write; never use the composed subtitle and never set it for Glob/Grep. Make that path openable from inside the row: a trailing 44pt 'Open file' icon button beside the chevron, or a context-menu item plus .accessibilityAction(named: "Open file"). For Edit/Patch, the DiffCardView header link is enough. Add a ReadSnapshots case that injects ocFileLinks so this layout is covered.
- Verifier's note: Keep design.md:131's intent without a second visible row. Expose the raw input path (Read on files, Edit, Write) through the existing header: a context-menu 'Open file' item plus .accessibilityAction(named:), or a trailing icon. Never pass the composed Glob/Grep subtitle to fileLinks.open. Add a ReadSnapshots case that injects ocFileLinks.
- Also reported as: F24-03 by touch-gestures-motion, F25-02 by l10n-text, F30-01 by visual-polish-iphone, F32-01 by design-parity, F35-03 by sweep-read-snapshots

<a id="f06-02"></a>

## F06-02: Write rows show an 'Added file' badge while streaming, while awaiting approval, in red after failing, and for overwrites

*P2 bug · state · effort S · found by tool-rows-files*

- Where: `OCRender/ToolPresenter.swift:113`, `OCDesign/TimelineChrome.swift:42-46`, `FeatureTranscript/ToolRowView.swift:57`, `FeatureTranscript/ToolRowView.swift:96`, `OCDesign/CodeBlockView.swift:66`
- Evidence: `Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/ReadSnapshots/capture-_-name-height.tool-write-streaming-light-393.png`; `Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/ReadSnapshots/capture-_-name-height.tool-write-running-light-393.png`; `Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/ReadSnapshots/capture-_-name-height.tool-write-error-dark-393.png (red 'Added file' above 'The tool could not complete this action.')` (+3 more)
- What happens: The model streams a Write, or the Write waits for permission. The only badge on the row says 'Added file', because the badge replaces the 'Streaming'/'Running' status, while the permission card below is still asking whether to allow it. If the write fails or is rejected, the row still says 'Added file', now in red, next to the error. A successful overwrite of an existing file is also labelled 'Added file'. Separately, for an extensionless file (Makefile, Dockerfile), language() returns "", so the code block's language label is blank.
- Why it matters: The row tells the user a file was created when it was not, or before they have approved it. This is misleading at exactly the moment they are deciding.
- Fix: Set the badge only when status == "completed". Derive it from the result: 'Created' when the content says 'Created file', otherwise 'Updated' (or omit it). In every other state, leave badge nil so Running, Streaming and Error show. Make language() return nil for an empty extension.
- Verifier's note: Set the badge only when status == completed, or drop it as the desktop does. Derive 'Created' or 'Updated' from the content text. Make language() return nil for an empty extension.
- Also reported as: F35-02 by sweep-read-snapshots

<a id="f06-03"></a>

## F06-03: Edit/Patch rows fall back to escaped raw JSON whenever metadata.files is absent (awaiting approval, failed, rejected)

*P2 bug · functional · effort M · found by tool-rows-files*

- Where: `OCRender/ToolPresenter.swift:96`, `FeatureTranscript/ToolRowView.swift:56`, `FeatureTranscript/ToolRowView.swift:82-85`, `OCFoundation/JSONValue.swift:80-86`, `OCSync/StreamingHandlers.swift:61-62`
- Evidence: `Fixtures/v2/2.0.32/sse/permission-reject.sse: while awaiting approval the files preview is only on permission.asked, and session.tool.failed {type: permission.rejected} leaves the tool's metadata null (REST permission-reject.json: status error, metadata null)`; `ToolPresenter.swift:96: value.files = tool.toolState.fields.metadata?["files"]?.lossy(FileDiff.self).values ?? []`; `ToolRowView.swift:56: if presentation.files.isEmpty { genericDetails }, which renders CodeBlockView(presentation.input, language: "json")` (+2 more)
- What happens: Detailed or Everything preset, or Compact after expanding the row. Three cases: an Edit waiting for approval, an Edit that failed (oldString not found) or was rejected, or a V2 Patch before it completes. None of these has metadata.files. The row expands to a 'json' block such as {"newString" : "func load() {\n    …", "oldString" : …, "path" : …}: JSONEncoder output with escaped \n on one long line, in a non-wrapping block that scrolls horizontally. Failed rows add the error text, twice. Migrated V1 edits, which keep their V1 metadata (research/01 §9.4), probably land here too.
- Why it matters: These are the moments the user most needs to see what the agent tried to change: while approving, and after a failure or rejection. They get unreadable JSON instead of a diff.
- Fix: In EditPresenter, when files is empty, synthesize a FileDiff from EditInput.oldString/newString (a unified diff of the two strings, labelled with the input path), matching the reference fallback. In PatchPresenter, show PatchInput.patchText (currently unused) in a CodeBlockView with language "diff". Add snapshots for running and rejected edits without metadata.
- Verifier's note: Mirror the desktop edit renderer: when metadata.files is empty, diff oldString against newString under the input path. For patch, show patchText as a 'diff' block. While the input is still streaming, state.input is a partial JSON string; don't pretty-print it as JSON.

<a id="f06-04"></a>

## F06-04: V2 Patch rows never show which files they touch: the collapsed row reads only 'Patch'

*P2 bug · functional · effort S · found by tool-rows-files*

- Where: `OCRender/ToolPresenter.swift:100-105`, `OCModels/ToolInputs.swift:121-125`, `Packages/OpencodeKit/Tests/ReadSnapshots/ReadSnapshots.swift:110`
- Evidence: `ToolPresenter.swift:104: var value = EditPresenter().detail(tool); value.title = "Patch"; return value, so the subtitle comes from EditInput.filePath (filePath/file_path/path)`; `research/01 §9.2: the V2 patch input is only patchText ('*** Begin Patch … *** Update File: …'); GPT-family models get patch instead of edit and write`; `ToolInputs.swift:124: PatchInput.patchText is defined but never used` (+1 more)
- What happens: With a GPT-family model, every file change is a patch call. In Compact the group reads 'Used 3 Patch', and each row shows only the edit icon, 'Patch' and a chevron. To learn which file changed, the user must expand the row and then expand each collapsed diff card.
- Why it matters: For a whole class of models the transcript loses its most useful summary: which files the agent changed.
- Fix: Derive the subtitle from metadata.files: the first file's relative path plus '+N more', or 'N files'. Before completion, parse the '*** (Add|Update|Delete) File:' and '*** Move to:' lines in patchText. Update the snapshot fixture to a realistic patchText input.

<a id="f07-01"></a>

## F07-01: Background shell/subagent and composer-shell completion notices print raw \<shell>/\<subagent> protocol text and never show Open agent

*P2 bug · functional · effort M · found by tool-rows-exec*

- Where: `OCRender/TimelineRowBuilder.swift:96-105`, `FeatureTranscript/TimelineRowView.swift:123-127`, `OCSync/EventHandlers.swift:162`
- Evidence: `TimelineRowBuilder.swift:102 uses 'default: f.text.isEmpty ? message.type.capitalized : f.text', so the text of a 'synthetic' message (written for the model) is rendered verbatim. Line 104 takes the notice's link from 'f.metadata?["sessionID"]'.`; `opencode reference d0732ea packages/core/src/session/subagent-completion.ts:42-43: text is '<subagent sessionID="…" state="…" description="…">\n<full report>\n</subagent>' and metadata is '{source: "subagent", childID, agent, state}'. There is no 'sessionID' key, so the Open agent button at TimelineRowView.swift:126 never appears.`; `packages/core/src/shell/result.ts notification()/userNotification() produce '<shell id=… state=… command=…>\n<output>\n</shell>'. packages/core/src/session/session.ts:206-216 posts this, prefixed 'The following shell command was executed by the user:' and with no description, after every composer '!' command.` (+1 more)
- What happens: Run `!npm test` from the composer and let it exit 1. The notice's metadata makes shellFailed true, so even in Compact a separate muted row appears: 'The following shell command was executed by the user: \<shell id="sh_…" state="completed" command="npm test">', then the whole captured output (up to 50 KiB), then '\</shell>', right below the shell row that already shows the same output. When a background subagent finishes, its notice shows `<subagent sessionID="ses_…" …>` plus the entire report, with no Open agent button. Plan-mode reminders and the 'moved to the background' note also appear verbatim.
- Why it matters: Raw protocol markup and duplicated full output flood the transcript in small grey text. The one row announcing that a background subagent finished gives no way to open it.
- Fix: Special-case `synthetic` messages in TimelineRowBuilder. For metadata.source shell/subagent, build a short label from metadata.state and agent plus the description, for example 'Shell failed · npm test' or 'General agent finished'. Take the link from metadata.childID. Hide synthetic messages without a description unless they failed, as the desktop does. Never render `text` verbatim.

<a id="f07-02"></a>

## F07-02: Finished user shells re-poll the live output file: false red 'Could not load shell output.' and head-of-file instead of the saved output

*P2 bug · state · effort M · found by tool-rows-exec*

- Where: `FeatureTranscript/ToolRowView.swift:43-47`, `FeatureTranscript/ToolRowView.swift:60-61`, `FeatureTranscript/ToolRowView.swift:91-94`, `OCSync/SessionReadActions.swift:90-117`, `FeatureTranscript/TimelineRowView.swift:190-195`
- Evidence: `updatePolling() starts ShellOutputModel for any visible row that has a shellID, even when the status is exited/timeout/killed. StandaloneShell always sets shellID (TimelineRowView.swift:194).`; `SessionReadActions.swift:98 reads from cursor nil (byte 0) with limit 65,536, and for a non-running shell stops after that single page (:111). ToolRowView.swift:60 then prefers shell.output over presentation.output, the saved tail.`; `SessionReadActions.swift:112-113 turns any failure into 'Could not load shell output.', shown in red at ToolRowView.swift:61. The server looks shells up only in an in-memory map that keeps the last 25 exited shells (opencode reference packages/core/src/shell.ts:31, 153-156), so after a server restart every old shell fails.` (+1 more)
- What happens: Reopen an older session after the opencode service restarted, in Detailed or Everything mode (composer shell rows are separate and expanded there). Every '!' command row shows its saved output followed by a red 'Could not load shell output.'. For a recent command with more than 64 KiB of output, the row shows the first 64 KiB of the file instead of the saved tail with the result. Every time the row scrolls back on screen it downloads again from byte 0.
- Why it matters: Users see false errors on correct history, lose the end of long outputs, and pay for repeated downloads on cellular.
- Fix: Do not poll shells whose status is exited, timeout or killed: use f.output. Poll only while running or backgrounded. Treat not-found as 'missing': stop silently and keep presentation.output. For a finished shell, page until cursor >= size and keep the tail. Cache cursor and output per shellID outside the view so remounts resume where they left off.

<a id="f07-03"></a>

## F07-03: Backgrounded shells and subagents look finished: no running state, frozen output, model-only instructions shown

*P2 bug · state · effort M · found by tool-rows-exec*

- Where: `OCRender/ToolPresenter.swift:116-137`, `FeatureTranscript/ToolRowView.swift:58-61`, `FeatureTranscript/ToolRowView.swift:86`
- Evidence: `Background results arrive with status 'completed' but metadata '{status: "running", shellID}' (opencode reference packages/core/src/tool/plugin/shell.ts:80, 96-101) or '{sessionID, status: "running"}' (tool/plugin/subagent.ts:19-27, 264). See also research/01-opencode-server-api.md:1000.`; `ToolRowView.swift:86 derives running only from presentation.status, so ShellOutputModel makes one request and stops (SessionReadActions.swift:111). ShellPresenter adds no badge because there is no exit code.`; `The row's output is text meant for the model: 'You will be notified automatically… DO NOT poll for completion…' (shell.ts:26-27) and 'DO NOT sleep, poll for progress…' (subagent.ts:22-26).` (+2 more)
- What happens: The agent starts `npm run dev` with background: true, or delegates a background subagent. The row reads 'Shell / npm run dev' with no badge, exactly like a finished command. Expanded, its output is either a snapshot from the moment it first appeared or the model instructions above, and it never updates while watched. The subagent row shows no Running state while the child keeps working, and nothing on the phone can move a long blocking command to the background.
- Why it matters: Users can't tell that a dev server or subagent is still running, and the output they read is stale.
- Fix: Treat metadata.status == 'running' as running: show a 'Background' badge and keep polling while the shell exists or, for subagents, while the store reports the child session busy. Hide the model-only instruction text. Show the final exit state once the completion notice arrives. Add the planned 'Send to background' action to running shell rows.

<a id="f07-04"></a>

## F07-04: Shell output folds to its first 200 lines, so live output stops moving and the final result is hidden

*P2 bug · functional · effort S · found by tool-rows-exec*

- Where: `OCDesign/CodeBlockView.swift:20-33`, `FeatureTranscript/ToolRowView.swift:60`, `OCSync/SessionReadActions.swift:106-107`
- Evidence: `CodeBlockView.swift:21 sets 'preview' to the first 200 lines ('prefix(200)'). The Text at :26 renders only that head, and :31's 'Show full output (N lines)' opens a sheet.`; `Shell tool content is the tail of the command output plus closing notices: 'Exited with code N' and '[showing lines X-Y of Z; full output saved to …]' (opencode reference packages/core/src/shell.ts:242-249, shell/result.ts notice()). GenericToolPresenter joins them at the end of presentation.output.`; `ARCHITECTURE.md §3.1 plans folding output above 200 lines but does not say which end to keep. The desktop console is a 240 px vertically scrolling box (message-part.css:453-458).`
- What happens: The agent runs `swift test` and the row is open (Detailed or Everything mode, or tapped). After 200 lines the visible text stops changing; only the button's line count keeps rising, so the run looks hung. For a completed run, the summary, failure list and 'Exited with code 1' at the end are hidden until the user opens the sheet.
- Why it matters: The latest lines and the verdict, the most important part of terminal output, are exactly what the app hides.
- Fix: For shell and execute output, show the last 200 lines with the 'Show full output' control above them, or use a fixed-height scroll view anchored to the bottom. Keep head-folding for other code blocks.

<a id="f07-05"></a>

## F07-05: Subagent row expands into its prompt labelled 'json' and a raw \<subagent sessionID=…> result; tapping the row doesn't open the agent

*P2 bug · ux-flow · effort M · found by tool-rows-exec*

- Where: `FeatureTranscript/ToolRowView.swift:34-37`, `FeatureTranscript/ToolRowView.swift:79-85`, `OCRender/ToolPresenter.swift:129-137`
- Evidence: `The '.subagent' style falls through to 'default: genericDetails', which renders presentation.input with language 'json' (input is the plain-English prompt, ToolPresenter.swift:136) and then the raw tool content.`; `Recorded server data: Fixtures/v2/2.0.32/rest/subagent.json:349 has prompt 'Report fixture child result.'; :355 has content '<subagent sessionID="ses_eb8719b2effeJSUHThQ2ydE721" state="completed">\nFixture child result.\n</subagent>'.`; `Snapshots: tapping the header only toggles the disclosure, 'Open agent' is a separate ghost button, and the result is cut at 'Completed succe' (Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/ReadSnapshots/capture-_-name-height.tool-subagent-completed-light-393.png, capture-_-name-height.tool-task-running-light-393.png).` (+1 more)
- What happens: Open the UI-smoke 'subagent' session in Everything mode. The 'General / Fixture child' row is expanded: a 'json' block containing prose, then a 'Text' block starting `<subagent sessionID="ses_…" state="completed">`. With a real multi-paragraph prompt or report, each paragraph is one line that must be scrolled sideways. Tapping the header just collapses the row; opening the child needs the smaller 'Open agent' button, which VoiceOver announces identically for every subagent.
- Why it matters: Opening the child is the main action on a subagent row, yet the row's own tap target does something else and reveals protocol text.
- Fix: Make the header open the child, with a chevron-right and an accessibility hint naming the agent. Alternatively keep the disclosure but render the prompt and result as wrapped Markdown under 'Prompt' and 'Result' labels with the \<subagent> wrapper stripped. Title the row with the agent's display name (for example 'General agent') instead of `agent.capitalized`.

<a id="f07-06"></a>

## F07-06: Tool output never wraps; at accessibility sizes an iPhone shows about 15 characters per line

*P2 bug · accessibility · effort S · found by tool-rows-exec*

- Where: `OCDesign/CodeBlockView.swift:25-29`
- Evidence: `CodeBlockView puts the text in ScrollView(.horizontal) with .fixedSize(horizontal: true) and has no wrap mode.`; `At accessibility5, output is clipped at 'Completed succe' and JSON at '"name" : "rev' (Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/ReadSnapshots/capture-_-name-height.tool-shell-completed-light-393.png, capture-_-name-height.Exit-2-light-393.png, capture-_-name-height.tool-subagent-completed-light-393.png, capture-_-name-height.tool-webfetch-completed-light-393.png).`; `docs/design.md:19 says text wraps and scales, and docs/design.md:121 forces wrapped diff lines at accessibility sizes. The desktop console uses 'white-space: pre-wrap; overflow-x: hidden' (message-part.css:453-476).`
- What happens: At the largest text size on an iPhone, expand any shell row. Every output line longer than about 15 characters is clipped and must be scrolled sideways one block at a time, and a compiler error takes several swipes per line. Prose outputs (subagent prompts and reports, fetched pages, skill content) put whole paragraphs on single lines.
- Why it matters: Low-vision users effectively cannot read command output, and everyone else scrolls sideways to read logs on a phone.
- Fix: Wrap tool output by default, or at least at accessibility sizes and for output and prose blocks, following the diff viewer's rule. Keep horizontal scrolling as an option for source code.
- Verifier's note: Honour the existing 'wrapLines' AppStorage (default on) in CodeBlockView and force wrapping at accessibility sizes, matching DiffView.
- Also reported as: F22-10 by a11y-dynamic-type, F35-05 by sweep-read-snapshots

<a id="f07-07"></a>

## F07-07: In Detailed mode, opening a tool group expands every child, dumping JSON input and full output for each Read/Grep/Webfetch

*P2 bug · interaction · effort S · found by tool-rows-exec*

- Where: `FeatureTranscript/TimelineRowView.swift:70-73`, `FeatureTranscript/TimelineRowView.swift:169-170`, `OCRender/TimelineRow.swift:15`
- Evidence: `Group children are rendered with the session's 'detail'. ContentRow passes 'expanded: detail.expanded', which is true for .detailed (TimelineRow.swift:15), so every grouped tool starts open.`; `The snapshot rendered with .everything shows what a Detailed user gets after opening a group: the Read child opens to a 'json' input block plus its full output block (Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/ReadSnapshots/capture-_-name-height.row-toolGroup-light-393.png).`; `Desktop grouped tools use contentDefaultOpen, which opens only shell, edit and thinking per preset and leaves other tools collapsed (session-timeline-row.tsx:246, 385-397; current-tool-state.ts:93-115).`
- What happens: Switch the detail to Detailed and open 'Used 8 Read, Grep'. All eight children are already open, each showing pretty-printed input JSON and up to 200 lines of file content, so one tap produces a wall of code.
- Why it matters: Detailed mode is meant to show shell and edits while keeping exploration compact; opening one group buries the timeline.
- Fix: Inside a group, expand only the categories the preset expands (shell and edit) and keep other tools collapsed. Open failed tools, as the desktop does.
- Verifier's note: Derive each tool's default from its category: shell and execute, or edit, write and patch, open only when the preset expands that category; everything else starts collapsed, in Everything too. Correction: the desktop error card starts collapsed, and it opens a failed tool only when that tool's category is hidden.

<a id="f07-08"></a>

## F07-08: Questions summary lists all questions then all answers, losing which answer belongs to which question

*P2 bug · functional · effort S · found by tool-rows-exec*

- Where: `OCRender/ToolPresenter.swift:139-150`, `FeatureTranscript/ToolRowView.swift:76-78`, `OCRender/TimelineRowBuilder.swift:77`
- Evidence: `input holds the questions joined by blank lines and output holds the answers joined by newlines. The view prints them as two separate Texts, and the row has no subtitle.`; `Protocol: questions is an array of one or more entries and metadata.answers is string[][] (research/01-opencode-server-api.md:987; Fixtures/v2/2.0.32/snapshots/question-form.json:127).`; `Desktop pairs each question with its answer, shows '(no answer)' for gaps, uses the subtitle '{{count}} answered', and shows a muted 'Questions dismissed' for a dismissal (tool-renderer.tsx:2350-2395, 1376-1384).` (+1 more)
- What happens: The agent asks three questions (database, test framework, CI) and the user skips the second. The expanded row shows the three questions, then 'Postgres', a blank line and 'GitHub Actions', so the pairing has to be guessed. Collapsed, the row says only 'Questions'. If the user dismisses the form, an ungrouped red 'Error' row reading 'The user dismissed this question' appears even in Compact, and the text repeats when expanded.
- Why it matters: The record of the user's decisions is ambiguous, and an ordinary dismissal looks like a failure.
- Fix: Render each question followed by its answer, or '(no answer)'. Add a subtitle such as '3 answered'. Render a dismissal as a muted 'Questions dismissed' line instead of an error.

<a id="g04-m2"></a>

## G04-M2: Images returned by tools are discarded: reading a screenshot shows only 'Image read successfully'

*P2 bug · functional · effort M · found by verifier G04*

- Where: `OCRender/ToolPresenter.swift:54`, `FeatureTranscript/ToolRowView.swift:79-85`
- Evidence: `ToolPresenter.swift:54: value.output = state.content.filter { $0.type == "text" }.map { $0.fields.text }.joined(separator: "\n"), so file items are dropped`; `opencode reference packages/core/src/tool/plugin/read.ts:175-185: an image or PDF read returns [{text: 'Image read successfully'}, {type: 'file', uri: 'data:<mime>;base64,…', mime, name}]`; `research/01-opencode-server-api.md §9.3: MCP and CodeMode results carry images as data: file items` (+3 more)
- What happens: The agent reads a UI screenshot (read path 'docs/screen.png') or a browser MCP tool returns a screenshot. In any preset, expanding the row shows a json block {"path": "docs/screen.png"} and a Text block 'Image read successfully'. The image never appears, and an MCP-produced image cannot be reached any other way.
- Why it matters: On the phone, users can't see the images the agent looked at or produced, a v1.0 parity item. They can't check visual work without going to the computer.
- Fix: Collect the image and PDF file items in the presenters into a ToolPresentation.attachments array. Render downsampled thumbnails off the main actor with ImageIO, as ComposerChrome already does, with tap to zoom or Quick Look and Save/Copy. Show PDFs as a file chip.

<a id="f06-05"></a>

## F06-05: Inline diff card height is raw patch line count × 24pt: blank band for real patches, clipped inner scroller at larger text

*P2 bug · layout · effort M · found by tool-rows-files*

- Where: `OCDesign/DiffCardView.swift:32`, `OCDesign/DiffView.swift:108`, `OCDesign/DiffView.swift:228`, `OCRender/DiffDocument.swift:81-84`, `OCDesign/CodeCollection.swift:45`
- Evidence: `DiffCardView.swift:32: diff(full: false).frame(height: min(4_800, max(48, CGFloat(patch.components(separatedBy: "\n").count) * 24)))`; `Fixtures/v2/2.0.32/snapshots/permission-allow.json: the real edit patch starts with 'Index:', '=====', '---', '+++' and '@@'. That is 9 components, giving a 216pt frame, but only 3 rows render (72pt at default size), so about 144pt is empty`; `DiffDocument.swift:81-84: pre-hunk lines go to doc.headers and are not rows; DiffView.swift:228 sets lineHeight = max(24, ceil(font * 1.65)) with font 13/16/19/22 (rows 24/27/32/37pt)` (+2 more)
- What happens: Detailed preset (edit rows expanded), default text size: a typical single-hunk opencode edit leaves a 100–150pt empty band between the diff and 'Show full diff'. At xLarge text and above, or whenever code lines wrap (most lines on iPhone), the frame is shorter than the content. The rest of the diff is then clipped behind a vertical scroller nested inside the transcript, and that embedded collection also carries a pull-to-refresh control (CodeCollection.swift:45).
- Why it matters: Edit diffs, the core review surface in the transcript, either waste a lot of space or hide lines behind a scroll-within-scroll that is easy to miss and fights the transcript's own scrolling.
- Fix: Size the card from what OCDiffView actually measures: it already computes per-row heights in prepareSections, so publish their sum through a binding or preference and use min(cap, measured). Before measurement, estimate from the parsed rows rather than raw lines. For inline cards, disable vertical scrolling and the refresh control. Consider capping inline cards at about 20 rows, with 'Show full diff' for the rest.
- Verifier's note: Use the sum of the heights that prepareSections already measures, published back to the card and capped. Before measurement, estimate from DiffRows (excluding doc.headers), not raw lines. Make the refresh control opt-in.
- Also reported as: F13-10 by approvals-permission, F16-04 by diff-renderer, F22-02 by a11y-dynamic-type, F24-02 by touch-gestures-motion, F35-01 by sweep-read-snapshots, F36-03 by sweep-review-snapshots, F38-02 by sweep-approval-server-snapshots

<a id="g04-m1"></a>

## G04-M1: Agent shell rows that finish while on screen keep the last polled buffer, dropping the command's final output

*P2 bug · state · effort S · found by verifier G04*

- Where: `FeatureTranscript/ToolRowView.swift:60`, `FeatureTranscript/ToolRowView.swift:46-47`, `FeatureTranscript/ToolRowView.swift:91-94`, `OCSync/SessionReadActions.swift:90-117`, `OCSync/StreamingHandlers.swift:63-69` (+1 more)
- Evidence: `ToolRowView.swift:60: CodeBlockView(shell.output.isEmpty ? presentation.output : shell.output, language: "output", closed: !running)`; `ToolRowView.swift:92: guard visible, phase == .active, let store, let id = presentation.shellID else { shell.stop(); return }`; `StreamingHandlers.swift:63-69: session.tool.progress sets metadata {shellID}; session.tool.success replaces the state with the success metadata` (+3 more)
- What happens: Detailed or Everything preset (shell rows are separate and expanded), or a shell row the user opened in Compact. The agent runs `swift test`; the row polls every second and shows live output. When the tool completes, the success event replaces the metadata with one that has no shellID. updatePolling then calls shell.stop(), but shell.output is not empty, so the row keeps the last polled snapshot. Anything printed after the last poll, which is often the test summary or the failure, is missing. The saved result (output tail plus 'Exited with code N' or the truncation note) never appears until the cell is recycled.
- Why it matters: The row reports the command as finished yet can omit its verdict lines, so users may misread test or build results.
- Fix: In ToolRowView, show presentation.output whenever the tool is no longer running or presentation.shellID is nil, and use shell.output only while running. Alternatively, on the running-to-completed transition, read from the saved cursor to the end before stopping. Keep per-shell progress outside the view, as the desktop's shell-output.ts does.

<a id="f06-09"></a>

## F06-09: Tool errors render in full under collapsed rows and are repeated inside the expanded output

*P3 bug · layout · effort S · found by tool-rows-files*

- Where: `OCRender/ToolPresenter.swift:56-59`, `FeatureTranscript/ToolRowView.swift:28-30`, `OCRender/TimelineRowBuilder.swift:77`
- Evidence: `Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/ReadSnapshots/capture-_-name-height.tool-read-error-light-393.png`; `Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/ReadSnapshots/capture-_-name-height.tool-glob-error-light-393.png`; `Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/ReadSnapshots/capture-_-name-height.tool-unknown-error-light-393.png` (+3 more)
- What happens: A tool fails. Errored tools are always shown as separate rows (TimelineRowBuilder.swift:77). Collapsed, the whole message renders in red under the row, starting under the icon rather than the title. A malformed-arguments error can fill most of an iPhone screen. Expanded, the same message appears again at the top of the 'Text' output block (and in the recorded rejected-edit fixture, 'Keep the original fixture text.' appears twice).
- Why it matters: Errors are noisy, duplicated and can swamp the transcript.
- Fix: Stop prepending error.message to output. Show errorMessage once, aligned with the title column, with .lineLimit(3) while collapsed and in full when expanded. Offer 'Copy error' in a context menu.
- Also reported as: F35-10 by sweep-read-snapshots

<a id="f07-09"></a>

## F07-09: Tool status presentation: error text shown twice, 'Exit 0' badge on every success, signal kills look successful

*P3 bug · consistency · effort S · found by tool-rows-exec*

- Where: `OCRender/ToolPresenter.swift:23-25`, `OCRender/ToolPresenter.swift:124-125`, `FeatureTranscript/TimelineRowView.swift:192-195`, `OCDesign/CodeBlockView.swift:60`
- Evidence: `When expanded, 'The tool could not complete this action.' appears as the first output line and again in red below the row (Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/ReadSnapshots/capture-_-name-height.tool-shell-error-light-393.png, capture-_-name-height.tool-task-error-light-393.png, capture-_-name-height.tool-execute-error-light-393.png).`; `Recorded success metadata is '{status: completed, truncated: false, exit: 0}' (Fixtures/v2/2.0.32/snapshots/shell-output.json:114), so ShellPresenter shows an 'Exit 0' badge. The desktop reports only non-zero exits (ui i18n 'Command exited with code {{code}}').`; `shellFailed ignores metadata.signal. A killed process is reported with 'signal' and no 'exit', plus the content line 'Killed by SIGKILL' (opencode reference packages/core/src/shell/result.ts notice()).` (+1 more)
- What happens: Every successful agent command carries an 'Exit 0' badge, which takes a whole extra line at large text sizes. A test binary that segfaults (SIGSEGV) looks exactly like a pass. A failed tool, expanded, states its error twice.
- Why it matters: Noise on the common case and no signal on the rare important one make failures harder to spot.
- Fix: Show the exit badge only for non-zero codes. Treat a signal as a failure with a 'Killed (SIGSEGV)' badge. Map composer-shell timeout and killed to the same red 'Timed out' and 'Cancelled' badges. Stop prefixing the error to the output, or hide the red line when expanded. Use one word for the running state.
- Verifier's note: Fix the duplicated error under F06-09. Here: show only non-zero exits ('Command exited with code N' in the desktop's wording), treat a signal as a failure, and map composer timeout and killed to the red badges.

<a id="f06-07"></a>

## F06-07: Tool paths are shown raw: Edit/Write subtitles tail-truncate away the file name; Read rows wrap whole absolute paths

*P3 bug · layout · effort M · found by tool-rows-files*

- Where: `OCDesign/TimelineChrome.swift:37`, `OCDesign/TimelineChrome.swift:40`, `OCRender/ToolPresenter.swift:74`, `OCRender/ToolPresenter.swift:95`, `OCRender/ToolPresenter.swift:112`
- Evidence: `TimelineChrome.swift:40: Text(subtitle).font(OCType.small).foregroundStyle(OCColor.textMuted).lineLimit(2) (default tail truncation)`; `TimelineChrome.swift:37: the inline (Read/Glob/Grep) variant has no line limit`; `research/01 §9.2: glob returns absolute paths one per line and grep prints '<abs path>:', so the model's follow-up read and edit calls usually carry absolute paths` (+2 more)
- What happens: iPhone 17 Pro. A grouped Edit row has about 294pt of text width at the default 13pt, so two lines hold roughly 90 characters. With a path such as '/Users/\<name>/dev/\<project>/FeatureTranscript/ToolRowView.swift' (~100 characters), the subtitle is cut at the end, so the file name, the one part that matters, is lost. At larger text sizes this happens to much shorter paths. Read rows wrap the same path across several muted lines. The expanded diff card shows 'Packages/…/ToolRowView.swift', so one file appears in two forms.
- Why it matters: Users can't tell which file a collapsed edit touched, and Read groups become walls of grey path text.
- Fix: Relativize paths against the session directory (strip directory + '/' as ReviewPath does). Render the file name in primary text with the directory muted and middle-truncated, on a single line (reuse the TurnChangesCard layout). Keep the full path in the accessibility label and a 'Copy path' context action.
- Verifier's note: Follow the desktop: show the file name prominently, with the relativized directory muted and middle-truncated on one line, as TurnChangesCard already does. Keep the full path in the accessibility label and a Copy path action.
- Also reported as: F35-14 by sweep-read-snapshots, G13-M1 by verifier G13

<a id="f06-13"></a>

## F06-13: Tool row icon and chevron are vertically misaligned and fixed-size

*P3 bug · visual · effort S · found by tool-rows-files*

- Where: `OCDesign/TimelineChrome.swift:33-34`, `OCDesign/TimelineChrome.swift:50`, `OCDesign/Icon.swift:11-17`
- Evidence: `crops/tool-rows-files/iphone-tools-crop.png (measured on transcript-tools.png: icon centre about 285.8pt, text about 283.2pt, chevron about 279.8pt)`; `TimelineChrome.swift:33-34: HStack(alignment: .top) { OCIcon(icon)…padding(.top, OCSpacing.xs) … OCIcon(expanded ? "chevron-down" : "chevron-right", size: 12) } (the chevron has no matching padding)`; `Accessibility5 snapshots: the 16pt icon and 12pt chevron stay tiny next to text that is roughly twice the size`
- What happens: In every tool row the glyph sits about 3pt below the text and the chevron about 3pt above it, about 6pt apart. At accessibility text sizes the icons do not grow.
- Why it matters: A small but visible polish defect, repeated on every row of every transcript.
- Fix: Align the icon and chevron to the first text line (for example .alignmentGuide or .firstTextBaseline with matching offsets), or give both the same top padding. Scale them with @ScaledMetric; the Dynamic Type part fits the M9a accessibility pass.

<a id="f07-13"></a>

## F07-13: ANSI colour codes in shell and CodeMode output are shown as raw escape text

*P3 bug · visual · effort S · found by tool-rows-exec*

- Where: `OCDesign/CodeBlockView.swift:26`, `OCDesign/CodeBlockView.swift:67`, `FeatureTranscript/ToolRowView.swift:60`, `FeatureTranscript/ToolRowView.swift:75`
- Evidence: `Packages/OpencodeKit/Sources has no ANSI handling: a grep for ansi, \u{1B} and x1b finds nothing. Output goes straight into Text(AttributedString) at CodeBlockView.swift:26, and Copy copies it unchanged.`; `The server runs commands with TERM=xterm-256color on top of the user's environment (opencode reference packages/core/src/shell.ts:259-272).`; `The desktop strips ANSI codes and converts carriage returns to newlines for both shell and execute output (tool-renderer.tsx:22, 1920, 1990-1993).`
- What happens: The agent runs a command with colour forced, for example `pytest --color=yes` or `git -c color.ui=always log`, or with FORCE_COLOR set in the user's profile. The expanded row shows fragments like '[32mPASSED[0m' and '[1m[31mFAILED[0m' between the words, and Copy includes them.
- Why it matters: Logs become noisy and harder to scan, a parity gap with the desktop.
- Fix: Strip CSI and OSC sequences (or map SGR colours to attributes) and normalize carriage returns before display and copy, in one helper used by shell, execute and composer-shell rows.

<a id="f06-06"></a>

## F06-06: In the default Compact preset, opening an Edit row reveals a second, collapsed diff card; tapping its file name navigates away

*P3 improvement · interaction · effort S · found by tool-rows-files*

- Where: `FeatureTranscript/ToolRowView.swift:54`, `OCDesign/DiffCardView.swift:28-29`, `OCDesign/DiffCardView.swift:55-61`, `OCDesign/DiffCardView.swift:68-70`
- Evidence: `ToolRowView.swift:54: DiffCardView(..., expanded: expanded), where expanded is the preset's detail.expanded (false for Compact, the default), not whether the user opened the row`; `DiffCardView.swift:28-29: with fileLinks set (always in the app), the header is not a toggle. Only the 44pt chevron OCIconButton expands it, and the file-name Button (line 58) calls openFile()`
- What happens: Compact preset. Expand 'Used 2 Read, Edit', then tap the Edit row. The content is a collapsed card showing 'main.swift +1 −1' and a chevron. Tapping the file name, the biggest and most obvious target, opens the Files viewer (a sheet on iPhone) instead of the diff. Only the small chevron shows the change. Seeing one edit takes three taps.
- Why it matters: Reviewing what the agent changed, a core task, takes extra taps, and the most likely tap takes the user out of the transcript.
- Fix: When the user expands an Edit or Patch row, expand its diff cards too: pass the chrome's live expanded state, or auto-expand when there is a single file. Make the card header toggle, and move 'Open file' to a trailing icon or context menu.

<a id="f06-10"></a>

## F06-10: Glob/Grep summary text is cryptic: '/' default, raw '.', no zero or truncated counts, files called 'matches'

*P3 improvement · copy · effort S · found by tool-rows-files*

- Where: `OCRender/ToolPresenter.swift:216-226`
- Evidence: `iphone/transcript-tools.png ('Grep . pattern=original · (1 match)')`; `.build/design-reference/timeline-light-1440x900.png (the reference shows 'Grep / pattern=original · (1 match)' for the same call, with the name, arguments and count styled separately)`; `Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/ReadSnapshots/capture-_-name-height.tool-glob-completed-light-393.png (at large text it wraps as 'Glob /' + 'pattern=*.swift')` (+1 more)
- What happens: Glob with no path shows 'Glob / pattern=*.txt', which reads like a search of the filesystem root although it ran in the session directory. Grep with path '.' shows '.', unlike the reference. An absolute path gives 'Grep /Users/\<name>/Sources pattern=TODO include=*.swift · (12 matches)'. A search with no results shows no count at all, metadata.truncated is ignored, and Glob counts files as 'matches'. VoiceOver reads the slash, the equals signs and the middle dot literally.
- Why it matters: The most frequent rows in agent transcripts are harder to scan than they need to be, and 'found nothing' looks the same as 'unknown'.
- Fix: Build a structured summary: the quoted pattern first; 'in \<relative dir>' only when a path other than '.' is given; then the include filter; then the count ('1 file' or 'N files' for glob, 'N matches' for grep, 'No matches' for 0, 'N+' when truncated). Render name, arguments and count with separate styles, as the reference does, and give VoiceOver a spoken form ('Grep for original, 1 match').
- Verifier's note: Keep the desktop's 'Glob / pattern=…' format and relativize as displayDirectory does. Add a spoken accessibility label such as 'Grep for original, 1 match'. Showing 'No matches' or 'N+' would go beyond parity; decide that deliberately.

<a id="f06-11"></a>

## F06-11: Explore rows render the tool name in the same muted style as the path, and file tools use two different header layouts

*P3 improvement · design-parity · effort S · found by tool-rows-files*

- Where: `OCDesign/TimelineChrome.swift:36-41`
- Evidence: `.build/design-compare/m2b-transcript-tools.png (web: 'Read' strong and 'sample.txt' muted; native: everything muted)`; `.build/design-reference/timeline-light-1440x900.png`; `scratch/sheets/tool-rows-files-1.png (Read/Glob/Grep rows are one muted line; Write is a medium-weight title over a second line)` (+1 more)
- What happens: Inside one group, 'Read sample.txt' is a single grey line with nothing marking the tool name, while 'Edit' and 'Write' rows use a dark, medium-weight title with the path on a second line. The reference renders every tool as one line, with a strong name and a muted detail.
- Why it matters: Rows are harder to scan, and file tools look inconsistent and drift from the desktop design the app deliberately reproduces.
- Fix: In the inline variant, compose Text(title).foregroundStyle(OCColor.text) + Text(" " + subtitle).foregroundStyle(OCColor.textMuted). Consider the same one-line layout for Edit, Write and Patch, with the badge trailing, as the reference does.

<a id="f06-12"></a>

## F06-12: Expanded Read/Glob/Grep content is raw: redundant JSON input, unwrapped plain text, and result paths that can't be opened

*P3 improvement · interaction · effort M · found by tool-rows-files*

- Where: `FeatureTranscript/ToolRowView.swift:79`, `FeatureTranscript/ToolRowView.swift:82-85`, `OCModels/ToolInputs.swift:42-44`
- Evidence: `Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/ReadSnapshots/capture-_-name-height.tool-read-completed-light-393.png (a json block repeating the path, then a clipped 'Text' block)`; `ToolRowView.swift:79/83: default: genericDetails → CodeBlockView(presentation.input, language: "json") and CodeBlockView(presentation.output)`; `Fixtures/v2/2.0.32/snapshots/permission-allow.json: read content is 'Read file sample.txt, lines 1-2\n1: original fixture line\n2: second line'` (+1 more)
- What happens: Expanding a Read shows {"path" : "sample.txt"} again, then the file text with 'N:' prefixes, unhighlighted, in a block that doesn't wrap and is cut off at the right edge on iPhone. A paged read doesn't show which lines it covered. Glob output (absolute paths) and Grep output ('\<abs path>:' plus 'Line n: text') are plain text, so the user can't jump from a hit to the file.
- Why it matters: On a phone, the natural next step after seeing a search result or a read is to open that file or line. Today that means retyping or hunting in the Files tab.
- Fix: Hide the JSON input when the summary already shows every field, or put it behind 'Show input'. Render glob results and grep file groups as tappable file rows that open the viewer at the hit line. Highlight read output by file extension and show 'lines X–Y' in the summary from offset and limit. Respect the existing 'Wrap lines' setting.

<a id="f07-10"></a>

## F07-10: Tool group labels reuse row titles, producing 'Used 2 Read, General' or the whole shell command as the header

*P3 improvement · copy · effort S · found by tool-rows-exec*

- Where: `OCRender/TimelineRowBuilder.swift:41-43`, `OCRender/TimelineRowBuilder.swift:74`, `OCRender/TimelineRowBuilder.swift:93`, `OCDesign/TimelineChrome.swift:39`
- Evidence: `Group names come from each row's text: the presentation title ('General' or 'Explore' from the agent name, 'Loaded skill', 'CodeMode', 'Tasks', 'Websearch'), or f.command for composer shells.`; `OCToolChrome's title Text has no lineLimit (TimelineChrome.swift:39), so a long or heredoc command becomes a multi-line bold header.`; `The desktop names each tool once with fixed nouns (Agent, Shell, Execute, Skill, Questions, Web Search) in tool-renderer.tsx:333-367 and 473-485, and shows 'Used 4 Read, Edit, Write, Shell' in .build/design-reference/m4-working-light-1440x900.png.` (+1 more)
- What happens: In Compact (the default), a turn that read a file and delegated to the general agent shows 'Used 2 Read, General'. Loading a skill gives 'Used 2 Read, Loaded skill'. Running `!cat <<'EOF' > notes.md …` from the composer turns the group title into the entire multi-line command in bold.
- Why it matters: In Compact mode the group header is the main summary of the agent's work, and these names make it read as nonsense.
- Fix: Add a short group noun per tool (Agent, Shell, Execute, Skill, Questions, Web search, Todo) and use it for group names, including composer shells. Limit group titles to one or two lines.

<a id="f07-11"></a>

## F07-11: Webfetch, skill and todo rows dump raw JSON input and unformatted output instead of a compact summary

*P3 improvement · visual · effort M · found by tool-rows-exec*

- Where: `OCRender/ToolPresenter.swift:152-182`, `OCRender/ToolPresenter.swift:206-213`, `FeatureTranscript/ToolRowView.swift:62-66`, `FeatureTranscript/ToolRowView.swift:79`
- Evidence: `The webfetch subtitle URL breaks after 'https://' and is not tappable. The body repeats the URL as '{"url": …}' JSON, then shows the fetched page in a 'Text' code block (Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/ReadSnapshots/capture-_-name-height.tool-webfetch-completed-light-393.png, capture-_-name-height.tool-webfetch-completed-light-820.png).`; `The skill row shows 'Loaded skill review', then '{"name": "review"}', then the skill body, which the server wraps in <skill_content name=…> tags (Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/ReadSnapshots/capture-_-name-height.tool-skill-completed-light-393.png; research/01-opencode-server-api.md:988).`; `TodoPresenter keeps the pretty-printed todos array as input and prints raw lines such as 'in_progress: …'. For todoread it replaces the real output with an empty string (Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/ReadSnapshots/capture-_-name-height.tool-todowrite-completed-light-393.png).` (+2 more)
- What happens: On an iPhone a webfetch row reads 'Webfetch / https:// / example.com/do…', and tapping the URL does nothing. Expanding it shows JSON with the same URL and up to 50 KiB of page text in a non-wrapping block. A migrated V1 session's 'Tasks' row shows the whole todos JSON array before 'pending: Write tests'.
- Why it matters: Tools that should be one-liners turn into code dumps, while the one useful action, opening the URL, is missing.
- Fix: Make the webfetch URL a Link with the external-link icon and drop its JSON body. Show skills as a single line. Render todos as a checklist with a '3 of 5 done' subtitle and no JSON. For websearch, parse '## [title](url)' and show each title with its domain.

<a id="f06-14"></a>

## F06-14: Running and streaming tools have no activity cue: a static grey badge, and nothing at all inside collapsed groups

*P3 improvement · state · effort S · found by tool-rows-files*

- Where: `OCDesign/TimelineChrome.swift:42-46`, `FeatureTranscript/TimelineRowView.swift:70`, `OCDesign/CodeBlockView.swift:60`
- Evidence: `Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/ReadSnapshots/capture-_-name-height.tool-grep-running-light-393.png`; `Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/ReadSnapshots/capture-_-name-height.tool-read-streaming-light-393.png`; `TimelineChrome.swift:44: OCBadge(badge ?? status.capitalized, tone: failed ? .danger : .neutral) (the same neutral style as 'MCP' or 'Added file'; no ProgressView)`
- What happens: A long Grep or Read is in flight. Its row shows a grey 'Running' tag that looks like any other metadata badge. While the model is still writing the arguments, the tag says 'Streaming', which is internal jargon. In the default Compact preset the row sits inside a collapsed 'Used N …' group, so there is no per-tool sign of progress; only the global 'Working…' row remains.
- Why it matters: Users can't tell at a glance which step the agent is on, or whether a tool is stuck.
- Fix: Show a small ProgressView, or the reference's text shimmer (static under Reduce Motion), for running and pending tools. Label input streaming as 'Preparing…'. Surface a running indicator on collapsed group headers.
- Also reported as: F35-13 by sweep-read-snapshots

<a id="f07-12"></a>

## F07-12: MCP and CodeMode rows: raw server_tool names, 'Completed · MCP' on every call, empty boxes for nested calls

*P3 improvement · consistency · effort M · found by tool-rows-exec*

- Where: `OCRender/ToolPresenter.swift:50-61`, `FeatureTranscript/ToolRowView.swift:67-75`, `FeatureTranscript/ToolRowView.swift:87-90`, `OCRender/ToolPresenter.swift:183-204`
- Evidence: `The generic row shows the title 'mcp_lookup' and a 'Completed · MCP' badge wrapped onto two lines (Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/ReadSnapshots/capture-_-name-height.tool-mcp_lookup-completed-light-393.png; crop at crops/tool-rows-exec/mcp-badge.png). Known tools show no badge when completed, but the generic style always prefixes the status (ToolRowView.swift:87-90).`; `Any name containing '_' gets the MCP badge (ToolPresenter.swift:60; Packages/OpencodeKit/Tests/OCRenderTests/ToolPresenterTests.swift:14 expects 'future_tool' to be badged MCP). Namespaced plugin tools are also named '<namespace>_<name>' (research/01-opencode-server-api.md:965).`; `Generic rows have no subtitle. The desktop shows 'Called 'tool'' with the first of description/query/url/path/pattern/name and up to three arguments (basic-tool.tsx:374-417).` (+1 more)
- What happens: A GitHub MCP call appears as 'github_search_issues' with a 'Completed · MCP' badge, and nothing in the collapsed row says what it searched for. A CodeMode run with three nested calls shows three empty 'Text' boxes, then the script's console output, which looks like the last call's result.
- Why it matters: MCP and CodeMode are how most third-party tools appear, and these rows are noisy yet uninformative.
- Fix: Split '\<server>_\<tool>' into a readable tool title with the server as the badge, but only when the prefix matches a connected MCP server. Drop the 'Completed' prefix. Add a subtitle from common input keys. Skip empty nested blocks, label the console output 'Output', and title the tool 'Execute'.
- Also reported as: F35-11 by sweep-read-snapshots
