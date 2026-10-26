# OpenCode design mapping

D1 follows OpenCode's default **OC-2** theme at source revision `d0732eadf883bdc64c0b0ea91e9c4ee0fe51d8c3`. The reference is read-only: no code from the clone is built or executed. The visual reference is the UI served by sandboxed `@opencode/cli@2.0.32`.

| Native source in `Packages/OpencodeKit/Sources/OCDesign` | OpenCode source |
| --- | --- |
| `Colors.swift`, `Resources/Colors.xcassets` | `packages/ui/src/theme/themes/oc-2.json`, `styles/tokens/{colors,theme}.css`, `theme/resolve.ts`, `styles/theme.css` (legacy diff/syntax tokens) |
| `Typography.swift`, `Resources/Fonts` | `packages/ui/src/styles/theme.css`, `actions/button/button.css`, `assets/fonts/Inter.ttf`, `assets/fonts/JetBrainsMonoNerdFontMono-Regular.woff2` |
| `Metrics.swift` | `packages/ui/src/styles/theme.css`, `styles/tokens/theme.css` (elevation), `actions/button/button.css`, `components/dock-surface.css`, `feedback/toast/toast.css`, `forms/switch/switch.css`, `packages/app/src/shell/mobile-drawer.css` |
| `Icon.swift`, `Resources/Icons.xcassets` | `packages/ui/src/icons/catalog.ts`, `icons/icon/{additional-icons.ts,icon.tsx}`; 149 template SVGs, primary catalog takes precedence |
| `Controls.swift` | `packages/ui/src/actions/{button,icon-button}/*.css`, `components/text-field.css`, `forms/switch/switch.css`, `navigation/segmented-control/segmented-control.css` |
| `Rows.swift` | `packages/ui/src/data-display/badge/badge.css`, `packages/app/src/home`, `packages/session-ui/src/components/basic-tool.css`, `v2/components/session-review-v2.css` |
| `Surfaces.swift`, `Feedback.swift` | `packages/ui/src/components/{card,dock-surface,spinner,progress}.css`, `overlays/dialog/dialog.css`, `feedback/toast/toast.css` |
| `WorkspaceShell.swift` | `packages/app/src/shell/shell.tsx`, `session/screen-layout.ts`, `shell/{mobile-drawer,mobile-panel-drawer}.tsx` |
| `FeatureServers` screens | `packages/app/src/servers/connect`, `settings/{navigation,shell}.tsx`, `settings/servers/servers.tsx`; native credentials/diagnostics behaviour is retained |

`OCTheme` names the preset independently of semantic colour names so another asset namespace can be added later. Colours follow system appearance. Inter and JetBrains Mono register once through Core Text; every font uses `Font.custom(_:size:relativeTo:)`. Font licences were checked in their OpenType name tables, not inferred from the repository MIT licence. See `THIRD_PARTY_NOTICES.md` and the bundled licence files.

Native adaptations: controls have at least 44-point touch targets, text wraps and scales, segmented options stack at accessibility sizes, and motion honours Reduce Motion. The app manifest in `project.yml` explicitly supports portrait and landscape, including all four iPad orientations. Native toolbar icon controls use plain button styling: UIKit can flatten a custom button background into a solid template image. Only camera/QR operations use SF Symbols where the upstream catalog has no equivalent.

D1.1 follows the updated SPEC §5 and ARCHITECTURE §3.4: project tabs sit above the main session slot and review panel. The Home sidebar collapses; at narrower iPad widths it opens as a sheet, and review also becomes a sheet when the available width or accessibility text size cannot accommodate both panes. iPhone opens Home with a project picker, server switcher, search, triage sections and sessions grouped by day. Server management and every connection flow live in Settings. M2b fills Home and the timeline; M4 fills the review panel's Changes and Files tabs, and the panel starts collapsed. M3a enables approvals and M3b enables the desktop-style prompt dock. When review is opened, the timeline starts at the reference app’s 450-point width and review receives the remaining space. No disagreement with the updated layout documents remains.

`FeatureServers/WorkspaceSidebar.swift` delegates to `FeatureInbox/HomeView.swift`, which maps to `packages/app/src/home/{projects,sessions}`; `OCDesign/WorkspacePanel.swift` maps to `packages/session-ui/src/v2/components/session-review-v2.css` and the session prompt dock. The centred connection form maps to `packages/app/src/servers/connect/{screen.css,method.tsx}`: labelled pairing field, password link, supported-device scanner, and copyable `opencode pair` chip. Its neutral server icon replaces the upstream wordmark.

