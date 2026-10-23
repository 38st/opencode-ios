# UI review

A review of the iPhone and iPad interface on 2026-10-22, at `e096b48` plus the M5a work that was then in the working tree. Forty reviewers each took one screen, one lens or one set of snapshot images. Twenty verifiers then tried to refute every finding against the code, the images and the design docs. A synthesizer merged duplicates and ranked the results, and a critic looked for gaps. Nothing was built or run for the review.

- Screens, 19 reviewers: onboarding and pairing, servers and settings, Home, the session header, timeline rows, file tools, shell and other tools, transcript scrolling, the composer, the prompt editor, pickers and new session, session actions, permissions, questions, the review panel, the diff renderer, line comments, files, and the iPad shell.
- Lenses, 17 reviewers: design tokens, VoiceOver, Dynamic Type, contrast and dark mode, touch targets and gestures, localization, SwiftUI state, performance, empty, error and offline states, wording, visual polish on iPhone and on iPad, parity with the desktop design, end-to-end flows, iPad keyboard and multitasking, privacy, and navigation and state restoration.
- Image sweeps, 4 reviewers: the 1,282 snapshot baselines, looking for clipping, overlap and dark-mode problems.

Evidence names: `iphone/…` and `ipad/…` are the 41 iPhone and 21 iPad screenshots from the UI smoke run of 2026-10-22 (`node Tools/ui-smoke/index.mjs` exports them to `.build/screenshots`). Snapshot paths point at the baselines under `Packages/OpencodeKit/Tests`, and `.build/design-compare` holds the side-by-side comparisons with the desktop app. `crops/…` were temporary crops made during the review and are not kept.

Limits: VoiceOver output, Dynamic Type at run time, scrolling performance and device-only behaviour (the camera, Face ID, the Local Network alert) were judged from code and snapshots, not observed. Findings marked plausible need a running app to confirm. Deliberate decisions recorded in `docs/design.md` are not reported as bugs, and work that the roadmap already plans is tagged with its milestone.

Severity: P0 is a crash, data loss, a blocked core flow or an exposed secret. P1 is clearly broken in a primary flow, or a serious accessibility barrier. P2 is a noticeable defect or friction with a workaround. P3 is polish.

| | P0 | P1 | P2 | P3 | Total |
| --- | --- | --- | --- | --- | --- |
| Bugs | 0 | 9 | 135 | 99 | 243 |
| Improvements | 0 | 0 | 24 | 71 | 95 |

## What the review found

Forty reviewers filed 595 findings. The verifiers refuted one and marked 30 as duplicates; the two snapshot-sweep pairs lost their verifier to a usage limit, so their 56 findings stayed unverified. Merging the rest by root cause left **338 distinct findings: 243 bugs and 95 improvements**, with no P0 and nine P1. Of those, 319 were confirmed by a verifier, 11 are plausible, and 8 unverified sweep findings survived on their own (they are tagged *not verified*). The synthesis step also hit the limit, so the clusters, themes and rankings below were written by hand from the verified findings, with the P1 bugs checked against the code again.

No crash or data-loss bug was found. The serious problems are a stuck composer, a keyboard that cannot be dismissed, connection state that is visible only in Settings, a hidden New session screen on iPads in portrait, and an accessibility layer that has labels but no announcements, values or headings. Most of the rest comes from a small number of shared causes: fixed point sizes in OCDesign components, five colour tokens, raw wire data shown as text, and the current selection not travelling between Home, the tabs and New session. Fixing those causes clears dozens of findings at once; the Themes section lists them.

Each finding below links to its full entry: where it is in the code, the evidence image, the scenario, why it matters and a suggested fix. The duplicates folded into each entry are listed under *Also reported as*, so the finder count shows how many independent reviewers hit the same thing.

## Fix first

