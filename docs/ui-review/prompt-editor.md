# UI review: Prompt editor

Part of the [UI review](README.md). 10 bugs and 2 improvements, bugs first, then by severity. Paths under `Packages/OpencodeKit/Sources` are written without that prefix.

| ID | Severity | Finding |
| --- | --- | --- |
| [F10-03](#f10-03) | P1 bug | On iPhone the keyboard cannot be dismissed once the prompt is focused, leaving about 155 pt for the transcript |
| [F10-01](#f10-01) | P2 bug | Shell mode keeps autocapitalization, autocorrect and smart quotes/dashes, so commands are rewritten before they run on the user's computer |
| [F10-02](#f10-02) | P2 bug | Shell mode hides staged attachments, enables Send with an empty command, and any shell send permanently deletes them |
| [F10-04](#f10-04) | P2 bug | @ file results disappear on every keystroke, and 'No matching items' shows while the search is still running |
| [F10-06](#f10-06) | P2 bug | VoiceOver gets no semantics for mentions, the suggestion list or the switch into shell mode |
| [F10-07](#f10-07) | P3 bug | The + menu's Commands and Shell command items ignore existing text, and /new and ⌘N do nothing on New session |
| [F10-08](#f10-08) | P3 bug | The placeholder is drawn 4–12 pt above where the caret and typed text appear |
| [F10-09](#f10-09) | P3 bug | The suggestion list ignores focus, can't be dismissed by touch, and swallows Return when nothing matches |
| [F10-10](#f10-10) | P3 bug | The caret and selections can land inside a mention; Cut copies a fragment but deletes the whole token |
| [F10-11](#f10-11) | P3 bug | On New session the suggestion list pushes the editor down, so the text jumps whenever @ or / is typed |
| [F10-05](#f10-05) | P3 improvement | One Esc, or Return in an empty composer, interrupts the running agent; Esc is swallowed even when there is nothing to do |
| [F29-08](#f29-08) | P3 improvement | One action, several names: Undo vs Revert, Delete vs Remove vs Discard, and two different meanings each for Undo and Pending |

<a id="f10-03"></a>

## F10-03: On iPhone the keyboard cannot be dismissed once the prompt is focused, leaving about 155 pt for the transcript

*P1 bug · interaction · effort S · found by prompt-editor*

- Where: `FeatureComposer/PromptEditor.swift:32`, `FeatureTranscript/TimelineCollection.swift:42-47`, `FeatureTranscript/SessionScreen.swift:60-61`
- Evidence: `iphone/composer-queue.png: with the keyboard up, the transcript between the Compact row and the queue row is about 155 pt of the 874 pt screen.`; `iphone/composer-worktree.png: same situation after starting a session.`; `The timeline collection view never sets keyboardDismissMode (default .none) and the editor sets 'view.keyboardDismissMode = .none'. A grep finds no resignFirstResponder, endEditing, inputAccessoryView or keyboard toolbar anywhere in Sources.` (+1 more)
- What happens: iPhone 17 Pro: send a follow-up while the agent runs; by design the keyboard stays up. To read the streaming reply, the user scrolls the transcript (the keyboard stays), taps it (nothing happens) or presses Return (adds a newline). There is no Done key. Only leaving the session hides the keyboard.
- Why it matters: The core iPhone loop (prompt, watch tool output, answer approvals) happens in a sliver of the screen. The queue panel and approval dock shrink it further.
- Fix: Set keyboardDismissMode = .interactive on TimelineCollectionView, and also on the editor. Add a 'Hide keyboard' control on compact width, as an input accessory or a button beside Send. Consider resigning the editor after send on compact width, as the desktop's phone layout does.
- Verifier's note: Set keyboardDismissMode = .interactive on TimelineCollectionView and add .scrollDismissesKeyboard(.interactively) to the dock's SwiftUI ScrollView. On compact width also add an explicit hide-keyboard control. This keeps ARCHITECTURE's rule that the keyboard stays open after sending.
- Also reported as: F09-10 by composer-dock, F24-01 by touch-gestures-motion

<a id="f10-01"></a>

## F10-01: Shell mode keeps autocapitalization, autocorrect and smart quotes/dashes, so commands are rewritten before they run on the user's computer

*P2 bug · functional · effort S · found by prompt-editor*

- Where: `FeatureComposer/PromptEditor.swift:22-36`, `FeatureComposer/PromptEditor.swift:37-40`, `OCSync/ComposerModel.swift:75`, `OCSync/ComposerModel.swift:183-184`, `FeatureComposer/ComposerDock.swift:45`
- Evidence: `makeUIView sets no UITextInputTraits. A grep of Packages/OpencodeKit/Sources for smartQuotesType|smartDashesType|autocorrectionType|autocapitalizationType|spellCheckingType|inlinePredictionType|writingToolsBehavior finds nothing for the prompt editor; only the server URL, search and directory fields disable autocorrect.`; `updateUIView only swaps the font for shell mode: 'view.updateStyle(shell: shell)'`; `iphone/composer-queue.png: the focused empty editor shows Shift engaged (auto-capitalization) and the predictive bar (crop: crops/prompt-editor/shift-key.png). The same EditorView becomes the shell editor.` (+1 more)
- What happens: iPhone, touch keyboard, default iOS settings (Auto-Capitalization, Auto-Correction and Smart Punctuation on). Type ! to enter shell mode, then type the placeholder's own example `git status`, or `npm test -- --watch`, or `git commit -m "wip"`. The keyboard capitalizes the first word (Git, Npm). Smart Punctuation turns -- into an em dash and straight quotes into curly ones. Autocorrect can replace short tokens. The rewritten string is posted unchanged to the session shell endpoint and executed on the host. Ordinary prompts containing code, flags or JSON get the same smart-punctuation substitution.
- Why it matters: Commands fail: 'command not found' on case-sensitive hosts, an unknown flag —watch, or literal “wip” quotes. Worse, a command can run with silently changed arguments. Shell mode is close to unusable on a touch keyboard without manual correction of every command.
- Fix: Set input traits from the mode in EditorView (in makeUIView and updateUIView), and call reloadInputViews() when shell mode toggles. In shell mode set: autocapitalizationType = .none, autocorrectionType = .no, spellCheckingType = .no, smartQuotesType = .no, smartDashesType = .no, smartInsertDeleteType = .no, inlinePredictionType = .no and writingToolsBehavior = .none (optionally keyboardType = .asciiCapable). For ordinary prompts, at least disable smart quotes and smart dashes, since prompts routinely contain code and flags. Consider making touch Return run the command in shell mode (returnKeyType = .go).
- Verifier's note: Set the traits in makeUIView and update them in updateUIView when shell mode changes, then call reloadInputViews() on the first responder. In shell mode turn off autocapitalization, autocorrection, spell checking, smart quotes, smart dashes, smart insert/delete and inline predictions. In prompt mode at least turn off smart quotes and dashes.

<a id="f10-02"></a>

## F10-02: Shell mode hides staged attachments, enables Send with an empty command, and any shell send permanently deletes them

*P2 bug · state · effort S · found by prompt-editor*

- Where: `OCSync/ComposerModel.swift:52`, `OCSync/ComposerModel.swift:183-184`, `OCSync/ComposerModel.swift:209-214`, `FeatureComposer/ComposerDock.swift:132-147`, `FeatureComposer/ComposerDock.swift:173-185` (+1 more)
- Evidence: `ComposerDock.swift:132-138: 'if model.options.shell { …Shell command / Exit… } else if !model.attachments.isEmpty { …chips… }'. The chips and the capability warning disappear in shell mode.`; `ComposerModel.swift:52: 'blank' is true only if the trimmed text is empty && attachments.isEmpty && (options.shell || comments.isEmpty). Hidden attachments make an empty shell command non-blank, so Send is enabled. During a run the button shows Send (arrow-up) instead of Stop.`; `ComposerModel.swift:209-211: after a successful shell send, 'store.drafts?.delete(draft)' runs (DraftFiles.swift:48-50 removes the attachment directory) and then 'self.attachments = []'. Lines 212-214 deliberately re-save comments for shell sends, but not attachments.` (+1 more)
- What happens: Take a photo with + > Camera (or paste a screenshot) to ask about it, then type ! to run `git status` first. The attachment chip vanishes behind the Shell command header. Send is already enabled before any command is typed; tapping it posts an empty shell command. After `git status` runs, the composer returns to prompt mode and the photo is gone: the draft's attachment files were deleted.
- Why it matters: Staged attachments are lost silently and permanently. Camera captures and pasted images have no other copy (data loss; rated P1 rather than P0 only because it needs the attach-then-shell sequence). The empty-command send and the missing Stop button follow from the same defect.
- Fix: In shell mode, compute blank from the command text only. On a shell send, keep attachments: carry them into the fresh draft, as is already done for comments, instead of deleting the old draft's files. Show a short 'N attachments kept for your next prompt' note in the shell header. Alternatively, refuse to enter shell mode while attachments are staged and say why.
- Verifier's note: From F09-03: also disable Photos, Camera, Files and Paste in the + menu while in shell mode (the reference hides + there), and reword the placeholder to 'Enter a shell command, e.g. git status'.
- Also reported as: F09-03 by composer-dock

<a id="f10-04"></a>

## F10-04: @ file results disappear on every keystroke, and 'No matching items' shows while the search is still running

*P2 bug · state · effort S · found by prompt-editor*

- Where: `FeatureComposer/ComposerDock.swift:309-327`, `FeatureComposer/ComposerDock.swift:231`, `FeatureComposer/ComposerDock.swift:244-245`
- Evidence: `ComposerDock.swift:316 replaces the list with local-only items ('files: []') before 'Task.sleep(for: .milliseconds(120))' at line 318 and the fs/find round trip at line 319.`; `ComposerDock.swift:231 shows 'Text("No matching items")' whenever 'suggestions' is empty, including while the request is in flight. There is no loading state.`; `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-context-light-393-default.png: the file row (Sources/main.swift) sits below the local rows; this is the row that drops out on each keystroke.`
- What happens: Server reached through a tunnel with a 200-400 ms round trip. Type @src/ma one character at a time. After each character the file rows vanish and the list shrinks to 'No matching items', because no agent, skill or reference matches a path. That lasts 120 ms plus the round trip, then the files come back. The list, and the transcript above it, jump on every keystroke. A hardware Return in that window is swallowed.
- Why it matters: The flicker and the false empty state make users think the file isn't in the project, so they retype or give up. The moving list is also hard to tap.
- Fix: Keep the previous file rows, filtered on the client with ComposerSuggestions.matches, until the new response arrives. Show a 'Searching…' row while a request is pending, and show 'No matching items' only after it completes. Keep the list height stable between updates, or animate the change.

<a id="f10-06"></a>

## F10-06: VoiceOver gets no semantics for mentions, the suggestion list or the switch into shell mode

*P2 bug · accessibility · effort M · found by prompt-editor*

- Where: `FeatureComposer/PromptEditor.swift:30`, `FeatureComposer/PromptEditor.swift:67-77`, `FeatureComposer/PromptEditor.swift:187-206`, `FeatureComposer/ComposerDock.swift:148-152`, `FeatureComposer/ComposerDock.swift:227-249` (+1 more)
- Evidence: `PromptEditor.swift:74 gives mention ranges only 'tokenKey' and a foreground colour; there is no accessibility attribute.`; `PromptEditor.swift:30: 'view.accessibilityLabel = "Prompt"' in both prompt and shell mode.`; `ComposerDock.swift:150-151: the placeholder Text is not accessibilityHidden, so VoiceOver treats it as a separate element over the field.` (+2 more)
- What happens: VoiceOver on an iPhone. The field reads 'Prompt, Review at main dot swift and preserve…'; nothing says @main.swift is a resolved file reference rather than literal text. Colour is the only cue, which also fails colour-blind users. Typing @ shows a list that is never announced. With a hardware keyboard, ↑ and ↓ move a highlight that is never spoken, and Return inserts whichever row is highlighted. Typing ! clears the field and switches to shell mode with no announcement, and the label stays 'Prompt'. Backspacing into a mention removes the whole token in one step, likely without the usual echo of the deleted text.
- Why it matters: Blind users can't tell which references will be attached. They can't use suggestions efficiently. They can end up in shell mode without knowing it, so a prompt gets executed as a shell command. The roadmap's general M9 VoiceOver pass does not cover these specifics.
- Fix: Give mention ranges an accessibility attribute such as NSAttributedString.Key.accessibilityTextCustom (for example ['file reference']), plus a cue that isn't colour (an underline or tinted background). Post UIAccessibility announcements when the list opens ('4 suggestions'), when the highlight changes, when a mention is removed ('Removed main.swift') and when the mode switches. Mark the active row .isSelected. Set the label to 'Shell command' in shell mode. Hide the placeholder Text from VoiceOver and expose its text as the editor's accessibilityHint.

<a id="f10-07"></a>

## F10-07: The + menu's Commands and Shell command items ignore existing text, and /new and ⌘N do nothing on New session

*P3 bug · functional · effort S · found by prompt-editor*

- Where: `FeatureComposer/ComposerDock.swift:180-182`, `FeatureComposer/ComposerDock.swift:355-360`, `OCModels/ComposerSuggestions.swift:25`, `OCModels/ComposerSuggestions.swift:56-61`, `FeatureComposer/ComposerDock.swift:336` (+2 more)
- Evidence: `'insert("/")' appends ' /' to non-empty text (ComposerDock.swift:358-359). The command trigger only matches when the whole prompt is '^/(\S*)$' (ComposerSuggestions.swift:25).`; `'insert' never calls model.requestFocus(), so the caret isn't placed after the inserted @ or /.`; `Shell command calls 'model.shellMode(true)' and leaves the text as it is (ComposerDock.swift:182).` (+1 more)
- What happens: Type 'Fix the flaky login test', then tap + > Commands. The prompt becomes 'Fix the flaky login test /' and no command list appears. + > Context does open the list, but the editor isn't focused. Tapping into the text to type a query moves the caret off the @ unless the tap lands exactly at the end, and that closes the list. + > Shell command keeps the prose, so Send runs 'Fix the flaky login test' in the user's shell. On New session, choosing /new clears the text and nothing else happens.
- Why it matters: These entry points into commands and shell mode are dead or surprising, and the Shell command one can execute prose on the host.
- Fix: Enable Commands and Shell command only when the prompt is empty, or replace the text after confirming. Call model.requestFocus() after insert so the caret lands after the trigger. Hide `.new` when there is no session, or give NewSessionView a real newSession closure.

<a id="f10-08"></a>

## F10-08: The placeholder is drawn 4–12 pt above where the caret and typed text appear

*P3 bug · visual · effort S · found by prompt-editor*

- Where: `FeatureComposer/ComposerDock.swift:148-152`, `OCDesign/ComposerChrome.swift:59-68`, `FeatureComposer/PromptEditor.swift:28`, `OCDesign/Typography.swift:25`
- Evidence: `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-idle-light-393-default.png vs capture-_-name-fixedHeight.dock-typing-light-393-default.png (both surfaces start at y = 48 px): the placeholder line spans y = 104–142 px and the first typed line y = 117–155 px, 13 px (4.3 pt) lower.`; `capture-_-name-fixedHeight.dock-idle-light-393-accessibility5.png vs capture-_-name-fixedHeight.dock-typing-light-393-accessibility5.png: the tops of the capital letters are at 123 px vs 158 px, an 11.7 pt offset.`; `iphone/composer-queue.png and composer-worktree.png: the 20 pt caret overlaps the 'A' of the placeholder and extends below its baseline (crop: crops/prompt-editor/queue-caret.png).` (+1 more)
- What happens: Focus an empty composer at any text size. The caret is drawn over the first letter of 'Ask anything…' and lower than it. The first typed character appears 4.3 pt (default size) to 11.7 pt (accessibility5) below where the placeholder was, so the line visibly jumps.
- Why it matters: The composer's most-viewed state looks misaligned, and the jump grows with Dynamic Type.
- Fix: Draw the placeholder inside EditorView, as a UILabel or drawn text using the same UIFont, paragraph style, textContainerInset and lineFragmentPadding. Alternatively, give the SwiftUI Text the editor's UIFont and minimum line height, and offset it by the line-height difference.
- Verifier's note: There is also a 1.7-pt horizontal offset: the placeholder starts at 16 pt, the text at 17 pt (12-pt inset plus 5-pt lineFragmentPadding). Drawing the placeholder inside EditorView with the editor's UIFont, paragraph style and insets fixes both offsets and the .footnote/.body scaling mismatch.
- Also reported as: F37-09 by sweep-composer-snapshots

<a id="f10-09"></a>

## F10-09: The suggestion list ignores focus, can't be dismissed by touch, and swallows Return when nothing matches

*P3 bug · interaction · effort S · found by prompt-editor*

- Where: `FeatureComposer/ComposerDock.swift:57`, `FeatureComposer/ComposerDock.swift:70`, `FeatureComposer/ComposerDock.swift:362-369`
- Evidence: `ComposerDock.swift:57 shows the list whenever the text and caret form a trigger; focus is never considered.`; `ComposerDock.swift:70: 'caret = String(model.text.characters).utf16.count' after the draft loads, so a draft ending in '@lat' or '/rev' opens the list on arrival, without focus.`; `ComposerDock.swift:367: 'case .send, .tab: if suggestions.indices.contains(active) { select(...) }; return true' consumes Return even when the list is empty.` (+1 more)
- What happens: (a) Type '@lat', leave the session and come back. The list immediately covers part of the transcript, and on iPhone the only way to close it is to edit the text; Esc exists only on hardware keyboards. (b) iPad with a hardware keyboard: type 'Bump @types/node' and press Return while the list shows 'No matching items' or is still loading. Nothing happens. (c) Touch keyboard: the first row is highlighted as if Return would pick it, but Return inserts a newline and leaves '@lat' as plain text.
- Why it matters: The list can stay stuck over the transcript and sends get swallowed. The highlight also promises an action the touch keyboard doesn't perform.
- Fix: Show the list only while the editor is first responder, tracked with textViewDidBeginEditing and textViewDidEndEditing in the coordinator. Add a close control or dismiss on tapping outside. Let Return fall through to send when there are no rows. On touch keyboards, either accept the highlighted row when Return is pressed with suggestions open (intercept "\n" in shouldChangeTextIn) or don't pre-highlight a row.

<a id="f10-10"></a>

## F10-10: The caret and selections can land inside a mention; Cut copies a fragment but deletes the whole token

*P3 bug · interaction · effort S · found by prompt-editor*

- Where: `FeatureComposer/PromptEditor.swift:91-105`, `FeatureComposer/PromptEditor.swift:114-118`, `FeatureComposer/PromptEditor.swift:187-206`
- Evidence: `PromptEditor.swift:95-97 moves text typed inside a token to the token's end ('expanded = NSRange(location: NSMaxRange(tokenRange), length: 0)') instead of keeping the caret out of tokens.`; `textViewDidChangeSelection (lines 114-118) never snaps a caret or a partial selection to token boundaries.`; `deleteBackward (lines 189-196) and shouldChangeTextIn (line 94) expand a partial selection to the whole token, but copy and cut put only the selected fragment on the pasteboard.`
- What happens: With a hardware keyboard, press ← three times after '@main.swift' and type x. The x appears after the token, not where the caret is drawn. Select 'Review @ma' (half of the mention) and choose Cut. The pasteboard gets 'Review @ma' but 'Review @main.swift' is deleted, so pasting it back loses 'in.swift' and the mention. With a Japanese or Chinese IME, starting a composition while the caret is inside a token likely commits the first raw keystroke after the token, because shouldChangeTextIn runs before markedTextRange exists.
- Why it matters: The caret behaves surprisingly, and editing around mentions silently loses small amounts of text.
- Fix: In textViewDidChangeSelection, move a collapsed caret inside a token to the nearer edge, and extend partial selections to whole tokens. Arrow keys then step over tokens, and copy and cut match what gets deleted. Add regression tests next to EditorBehaviorTests.
- Verifier's note: Test the IME case with a Japanese keyboard before acting on it. The snapping fix in textViewDidChangeSelection resolves the caret and Cut cases.

<a id="f10-11"></a>

## F10-11: On New session the suggestion list pushes the editor down, so the text jumps whenever @ or / is typed

*P3 bug · layout · effort S · found by prompt-editor*

- Where: `FeatureComposer/NewSessionView.swift:35-41`, `FeatureComposer/ComposerDock.swift:50-58`, `FeatureComposer/ComposerDock.swift:244-245`
- Evidence: `ComposerDock lays the list out above OCComposerSurface in the same VStack (ComposerDock.swift:57-58).`; `NewSessionView puts the dock in a top-anchored ScrollView VStack (NewSessionView.swift:35-39). In SessionScreen, by contrast, the composer is docked at the bottom, so the list grows upward.`; `The list height follows its content on every keystroke ('.frame(height: min(220, suggestionHeight))', ComposerDock.swift:245).`
- What happens: iPhone, New session, keyboard up: type @. The composer and caret drop by the height of the list (up to 224 pt), then move again as rows filter or file results arrive. With the keyboard up, the editor can end up pressed against the keyboard's top edge.
- Why it matters: On the first screen of new work, the text being typed jumps around.
- Fix: Render the list as an overlay anchored to the top edge of the surface (for example with an alignment guide on the overlay), so it never affects layout. Alternatively, place it below the composer on New session.

<a id="f10-05"></a>

## F10-05: One Esc, or Return in an empty composer, interrupts the running agent; Esc is swallowed even when there is nothing to do

*P3 improvement · interaction · effort S · found by prompt-editor*

- Where: `FeatureComposer/ComposerDock.swift:361-376`, `OCModels/ComposerSuggestions.swift:113-114`, `FeatureComposer/PromptEditor.swift:211-225`, `FeatureServers/ServerRootView.swift:91`
- Evidence: `ComposerDock.swift:364: the first Esc closes the list. Line 375: 'if model.options.shell { … } else if running { stop() }', so the next Esc stops the run even when the composer contains text.`; `ComposerSuggestions.swift:114: 'if blank { return running ? .stop : .empty }'. A hardware Return in an empty composer stops the run.`; `research/02-opencode-features.md:729: the TUI interrupts only on Esc pressed twice within 5 s.` (+1 more)
- What happens: iPad with a Magic Keyboard while a run is active. Pressing Esc twice to get rid of an @ list interrupts the run on the second press. Pressing Esc while typing a follow-up interrupts. Pressing Return twice after sending a follow-up makes the second Return hit the now-empty composer, which calls interrupt with resume and turns the steer into an interrupt. In the compact New session sheet, Esc does nothing instead of cancelling.
- Why it matters: Accidental interrupts throw away the agent's in-progress step, and Esc is a reflexive 'dismiss' key on iPad.
- Fix: Require a second Esc within about 3 s to stop, with a transient 'Press Esc again to stop' hint, as in the TUI. Don't map Return on an empty composer to Stop (keep Stop on the button and ⌘.), or ignore it for about 1 s after a send. Omit the Esc key command, or return false from canPerformAction for it, when there is nothing to close, exit or stop, so the system Cancel shortcut works. This revisits docs/design.md:74-77.

<a id="f29-08"></a>

## F29-08: One action, several names: Undo vs Revert, Delete vs Remove vs Discard, and two different meanings each for Undo and Pending

*P3 improvement · consistency · effort M · found by ux-writing*

- Where: `FeatureComposer/SelectionOptions.swift:40`, `FeatureComposer/SelectionOptions.swift:42`, `FeatureTranscript/TimelineRowView.swift:54`, `FeatureTranscript/TimelineRowView.swift:56`, `FeatureTranscript/TimelineRowView.swift:65` (+9 more)
- Evidence: `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.session-menu-light-393-default.png: “Undo last message”, “Redo last message”, “Fork from message”`; `iphone/composer-revert-confirmation.png: “4 messages reverted” and “Discard reverted messages?”`; `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.pending-steering-light-393-default.png: “Pending · Move to queue · Delete”` (+1 more)
- What happens: Revert and undo:
  - The … menu says “Undo last message”; long-pressing a prompt says “Revert message”; /undo says “Undo the last message”.
  - The result is “4 messages reverted” and “Discard reverted messages?”, and a stale send fails with “The staged revert changed”.
  - The queue row's undo icon means “put this prompt back in the composer”, which is a different operation, as in “Leave shell mode before undoing a queued prompt”.

  Removing pending input:
  - The same removal is called “Delete” on a pending steer, “Remove” on a queued prompt and “Discard” on a saved prompt.

  Other drift:
  - “Pending” marks both an unapplied model or agent choice in the header and an undelivered steer.
  - The session screen says “Loading conversation…” where everything else says session.
  - The menu says “Fork from message” while the context menu says “Fork from here”.
- Why it matters: Users have to learn that controls with different names do the same thing, and that controls with the same name don't. None of the Undo labels mention that file changes are rolled back as well.
- Fix: Adopt a short glossary and apply it everywhere:
  - “Revert” for rolling back messages: “Revert last message”, “Revert to here”, and “/undo: Revert the last message and its file changes”. Drop “staged”.
  - “Remove” for pending input.
  - Queue row icon: label it “Move back to composer”.
  - Header badge: “Applies on next send”.
  - Always “session”, never “conversation”.

  Record the glossary in docs/design.md so M9a's String Catalogs inherit it.