## Reproduce and compare

Run from the repository root:

```sh
node Tools/design-reference/index.mjs --version 2.0.32
TEST_RUNNER_OC_RECORD_SNAPSHOTS=1 xcodebuild -project Opencode.xcodeproj -scheme Opencode -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/DerivedData -only-testing:ServerSnapshots -only-testing:ReadSnapshots -only-testing:ApprovalSnapshots -only-testing:ComposerSnapshots -only-testing:ReviewSnapshots -parallel-testing-enabled NO -collect-test-diagnostics never test
node Tools/ui-smoke/index.mjs --version 2.0.32
python3 Tools/design-reference/compare.py
python3 Tools/design-reference/compare-read.py
python3 Tools/design-reference/compare-approvals.py
python3 Tools/design-reference/compare-composer.py
python3 Tools/design-reference/compare-review.py
```

Record mode intentionally reports snapshot-recording issues; rerun without `TEST_RUNNER_OC_RECORD_SNAPSHOTS` to assert the new baselines. The capture script installs Playwright 1.56.1 only in `.build/design-tools`, and sets `PLAYWRIGHT_BROWSERS_PATH` to `.build/playwright`. It uses Playwright's pinned Chromium download and macOS `ditto` to avoid the Node 26 ZIP-extraction hang. No global browser, npm package, OpenCode installation, or simulator is installed or configured.

`.build/design-reference/manifest.json` identifies each official capture and route. `.build/design-compare/index.html` labels each source/native pair. Native server diagnostics and upgrade instructions have no exact web counterpart: comparisons explicitly use the upstream settings surface and connection form as component references. Native image pixels are reduced to the matching logical viewport size without cropping. Baselines cover all M1b screens in both appearances at 393×852, 820×1180 and 1180×820, components, font/icon loading, and all connection states at the largest Dynamic Type size.

To refresh assets, use `Tools/design-reference/import-assets.py SOURCE` (FontTools and Brotli required in a local virtualenv) and `Tools/design-reference/import-tokens.py SOURCE --resolved .build/design-reference`. The latter uses computed tokens captured from the served default theme for generated diff/syntax colours. Both importers only read the checkout. Inspect the comparisons and rerun tests before accepting a new source revision.

## Read screens and rendering

`FeatureInbox` renders cross-server Needs you and Running sections, then activity grouped by day. Project letter tiles, unread dots, subdued directory/server labels and local pin/hide state reuse OCDesign. Review opens the permission, question or failure in its owning session.

`OCRender/TimelineRowBuilder.swift` follows `packages/session-ui` detail presets. Compact is the default. Prompts use the trailing accent bubble; tools use disclosure rows and the reference catalog icons. `ToolPresenter.swift` maps V1 names and preserves generic JSON/text fallbacks. `OCDesign/MarkdownBlockView.swift` isolates Textual 0.5.0; headings, quotes, tables, code and diff surfaces use OCDesign tokens. Markdown images retain alt text without fetching their URLs. The transcript uses ARCHITECTURE §3.1’s UICollectionView/UIHostingConfiguration fallback: iOS 26.5 repeatedly entered an endless LazyVStack layout cycle while scrolling variable-height rows. Stable cell identities preserve streaming observation, and prepending pages preserves the first visible row’s pixel offset. Shell polling follows cell display callbacks and scene activity.

The 400 read snapshots cover every timeline row, Home status rows, four states of each presenter, an unknown state, shell exit/timeout, Markdown and diff cards in both themes, at accessibility5 and widths 393 and 820. Tool snapshots fit their complete content; async Markdown snapshots reserve space until parsing finishes. `ReadPerformanceTests` records host/simulator JSON under `.build/performance`: main-thread CPU and wall p95 budgets are 4 ms at 50 deltas/s, cold off-main projection of 2,000 messages has a 250 ms simulator allowance, and the 5,000-row test checks physical footprint below 250 MiB (resident size is reported separately because it includes shared SDK mappings). These simulator checks do not replace the architecture’s iPhone 13 Instruments acceptance trace.

`Tools/ui-smoke` regenerates the Xcode project, verifies that the read-flow test actually ran, and requires fresh captures. `--read-flows-only` selects just M2b flows; `--ipad-only` uses the explicitly created “opencode-ios iPad” device. The normal command runs server flows, snapshots and read flows, then the iPad flow when that named device exists. `.build/design-compare/m2b.html` contains the read-screen comparisons.

## Approvals and the write core (M3a)

M3 is split in two. M3a ships the durable write core and the permission and question sheets. M3b adds the composer, pickers, new-session UI and session-action controls on top of it.

