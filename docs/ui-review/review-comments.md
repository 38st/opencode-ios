# UI review: Review comments

Part of the [UI review](README.md). 8 bugs and 3 improvements, bugs first, then by severity. Paths under `Packages/OpencodeKit/Sources` are written without that prefix.

| ID | Severity | Finding |
| --- | --- | --- |
| [F17-01](#f17-01) | P2 bug | A half-written comment is silently lost on rotation, swipe-down, re-selection or a busy composer |
| [F17-03](#f17-03) | P2 bug | Comments on a subagent's diffs or permission preview go to its read-only composer and are never sent |
| [F17-05](#f17-05) | P2 bug | Tapping a review comment chip opens the file but not the commented lines |
| [F17-06](#f17-06) | P2 bug | Prompts with line comments lose right alignment: text bubble, badges and Show more sit on the left |
| [F17-07](#f17-07) | P2 bug | Composer comment chips are fixed-width, unpadded and announce 'Remove attachment' |
| [F17-08](#f17-08) | P2 bug | With a hardware keyboard, ← and → in the inline review comment switch files instead of moving the caret |
| [F17-11](#f17-11) | P3 bug | Comment ranges hide which side they are on and mix old and new line numbers |
| [F17-13](#f17-13) | P3 bug | Finishing a range selection jumps the diff, and a cancelled selection stays highlighted |
| [F17-09](#f17-09) | P2 improvement | Commenting hides behind an unhinted long press with no haptic or range feedback, and it blocks copying code |
| [F17-14](#f17-14) | P3 improvement | Sent comment cards can't be tapped, read as three VoiceOver stops, and order their fields differently from the chip |
| [F17-10](#f17-10) | P3 improvement | On iPhone the comment sheet hides the code under discussion and floats a desktop card in a full-height sheet |

<a id="f17-01"></a>

## F17-01: A half-written comment is silently lost on rotation, swipe-down, re-selection or a busy composer

*P2 bug · state · effort M · found by review-comments*

- Where: `FeatureReview/ReviewScreen.swift:66`, `FeatureReview/ReviewScreen.swift:213`, `FeatureReview/ReviewScreen.swift:222`, `FeatureFiles/FilesScreen.swift:63`, `OCDesign/LineCommentEditor.swift:11` (+3 more)
- Evidence: `ReviewScreen.swift:66 '.sheet(item: Binding(get: { regular ? nil : comment }, set: { comment = $0 }))': the sheet exists only below the 480 pt breakpoint. The inline editor (ReviewScreen.swift:220-222) is a separate view created with 'initialText: ""'.`; `LineCommentEditor.swift:11 '@State private var text': the typed text lives only in whichever editor instance is on screen.`; `ReviewScreen.swift:222 '.id(value.id)', and OCDiffSelection gets a fresh UUID on every long press (DiffView.swift:25), so each new selection rebuilds an empty editor. inlinePlacement (ReviewScreen.swift:213-216) prefers 'comment' over 'editing'.` (+3 more)
- What happens: (1) iPhone in portrait, Review sheet: long-press some lines and type a paragraph in the comment sheet, then rotate to landscape. The panel becomes 480 pt or wider, so `regular` flips, the sheet's getter returns nil and the sheet dismisses, and an empty inline editor appears. Rotating back gives an empty sheet. (2) Swiping the sheet down (the drag indicator invites it), or tapping outside a diff-card comment sheet on iPad, closes it without a 'Discard comment?' prompt. (3) iPad inline editor with text: long-pressing again to adjust the range replaces it with an empty editor. Choosing Edit on another annotation while a new comment is open appears to do nothing, and that edit editor pops up later. (4) Tapping Comment or Save while the composer is busy (for example while an attachment is processed) does nothing, yet the editor closes as if it had succeeded.
- Why it matters: The comment text is the whole point of the feature. A typed paragraph disappears without confirmation or a saved draft, and in case 4 with no sign that anything failed.
- Fix: Keep the draft text outside the editor (a draft string on the screen's comment state, or in ComposerModel keyed by file and range) and pass it to whichever presentation is active. When the range changes, re-anchor the open editor and keep its text. Add `.interactiveDismissDisabled(!text.isEmpty)` plus a discard confirmation. Clear or confirm `comment` when Edit is chosen. Make addComment and updateComment report success, and keep the editor open with an error (or disable Comment while composer.busy).
- Verifier's note: The VoiceOver 'Extend selection to this line' action on iPad hits the same root cause: it calls onComment with a new OCDiffSelection, which recreates the inline editor and wipes the typed text. Keep the draft outside the editor, keyed by file, so changing the range keeps the text.
- Also reported as: F40-12 by navigation-state-restoration, G12-M1 by verifier G12

<a id="f17-03"></a>

## F17-03: Comments on a subagent's diffs or permission preview go to its read-only composer and are never sent

*P2 bug · functional · effort M · found by review-comments*

- Where: `FeatureTranscript/SessionScreen.swift:107`, `FeatureApprovals/PermissionSheet.swift:98`, `FeatureApprovals/PermissionSheet.swift:110`, `FeatureApprovals/ApprovalDock.swift:19`, `FeatureComposer/ComposerDock.swift:51` (+1 more)
- Evidence: `SessionScreen.swift:107-110: the transcript's comment handler adds to 'composer(sessionID: sessionID, …)' for every session, subagents included.`; `PermissionSheet.swift:98 'let composer = store.composer(sessionID: request.sessionID, directory: directory)'. The parent's ApprovalDock (ApprovalDock.swift:12-19) also lists child requests, with child: true and a 'Subagent' badge.`; `ComposerDock.swift:51-55: a subagent composer renders only 'Subagent sessions are read only…' and never shows comment chips. addComment (ComposerModel.swift:91) has no parent check, and submit refuses child sessions.`
- What happens: A subagent asks to edit a file, and the parent session's dock shows the request with a 'Subagent' badge. Tap Review, long-press a line in the edit preview, write 'keep the old name' and tap Comment. The sheet closes and an annotation appears in the preview, but the parent's composer gets no chip; the comment stays in the subagent's draft permanently. The same happens with diff cards inside an opened subagent transcript.
- Why it matters: The user believes the feedback was queued for the agent, but it silently goes nowhere.
- Fix: Route comments from subagent transcripts and subagent permission previews to the root session's composer (walk parentID). Alternatively, pass onComment = nil there and tell the user that comments go to the parent session.
- Also reported as: G07-M2 by verifier G07

<a id="f17-05"></a>

## F17-05: Tapping a review comment chip opens the file but not the commented lines

*P2 bug · navigation · effort S · found by review-comments*

- Where: `OCSync/ComposerModel.swift:107`, `OCSync/ReviewModel.swift:73`, `OCDesign/CodeCollection.swift:98`
- Evidence: `ComposerModel.swift:107-108 'review.selection = comment.selection' followed by 'review.choose(review.source, file: path, present: true)'.`; `ReviewModel.swift:73: choose runs 'selection = nil; scrollOffsets["accordion"] = 0' whenever a file is passed, wiping the selection set on the line before.`; `CodeCollection.swift:98-103 scrolls to a line only when 'selected' is non-nil.` (+1 more)
- What happens: iPhone, with a 600-line diff of Sources/Big.swift. Comment on lines 420-424, close Review, then tap the 'Big.swift:420-424' chip. The Review sheet opens scrolled to the Big.swift header with nothing highlighted; on iPad the file opens at its previous scroll position. Comments made in the Files viewer do work, because FilesModel.selection is set after openLink. A chip for a comment made on a transcript diff card whose file isn't in the current review source opens the first changed file instead.
- Why it matters: The chip has one job, taking the user back to the comment, and it fails for review comments, which are the common case.
- Fix: Apply the selection after choose returns (or give choose a selection parameter that it applies after its reset). Fall back to the Files viewer when the path isn't in the current source. Optionally use focusedComment to flash the card.

<a id="f17-06"></a>

## F17-06: Prompts with line comments lose right alignment: text bubble, badges and Show more sit on the left

*P2 bug · layout · effort S · found by review-comments*

- Where: `FeatureComposer/SessionActions.swift:133`, `FeatureComposer/SessionActions.swift:128`, `FeatureTranscript/TimelineRowView.swift:42`, `FeatureTranscript/TimelineRowView.swift:59`
- Evidence: `SessionActions.swift:133 'HStack { Spacer(minLength: 0); OCCommentCard(comment) }' stretches horizontally, so the leading-aligned VStack fills the row and the text bubble (SessionActions.swift:128-130) is drawn at its leading edge. TimelineRowView.swift:59-60 also drops the outer padding and background when the prompt has comments.`; `ipad/ipad-review-comment.png (crop: crops/review-comments/ipad-transcript-crop.png): the '@Example.swift' user bubble starts 24 pt from the left, just under the assistant's 'Hello, fixture world!', while its card is right-aligned. Prompts without comments are right-aligned ('Review a small edit' in iphone/review-comment.png).`; `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.comment-sent-light-393-default.png; capture-_-name.comment-show-more-light-393-default.png has 'Show more' at the far left.` (+1 more)
- What happens: Send 'Review these' with one or more line comments. In the transcript, the user's text bubble sits at the left as if it were part of the assistant's reply, and the cards hug the right edge. The Sending/Pending badges, the 'Move to queue' and 'Delete' buttons, and 'Show more' also sit at the left.
- Why it matters: It breaks the transcript's who-said-what layout, precisely for the review feedback prompts users most want to find again.
- Fix: Lay out commented prompts with trailing alignment: VStack(alignment: .trailing), with the bubble, badges and Show more framed `.frame(maxWidth: .infinity, alignment: .trailing)`. Alternatively, follow the desktop and put the cards inside the blue bubble, below the text.
- Also reported as: F31-11 by visual-polish-ipad, F36-02 by sweep-review-snapshots

<a id="f17-07"></a>

## F17-07: Composer comment chips are fixed-width, unpadded and announce 'Remove attachment'

*P2 bug · accessibility · effort S · found by review-comments*

- Where: `FeatureComposer/ComposerDock.swift:124`, `FeatureComposer/ComposerDock.swift:126`, `FeatureComposer/ComposerDock.swift:127`, `OCDesign/ComposerChrome.swift:90`
- Evidence: `ComposerDock.swift:124 '.frame(width: 116, alignment: .leading)'; 127 '.frame(width: 160).padding(.vertical, OCSpacing.xs)', with no horizontal padding; 126 'OCIconButton("Remove attachment", icon: "close")'.`; `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.comment-composer-light-393-accessibility5.png and capture-_-name.comment-composer-dark-820-accessibility5.png: the chip reads 'Keep…' / 'Exa…' next to a 16 pt close glyph.`; `iphone/review-comment.png (zoom: crops/review-comments/iphone-chip-zoom.png): 'Simplify this revi…' starts flush against the chip's rounded left edge.` (+1 more)
- What happens: (1) At accessibility text sizes each pending comment shows only 'Keep…' and 'Exa…', so comments and files can't be told apart. (2) With VoiceOver and three comments, there are three identical 'Remove attachment' buttons with no hint, and the chip doesn't say that tapping it opens the comment in review. (3) At the default size the text touches the chip's edge.
- Why it matters: Low-vision and VoiceOver users can't identify their pending comments or safely remove the right one.
- Fix: Replace the fixed widths with a maximum width that grows with Dynamic Type (a two-line limit, or a stacked layout at accessibility sizes). Add horizontal padding like OCAttachmentChip. Label the button 'Remove comment' with the comment text as its hint, add a hint to the chip ('Shows the comment in review'), and scale the close icon with @ScaledMetric.
- Verifier's note: Copy OCAttachmentChip's padding and `.accessibilityHint(name)` pattern, label the button 'Remove comment', and consider the same remove icon as attachments (outline-xmark instead of close).
- Also reported as: F09-14 by composer-dock, F22-08 by a11y-dynamic-type, F30-13 by visual-polish-iphone, F36-11 by sweep-review-snapshots

<a id="f17-08"></a>

## F17-08: With a hardware keyboard, ← and → in the inline review comment switch files instead of moving the caret

*P2 bug · ipad · effort S · plausible, needs a running app to confirm · found by review-comments*

- Where: `OCDesign/CodeCollection.swift:327`, `OCDesign/CodeCollection.swift:311`, `OCDesign/CodeEditorCell.swift:30`, `FeatureReview/ReviewScreen.swift:203`, `OCDesign/CommentTextView.swift:50`
- Evidence: `CodeCollection.swift:327-335 registers ← and → with 'wantsPriorityOverSystemBehavior = true' whenever 'move != nil'; ReviewScreen.swift:203 passes onMove. CodeCollectionController (line 311) exposes the same commands.`; `CodeEditorCell.swift:25-33 hosts the editor in a child controller of CodeCollectionController, inside a collection cell. The collection view and its controller are therefore next responders of the comment text view.`; `CommentTextView.swift:50-57: the editor's text view claims only Return and Escape.` (+1 more)
- What happens: iPad with a hardware keyboard, Review at regular width. Long-press some lines, type 'rename tmp to', then press ← to fix a typo. Review jumps to the previous file (wrapping from the first file to the last), and the editor and keyboard disappear until the user navigates back to the original file.
- Why it matters: Hardware-keyboard users can't move the caret inside their comment, and from their side it looks as if the comment vanished.
- Fix: Don't offer the ← and → commands while a text input inside the collection is first responder (check in CodeCollectionView.keyCommands and canPerformAction). Alternatively, have CommentEditorView claim ← and → itself and perform normal caret movement.

<a id="f17-11"></a>

## F17-11: Comment ranges hide which side they are on and mix old and new line numbers

*P3 bug · copy · effort S · found by review-comments*

- Where: `OCModels/LineComment.swift:18`, `FeatureComposer/ComposerDock.swift:122`, `OCDesign/DiffView.swift:159`, `OCDesign/CodeCell.swift:132`, `OCDesign/DiffCardView.swift:76`
- Evidence: `LineComment.swift:18 'lower == upper ? "line \(lower)" : "lines \(lower)-\(upper)"' uses the raw start and end. In a mixed selection, start is an old-file number and end is a new-file number. ComposerDock.swift:122 formats the chip the same way, while the note and metadata use newRange (DiffView.swift:159-165) and the sent card is rebuilt from that range.`; `Deleted-side ranges carry no marker. Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.comment-split-sides-light-393-default.png (unified) labels both 'Preserve this old behavior.' (old lines) and 'Keep the public name…' (new lines) as 'lines 2-3'.`; `DiffCardView.swift:76 draws every pending comment for a path into every tool diff of that path by line number, including diffs of older versions.`
- What happens: Five lines were inserted above a modification. In unified view, drag from deleted old line 20 to added new line 25. The editor footer, the annotation and the chip all say 'lines 20-25', but the agent is told 'line 25', and after sending the card says 'line 25'. Separately, a pending comment on line 2 also appears under line 2 of an older edit tool card in the transcript, where line 2 holds different code.
- Why it matters: Before sending, users can't trust which lines a comment actually covers.
- Fix: Build labels from the range that is actually sent: newRange, or 'deleted lines a–b' for old-side ranges. Use one shared formatter for the editor, annotation, chip and card. Draw pending comments only in the current review and file views.

<a id="f17-13"></a>

## F17-13: Finishing a range selection jumps the diff, and a cancelled selection stays highlighted

*P3 bug · interaction · effort S · found by review-comments*

- Where: `OCDesign/CodeCollection.swift:101`, `FeatureReview/ReviewScreen.swift:202`, `FeatureReview/ReviewScreen.swift:69`, `FeatureFiles/FilesScreen.swift:212`, `OCDesign/CodeCell.swift:134`
- Evidence: `ReviewScreen.swift:202 and FilesScreen.swift:212 store the gesture's range in model.selection, the same value used for 'open at line' and for Find.`; `CodeCollection.swift:98-103: any new selection runs 'view.scrollToItem(at: IndexPath(item: max(0, row - 4), …), at: .top, animated: false)'.`; `Cancel (ReviewScreen.swift:69, FilesScreen.swift:66) clears only 'comment'. model.selection keeps painting the same accent tint that CodeCell.swift:134-137 uses for commented lines.`
- What happens: iPad, a long file. Long-press near the bottom of the screen and drag across three lines. On release the diff jumps, without animation, so the selection sits four rows below the top, and then the inline editor is revealed. Tap Cancel: the three lines stay tinted like a commented range until another file is selected.
- Why it matters: The view jumps at the moment of release, and the leftover highlight suggests a comment exists where none does.
- Fix: Don't scroll for selections made by the gesture (or scroll, animated, only when the row is off-screen). Clear model.selection on Cancel and after Comment.
- Verifier's note: Clearing model.selection on Cancel would break the VoiceOver flow 'Comment on line → Cancel → Extend selection to this line', which uses parent.selected as its anchor (CodeCollection.swift:187-192). Keep a separate anchor for Extend that is scoped to the file, or clear only the visible tint.

<a id="f17-09"></a>

## F17-09: Commenting hides behind an unhinted long press with no haptic or range feedback, and it blocks copying code

*P2 improvement · interaction · effort M · found by review-comments*

- Where: `OCDesign/CodeCollection.swift:41`, `OCDesign/CodeCollection.swift:209`, `OCDesign/CodeCollection.swift:252`, `docs/design.md:129`
- Evidence: `CodeCollection.swift:41-42: the only way in is a 0.4 s UILongPressGestureRecognizer. CodeCollection.swift:209 returns no context menu for code rows.`; `There is no UIFeedbackGenerator or sensoryFeedback anywhere in Packages/OpencodeKit/Sources.`; `CodeCollection.swift:252-260: selectLines has no edge auto-scroll.` (+2 more)
- What happens: A first-time iPhone user opens Review: nothing suggests that lines can be commented on, and tapping a line does nothing. A user who discovers the long press gets no haptic when it begins, their finger covers the line being picked, and nothing reads out 'lines 12–18'. Dragging to the edge of the screen doesn't scroll, so a range can't extend beyond one screen. A long press meant to copy a snippet opens the comment editor instead.
- Why it matters: Line comments are a headline feature (SPEC.md:62: 'Review built for the phone, with line comments that go back to the agent'), yet they are effectively undiscoverable. The code viewer also can't copy code.
- Fix: This revisits docs/design.md:129 but keeps the long press. Add a one-time TipKit tip or an inline hint ('Touch and hold a line to comment'). Play UISelectionFeedbackGenerator when the press begins and on each line change. Float a range label above the finger and auto-scroll near the top and bottom edges. On release, offer an edit menu with Comment and Copy (also reachable by pointer right-click), or add a Copy button to the editor footer.
- Also reported as: F33-14 by ux-flows-ia

<a id="f17-14"></a>

## F17-14: Sent comment cards can't be tapped, read as three VoiceOver stops, and order their fields differently from the chip

*P3 improvement · consistency · effort M · found by review-comments*

- Where: `OCDesign/LineCommentEditor.swift:52`, `FeatureComposer/SessionActions.swift:133`, `FeatureTranscript/TimelineRowView.swift:63`, `OCDesign/TextSelection.swift:13`
- Evidence: `LineCommentEditor.swift:52-60: OCCommentCard shows the file name, then the range, then the comment, with no tap action and no accessibility grouping. The composer chip (ComposerDock.swift:119-122) and the diff annotation (CodeCell.swift:98-106) put the comment first, as does the desktop sent card (.build/design-reference/m4-comment-sent-light-1440x900.png: comment, then 'Example.swift:2').`; `TimelineRowView.swift:63 'Copy', and on iOS before 27 'Select text' and 'Copy' (TextSelection.swift:13-15), copy the raw prompt text: 'The user made the following comment regarding lines 2 through 3 of /abs/path: …'.`; `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.comment-only-light-393-default.png: six cards, each with three separate text rows.`
- What happens: In the transcript, a sent comment can't be tapped to see the code it refers to, although the composer chip can. VoiceOver reads 'Example.swift', 'lines 2-3' and 'Keep the public…' as separate stops, so six comments take 18 swipes. Long-press → Copy on such a prompt puts the raw comment notes, with absolute server paths, on the clipboard.
- Why it matters: Minor friction and inconsistency when going back over review feedback.
- Fix: Make a card tap open the file at its range, reusing the chip's focus logic. Combine each card into one accessibility element ('Comment on Example.swift, lines 2–3: …'). Show the comment first, then file:range, as the chip and the desktop do. Copy the displayed text plus readable comment lines instead of the raw notes.

<a id="f17-10"></a>

## F17-10: On iPhone the comment sheet hides the code under discussion and floats a desktop card in a full-height sheet

*P3 improvement · ux-flow · effort M · found by review-comments*

- Where: `OCDesign/Surfaces.swift:57`, `OCDesign/LineCommentEditor.swift:40`, `FeatureReview/ReviewScreen.swift:67`, `FeatureFiles/FilesScreen.swift:64`, `OCDesign/DiffCardView.swift:42` (+2 more)
- Evidence: `Surfaces.swift:57-61: ocSheet sets no detents, so the comment sheet opens at .large over the diff.`; `LineCommentEditor.swift:40-42: the editor is a bordered layer1 card capped at 400 pt, designed for inline use. In a sheet it is centered, 1 pt from the edges on a 402 pt iPhone 17 Pro and touching them on 375 pt phones.`; `OCDiffSelection.preview (DiffView.swift:28, the first selected lines) is computed but never shown in the editor.` (+3 more)
- What happens: On iPhone in Review, long-press lines 40-44. A full-height sheet covers the diff, the keyboard comes up, and the card floats in the remaining space showing only 'lines 40-44'; the code being commented on is no longer visible. After tapping Comment the sheet closes, and nothing says the comment now waits in the composer, which is hidden behind the Review sheet.
- Why it matters: Users write review comments without seeing the code, inside chrome meant for a desktop popover.
- Fix: Present the sheet at a fitted height or with `.presentationDetents([.medium, .large])`, as OCConfirmationSheet does. In sheets, render the editor full-width without the card border. Show the first lines of the selection (`preview`) above the field and the file name with middle truncation. Use inline editing for diff cards at regular width, and confirm 'Added to your next prompt' after submitting.
