# UI review: Design system

Part of the [UI review](README.md). 14 bugs and 11 improvements, bugs first, then by severity. Paths under `Packages/OpencodeKit/Sources` are written without that prefix.

| ID | Severity | Finding |
| --- | --- | --- |
| [F20-01](#f20-01) | P2 bug | In light mode layer1 equals backgroundDeep, so tab selection and header bands disappear |
| [F20-02](#f20-02) | P2 bug | Two referenced icon names don't exist in Icons.xcassets, so controls render as blank |
| [F20-07](#f20-07) | P2 bug | Icons, switches and status dots use fixed point sizes and don't scale with Dynamic Type |
| [F20-10](#f20-10) | P2 bug | Errors are shown ad hoc in about 20 places; the shared banner shows an info glyph for warnings and errors, and nothing is announced |
| [F23-01](#f23-01) | P2 bug | Warning-tone text and icons are 2.35–2.46:1 in light mode (risk badge, pairing and server warnings); success badges are 3.97:1 |
| [F23-04](#f23-04) | P2 bug | Generic folder icon (and 9 other currentColor file icons) renders pure black in dark mode, 1.16:1 |
| [F23-03](#f23-03) | P2 bug | Dark mode: the global OCColor.text tint makes switches white-on-white and swipe actions white text on pale fills (1.88–2.73:1) |
| [F20-09](#f20-09) | P3 bug | Primary (contrast) buttons show no pressed state in light mode, and the hover and focus tokens are never used |
| [F23-06](#f23-06) | P3 bug | Placeholders use three different colours; the system placeholder is 1.72:1 and the Home search field fill is 1.04:1 |
| [F23-10](#f23-10) | P3 bug | Dark-mode @ and / suggestion list is the page colour with no border, so its edge disappears |
| [F23-11](#f23-11) | P3 bug | In dark mode, markdown links differ from body text by only 1.80:1 and have no underline |
| [F23-14](#f23-14) | P3 bug | Find in file: other matches are 1.22:1 against the page, and the current match differs only in intensity |
| [G17-M1](#g17-m1) | P3 bug | Two different switch designs, and the OC switch behind the iPad 'Reviewed' control has a 1.38:1 off state |
| [F23-13](#f23-13) | P3 bug | Smart Invert will invert attached photos and image previews |
| [F20-13](#f20-13) | P3 improvement | Type tokens scale on mismatched Dynamic Type curves, and diff code uses its own stepped size |
| [F20-14](#f20-14) | P3 improvement | Feature code bypasses OCDesign: system-font titles, four search-field styles, raw spinners and unused components |
| [F23-07](#f23-07) | P3 improvement | textFaint (#808080 in both appearances) fails 4.5:1 for Home paths and costs, line numbers and comment metadata |
| [F23-08](#f23-08) | P3 improvement | No Increase Contrast support: none of the 67 colour sets has a high-contrast variant |
| [F23-12](#f23-12) | P3 improvement | Syntax and mention colours fall below 4.5:1: dark punctuation and operators 3.65–3.77:1, light property names and file mentions 3.62–3.77:1, sent '@' 2.42:1 |
| [F24-12](#f24-12) | P3 improvement | Panels, the approval dock and the Jump pill appear and disappear with hard cuts, and most motion tokens are unused |
| [F25-06](#f25-06) | P3 improvement | UI text can’t be localized as built: OCDesign takes String titles, ~140 English strings live in model layers, and the package has no localization bundle |
| [F25-12](#f25-12) | P3 improvement | Directional icons and arrow-key navigation won’t mirror in RTL localizations |
| [F30-06](#f30-06) | P3 improvement | Ghost buttons and menus look like plain text and sit 12pt in from the content edge |
| [F38-14](#f38-14) | P3 improvement | iPad onboarding sits in the top-left of a 640-pt column, leaving most of the screen empty |
| [F31-14](#f31-14) | P3 improvement | No pointer hover feedback on any custom control on iPad |

<a id="f20-01"></a>

## F20-01: In light mode layer1 equals backgroundDeep, so tab selection and header bands disappear

*P2 bug · state · effort M · found by design-system*

- Where: `OCDesign/WorkspaceShell.swift:87`, `OCDesign/WorkspaceShell.swift:89`, `OCDesign/Controls.swift:102`, `OCDesign/Controls.swift:106`, `FeatureFiles/FilesScreen.swift:36` (+6 more)
- Evidence: `Colors.xcassets light: layer1 #fafafa == backgroundDeep #fafafa; layer1 vs background #ffffff is 1.04:1 (dark #242424 vs #080808/#161616 is clearly distinct)`; `ipad/ipad-review-changes.png and ipad-review-files.png: every pixel of the project-tab row samples #fafafa, no tab reads as selected`; `crops/design-system/crops/ipad-seg.png and iphone-seg.png: selected 'Files Changed 7' is a #ffffff chip on a #fafafa track and merges into the white panel; label weight and colour unchanged` (+3 more)
- What happens: iPad, light mode, several projects open. The tab row ('project', 'composer-worktree-project', 'review-project', …) shows no highlight on the current project. In the review panel (iPad side panel or iPhone Review sheet), the selected tab among Files Changed / Files / Terminal / Context is a white chip on an almost-white track. In Files, 'All files' and the open file's tab look identical. Transcript code blocks lose their header band in light mode only.
- Why it matters: Users can't tell which project, panel tab or file is active, which is the main orientation cue in the iPad layout and the review panel. VoiceOver also gets no selected trait for file tabs, or for project tabs when selection is nil (the first tab is drawn selected without the trait). The review tabs also never stack at accessibility sizes, although docs/design.md says segmented options do, because WorkspacePanel passes equalWidth: false.
- Fix: Stop using layer1 to mark selection or raised bands on base or deep backgrounds. Add a selected-surface token that matches the reference (layer2 #f2f2f2 / dark #2e2e2e, or the #e6e6e6 tab fill). Build one OCTab component, with a filled pill, a medium-weight label and .isSelected, and use it for project tabs, review panel tabs and file tabs. Give code-block headers layer2 in light mode. Let review tabs stack at accessibility sizes. Add selected and unselected cases to DesignScreenTests.components.
- Verifier's note: Three more cases share this root cause and should be fixed with it. (1) The pinned diff file headers: CodeHeader sets backgroundColor to layer1 (CodeCell.swift:167) on a backgroundDeep collection (CodeCollection.swift:34). In light mode the sticky 44/88pt header is the same #fafafa as the code scrolling under it; ReviewSnapshots changes-working-light-393-default.png shows header rows y=270-570 matching the context rows. (2) From F23-05: HomeSessionRow has no selected state, so the open session isn't marked in the iPad sidebar (ipad-transcript-live.png). OCListRow already has a selected surface (OCColor.pressed, about #ebebeb, matching upstream) that could be reused. (3) OCProjectTabs draws the first project as selected when selection is nil, but nil is Home's 'All projects' filter (ServerRootView.swift:28/50, HomeView.swift:53). This already shows in dark: design-compare/ipad-shell-dark.png has the tab filled while Home reads 'All projects'. Once the selection is visible in light, nil must draw no selection (or get an explicit 'All projects' tab).
- Also reported as: F19-04 by ipad-shell, F23-05 by contrast-dark-mode, F31-02 by visual-polish-ipad, F31-04 by visual-polish-ipad, F32-04 by design-parity, F33-07 by ux-flows-ia

<a id="f20-02"></a>

## F20-02: Two referenced icon names don't exist in Icons.xcassets, so controls render as blank

*P2 bug · functional · effort S · found by design-system*

- Where: `OCDesign/CodeCell.swift:23`, `OCDesign/CodeCell.swift:103`, `OCDesign/LineCommentEditor.swift:55`, `FeatureFiles/FilesScreen.swift:179`, `OCDesign/Icon.swift:16`
- Evidence: `CodeCell.swift:23 'more.setImage(UIImage(named: "ellipsis", in: .module, compatibleWith: nil), for: .normal)' and LineCommentEditor.swift:55 'OCIcon("ellipsis")': there is no ellipsis.imageset (the three-dot glyphs are 'dot-grid', used by SessionActions, and 'outline-dots')`; `FilesScreen.swift:179 'OCIconButton("Previous match", icon: "chevron-up")': there is no chevron-up.imageset (only chevron-down/left/right)`; `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.comment-card-light-393-default.png: card built with edit and delete shows no menu glyph (zero ink in the header's right side)` (+2 more)
- What happens: In review, long-press lines and add a comment. The card drawn inside the diff has a 44pt More options button (Edit, Delete) with no image, so its corner is blank; tapping the blank area opens the menu. In the file viewer, open Find: the bar shows '0/0', an empty 44pt gap, a down chevron and close. Previous match is invisible.
- Why it matters: Sighted users can't discover how to edit or delete a draft line comment from the diff, or how to step back through find results. The snapshot baselines recorded the blank state, so the tests pass.
- Fix: Use existing assets: `dot-grid` for More options (matching the session menu). For Previous match, import `chevron-up` from the upstream catalog or rotate `chevron-down`. Add a unit test that resolves every icon literal referenced in Sources through OCIcon.isBundled and UIImage(named:in:). Make OCIcon assert in DEBUG when an asset is missing.
- Verifier's note: Use dot-grid, as SessionActions.swift:36 does, in CodeCell.swift:23 and LineCommentEditor.swift:55. For Previous match, add an up-chevron asset or rotate chevron-down by 180°.
- Also reported as: F17-04 by review-comments, F24-04 by touch-gestures-motion, F36-01 by sweep-review-snapshots

<a id="f20-07"></a>

## F20-07: Icons, switches and status dots use fixed point sizes and don't scale with Dynamic Type

*P2 bug · accessibility · effort M · found by design-system*

- Where: `OCDesign/Icon.swift:11`, `OCDesign/Icon.swift:17`, `OCDesign/FileIcon.swift:34`, `OCDesign/Controls.swift:119`, `OCDesign/Rows.swift:19` (+1 more)
- Evidence: `Icon.swift:16-17 '.frame(width: size, height: size)' with a fixed 'size: CGFloat = 16'; Controls.swift:119 '.frame(width: 24, height: 16)'; no icon in Sources uses @ScaledMetric (only OCProjectAvatar and LineCommentEditor do)`; `Packages/OpencodeKit/Tests/FeatureServersTests/__Snapshots__/ServerRowTests/allStatesAtLargestDynamicType.repair-light-402.png: the lock icon is 40px tall beside 85px cap-height text; the status dot stays 6pt`; `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.changes-no-git-light-393-accessibility5.png and tool-diff-light-393-accessibility5.png: 16pt glyphs and 12pt chevrons beside large titles` (+2 more)
- What happens: Set Larger Text to the maximum and open Home, the server list, a question form or the review panel. Text grows about threefold, while every icon, chevron, status dot and OC switch stays between 6 and 24pt.
- Why it matters: Status cues (the needs-you triangle, failed circle, unread dot, lock) plus disclosure chevrons and switches become hard to see, for exactly the users who enlarge text. The balance between glyph and label breaks down.
- Fix: Size OCIcon and OCFileIcon relative to a text style, either with @ScaledMetric(relativeTo:) and a cap or with a size enum mapped to text styles. Scale OCToggleStyle's track and thumb, OCStatusDot and the indicator dot the same way. Keep the existing 44pt hit targets.
- Also reported as: F22-04 by a11y-dynamic-type, F35-08 by sweep-read-snapshots, F36-09 by sweep-review-snapshots, F38-11 by sweep-approval-server-snapshots

<a id="f20-10"></a>

## F20-10: Errors are shown ad hoc in about 20 places; the shared banner shows an info glyph for warnings and errors, and nothing is announced

*P2 bug · accessibility · effort M · found by design-system*

- Where: `OCDesign/Feedback.swift:25`, `OCDesign/Feedback.swift:37`, `FeatureApprovals/PermissionSheet.swift:58`, `FeatureApprovals/QuestionSheet.swift:43`, `FeatureComposer/ComposerDock.swift:160` (+5 more)
- Evidence: `Feedback.swift:25 'OCIcon(tone == .success ? "check" : "info")': warning and danger banners get the info glyph although 'warning' and 'circle-x' are bundled (TimelineChrome.swift:81-82); visible on 'Needs re-pairing' in iphone/re-pair.png and in components.light.png`; `OCBanner is used only in AddServerView. Everywhere else an error is 'Text(error).font(OCType.small).foregroundStyle(OCColor.danger)' with padding .sm, .md, the default or none (also PendingInputPanel.swift:30, NewSessionView.swift:47,179, SavedPromptReview.swift:30,36, ToolRowView.swift:29,61, SessionTimeline.swift:33, ServerDetailView.swift:41)`; `No AccessibilityNotification or UIAccessibility.post anywhere in Packages/OpencodeKit/Sources or App; OCToast only adds '.updatesFrequently', and the registry error toast is an untoned card`
- What happens: An 'Allow once' reply fails ('Reply could not be sent. Try again.'), a send fails, or Home can't refresh. A small red line without an icon appears wherever that screen placed it, and VoiceOver users hear nothing. On the re-pair sheet, the warning banner shows an 'i' glyph.
- Why it matters: Failures in approvals and sending are easy to miss. Colour is the only signal, which fails colour-blind users, VoiceOver gets no status message (WCAG 4.1.3), and each screen presents errors differently.
- Fix: Create a single OCInlineMessage/OCBanner with an icon per tone (warning → warning, danger → circle-x, success → check, info → info), consistent padding and an 'Error:' accessibility prefix. Post AccessibilityNotification.Announcement when it appears. Use it at all of these call sites and give OCToast a tone.

<a id="f23-01"></a>

## F23-01: Warning-tone text and icons are 2.35–2.46:1 in light mode (risk badge, pairing and server warnings); success badges are 3.97:1

*P2 bug · accessibility · effort M · found by contrast-dark-mode*

- Where: `OCDesign/Rows.swift:7-10`, `OCDesign/Rows.swift:19`, `FeatureApprovals/PermissionSheet.swift:34`, `FeatureApprovals/PermissionSheet.swift:54`, `FeatureApprovals/QuestionSheet.swift:41` (+9 more)
- Evidence: `Tokens: oc2-warning light #CB9F34; oc2-warningBackground light #FEFAEC; oc2-success light #198B43; oc2-successBackground light #E7F9EA. Rows.swift:9 'case .warning: OCColor.warning'`; `iphone/permission-sheet.png: 'Elevated risk' badge is #CB9F34 on #FEFAEC = 2.35:1 at 11pt (crop: crops/contrast-dark-mode/perm-badge.png). 'Low risk' uses the same tone (PermissionSheet.swift:34)`; `Packages/OpencodeKit/Tests/FeatureServersTests/__Snapshots__/ServerRowTests/allStatesAtLargestDynamicType.repair-light-402.png: 'Needs re-pairing' pill 2.35:1; 'Pairing expires soon' #CB9F34 on #FFFFFF = 2.46:1` (+4 more)
- What happens: Light mode, any text size.
  - Opening a permission request shows the 'Elevated risk' or 'Low risk' badge as mustard 11pt text on cream.
  - In Settings, a server that needs re-pairing shows a mustard 'Needs re-pairing' pill and 'Pairing expires soon' line.
  - The re-pair screen shows a mustard banner and a token-expiry sentence.
  - Attaching a PDF for a model without PDF input shows the warning in mustard on white.
  - Home rows waiting on the user show a faint mustard triangle.
  - Success pills ('Connected · LAN', 'Already handled') are green on mint at 3.97:1.
- Why it matters: The risk tier and the connection and pairing warnings are exactly what users must notice before approving an action or fixing a broken server. At 2.35:1 they fail WCAG 1.4.3 even for large text, and the dots and triangle fail the 3:1 minimum for non-text elements. Low-vision users, and anyone reading outdoors, will miss them.
- Fix: Add text-strength colour sets and use them for OCTone.foreground and the direct uses:
  - warningText: light #805711 (upstream's syntax-warning / icon-warning-active value; 6.11:1 on #FEFAEC, 6.38:1 on white), dark #F2CF76.
  - successText: light #1D783C (the existing diffAddNumber value; 5.03:1 on #E7F9EA, 5.52:1 on white), dark #6BD586.

  Apply warningText to OCStatusDot and the Home needs-you triangle as well. Keep #CB9F34 and #198B43 for fills and borders only. Re-record the light Approval, Server and Composer snapshots.
- Also reported as: F09-08 by composer-dock, F13-04 by approvals-permission, F20-03 by design-system, F30-09 by visual-polish-iphone, F37-05 by sweep-composer-snapshots, F38-01 by sweep-approval-server-snapshots

<a id="f23-04"></a>

## F23-04: Generic folder icon (and 9 other currentColor file icons) renders pure black in dark mode, 1.16:1

*P2 bug · visual · effort S · found by contrast-dark-mode*

- Where: `OCDesign/FileIcon.swift:33-34`, `OCDesign/Resources/Icons.xcassets/filetype-Folder.imageset/icon.svg:1`, `FeatureFiles/FilesScreen.swift:124`, `FeatureComposer/ComposerDock.swift:255`
- Evidence: `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.files-tree-dark-820-default.png: the 'Sources' folder glyph is #000000 on #161616 = 1.16:1. Crops: crops/contrast-dark-mode/files-tree-dark.png vs crops/contrast-dark-mode/files-tree-light.png`; `filetype-Folder icon.svg contains 'fill="currentColor"'. So do FolderCircleci, FolderGithub, FolderMacos, FolderGhWorkflows, FolderIntellij, FolderScripts, FolderTarget, FolderVercel and Vlang`; `FileIcon.swift:33 '.renderingMode(monochrome ? .template : .original)': with original rendering, currentColor resolves to black` (+1 more)
- What happens: Dark mode. In Files (the review panel's Files tab or the file viewer), or after typing @ and matching a directory:
  - Every directory without a special mapping (Sources, workspace, most project folders) shows a black folder that is effectively invisible.
  - .github, scripts and target folders show a black body with a light emblem.
  - .v files show a half-black logo.
- Why it matters: In dark mode, directories lose their icon in a core review flow. The rows look broken, and only the chevron is left to tell them apart from files.
- Fix: Render icons whose SVG uses currentColor with `.renderingMode(.template)` and `.foregroundStyle(OCColor.iconMuted)` (#808080: 3.95:1 on white, 4.58:1 on #161616). Alternatively, replace currentColor in those 10 SVGs with an explicit neutral such as #78909C (3.35:1 and 5.40:1). Add a unit test that no bundled filetype SVG contains currentColor.
- Also reported as: F18-03 by files-browser, F32-09 by design-parity, F36-05 by sweep-review-snapshots

<a id="f23-03"></a>

## F23-03: Dark mode: the global OCColor.text tint makes switches white-on-white and swipe actions white text on pale fills (1.88–2.73:1)

*P2 bug · accessibility · effort S · found by contrast-dark-mode*

- Where: `OCDesign/Surfaces.swift:50`, `FeatureServers/ServerSettingsView.swift:31-34`, `FeatureComposer/ModelPicker.swift:21`, `FeatureInbox/HomeView.swift:157-163`
- Evidence: `Surfaces.swift:50: ThemeModifier applies '.tint(OCColor.text)', and OCColor.text is #FAFAFA in dark`; `Packages/OpencodeKit/Tests/FeatureServersTests/__Snapshots__/DesignScreenTests/screens.server-management-dark-393x852.png: the 'Wrap lines' and 'Changed files' ON tracks render #FAFAFA (crop: crops/contrast-dark-mode/toggle-wrap-on.png). The system thumb is #FFFFFF, giving 1.04:1 between thumb and track`; `iphone/server-list.png (light): ON track #161616 with a #FFFFFF thumb, which works only in light (crops/contrast-dark-mode/app-toggle-light.png)` (+1 more)
- What happens: Dark mode. In Settings > App, the 'Wrap lines' and 'Changed files' switches, which are on, show as solid white capsules with no visible knob; 'Show all models' in the model picker does the same. On Home, swiping a session row shows 'Mark read', 'Pin' and 'Hide' with white titles on pale blue and grey fills.
- Why it matters: The on/off state relies on track colour alone, and the knob-position cue disappears. Swipe-action labels fail 4.5:1 badly (1.88:1 for Mark read). The root cause is foreground tokens, which turn light in dark mode, being used as fills.
- Fix:
  - Give native Toggles a fill tint that stays saturated in both appearances, e.g. `.tint(OCColor.accentBackground)` (#3B5CF6; the white thumb is 5.19:1 against it), which also matches OCToggleStyle's on colour.
  - Swipe actions: use accentBackground for Mark read and OCColor.contrast for Hide (white is 6.7–15.5:1 on it). For Pin, add a fill that stays #3250DF in both appearances (6.27:1 with white).
  - Stop relying on the global `.tint(OCColor.text)` for these controls.
- Also reported as: F20-12 by design-system

<a id="f20-09"></a>

## F20-09: Primary (contrast) buttons show no pressed state in light mode, and the hover and focus tokens are never used

*P3 bug · interaction · effort S · found by design-system*

- Where: `OCDesign/Controls.swift:18`, `OCDesign/Controls.swift:20`, `OCDesign/Controls.swift:21`, `OCDesign/Controls.swift:46`, `OCDesign/LineCommentEditor.swift:30` (+1 more)
- Evidence: `Controls.swift:18 overlays OCColor.pressed (black at 8% in light mode) on every variant; on the contrast fill #242424 that gives #212121, a 1.04:1 change`; `Reference .build/design-reference/computed-tokens-light.json: 'v2-overlay-simple-overlay-contrast-pressed' #ffffff3d and '-contrast-hover' #ffffff1f exist upstream for exactly this case and are not ported`; `OCColor.hover is used only for keyboard-highlighted suggestions (ComposerDock.swift:241); OCColor.focus only as an always-on border (LineCommentEditor.swift:30); there is no '.hoverEffect' anywhere in Sources; the button contentShape is a square Rectangle (Controls.swift:21)` (+1 more)
- What happens: Light mode. Tap 'Allow once' in the approval dock, 'Submit answers', 'Connect' or 'Comment': nothing visibly changes while the finger is down. With a trackpad on iPad, or on Mac as 'Designed for iPad', ghost and neutral buttons and segmented options get no OC-2 hover fill, and text fields show no focus ring.
- Why it matters: The app's most consequential buttons give no press feedback, so taps feel unregistered and invite double taps on approvals. Pointer and keyboard users get no hover or focus cues.
- Fix: Give OCButtonStyle a per-variant pressed overlay (contrast: white 24% in light, black 40% in dark, per the reference tokens). Add .hoverEffect(.highlight) with .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: OCRadius.md)). Use OCColor.focus for the border of a focused OCTextFieldStyle field. Add pressed and disabled cases to the components snapshot.

<a id="f23-06"></a>

## F23-06: Placeholders use three different colours; the system placeholder is 1.72:1 and the Home search field fill is 1.04:1

*P3 bug · accessibility · effort M · found by contrast-dark-mode*

- Where: `FeatureInbox/HomeView.swift:137-141`, `FeatureReview/ReviewScreen.swift:95`, `FeatureFiles/FilesScreen.swift:81`, `FeatureFiles/FilesScreen.swift:177`, `FeatureServers/AddServerView.swift:54` (+9 more)
- Evidence: `iphone/add-server-password.png: the 'Studio Mac' and 'Password' placeholders are #C5C5C7 on #FFFFFF = 1.72:1, but 'http://192.168.1.2:4096' is #808080 = 3.95:1 and looks pre-filled (crops/contrast-dark-mode/asp-small.png)`; `iphone/home.png: 'Search sessions' is #C1C1C3 on #FAFAFA = 1.72:1. The field fill #FAFAFA sits on the #FFFFFF list row (1.04:1) with no border (crops/contrast-dark-mode/home-search.png)`; `ipad/ipad-review-changes.png: 'Filter files' is #C5C5C7 on #FFFFFF = 1.72:1, with no icon or outline (crops/contrast-dark-mode/ipad-filter.png)` (+2 more)
- What happens: Light mode:
  - Home: the search field is an almost invisible off-white strip with pale 'Search sessions' text.
  - Add server (password method): the Name and Password hints are pale grey, but the Server URL hint is mid-grey, so the URL looks already filled in.
  - Review: 'Filter files' is a line of pale text with nothing marking it as a field.
  - The permission 'Tell the agent what to do instead', question answer and session-title fields show the same pale placeholder.
- Why it matters: Users can miss the search and filter fields entirely, and may skip Server URL because it looks filled. Placeholders that act as the field's only label fail 4.5:1. The inconsistency makes the design system feel unfinished.
- Fix: Use one placeholder colour everywhere: pass `prompt: Text(…).foregroundStyle(OCColor.textMuted)` (6.4–6.7:1) to every TextField and SecureField, ideally through a small OC helper, and switch AddServerView and LineCommentEditor from textFaint to textMuted. Give the inline search and filter fields a visible container: a layer2 fill (#F2F2F2) plus an OCColor.borderStrong hairline, or the native `.searchable` field.

<a id="f23-10"></a>

## F23-10: Dark-mode @ and / suggestion list is the page colour with no border, so its edge disappears

*P3 bug · visual · effort S · found by contrast-dark-mode*

- Where: `FeatureComposer/ComposerDock.swift:245-246`, `OCDesign/Metrics.swift:60-67`, `FeatureTranscript/SessionScreen.swift:78`
- Evidence: `ComposerDock.swift:246 '.background(OCColor.background, in: RoundedRectangle(cornerRadius: OCRadius.dock)).ocElevation(.floating)', with no strokeBorder`; `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-commands-dark-393-default.png: the list fill (#161616) equals the page (#161616), 1.00:1; only a 30% black shadow marks the edge (crops/contrast-dark-mode/suggest-dark.png)`; `Upstream: .build/design-reference/composer-commands-dark-393x852.png draws a 1px #2E2E2E ring around the list` (+1 more)
- What happens: Dark mode, in a session with transcript content: typing @ or / opens the suggestion list over the transcript, in the same #161616 and with no outline. Its top edge and corners are invisible, so the rows run into the transcript text behind them.
- Why it matters: Floating UI loses its separation in dark mode, where shadows don't show on near-black, making suggestions harder to tell apart from the transcript. It also differs from the desktop and from the composer itself, which has a border.
- Fix: Add `.overlay(RoundedRectangle(cornerRadius: OCRadius.dock).strokeBorder(OCColor.border, lineWidth: OCBorder.hairline))`, as OCPromptDock does, and use layer1 in dark to match OCComposerSurface. Consider having ElevationModifier draw a 0.5pt 20% white ring in dark mode, as upstream's dark elevation does (`0 0 0 0.5px #fff3`).

<a id="f23-11"></a>

## F23-11: In dark mode, markdown links differ from body text by only 1.80:1 and have no underline

*P3 bug · accessibility · effort S · found by contrast-dark-mode*

- Where: `OCDesign/MarkdownBlockView.swift:26`
- Evidence: `MarkdownBlockView.swift:26 '.link(.foregroundColor(OCColor.accent))' sets colour only; nothing in Sources underlines links`; `Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/ReadSnapshots/capture-_-name-height.markdown-dark-820.png: 'a link' is #A2BCFF next to body text #FAFAFA, a luminance contrast of 1.80:1`; `Light: #3B5CF6 against #161616 is 3.49:1, which passes the 3:1 link-to-text guideline` (+1 more)
- What happens: Dark mode, an assistant paragraph containing a URL or a file link: the link is pale blue next to near-white text, with no underline.
- Why it matters: Users with colour-vision deficiencies or reduced contrast sensitivity can't pick out links in dark mode. WCAG 1.4.1 needs either a non-colour cue or at least 3:1 against the surrounding text.
- Fix: Underline links in both appearances: `.link(.foregroundColor(OCColor.accent), .underlineStyle(.single))`. This also marks the file-path links.

<a id="f23-14"></a>

## F23-14: Find in file: other matches are 1.22:1 against the page, and the current match differs only in intensity

*P3 bug · visual · effort S · found by contrast-dark-mode*

- Where: `OCDesign/CodeCell.swift:84-87`
- Evidence: `CodeCell.swift:86 'UIColor(OCColor.warning).withAlphaComponent(active ? 0.55 : 0.25)'`; `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.files-find-in-file-light-820-default.png: another match's fill (#EEE3C8) on #FAFAFA is 1.22:1, and string text on it (#198B43) is 3.42:1; the current match (#E1C88E) is 1.57:1 (crops/contrast-dark-mode/find-light.png)`; `Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots/capture-_-name.files-find-in-file-dark-820-default.png: #FAFAFA text on the current match (#897645) is 4.24:1, and another match (#433A23) is 1.78:1 against #080808 (crops/contrast-dark-mode/find-dark.png)`
- What happens: Open a file in Files and use Find with several matches. In light mode the other matches are barely tinted cream and the current one is only a slightly stronger cream. In dark mode the current match's highlight drags its own text down to 4.24:1.
- Why it matters: Users can't scan for the other matches, and knowing which match is current depends on a subtle change in the intensity of a single hue.
- Fix: Outline or underline every match with a 1pt OCColor.warning stroke. Fill the current match with full-strength OCColor.warning and force its text to #161616 (7.4:1 on #CB9F34, 12:1 on #F2CF76). Keep other matches at about 0.35 alpha plus the outline.

<a id="g17-m1"></a>

## G17-M1: Two different switch designs, and the OC switch behind the iPad 'Reviewed' control has a 1.38:1 off state

*P3 bug · accessibility · effort S · found by verifier G17*

- Where: `OCDesign/Controls.swift:54-69`, `OCDesign/Controls.swift:111-129`, `FeatureReview/ReviewScreen.swift:145`, `FeatureApprovals/FormRenderer.swift:86`, `FeatureServers/ServerSettingsView.swift:31-34` (+1 more)
- Evidence: `ipad/ipad-review-changes.png: the 'Reviewed' switch at the right of the diff toolbar has track (219,219,219) and thumb (242,242,242) on a white (255) toolbar. That is 1.38:1 track to background and 1.24:1 thumb to track; WCAG 1.4.11 requires 3:1. Zoom: crops/verify-G17/reviewed-toggle.png`; `iphone/server-list.png: Settings uses full-size system switches tinted black (on track (22,22,22)), a different design from the 24×16 OC switch`; `Controls.swift:117-119 'RoundedRectangle(cornerRadius: OCRadius.sm).fill(configuration.isOn ? OCColor.accentBackground : OCColor.layer4).frame(width: 24, height: 16)' with thumb toggleThumb #F2F2F2` (+1 more)
- What happens: iPad landscape, light mode, Review panel open on a changed file. The per-file 'Reviewed' control is a pale grey 24×16 pill that barely stands out from the white toolbar, so it is hard to see as a switch or to tell that it is off. The same user sees large black iOS switches in Settings. The OC switch also renders the question-form 'I completed this step' field.
- Why it matters: The main per-file progress control in iPad review is hard to find and read, and the app shows two unrelated switch designs.
- Fix: Use one switch everywhere. Either keep OCToggleStyle, give its off state a boundary of at least 3:1 (a borderStrong outline or a darker track token) and size it with @ScaledMetric, then use OCToggleRow in ServerSettingsView; or use the system switch everywhere, tinted with OCColor.accent rather than OCColor.text.
- Also reported as: F23-09 by contrast-dark-mode, F32-11 by design-parity

<a id="f23-13"></a>

## F23-13: Smart Invert will invert attached photos and image previews

*P3 bug · accessibility · effort S · plausible, needs a running app to confirm · found by contrast-dark-mode*

- Where: `OCDesign/ComposerChrome.swift:83-85`, `FeatureFiles/FilesScreen.swift:246`, `OCDesign/CodeEditorCell.swift:42-53`, `OCDesign/FileIcon.swift:33`
- Evidence: `No 'accessibilityIgnoresInvertColors' (SwiftUI modifier or UIView property) anywhere in Packages/OpencodeKit/Sources or App`; `Image sites without it: OCAttachmentChip 'Image(uiImage: thumbnail)' (ComposerChrome.swift:84), the FilesScreen image viewer 'Image(uiImage: image)' (FilesScreen.swift:246) and the review image diff's UIImageView in CodeImageCell (CodeEditorCell.swift:43)`
- What happens: With Settings > Accessibility > Display & Text Size > Smart Invert on, attach a photo or screenshot to a prompt, open a PNG in Files, or review an image change: the image appears as a colour negative, both in the composer chip and in the sent-prompt thumbnail.
- Why it matters: People who rely on Smart Invert can't judge the images they attach or review. System apps exclude photos from inversion, so users expect this app to as well.
- Fix: Add `.accessibilityIgnoresInvertColors()` to the thumbnail and image-viewer Images, and set `image.accessibilityIgnoresInvertColors = true` in CodeImageCell. Consider it for the full-colour file-type icons too.

<a id="f20-13"></a>

## F20-13: Type tokens scale on mismatched Dynamic Type curves, and diff code uses its own stepped size

*P3 improvement · consistency · effort M · found by design-system*

- Where: `OCDesign/Typography.swift:24`, `OCDesign/Typography.swift:25`, `OCDesign/Typography.swift:26`, `OCDesign/Typography.swift:30`, `OCDesign/Typography.swift:33` (+2 more)
- Evidence: `Typography.swift: micro 11 → .caption2, small 13 → .footnote, body 14 → .body, button 13 → .body, code 13 → .body. Footnote and caption2 grow faster than body, so small catches up with body and overtakes button at large sizes`; `Tests/FeatureServersTests/__Snapshots__/ServerRowTests/allStatesAtLargestDynamicType.repair-light-402.png: small ('Needs re-pairing', 'Unencrypted') caps 83-84px vs body ('Pairing expires soon') 85px, so the 13:14 step is gone`; `DiffView.swift:108 'typeSize.isAccessibilitySize ? 22 : … 13' while OCType.code follows .body: at accessibility5, code lines in ReadSnapshots capture-_-name-height.markdown-light-393.png are about 1.6x taller than in ReviewSnapshots capture-_-name.diff-swift-unified-wrap-light-393-accessibility5.png` (+1 more)
- What happens: With larger text, secondary text (small, micro) ends up the same size as primary text. The same code is about 1.6x larger in a transcript code block than in the diff viewer.
- Why it matters: The hierarchy flattens for large-text users and code size jumps between surfaces. Using 'button' as a title style makes future type changes risky.
- Fix: Anchor every Inter token to one curve: all relativeTo .body, or styles whose default sizes match the token (e.g. body 14 → .subheadline or .callout). Add a label/title-small token instead of reusing button. Drive the diff font from UIFontMetrics(forTextStyle: .body) with a cap instead of fixed buckets.

<a id="f20-14"></a>

## F20-14: Feature code bypasses OCDesign: system-font titles, four search-field styles, raw spinners and unused components

*P3 improvement · consistency · effort M · found by design-system*

- Where: `FeatureTranscript/SessionScreen.swift:79`, `FeatureComposer/ModelPicker.swift:49`, `FeatureComposer/NewSessionView.swift:206`, `OCDesign/TextSelection.swift:36`, `FeatureReview/ReviewScreen.swift:95` (+6 more)
- Evidence: `crops/design-system/crops/navtitles.png: the session title 'Design system' (evidence/app/iphone/transcript-tools.png) is SF Pro semibold, while 'Settings' and 'Permission required' are Inter medium via ocNavigationTitle. Plain .navigationTitle is also used at SessionActions.swift:80, NewSessionView.swift:180,206, ModelPicker.swift:49 and TextSelection.swift:36`; `Search and filter fields: Changes 'Filter files' is a bare .plain field that reads as stray grey text (evidence/app/ipad/ipad-review-changes.png); the Files filter inherits the bordered OCTextFieldStyle (ipad-review-files.png); Home 'Search sessions' is a #fafafa fill with a magnifier on #ffffff (home.png); ModelPicker and BranchPicker use system .searchable`; `Raw ProgressView at SessionScreen.swift:55, ReviewScreen.swift:32, FilesScreen.swift:214 and NewSessionView.swift:41-42; OCSpinner is used once` (+2 more)
- What happens: On iPhone, moving between Settings and a session changes the navigation title's typeface and weight. The review panel's two filter fields look unrelated. Loading states switch between a stacked system spinner and OCSpinner.
- Why it matters: Small inconsistencies make the app feel less polished and less like opencode. The component gallery tests components the app doesn't ship and misses the ones it does, so regressions like the selected-tab and toggle-contrast problems go uncaught.
- Fix: Use ocNavigationTitle everywhere, or set Inter through UINavigationBarAppearance. Add an OCSearchField component and use it for Home, Changes and Files. Replace raw ProgressView with OCSpinner. Delete or adopt OCToolRow, OCListRow, OCProgress and PlaceholderRootView. Point the components snapshot at shipped components and their states. Add OCColor entries for toggleThumb, sentMentionPrefix and the composer surface, and use OCLayout.touchTarget instead of literal 44.
- Also reported as: F04-13 by session-chrome, F30-14 by visual-polish-iphone

<a id="f23-07"></a>

## F23-07: textFaint (#808080 in both appearances) fails 4.5:1 for Home paths and costs, line numbers and comment metadata

*P3 improvement · accessibility · effort S · found by contrast-dark-mode*

- Where: `OCDesign/Resources/Colors.xcassets/oc2-textFaint.colorset/Contents.json`, `FeatureInbox/HomeSessionRow.swift:43-45`, `FeatureInbox/HomeSessionRow.swift:61`, `OCDesign/CodeCell.swift:106`, `OCDesign/CodeCell.swift:142` (+2 more)
- Evidence: `iphone/home.png: 'Studio Mac · /Users/<name>/2.1.2/…' and '$0.00' are #808080 on #FFFFFF = 3.95:1 at 11pt medium (crops/contrast-dark-mode/home-row.png)`; `Computed: on layer1, 3.78:1 light and 3.93:1 dark (line-comment 'lines 2–3' and the CodeCell comment meta). On backgroundDeep, 3.78:1 light (context-line numbers)`; `oc2-textFaint is #808080 in both light and dark, the same as upstream's v2-text-text-faint (.build/design-reference/computed-tokens-light.json)`
- What happens: Light mode, default text size:
  - iPhone Home: every row's server and directory path and its cost are 11pt mid-grey on white.
  - In a diff, the context-line numbers are the same grey on #FAFAFA.
  - When adding a line comment, 'lines 2–3' is grey on the #FAFAFA card; it is 3.93:1 in dark too.
- Why it matters: These carry real information (which server and folder a session belongs to, its cost, a comment's line range) at the smallest type size, and below 4.5:1 they are hard to read for low-vision users. This revisits docs/design.md's 'subdued directory/server labels' decision.
- Fix: Use textMuted (6.4–6.7:1) for informational labels: Home path and cost, comment range and meta. Keep textFaint for disabled or decorative text, and retune it to light #737373 (4.54:1 on #FAFAFA) and dark #8C8C8C (4.62:1 on #242424) so the gutters pass. Record the deviation from OC-2 in docs/design.md.

<a id="f23-08"></a>

## F23-08: No Increase Contrast support: none of the 67 colour sets has a high-contrast variant

*P3 improvement · accessibility · effort M · found by contrast-dark-mode*

- Where: `OCDesign/Resources/Colors.xcassets/oc2-border.colorset/Contents.json`, `OCDesign/Colors.swift:5-8`, `research/07-ios-stack.md:317`
- Evidence: `All 67 *.colorset/Contents.json files contain only luminosity light/dark entries; none has an 'appearance: contrast, value: high' entry (oc2-sentMentionPrefix has no dark entry either)`; `No reference to colorSchemeContrast, accessibilityContrast or differentiateWithoutColor in Packages/OpencodeKit/Sources or App`; `Borders are alpha overlays: border 10% (1.26:1 light, 1.33:1 dark), borderMuted 7.8% (1.19, 1.23) and borderStrong 20% (1.61, 1.88). Text-field and card outlines stay at these values` (+1 more)
- What happens: With Settings > Accessibility > Display & Text Size > Increase Contrast turned on, in either appearance, the app looks exactly the same: textFaint stays at 3.4–3.95:1, warning text at 2.35:1, and card and field outlines at 1.2–1.9:1.
- Why it matters: Users who rely on Increase Contrast get nothing from it. While the defaults fail, the app also can't claim the App Store's Sufficient Contrast accessibility label.
- Fix: Add 'High Contrast' appearance entries to:
  - oc2-textFaint (use the textMuted values) and oc2-textMuted (#3A3A3A / #DBDBDB);
  - oc2-border, borderMuted and borderStrong (alpha 0.35–0.5);
  - oc2-iconMuted and the warning and success inks;
  - oc2-syntaxPunctuation and oc2-syntaxOperator.

  Asset-catalog colours resolve these from UITraitCollection.accessibilityContrast with no code changes. Add a snapshot pass with traitOverrides.accessibilityContrast = .high, and add Increase Contrast to the M9 accessibility checklist.

<a id="f23-12"></a>

## F23-12: Syntax and mention colours fall below 4.5:1: dark punctuation and operators 3.65–3.77:1, light property names and file mentions 3.62–3.77:1, sent '@' 2.42:1

*P3 improvement · accessibility · effort S · found by contrast-dark-mode*

- Where: `OCDesign/Resources/Colors.xcassets/oc2-syntaxPunctuation.colorset/Contents.json`, `OCDesign/Resources/Colors.xcassets/oc2-syntaxOperator.colorset/Contents.json`, `OCDesign/Resources/Colors.xcassets/oc2-syntaxProperty.colorset/Contents.json`, `OCDesign/Resources/Colors.xcassets/oc2-syntaxString.colorset/Contents.json`, `OCDesign/CodeCell.swift:158` (+4 more)
- Evidence: `Packages/OpencodeKit/Tests/ReadSnapshots/__Snapshots__/ReadSnapshots/capture-_-name-height.diff-dark-820.png: '=' is #707070 on the deleted row #1F0E0F (3.76:1) and on the added row #09150E (3.77:1); crops/contrast-dark-mode/diff-dark-rows.png. It is 3.65:1 on #161616 and 3.13:1 on layer1`; `Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots/capture-_-name-fixedHeight.dock-typing-light-393-default.png: the file mention '@main.swift' is #D16427 on #FEFEFE = 3.74:1 (crops/contrast-dark-mode/dock-typing-light-top.png). Property tokens are 3.62:1 on the #FAFAFA code background and 3.40–3.49:1 on diff tints`; `Light syntaxString (#198B43) is 4.18:1 on #FAFAFA and 3.93–4.03:1 on diff tints` (+2 more)
- What happens:
  - Dark mode, any diff or code block: '=', ',', '{' and operators are mid-grey on near-black.
  - Light mode composer: a file mention such as '@main.swift' is orange on white.
  - Sent prompts: the '@' is pale blue on the pale blue bubble.
- Why it matters: Code is read character by character, and punctuation and property names below 4.5:1 slow low-vision readers. This revisits docs/design.md, which specifies the mention syntax colours and the lighter '@' prefix, and the OC-2 syntax tokens.
- Fix:
  - Dark syntaxPunctuation and syntaxOperator: #707070 → #8C8C8C (5.38:1 on #161616, 5.54:1 on diff rows).
  - Light syntaxProperty: #D16427 → #A84F1E (5.29:1 on #FAFAFA, 4.98:1 on diff tints).
  - Light syntaxString: #198B43 → #1D783C (4.97–5.52:1).
  - Sent '@': use OCColor.accent.
  - Record the deviation from OC-2 in docs/design.md.

<a id="f24-12"></a>

## F24-12: Panels, the approval dock and the Jump pill appear and disappear with hard cuts, and most motion tokens are unused

*P3 improvement · visual · effort M · found by touch-gestures-motion*

- Where: `OCDesign/Metrics.swift:46`, `OCDesign/WorkspaceShell.swift:34`, `OCDesign/WorkspaceShell.swift:39`, `FeatureApprovals/ApprovalDock.swift:14`, `FeatureTranscript/SessionTimeline.swift:41` (+1 more)
- Evidence: `grep: only OCMotion.fast (button press) and OCMotion.toggle are referenced; OCMotion.panel (from mobile-drawer.css), toast, opacity, standard and easing have no uses`; `No withAnimation or .transition anywhere in Sources`
- What happens: On iPad, toggling Review snaps the timeline from full width to 450 pt and the panel pops in; toggling Home does the same. Approving in the dock removes the card instantly and the composer and transcript jump. 'Jump to latest' pops in and out, and tool disclosures expand without a transition.
- Why it matters: Abrupt layout jumps make it hard to follow what moved. The design system already defines the desktop's drawer timings.
- Fix: Wrap the shell toggles and the dock/pill insertions in withAnimation(reduceMotion ? nil : OCMotion.easing). Add .transition(.move(edge:).combined(with: .opacity)), falling back to opacity only under Reduce Motion, using the panel and opacity tokens. Keep timeline row updates unanimated.

<a id="f25-06"></a>

## F25-06: UI text can’t be localized as built: OCDesign takes String titles, ~140 English strings live in model layers, and the package has no localization bundle

*P3 improvement · localization · effort L · found by l10n-text*

- Where: `Packages/OpencodeKit/Package.swift:34`, `Packages/OpencodeKit/Package.swift:61`, `Packages/OpencodeKit/Package.swift:66`, `OCDesign/Controls.swift:25`, `OCDesign/Rows.swift:21` (+11 more)
- Evidence: `Controls.swift:30-40 public init(_ title: String, icon: String, …) … .accessibilityLabel(title).help(title): a String goes through the verbatim StringProtocol overloads and is never looked up`; `Script count over Feature*/OCDesign (previews excluded): 92 literals passed directly to String-typed OCDesign inits, including OCIconButton 29 (the only VoiceOver labels of icon buttons), OCLabel 21, OCBadge 14, ocNavigationTitle 7, OCSection 5, OCEmptyState 5, OCConfirmationSheet 3; more arrive via ternaries and variables`; `About 140 English sentence literals in OCModels, OCSync, OCRender and OCNetworking (FormValidation errors, ConnectionFailure.message, WriteErrorMessage, ServerStatus titles, tool titles, timeline sentences)` (+2 more)
- What happens: M9a adds a String Catalog. Xcode extracts only LocalizedStringKey, LocalizedStringResource and String(localized:) literals. Every badge, banner, empty state, sheet title, confirmation and icon-button VoiceOver label therefore stays English, as does every error, status and tool label built in the model layers. Even the literals it does extract from the Feature targets won’t resolve at runtime, because SwiftUI looks them up in the main bundle.
- Why it matters: The catalog alone would produce a half-translated app. Changing about 20 component APIs and five modules is the expensive part of localization, and it is cheaper before more screens are built on these APIs. Translators could also break the comment and voice wire formats if those strings land in the catalog.
- Fix: Add defaultLocalization: "en" and a String Catalog per UI-owning target (or one strings target), and pass bundle: #bundle or .module. Change OCDesign inits to take LocalizedStringResource, keeping explicit verbatim: overloads for user content. Have ToolPresenter, TimelineRowBuilder, ServerStatus, WriteErrorMessage, FormValidation and ConnectionFailure return LocalizedStringResource, or enums that views format. Mark the wire strings as non-localizable. M9a plans the catalog; this prerequisite work is not listed there.
- Also reported as: F25-07 by l10n-text

<a id="f25-12"></a>

## F25-12: Directional icons and arrow-key navigation won’t mirror in RTL localizations

*P3 improvement · localization · effort S · found by l10n-text*

- Where: `OCDesign/Resources/Icons.xcassets/chevron-right.imageset/Contents.json:1`, `OCDesign/TimelineChrome.swift:50`, `OCDesign/DiffCardView.swift:69`, `FeatureFiles/FilesScreen.swift:123`, `FeatureReview/ReviewScreen.swift:141` (+3 more)
- Evidence: `None of the 381 imagesets sets "language-direction"; chevron-right/Contents.json has only preserves-vector-representation and template-rendering-intent`; `Collapsed disclosures use "chevron-right"; previous/next file use chevron-left/right with .keyboardShortcut(.leftArrow/.rightArrow, modifiers: []); the panel toggles use "layout-left" and "sidebar-right"`; `Copy: “Settings → Privacy & Security → Local Network”`
- What happens: With an Arabic or Hebrew localization, SwiftUI mirrors the layout (the Home sidebar moves to the right and the review panel to the left), but disclosure chevrons still point right, the sidebar-toggle glyphs point to the wrong side, and the → arrows in copy read backwards.
- Why it matters: Disclosure and navigation affordances read backwards for RTL users once an RTL localization ships.
- Fix: Set "language-direction": "left-to-right" on the directional imagesets (chevrons, arrows, layout-left/right, sidebar-right, undo), or apply .flipsForRightToLeftLayoutDirection(true) in OCIcon for that set. Map previous/next to layout-relative keys. Avoid literal arrows in localizable copy.

<a id="f30-06"></a>

## F30-06: Ghost buttons and menus look like plain text and sit 12pt in from the content edge

*P3 improvement · interaction · effort M · found by visual-polish-iphone*

- Where: `OCDesign/Controls.swift:11-24`, `FeatureInbox/HomeSessionRow.swift:63-67`, `FeatureComposer/ComposerDock.swift:210-213`, `FeatureComposer/PendingInputPanel.swift:40-41`, `FeatureFiles/FilesScreen.swift:34-44` (+3 more)
- Evidence: `iphone/home.png: 'Review' on Needs-you rows is black 13pt text with no shape, in the same colour as the titles`; `iphone/composer-queue.png and composer-send-menu.png: 'Steer' in the queue card and 'Queue' in the composer toolbar read as labels`; `iphone/question-sheet.png, permission-sheet.png, update.png: the 'Dismiss', 'Reject' and 'Copy command' labels start ~12pt right of the content edge (~36pt vs 24pt)` (+3 more)
- What happens: iPhone 17 Pro, light. These controls all render as body-coloured text with no container, chevron or tint:
  - the main action on a Needs-you row ('Review');
  - the alternate delivery action and the queue card's 'Steer';
  - the sheets' negative actions;
  - 'Review options';
  - the Files tab strip;
  - the new-session project and worktree menus.

  The 12pt padding stays even though the background is clear, so their labels don't line up with the text above them.
- Why it matters: Users find key actions only by tapping around. This is a main reason the app reads as a web page rather than an iOS app. Revisits docs/design.md, which takes the ghost variant from button.css.
- Fix: On iOS, give ghost buttons a tappable look: an accent or tint foreground, or a subtle layer1 fill. Remove or offset the leading padding when a ghost button starts a column. Give the open file tab a selected style. Add chevrons to the menu labels (project, worktree, Review options). Move Find to an icon-only trailing button, away from 'Mention in composer'.
- Verifier's note: Restyle the standalone actions: Home Review, queue Steer/Send, alternate delivery, Review options, the Files tabs, the new-session selectors (add chevrons) and Copy command. Keep the ghost style for secondary actions beside a primary. The Files-tab selected state overlaps F31-04.

<a id="f38-14"></a>

## F38-14: iPad onboarding sits in the top-left of a 640-pt column, leaving most of the screen empty

*P3 improvement · ipad · effort S · not verified · found by sweep-approval-server-snapshots*

- Where: `OCDesign/Feedback.swift:74`, `FeatureServers/ServerRootView.swift:37`
- Evidence: `Packages/OpencodeKit/Tests/FeatureServersTests/__Snapshots__/DesignScreenTests/screens.onboarding-light-1180x820.png: icon, title, one line and the button fill about 170 pt at the upper left; roughly 70% of the screen is blank`; `Packages/OpencodeKit/Tests/FeatureServersTests/__Snapshots__/DesignScreenTests/screens.onboarding-light-820x1180.png and screens.onboarding-dark-1180x820.png: same`; `Packages/OpencodeKit/Tests/FeatureServersTests/__Snapshots__/DesignScreenTests/screens.add-server-light-1180x820.png: by contrast, the connection form the button opens is centred` (+1 more)
- What happens: First launch on iPad, in either orientation.
- Why it matters: The first screen looks sparse and unfinished, and it doesn't match the centred connect screen it leads to.
- Fix: At regular width, centre the empty state vertically and horizontally, as AddServerView does. Or embed the pairing form directly in the onboarding page.

<a id="f31-14"></a>

## F31-14: No pointer hover feedback on any custom control on iPad

*P3 improvement · ipad · effort M · plausible, needs a running app to confirm · found by visual-polish-ipad*

- Where: `OCDesign/Controls.swift:11-24`, `OCDesign/Controls.swift:36-40`, `OCDesign/WorkspaceShell.swift:84-89`, `FeatureInbox/HomeSessionRow.swift:53`, `FeatureReview/ReviewScreen.swift:100-114` (+1 more)
- Evidence: `Searching Packages/OpencodeKit/Sources for hoverEffect, onHover or pointerStyle finds nothing`; `Every control uses the custom OCButtonStyle or '.buttonStyle(.plain)': project tabs, OCIconButton, OCSegmentedControl, Home rows and review tree rows. As far as I know these do not get the system's automatic pointer effect`; `OCColor.hover, the desktop's overlay-hover token, is used only by the @-suggestion list (ComposerDock.swift:241)`
- What happens: iPad with a Magic Keyboard or trackpad: moving the pointer over tabs, sidebar sessions, toolbar icons or file-tree rows gives no highlight or lift; only `.help` tooltips appear on icon buttons.
- Why it matters: Pointer users get no hint of what is clickable or which row they are about to open, unlike both iPadOS conventions and the desktop design.
- Fix: Add `.hoverEffect(.highlight)` with `.contentShape(.hoverEffect, RoundedRectangle(cornerRadius: OCRadius.md))` in OCButtonStyle, OCIconButton, OCSegmentedControl, OCProjectTabs and the row buttons. Alternatively paint OCColor.hover via `.onHover` to match the desktop.
- Also reported as: F34-12 by ipad-keyboard-multitasking