`FeatureApprovals` maps to the reference permission and question docks in `packages/session-ui`. `ApprovalDock.swift` shows a bounded dock of root and child-session requests directly above the prompt dock. `PermissionSheet.swift` shows the full review: the action, resources, directory and save patterns (all copyable), an edit preview and a risk tier from `OCModels/PermissionRisk.swift`. "Allow always" and high-risk "Allow once" require device-owner authentication through `OCSecurity/BiometricGate.swift`. The negative action is labelled "Reject", not the desktop's "Deny". There is no automatic approval mode. `QuestionSheet.swift` and `FormRenderer.swift` render every current form field type, with conditions, defaults, validation, a review step and external completion.

Writes go through the outbox. Admission bytes are persisted (outbox `operation` column, migration v2) before sending, and replies are owned by the store so dismissing a sheet cannot cancel a request. `DraftStore` keeps attributed draft text in GRDB and attachment files below Application Support/Drafts/<id>/.

Transcript polish in M3a: tool groups read "Used N Read, Glob, Grep" (replacing the architecture's older "Explored N files" example), Compact hides empty "Turn complete" rows, and the jump pill hides a zero count. `.build/design-compare/m3a.html` contains the approval comparisons. The 68 approval snapshots cover every permission and question state at widths 393 and 820, in both themes and at accessibility5.

## Composer, pickers and session actions (M3b)

`FeatureComposer/ComposerDock.swift` is the session prompt dock from `packages/app/src/composer/{composer.tsx,editor/}`. It is a raised 12-point surface with a 60–180-point editor and a 44-point toolbar. The toolbar holds the "+" menu (Photos, Camera, Files, Paste, Commands, Context, Shell command), the agent, model and variant controls, and Send. Controls keep 44-point touch targets; at accessibility sizes the selection and send controls take separate rows. The approval dock sits directly above the composer, with queued and unsent input above it. Subagent sessions show a read-only dock.

`PromptEditor.swift` wraps a TextKit 2 `UITextView`: in `Tests/ComposerEditorTests`, the iOS 26 `TextEditor` with a formatting definition did not delete mentions atomically.
- Mentions are inserted whole with a trailing space and deleted whole. Files, agents and references use the property, type and keyword syntax colours; skills stay plain.
- Sent prompts keep the desktop's accent text, with semibold mentions (`session-ui/src/message/message-content.tsx`).
- On a touch keyboard, Return inserts a newline.
- With a hardware keyboard:
  - Return sends, Shift-Return inserts a newline, and ⌘↩ sends with the alternate delivery.
  - Esc closes suggestions, then leaves shell mode, then stops the run.
  - ⌘. stops (the desktop uses it to cycle agents), ⌘' opens the model picker, ⇧⌘D cycles the variant, ⌘U attaches and ⌘N starts a new session.
  - These commands yield to an input method that has marked text.

Context, commands and shell mode:
- `@` lists references, skills and subagents, then files and directories from `fs/find`, with the desktop's row icons. The search is debounced by 120 ms; the desktop searches on every keystroke.
- The 231 file-type icons come from OpenCode's file-icon sprite, whose artwork is Material Icon Theme's (see `THIRD_PARTY_NOTICES.md`).
- MCP resources are not offered, because the server accepts only `data:` and `file://` attachments.
- `/` lists the server's commands, then new, undo, redo, compact, fork, model and agent. The desktop's export, open, terminal, MCP, connect and btw commands belong to later milestones.
- `!` enters shell mode, which uses the code font.

Attachments are sent inline as canonical base64 `data:` URLs, up to 20 MiB each. Images are downscaled to 2,000 px (HEIC becomes JPEG); PDFs and text files go as they are. Chips use 58 × 46-point thumbnails. When the model lacks image or PDF input, the dock warns before sending. Unlike the desktop, nothing is uploaded through the experimental `fs/write` route.

Delivery and pending input:
- While a run is active, Send uses the Follow-up behavior setting (Steer by default), and the alternate Queue or Steer action sits beside it, as on the desktop. The Settings sheet's App section holds Follow-up behavior and Show agent.
- Long-pressing Send adds Interrupt and send, which the desktop lacks. It interrupts only the run that was active when chosen.
- Stop, shown for an empty composer, interrupts with resume, as on the desktop.
- Pending steers stay in the timeline with Move to queue and Delete.
- The queue panel holds:
  - queued prompts, with Steer (Send when idle), Undo (restores the prompt) and Remove;
  - the outbox states: Sending, Edit and resend, and waiting for confirmation.
- In-place queue editing and reordering are not implemented.

The model picker is ported from `providers/models/select-dialog.tsx`. It is a sheet on iPhone and a popover on iPad.
- From the desktop: providers in the desktop order, search, the Free and Latest badges, and stale-model hiding with a Show all models toggle.
- Added on iOS: Default, image, PDF and variant badges; prices per million tokens; and the five most recent models per server.
- Agent and variant choices are native menus. As on the desktop, the agent control appears only for a custom primary agent or with the Show agent setting.
- A choice not yet applied is marked Pending; the session header shows the server's selection.

`NewSessionView.swift` follows `new-session/view.tsx`, with a neutral title in place of the wordmark. It shows:
- the composer;
- a project selector with a server directory browser;
- a worktree selector: Local repository, New worktree from a branch, or an existing worktree.

The draft follows the chosen project.

Session actions are Rename, Fork from message, Compact, Undo, Redo and Delete, reached from the header menu, the prompt-row context menu and slash commands. Two behaviours differ from the desktop: sending while a revert is staged asks for confirmation, and restoring a prompt over unsent input asks before replacing it. Confirmations are sheets sized to their content.

`.build/design-compare/m3b.html` contains the composer comparisons. The composer snapshots cover every state of the dock, pending input, pickers, new-session view and confirmations, at widths 393 and 820, in both themes, at the default text size and accessibility5.

## Review, diffs and files (M4)

The workspace review panel receives the selected server, session and shared composer. Changes and Files fill its first two tabs; Terminal and Context remain later milestones. On iPad the panel stays beside the timeline when the existing shell rule permits and becomes a sheet otherwise. iPhone keeps the specification's Review sheet rather than the desktop's Session/Changes/More switcher.

`FeatureReview` follows `packages/app/src/pages/session/review` and `session-ui` review components.
- At a panel width of 480 points or more, review shows a changed-file sidebar (240 points by default, 200–480, resizable, resettable and collapsible) beside the diff. Split view needs 560 points of diff column. Narrower panels show one virtualized accordion. Accessibility text sizes force unified, wrapped lines.
- The source menu chooses the session's latest turn, a specific turn, working changes or the branch. A directory without Git offers to initialize it.
- Reviewed marks are a native addition required by ARCHITECTURE. A mark is keyed to the file's patch digest, so new content clears it, and reviewed files collapse in the accordion.
- The compact rendering gate is 20,000 changed lines rather than the desktop's 500; the "Diff too large to render" and "Render anyway" wording is kept.
- Each turn with changes ends in a changes card. Tapping a file opens it in review for that turn rather than expanding inline. "Changed files" defaults on, as SPEC requires. A turn end without changes keeps M2b's row.

`OCDesign/DiffView.swift` and `CodeCollection.swift` are one native UICollectionView renderer for review, the file viewer and tool diff cards. It replaces ARCHITECTURE's Runestone role, because Runestone needs tree-sitter 0.20 and the project uses 0.25. Parsing, word diffs, tree-sitter highlighting and line measurement run off the main actor. Headers pin, context expands 20 lines at a time, horizontal scrolling is shared and stops at the widest line, and gutters scale with Dynamic Type. The four diff tints use the reference green and red at its weak and strong opacities.

Line comments start with a long press, never a plain tap, and extend by dragging. Regular widths edit inline; compact widths use a sheet. Comments persist with the draft and reach the next prompt in the desktop's wire format (notes in the text, `metadata.comments` and ranged `file://` parts). Notes name the file by its absolute server path. A comment on deleted lines carries the deleted text instead of a current-file range. The sent prompt shows comment cards in place of the raw notes.

`FeatureFiles` shows a lazy tree with fuzzy find, open-file tabs, and source, Markdown, image and Quick Look viewers. At compact widths these are separate screens. Find in file lists every match and steps through them with the visible Find button; ⌘F moves to the menu commands in M6. Files load by range with ETag revalidation, beneath a 40-file, 20-MiB memory cache and a per-server disk cache that is deleted with its server. Paths in messages, tool rows and diffs open the viewer; inline-code paths become links once the server confirms they exist.

`.build/design-compare/m4.html` contains the review comparisons (`python3 Tools/design-reference/compare-review.py`, after recording `ReviewSnapshots`). `ReviewSmokeTests` scrolls a 5,000-line rewrite end to end on iPhone and iPad, in unified and split views, and checks the scroll budgets with the DEBUG frame recorder, because simulator signposts report no hitch data.
