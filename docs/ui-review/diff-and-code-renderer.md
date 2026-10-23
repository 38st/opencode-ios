# UI review: Diff and code renderer

Part of the [UI review](README.md). 15 bugs and 7 improvements, bugs first, then by severity. Paths under `Packages/OpencodeKit/Sources` are written without that prefix.

| ID | Severity | Finding |
| --- | --- | --- |
| [F16-02](#f16-02) | P2 bug | Unpaired added or removed lines are fully word-highlighted and lose all syntax colouring |
| [F16-03](#f16-03) | P2 bug | In split view, commenting on an unchanged line in the left column sends the agent a 'deleted lines' note |
| [F16-06](#f16-06) | P2 bug | VoiceOver reads split rows twice, offers no-op actions that empty the clipboard, and reused cells keep a stale hint |
| [F21-08](#f21-08) | P2 bug | Headings are missing almost everywhere: review file headers, markdown headings in replies, screen and sheet titles |
| [F35-06](#f35-06) | P2 bug | Diff card file name stays on one middle-truncated line at accessibility sizes ("Source…ain.swift") |
| [F16-01](#f16-01) | P2 bug | Very long lines (minified or generated files) become one cell thousands of points tall, drawn in a single draw pass |
| [F16-07](#f16-07) | P2 bug | Wrapped CJK and full-width text is silently clipped, and with wrapping off the end of the line cannot be scrolled to |
| [F22-09](#f22-09) | P2 bug | Review accordion file headers use fixed 44/88pt rows and a font resolved outside the view's trait collection |
| [F16-10](#f16-10) | P3 bug | Line numbers sit 4–5 pt above the code baseline |
| [F16-12](#f16-12) | P3 bug | TypeScript primitive type keywords are coloured as literals (`: string` green like string literals) |
| [F22-11](#f22-11) | P3 bug | Diff label rows are drawn into a single fixed line, clipping 'Open file' and long hunk headings at larger sizes |
| [G08-M1](#g08-m1) | P3 bug | VoiceOver 'Extend selection to this line' anchors on a stale or other-file selection and sends the wrong range |
| [F16-09](#f16-09) | P3 bug | Placeholder and hunk rows are one line tall, and header-only patches are mislabelled 'Diff too large to render' |
| [F24-11](#f24-11) | P3 bug | Pull-to-refresh in Review and Files snaps back instantly, can't be pulled on short content, and does nothing inside transcript diff cards |
| [F40-14](#f40-14) | P3 bug | With Wrap lines off, transcript diff cards capture horizontal swipes and can block iPhone back navigation |
| [F16-05](#f16-05) | P2 improvement | Code cannot be copied from diffs or the file viewer without VoiceOver, and the only 'Copy line' menu item copies placeholder text |
| [F16-08](#f16-08) | P3 improvement | Additions and deletions are told apart almost only by colour, with no +/− markers and no Differentiate Without Color support |
| [F16-11](#f16-11) | P3 improvement | Context folds: '1 hidden lines' rows, and the top fold expands from the start of the file instead of next to the change |
| [F27-10](#f27-10) | P3 improvement | Diff views re-parse the whole patch on every width change, starting a non-cancellable full preparation per drag event |
| [F16-13](#f16-13) | P3 improvement | Code gets little width: split engages at a 560 pt column (about 29–38 characters), the unified gutter shows two number columns, and wrapping breaks mid-word |
| [F27-06](#f27-06) | P3 improvement | Expanded inline diff cards embed a full-height UICollectionView in each transcript cell, realizing and drawing up to 200 rows at once |
| [F27-11](#f27-11) | P3 improvement | Horizontal diff scrolling rebuilds attributed strings and accessibility actions for every visible line on each pan event |

<a id="f16-02"></a>

## F16-02: Unpaired added or removed lines are fully word-highlighted and lose all syntax colouring

*P2 bug · visual · effort S · found by diff-renderer*

- Where: `OCRender/WordDiff.swift:45-49`, `OCDesign/CodeCell.swift:80-83`
- Evidence: `iphone/review-turn-navigation.png: the added file src/created.ts line 'export const created = true;' has the strong tint rgb(208,238,216) behind all its text, and every glyph is diffAddText rgb(20,54,29); 'export'/'const' are not keyword pink and 'true' is not constant teal`; `.build/design-reference/review-light-393x852.png: the desktop shows an added file with only the weak line tint rgb(243,249,245) and no word emphasis`; `WordDiff.swift:47: 'let spans = changed(a.map { document.lines[$0].text } ?? "", b.map { document.lines[$0].text } ?? "")': a line with no counterpart is diffed against "", so every token, including indentation, is marked changed` (+1 more)
- What happens: Any newly written file (the Write tool), any deleted file, or any block of inserted lines with fewer deletions than additions (the 2nd and 3rd added lines after a single removed line), in unified and split, in both appearances. Each line becomes a solid strong-green (or red) bar of uniformly coloured text.
- Why it matters: New files are the most common thing an agent produces, and they lose syntax highlighting entirely. Strong emphasis stops meaning 'what changed inside this line', and the renderer departs from the desktop.
- Fix: Compute word spans only when a pair has both sides, and optionally only when the pair is similar enough (for example, at least 40% of tokens in common). Leave unpaired lines with the weak line tint and normal syntax colours.

<a id="f16-03"></a>

## F16-03: In split view, commenting on an unchanged line in the left column sends the agent a 'deleted lines' note

*P2 bug · functional · effort S · found by diff-renderer*

- Where: `OCDesign/CodeCollection.swift:243-250`, `OCDesign/CodeCell.swift:41-44`, `OCDesign/DiffView.swift:156-171`, `OCModels/LineComment.swift:40-53`
- Evidence: `CodeCollection.swift:249: 'let side: LineSelection.Side = parent.split ? (right ? .additions : .deletions) : cell.kind == .deletion ? .deletions : .additions': any left-half press is .deletions, even on context rows (left == right)`; `LineComment.note: 'selection.deleted' → "regarding deleted lines 12 through 14 of …" plus the lines fenced as deleted text; m4-audit #8: deleted-side comments also omit the ranged file part`; `CodeCell.swift:41-44: VoiceOver offers 'Comment on deleted line' and 'Copy deleted line' on every context row in split view`
- What happens: iPad review in split view (the default at 560 pt or more). Long-press lines 12–14, which are unchanged, in the left column and type a comment. The prompt tells the agent these are deleted lines, fences them as removed code and attaches no file part. The same selection in unified view correctly uses the new side.
- Why it matters: The agent gets false information about which code still exists, and no file reference, from a natural gesture in the default iPad layout.
- Fix: In point(), use .deletions only when the pressed cell's kind is .deletion. Map left-column context lines to their new line numbers on the additions side, and offer the 'deleted line' accessibility actions only when row.left?.kind == .deletion.
- Also reported as: F17-02 by review-comments

<a id="f16-06"></a>

## F16-06: VoiceOver reads split rows twice, offers no-op actions that empty the clipboard, and reused cells keep a stale hint

*P2 bug · accessibility · effort S · found by diff-renderer*

- Where: `OCDesign/CodeCell.swift:34-46`, `OCDesign/CodeCell.swift:107`, `OCDesign/CodeCollection.swift:176-182`
- Evidence: `CodeCell.swift:45: 'accessibilityLabel = "Old line \(deleted.oldLine ?? 0), \(deleted.text). " + (accessibilityLabel ?? "")': for split context rows (left == right) the text is read twice, e.g. 'Old line 12, foo(). Line 12, context, foo()'. Deletion-only rows likewise.`; `The old half of a modified pair is announced as 'Old line 2, …' without 'removed'; 'context' is jargon; hunk rows are read as raw '@@ -12,7 +12,8 @@'`; `Label rows that keep the default actions (hunk headings, 'No changes', 'Loading…', 'Unable to load image.') offer 'Comment on line' and 'Extend selection', which do nothing, and 'Copy line', which runs 'OCCopy.text(line?.text ?? "")' and sets the pasteboard to an empty string` (+1 more)
- What happens: VoiceOver on, iPad review in split view (the default): every unchanged line's content is spoken twice. Swiping through a diff with a comment card makes later code lines carry the 'More options: Edit or Delete' hint. Trying the actions on a hunk heading wipes the clipboard.
- Why it matters: Reviewing a diff with VoiceOver is slow and misleading, and the clipboard can be lost.
- Fix: Build one label per row: 'Unchanged line 12: …' once; 'Removed line 2: …; added line 2: …' for pairs; friendly hunk text ('Lines 12 to 18, func foo'). Reset accessibilityHint and the custom actions in configure for every row. Give label rows only relevant actions (none, Expand, or Open file), and never copy an empty string.
- Verifier's note: Reset accessibilityHint, and set the custom actions explicitly, in configure for every row. Skip OCCopy when the text is empty.
- Also reported as: F17-12 by review-comments, F21-09 by a11y-voiceover, F21-11 by a11y-voiceover

<a id="f21-08"></a>

## F21-08: Headings are missing almost everywhere: review file headers, markdown headings in replies, screen and sheet titles

*P2 bug · accessibility · effort S · found by a11y-voiceover*

- Where: `OCDesign/CodeCell.swift:184`, `OCDesign/MarkdownStyles.swift:12`, `OCDesign/Surfaces.swift:78`, `FeatureTranscript/SessionScreen.swift:161`, `FeatureApprovals/PermissionSheet.swift:74` (+4 more)
- Evidence: `CodeCell.swift:163-188: CodeHeader's toggle is a plain UIButton (.button trait only). The 'Modified +1 −1' summary lives only in the open button's title, whose label is 'Open file <path>' (:185-186), so it is never spoken`; `MarkdownStyles.swift:10-15: OCMarkdownHeading only sets a font. Textual's Heading (.build/checkouts/textual/Sources/Textual/Internal/StructuredText/Heading.swift) adds no trait`; `Surfaces.swift:76-79: ocNavigationTitle replaces the bar title with a principal Text without .isHeader (Settings, Permission, Question, Add server, Diagnostics, full diff)` (+3 more)
- What happens: iPhone Review with several files expanded. The Headings rotor finds nothing, so getting to the 4th file means swiping through every line of files 1-3, and each file's 'Modified/Added +N −M' summary is never read. A long agent answer with '## Stream summary' sections can't be skimmed by heading. The Permission and Question sheets and the iPad session title expose no heading to orient on.
- Why it matters: Heading navigation is VoiceOver's main way to skim long content. Without it, diffs, long answers and multi-section sheets can only be read line by line (WCAG 1.3.1).
- Fix: Add .header to CodeHeader's toggle and put the summary in its value ('Modified, 1 addition, 1 deletion, expanded'). Add .accessibilityAddTraits(.isHeader) in OCMarkdownHeading, the ocNavigationTitle principal Text, SessionHeader's title, OCEmptyState titles, the PermissionContent / QuestionContent section titles, FormRenderer field titles, ServerSettingsView 'Servers' / 'App', the Add server title and 'New session'.

<a id="f35-06"></a>

## F35-06: Diff card file name stays on one middle-truncated line at accessibility sizes ("Source…ain.swift")

*P2 bug · accessibility · effort S · not verified · found by sweep-read-snapshots*

- Where: `OCDesign/DiffCardView.swift:58`, `OCDesign/DiffCardView.swift:60`, `OCDesign/DiffCardView.swift:65`
- Evidence: `capture-_-name-height.diff-light-393.png and diff-dark-393.png: "Sources/main.swift" renders as "Source…ain.swift". The header already stacks name and counts vertically, so there is room to wrap.`; `DiffCardView.swift:60 'Text(file).font(OCType.small).lineLimit(1).truncationMode(.middle)' applies at every text size`
- What happens: iPhone at accessibility sizes. Any real path (for example OCDesign/DiffCardView.swift) collapses to a few characters from each end, including inside the file name.
- Why it matters: The header's key information is unreadable, so users cannot tell which file changed.
- Fix: At accessibility sizes, allow wrapping (lineLimit nil or 3), or show the file name on its own line with the middle-truncated directory below.

<a id="f16-01"></a>

## F16-01: Very long lines (minified or generated files) become one cell thousands of points tall, drawn in a single draw pass

*P2 bug · performance · effort M · plausible, needs a running app to confirm · found by diff-renderer*

- Where: `OCDesign/DiffView.swift:239-253`, `OCDesign/CodeCell.swift:152-155`, `OCDesign/CodeCollection.swift:273-278`, `OCSync/FilesModel.swift:189-200`, `FeatureFiles/FilesScreen.swift:211` (+1 more)
- Evidence: `DiffView.swift:247-251: 'while index < attributed.length { let count = CTTypesetterSuggestClusterBreak(typesetter, index, columnWidth); index += max(1, count); lines += 1 }' → 'CGFloat(max(1, lines)) * lineHeight', with no cap`; `CodeCell.swift:154: the whole line is drawn by one 'attributed.draw(with:)' into the cell's own (untiled) backing store; with wrapping off the draw width is 'CGFloat(attributed.length) * fontSize'`; `CodeCollection.swift:277: every horizontal pan frame calls configure on every visible cell, which rebuilds each line's NSAttributedString (CodeCell.swift:33)` (+1 more)
- What happens: iPhone 17 Pro at the default text size. Open dist/app.min.js (about 300 KB on one line) in Files, or review a turn that touched such a file. About 40 characters fit per wrapped line, so CodeMetrics yields roughly 7,500 visual lines: one row of about 180,000 pt. The cell's backing store needs about 14 KB per point of height at 3x. Rows taller than the GPU texture limit (16,384 px, about 5,461 pt; a line of roughly 9,000+ characters on iPhone) are likely to be dropped by Core Animation, leaving a huge blank area. Shorter rows still cost tens to hundreds of MB. With wrapping off, every pan frame re-typesets the whole line.
- Why it matters: Minified bundles, source maps, SVG paths and single-line JSON are common in agent work. Their content shows blank or janky, and memory pressure risks the app being terminated in Files or Review.
- Fix: Cap what one row renders. For example, show the first N thousand characters plus a 'Line truncated (N characters): Open file / Show all' affordance, force no-wrap for lines over a threshold, or split long wrapped lines into several virtual rows of at most about one screen each. Cache the attributed strings in the cell and change only the offset (setNeedsDisplay) during horizontal pans. Consider a byte-based gate next to the 20,000-line gate.
- Verifier's note: Gate rendering on line length as well as line count. Above a threshold (for example 2,000 characters), render a prefix with an 'Open full line' action that opens a text sheet, so that no row is taller than about one screen. Cache attributed strings per cell and call only setNeedsDisplay during horizontal pans.

<a id="f16-07"></a>

## F16-07: Wrapped CJK and full-width text is silently clipped, and with wrapping off the end of the line cannot be scrolled to

*P2 bug · localization · effort S · found by diff-renderer*

- Where: `OCDesign/DiffView.swift:243`, `OCDesign/DiffView.swift:150-152`, `OCDesign/CodeCell.swift:153-154`, `OCDesign/CodeCollection.swift:268-272`
- Evidence: `DiffView.swift:243: 'if CGFloat(display.utf16.count) * font * 0.61 <= columnWidth { return lineHeight }': the fast path assumes every UTF-16 unit is 0.6 em wide. JetBrains Mono has no CJK glyphs, and the fallback ideographs are about 1 em.`; `DiffView.swift:152: 'textWidth: CGFloat(widest) * fontSize * 0.61 + 24' bounds horizontal scrolling with the same underestimate`; `CodeCell.swift:153: drawing is clipped to the row height, so an extra wrapped line is cut without any indicator`
- What happens: iPhone 17 Pro, unified view, default size, code column about 322 pt. A line `// ` followed by 30 Chinese characters is estimated at about 262 pt (one row) but renders at about 413 pt, so it wraps to two lines inside a 24 pt row and the last about 8 characters vanish. With Wrap lines off, the scroll limit is about 150 pt short, so the tail stays unreachable. The same applies to Japanese and Korean strings, comments and Markdown, and it is worse in narrower split columns.
- Why it matters: Code-review content is silently lost for CJK users, and nothing tells them text is missing.
- Fix: Use the fast path only when every scalar is narrow (ASCII or Latin, for example), and otherwise measure with the CTTypesetter path. Derive textWidth from measured CTLine widths, at least for non-ASCII lines.

<a id="f22-09"></a>

## F22-09: Review accordion file headers use fixed 44/88pt rows and a font resolved outside the view's trait collection

*P2 bug · accessibility · effort M · found by a11y-dynamic-type*

- Where: `OCDesign/CodeCell.swift:174-189`, `OCDesign/CodeCollection.swift:363`, `FeatureReview/ReviewScreen.swift:192`
- Evidence: `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.changes-working-light-393-accessibility5.png: 'Example.swift' and 'Modified +2 −2 · Open file' stay at ~13pt while every surrounding label is ~44pt. Crop: crops/a11y-dynamic-type/changes-working-a5.png`; `CodeCell.swift:176 calls UIFontMetrics(forTextStyle: .footnote).scaledFont(for:) without compatibleWith:, and nothing sets adjustsFontForContentSizeCategory. CodeCell.swift:189 fixes both buttons at 44pt. CodeCollection.swift:363 sets the header height to 88pt or 44pt.`
- What happens: On iPhone, or on iPad at an accessibility size (which forces the compact accordion), open Review → Changes.

  - **Font source:** the header font isn't taken from the collection view's traits. In snapshots it ignores the size, and it won't update if the text size changes while the panel is open.
  - **Fixed rows:** once it does pick up AX5 from the system (44pt Inter, 53pt line), it is drawn into fixed 44pt button frames inside an 88pt header. The title and the 'Modified … · Open file' line overflow their rows, and the second line (~600pt wide) is middle-truncated.
- Why it matters: In the main iPhone review layout, the file name and the Open file action are either tiny or cramped and overlapping at large sizes.
- Fix: Resolve the font with scaledFont(for:compatibleWith: traitCollection) and set adjustsFontForContentSizeCategory on both labels. Derive the CodeLayout header heights from the scaled line height (or UIFontMetrics.scaledValue(for: 44)), and invalidate them when traits change. Allow the title two lines with middle truncation.
- Also reported as: F15-09 by review-changes, F16-14 by diff-renderer, F36-08 by sweep-review-snapshots

<a id="f16-10"></a>

## F16-10: Line numbers sit 4–5 pt above the code baseline

*P3 bug · design-parity · effort S · found by diff-renderer*

- Where: `OCDesign/CodeCell.swift:141-150`, `OCDesign/CodeCell.swift:70-71`
- Evidence: `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.diff-swift-unified-wrap-light-393-default.png: the ink of number '1' ends at y=48 px while the 'E' of 'Example' ends at y=60 px, a 4 pt offset`; `capture-_-name.diff-swift-unified-wrap-light-393-accessibility5.png: 76 px vs 91 px, a 5 pt offset`; `.build/design-compare/m4-diff-swift-unified-wrap-light-393-default.png: the desktop reference shares a baseline between numbers and code` (+1 more)
- What happens: Every diff and source view on all devices: each row's number floats visibly higher than its code, more so at larger text.
- Why it matters: The gutter looks misaligned on every line and departs from the reference design.
- Fix: Draw numbers with the same paragraph style (min/max line height) at y: 0, or offset them by lineHeight − font.lineHeight so the baselines match.
- Also reported as: F30-12 by visual-polish-iphone, F36-13 by sweep-review-snapshots

<a id="f16-12"></a>

## F16-12: TypeScript primitive type keywords are coloured as literals (`: string` green like string literals)

*P3 bug · visual · effort S · found by diff-renderer*

- Where: `OCRender/CodeHighlighter.swift:75-86`
- Evidence: `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.diff-typescript-unified-wrap-light-393-default.png: 'string' in '(name: string): string' samples rgb(25,139,67), which is syntaxString, the same as the '"Hello"' literal`; `CodeHighlighter.swift:77-78 match the types "string", "number" and "boolean" whether or not the node is named, so TypeScript's anonymous predefined_type tokens are classified as .string or .number. 'void' and 'any' fall through to keyword pink.`
- What happens: Every TypeScript diff or file: type annotations such as `: string`, `: number` and `: boolean` look like string and numeric literals, and primitive types get three different colours.
- Why it matters: Misleading colours in the most common language for opencode users.
- Fix: Apply the literal classes only to named nodes (if named && list.contains(type)), and map predefined_type and its children to .type, as other grammars' primitive_type already is.
- Also reported as: F36-14 by sweep-review-snapshots

<a id="f22-11"></a>

## F22-11: Diff label rows are drawn into a single fixed line, clipping 'Open file' and long hunk headings at larger sizes

*P3 bug · layout · effort S · found by a11y-dynamic-type*

- Where: `OCDesign/CodeCell.swift:110-113`, `OCDesign/DiffView.swift:231-234`, `OCRender/DiffRows.swift:54`, `OCRender/DiffRows.swift:57`
- Evidence: `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.changes-truncated-light-393-accessibility5.png: only 'Diff too large to render  ·' is visible. The 'Open file' half wraps onto a second line that the 37pt row clips. Crop: crops/a11y-dynamic-type/changes-truncated-a5-row.png`; `DiffView.swift:234 guard row.commentID != nil else { return lineHeight }: label rows always get exactly one line.`
- What happens: Affects iPhone at xxxLarge or any accessibility size, and narrower transcript diff cards from xLarge. Applies to a binary, too-large or truncated file, a long hunk heading, or an image message. NSString.draw(in:) word-wraps the label, but the row is only one line tall, so the tail (including the 'Open file' cue) disappears with no ellipsis.
- Why it matters: The cue that the row opens the file is lost, and long hunk headings and media messages are cut.
- Fix: Measure label rows in CodeMetrics.heights the same way as wrapped code lines (same typesetter, label font). Alternatively, draw with middle truncation and put 'Open file' on its own line at accessibility sizes.

<a id="g08-m1"></a>

## G08-M1: VoiceOver 'Extend selection to this line' anchors on a stale or other-file selection and sends the wrong range

*P3 bug · accessibility · effort S · found by verifier G08*

- Where: `OCDesign/CodeCollection.swift:187-192`, `OCDesign/CodeCell.swift:38`, `FeatureReview/ReviewScreen.swift:68`, `FeatureReview/ReviewScreen.swift:201-202`, `FeatureFiles/FilesScreen.swift:163`
- Evidence: `CodeCollection.swift:189-191: 'let prior = self.parent.selected ?? .init(start: line, side: side); self.selection = .init(start: prior.start, end: line, side: prior.side, endSide: side); self.parent.onComment(section.id, self.selection ?? prior)'. The anchor is the model-wide selection and is never checked against section.id or parent.selectedFile.`; `ReviewScreen.swift:201 passes 'selected: model.selection' for the whole compact accordion. Submitting at :68 clears only 'comment', so model.selection outlives a sent comment.`; `FilesScreen.swift:163: Find writes model.selection too, so Extend after a find anchors on the match.`
- What happens: VoiceOver on, iPhone Review accordion with Sources/Example.swift and src/created.ts expanded. On Example.swift line 120, choose 'Comment on line', then type and submit a comment. Later, on src/created.ts line 5, choose 'Extend selection to this line' to start a new range. The action builds start 120, end 5, and the editor opens for src/created.ts with 'lines 5-120'; submitting sends 'lines 5 through 120'. Within a single file, Extend after any submitted comment likewise starts from that comment's first line.
- Why it matters: Extend is VoiceOver users' only way to make a multi-line comment, and it silently produces a range they never selected, which is then sent to the agent.
- Fix: Keep a per-file anchor that 'Comment on line' and the long-press gesture set, and clear it after submitting. Ignore parent.selected when parent.selectedFile != section.id. Announce the resulting range, for example UIAccessibility.post(notification: .announcement, argument: 'Lines 5 to 9 selected').

<a id="f16-09"></a>

## F16-09: Placeholder and hunk rows are one line tall, and header-only patches are mislabelled 'Diff too large to render'

*P3 bug · layout · effort M · found by diff-renderer*

- Where: `OCDesign/DiffView.swift:115`, `OCDesign/DiffView.swift:234`, `OCDesign/CodeCell.swift:110-113`, `OCSync/ReviewModel.swift:254`
- Evidence: `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.changes-truncated-light-393-accessibility5.png: the row reads 'Diff too large to render  ·' and the 'Open file' action text is cut off`; `DiffView.swift:234: 'guard row.commentID != nil else { return lineHeight }': every label row is a single line, but CodeCell draws it with NSString.draw(in:), which word-wraps and clips`; `DiffView.swift:115: 'doc.kind == .headerOnly ? "Diff too large to render"'. ReviewModel.swift:254 retries header-only patches only when additions > 0 or deletions > 0, so 0/0 header-only patches reach this label.`
- What happens: (1) At accessibility text sizes on iPhone, the 'Open file' call to action on truncated or binary rows is cut off. Even at the default size, long hunk headings such as '@@ -120,7 +120,9 @@ public func makeSomething(argument:)' lose their tail without an ellipsis. (2) A mode-only change (old mode 100644 → new mode 100755) or a newly created empty file produces headers with no hunks and 0/0 counts, and the app says the diff is 'too large to render'.
- Why it matters: The action text is lost at large sizes, and users get wrong information about simple changes.
- Fix: Measure label rows with their font and width (as comment cards already are). Derive the label from the headers and counts: 'Empty file added', 'File mode changed 644 → 755', 'Renamed', and keep 'Diff too large to render' for real truncation.
- Verifier's note: Empty patches map to 'Binary file' (DiffView.swift:115), so an empty file created in a session may be labelled binary. Derive these labels from FileDiff.status, the counts and the headers.

<a id="f24-11"></a>

## F24-11: Pull-to-refresh in Review and Files snaps back instantly, can't be pulled on short content, and does nothing inside transcript diff cards

*P3 bug · interaction · effort S · found by touch-gestures-motion*

- Where: `OCDesign/CodeCollection.swift:45`, `OCDesign/CodeCollection.swift:242`, `FeatureReview/ReviewScreen.swift:120`, `FeatureFiles/FilesScreen.swift:105`, `OCSync/ReviewModel.swift:104`
- Evidence: `@objc func refresh(_ control: UIRefreshControl) { parent.refresh(); control.endRefreshing() }`; `ReviewScreen: .refreshable { model.refresh() }, where refresh() spawns a Task and returns; same pattern for FilesModel.invalidate()`; `No alwaysBounceVertical on the code collection` (+1 more)
- What happens: Pull down on the Changes diff or an open file. The spinner disappears immediately, and nothing shows that a reload is running or has finished; the loading view only appears before the first load. On a 5-line file (review-files.png) or a short accordion the collection can't be pulled at all. The 'No uncommitted changes yet' empty state has no refresh. Inline transcript diff cards get the same refresh control with an empty closure.
- Why it matters: Users get no feedback from pull-to-refresh, and the affordance only works some of the time.
- Fix: Make refresh async and await it in .refreshable. End the UIRefreshControl when ReviewModel.loading or FilesModel.loading becomes false. Set alwaysBounceVertical = true when a refresh closure is provided, and install no refresh control otherwise. Add .refreshable to the review empty states.

<a id="f40-14"></a>

## F40-14: With Wrap lines off, transcript diff cards capture horizontal swipes and can block iPhone back navigation

*P3 bug · interaction · effort S · plausible, needs a running app to confirm · found by navigation-state-restoration*

- Where: `OCDesign/CodeCollection.swift:43-44`, `OCDesign/CodeCollection.swift:261-266`, `FeatureTranscript/ToolRowView.swift:54`, `FeatureServers/ServerRootView.swift:65-70`
- Evidence: `CodeCollection.swift:265 'return !parent.wrap && abs(velocity.x) > abs(velocity.y)': the pan begins even when nothing overflows ('maxHorizontalOffset() == 0') or the content is already at its leading edge`; `There is no shouldRequireFailureOf or shouldBeRequiredToFailBy relationship with the navigation controller's interactivePopGestureRecognizer or iOS 26's interactiveContentPopGestureRecognizer`; `Transcript tool rows embed DiffCardView, which uses OCDiffView and CodeCollection (ToolRowView.swift:54), inside the iPhone NavigationStack`
- What happens: iPhone with Settings > Wrap lines turned off. In a session, a rightward swipe that starts on an edit or patch diff card is claimed by the card's custom pan even when the diff fits or is already scrolled to its start. Inferred from code: the content-area back swipe likely does not fire there, and near the left edge the two gestures compete. Not verified on a device.
- Why it matters: Back swipes fail inconsistently on screens full of diffs, which is the main way iPhone users leave a session.
- Fix: Begin the pan only when there is overflow in the swipe direction (offset above 0 for a rightward swipe, below the maximum for a leftward one). Have it yield to the navigation controller's pop gestures, through `require(toFail:)` or the shouldBeRequiredToFailBy delegate.

<a id="f16-05"></a>

## F16-05: Code cannot be copied from diffs or the file viewer without VoiceOver, and the only 'Copy line' menu item copies placeholder text

*P2 improvement · interaction · effort M · found by diff-renderer*

- Where: `OCDesign/CodeCollection.swift:207-222`, `OCDesign/CodeCell.swift:36-40`, `OCDesign/DiffCardView.swift:30-53`, `FeatureFiles/FilesScreen.swift:167-174`
- Evidence: `CodeCollection.swift:209: 'guard row.commentID != "__editor", row.hidden != nil || row.commentID != nil else { return nil }': code rows get no context menu, and long press (0.4 s) is reserved for comment selection`; `CodeCollection.swift:220: 'OCCopy.text((row.right ?? row.left)?.text ?? row.label ?? "")': on a fold row this copies the literal text '11 hidden lines'`; `CodeCell.swift:39: 'Copy line' exists only as an accessibility custom action` (+1 more)
- What happens: A sighted user wants to copy a snippet from a reviewed change, a tool diff or an opened source file to paste into the prompt or another app. No gesture, menu or toolbar action does it on iPhone or iPad.
- Why it matters: A basic expectation of a code viewer is missing across Review, Files, tool cards and permission previews.
- Fix: When a long-press selection ends, show an edit menu (UIEditMenuInteraction) with 'Comment…', 'Copy' (the selected lines of that side) and 'Copy with line numbers'. Add Copy to secondary-click menus on code rows, and add 'Copy diff'/'Copy contents' toolbar actions. Retitle or remove the fold-row item.
- Also reported as: F18-07 by files-browser

<a id="f16-08"></a>

## F16-08: Additions and deletions are told apart almost only by colour, with no +/− markers and no Differentiate Without Color support

*P3 improvement · accessibility · effort M · found by diff-renderer*

- Where: `OCDesign/CodeCell.swift:126-142`, `OCDesign/CodeCell.swift:80-83`, `OCDesign/Resources/Colors.xcassets/oc2-diffAddWeak.colorset`, `OCDesign/Resources/Colors.xcassets/oc2-diffRemoveWeak.colorset`
- Evidence: `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.diff-swift-unified-wrap-dark-393-default.png: the only cues are a 2 pt coloured bar, coloured numbers and tints`; `Deuteranopia simulation, light mode: bar/number colours rgb(29,120,60) and rgb(184,45,53) become rgb(110,102,64) and rgb(121,109,48) (1.1:1). Line tints rgb(241,248,243) and rgb(250,241,241) both become about rgb(245,245,242). Strong word tints become about rgb(235,233,223) and rgb(227,224,215).`; `Dark mode: the weak tints (alpha 0.10 over rgb(8,8,8)) measure 1.07:1 against the background and 1.00:1 against each other` (+1 more)
- What happens: A red-green colour-blind reviewer in unified view can tell removed from added lines only by which of the two number columns is filled. In dark mode on an OLED iPhone, the line tints are close to invisible even with normal vision.
- Why it matters: A core review judgement (what was removed and what was added) relies on colour, which does not meet WCAG 1.4.1 (Use of Color).
- Fix: Draw a one-character '+'/'−' marker after the line numbers, like the desktop's diff indicators, either always or when Differentiate Without Color is on, and say 'added' or 'removed' in VoiceOver. Raise the weak-tint alpha and the line-number contrast when Increase Contrast is on. This revisits the tint decision in docs/design.md.
- Verifier's note: Show +/- markers at least when Differentiate Without Color is on, which keeps desktop parity by default. Keep the two-column unified gutter, because it is the existing positional cue.

<a id="f16-11"></a>

## F16-11: Context folds: '1 hidden lines' rows, and the top fold expands from the start of the file instead of next to the change

*P3 improvement · interaction · effort S · found by diff-renderer*

- Where: `OCRender/DiffRows.swift:39-40`, `OCRender/DiffRows.swift:57`, `OCRender/DiffRows.swift:20-24`, `OCDesign/CodeCollection.swift:204`
- Evidence: `DiffRows.swift:39-40 folds any run longer than the 4+4 context lines, so a 9-line unchanged run yields '"\(range.count) hidden lines"' = '1 hidden lines', a row as tall as the line it hides`; `CodeCollection.swift:204: a tap calls 'onExpand(section.id, range, false, false)' → 'range.prefix(20)'. For the leading fold (lines 0..<first change−4) this reveals lines 1–20 of the file, the end farthest from the change.`; `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.context-collapsed-light-393-default.png: folds are plain muted text with no expand affordance`
- What happens: A file whose first change is at line 500: tapping the top '496 hidden lines' row shows lines 1–20 and leaves 476 lines hidden between them and the change. Context next to the change needs the long-press menu ('Expand 20 lines below').
- Why it matters: Expanding context takes extra taps and guesswork, and singular and plural wording is wrong.
- Fix: Don't fold runs shorter than about 3 lines. Use 'line' for a count of one. For the leading fold, make a tap reveal the lines next to the first change (range.suffix). Show explicit ↑/↓ expand affordances on fold rows, as the desktop separators do.

<a id="f27-10"></a>

## F27-10: Diff views re-parse the whole patch on every width change, starting a non-cancellable full preparation per drag event

*P3 improvement · performance · effort M · found by ui-performance*

- Where: `OCDesign/DiffView.swift:72-105`, `OCRender/DiffDocument.swift:55-59`, `FeatureReview/ReviewScreen.swift:50-53`, `FeatureFiles/FilesScreen.swift:48-51`
- Evidence: `DiffView.swift:83 '.task(id: PreparationKey(... width: geometry.size.width ...))': width is part of the key, and each run calls DiffParser.prepare (line 92) for every expanded input`; `DiffDocument.swift:55-59: the @concurrent prepare parses and runs WordDiff with no cancellation checks, so a cancelled task still completes its full parse`; `ReviewScreen.swift:52 updates model.sidebarWidth on every DragGesture change, and FilesScreen.swift:48-51 does the same for the file tree` (+2 more)
- What happens: In iPad Review with the 5,000-line diff, drag the file-tree divider for one second. Each of the 60-120 drag events per second restarts preparation, so dozens of full parses, word diffs and re-measurements run concurrently off-main. The CPU saturates, and the final layout appears only after they drain. Resizing a Stage Manager window behaves the same way.
- Why it matters: Resizing on iPad causes CPU and thermal spikes, late diff updates, and stutter from CPU contention.
- Fix: Separate width-independent work from measurement. Cache the parsed, word-diffed and highlighted DiffDocument by text hash, as DiffHighlighter already does, and key only CodeMetrics.heights on width. Re-measure for width only after the drag ends. Add Task.checkCancellation() in the parse and word-diff loops.
- Verifier's note: Also check for cancellation between inputs inside the preparation loop, not only after it.

<a id="f16-13"></a>

## F16-13: Code gets little width: split engages at a 560 pt column (about 29–38 characters), the unified gutter shows two number columns, and wrapping breaks mid-word

*P3 improvement · layout · effort M · found by diff-renderer*

- Where: `OCDesign/DiffView.swift:73`, `OCDesign/DiffView.swift:147`, `OCDesign/CodeCell.swift:70`, `OCDesign/DiffView.swift:248`, `docs/design.md:121`
- Evidence: `ipad/ipad-review-large-split.png: a 706 pt diff area gives two 353 pt columns, about 297 pt of code each (about 38 characters at 13 pt). At the 560 pt threshold that drops to about 29 characters.`; `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.diff-typescript-unified-wrap-dark-393-accessibility5.png: code starts at about 118 pt of 393 pt (the two-number gutter is 30% of the width), and lines break as 'gree|ting', 'He|llo', 'We|lcome'`; `.build/design-compare/m4-diff-swift-unified-wrap-light-393-default.png: the desktop's unified view uses a single number column`
- What happens: On iPad landscape with split on (the default), ordinary 80–120-character lines wrap 3–4 times per column. On iPhone at accessibility sizes, only about 20 characters fit per visual line and identifiers are cut mid-word.
- Why it matters: Wrapped code is harder to read where screen space is already tight.
- Fix: Use split only when each column fits about 80 characters at the current font, for example about 600 pt or more per column at 13 pt, computed from character capacity rather than a fixed 560 pt. In compact or accessibility layouts, show one number column (the new number, or the old one for deletions). Wrap at word and punctuation boundaries with a character fallback (CTTypesetterSuggestLineBreak and .byWordWrapping in both measurement and drawing). This revisits the 560 pt split rule in docs/design.md.
- Verifier's note: Word-boundary wrapping has to change in both places to keep row heights correct: CodeMetrics (CTTypesetterSuggestLineBreak) and CodeCell (.byWordWrapping). Do not drop the old-number column in unified view unless +/- markers are added at the same time.

<a id="f27-06"></a>

## F27-06: Expanded inline diff cards embed a full-height UICollectionView in each transcript cell, realizing and drawing up to 200 rows at once

*P3 improvement · performance · effort M · found by ui-performance*

- Where: `OCDesign/DiffCardView.swift:30-33`, `OCDesign/DiffCardView.swift:75-79`, `OCDesign/CodeCollection.swift:30-53`, `OCDesign/CodeCollection.swift:382-393`, `FeatureTranscript/ToolRowView.swift:52-56` (+1 more)
- Evidence: `DiffCardView.swift:32 sizes the nested diff at 'min(4_800, max(48, patch line count * 24))'. Its own bounds therefore cover every row, and CodeLayout.layoutAttributesForElements (CodeCollection.swift:382-393) returns all of them`; `ToolRowView.swift:54 passes 'expanded: expanded', which is 'detail.expanded' (TimelineRowView.swift:170), so every edit row in the Detailed and Everything presets shows its diff expanded`; `CodeCollection.swift:30-53: each card creates a UIViewController, a UICollectionView, two gesture recognizers and a UIRefreshControl. OCDiffView then re-parses and re-measures the patch (DiffView.swift:83-105), and repeats this after every cell reuse because of '.id(id)'` (+1 more)
- What happens: With Timeline detail set to Detailed or Everything, in a session with several 100-200-line edits, each edit cell that scrolls in builds a nested collection view and draws up to 200 CodeCells with CoreText, even when only its top edge is visible. Scrolling back rebuilds it and prepares the diff again.
- Why it matters: Edit-heavy sessions hitch while scrolling in the expanded presets, and each visible edit costs extra memory. Switching to Compact avoids it.
- Fix: Inside timeline cells, render a bounded, non-scrolling preview: the first 20-40 prepared rows drawn in one view, or a cached image, sized from CodeMetrics heights. Keep the full scrolling CodeCollection for the Show full diff sheet. Cache prepared DiffDocuments by patch hash so a reused cell does not parse again.

<a id="f27-11"></a>

## F27-11: Horizontal diff scrolling rebuilds attributed strings and accessibility actions for every visible line on each pan event

*P3 improvement · performance · effort S · found by ui-performance*

- Where: `OCDesign/CodeCollection.swift:273-301`, `OCDesign/CodeCollection.swift:95-97`, `OCDesign/CodeCell.swift:28-48`, `OCDesign/CodeCell.swift:68-89`
- Evidence: `CodeCollection.swift:277 'for path in view.indexPathsForVisibleItems { ... configure(cell, at: path) }' runs on every pan callback (line 282) and every decay display-link tick (line 297)`; `CodeCell.swift:33 'left = attributed(row.left); right = attributed(row.right)'; lines 36-46 allocate 3-6 UIAccessibilityCustomActions, then setNeedsDisplay() (line 47)`; `CodeCell.swift:75-76: for every syntax, word and match span, the code slices the line prefix and runs replacingOccurrences for tabs, which is O(spans x line length)` (+2 more)
- What happens: In the iPad split diff with wrapping off, pan sideways across long lines. Up to 120 times a second, about 40 visible cells each rebuild two NSAttributedStrings with per-span string slicing, recreate their accessibility actions, and redraw with CoreText. The else-branch at line 96 also reconfigures every visible cell on any unrelated SwiftUI update, such as typing in the review file filter.
- Why it matters: Horizontal panning probably drops frames on ProMotion devices, and the rebuilds waste CPU and battery.
- Fix: When only the horizontal offset changes, update the cell's offset and redraw, or translate a text sublayer, without calling configure. Cache attributed strings per row, since they depend only on the row, wrap setting, font and matches, and build the accessibility actions once per row. Reconfigure visible cells in updateUIViewController only when selection, search or comments actually changed.
