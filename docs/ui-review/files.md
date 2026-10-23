# UI review: Files

Part of the [UI review](README.md). 12 bugs and 4 improvements, bugs first, then by severity. Paths under `Packages/OpencodeKit/Sources` are written without that prefix.

| ID | Severity | Finding |
| --- | --- | --- |
| [F18-01](#f18-01) | P2 bug | Markdown preview links resolve from the project root, and #anchor links open a bogus "File not found" tab |
| [F18-02](#f18-02) | P2 bug | Nothing marks the open file: tabs have no active state and the find list highlights a different file |
| [F18-04](#f18-04) | P2 bug | File tree nesting reads backwards: child rows start left of their parent, and files and folders are misaligned |
| [F18-05](#f18-05) | P2 bug | On iPhone, "Mention in composer" gives no feedback and adds duplicate mentions |
| [F18-10](#f18-10) | P2 bug | Find in file: the field isn't focused on open, Return and Escape don't behave as expected, and a stale query overrides link targets |
| [F18-11](#f18-11) | P2 bug | Fuzzy-find results truncate the file name before its folder and drop the "/" separator |
| [F18-12](#f18-12) | P2 bug | Files loses the user's place: the iPhone tree scrolls back to the top, tab switches snap to an old line, and the tree width resets |
| [F18-13](#f18-13) | P2 bug | Status messages are dead ends or unclear: not-found and list errors lack Retry, and the large-file banner has no units |
| [F21-10](#f21-10) | P2 bug | File trees hide folder vs file, expanded state and reviewed status from VoiceOver; status reads as the letters 'A', 'D', 'M' |
| [F18-06](#f18-06) | P3 bug | A failed file search shows "No results found" on iPhone, or a red error over the open file on iPad |
| [F27-05](#f27-05) | P3 bug | Files image viewer decodes the full-resolution image on the main thread and creates a new UIImage on every body pass |
| [G13-M2](#g13-m2) | P3 bug | Files search results put the directory before the file name on one line, so at accessibility sizes the name loses its extension ('Sources Example.s…') |
| [F18-09](#f18-09) | P2 improvement | The viewer never shows the file's path, and Copy path and Share are unreachable while viewing |
| [G09-M2](#g09-m2) | P3 improvement | Wrap lines can't be changed from the Files viewer or the iPhone review, only from Settings |
| [G15-M2](#g15-m2) | P3 improvement | The Files text viewer re-decodes the whole file into new Strings on every render, then compares and hashes them on the main thread |
| [F18-14](#f18-14) | P3 improvement | Image viewer pinch-zoom grows from the top-left corner, with no double-tap or zoom-to-point |

<a id="f18-01"></a>

## F18-01: Markdown preview links resolve from the project root, and #anchor links open a bogus "File not found" tab

*P2 bug · functional · effort M · found by files-browser*

- Where: `FeatureFiles/FilesScreen.swift:209`, `OCRender/StreamingMarkdown.swift:19-24`, `OCRender/StreamingMarkdown.swift:53`, `OCDesign/MarkdownBlockView.swift:28-31`, `FeatureReview/WorkspaceReviewPanel.swift:42` (+2 more)
- Evidence: `FilesScreen.swift:209 'else if path.path.lowercased().hasSuffix(".md") && preview { ScrollView { StreamingMarkdownView(content.text)... } }': no base directory and no link handling of its own; it inherits the panel's ocFileLinks, which calls files.openLink(link)`; `StreamingMarkdown.swift:22 'let fileLink = scheme == nil || ...': "#installation" has no scheme, so it stays a file link`; `FilesModel.swift:157 'path.replacingOccurrences(of: #"^(\.\./)+"#, with: "" ...)', then a fuzzy suffix match from the session root` (+3 more)
- What happens: iPhone or iPad, Files tab: open a README.md that has a table of contents, with Preview on, and tap "Installation" (href #installation). FileLink keeps "#installation" and fuzzy find has no exact match, so ReviewPath accepts it. open() adds a tab "#installation", and the README is replaced by red text "File not found: #installation". A folder link such as [docs](docs/) behaves the same way. In docs/guide/README.md, [API](../api.md) loses its ../ and opens whichever api.md matches by suffix (the root one if it exists), or drops the user into the filter list. A prompt doc such as AGENTS.md that mentions \<think> outside code previews with text missing.
- Why it matters: Tables of contents and relative links are standard in READMEs. Here they open the wrong file or leave junk error tabs, and the user loses the document they were reading. The preview can also silently hide file text.
- Fix: In FilesScreen, give the preview its own ocFileLinks (or a base path):
  - Treat #fragment links as in-document: scroll to the matching heading, or ignore them.
  - Resolve relative hrefs against (path.path as NSString).deletingLastPathComponent before calling openLink. FileLink.normalize already folds "..".
  - Don't add a tab until the read succeeds, or remove it on 404.
  - Add a no-cleanup option to StreamingMarkdown for file previews.
  - Decide previewability with FileLanguage == "markdown" so .markdown files get a preview too.

<a id="f18-02"></a>

## F18-02: Nothing marks the open file: tabs have no active state and the find list highlights a different file

*P2 bug · state · effort S · found by files-browser*

- Where: `FeatureFiles/FilesScreen.swift:36-41`, `FeatureFiles/FilesScreen.swift:83-86`, `FeatureFiles/FilesScreen.swift:130`, `FeatureReview/ReviewScreen.swift:113-115`
- Evidence: `iphone/review-files.png: "All files" and "Example.swift ×" are styled identically`; `ipad/ipad-review-files.png: the "src example.ts" row is highlighted while Sources/Example.swift is the open file`; `ipad/ipad-review-file-tree.png: the open Example.swift has no highlight in the tree` (+3 more)
- What happens: iPhone, light mode: open three files from transcript links. The tab strip reads "All files  A.swift ×  B.swift ×  C.swift ×" in identical ghost styling, so nothing shows which file is on screen. iPad: filter "Example" and tap the second result, Sources/Example.swift. The first row (src example.ts) stays highlighted while Example.swift is open. With the filter cleared, the tree never marks the open file. VoiceOver reports no selected tab.
- Why it matters: Users lose track of which file they are reading, and the only highlight points at the wrong file. The desktop app, and this app's own Review sidebar (layer2 background plus a "Selected" value), both mark the active file.
- Fix:
  - Style the active tab, and "All files" while browsing, as selected (layer2 fill or a 2-point underline like the desktop), add .accessibilityAddTraits(.isSelected), and scroll it into view with a ScrollViewReader.
  - In both the tree and the results, highlight the row whose path equals model.selectedPath?.path.
  - Draw the resultIndex cursor only while filterFocused, and set resultIndex when a row is tapped.

<a id="f18-04"></a>

## F18-04: File tree nesting reads backwards: child rows start left of their parent, and files and folders are misaligned

*P2 bug · layout · effort S · found by files-browser*

- Where: `FeatureFiles/FilesScreen.swift:123`, `FeatureFiles/FilesScreen.swift:126`, `FeatureFiles/FilesScreen.swift:128-130`, `FeatureFiles/FilesScreen.swift:117-121`
- Evidence: `crops/files-browser/ipad-tree-crop.png (crop of ipad-review-file-tree.png): the child Example.swift's name starts at about 514 pt and its parent Sources at about 518.5 pt; top-level files start 20 pt left of top-level folders`; `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.files-tree-light-393-default.png: the Example.swift and README.md names sit left of "Sources"`; `Desktop reference .build/design-reference/m4-files-tree-light-393x852.png aligns all names, with the chevron taking the icon column for folders` (+1 more)
- What happens: Any device: expand Sources. Its child Example.swift is drawn about 4 pt left of "Sources", and top-level files sit 20 pt left of top-level folders, so the nesting looks inverted. On iPhone at deeper levels, names truncate at the tail and lose their extension ("ComponentRegistryProv…"). At accessibility sizes the fixed 16 pt indent is a fraction of a glyph, so the levels blur together. VoiceOver reads a folder as "Sources, M, button": it doesn't say folder, gives no Expanded or Collapsed value, and reads the status letters M, A and D literally. The status letters are muted gray, while ReviewScreen colors A and D.
- Why it matters: Users misread the hierarchy, which is the tree's whole purpose. Screen-reader users can't tell folders from files or whether a folder is open.
- Fix:
  - Reserve the chevron slot on file rows, or follow the desktop and put the chevron in the icon column for folders.
  - Indent at least 20 pt per level, scaled with @ScaledMetric.
  - Use .truncationMode(.middle) for names.
  - Add .accessibilityLabel("\<name>, folder") and .accessibilityValue(expanded ? "Expanded" : "Collapsed"), as TimelineChrome.swift:54 does.
  - Spell out the status ("Modified", "Added", "Deleted") and color the letters as in ReviewScreen.swift:111.

<a id="f18-05"></a>

## F18-05: On iPhone, "Mention in composer" gives no feedback and adds duplicate mentions

*P2 bug · ux-flow · effort S · found by files-browser*

- Where: `FeatureFiles/FilesScreen.swift:131`, `FeatureFiles/FilesScreen.swift:170`, `OCSync/ComposerModel.swift:111-118`, `FeatureTranscript/SessionScreen.swift:80-83`
- Evidence: `FilesScreen.swift:170 'composer.mentionFile(path.absolute, focus: regularWidth)': regularWidth is false on iPhone`; `ComposerModel.swift:116 'next.append(token); next.append(AttributedString(" ")); setText(next)': no check for an existing mention`; `iphone/review-files.png: the full-height review sheet hides the composer`
- What happens: iPhone: in the Files sheet, tap "Mention in composer". Nothing visibly changes: the composer is behind the full-height review sheet, and there is no toast, haptic or dismissal. Tapping again because nothing seemed to happen adds a second "@Example.swift", which the user only finds after closing the sheet. The tree's long-press "Mention in composer" behaves the same.
- Why it matters: The viewer's most prominent action looks broken on iPhone, and repeated taps fill the prompt with duplicate mentions.
- Fix: On compact widths, close the review sheet and focus the composer after mentioning, or show a short confirmation ("Added @Example.swift", with Undo) and a success haptic. Skip the append, or show a "Mentioned" state, when the draft already mentions the same absolute path.

<a id="f18-10"></a>

## F18-10: Find in file: the field isn't focused on open, Return and Escape don't behave as expected, and a stale query overrides link targets

*P2 bug · interaction · effort M · found by files-browser*

- Where: `FeatureFiles/FilesScreen.swift:169`, `FeatureFiles/FilesScreen.swift:175-182`, `FeatureFiles/FilesScreen.swift:216-219`, `OCDesign/CodeCollection.swift:98-103`, `UITests/ReviewSmokeTests.swift:165-167`
- Evidence: `The only @FocusState is filterFocused, so the find field gets no focus; the UI test has to call 'find.tap()' before 'typeText'`; `FilesScreen.swift:218 'search = result; matchIndex = 0; nextMatch(0)' runs whenever the file text changes, and nextMatch sets model.selection to the first match`; `FilesScreen.swift:169 'finding.toggle()': ⌘F closes an open bar instead of refocusing it` (+2 more)
- What happens: iPad with a keyboard: ⌘F or the magnifier opens the bar, but typing goes nowhere until the field is tapped. Return moves to the next match once; SwiftUI's default then ends editing (inferred), so a second Return does nothing. Escape doesn't close the bar, and there is no ⇧Return or ⌘G. With the bar left open on "let", tapping a transcript link to Bar.swift:120 opens Bar.swift and then jumps to the first "let", discarding line 120. With Wrap lines off, a match past the right edge is never scrolled into view.
- Why it matters: Find takes extra steps on both devices, and a leftover query silently breaks the "open at a line from transcript links" requirement.
- Fix:
  - Focus the field when the bar opens, and make ⌘F refocus instead of toggling.
  - Refocus in onSubmit, close on .onKeyPress(.escape), and use Shift-Return for previous.
  - Turn off autocorrection and autocapitalization.
  - Jump to the first match only when the query changes, not when the content of a newly opened file loads with a link selection.
  - With wrapping off, set the horizontal offset to reveal the current match.
  - M6 plans only ⌘F as a menu command, not these fixes.
- Verifier's note: The link override happens only while FilesScreen stays mounted with the find bar open, for example in the iPad side panel. The find state is @State and resets whenever the tab or sheet is rebuilt.

<a id="f18-11"></a>

## F18-11: Fuzzy-find results truncate the file name before its folder and drop the "/" separator

*P2 bug · layout · effort S · found by files-browser*

- Where: `FeatureFiles/FilesScreen.swift:125-126`, `FeatureFiles/FilesScreen.swift:81-87`, `FeatureReview/ReviewScreen.swift:103-107`, `FeatureInbox/HomeView.swift:139`
- Evidence: `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.files-find-light-393-accessibility5.png: "Sources Example.s…" and "Tests ExampleTests…"`; `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.files-find-light-393-default.png and ipad/ipad-review-files.png: "Sources  Example.swift" and "src  example.ts", with a space instead of "/"`; `Desktop .build/design-reference/m4-file-view-light-1180x820.png shows "Sources/Example.swift" and a clear (×) button in the field` (+1 more)
- What happens: iPhone, filtering "button" in a monorepo: a row reads "packages/app/src/components/settings  Button.tsx" on one line, and the name, the part that matters, truncates. At AX5 even "Sources Example.swift" becomes "Sources Example.s…". The filter field capitalizes the first letter and may autocorrect on Return, which opens the top result. It has no clear button (Escape works only with a hardware keyboard), and the arrow-key highlight isn't scrolled into view.
- Why it matters: Users can't tell similarly named results apart and may open the wrong file.
- Fix:
  - Put the name first with .layoutPriority(1), and show the directory muted with a trailing "/" and .truncationMode(.head), or use ReviewScreen's two-line layout.
  - Add .textInputAutocapitalization(.never) and .autocorrectionDisabled(), as HomeView's search does.
  - Add a clear (×) button.
  - Keep the resultIndex row visible with a ScrollViewReader.
- Verifier's note: Correction: HomeView's search sets only autocorrectionDisabled(), so add both modifiers here.

<a id="f18-12"></a>

## F18-12: Files loses the user's place: the iPhone tree scrolls back to the top, tab switches snap to an old line, and the tree width resets

*P2 bug · state · effort M · found by files-browser*

- Where: `FeatureFiles/FilesScreen.swift:46-47`, `FeatureFiles/FilesScreen.swift:16`, `OCDesign/CodeCollection.swift:94`, `OCDesign/CodeCollection.swift:98-103`, `FeatureReview/ReviewScreen.swift:139` (+1 more)
- Evidence: `FilesScreen.swift:46 'if regular || model.selectedPath == nil { browser... }': on compact widths the browser's ScrollView is destroyed while a file is open and rebuilt at the top`; `FilesScreen.swift:16 '@State private var sidebarWidth: Double = 240' resets each time the view is rebuilt; Review keeps model.sidebarWidth and has a "Toggle file tree" button`; `CodeCollection.swift:94 restores the saved offset, then lines 98-103 scroll to the remembered selection (row − 4) whenever one exists`
- What happens: iPhone: expand packages/app/src/components, scroll about 60 rows, open Settings.tsx, then tap All files. The tree comes back at the top, and the same happens for every neighbouring file. Any device: open a file from a link (selection at line 2), scroll to line 400, switch tabs and come back; it snaps to line 2. iPad: drag the tree to 360 pt, switch to Changes and back, and it is 240 pt again. Unlike Review's tree, it can't be hidden to give the code the full width.
- Why it matters: Browsing a large repository on a phone means re-scrolling after every file, and viewer positions feel unreliable.
- Fix:
  - Keep the browser mounted on compact widths (hide it, or push the viewer in a NavigationStack), or restore it with .scrollPosition(id:) keyed by entry path and scroll to the open file.
  - In CodeCollection, scroll to a selection only when it is newly requested (link or find), not when a document is restored.
  - Move sidebarWidth and visibility into FilesModel and add Review's file-tree toggle.

<a id="f18-13"></a>

## F18-13: Status messages are dead ends or unclear: not-found and list errors lack Retry, and the large-file banner has no units

*P2 bug · copy · effort M · found by files-browser*

- Where: `FeatureFiles/FilesScreen.swift:93-99`, `FeatureFiles/FilesScreen.swift:108-116`, `FeatureFiles/FilesScreen.swift:184`, `FeatureFiles/FilesScreen.swift:200`, `OCModels/FileContent.swift:13-21` (+1 more)
- Evidence: `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.files-not-found-light-393-default.png: only a red "File not found: Example.swift"; the tab, Find and Mention stay`; `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.files-list-error-light-393-default.png: plain "Failed to list files" text with no button`; `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.files-large-file-light-393-default.png: "Showing the first 63 of 3,000,000"` (+1 more)
- What happens: (a) The agent deleted a file: the viewer shows one red line with no Retry or Close tab, and the 404 message drops the folder ("File not found: index.ts").
  (b) The root listing fails: plain text, with retry only through pull-to-refresh, which users won't discover. A subfolder failure does get a button labelled "Failed to list files".
  (c) Expanding a folder shows nothing while it loads or when it is empty.
  (d) A large text file shows "Showing the first 63 of 3,000,000" with no units. A minified file or source map over 2 MiB shows "Showing the first 0 of …" and an empty viewer, because only complete lines are shown (docs/m4-audit.md decision 10; this part revisits that decision). "Load more" adds 1 MiB per tap and there is no Load all.
- Why it matters: Users can't recover where they are, can't interpret the numbers, and large single-line files look broken.
- Fix:
  - For read errors, use OCEmptyState with Retry and Close tab, and show the relative path in the message.
  - Give root listing errors a Retry button.
  - Add "Loading…" and "Empty folder" placeholder rows.
  - Write "Showing 1 MB of 2.9 MB" with .byteCount and add Load all.
  - When a loaded chunk has no newline, show the truncated partial line with a notice.
- Raised from P3 to P2, the severity of F28-11, which describes the same problem.
- Also reported as: F28-11 by states-coverage, G13-M3 by verifier G13

<a id="f21-10"></a>

## F21-10: File trees hide folder vs file, expanded state and reviewed status from VoiceOver; status reads as the letters 'A', 'D', 'M'

*P2 bug · accessibility · effort S · found by a11y-voiceover*

- Where: `FeatureFiles/FilesScreen.swift:123`, `FeatureFiles/FilesScreen.swift:142`, `FeatureReview/ReviewScreen.swift:110`, `FeatureReview/ReviewScreen.swift:116`, `FeatureReview/ReviewScreen.swift:154`
- Evidence: `FilesScreen.swift:123-128: a folder row is OCIcon(chevron) + OCFileIcon(directory), both accessibilityHidden, plus the name and Text("A"/"D"/"M"). There is no expanded value or folder wording, and depth is only leading padding`; `ReviewScreen.swift:110: if model.isReviewed(file) { OCIcon("check") }, which is hidden. :111 Text("A"/"D"). :115 .accessibilityValue("Selected") instead of the selected trait. :116 folders are plain OCLabel text`; `ipad/ipad-review-file-tree.png ('.git', 'Sources M', 'src A')` (+1 more)
- What happens: iPad Files tab with VoiceOver. 'Sources, M, button' and 'Example.swift, M, button' sound the same. Nothing says Sources is a folder or whether it is open, so double-tapping it seems to do nothing audible. In Review's sidebar, files already marked reviewed carry only a hidden checkmark, so 'Example.swift, A, button' gives no reviewed state, and 'A'/'D'/'M' are spoken as single letters.
- Why it matters: Blind users can't understand or move through the project tree, and can't track review progress file by file.
- Fix: Give rows explicit semantics: 'Sources, folder' with the value 'Expanded'/'Collapsed' (or an accessibilityRepresentation as a DisclosureGroup). Speak 'Modified'/'Added'/'Deleted' instead of letters. Put 'Reviewed' in the value of reviewed files, use .isSelected for the current file, and expose nesting with the level in the value or with accessibilityChildren.

<a id="f18-06"></a>

## F18-06: A failed file search shows "No results found" on iPhone, or a red error over the open file on iPad

*P3 bug · functional · effort S · found by files-browser*

- Where: `OCSync/FilesModel.swift:87-97`, `FeatureFiles/FilesScreen.swift:99-103`, `FeatureFiles/FilesScreen.swift:184`
- Evidence: `FilesModel.swift:96 '} catch { if !Task.isCancelled { self?.error = "Could not search files." } }': writes the viewer's error, leaves 'results' stale, and nothing clears it after a later successful search`; `FilesScreen.swift:102 'if model.results.isEmpty { Text("No results found")... }'`; `FilesScreen.swift:184 'if let error = model.error { Text(error)...foregroundStyle(OCColor.danger) }': rendered only inside 'viewer'`
- What happens: The server is restarting or the connection drops, and the user types "router" into Filter files. On iPhone (tree visible, no file open), the list says "No results found" or keeps the previous query's results. On iPad with a file open, the tree says the same, while red "Could not search files." appears above the unrelated file's code and stays until another file is opened.
- Why it matters: Users conclude the file doesn't exist, and on iPad the error is attached to the wrong surface.
- Fix: Add a searchError to FilesModel. Clear it and results when each search starts, show it in the browser instead of "No results found" with a Retry button, and keep `error` for the viewer only.
- Verifier's note: Also add an in-progress state. When the first character is typed, results is empty, so 'No results found' shows for the whole 120 ms debounce and network round trip. On a slow tunnel that flash looks the same as a failed search.

<a id="f27-05"></a>

## F27-05: Files image viewer decodes the full-resolution image on the main thread and creates a new UIImage on every body pass

*P3 bug · performance · effort S · found by ui-performance*

- Where: `FeatureFiles/FilesScreen.swift:203-205`, `FeatureFiles/FilesScreen.swift:235-255`, `OCDesign/CodeEditorCell.swift:52`, `OCDesign/CodeCollection.swift:70-87`
- Evidence: `FilesScreen.swift:204 'if let image = UIImage(data: content.data), content.complete { ZoomImage(image: image) }': a new UIImage each time 'viewer' is evaluated, created even before the 'content.complete' check`; `FilesScreen.swift:246-247 'Image(uiImage: image).resizable().frame(width: image.size.width * fit * zoom, ...)' displays the original bitmap, and nothing downsamples it`; `ARCHITECTURE.md:453 says 'Images are downsampled with ImageIO'; OCAttachmentChip (ComposerChrome.swift:100-105) already uses CGImageSourceCreateThumbnailAtIndex off the main actor`
- What happens: Open a 12-megapixel photo in Files on iPad (regular width, browser beside the viewer). Each of these re-evaluates FilesScreen.body: a keystroke in Filter files, toggling Find or typing in it, or a change to loading or error. Each pass builds a new UIImage, which forces another full-size decode (about 48 MB RGBA) when Core Animation commits on the main thread.
- Why it matters: Typing lags and the viewer hitches while an image is open. Large images cause big memory spikes (images of 20 megapixels or more decode to 80-200 MB), which risks a jetsam kill on iPhone.
- Fix: Decode once, off the main actor, with CGImageSourceCreateThumbnailAtIndex at the viewport size times the screen scale; decode at a higher resolution only when zoomed. Keep the result in FilesModel or @State keyed by path and etag. Check content.complete before decoding.
- Verifier's note: Apply the same ImageIO thumbnail decode, already used by OCAttachmentChip in ComposerChrome.swift:100-105, to CodeImageCell (a 280-pt cell).

<a id="g13-m2"></a>

## G13-M2: Files search results put the directory before the file name on one line, so at accessibility sizes the name loses its extension ('Sources Example.s…')

*P3 bug · layout · effort S · found by verifier G13*

- Where: `FeatureFiles/FilesScreen.swift:122-128`
- Evidence: `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.files-find-light-393-accessibility5.png: the results read 'Sources Example.s…' and 'Tests ExampleTests…'. The -default image shows the full names.`; `FilesScreen.swift:125-126: the directory Text and the name Text are both lineLimit(1) with equal priority in one HStack. The directory has no trailing '/', so the two read as separate words.`
- What happens: iPhone at AX5, or iPad at an accessibility size (which forces the compact Files layout): type 'Example' into Filter files. Each result shows the muted directory first at its full width, and the file name is tail-truncated. With real directory depths (for example 'FeatureFiles'), the name is cut even at the default size, and results that share a prefix can't be told apart.
- Why it matters: Search is the main way to open a file, and large-text users can't tell which result is the file they want.
- Fix: Show the name first with layoutPriority(1) and middle truncation. Put the directory on a muted second line at accessibility sizes, as ReviewScreen's file sidebar already does (ReviewScreen.swift:103-107), or at least give the name priority and add a '/' separator.

<a id="f18-09"></a>

## F18-09: The viewer never shows the file's path, and Copy path and Share are unreachable while viewing

*P2 improvement · navigation · effort M · found by files-browser*

- Where: `FeatureFiles/FilesScreen.swift:39`, `FeatureFiles/FilesScreen.swift:131-133`, `FeatureFiles/FilesScreen.swift:167-174`, `FeatureFiles/FilesScreen.swift:73`, `FeatureFiles/FilesScreen.swift:223-233` (+2 more)
- Evidence: `iphone/review-file-link.png: only the tab label "Example.swift" identifies the file`; `The tab label is '(path.path as NSString).lastPathComponent', and "Copy path" exists only in the tree row's contextMenu (FilesScreen.swift:132)`; `QuickLookView returns a bare 'QLPreviewController()' with no UINavigationController around it (FilesScreen.swift:226)` (+2 more)
- What happens: iPhone: open packages/app/src/index.ts and packages/server/src/index.ts. You get two identical "index.ts" tabs, and the viewer shows no path. The tree, which has Copy path, is hidden while a file is open, so copying the path means tapping All files, finding the row and long-pressing it. No file has Share or Open in…. Quick Look (PDF, Office docs) is embedded without a navigation controller, so its title, Done and Share controls most likely don't appear (inferred; I couldn't run it). Its preview is named content.pdf.
- Why it matters: Users can't confirm which file they're reading, tell duplicate names apart in monorepos, or export a file to another app.
- Fix:
  - Add a compact path row under the tabs: the middle-truncated relative path, like ReviewScreen's header, with a menu for Copy path, Copy relative path, Reveal in tree and Share (a ShareLink to the cached file).
  - Disambiguate duplicate tab names with the parent folder ("index.ts · app").
  - Present Quick Look with SwiftUI's .quickLookPreview($url), or wrap QLPreviewController in a UINavigationController.
  - Write the local copy under the real file name, or set previewItemTitle.

<a id="g09-m2"></a>

## G09-M2: Wrap lines can't be changed from the Files viewer or the iPhone review, only from Settings

*P3 improvement · ux-flow · effort S · found by verifier G09*

- Where: `FeatureFiles/FilesScreen.swift:13`, `FeatureFiles/FilesScreen.swift:167-174`, `FeatureReview/ReviewScreen.swift:186-189`, `FeatureReview/ReviewScreen.swift:144`, `FeatureServers/ServerSettingsView.swift:31`
- Evidence: `A grep for 'Wrap lines' finds only three places: Settings (ServerSettingsView.swift:31), the regular-width Review toolbar menu (ReviewScreen.swift:144) and a tool card's full-diff sheet (DiffCardView.swift:89).`; `FilesScreen.swift:13 reads @AppStorage("wrapLines"), but its toolbar (lines 167-174) holds only Find, Mention in composer, Source/Preview and Cancel.`; `ReviewScreen.swift:186-189: the compact 'Review options' menu holds only 'Show all lines' and the per-file Reviewed marks.` (+1 more)
- What happens: On iPhone, reading a source file in Files or a diff in the review sheet. Wrapping is on by default, so long lines break about every 40 characters, often mid-word. To turn wrapping off, the user has to close the review sheet, leave the session and find 'Wrap lines' under Settings > App. The iPad Files viewer has no control either.
- Why it matters: Reading code is the main job of these screens, and the setting that most affects readability isn't available there. docs/m4-audit.md decision 16 notes that the desktop exposes this preference in its mobile layout.
- Fix: Add a Wrap lines toggle to the Files viewer toolbar, either as an icon button or in a More menu together with Source/Preview and Copy path. Add the same toggle to the compact 'Review options' menu. At accessibility sizes, where wrapping is forced, show the toggle disabled with a short note.

<a id="g15-m2"></a>

## G15-M2: The Files text viewer re-decodes the whole file into new Strings on every render, then compares and hashes them on the main thread

*P3 improvement · performance · effort S · found by verifier G15*

- Where: `OCModels/FileContent.swift:13-21`, `FeatureFiles/FilesScreen.swift:211`, `FeatureFiles/FilesScreen.swift:216-217`, `OCDesign/DiffView.swift:75`, `OCDesign/DiffView.swift:83`
- Evidence: `FileContent.swift:13-21: 'text' is a computed property that copies 'data' and runs String(decoding: bytes, as: UTF8.self) on every read`; `FilesScreen.swift:211 passes 'text: content.text' to OCDiffView, and :216 builds '.task(id: SearchRequest(query: finding ? find : "", text: model.content?.text ?? ""))'. Every body pass therefore decodes the open file twice, even with Find closed and even for image files, whose bytes get decoded as UTF-8 with replacement characters`; `SwiftUI compares each new SearchRequest, and DiffView's PreparationKey (DiffView.swift:83, whose inputs carry the text), with the previous value. Freshly decoded strings never share storage, so each comparison walks the whole text` (+3 more)
- What happens: Open a 2 MB log in Files and search it with Find. Before any search work, each keystroke decodes the log twice, compares it twice and FNV-hashes it once on the main thread: a few milliseconds at 2 MB, and proportionally more after Load more. CodeCollection then reconfigures every visible cell (F27-11). On iPad, with a large image open, each filter keystroke also decodes the image bytes as text.
- Why it matters: Typing in Find and in the iPad file filter lags on large files, and the cost grows with file size.
- Fix: Decode once when the content changes: keep the decoded text in FilesModel, or cache it lazily in FileContent, and pass that same String instance everywhere. Key the search task and the DiffView preparation on path + etag + data.count (or a revision counter) instead of the full text, and compute the measurement hash once, off the main actor. Skip text decoding for image, Quick Look and binary files.

<a id="f18-14"></a>

## F18-14: Image viewer pinch-zoom grows from the top-left corner, with no double-tap or zoom-to-point

*P3 improvement · interaction · effort M · found by files-browser*

- Where: `FeatureFiles/FilesScreen.swift:235-255`
- Evidence: `FilesScreen.swift:247-250: '.frame(width: image.size.width * fit * zoom, ...)' inside 'ScrollView([.horizontal, .vertical])' with 'MagnifyGesture().updating($pinch)'; the content offset is never adjusted and there is no double-tap gesture`; `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.files-image-light-393-default.png and capture-_-name.files-image-dark-393-default.png: a full-width "Fit" row above a small centered image`
- What happens: iPhone: open a screenshot PNG and pinch on a button in the middle. The content grows from its origin while the scroll offset stays put, so the view drifts to the top-left and the user has to pan to find the spot. Double-tap does nothing. "Fit" always takes a 44-point row, even when the image is already fitted. A transparent PNG with dark glyphs disappears on the dark background, and no dimensions or file size are shown.
- Why it matters: Inspecting UI screenshots and assets, common when the agent works on UI, is clumsy.
- Fix: Host the image in a UIScrollView (viewForZooming) for native pinch-at-point, bounce and double-tap-to-zoom at the tap location. Show Fit only when zoomed, add a checkerboard or neutral backdrop for transparency, and add a caption such as "1179 × 2556 · 412 KB".