| # | Finding | Severity | Area | Why |
| --- | --- | --- | --- | --- |
| 1 | [F09-02](composer.md#f09-02) Edit and resend, then Discard on the failed row, leaves the composer unable to send in that session | P1 bug | Composer | Edit and resend then Discard leaves a session that can never send again; the user has no way to see why. |
| 2 | [F10-03](prompt-editor.md#f10-03) On iPhone the keyboard cannot be dismissed once the prompt is focused, leaving about 155 pt for the transcript | P1 bug | Prompt editor | The most common action on iPhone; the transcript is unreadable while typing and the keyboard never goes away. |
| 3 | [F28-01](home.md#f28-01) Connection loss is invisible outside Settings: Home and the session screen keep looking live while offline | P1 bug | Home | The honest connection state the spec promises; users wait on runs nobody is observing. |
| 4 | [F19-01](ipad-keyboard-and-app-shell.md#f19-01) In portrait and other narrow iPad widths, New session stays hidden under the Home sheet (the + looks dead, and ⌘N opens Home) | P1 bug | iPad, keyboard and app shell | On iPads in portrait, the + button looks dead and ⌘N opens the wrong thing. |
| 5 | [F06-01](tool-rows.md#f06-01) Every file-tool row is followed by a duplicate bold line repeating its subtitle; for Glob/Grep it is a fake file link | P1 bug | Tool rows | Visible in every transcript with file tools; a dead link for Glob and Grep. A one-line fix. |
| 6 | [F10-01](prompt-editor.md#f10-01) Shell mode keeps autocapitalization, autocorrect and smart quotes/dashes, so commands are rewritten before they run on the user's computer | P2 bug | Prompt editor | Autocorrect and smart quotes rewrite shell commands before they run on the user's computer. |
| 7 | [F13-01](approvals-and-questions.md#f13-01) The same permission request appears 2 to 3 times on the session screen, each copy with its own Allow once | P2 bug | Approvals and questions | Every approval is drawn two or three times, each with its own Allow once. |
| 8 | [F04-01](session-screen.md#f04-01) At accessibility text sizes, fixed session chrome leaves the iPhone transcript only ~13–130 pt | P1 bug | Session screen | At accessibility text sizes the session screen has almost no room for the conversation. |
| 9 | [F21-01](session-screen.md#f21-01) No VoiceOver announcements anywhere: approvals, run end/failure, inline errors and copy feedback arrive silently | P1 bug | Session screen | VoiceOver users are never told that an approval arrived or a run finished. |
| 10 | [F08-01](transcript-list-behaviour.md#f08-01) Auto-follow ignores VoiceOver, Switch Control and keyboard scrolling, so during a run the transcript snaps back to the bottom | P1 bug | Transcript list behaviour | Auto-follow drags VoiceOver and keyboard users back to the bottom while they read. |
| 11 | [F11-01](pickers-and-new-session.md#f11-01) VoiceOver never announces the chosen project, worktree, agent or variant, and their menus mark no current choice | P1 bug | Pickers and new session | The new-session pickers never tell VoiceOver which project, worktree or agent is chosen. |
| 12 | [F03-01](home.md#f03-01) New session ignores the project picked in Home or in the iPad project tabs | P2 bug | Home | The first prompt starts the agent in the wrong repository unless the user spots the small chip. |
| 13 | [F13-02](approvals-and-questions.md#f13-02) Face ID cancel or failure closes the sheet first, then shows a misleading, sticky, server-wide error; the authenticating, sending and failed states never appear | P2 bug | Approvals and questions | Cancelling Face ID shows a wrong, sticky, server-wide error. |
| 14 | [F06-05](tool-rows.md#f06-05) Inline diff card height is raw patch line count × 24pt: blank band for real patches, clipped inner scroller at larger text | P2 bug | Tool rows | Reported by eight reviewers: blank bands at default text, clipped rows and trapped swipes at large text. |
| 15 | [G05-M1](composer.md#g05-m1) Typing a built-in slash command (/compact, /undo, /new) and tapping Send sends it to the agent as plain text | P2 bug | Composer | Typing /compact or /undo and tapping Send sends the command to the model as text. |

## Highest-value improvements

| # | Finding | Severity | Area | Why |
| --- | --- | --- | --- | --- |
| 1 | [F09-12](composer.md#f09-12) While a run is active and the prompt has text, there is no touch path to Stop, and Interrupt and send hides behind a long-press | P2 improvement | Composer | While a run is active and the prompt has text there is no touch path to Stop. |
| 2 | [F32-07](approvals-and-questions.md#f32-07) The approval docks do less than the reference: questions need a sheet and 4 taps, and the permission dock has no Reject | P2 improvement | Approvals and questions | The dock lets users allow in one tap but refusing takes four; questions always need a sheet. |
| 3 | [F03-10](home.md#f03-10) Row subtitles spend their line on 'Server · /absolute/path' and never say what is blocked or running | P2 improvement | Home | Home rows could say what is blocked or running instead of spending the line on an absolute path. |
| 4 | [F13-06](approvals-and-questions.md#f13-06) The 'Allow always' scope shows a bare pattern such as '*' with no action or project, so users can't tell it approves every future read or edit | P2 improvement | Approvals and questions | 'Allow always' with a bare '*' approves every future read or edit without saying so. |
| 5 | [F29-04](approvals-and-questions.md#f29-04) Permission dock and sheet show the raw action id (“Shell”, “edit”, “External_directory”) instead of the desktop's plain-language description | P2 improvement | Approvals and questions | Plain-language descriptions of what the agent wants to do, as the desktop shows. |
| 6 | [F17-09](review-comments.md#f17-09) Commenting hides behind an unhinted long press with no haptic or range feedback, and it blocks copying code | P2 improvement | Review comments | Line comments are a headline feature with no visible affordance. |
| 7 | [F16-05](diff-and-code-renderer.md#f16-05) Code cannot be copied from diffs or the file viewer without VoiceOver, and the only 'Copy line' menu item copies placeholder text | P2 improvement | Diff and code renderer | Code cannot be copied from diffs or the file viewer. |
| 8 | [F15-05](review-panel.md#f15-05) Reviewed state is invisible in the iPhone accordion and buried in a per-file menu | P2 improvement | Review panel | Reviewed state is invisible on iPhone and buried in a per-file menu. |
| 9 | [F09-06](composer.md#f09-06) Queue and outbox rows don't say what state they are in or why a prompt failed | P2 improvement | Composer | Queue and outbox rows should say what state a prompt is in and why it failed. |
| 10 | [F11-07](pickers-and-new-session.md#f11-07) New session opens without focusing the prompt, so ⌘N on iPad and + on iPhone need an extra tap before typing | P2 improvement | Pickers and new session | Focus the prompt when New session opens; saves a tap on every new session. |
| 11 | [F04-08](session-screen.md#f04-08) iPhone session chrome uses ~190 pt before the first message while the nav bar's trailing area sits empty | P2 improvement | Session screen | About 190 pt of chrome before the first message, with an empty navigation bar beside it. |
| 12 | [F34-10](ipad-keyboard-and-app-shell.md#f34-10) Most spec shortcuts are missing or need the prompt focused, and none appear in the menu bar or ⌘ overlay | P2 improvement | iPad, keyboard and app shell | Most spec shortcuts are missing and none appear in the menu bar or ⌘ overlay. |
| 13 | [F39-02](privacy-and-security.md#f39-02) No app lock and no app-switcher privacy cover: code, diffs and pending approvals stay visible when the app is backgrounded | P2 improvement | Privacy and security | Code, diffs and pending approvals stay visible in the app switcher. |
| 14 | [F33-01](approvals-and-questions.md#f33-01) Requests in other sessions are invisible while you are inside a session, and M5 presence will also suppress their pushes | P2 improvement | Approvals and questions | Requests in other sessions are invisible while inside a session. |
| 15 | [F13-07](approvals-and-questions.md#f13-07) Risk tiers mislabel common prompts: a .env read is 'Low risk', while built-in subagent, skill and question requests are 'High risk' and need Face ID | P2 improvement | Approvals and questions | A .env read is Low risk while built-in subagent and question requests need Face ID. |

## Quick wins

- [F06-01](tool-rows.md#f06-01) Every file-tool row is followed by a duplicate bold line repeating its subtitle; for Glob/Grep it is a fake file link (P1 bug, effort S)
- [F25-01](approvals-and-questions.md#f25-01) Reject explanation says “this session’s 0 other pending requests” (and “1 other pending requests”) (P2 bug, effort S)
- [F09-01](composer.md#f09-01) Dark mode: the enabled Send/Stop button uses the wrong colour token and looks disabled (2.7:1 glyph) (P2 bug, effort S)
- [F23-04](design-system.md#f23-04) Generic folder icon (and 9 other currentColor file icons) renders pure black in dark mode, 1.16:1 (P2 bug, effort S)
- [F20-02](design-system.md#f20-02) Two referenced icon names don't exist in Icons.xcassets, so controls render as blank (P2 bug, effort S)
- [F02-08](servers-and-settings.md#f02-08) App preferences are hard to understand: the Follow-up behavior picker has no visible label and the toggles have no explanations (P2 bug, effort S)
- [F08-02](transcript-list-behaviour.md#f08-02) 'Load earlier messages' appears on every session loaded from the server, even 1–3 message ones, pinned above the list (P2 bug, effort S)
- [F05-02](timeline-rows-and-markdown.md#f05-02) Stopping a run, or Interrupt and send, shows a red 'Run failed — Step interrupted' card (P2 bug, effort S)
- [F04-07](session-screen.md#f04-07) Header shows the raw model ID, not the composer's model name, and long IDs collapse the header into a 4–6 line stack (P2 bug, effort M)
- [F14-08](approvals-and-questions.md#f14-08) The review step shows option values instead of the labels the user picked ('unit' for 'Unit tests') (P2 bug, effort S)
- [F11-14](pickers-and-new-session.md#f11-14) Dark mode: the "Show all models" row sits on a pure black band (P3 bug, effort S)
- [F10-08](prompt-editor.md#f10-08) The placeholder is drawn 4–12 pt above where the caret and typed text appear (P3 bug, effort S)

## Themes

**Connection and run state are invisible outside Settings.** ServerStatus is rendered only on the server card. Home, the session screen and the composer keep showing live indicators while the server is unreachable, a failed resync is swallowed, loads can spin for 90 s against a dead server, and nothing says whether the agent is working, retrying or blocked on the user. ([F28-01](home.md#f28-01), [F33-03](home.md#f33-03), [G16-M1](servers-and-settings.md#g16-m1), [F28-05](composer.md#f28-05), [F28-10](review-panel.md#f28-10), [F07-03](tool-rows.md#f07-03), [F28-03](session-screen.md#f28-03))

**Fixed chrome and the keyboard starve the iPhone transcript.** The header, toolbar, approval dock, queue panel and composer are fixed-height, the keyboard cannot be dismissed, and the collection view does not stay pinned when its viewport shrinks. At default text the transcript is a strip; at accessibility sizes it can vanish. ([F10-03](prompt-editor.md#f10-03), [F04-01](session-screen.md#f04-01), [F04-08](session-screen.md#f04-08), [F13-03](approvals-and-questions.md#f13-03), [F08-04](transcript-list-behaviour.md#f08-04), [F22-07](composer.md#f22-07), [F09-11](composer.md#f09-11))

**Shared components use fixed point sizes.** OCIcon, status dots, switches, diff cards (24 pt per patch line), comment chips, accordion headers and hidden-indicator scrollers are sized in points, so they clip, overflow or vanish at larger text and on narrow widths. Fixing the OCDesign component fixes every screen. ([F20-07](design-system.md#f20-07), [F06-05](tool-rows.md#f06-05), [F22-03](composer.md#f22-03), [F17-07](review-comments.md#f17-07), [F22-09](diff-and-code-renderer.md#f22-09), [F05-07](timeline-rows-and-markdown.md#f05-07), [F22-06](timeline-rows-and-markdown.md#f22-06), [F07-06](tool-rows.md#f07-06))

**A handful of colour tokens cause most contrast failures.** The warning tone (2.35:1 on white), the dark-mode contrast fill (#5C5C5C), layer1 equal to backgroundDeep in light mode, textFaint at #808080, currentColor file icons and the global text tint on switches account for nearly every contrast and dark-mode finding. ([F23-01](design-system.md#f23-01), [F09-01](composer.md#f09-01), [F20-01](design-system.md#f20-01), [F23-07](design-system.md#f23-07), [F23-04](design-system.md#f23-04), [F23-03](design-system.md#f23-03), [F23-12](design-system.md#f23-12), [F23-08](design-system.md#f23-08), [F23-06](design-system.md#f23-06))

**VoiceOver gets labels but not state.** Nothing is announced (approvals, run end, errors), accessibility labels replace the visible value on pickers, status lives on hidden images, there are almost no headings, the transcript has no speaker, and auto-follow drags focus back to the bottom. ([F21-01](session-screen.md#f21-01), [F11-01](pickers-and-new-session.md#f11-01), [F03-09](home.md#f03-09), [F21-08](diff-and-code-renderer.md#f21-08), [F21-07](timeline-rows-and-markdown.md#f21-07), [F13-09](approvals-and-questions.md#f13-09), [F14-07](approvals-and-questions.md#f14-07), [G12-M2](approvals-and-questions.md#g12-m2), [F08-01](transcript-list-behaviour.md#f08-01), [F16-06](diff-and-code-renderer.md#f16-06), [F21-10](files.md#f21-10))

**Raw wire data leaks into the UI.** Model ids in the header, action ids on permission cards, escaped JSON in tool rows, \<shell> and \<subagent> protocol text, internal state names, 'Exit 0' badges and 'attempt 0' diagnostics all surface strings meant for machines. ([F04-07](session-screen.md#f04-07), [F29-04](approvals-and-questions.md#f29-04), [F06-03](tool-rows.md#f06-03), [F07-01](tool-rows.md#f07-01), [F07-05](tool-rows.md#f07-05), [F07-11](tool-rows.md#f07-11), [F07-12](tool-rows.md#f07-12), [F06-12](tool-rows.md#f06-12), [F02-06](servers-and-settings.md#f02-06), [F29-13](servers-and-settings.md#f29-13), [F05-04](timeline-rows-and-markdown.md#f05-04), [F07-09](tool-rows.md#f07-09))

**The current selection does not travel.** New session ignores the project and server the user is looking at, project tabs only filter a hidden list, navigation rewrites Home's filters, the sidebar never marks the open session, project order flips on every update, and pinning does not float a session. ([F03-01](home.md#f03-01), [F40-01](servers-and-settings.md#f40-01), [F19-02](ipad-keyboard-and-app-shell.md#f19-02), [F03-02](home.md#f03-02), [F03-07](home.md#f03-07), [F03-04](home.md#f03-04), [F26-01](pickers-and-new-session.md#f26-01), [F19-01](ipad-keyboard-and-app-shell.md#f19-01))

**Errors are sticky, generic or silent, and designed states never appear.** Session errors outlive their cause and leak across sessions, the registry toast cannot be dismissed, cancelling Face ID leaves a wrong message, cancelled requests look like failures, sheets close before the server replies, and the authenticating, sending, failed and 'already handled' states that were designed are never shown. ([F04-09](session-screen.md#f04-09), [F02-14](servers-and-settings.md#f02-14), [F13-02](approvals-and-questions.md#f13-02), [F13-12](approvals-and-questions.md#f13-12), [F03-06](home.md#f03-06), [F20-10](design-system.md#f20-10), [F28-09](home.md#f28-09), [F09-06](composer.md#f09-06), [F12-09](session-actions-and-confirmations.md#f12-09), [F14-14](approvals-and-questions.md#f14-14), [F28-05](composer.md#f28-05))

**State is lost on cell reuse, rotation and relaunch.** Expanded tool rows collapse when they scroll away, reading position is lost on width changes, Files and Home forget their place, rotation pops the Home sheet, half-written comments are discarded, and nothing survives the app being killed. ([F08-05](transcript-list-behaviour.md#f08-05), [F08-08](transcript-list-behaviour.md#f08-08), [F18-12](files.md#f18-12), [F19-03](ipad-keyboard-and-app-shell.md#f19-03), [F17-01](review-comments.md#f17-01), [F40-09](servers-and-settings.md#f40-09), [F40-13](home.md#f40-13), [F26-02](servers-and-settings.md#f26-02))

**The same information is drawn twice.** Pending requests appear as a timeline card and in the dock, file-tool rows repeat their subtitle, reasoning has two identical 'Thinking' disclosures, the header repeats the composer's agent and model, tool errors print twice and approval sheets stack their title. ([F13-01](approvals-and-questions.md#f13-01), [F06-01](tool-rows.md#f06-01), [F05-06](timeline-rows-and-markdown.md#f05-06), [F04-08](session-screen.md#f04-08), [F38-12](approvals-and-questions.md#f38-12), [F06-09](tool-rows.md#f06-09))

**Rebuild work runs on the main thread on every event.** Each streamed delta re-hashes the transcript, Home rebuilds every summary several times per render, Review re-sorts and re-hashes every patch, each keystroke rescans the prompt, and models are never evicted. Long sessions will feel it first. ([F27-01](timeline-rows-and-markdown.md#f27-01), [F26-11](home.md#f26-11), [F27-02](timeline-rows-and-markdown.md#f27-02), [F15-07](review-panel.md#f15-07), [F27-12](composer.md#f27-12), [F08-10](transcript-list-behaviour.md#f08-10), [F27-09](review-panel.md#f27-09), [F27-14](composer.md#f27-14))

## Findings by area

| Area | Bugs | Improvements | P0 or P1 |
| --- | --- | --- | --- |
| [Onboarding and pairing](onboarding-and-pairing.md) | 9 | 6 | 0 |
| [Home](home.md) | 17 | 3 | 1 |
| [Session screen](session-screen.md) | 9 | 6 | 2 |
| [Timeline rows and markdown](timeline-rows-and-markdown.md) | 16 | 3 | 0 |
| [Tool rows](tool-rows.md) | 20 | 8 | 1 |
| [Transcript list behaviour](transcript-list-behaviour.md) | 9 | 0 | 1 |
| [Composer](composer.md) | 17 | 7 | 1 |
| [Prompt editor](prompt-editor.md) | 10 | 2 | 1 |
| [Pickers and new session](pickers-and-new-session.md) | 11 | 5 | 1 |
| [Session actions and confirmations](session-actions-and-confirmations.md) | 9 | 3 | 0 |
| [Approvals and questions](approvals-and-questions.md) | 19 | 12 | 0 |
| [Review panel](review-panel.md) | 18 | 3 | 0 |
| [Diff and code renderer](diff-and-code-renderer.md) | 15 | 7 | 0 |
| [Review comments](review-comments.md) | 8 | 3 | 0 |
| [Files](files.md) | 12 | 4 | 0 |
| [Servers and settings](servers-and-settings.md) | 19 | 4 | 0 |
| [iPad, keyboard and app shell](ipad-keyboard-and-app-shell.md) | 10 | 4 | 1 |
| [Design system](design-system.md) | 14 | 11 | 0 |
| [Privacy and security](privacy-and-security.md) | 1 | 3 | 0 |
| [Cross-cutting](cross-cutting.md) | 0 | 1 | 0 |

## Not covered

The review was static: nothing was built or run, so these are inferred from code and images rather than observed, or were not examined at all.

- **Behaviour that needs a running app.** VoiceOver output and focus, Dynamic Type changes at run time, auto-follow timing, scrolling performance, keyboard animation, haptics, the QR scanner and camera prompt, Face ID and the timing of the Local Network alert. The 11 findings tagged *plausible* fall here.
- **Captures that do not exist.** There are no in-app screenshots of dark mode or of large text for Settings, server detail, diagnostics, Home or the session screen; those were judged from snapshot baselines of components. No iPhone landscape, no iPad Settings sheet, no add-server form as an iPad form sheet, no error banners, no scanner.
- **The two snapshot sweeps were not verified.** Their 56 findings mostly duplicated verified ones and were folded in; the 8 that stand alone are tagged *not verified*.
- **No completeness pass.** The critic agent that was to look for screens and states the roster missed did not run. Areas that got only one reviewer's attention: the Files image viewer, the directory browser, the branch picker, the diagnostics export, the update prompt, drag and drop, and Stage Manager window sizes other than the ones in the snapshots.
- **Not in scope.** Push notifications and the relay (M5b), the terminal (M7), and anything the roadmap lists for M8 parity, beyond noting where a finding is already planned.

## Rejected during verification

These were reported and then refuted by a verifier. They are listed so nobody files them again.

- F34-01, Return in an empty prompt stops the running agent: The code path is as described (ComposerSuggestions.swift:114, ComposerDock.swift:372-373, ComposerModel.swift:166-167), but the behaviour is deliberate desktop parity. research/02-opencode-features.md:377 records that on the desktop 'a blank submit while the agent works interrupts it' (app/composer/submit.ts), and research/08-feature-matrix.md:169 lists it under Stop. design.md:92 says Stop on an empty composer interrupts 'as on the desktop', and design.md:75 maps hardware Return to submit. In that state the visible button is Stop, submit is ignored while the previous send is still busy (ComposerModel.swift:149), and resume=true continues any pending steer. Refuted as a bug. If accidental stops are reported, a P3 guard would be enough, such as stopping only when the prompt was already empty before the last send.
