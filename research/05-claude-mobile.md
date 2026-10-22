# Claude for iOS: feature inventory, with depth on coding

Research date: 2026-10-15. Audience: the team building a native iOS/iPadOS client for opencode.
Scope: Anthropic's Claude app for iPhone and iPad, and Claude Code as reached from the phone.

Every claim carries a bracketed source key, such as [rc-docs]. Each key resolves to a URL in section 8 (Sources) at the end of this file. Claims I could not confirm were first tagged "unverified". A verification pass on 2026-10-15 resolved every one of those tags (see the last section); the few claims that still lack evidence now carry an [unconfirmed: ...] note.

---

## Key takeaways

1. **The Claude iOS app is a thin client for Claude Code.** Code runs in Anthropic's cloud or on your own computer. The phone starts, watches and steers sessions from one **Code** tab [mobile-docs].
2. **The Code tab is a triage inbox**: filter chips (All, Blocked, In progress, Done) with counts, a state glyph and unread dot per row, a cloud-or-laptop location line, a last-message preview, and an inline Approve button on blocked rows [itunes-api] [wn-w34].
3. **Cloud sessions** (formerly "Claude Code on the web") reached general availability on 2026-09-23. Each task gets its own VM and branch, you can steer or stop it, review a diff, open a PR, and turn on CI auto-fix [blog-web] [web-docs] [web-qs].
4. **Remote Control** drives a session on your own machine over an outbound-only relay. Pair by QR code, URL or a "device card". The phone has mode, model and effort controls, Stop, attachments, and two push-notification toggles. Trusted Devices adds biometric step-up [rc-docs] [wn-w34].
5. **Safety stance on the phone:** no Bypass permissions from the app, prompts stay open until answered, and Anthropic warns that phone instructions can cause real actions on your computer [mobile-docs] [rc-docs] [hc-dispatch].
6. **What is thin or absent:** no documented Live Activity for Code sessions, no first-party Apple Watch app, and nothing documented about iPad layout, accessibility or offline behavior [gh-101173] [itunes-api] [appstore].
7. **The general chat app** adds voice mode, a widget, an "Ask Claude" App Intent (Siri, Spotlight, Shortcuts, Share sheet), Lock Screen, Control Center and Action button controls, and iOS data tools (Mail and Messages drafts, Calendar, Reminders, Maps, Health) [hc-voice] [hc-intents] [hc-lockscreen] [hc-ios-apps].
8. **Mobile limits to note:** Research on the phone skips connectors, sharing a chat with people is not available from the app, and artifact sharing settings cannot be changed there [hc-research] [hc-share-people] [hc-artifacts].
9. **Biggest pain points** (by GitHub reactions): Remote Control disconnects that never recover (109), phone prompts despite bypass or mode drift (85), approval prompts that do not render or answers that never arrive (30 and 27), silent hangs, push reliability, Code-tab crashes, and lost drafts [gh-34255] [gh-29214] [gh-35637] [gh-28508] [gh-51267] [gh-73610].
10. **Where to beat Claude:** durable, fully visible approvals; honest reconnect states; per-session drafts that never vanish; Live Activities, Watch and actionable notifications; and a phone-first diff review (Claude's phone diff layout is undocumented). Details in section 5.

---

## 0. Reading guide

### 0.1 Tags used in this report

- `[key]` is a source key. See section 8 for the URL behind each key.
- `[unconfirmed: ...]` (added in the 2026-10-15 verification pass) means real effort found no public evidence either way; the note says what was tried. Treat it as a question, not a fact.
- "(corrected 2026-10-15)" marks a claim that the verification pass rewrote to match the evidence.
- "Reported" means a user report on GitHub (issue tracker for Claude Code), not an Anthropic statement.
- "Marketing image" means something read off the App Store screenshots. Those are polished mock-ups, so real UI may differ in detail.

### 0.2 Names and statuses that have changed (read this first)

The product names moved a lot in 2026. Old articles will mislead you.

- "Claude Code on the web" is now called **cloud sessions**. It left research preview and became generally available on 2026-09-23, according to an update note on Anthropic's launch post [blog-web]. The docs now describe the browser at claude.ai/code as just one of several places to start a cloud session [web-docs].
- **Remote Control** (drive a session running on your own machine from the phone) started as a Max-only research preview on 2026-02-24/25 [decoder-rc] [helpnet-rc]. The "Week 34" digest (Aug 17-21, 2026) says it is out of research preview [wn-w34].
- **Dispatch** (message a task from the phone and let the Desktop app decide how to run it) is now a limited beta that is closed to new users [hc-dispatch] [hc-one-claude]. The App Store listing still advertises it with a screenshot [itunes-api].
- **Cowork** (the agentic knowledge-work mode) was folded into every conversation on web, desktop and mobile starting 2026-09-16, rolling out to Pro and Max first [hc-release-notes] [hc-one-claude].
- **Ultraplan** (cloud planning with a web review editor) was an early preview in April 2026 [wn-w15]. It has since been removed [ultraplan-docs]. The removal shipped in CLI 2.1.222, published 2026-08-04, whose changelog entry reads "Removed ultraplan feature" [changelog] [npm] (corrected 2026-10-15).
- **Projects** means two things. Chat Projects are workspaces with files and instructions, free on all plans [hc-projects]. The redesigned **Claude Code Projects** are one coordinator conversation that starts parallel cloud threads. They are a public beta for Pro and Max, announced 2026-09-17 [blog-projects] [projects-docs].
- **Styles** (Concise, Explanatory, Formal and custom writing styles) are being migrated into skills, and the built-in presets will go away [hc-styles].
- **Artifacts** now have "legacy" artifacts (made before 2026-09-16) and new template-based ones (Docs, Slides, Design, Dashboards, Motion) [hc-artifacts].
- **Models in the picker** as of this date: Haiku 5.5, Sonnet 5.5, Opus 5.5, Fable 5.1, plus older Opus 5, Sonnet 5, Fable 5, Opus 4.8/4.7/4.6 and Sonnet 4.6 [hc-effort]. In Claude Code, the `opus`, `sonnet` and `haiku` aliases resolve to 5.5 versions, and the default on paid plans is Opus 5.5 [model-docs].

### 0.3 What I could not reach

- X/Twitter pages returned HTTP 402, and my searches surfaced no Reddit threads. For user sentiment I used GitHub issues in `anthropics/claude-code`. That repo is where iOS-app bugs get filed, because the iOS app has no public tracker. One such issue was labelled "invalid" for exactly that reason [gh-101173]. I also used the four sample reviews visible on the App Store page [appstore].
- My web-search quota ran out near the end of the research. A few older dates therefore rely on secondary press pages that I did fetch (named in the text). The Team and Enterprise rollout date for cloud sessions was left open at first; the 2026-10-15 verification pass found it (section 3.3).
- I cannot see the live app. UI descriptions come from Anthropic docs, App Store screenshots, the docs' own screenshot, and user bug reports.

---

## 1. The app at a glance

| Item | Value | Source |
|---|---|---|
| Name / seller | "Claude by Anthropic" / Anthropic PBC | [appstore] |
| First release | 2024-05-01 | [itunes-api] |
| Current version | 1.261014.20, released 2026-10-15 21:12 UTC, with the same generic bug-fix note and minimum iOS 18.0. The previous build, 1.261013.20, was released 2026-10-14 22:42 UTC. Apple's lookup API answers inconsistently right after a release (some calls still return 1.261013.20), but the App Store page's version history lists 1.261014.20 (corrected 2026-10-15) | [itunes-api] [appstore] |
| Requirements | iOS 18.0+ and iPadOS 18.0+ | [hc-install-ios] [itunes-api] |
| Devices | One universal build for iPhone and iPad. The supported-device list has no Apple Watch, Mac or Vision entries | [itunes-api] [appstore] |
| Size | 208 MB for 1.261013.20; the App Store page shows 209.2 MB for 1.261014.20 | [itunes-api] [appstore] |
| Rating | 4.72 from 279,494 US ratings | [itunes-api] |
| Languages | English plus 33 more | [appstore] |
| "What's New" history | 25 versions listed, a rolling window: from 1.260824.0 on Aug 25 at research time, and from 1.260826.0 (Aug 27) to 1.261014.20 after the 2026-10-15 release. Every one carries the same generic bug-fix note | [appstore] |
| Version numbering | Looks like 1.YYMMDD.N (for example 1.260618.0 was reported on Jun 22, 2026 and 1.261005.20 on Oct 11). This is my inference from reported versions | [gh-70144] [gh-101173] |
| Accessibility | The developer has not declared any accessibility features on the listing | [appstore] |
| Privacy labels | Data linked to you: coarse location, name/email/phone, photos/videos and other user content, user and device IDs, product interaction, diagnostics | [appstore] |
| Second app | "Claude for Intune" is a managed variant for Enterprise orgs that use Microsoft Intune | [hc-install-ios] |
| In-app purchases | Pro $20/month or $214.99/year; Max 5x $124.99/month; Max 20x $249.99/month; usage credits $20, $45, $200 | [appstore] |

### 1.1 Plans and web prices (for comparison with in-app prices)

| Plan | Web price | Notes | Source |
|---|---|---|---|
| Free | $0 | Chat on web, desktop and mobile; web search; file creation; memory; connectors; artifacts. No research, no Claude Code | [pricing] |
| Pro | $20/month, or $17/month billed annually ($200 up front) | More usage, Claude Code, research, projects, more models | [pricing] [cc-product] |
| Max | From $100/month (5x or 20x Pro usage); $100 and $200 tiers | Priority access, early features, API credits | [pricing] [cc-product] |
| Team | Standard $20/seat/month annual ($25 monthly); Premium $100/seat annual ($125 monthly) | Claude Code is included in every Team seat since 2026-01-16 | [pricing] [hc-release-notes] |
| Enterprise | $20/seat/month annual (20-seat minimum) plus API-rate usage | Admin controls, SSO, SCIM, compliance API | [pricing] |

In-app prices are higher than web prices. Max 5x is $124.99 in the app versus $100 on the web, and Max 20x is $249.99 versus $200. Pro annual is $214.99 in the app versus $200 on the web [appstore] [pricing] [cc-product].

### 1.2 Navigation and composer, as visible in the evidence

- A top-left button opens a sidebar. The docs place the **Artifacts** tab in the sidebar [hc-artifacts] and point to **Code** in "the app's navigation" [mobile-docs]; conversations are listed under Recents [hc-one-claude]. The top-right has a new-chat button, and chat screens add a "..." overflow menu [itunes-api] (marketing image).
- Claude Code's creator points people to the Code tab on the left of the app [boris-thread], and the official mobile docs tell you to tap Code in the app navigation [mobile-docs].
- Chat composer (marketing image): a "+" button, a pill showing the current model name ("Opus"), a microphone button for dictation, and an orange send arrow [itunes-api].
- The "+" menu is where per-chat toggles live. Documented on mobile: a Memory switch [hc-memory], Connectors on/off [connectors-docs], and (in Code sessions) Permission [perm-docs]. The Help Center's steps for Web search and Research ("+" at the bottom left of the chat, then the item) name no surface, and the Research article lists Claude Mobile among the supported apps, but neither article shows phone-specific steps [hc-websearch] [hc-research]. In the new unified experience there is no web-search toggle at all because Claude decides when to search, and Research starts with `/deep-research` or "+" then "Research" [hc-websearch] [hc-one-claude] (corrected 2026-10-15).
- Voice mode is started from a separate sound-wave button next to the microphone [hc-voice].

---

## 2. Timeline of dated milestones

Dates come from the cited source. Where a date comes from press or a changelog entry rather than Anthropic's own announcement, the source key says so.

| Date | Milestone | Source |
|---|---|---|
| 2024-05-01 | iOS app first released | [itunes-api] |
| 2025-01-22 | Home Screen / Lock Screen / Today View widget reported (new chat, analyze photo, dictation) | [onlinemarketing-widget] |
| 2025-05-16 | Research reported available on mobile | [alt-research-mobile] |
| 2025-05-27 | Voice mode beta on iOS and Android (English only at launch, five preset voices) | [ppc-voice] |
| 2025-07-21 | Artifacts on iOS and Android | [blog-artifacts] |
| 2025-07-28 | Remote MCP connectors (Notion, Canva, Asana and others) usable on mobile for paid plans | [alt-connectors-mobile] |
| 2025-07-31 | Drafting emails, messages, calendar invites from the mobile app | [alt-drafting-mobile] |
| 2025-08-11 | Search past chats (Max, Team, Enterprise at first; now all paid plans) | [hc-release-notes] [hc-memory] |
| 2025-09-03 | Calendar, location, maps (iOS and Android); reminders (iOS only) | [hc-release-notes] |
| 2025-09-11 | Memory (Team) and incognito chats (Free, Pro, Max, Team) | [hc-release-notes] |
| 2025-09-29 | File creation and editing on iOS/Android for paid plans, and on Pro | [hc-release-notes] |
| 2025-10-20 | Claude Code on the web plus iOS app: research preview for Pro and Max. CLI 2.0.24 added web-to-CLI teleport the same day | [blog-web] [9to5mac] [changelog] [npm] |
| 2025-10-21 | Artifacts gain MCP connectors and persistent storage | [blog-artifacts] |
| 2025-10-23 | Memory for Max (Pro over the following two weeks) | [hc-release-notes] |
| 2025-11-12 | Claude Code on the web research preview expanded to Team and Enterprise, from the browser and the iOS app | [x-claudeai-teament] |
| 2025-11-18 | CLI 2.0.45: start a message with `&` to send a background task to Claude Code on the web | [changelog] [npm] |
| 2026-01-07 | CLI 2.1.0 adds `/teleport` and `/remote-env` | [changelog] [npm] |
| 2026-01-12 | Health and fitness data on iOS and Android (Pro and Max, US only, beta) | [hc-release-notes] [mactrast-health] |
| 2026-02-23 to 02-25 | Remote Control: `claude remote-control` subcommand (CLI 2.1.51, Feb 23), research preview for Max announced Feb 24-25, expanded to more users in 2.1.58 (Feb 25) | [changelog] [npm] [decoder-rc] [helpnet-rc] |
| 2026-03-02 | Chat-history memory for all users, including Free | [hc-release-notes] |
| 2026-03-12 / 03-25 | Interactive charts inline (Mar 12); interactive apps rendered in the iOS/Android conversation (Mar 25) | [hc-release-notes] |
| 2026-03-17 | Dispatch research preview (Max first); persistent agent thread in the iOS/Android apps | [macstories-dispatch] [hc-release-notes] |
| 2026-03-20 | CLI 2.1.81: channel servers can forward tool-approval prompts to your phone | [changelog] [npm] |
| 2026-03-23 to 03-27 | Auto mode (classifier replaces permission prompts) enters research preview; PR auto-fix lands on the web | [whatsnew] |
| 2026-03-29/30 | Claude Code's creator says he writes much of his code from the iOS app | [boris-threads] [boris-thread] |
| 2026-04-13 to 04-17 | Mobile push notifications for Remote Control (CLI 2.1.110 added the push tool on Apr 15); Routines; Opus 4.7 with the `xhigh` effort level | [wn-w16] [changelog] [npm] |
| 2026-04-20 to 04-24 | Redesigned claude.ai/code with a sessions sidebar and drag-and-drop layout | [wn-w17] |
| 2026-06-25 | Trusted Devices for Remote Control (admins can require device verification) | [hc-release-notes] [rc-docs] |
| 2026-07-07 | Cowork on web and mobile (Max first); sessions run remotely so work continues with the laptop closed | [blog-cowork-mobile] [hc-release-notes] |
| 2026-08-04 | CLI 2.1.222 removes Ultraplan | [changelog] [npm] |
| 2026-08-17 to 08-21 | "Week 34" digest (CLI 2.1.234 to 2.1.239): device cards on the phone's Code tab, effort changes from the phone applied on your machine, and Remote Control "out of research preview". Several long-open phone issues (push for approvals, permission-mode switching, a Stop control, `gh` in cloud sessions) were closed as completed on Aug 17 | [wn-w34] [changelog] [npm] [gh-29319] [gh-29438] [gh-47127] [gh-14059] |
| 2026-09-16 | Cowork capabilities folded into every conversation; artifacts available on every plan | [hc-release-notes] |
| 2026-09-17 | Claude Code Projects redesign (beta) | [blog-projects] |
| 2026-09-22 | CLI 2.1.280: projects can run a thread on your own computer; Claude app diff-view fixes | [changelog] [npm] [projects-docs] |
| 2026-09-23 | Cloud sessions generally available | [blog-web] [aicoder-ga] |
| 2026-10-14 | iOS app 1.261013.20 released | [itunes-api] |
| 2026-10-15 | iOS app 1.261014.20 released (21:12 UTC) | [itunes-api] [appstore] |

---

## 3. Part A: Claude Code on the phone

Anthropic's own framing: Claude Code has no separate mobile app. The Claude app is a client for Claude Code sessions, not a place where code runs, and cloud sessions and Remote Control both live in the **Code** tab [mobile-docs]. Official marketing describes Remote Control on mobile as the way to send tasks from your phone to the Claude Code CLI [download].

### 3.1 Five ways to reach Claude Code from the phone

| Path | Where the code runs | Start a task from the phone? | Your computer must be on? | Plans | Launch / status |
|---|---|---|---|---|---|
| **Cloud sessions** | Anthropic-managed VM, or your org's self-hosted runner | Yes. Code tab, pick repo and branch, type the task [mobile-docs] | No | Pro, Max, Team; Enterprise with premium or Chat + Claude Code seats [web-docs] | Research preview 2025-10-20; GA 2026-09-23 [blog-web] |
| **Remote Control** | Your computer (CLI, Desktop app or VS Code) | Steer running sessions. Since Aug 2026 also start one from a "device card" for a machine running `claude remote-control` [wn-w34] | Yes: the `claude` process must keep running and the machine must be awake [rc-docs] | Pro and Max; Team and Enterprise only after an Owner turns it on [rc-docs] [avail-docs] | Research preview 2026-02-24/25 (Max); out of preview Aug 2026 [decoder-rc] [wn-w34] |
| **Dispatch** | Desktop app, through one persistent Cowork thread | Yes. Message a task; Dispatch decides whether to open a Code session [desktop-docs] | Yes: Desktop open and awake [hc-dispatch] | Pro and Max only [avail-docs] | Research preview 2026-03-17 [macstories-dispatch]; now limited beta, closed to new users [hc-dispatch] |
| **Projects (Claude Code)** | Cloud threads; one thread can run on your computer through Remote Control | Yes. Projects can be created and used in the iOS and Android apps [projects-docs] | Cloud threads: no. Local thread: yes [projects-docs] | Pro and Max beta; not Team or Enterprise [projects-docs] | Beta 2026-09-17 [blog-projects] |
| **Channels** (Telegram, Discord, iMessage) | Your CLI session | Through the chat app, not the Claude app | Yes | Pro and Max; Team and Enterprise need admin enablement [avail-docs] | Research preview [channels-docs] |

Official guidance on choosing: if your computer will be off, use cloud sessions or a project. Remote Control and Dispatch drive your own machine, so it must stay on [mobile-docs].

### 3.2 The Code tab: what the phone screen shows

**Entry and availability**
- Tap **Code** in the app navigation, or open `claude.ai/code/new` on the phone to start a new Code session inside the app [mobile-docs].
- Sign in with the same claude.ai account. Console API keys and Bedrock/Vertex/Foundry setups cannot reach cloud sessions or Remote Control [mobile-docs] [rc-docs].
- If the tab is missing, your plan or organization may not include these features [mobile-docs].

**Docs screenshot (Aug 2026)** [wn-w34]
- Header "Code". A **Devices** section with a "+" button and one chip per computer running `claude remote-control`, each with a green status dot.
- A **Sessions** list with an "All" filter dropdown. A row shows a status glyph, an auto-generated name in the form `hostname-adjective-noun`, a green "Connected" label with a laptop icon, and a relative age such as "5d".

**Marketing images (Oct 2026)** [itunes-api]
- Filter chips with counts: All, Blocked, In progress, Done.
- Date group headers such as "Today".
- Each row has: a status icon (spinner means running, a raised hand means waiting on you, a pull-request glyph means a PR is ready), a blue unread dot, a relative time, and a location line. Local Remote Control sessions show a laptop and "Connected". Cloud sessions show a cloud icon and `owner/repo`.
- A grey preview bubble shows the last message. PR numbers such as "#1234" appear in it.
- A blocked row has an inline **Approve** button, so a simple approval needs no navigation.
- On iPad the same list appears as one centered column with a menu button for the sidebar. None of the iPad marketing images shows a multi-pane layout [itunes-api]. An iPad user mentions a sidebar with Recents next to the Code tab, but does not say whether it stays open beside the content [gh-97737].
- Anthropic's own docs screenshot from August 2026 shows an "All" dropdown above the session list instead of filter chips [wn-w34]. Either the chips shipped after that screenshot, or they exist only in the marketing mock-up; I could not tell which. A user confirms that the Code tab list marks cloud, local and offline sessions with icons [gh-97734].

**Inside a session**
- The transcript streams live. Tool calls collapse into groups with a one-line label [changelog].
- On mobile Remote Control, assistant text written before or between tool calls is replaced by a short grey summary, with no way to turn that off (reported). Users say they cannot tell a summary from a failed answer [gh-97418].
- A context-usage figure is shown. A bug where it went stale after `/compact` or `/clear` was fixed in 2.1.280 [changelog].
- Docs describe a diff pane on connected devices [rc-docs], and the changelog mentions a diff view in the Claude app for Remote Control and cloud sessions without saying whether that is the phone or the Desktop app [changelog]. On the phone, Anthropic says `/diff` opens a "native diff sheet" [x-claudedevs-0821], and an iPhone user describes a "Diff +X -Y" badge above the response and PR-create area [gh-54228]. The sheet's layout is not documented (details in 3.8) (corrected 2026-10-15).
- Files Claude produces for you are now saved where the app can open them (2.1.280). Images in BMP, HEIC, HEIF, AVIF and TIFF get a preview (2.1.285) [changelog].
- A session waiting on a permission prompt shows a "Requires Action" state. Since 2.1.295 the status names an MCP tool by server and readable name [changelog].
- Composer: a "+" menu that includes **Permission** [perm-docs]; model and effort controls [rc-docs]; dictation [gh-61930]. A Stop control replaces send while a turn runs [projects-docs] [gh-47127]. A message sent mid-turn appears as small grey italic pending text until the turn ends, and (reported) is lost if you leave the screen [gh-73610].

**Session management**
- Renaming in the app updates the local session title used by `claude --resume` (fixed in 2.1.149) [changelog].
- Titles: auto-generated short names such as "Login button bug" since 2.1.234 [changelog]. Remote Control sessions start with a placeholder like `myhost-graceful-unicorn` until the first prompt (2.1.246) [rc-docs] [changelog].
- An **Archived** tab exists on iOS [gh-71616].
- Fork a session started with `--remote-control` from the app: the fork runs as a background session on your computer (CLI 2.1.273, 2026-09-15) [changelog] [npm].

### 3.3 Cloud sessions in detail

**What it is.** A Claude Code session on cloud infrastructure instead of your machine. It keeps running after you close the laptop, counts toward plan limits, and has no separate VM charge [web-docs].

**How a task runs** [web-qs]
1. Clone and prepare: the repo is cloned to an Anthropic-managed VM and your setup script runs.
2. Configure network by the environment's access level.
3. Work: Claude analyzes, edits, runs tests. You can watch and steer or walk away.
4. Push the branch. The session stays open, so PR creation and further edits happen in the same conversation.

**Start flow on the phone** [mobile-docs] [web-qs]
- Code tab, repository selector under the input box (multiple repositories allowed), permission mode, describe the task, submit. Each task gets its own session and branch.
- The docs say you choose a branch on the phone. A May 2026 regression report (app 1.260413.1) says the iPhone showed no base-branch selector while the Mac app did. That issue was closed "not planned" by a bot, so the current state is [unconfirmed: the mobile docs still say you pick a repository and branch (checked 2026-10-15); the last "same here" comment on the issue is from 2026-06-05, the stale bot closed it on 2026-07-12 and it is now locked, and no later issue or changelog entry mentions the selector; needs a check on a device] [gh-55500] [mobile-docs].
- Web prefill links: `claude.ai/code?prompt=...&repositories=owner/repo&environment=...`, plus `prompt_url` for long prompts [web-qs].
- From a terminal: `claude --cloud "task"` starts a cloud session from your GitHub remote and current branch (push first). The CLI shows a live setup checklist and queues messages you type while it provisions [web-docs]. With no GitHub remote, or without the GitHub App on the repo, it bundles and uploads the local repo instead (100 MB limit, with fallbacks) [web-docs].
- `claude -p "message" --cloud <session-id>` queues a follow-up into a running cloud session from any machine [web-docs].

**Permission modes** are Accept edits, Plan and Auto. Auto appears only when the organization allows it and the model supports it. There is no Manual and no Bypass in cloud sessions, and file edits are pre-approved regardless of mode [web-qs] [perm-docs].

**Running and steering** [web-docs] [cloudenv-docs]
- Watch progress, answer Claude's questions, redirect it.
- A message sent while Claude is working queues. On the web an "x" on the queued message takes it back and returns the text to the box.
- If Claude asks a question and the session sits idle, you can still answer until the environment expires.
- After a few minutes idle the VM pauses with files saved, and your next message restores it. If the VM was reclaimed, reopening builds a fresh one. The conversation is restored. Background work, such as subagents and shell commands, is not.
- Auto-compaction runs near the context limit. `/compact` and `/context` work; `/clear` does not (start a new session).
- Mobile quirk: in cloud sessions on the mobile app you cannot edit and retry a prompt that was flagged by a safety fallback; switch models or continue from a desktop browser [model-docs].

**The VM**: Ubuntu 24.04 on x86_64, 4 vCPUs, 16 GB RAM, 30 GB disk, Docker available [cloudenv-docs].

**Handoffs between terminal and cloud** [web-docs] [desktop-docs]
- Cloud to terminal (teleport): `claude --teleport` (picker) or `claude --teleport <id>`, `/teleport` or `/tp`, `/tasks` then `t`, or "Open in > Terminal" on claude.ai/code, which copies a command. It checks for a clean git tree (offers to stash), the same repository (not a fork), a pushed branch, and the same account.
- The terminal gets its own copy. New work there does not appear in the cloud session.
- Terminal to cloud is one-way: start a new `--cloud` session. The Desktop app can send a local session to the cloud from "Open in > Cloud", carrying the conversation over as a summary.
- The phone app has no documented teleport button. The documented routes run on a computer (`claude --teleport`, `/teleport`, `/tasks`, or "Open in > Terminal" on claude.ai/code), plus one in-session route: typing `/teleport` inside a cloud session makes Claude reply with the exact `claude --teleport <session-id>` command (needs Claude Code 2.1.223 or later in the session's environment), and the docs do not limit that to the browser [web-docs]. Anthropic's suggested flow is to start a session on the web or the phone, then run `claude --teleport` in your terminal [x-claudedevs-0424] (corrected 2026-10-15).

**Sharing, archive, delete** [web-docs]
- Team and Enterprise: Private or Team visibility. Pro and Max: Private or Public (any signed-in claude.ai user). Recipients see the latest state when they open the link, not live updates.
- Sessions can be archived (hidden from the default list) or deleted permanently.

**Security** [web-docs]: each session is an isolated VM; network is limited by default; git credentials and signing keys stay outside the sandbox behind a proxy. Organizations with Zero Data Retention, the HIPAA configuration, or customer-managed encryption keys cannot use cloud sessions. Organization IP allowlisting breaks Anthropic-hosted cloud sessions unless Anthropic exempts them.

**Launch and plans.** Research preview for Pro and Max on 2025-10-20 [blog-web] [9to5mac]. GA on 2026-09-23 for Pro, Max, Team, and Enterprise users with premium or Chat + Claude Code seats [blog-web]. At GA, @ClaudeDevs (an X account that describes itself as official updates for developers building with Claude) announced a one-time credit for existing subscribers to try cloud sessions: $100 on Pro, $250 on Max, separate from usage limits, for cloud sessions only, one per account, to be claimed by Oct 7, terms apply [x-claudedevs-ga] [aicoder-ga]. I did not find the credit on an Anthropic web page (blog-web, web-docs). Team and Enterprise users got the research preview on 2025-11-12, when @claudeai said Claude Code users on those plans could now run tasks from the browser and the Claude iOS app [x-claudeai-teament] (corrected 2026-10-15). On 2026-10-15 the Help Center's table of beta and research-preview features still listed "Claude Code web (CCR)" as a research preview, which looks stale next to the GA note [hc-beta].

### 3.4 GitHub connection and environments

**Connecting GitHub** [web-docs] [web-qs]
- Two methods. (1) Authorize the Claude GitHub App during claude.ai/code onboarding. (2) Run `/web-setup` in the CLI to send your local `gh` token to your account. Auto-fix and Projects need the GitHub App installed on the repo.
- Team and Enterprise: an Owner must enable the GitHub connector first. A separate "Quick setup" toggle turns on `/web-setup` and automatic Default-environment creation.
- GitHub credentials are encrypted on Anthropic's servers and never enter the VM. Git operations go through a proxy.
- GitHub Enterprise Server is supported on Team and Enterprise. GitLab and Bitbucket repos can be sent only as a local bundle, and the session cannot push back [web-docs].

**Environments** [cloudenv-docs] [web-qs]
- A saved configuration used wherever you start a cloud session: Desktop, the mobile app, claude.ai/code, `--cloud`, routines. You add and edit environments in the environment selector at claude.ai/code or in Desktop. The phone chooses among them.
- Pro and Max onboarding creates a **Default** environment with **Trusted** network access. Team and Enterprise see a "Create your first cloud environment" form unless Quick setup is on.
- Network access levels: **None**, **Trusted** (package registries, GitHub, cloud SDKs), **Full**, **Custom** (your own allowlist, optionally with the defaults). GitHub and MCP-connector traffic travel by separate paths.
- Environment variables are visible to anyone who uses the environment. **Network secrets** are API keys that Anthropic's proxy attaches to matching requests after they leave the VM, so the key never sits in the VM.
- Setup scripts run as root on the first session. If they finish in about five minutes, Anthropic snapshots the filesystem and reuses it; the cache rebuilds on changes or after about seven days. Heavy downloads belong in a SessionStart hook.
- Team and Enterprise can share environments (shown under an "Organization" heading) and route sessions to self-hosted runners [cloudenv-docs]. Self-hosted environments entered public beta in the Week 32 digest (Aug 3-7, 2026) [whatsnew].
- `gh` in cloud sessions: a Dec 2025 iOS user could not diagnose a failing GitHub Actions run because the session had no `gh` and could not create PRs. It was closed as completed on 2026-08-17: cloud sessions now include built-in GitHub tools, and `gh` can be installed from the setup script [gh-14059]. CLI 2.1.288 added a built-in `gh api` for images without `gh` [changelog].

### 3.5 Remote Control in detail

**What it is.** The phone (or claude.ai/code) becomes a window onto a Claude Code session that keeps running on your computer, so code execution, filesystem access, MCP servers and project config stay local [rc-docs].

**How it is started** [rc-docs] [desktop-docs]
- Server mode: `claude remote-control`. It asks a one-time "Enable Remote Control?" question, then stays running and prints a session URL. Press **Space** to toggle a QR code.
  - Flags: `--name`, `--remote-control-session-name-prefix` (default is the hostname), `--continue` and `--session-id` (resume within about four hours), `--spawn same-dir|worktree|session`, `--capacity N` (default 32), `--[no-]create-session-in-dir`, `--permission-mode`, `--chrome/--no-chrome`, `-d/--debug`, `--verbose`. Press `w` at runtime to toggle same-dir and worktree.
- Interactive: `claude --remote-control ["name"]` (alias `--rc`). You can type locally while the session is also reachable remotely.
- From an existing session: `/remote-control` or `/rc`. It carries over the current conversation. The panel shows the URL and a QR code and can disconnect.
- VS Code: `/remote-control` shows a "Remote Control" indicator; no QR or name argument.
- Desktop app: `/remote-control` or the session's Remote Control switch. A laptop icon in the toolbar shows connection state. Settings > Claude Code > **Connect new sessions to Remote Control** turns it on for every session.
- Auto-connect for every interactive session: `/config` > "Enable Remote Control for all sessions" or `remoteControlAtStartup` in user settings. A checked-in project file cannot turn it on, only off.
- If the phone lacks the app, `/mobile` (aliases `/ios`, `/android`) shows a QR code for claude.ai/mobile [rc-docs] [mobile-docs].

**How the phone connects** [rc-docs] [wn-w34]
- Scan the QR code, open the session URL, or open the Claude app, tap **Code**, and pick the session. Online sessions show a computer icon with a green dot.
- Since Aug 2026, any machine running `claude remote-control` shows up as a **device card** at the top of the Code tab. Tap it to pick a directory and start a new session there.
- The title is chosen in this order: the name you passed, then `/rename`, then the last meaningful message, then an auto-generated `host-adjective-noun` name.

**What the phone shows and can do** [rc-docs] [changelog]
- The conversation as it happens, including compaction progress and `/clear`. Subagent and dynamic-workflow progress appears, and you can stop them from the phone, which stops them on your machine.
- A diff pane (see 3.8), model and effort controls, a permission-mode dropdown, context usage, and a Stop control.
- `@` file-path autocomplete from your local project (since 2.1.113).
- Photos attach directly to your message, and Claude Code also saves each photo under `~/.claude/uploads/` and tells Claude the path. Other files are downloaded to the machine and passed as `@` references. If a file fails to download, Claude gets a note that some attachments did not arrive [rc-docs] [mobile-docs].
- Sessions can be forked from the app and renamed from the phone, which syncs the local title (see 3.2).
- Recent changelog fixes show what the loop handles: files of 30 to 35 MiB (2.1.299), messages with up to 20 attached files (2.1.287), a retry for files that Claude sends you (2.1.287), and streaming of replies in very long sessions (2.1.290 and 2.1.293) [changelog].

**Approvals.** Permission prompts and `AskUserQuestion` questions stay open until answered. Other forwarded dialogs expire after five minutes by default (`dialogExpiry`), then take their no-action default. The Fable usage-credits consent prompt is not forwarded to the phone, so an unanswered prompt ends the turn [rc-docs] [model-docs]. Many approval bugs are reported (see section 6).

**Security model** [rc-docs]
- The local process makes **outbound HTTPS only** and opens no inbound ports. It registers with the Anthropic API and polls for work. The server relays messages over a streaming connection.
- Multiple short-lived credentials, each scoped to one purpose and expiring independently. All traffic is TLS.
- The session transcript, including messages, replies and tool activity, is stored on Anthropic's servers while connected.
- Zero Data Retention and HIPAA organizations cannot enable it. `disableRemoteControl` turns it off per machine. Sandboxing is configured in settings, not by flag.
- **Trusted Devices** (beta; Pro, Max, Team, Enterprise): each browser, phone or desktop app enrolls its own credential shortly after a full sign-in, and the sign-in must be at most 18 hours old. After that a Face ID, Touch ID, Windows Hello or passkey prompt refreshes it. Anthropic stores only the device public key and metadata, not biometrics. Members can revoke devices at claude.ai/settings/account [rc-docs]. Team and Enterprise admins got the toggle on 2026-06-25 [hc-release-notes]. A project cannot run a thread on your computer while Trusted Devices is on [projects-docs].
- Requirements: claude.ai login (no API key or long-lived `setup-token`), no Bedrock/Vertex/Foundry, no `ANTHROPIC_BASE_URL` gateway, and feature-flag fetching must not be disabled [rc-docs].

**Limits and reconnection** [rc-docs] [changelog]
- One remote session per interactive process. Server mode serves many sessions from one process.
- If the laptop sleeps or the network drops, the process reconnects when it comes back. In server mode it gives up after about 10 minutes of outage and exits. In an interactive session it keeps retrying. After `Ctrl+C` you can resume server sessions for about four hours.
- Since 2.1.299, when the computer cannot be reached, your text stays in the input box and Send is disabled until it reconnects.
- Remote Control polls about once per 10 minutes while connected (2.1.70) [changelog].
- For SSH hosts, the docs advise running `claude` inside tmux or screen [rc-docs].

**Launch and plans.** Research preview for Max on 2026-02-24/25, announced as running locally, with the web and mobile apps acting as a window onto that local session [decoder-rc] [helpnet-rc]. Out of research preview in Aug 2026 [wn-w34]. Today: Pro, Max; Team and Enterprise admin-enabled [avail-docs].

### 3.6 Desktop-to-phone sync, Dispatch and Projects

**Sync basics.** Sessions persist across devices. A task started on a laptop is ready to review on the phone, and one started on the phone is waiting at the desk [mobile-docs].

**Desktop app** [desktop-docs] [projects-docs]
- A local Desktop session appears at claude.ai/code and in your Claude apps once Remote Control connects it. A laptop icon before the title shows state.
- Settings > Claude Code has **Connect new sessions to Remote Control**, **Use this computer from your phone and claude.ai** with a folder list, and **Keep this computer awake for Remote Control**. Closing a laptop lid counts as sleep.
- Archiving a session in Desktop also archives its Remote Control copy.
- Remote Control sessions hosted by Desktop or VS Code report their permission mode to phones, and their model to claude.ai/code, as they change (2.1.234) [changelog].
- A recent Desktop (Cowork) change: approval prompts while Remote Control is on now appear only when the work was started or steered from another device, and the approval card can turn Remote Control off for the session (Desktop v2.7032.0, 2026-09-22) [cowork-changelog].

**Dispatch** [desktop-docs] [hc-dispatch] [macstories-dispatch]
- One persistent Cowork conversation. You message a task from the phone, and Dispatch either opens a Code session when asked, or decides a task is development work (bug fixes, dependency updates, tests, PRs) and opens one itself. Research and documents stay in Cowork.
- The session appears in the Desktop Code tab with a **Dispatch** badge. You get a push when it finishes or needs approval.
- Setup: open Cowork, click Dispatch, "Get started", toggle file access and keep-awake, "Finish setup". MacStories paired by QR code and saw a Dispatch entry appear in the iOS sidebar.
- Requirements: Desktop app (macOS, Windows x64 or Linux) open and awake, the mobile app, Pro or Max. Not on Team or Enterprise. Computer-use approvals from Dispatch expire after 30 minutes.
- Anthropic's own warning: instructions from your phone can trigger real actions on your computer, and malicious content could cascade into hard-to-reverse actions [hc-dispatch].
- Reliability in the launch-day MacStories test: 6 of 13 tasks fully succeeded and 6 failed, which the author summed up as roughly a coin flip [macstories-dispatch]. Claude Code's creator says he uses it daily [boris-thread].

**Projects (Claude Code)** [projects-docs] [blog-projects]
- One long-running coordinator conversation plus worker threads. Each thread is usually a cloud session on its own branch that opens a PR when the work calls for it, and watches that PR with auto-fix on.
- The **Overview** pane groups threads: Ready for review, Waiting on you, Working, Landing, Idle, Resolved. It has Library, Pull requests and Routines tabs. A dot on the Overview button shows when something waits on you.
- A thread card can show buttons: **Resolve conflicts**, **Fix CI**, **Address comments**, **Merge it**, **Review PR**, **Create PR**. The first four send an instruction to the thread as a message from you.
- You can open any thread, read its transcript, steer it, answer its permission prompt, or press **Stop**. Telling the coordinator "go ahead" does not reach a thread waiting on an approval.
- **Work locally**: from the "+" menu you can ask for one thread to run on your computer. You pick a folder on an "Allow Claude to work in a folder on your device" card (optionally in a worktree) and click **Allow once**. This needs Claude Code 2.1.280 or later [projects-docs]. The launch post (Sep 17) still said local threads were "coming very soon" [blog-projects], so the docs moved faster than the post.
- New projects default to Opus on high effort for threads and low effort for the coordinator. Project settings show usage per thread and model. The enforced limit is 200 new threads per day across projects. A thread that hits the plan limit shows "Service is busy" and retries on its own.
- Phone notifications for projects are not documented. The docs say project notifications are desktop-only, and that in a browser you check the dot on the Overview button instead [projects-docs].
- Plans: Pro and Max beta, not Team or Enterprise [projects-docs].

### 3.7 Notifications, background work and Live Activities

**Remote Control push** [rc-docs] [wn-w16] [gh-29438]
- Two toggles in `/config`: **Push when Claude decides** (proactive pushes, such as a long task finishing) and **Push when actions required** (permission prompts and questions). There is no per-event configuration beyond these two.
- You can also ask in a prompt: "notify me when the tests finish". The push tool landed in CLI 2.1.110 on 2026-04-15 [changelog] [npm]. The "actions required" push was a long-standing top request and was closed as shipped on 2026-08-17 [gh-29438].
- Setup: install the app, sign in with the same account, allow notifications, enable in `/config`. If `/config` says "No mobile registered", open the Claude app so it refreshes its push token. iOS Focus modes and notification summaries can suppress or delay pushes.
- Presence-aware: pushes are skipped while you are typing in or focused on the connected terminal. A marker file (`CLAUDE_CLIENT_PRESENCE_FILE`) extends this to any time you are at the machine [rc-docs].
- Dispatch and Cowork send a push when a task finishes or needs your go-ahead [desktop-docs] [hc-cowork-mobile]. Routines have notification settings as well [changelog].

**What a push looks like.** The Dispatch marketing image shows lock-screen notifications titled "Claude responded" with the first lines of the reply as the body [itunes-api]. I found no evidence of Approve/Deny buttons on a lock-screen notification. A September 2026 feature request says the "input needed" push carries neither the question nor its options, so answering means unlocking and opening the app, and it asks for notification actions (open) [gh-95391].

**Live Activities and the Dynamic Island**
- Anthropic's release notes, docs and App Store listing do not mention Live Activities [hc-release-notes] [appstore].
- A GitHub report from Oct 11-12, 2026 describes a "Claude's reply / Thinking..." element on the Dynamic Island while a chat reply generates. It has a progress bar and a stop button, ignores the iOS Live Activities setting, and ends as "Task failed" when Background App Refresh is off. The reporter says Claude Code sessions never show it, even over 24 hours. The reporter guesses it is an iOS 26 continued-processing task rather than a Live Activity. That guess is unconfirmed, and the issue was labelled invalid for being in the wrong repo [gh-101173]. Reporters in the same thread say iOS Settings > Claude shows "Allow Live Activities" and "More Frequent Updates" switches, and that turning both off does not hide the element [gh-101173].
- So: **no Live Activity for Claude Code sessions** as far as anyone has reported. Third-party apps fill the gap, which suggests demand: the App Store listings of Agentfy: Claude Code Monitor, Codync and Lody advertise Live Activities or the Dynamic Island for agent status [appstore-3p]. I found no App Store app named ClaudeLive (corrected 2026-10-15).

**Apple Watch.** No first-party app. The supported-device list and the app page show no Watch entry [itunes-api] [appstore]. iOS can mirror notifications to a paired watch, and one reporter says Remote Control permission pushes arrive on the phone and, mirrored, on the Apple Watch [gh-96126].

**Background tasks.** Subagents and dynamic workflows running in a session are visible on the phone and stoppable from it [rc-docs]. Desktop has a Background tasks panel and the terminal has agent view; neither is documented on the phone [desktop-docs] [agentview-docs].

### 3.8 Review UI: diffs, comments, PRs, CI

**On the web** [web-qs] [web-docs]
- A diff badge such as `+42 -18` opens a diff view with a file list on the left and changes on the right. It compares against the session's base branch by default, and **Compare against** picks any other branch.
- Select a line, type feedback, press Enter. Comments queue and are bundled with your next message, so Claude receives each note together with its file and line.
- **Create PR** offers a full PR, a draft, or GitHub's compose page with a generated title and description.
- A CI status bar has an **Auto-fix** toggle. With it on, Claude watches the PR, investigates CI failures and review comments, pushes a fix when the fix is clear, and asks you when a comment is ambiguous. Replies on GitHub go out under your username, labelled as Claude Code. GitHub sends no webhook for merge conflicts, so Claude cannot react to those alone.
- Diffs are computed from raw git blobs, so repo diff drivers are ignored [web-docs].
- Cloud sessions can also be pointed at an existing PR URL and told to auto-fix it, and `/autofix-pr` does that from a terminal [web-docs] [wn-w15].

**On the phone**
- Docs say a connected device's diff pane shows your changes. On a branch ahead of the default branch it shows everything since the split, including uncommitted edits; otherwise only uncommitted changes [rc-docs]. Changelog entries mention a diff view in the Claude app for Remote Control and cloud sessions: a fix for a branch's committed files being dropped when uncommitted changes exist (2.1.280), and a fix for deleted and renamed files showing as modified on claude.ai and the Desktop app (listed under 2.1.300, needs 2.1.296 or later on your machine) [changelog]. Those entries do not say whether the phone shares that view. Anthropic's Remote Control update of 2026-08-21 says `/diff` sent from the phone "opens the native diff sheet" [x-claudedevs-0821], and an April 2026 iPhone report describes a "Diff +X -Y" badge above the response and PR-create area that summed every edit instead of showing the git state (closed as a duplicate) [gh-54228]. The sheet's layout is still undocumented (corrected 2026-10-15).
- Inline line comments on the phone diff: [unconfirmed: the cloud-session docs describe selecting a line in the diff view to leave a comment without naming a surface, and the quickstart shows it in the browser; no doc, Anthropic post or GitHub issue mentions comments in the phone's diff sheet. Checked web-docs, web-qs, rc-docs, @ClaudeDevs posts since April 2026, and GitHub searches for "diff" with iOS or mobile] [web-docs] [web-qs].
- A Create PR control exists on iOS. In Feb-Mar 2026 users said it appeared only sometimes and that PR creation failed because the environment had no GitHub API authentication. That gap was closed on 2026-08-17 [gh-14059].
- Auto-fix from the phone: ask Claude to watch the PR and fix CI failures and review comments as they arrive [web-docs].
- Approval prompts on the phone show only about the first 100 characters of a command, with no way to expand, scroll or copy the rest, and Edit/Write diffs are truncated the same way. This was reported in March 2026 [gh-37235] and again on 2026-08-14 against the then-current App Store build [gh-86704]. The stale bot closed both "not planned", and no fix is recorded in the changelog (corrected 2026-10-15).
- Project thread cards carry PR actions (see 3.6) [projects-docs].
- Code review products: `/ultrareview` (cloud multi-agent review) entered research preview in Week 17 [wn-w17]; GitHub Code Review is Team and Enterprise [avail-docs]. Reopening a finished ultrareview session in the Claude app was fixed in 2.1.271 [changelog].

### 3.9 Plan mode and permission modes on the phone

| Mode | Cloud sessions | Remote Control (from the phone) |
|---|---|---|
| Manual (config value `default`) | Not offered. File edits are pre-approved, shown as "Accept edits" | Offered |
| Accept edits | Offered | Offered |
| Plan | Offered | Offered |
| Auto | Offered if the org allows it and the model supports it | Offered if the session meets auto-mode requirements |
| Bypass permissions | Not available | Cannot be selected from the app |

Sources: [mobile-docs] [perm-docs] [web-qs].

- To switch on the phone: tap **+** in the prompt box, then **Permission**. The dropdown mirrors the mode of the local session, including a mode set from the terminal with Shift+Tab, and updates when it changes in either place. The sync fixes landed between CLI 2.1.202 (July 2026) and 2.1.234 (Aug 2026) [perm-docs] [changelog] [gh-29319].
- Plan mode: Claude reads files, runs exploratory commands and writes a plan, with edits blocked until you approve. The cloud docs describe Plan as Claude proposing an approach and waiting for your approval before it edits [perm-docs] [web-qs]. In the terminal, approval offers three choices: "Yes, and use auto mode", "Yes, manually approve edits", "No, keep planning" [perm-docs]. How these appear on the phone is not documented. A user report describes an "Approve plan" button in the app [gh-35637].
- Reported plan problems on the phone: plans that cannot be accepted (open since Feb 2026) [gh-28330]; the iPhone spinning with no plan text or buttons when a plan awaits approval on the desktop [gh-33967]; the phone's "Approve plan" sending an unqualified approval that ignores `defaultMode: "auto"` [gh-35637].
- Auto mode: a classifier model reviews actions instead of you. It was a research preview in March 2026, became the default for new sessions on Pro, Max and Team from 2026-08-14 [whatsnew] and the built-in default in terminal and VS Code from CLI 2.1.283 [perm-docs]. Projects threads run in auto mode when the model supports it [projects-docs].
- Mode drift: users report the phone pushing a bypass-permissions host back to prompting and being unable to restore it from the phone (open, 85 reactions) [gh-29214].
- Ultraplan (cloud plan drafting with a web editor) is gone [ultraplan-docs].

### 3.10 Slash commands from the phone

Commands that only work in the terminal UI, such as `/plugin` and `/resume`, do not work from the phone [rc-docs] [mobile-docs]. What does work [rc-docs]:

| Group | Commands |
|---|---|
| Text-output commands | `/compact`, `/clear`, `/context`, `/usage`, `/exit`, `/usage-credits`, `/recap`, `/reload-plugins` (only when the session runs in an interactive terminal) |
| Argument forms instead of pickers | `/model <name>`, `/effort <level>`, `/fast`, `/color`, `/rename`, `/autocompact <size>` (2.1.221), `/advisor <model\|off>` (2.1.260), `/output-style <name>` (2.1.269, built-in styles only), `/focus on\|off` (2.1.281) |
| Partial | `/mcp` returns a text summary on mobile (a connector directory on web); `reconnect`, `enable`, `disable` work; `/config key=value` sets a setting on mobile, and bare `/config` lists keys (on the web it opens settings) |
| Not available | `/claude-api` typed from mobile or web |

- A connector that needs re-authorization cannot be fixed from the phone's `/mcp` panel. You run `claude mcp login "claude.ai Slack" --no-browser` on the host, open the printed link, then `/mcp reconnect` [rc-docs].
- A line starting with `!` sent from the phone goes to Claude as a message and does not run in shell mode [rc-docs].
- A regression where a server-injected `<system-reminder>` prefix broke slash commands from mobile and web is open (14 reactions) [gh-68038].
- `/context` output once rendered blank on mobile clients (fixed in 2.1.267) [changelog].
- Cloud sessions support text-output commands only, with the same argument forms for `/model`, `/effort`, `/color`, `/rename`, and `/fast` [web-docs].

### 3.11 Model, effort and related controls

- **Model.** Picking a model from the phone's model control applies to that session only. Sending `/model <name>` from the phone to an interactive session also changes your default for new sessions. Needs Claude Code 2.1.238 or later [rc-docs]. Sessions started from the Claude app now honor the chosen model (fixed in 2.1.257) [changelog].
- **Effort.** A control on the phone sets the level on your machine (needs 2.1.234+). If `CLAUDE_CODE_EFFORT_LEVEL` is pinned on the host, the host refuses other picks. Levels: low, medium, high, **xhigh** (new with Opus 4.7), max. Defaults vary by model, for example Opus 5.5, Sonnet 5.5 and Haiku 5.5 default to medium, and Fable 5.1 to high [rc-docs] [model-docs]. Moving the effort picker shows a "Change effort?" confirmation on iOS (reported) [gh-99489].
- **Ultracode.** A separate on/off setting (since 2.1.284) that makes Claude orchestrate dynamic workflows of many subagents at any effort level. Reported bug: the iOS effort picker shows "Extra" instead of Ultracode and reverts the choice within seconds, because the phone sends Ultracode as an effort level that the CLI maps to `xhigh` [gh-99489] [model-docs].
- **Fable and credits.** Fable models may bill to usage credits. The picker then shows "Requires usage credits", and an interactive session asks for consent. Remote Control, background sessions and agent teams wait five minutes by default for an answer and then end the turn without sending the request [model-docs] [rc-docs].
- **Fast mode** (`/fast`) works from the phone when your account has it [rc-docs] [web-docs]. The `/advisor` command also works.
- **Thinking.** The chat model menu has a "Thinking" (or "Extended") toggle separate from effort. It cannot be turned off on the newest models (Haiku 5.5, Sonnet 5.5, Opus 5.5, Fable 5.1, Opus 5) [hc-effort].

### 3.12 Multiple parallel sessions

- **Cloud**: each task gets its own VM and branch, and you can start many. They share your plan's rate limits, so parallel work burns usage faster [web-docs] [web-qs].
- **Projects** add a coordinator that starts and tracks threads (see 3.6) [projects-docs].
- **Remote Control server mode** runs up to 32 concurrent sessions per process. `--spawn worktree` gives each on-demand session its own git worktree, and `same-dir` shares one folder [rc-docs].
- **Agent view** (`claude agents`) is one terminal screen for every background session, with states Working, Needs input, Idle, Completed, Failed and Stopped, Haiku-written one-line headlines, a peek-and-reply panel, and per-session worktrees. It is a research preview and is terminal-only [agentview-docs]. Not on the phone: its docs describe it only as a terminal screen opened with `claude agents`, and the mobile and Remote Control docs do not mention it [agentview-docs] [mobile-docs] [rc-docs].
- **Routines** run scheduled, API-triggered or GitHub-triggered cloud sessions. Each run appears as a session alongside your others [routines-docs].
- The agent-view docs warn that ten parallel agents use quota roughly ten times as fast [agentview-docs].

### 3.13 Other Code-adjacent features that touch the phone

- **Attachments** (above). Limits are not published for the Code composer. Changelog fixes imply the apps accept up to 20 files per message and files of 30 to 35 MiB [changelog].
- **Voice dictation** exists in the Code composer. The help center says dictation, but not voice mode, is available in Code and Cowork [hc-voice] [gh-61930]. The terminal's `/voice` is separate and does not run in cloud sessions [voicecli-docs].
- **Routines** (Pro, Max, Team, Enterprise; research preview since Week 16). Create at claude.ai/code/routines, from Desktop, or with `/schedule`. The docs list only these three surfaces, so phone creation is not documented [routines-docs]. A July 2026 user comment says routines have no presence in the mobile app beyond push notifications, with no in-app list, so the user opens claude.ai/code/routines in a mobile browser instead [gh-18189].
- **Channels permission relay**: channel servers that declare the capability can forward tool-approval prompts to your phone through Telegram, Discord or iMessage. Anyone on the sender allowlist can approve or deny, so allowlist carefully (CLI 2.1.81, 2026-03-20) [channels-docs] [changelog]. Claude Code's creator described a personal hook that routes permission prompts to WhatsApp [boris-thread].
- **Artifacts from Claude Code**: Claude can publish a live page to claude.ai for diffs with annotations, dashboards and plan comparisons. Sessions served by `claude remote-control` can publish them (2.1.281). Published Code artifacts do not appear in the iOS Artifacts tab, which has no Code section; you must open the URL in a browser (reported, open, 36 reactions) [artifacts-docs] [gh-78792].
- **Mods** (server-driven UI): in VS Code and the desktop and mobile apps, a tree drawn above the question dialog can hold Markdown and up to 48 rows (2.1.301). One report says mod UI is not drawn in the iOS view of a Remote Control session [changelog] [gh-99217].
- **Desktop iOS Simulator pane** (public beta, Week 30) lets Claude run and tap through an iOS app on a Mac. It is a desktop feature, not on the phone [whatsnew].

---

## 4. Part B: the general chat app

Each entry gives what it is and how it behaves, launch date, and plan availability.

### 4.1 Chat basics, streaming and rich in-chat cards

- **UX.** Sidebar button top-left, new-chat button and "..." menu top-right. The composer has "+", a model pill, a mic and a send arrow. Replies stream in [itunes-api] (marketing image). Changelog fixes for replies that appeared a block at a time in very long sessions show that streaming is the intended behavior [changelog].
- **Stop and progress.** While a chat reply generates, a Dynamic Island element with a progress bar and a stop button is reported. It is not documented by Anthropic (see 3.7) [gh-101173].
- **Rich cards seen in marketing images** [itunes-api]:
  - File chips on the user's message (a photo thumbnail plus "DOC" and "PDF" chips with filenames) and a generated-file card ("All About Minnie, Presentation, PPTX").
  - An interactive map with rating pins and place cards (name, rating, review count, cuisine) for a restaurant search. The help article says Claude can show suggested places on an interactive map and open directions in Apple Maps [hc-ios-apps].
  - An email draft card with an A/B toggle between tone variants ("Warm and gracious", "Confident and concise") and separate Subject and Body fields.
  - An interactive flashcard app in a full-height sheet with a close "X" and "..." menu, on both iPhone and iPad.
- **Interactive charts** inline in replies (2026-03-12) and **interactive apps** rendered inside the conversation on iOS and Android (2026-03-25) [hc-release-notes].
- **Edit and retry** exist in claude.ai and cloud sessions [changelog], but on mobile cloud sessions you cannot edit and retry a flagged prompt [model-docs].
- **Launch:** app 2024-05-01 [itunes-api]. **Plans:** all, including Free [pricing] [download].
- Message actions on iOS such as copy, regenerate or read-aloud are not documented in the Help Center (checked its sitemap and its iOS collection) [hc-sitemap] [hc-ios-collection]. Branching a conversation from an earlier point is documented as unavailable in the new unified experience [hc-one-claude]. A request for read-aloud of Remote Control replies on the phone was closed "not planned" in October 2026 [gh-88495] (corrected 2026-10-15).

### 4.2 Model picker, extended thinking and effort

- **UX.** A menu next to the send button, labelled with the current model name. Tap it, pick a model, or choose "More models". You can change model, effort or thinking at any point, and the change applies from the next reply [hc-effort]. Marketing images show the pill in the composer [itunes-api].
- **Models named in the help article:** Haiku 5.5, Sonnet 5.5, Opus 5.5, Fable 5.1, Opus 5, Sonnet 5, Fable 5, Opus 4.7, Opus 4.6, Sonnet 4.6 (Opus 4.8 appears in the effort list) [hc-effort].
- **Effort levels:** Low, Medium, High, Extra high (xhigh, built for long coding and agentic work, Opus 4.7 and newer), Max. Each model has a "Default" marker. Higher effort uses more tokens and hits limits sooner [hc-effort].
- **Thinking** is a separate toggle (labelled "Extended" on older models). It cannot be turned off on Haiku 5.5, Sonnet 5.5, Opus 5.5, Fable 5.1 or Opus 5 in Claude [hc-effort].
- **Admin control:** Enterprise admins can disable models or effort levels per role and set the starting model and effort [hc-effort].
- **Voice mode** starts on your last-used model and moves to the newest generation of it. Fable is not available in voice mode [hc-voice].
- **Launch/plans:** the article gives no dates or per-plan mapping. Effort and thinking controls are available to all plans, with model access varying by plan and admin settings [hc-effort]. The mobile steps are not documented separately: the article gives one set of steps (click the model name next to the send button) without naming a surface [hc-effort].

### 4.3 Projects (chat)

- **What it is.** A self-contained workspace with its own chat history, uploaded knowledge, and instructions. Free users can create up to five projects. Paid plans get retrieval that stretches knowledge capacity up to 10x. Team and Enterprise can share a project with "Can view" or "Can edit" permissions [hc-projects].
- **Memory** is separate per project, and you can isolate a project by turning off "Use account memory" [hc-memory].
- **On mobile.** The Cowork-on-mobile article lists projects among features that work on web, desktop and mobile [hc-cowork-mobile]. Whether you can create a project from the phone is not documented: the Help Center's creation steps are web steps (claude.ai/projects, then "+ New Project") [hc-create-projects]. An iOS bug report says Cowork tasks are missing from the project view (open) [gh-96284].
- **Launch:** Projects launched on 2024-06-25 for Claude.ai Pro and Team users [anthropic-projects] (corrected 2026-10-15). Team and Enterprise project sharing 2025-08-01 [hc-release-notes]. The redesigned Claude Code Projects are described in 3.6 [blog-projects].
- **Plans:** all users for chat Projects (Free limited to five) [hc-projects].

### 4.4 Artifacts: viewing and running on mobile

- **What it is.** Significant self-contained content that opens beside the chat: a document, deck, design, dashboard or small interactive tool. Artifacts are saved in the **Artifacts** tab of the sidebar [hc-artifacts].
- **On iOS and Android.** Ask for a design, deck or doc in any chat, then view and edit it in the Artifacts tab. **Sharing settings cannot be changed on mobile**; use the web or Desktop [hc-artifacts]. Marketing images show an interactive flashcard app running in a full-height sheet [itunes-api].
- **Interactive, AI-powered artifacts** can call Claude. No API keys; each viewer signs in with their own account and their own usage counts [hc-artifacts].
- **Connectors and storage** in artifacts are described as available on web and desktop for Pro and up. Storage is limited to 20 MB of text per artifact [hc-artifacts]. Whether they run on mobile is not stated; both availability lines name only web and Desktop [hc-artifacts].
- **Code artifacts** published from Claude Code do not appear in the iOS Artifacts tab (reported, open) [gh-78792].
- **Launch:** iOS and Android 2025-07-21; Team and Enterprise 2025-07-31; MCP and persistent storage 2025-10-21 [blog-artifacts]. Docs, Slides and Design templates and the "legacy artifact" split date from 2026-09-16 [hc-artifacts] [hc-release-notes].
- **Plans:** create artifacts in chat on all plans including Free; Docs, Slides and Design on all plans; Dashboards (beta) Pro and up; Motion (beta) Team and Enterprise; connecting apps and storing data Pro and up; Enterprise defaults for Docs, Slides and Design turn on 2026-10-15 [hc-artifacts].

### 4.5 Uploads: files, photos, camera and documents

- **UX.** Tap "+" and choose "Add files or photos" [hc-upload]. Attachments show as chips with a thumbnail or a type label [itunes-api]. On the web you can also drag, drop and paste images [hc-upload].
- **Camera.** The widget's camera button and the "Analyze Photo with Claude" control start a photo capture for analysis [hc-intents]. In voice mode the "+" adds camera, photo or file input mid-conversation [ppc-voice].
- **Types:** PDF, DOCX, CSV, TXT, HTML, ODT, RTF, EPUB, JSON, XLSX (XLSX needs code execution and file creation); images JPEG, PNG, GIF, WebP [hc-upload].
- **Chat limits:** 500 MB per file, 20 files per chat, images up to 8000 by 8000 pixels, PDFs up to 1000 pages (visual analysis up to 100 pages, text only beyond that). **Project limits:** 30 MB per file [hc-upload].
- Mobile-specific limits and picker sources (Files, Photos, Drive) are not documented. The upload article gives one set of steps ("Add files or photos", then choose files from your device) and one set of limits, without naming a surface [hc-upload].
- **File creation and editing.** Claude can create and edit Excel, PowerPoint, documents and PDFs (2025-09-09), extended to Pro and to iOS and Android on paid plans (2025-09-29) [hc-release-notes]. Marketing: "Turn ideas into downloadable files" [itunes-api].

### 4.6 Voice mode and dictation

- **Voice mode UX** [hc-voice] [ppc-voice]
  - Tap the sound-wave icon next to the microphone in the text field and pick a voice. Speak; tap the up arrow to send; tap the stop square to interrupt Claude.
  - **Hands-free** (default): continuous listening, Claude answers at natural pauses. **Push-to-talk**: hold a button while speaking, recommended for noisy places.
  - Voices are a limited preset list, which the help article says prevents voice cloning. The settings button at bottom-left sets voice and pace.
  - Key points appear on screen as Claude speaks. Transcripts are saved to chat history. You can switch between voice and text in the same chat.
  - Voice mode can use web search and connected tools (Gmail, Calendar, Docs, Slack); some results cannot be shown on screen.
  - Language is set in Settings > General > Voice > Language. Non-English support is beta.
  - It counts toward normal usage limits. Voice mode uses more battery.
  - Enterprise owners can disable it by contacting Support.
  - In the new unified experience voice mode works in any conversation, including ones where Claude is running a task [hc-voice].
- **Dictation** converts speech to text in the composer. The widget's microphone button opens the app straight into dictation [hc-intents]. Dictation (not voice mode) is available in Cowork and Claude Code [hc-voice].
- **Launch:** voice mode beta on iOS and Android on 2025-05-27, English only, five preset voices [ppc-voice]. **Plans:** all plans, Free through Enterprise [hc-voice]. One press piece reports roughly 20 to 30 voice messages for free users at launch [ppc-voice], and Anthropic's own help article said the same at launch: free users could expect about 20 to 30 voice messages before reaching session limits [hc-voice-2025]. The current article gives no number [hc-voice].
- **Known bug:** after a long dictation in the Code tab, the keyboard can cover the Send button, and leaving the screen wipes the transcript (reported) [gh-61930].

### 4.7 Web search

- **UX.** On the web, "+" then "Web search" with a check mark; it can be turned off the same way. Every answer includes citations. With search on, Claude can fetch full pages from URLs you supply. Image results are included. In the new unified experience there is no toggle, because Claude searches when it judges it helpful [hc-websearch]. Mobile steps are not documented; the article's steps name no surface [hc-websearch].
- **Launch:** preview for paid US users on 2025-03-20; all plans, globally, on 2025-05-27 [blog-websearch].
- **Plans:** all plans. Team and Enterprise need an Owner to enable it first. Free-plan limits reset every five hours and search and fetch both count [hc-websearch].

### 4.8 Research

- **What it is.** Claude runs several searches that build on each other and decides what to look up next. It uses the web and, on web and desktop, your connected tools. It needs web search on [hc-research].
- **On mobile**, Research searches **only the web** and skips your connectors, with no error or warning. Start it on web or desktop to include connectors [hc-research].
- It runs on Claude Opus 5.5, falling back to Opus 4.8, whatever model the chat uses. It can use limits faster than normal chats [hc-research].
- **Launch:** early beta 2025-04-15 for Max, Team and Enterprise, in the US, Japan and Brazil [blog-research]; reported on mobile 2025-05-16 [alt-research-mobile]. **Plans:** paid plans (Pro, Max, Team, Enterprise) [hc-research].

### 4.9 Connectors, MCP and integrations on mobile

- **UX.** Connected apps are available on web, desktop and mobile. In a chat, tap "+" then **Connectors** and toggle each one for this conversation. Claude may ask before a tool runs: **Allow once** or **Always allow**. Per-tool permissions are Always allow, Needs approval, or Blocked [connectors-docs].
- **What mobile supports.** Remote connectors. Local connectors (desktop extensions) and local MCP servers are desktop-only. The connectors page lists interactive "MCP Apps" for the web [connectors-docs], while the release notes say the iOS and Android apps can render interactive apps in the conversation since 2026-03-25 [hc-release-notes]. The Help Center says you can browse the Connectors Directory and connect a new service in Claude for iOS and Android, that installing connectors on mobile is in beta, and that web and Desktop remain the primary path for custom connectors [hc-connectors] (corrected 2026-10-15). The connectors page places the directory at Customize > Connectors on web and desktop [connectors-docs].
- **Marketing image** shows connector tiles: Slack, Asana, Canva, HubSpot, Google Drive, Figma, Google Calendar, Notion, Gmail [itunes-api].
- **Voice mode and Free plans:** Free can connect one tool; paid plans can connect more [hc-voice].
- **Claude Code reuse.** Cloud sessions and Remote Control sessions use the connectors on your claude.ai account. In a cloud thread, "+" then **Connectors** shows them; turning one off there saves as your account default [projects-docs] [connectors-docs].
- **Launch:** remote MCP connectors on iOS and Android for paid plans, reported 2025-07-28 [alt-connectors-mobile]. **Plans:** connectors work across plans, with a one-tool limit on Free in voice mode; Team and Enterprise owners add connectors for the org [connectors-docs] [hc-voice].

### 4.10 Using iOS apps and data from a chat

This is the most native-feeling part of the app [hc-ios-apps]. The article is dated 2026-08-25.

| Area | What Claude can do | Limits |
|---|---|---|
| Messages | Draft texts that open in Messages, WhatsApp, Messenger or Signal for you to send | Cannot read existing messages |
| Mail | Draft emails that open pre-filled in Mail, Gmail or Outlook | Cannot read existing email |
| Calendar | Check availability, find free slots, create and edit events | Editing depends on who owns the event |
| Reminders | Add and manage items, due dates, priorities, notes, recurring tasks | Cannot create or edit reminder lists |
| Location | Use your location for nearby suggestions when relevant | Team and Enterprise members cannot use it for now |
| Maps | Show suggested places on an interactive map and open directions in Apple Maps | Depends on location and map access |
| Health | Read activity, workouts, vitals, body measurements, sleep, nutrition; show trends in native charts | Pro and Max, US only, beta, read-only |
| Contacts | Not supported | No direct access |

- **How it feels.** Claude offers an app action as a card or prompt in the conversation. For messages and email you tap the card, review the draft in the target app, and send it yourself. Permissions are asked when needed with **Allow once**, **Always allow** or **Don't allow**, and managed in Settings > Claude (Health in Settings > Health > Data Access & Devices > Claude). Actions stay in the conversation history. Health data is not saved to memory unless you enable sensitive topics [hc-ios-apps].
- **Launch:** drafting emails, messages and calendar invites on mobile 2025-07-31 [alt-drafting-mobile]; location, maps, calendar and reminders (reminders iOS only) 2025-09-03 [hc-release-notes]; Health 2026-01-12 (Pro and Max, US) [hc-release-notes] [mactrast-health].
- **Plans:** all plans, except Health (Pro and Max) and Location (not Team or Enterprise) [hc-ios-apps].

### 4.11 Memory, incognito and chat search

- **Memory UX** [hc-memory]
  - Claude saves memory as individual Topics during chats. You read, edit or delete them in Settings > Memory, or tell Claude in chat to remember or forget something.
  - **Pause memory** keeps existing entries but stops using and creating them. **Reset memory** deletes everything, including project memory.
  - To keep one chat out of memory, turn off "Memory" in the "+" menu before sending the first message. On mobile the switch stays visible but locked afterwards.
  - Each project has its own memory. Sensitive topics (health, race, religion, politics and similar) are not saved unless you opt in.
  - Mobile needs the latest app version.
- **Incognito chats.** Tap the ghost icon in a new chat. It is not saved to history or memory and Claude will not search it. Available on all plans [hc-memory]. Incognito chats still open in the previous experience and cannot create files or run code [hc-one-claude].
- **Search and reference past chats.** Claude searches earlier chats and shows the searches as tool calls with citations. Paid plans only (Pro, Max, Team, Enterprise), on web, Desktop and the mobile apps. Switch it off under Settings > Memory > "Search and reference chats" [hc-memory]. A phone UI for searching chat history yourself is not documented. The new-experience article says search covers your chats and new conversations but not older Cowork tasks, without naming a surface [hc-one-claude].
- **Launch dates** [hc-release-notes]: search past chats 2025-08-11 (Max, Team, Enterprise); memory for Team and incognito for Free, Pro, Max, Team 2025-09-11; Enterprise memory 2025-09-18; Max 2025-10-23 (Pro next); chat-history memory for all users 2026-03-02; categorized-entry memory 2026-07-10; shared across chat and cloud Cowork with Topics 2026-08-25.
- **Plans:** Free, Pro and Max on by default; Team and Enterprise owners enable it, and it is off for each member until they opt in [hc-memory] [hc-release-notes].

### 4.12 Styles (being retired)

- Earlier, a "Use style" menu offered Normal, Concise, Formal and Explanatory, plus custom styles built from a writing sample. Anthropic's Help Center article "Styles are moving to skills" (dated 2026-06-01; web-archive copy of 2026-07-10) says custom styles migrate automatically to skills that arrive disabled under Customize > Skills, the Concise, Explanatory and Formal defaults are removed, Learning survives as a skill, and the styles menu goes away once the migration is complete [hc-styles-wb]. The live article URL now returns HTTP 404 [hc-styles].
- Launch date and mobile availability of styles: styles launched on 2024-11-26 for all Claude.ai users [anthropic-styles-wb] (corrected 2026-10-15). Neither the launch post nor the archived help articles mention the mobile apps, so mobile availability is [unconfirmed: no source names the apps; checked the 2024 launch post and help-article copies from 2025-07-08 and 2026-07-10].
- Claude Code has its own **output styles**, with a built-in Concise style (2026-08-17 to 08-21) selectable from the phone with `/output-style` for built-in styles only [wn-w34] [rc-docs].

### 4.13 Widgets

- **UX.** A Claude widget with three buttons: **Chat** (new conversation), **Microphone** (opens straight into dictation) and **Camera** (take a photo to analyze). Add it to the Home Screen or Today View. Widget sizes are not specified. Widget interactions count toward your usage limit [hc-intents].
- **Launch:** reported 2025-01-22 [onlinemarketing-widget]. **Plans:** all, requires the app; the help article says iOS 18 or later [hc-intents].

### 4.14 App Intents, Siri, Shortcuts, Spotlight and the Share sheet

- **"Ask Claude" intent.** Use it from Spotlight (type "Ask Claude"), Siri (say "Ask Claude" and it asks for the message), the Share menu (send selected text), or any app that supports intents. It runs without opening the app and uses the default model shown when you open Claude [hc-intents].
- **Shortcuts.** "Ask Claude" is an action you can chain with other actions. The help article walks through a "Summarize with Claude" shortcut that can be added to the Share Sheet [hc-intents].
- All of these count toward your usage limit [hc-intents].
- **Launch:** not stated by Anthropic. The help article describing the "Ask Claude" intent and Shortcuts already existed on 2024-12-18, its earliest web-archive copy [hc-intents-wb]. **Plans:** all; iOS 18 or later [hc-intents].

### 4.15 Lock Screen, Control Center and Action button

- **Controls** [hc-intents] [hc-lockscreen]
  - **Analyze Photo with Claude**: a control for Control Center or the Lock Screen that sends a picture to Claude.
  - **Open Claude**: add it to one of the two bottom circular Lock Screen slots, to Control Center, or to the **Action button** (Settings > Action Button > Controls > Choose a Control > Open Claude). Hold the button to open the app.
- **Requirements:** iOS 18 or later. Device models are not listed [hc-lockscreen]. **Plans:** all. **Launch:** not stated by Anthropic. The help article existed on 2025-03-13, its earliest web-archive copy [hc-lockscreen-wb].

### 4.16 Apple Watch

- No first-party Apple Watch app. The listing's supported-device data has no Watch entry, and the App Store page lists only iPhone and iPad under Compatibility [itunes-api] [appstore]. Notifications can mirror to a paired watch by default iOS behavior, and one user reports Remote Control permission pushes arriving on the phone and the watch [gh-96126]. I found no Anthropic watch features in the Help Center's iOS collection, the Claude Code docs or the changelog [hc-ios-collection] [mobile-docs] [changelog].

### 4.17 iPad

- **Facts.** One universal app that needs iPadOS 18.0 or later. The Claude Code docs tell iPad users to install the same iOS app [mobile-docs] [hc-install-ios] [itunes-api]. The Code tab and sessions open on iPad; a crash on iPadOS 26.5 when opening any Code session (build 1.260618.0) was fixed in a later build [gh-70144].
- **Not documented** (checked 2026-10-15 in the Help Center's iOS collection, the Claude Code mobile docs, and GitHub issue searches for Stage Manager, Split View and iPad keyboard shortcuts) [hc-ios-collection] [mobile-docs]: Stage Manager support, Split View and Slide Over behavior, a multi-pane layout, external-keyboard shortcuts, and Pencil input. App Store marketing images show the phone layout as one centered column on iPad, and a Claude Code session list in a narrow column [itunes-api]. I saw no evidence of a native iPad sidebar-and-detail layout.

### 4.18 Accessibility

- The App Store listing says the developer has not indicated which accessibility features the app supports [appstore]. I found no Anthropic accessibility statement for the iOS app. Anthropic's accessibility pages cover the Claude Code terminal [a11y-docs] and keyboard and screen-reader use of artifacts in a browser [hc-a11y-artifacts]. A user request (Aug 2026) asking Anthropic to confirm that the mobile Remote Control view works with VoiceOver and TalkBack was closed "not planned" by the stale bot [gh-88495].
- Claude Code in the terminal has a screen-reader mode for VoiceOver and NVDA (Week 29), which does not apply to the app [whatsnew].
- One user found that iOS Accessibility voice commands let them copy dictated text out of the Code composer after a keyboard bug [gh-61930] (anecdote).

### 4.19 Offline behavior

- I found no Anthropic statement about offline behavior; the Help Center has no article on it (sitemap checked 2026-10-15) [hc-sitemap]. Replies are generated on Anthropic's servers and finish even when the app is in the background (user report) [gh-101173], so a connection is presumably required.
- Documented reconnect behaviors for Code sessions: after a connection drop, cloud sessions catch up by showing missed activity all at once (2.1.295); when a Remote Control computer cannot be reached, your text stays in the box and Send is disabled until it reconnects (2.1.299) [changelog].
- Unsent drafts are reported to be lost when you navigate away from a session or when the app is backgrounded in some cases [gh-73610] [gh-63975].

### 4.20 Notifications in the chat app

- The App Store "Dispatch" image shows lock-screen notifications titled "Claude responded" with the reply text as the body [itunes-api]. Users in a bug thread confirmed that chat-completion and Dispatch-reply notifications worked while Claude Code pushes did not [gh-30592].
- Cowork and Dispatch push when a task is done or needs your input [hc-cowork-mobile] [desktop-docs].
- iOS Focus modes and notification summaries can delay Claude pushes; check Settings > Notifications > Claude [rc-docs].
- A user report says the app vibrates at the end of every response even with in-app haptics and System Haptics off [gh-101173].

### 4.21 Cowork and Dispatch on mobile

- **Cowork on mobile** (2026-07-07, Max first): open Cowork from the app sidebar. Sessions run in the cloud, so work continues with the laptop closed and scheduled tasks run with no device online. When Claude reaches a decision only you can make, the question reaches your phone and nothing ships until you approve [blog-cowork-mobile] [hc-cowork-mobile].
- **Plans:** cloud Cowork for Pro and Max; Team and Enterprise are beta. Tasks that need local files, the built-in browser or computer use need the Desktop app open [hc-cowork-mobile].
- **Folded into every conversation** on 2026-09-16: no mode to pick, tasks appear in Recents alongside chats, and the Code tab and model picker stay where they were [hc-one-claude].
- **Persistent agent thread** on iOS and Android for managing Cowork tasks (2026-03-17) and **Dispatch** are in 3.6 [hc-release-notes].
- From 2026-10-06, new Pro and Max Cowork tasks run in the cloud and the "Only on your computer" option was removed [hc-cowork-mobile].

### 4.22 Other app-level facts

- **Languages:** English plus 33 [appstore].
- **Privacy:** incognito and memory controls above; Health data is read-only and not saved to memory by default [hc-ios-apps].
- **Sharing a chat.** Sharing with specific people is not available from the mobile app: the help article says this is not yet available and is dated 2026-09-04 [hc-share-people]. Public links (Free, Pro, Max) show a snapshot without attached files; whether the iOS app can create one is not stated [hc-share-public] [hc-share]. Artifact sharing settings also cannot be changed on mobile [hc-artifacts].
- **Usage and billing:** in-app subscriptions and usage credits are sold through Apple (section 1) [appstore].

---

## 5. Patterns worth copying in a native iOS client for a coding agent

"Evidence" lines are cited facts about Claude. Lines starting "Mine:" are my recommendations, not facts. Where I mention opencode specifics, they come from the sibling files `02-opencode-features.md` and `03-mobile-clients-landscape.md` in this folder.

### 5.1 Information architecture

1. **A triage-first session list.**
   Evidence: the Code tab filters by state (All, Blocked, In progress, Done) with counts, shows a state glyph, unread dot, repo or computer line, last-message preview, and an inline Approve button on blocked rows [itunes-api]. The terminal's agent view colors a linked PR number by status [agentview-docs].
   Mine: sort "needs you" above everything. Derive state from server events (opencode emits `permission.asked`, `form.created`, `session.status` and `session.idle`).
2. **Host cards with live status.**
   Evidence: a Devices section with a chip per computer and a green dot; tap it, pick a directory, start a session; `--spawn worktree` gives each session its own worktree [wn-w34] [rc-docs].
   Mine: show each paired opencode server with reachability and version, and offer "New session in directory" with a worktree switch.
3. **Make location obvious.** Evidence: a cloud icon plus `owner/repo` versus a laptop plus "Connected" on every row [itunes-api]. Mine: tag each row with server name and directory so sessions from different machines never blur together.

### 5.2 Approvals, questions and trust

4. **Treat every blocking prompt as a durable record.**
   Evidence: permission prompts and `AskUserQuestion` stay open until answered; other forwarded dialogs expire after five minutes to a no-action default [rc-docs]. When prompts fail to render, the session looks hung (30 reactions, open), and a user proposes a prompt record with an ID, owning surface, delivery state and outcome [gh-35637].
   Mine: render from server state, never from terminal output. Show "waiting on you" even when details fail to load. Never let silence become approval.
5. **Show the whole command and diff before approving.**
   Evidence: iOS prompts show only the first ~100 characters, and users say this makes the app nearly unusable for that purpose (reported in March and again in August 2026, both closed as not planned) [gh-37235] [gh-86704].
   Mine: an expandable monospace sheet with working directory, files touched and copy. Keep Allow once, Allow always and Reject visibly distinct.
6. **Let the user pick the scope of an approval.**
   Evidence: connector tools offer Allow once, Always allow, Needs approval and Blocked [connectors-docs]. A WebFetch prompt that offers only per-domain approval drew a request for "allow all domains" [gh-95617].
   Mine: put a scope picker (this call, this command pattern, this domain, this session) in the approval sheet.
7. **A permission-mode control that mirrors the host.**
   Evidence: "+" then Permission; it reflects the host's mode, including changes made with Shift+Tab, and Bypass cannot be selected from the phone [perm-docs] [mobile-docs]. Reported drift is a top complaint (85 reactions) [gh-29214].
   Mine: the host is the source of truth. Show the mode in the header and confirm before any escalation.
8. **Presence-aware prompting.**
   Evidence: pushes are skipped while you are focused on the terminal, and a marker file extends that [rc-docs]. The Desktop app now asks for approval during Remote Control only when the work was started or steered from another device [cowork-changelog].
   Mine: use opencode's viewed/idle events as presence so the phone is not pinged while you are at the keyboard.
9. **Step-up security for remote steering.**
   Evidence: Trusted Devices enrolls each device, requires a sign-in no older than 18 hours, and refreshes with Face ID, Touch ID or a passkey [rc-docs]. Dispatch's help article warns that phone instructions can trigger hard-to-reverse actions [hc-dispatch].
   Mine: require biometrics for approvals that touch shell, network or outside-workspace paths, and for changing modes.
10. **Out-of-band approvals** through chat apps exist as an opt-in, with a warning that anyone on the allowlist can approve [channels-docs]. Mine: skip until the core flow is solid.

### 5.3 Steering and input

11. **Queue, take back, and Stop.**
    Evidence: a message sent mid-run queues, an "x" takes it back [web-docs], Stop replaces Send while a turn runs [projects-docs], and Stop interrupts like Esc, so queued messages continue [gh-47127]. Pending text appears in small grey italics [gh-73610].
    Mine: also offer "send now (steer)" versus "send after this turn".
12. **Never lose what the user typed.**
    Evidence: unsent prompts are lost when you swipe back or switch sessions, even when idle (reported, open) [gh-73610] [gh-63975]. A long dictation can be wiped by leaving the screen [gh-61930].
    Mine: persist a draft per session and per server, restore after backgrounding, and warn before discarding.
13. **Slash commands as text, plus native controls.**
    Evidence: only text-output and argument-style commands work from the phone, and pickers and sliders are replaced by arguments [rc-docs]. A native model and effort control exists as well [rc-docs].
    Mine: offer a command palette limited to mobile-safe commands, and native pickers for model, effort and agent.
14. **Voice that understands code.**
    Evidence (terminal dictation): tuned for coding vocabulary, with the project name and git branch added as recognition hints; hold-to-talk or tap-to-send; auto-submit only when the transcript has at least three words; recording stops after 15 seconds of silence or two minutes; Esc cancels [voicecli-docs]. Mobile counterpart: dictation in the composer, voice mode for chat [hc-voice].
    Mine: pass repo, branch and file names as recognition context; keep Send reachable after dictation.
15. **Attachments that reach the agent.**
    Evidence: photos go to the model directly and are saved at a path Claude can copy; other files land on the host and become `@` references; a partial failure leaves a note saying some attachments did not arrive; `@` autocomplete is served from the host's project [rc-docs] [mobile-docs] [changelog].
    Mine: mirror all four behaviors.

### 5.4 Review and shipping

16. **A short path from "done" to "PR".**
    Evidence: a diff badge (`+42 -18`), file list, **Compare against**, inline comments that queue and ride along with your next message, and **Create PR** as full, draft or GitHub compose page [web-qs]. A CI status bar with **Auto-fix** [web-docs]. Project cards add Fix CI, Address comments, Merge it, Review PR [projects-docs].
    Mine: design the phone diff around one file at a time with hunk navigation, a comment sheet, and a per-file "reviewed" mark. Claude's own phone diff layout is undocumented, so there is room to lead.
17. **Show PR and CI state on the list row** so triage needs no tap [agentview-docs] [itunes-api].

### 5.5 Connection and reliability

18. **Outbound-only host connections with QR pairing.**
    Evidence: the host makes outbound HTTPS only, registers and polls; short-lived, single-purpose credentials; QR or URL to connect [rc-docs]. Mine: opencode V2 already has `opencode pair` with a QR code and an OpenTunnel relay (see `03-mobile-clients-landscape.md`).
19. **Honest reconnect states.**
    Evidence of good behavior: when the host is unreachable, your text stays in the box and Send is disabled until it reconnects; after a drop, a cloud session shows missed activity all at once [changelog].
    Evidence of bad behavior: a reconnect budget (reportedly 3 per hour and 72 per day) that stops retrying while the phone still shows "reconnecting" (open, 109 reactions) [gh-34255].
    Mine: show connected, reconnecting (attempt n), offline since a time, with a manual button. Back off but never give up. Use opencode's durable session log for catch-up.
20. **Tell the user how the host stays awake.** Evidence: "Keep this computer awake for Remote Control", and the warning that closing a lid counts as sleep [projects-docs] [desktop-docs].

### 5.6 Notifications and system presence

21. **Two tiers of push.**
    Evidence: "Push when actions required" (permission prompts, questions) and "Push when Claude decides" (the agent chooses, for example when a long task ends); you can ask in a prompt: "notify me when the tests finish" [rc-docs].
    Mine: add a per-session mute and a quiet-hours option.
22. **Test and show push health.** Evidence of failure modes: "No mobile registered" [rc-docs]; "Mobile push requested" with nothing arriving on Android [gh-87003]; pushes for prompts a hook already auto-approved [gh-96126]; no sound or vibration on iOS [gh-53709]. Mine: a "send test push" button and a last-delivered timestamp.
23. **Go beyond Claude: Live Activities, Watch, actionable notifications.** Evidence: Claude shows no Live Activity for Code sessions [gh-101173] and has no Watch app [itunes-api]. A lock-screen push carries reply text but I found no Approve or Deny actions, and a user request for notification actions is open [itunes-api] [gh-95391]. Mine: a Live Activity per running session with Stop, actionable Approve and Deny behind Face ID, and mirrored Watch notifications. See `03-mobile-clients-landscape.md` section 3.2 for who else ships these.
24. **System entry points.** Evidence: a widget with Chat, Microphone and Camera; an "Ask Claude" App Intent usable from Siri, Spotlight, Shortcuts and the Share sheet; "Open Claude" and "Analyze Photo" controls for Lock Screen, Control Center and the Action button [hc-intents] [hc-lockscreen]. Mine: the same set, with "New task in this project" and "Approve next request" as intents.

### 5.7 Session lifecycle, cost and scale

25. **Short auto-titles, rename sync, fork, archive.** Evidence: titles like "Login button bug"; renames sync back; fork a session from the app; archived tab [changelog] [gh-71616]. Mine: opencode V2 has `session.fork` and rename but no archive call (see `02-opencode-features.md` A.1), so archive locally.
26. **Handoffs and links.** Evidence: `claude --teleport` checks for a clean tree, correct repo, pushed branch and same account; prefill URLs carry prompt, repository and environment; `claude.ai/code/new` opens a new session in the app [web-docs] [web-qs] [mobile-docs]. Mine: a universal link and App Intent that start a session with a prompt, directory and agent.
27. **Per-session model and effort with a "Default" marker, plus a context meter.** Evidence: [hc-effort] [rc-docs] [changelog]. Failure: the iOS effort picker snapping back to "Extra" because of a mismatch between app and host (open) [gh-99489]. Mine: always read the effective value back from the host and show it.
28. **Calm rate-limit states.** Evidence: a thread at the plan limit shows "Service is busy" and says it will continue automatically, with Stop available [projects-docs]; "auto-continue when limits reset" appears on Desktop [whatsnew]. Mine: map provider retry events to the same calm banner.
29. **Parallel work with an overview.** Evidence: Overview groups (Ready for review, Waiting on you, Working, Landing, Idle, Resolved), per-thread usage, a cap of 200 new threads per day [projects-docs]. Mine: group across servers and projects, and show per-session cost.

### 5.8 Extensibility and honesty

30. **Server-driven UI blocks** that render natively: Claude Code "mods" can draw a Markdown tree above the question dialog in the mobile apps (up to 48 rows) [changelog]. One report says mod UI is not drawn in iOS Remote Control views [gh-99217]. Mine: define a small, versioned set of renderable blocks.
31. **Name the limits in the UI.** Evidence: the docs say Bypass permissions cannot be selected from the app [mobile-docs]; mobile Research silently skips connectors [hc-research]; mobile summaries replace assistant text with no label (reported) [gh-97418]. Mine: whenever the phone does less than the desktop, say so inline.

---

## 6. Known user pain points

Counts are GitHub reactions and comments on 2026-10-15 [gh-search]. "Open" and "closed" refer to the issue state that day. The `anthropics/claude-code` tracker is also where iOS and Remote Control bugs are filed, because the iOS app has no public tracker [gh-101173].

### 6.1 Ranked by evidence

| # | Pain point | Evidence | Status |
|---|---|---|---|
| 1 | **Remote Control drops and does not recover.** Phone shows "reconnecting" or "active" while the host is dead; only a manual disconnect and reconnect on the host fixes it | [gh-34255] 109 reactions, 72 comments; [gh-28571] 54; [gh-28758] "session not connecting" 38; analysis in the thread shows a reconnect budget of 3 per hour and 72 per day, and idle expiry on the server | Open; no Anthropic reply visible on [gh-34255] |
| 2 | **Permission prompts and questions that never reach, or never render on, the phone.** The session looks hung and the host waits | [gh-35637] 30; [gh-28508] AskUserQuestion answers not received by the CLI, 27; [gh-28330] cannot accept plan mode, 15; [gh-33625] and [gh-33967] similar | Mostly open |
| 3 | **Mode drift and prompts despite bypass.** The phone keeps asking even when the host runs with bypass permissions, or silently drops to a stricter mode | [gh-29214] 85 reactions, 32 comments | Open |
| 4 | **Silent mid-turn hangs** that only a local Esc fixes. Triggers named: running `/compact` from the remote, a subagent finishing seconds after a turn ends, long MCP calls | [gh-51267] 18 reactions, 17 comments | Open |
| 5 | **Push notification gaps.** No push for approvals (shipped Aug 2026), pushes missing or silent, pushes for prompts that were auto-approved | [gh-29438] 69; [gh-30592] 34; [gh-53709]; [gh-87003]; [gh-96126] | Mixed |
| 6 | **Crashes in the Code tab.** Tapping a Remote Control session closes the app; an iPad crash opening any session; a crash when the environment button is tapped while a Remote Control server is registered | [gh-70182] 24; [gh-70108]; [gh-70382]; [gh-70262] (iOS 27 beta 2); [gh-70144] (iPad); [gh-65926] | Several closed; one confirmed fixed by a later build [gh-70144]; others not checked |
| 7 | **Lost input.** Unsent prompts discarded on navigation; a long dictation wiped, with the keyboard covering Send | [gh-73610]; [gh-63975]; [gh-61930] | Open or closed "not planned" |
| 8 | **Truncated approval content** (about 100 characters of a command, diffs cut off) | [gh-37235]; re-reported against the App Store build of 2026-08-14 [gh-86704] | Both closed "not planned" by the stale bot; no fix recorded |
| 9 | **Gaps versus desktop and web.** No base-branch selector on iPhone (regression); cannot start a session on your Mac (partly answered by device cards in Aug 2026); no "allow all domains"; published Code artifacts missing from the iOS Artifacts tab; prompt suggestions not shown; mobile summaries replace assistant text; new sessions auto-archive; Cowork tasks missing from the project view; no way to delete old sessions | [gh-55500]; [gh-57904]; [gh-95617]; [gh-78792] (36 reactions); [gh-97410]; [gh-97418]; [gh-71616]; [gh-96284]; [gh-50496] | Mixed |
| 10 | **GitHub and environment errors**: "GitHub repository access check failed" on a Remote Control environment | [gh-44805] 31 reactions | Open |
| 11 | **Effort and mode controls that disagree with the host** | [gh-99489] | Open |
| 12 | **Live Activity annoyances**: the chat "Thinking" island ignores the iOS setting, shows "Task failed" on success with Background App Refresh off, and a reported vibration after every reply | [gh-101173] | Open, labelled invalid |
| 13 | **Reliability of Dispatch**: 6 of 13 tasks fully succeeded in the launch-day test; now closed to new users | [macstories-dispatch] [hc-dispatch] | Legacy |
| 14 | **Usage and context limits in the merged app**: one report says the merged Claude app runs Opus 4.6 at 200K context on Max 5x while the help center says 500K, with about 92K of fixed overhead | [gh-100502] 11 reactions (title only; I did not open the thread) | Open |
| 15 | **Price**: in-app Max and annual Pro prices are above web prices | [appstore] [pricing] | Observed |
| 16 | **App Store review sample** (four visible reviews): one reports login loops and an error screen after an update; another reports account bans and unanswered support email | [appstore] | Anecdotal |

### 6.2 Process and product-shape pain points

- **No public tracker for the iOS app.** Bugs go to the Claude Code repo, and one was labelled "invalid" for being in the wrong place [gh-101173]. Several phone issues were closed "not planned" by a stale-bot with no maintainer reply, for example [gh-55500], [gh-57904], [gh-37235] and [gh-61930]. A wave of issues was closed as completed by an Anthropic collaborator on 2026-08-17 [gh-29438] [gh-29319] [gh-47127] [gh-14059].
- **Too many overlapping surfaces and names** (cloud sessions, Remote Control, Dispatch, Projects, Channels, Cowork, plus renames). This is my synthesis from sections 0.2 and 3.1, not a sourced complaint.
- **Parallel work burns plan usage fast**, and the Projects docs say a project uses limits faster than a single session, especially on Pro [projects-docs] [agentview-docs].
- **Competitors' phone starts.** One commenter says Codex's mobile app can start sessions on configured machines, which Claude lacked in May 2026 [gh-57904]. OpenAI's docs confirm that the phone can start new chats in projects on a connected host [codex-remote]. Claude added device cards in Aug 2026 [wn-w34].
- **Feature request: CarPlay** for Claude Code (2 reactions, open) [gh-101123].

---

## 7. Appendix: what I could not verify (open questions)

These were open at research time and worth testing on a real device or asking Anthropic. The verification pass of 2026-10-15 (last section) answered items 10 to 14 and part of items 1, 3, 4, 5 and 9; each answered item ends with a short note.

1. How the diff looks on an iPhone, and whether inline line comments work on the phone [rc-docs] [changelog]. Partly answered: `/diff` opens a "native diff sheet" [x-claudedevs-0821]; its layout and inline comments are still undocumented.
2. Whether the iOS composer today has a base-branch selector (docs say yes; a May 2026 regression report says no) [mobile-docs] [gh-55500].
3. Whether the phone can trigger teleport or "Open in terminal" [web-docs]. Partly answered: no teleport button is documented; typing `/teleport` in a cloud session returns the command to run on a computer [web-docs].
4. Whether Live Activities exist for any Code session type, and whether the chat "Thinking" island is a Live Activity at all [gh-101173]. Partly answered: reporters say Code sessions never show the island and that iOS Settings lists Live Activities switches for Claude [gh-101173].
5. Whether lock-screen notifications carry Approve or Deny actions [itunes-api]. Partly answered: a user says the "input needed" push carries no question, options or actions, and asks for them [gh-95391].
6. iPad layout beyond the marketing images: Stage Manager, Split View, external keyboard shortcuts [itunes-api].
7. Accessibility: VoiceOver, Dynamic Type, Switch Control behavior; the listing declares nothing [appstore].
8. Offline behavior and draft persistence for plain chat [gh-73610].
9. How to start Research or Web search on the phone in the unified experience [hc-research] [hc-websearch]. Partly answered: in the new experience Research starts with `/deep-research` or "+" then "Research", and web search has no toggle; no phone-specific steps [hc-one-claude].
10. Whether you can add a new connector from the phone [connectors-docs]. Answered: yes, in beta [hc-connectors].
11. Where "Styles" stands: the Help Center and blog pages returned HTTP 404 when I tried them [hc-styles]. Answered: the archived article confirms the move to skills [hc-styles-wb]; styles launched 2024-11-26 [anthropic-styles-wb].
12. Team and Enterprise launch dates for cloud sessions, and the removal date of Ultraplan [web-docs] [ultraplan-docs]. Answered: Team and Enterprise 2025-11-12 [x-claudeai-teament]; Ultraplan removed in CLI 2.1.222 on 2026-08-04 [changelog] [npm].
13. The $100 and $250 cloud-session "try credits" (secondary source only) [aicoder-ga]. Answered: announced by @ClaudeDevs on 2026-09-23 [x-claudedevs-ga].
14. Phone notifications for Projects threads and routines [projects-docs] [routines-docs]. Answered: project notifications are desktop-only per the docs [projects-docs]; routines send push notifications (CLI 2.1.292 fixed a bug that turned them off) [changelog] [gh-18189].
15. Whether the iOS app has any local on-device features (on-device speech or models). Nothing in the docs suggests it.

---

## 8. Appendix: Sources

Every bracketed key in this report resolves to a URL below. I opened pages with WebFetch unless a row says otherwise. Local sibling files are cited by name: `02-opencode-features.md` and `03-mobile-clients-landscape.md` in this folder.

### 8.1 Claude Code documentation (code.claude.com)

| Key | URL | What it is |
|---|---|---|
| rc-docs | https://code.claude.com/docs/en/remote-control | Remote Control: start modes, flags, what devices see, security, Trusted Devices, push, limits, commands from mobile |
| web-docs | https://code.claude.com/docs/en/claude-code-on-the-web | Cloud sessions: GitHub auth, teleport, review, auto-fix, sharing, security, limits |
| web-qs | https://code.claude.com/docs/en/web-quickstart | Cloud quickstart: connect GitHub, environments, start a task, prefill URL, review and create a PR |
| mobile-docs | https://code.claude.com/docs/en/mobile | Claude Code on mobile: Code tab, the four ways to reach sessions, limitations |
| projects-docs | https://code.claude.com/docs/en/claude-projects | Claude Code Projects: coordinator, threads, Overview pane, run a thread on your computer, limits |
| cloudenv-docs | https://code.claude.com/docs/en/cloud-environments | Cloud environments: access levels, secrets, setup scripts, VM spec, time limits |
| perm-docs | https://code.claude.com/docs/en/permission-modes | Permission modes, plan mode, auto mode, web and mobile tab (+ then Permission) |
| desktop-docs | https://code.claude.com/docs/en/desktop | Desktop app: Dispatch sessions, Remote Control visibility, cloud, diff review, PR monitoring |
| avail-docs | https://code.claude.com/docs/en/feature-availability | Feature availability by plan and provider |
| channels-docs | https://code.claude.com/docs/en/channels | Channels (Telegram, Discord, iMessage) and permission relay; research preview |
| routines-docs | https://code.claude.com/docs/en/routines | Routines: schedules, API and GitHub triggers; research preview |
| artifacts-docs | https://code.claude.com/docs/en/artifacts | Share session output as artifacts |
| agentview-docs | https://code.claude.com/docs/en/agent-view | Agent view (terminal): states, peek and reply, background sessions |
| voicecli-docs | https://code.claude.com/docs/en/voice-dictation | Voice dictation in the CLI (hold or tap; coding vocabulary) |
| ultraplan-docs | https://code.claude.com/docs/en/ultraplan | Notice that Ultraplan was removed |
| model-docs | https://code.claude.com/docs/en/model-config | Model lineup, effort levels, Ultracode, Fable and usage credits, mobile notes |
| a11y-docs | https://code.claude.com/docs/en/accessibility | Claude Code screen-reader mode and accessibility settings (terminal only; added 2026-10-15) |
| whatsnew | https://code.claude.com/docs/en/whats-new/index | Weekly digest index (Weeks 13 to 37) |
| wn-w15 | https://code.claude.com/docs/en/whats-new/2026-w15 | Week 15 (Apr 6-10, 2026): Ultraplan, /autofix-pr |
| wn-w16 | https://code.claude.com/docs/en/whats-new/2026-w16 | Week 16 (Apr 13-17, 2026): mobile push notifications, Routines, Opus 4.7 |
| wn-w17 | https://code.claude.com/docs/en/whats-new/2026-w17 | Week 17 (Apr 20-24, 2026): claude.ai/code redesign, /ultrareview |
| wn-w34 | https://code.claude.com/docs/en/whats-new/2026-w34 | Week 34 (Aug 17-21, 2026): device cards on the phone, Remote Control out of research preview; includes the phone Code-tab screenshot |
| changelog | https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md | Claude Code changelog (downloaded and searched locally; also at code.claude.com/docs/en/changelog) |
| npm | https://registry.npmjs.org/@anthropic-ai/claude-code | npm registry metadata; the release timestamps map CLI versions to dates |

### 8.2 Anthropic pages (claude.com)

| Key | URL | What it is |
|---|---|---|
| blog-web | https://claude.com/blog/claude-code-on-the-web | Launch post of 2025-10-20 with an update note dated 2026-09-23 (cloud sessions GA) |
| blog-projects | https://claude.com/blog/projects-redesigned | Projects redesign, 2026-09-17 |
| blog-cowork-mobile | https://claude.com/blog/cowork-web-mobile | Cowork on web and mobile, 2026-07-07 |
| blog-artifacts | https://claude.com/resources/articles/build-artifacts | Artifacts update notes: iOS/Android 2025-07-21; MCP and storage 2025-10-21 |
| blog-websearch | https://claude.com/blog/web-search | Web search: 2025-03-20 preview, all plans 2025-05-27 |
| blog-research | https://claude.com/blog/research | Research launch, 2025-04-15 |
| pricing | https://claude.com/pricing | Plans and prices |
| cc-product | https://claude.com/product/claude-code | Claude Code product page (surfaces, plans, Max 5x and 20x prices) |
| download | https://claude.com/download | Official description of the mobile apps and Remote Control positioning |
| connectors-docs | https://claude.com/docs/connectors/overview | Connectors: where they work (mobile supports remote connectors), permissions |
| cowork-changelog | https://claude.com/docs/cowork/changelog | Claude Desktop (Cowork) changelog; v2.7032.0 approval change |
| anthropic-projects | https://www.anthropic.com/news/projects | Projects launch post, 2024-06-25, for Claude.ai Pro and Team (added 2026-10-15) |
| anthropic-styles-wb | https://web.archive.org/web/20241126180354/https://www.anthropic.com/news/styles | Styles launch post of 2024-11-26, web-archive copy; the live URL returns HTTP 404 (added 2026-10-15) |

### 8.3 Help Center (support.claude.com)

| Key | URL | What it is |
|---|---|---|
| hc-release-notes | https://support.claude.com/en/articles/12138966-release-notes | Claude apps release notes, Aug 2025 to Oct 2026 |
| hc-intents | https://support.claude.com/en/articles/10263469-using-claude-app-intents-shortcuts-and-widgets-on-ios | App Intents, Shortcuts, widget, Analyze Photo control |
| hc-lockscreen | https://support.claude.com/en/articles/10302511-accessing-claude-app-on-ios-lock-screen-control-center-and-action-button | Lock Screen, Control Center, Action button |
| hc-ios-apps | https://support.claude.com/en/articles/11869619-use-claude-with-ios-apps | Messages, Mail, Calendar, Reminders, Location, Maps, Health on iOS |
| hc-install-ios | https://support.claude.com/en/articles/9266462-install-claude-for-ios | iOS and iPadOS 18.0 requirement; Claude for Intune |
| hc-voice | https://support.claude.com/en/articles/11101966-use-voice-mode | Voice mode and dictation |
| hc-effort | https://support.claude.com/en/articles/8664678-change-the-model-effort-and-extended-thinking-settings | Model menu, effort, thinking |
| hc-memory | https://support.claude.com/en/articles/11817273-use-claude-s-chat-search-and-memory-to-build-on-previous-context | Chat search, memory, incognito |
| hc-styles | https://support.claude.com/en/articles/10181068-configuring-and-using-styles | Styles article. It returned HTTP 404 when I opened it; the migration-to-skills claim comes from a search excerpt only |
| hc-artifacts | https://support.claude.com/en/articles/9487310-what-are-artifacts-and-how-do-i-use-them | Artifacts, mobile notes, plans |
| hc-upload | https://support.claude.com/en/articles/8241126-upload-files-to-claude | Upload types and limits |
| hc-research | https://support.claude.com/en/articles/11088861-use-research-on-claude | Research, mobile limitation |
| hc-websearch | https://support.claude.com/en/articles/10684626-enable-and-use-web-search | Web search |
| hc-share | https://support.claude.com/en/articles/10593882-share-and-unshare-chats | Share and unshare chats |
| hc-share-people | https://support.claude.com/en/articles/16762496-share-a-chat-with-specific-people | Sharing with specific people; not available on mobile |
| hc-share-public | https://support.claude.com/en/articles/16762437-public-links-for-shared-chats | Public links for shared chats |
| hc-projects | https://support.claude.com/en/articles/9517075-what-are-projects | Chat Projects and the new project model |
| hc-cowork-mobile | https://support.claude.com/en/articles/15520349-use-claude-cowork-on-web-desktop-and-mobile | Cowork on web, desktop and mobile |
| hc-dispatch | https://support.claude.com/en/articles/13947068 | Dispatch (assign tasks from anywhere in Cowork): limited beta, setup, warning |
| hc-one-claude | https://support.claude.com/en/articles/16761823-claude-cowork-and-chat-are-one-claude | Cowork and chat merged into one Claude |
| hc-connectors | https://support.claude.com/en/articles/11176164-use-connectors-to-extend-claude-s-capabilities | Connectors: browse the directory and connect a service on iOS and Android (beta) (added 2026-10-15) |
| hc-create-projects | https://support.claude.com/en/articles/9519177-how-can-i-create-and-manage-projects | Creating and managing chat projects (web steps) (added 2026-10-15) |
| hc-beta | https://support.claude.com/en/articles/14503520-available-beta-and-research-preview-features | Table of beta and research-preview features (added 2026-10-15) |
| hc-a11y-artifacts | https://support.claude.com/en/articles/17457950-use-artifacts-with-a-keyboard-or-screen-reader | Keyboard and screen-reader use of artifacts in a browser (added 2026-10-15) |
| hc-ios-collection | https://support.claude.com/en/collections/9879000-claude-for-ios | Help Center collection "Claude for iOS" (six articles; none on iPad, Watch, notifications, accessibility or offline) (added 2026-10-15) |
| hc-sitemap | https://support.claude.com/sitemap.xml | Help Center sitemap, used to list every English article (376 URLs on 2026-10-15) (added 2026-10-15) |
| hc-voice-2025 | https://web.archive.org/web/20250527211233/https://support.anthropic.com/en/articles/11101966-using-voice-mode-on-claude-mobile-apps | Voice mode article at launch, web-archive copy of 2025-05-27: free users can expect about 20 to 30 voice messages (added 2026-10-15) |
| hc-styles-wb | https://web.archive.org/web/20260710101210/https://support.claude.com/en/articles/10181068-styles-are-moving-to-skills | "Styles are moving to skills", dated 2026-06-01, web-archive copy of 2026-07-10 (added 2026-10-15) |
| hc-intents-wb | https://web.archive.org/web/20241218020658/https://support.anthropic.com/en/articles/10263469-using-claude-app-intents-and-shortcuts-on-ios | Earliest web-archive copy of the App Intents and Shortcuts article, 2024-12-18 (added 2026-10-15) |
| hc-lockscreen-wb | https://web.archive.org/web/20250313020235/https://support.anthropic.com/en/articles/10302511-accessing-claude-app-on-ios-lock-screen-control-center-and-action-button | Earliest web-archive copy of the Lock Screen and Control Center article, 2025-03-13 (added 2026-10-15) |

### 8.4 App Store

| Key | URL | What it is |
|---|---|---|
| appstore | https://apps.apple.com/us/app/claude-by-anthropic/id6473753684 | App Store listing: description, ratings, in-app purchases, privacy labels, languages, version history |
| itunes-api | https://itunes.apple.com/lookup?id=6473753684&country=us | Apple lookup API: version, dates, devices, universal build; its screenshot URLs are the marketing images I viewed |
| appstore-3p | https://itunes.apple.com/lookup?id=6757966311,6760984418,6761373528&country=us | Apple lookup for Agentfy: Claude Code Monitor, Codync and Lody, third-party apps whose descriptions advertise Live Activities or the Dynamic Island (added 2026-10-15) |

### 8.5 Press and other secondary sources

| Key | URL | What it is |
|---|---|---|
| 9to5mac | https://9to5mac.com/2025/10/20/claude-code-preview-ios-iphone/ | Claude Code on web and iOS, 2025-10-20 |
| decoder-rc | https://the-decoder.com/claude-code-sessions-now-accessible-from-any-device/ | Remote Control research preview, 2026-02-25 |
| helpnet-rc | https://www.helpnetsecurity.com/?p=358918 | Remote Control: how it works and security model, 2026-02-25 |
| macstories-dispatch | https://www.macstories.net/?p=196500 | Hands-on with Dispatch, 2026-03-17 |
| mactrast-health | https://www.mactrast.com/2026/01/claude-ai-iphone-app-gains-apple-health-integration-in-the-us/ | Apple Health integration, 2026-01-22 |
| ppc-voice | https://ppc.land/claude-adds-voice-mode-to-mobile-apps/ | Voice mode beta on mobile, 2025-05-27 |
| alt-research-mobile | https://alternativeto.net/news/2025/5/claude-s-research-is-now-available-on-mobile | Research on mobile, 2025-05-16 |
| alt-connectors-mobile | https://alternativeto.net/news/2025/7/claude-adds-mobile-access-to-connected-tools-for-paid-users | Connected tools on mobile, 2025-07-28 |
| alt-drafting-mobile | https://alternativeto.net/news/2025/7/claude-app-adds-email-messaging-and-calendar-invite-drafting-on-mobile | Drafting email, messages and invites on mobile, 2025-07-31 |
| onlinemarketing-widget | https://onlinemarketing.de/technologie/claude-direkt-auf-home-screen-ios-widget | iOS widget, 2025-01-22 |
| aicoder-ga | https://aicoder.com/news/news-20260923-claude-code-cloud-sessions-ga | Cloud sessions GA coverage, 2026-09-23 (secondary; source of the credit amounts) |
| boris-thread | https://threadreaderapp.com/thread/2038454336355999749.html | Claude Code creator's thread of 2026-03-30 (mobile app, teleport, Remote Control, Dispatch, WhatsApp hook) |
| boris-threads | https://www.threads.com/@boris_cherny/post/DWfjoFYlFM_/did-you-know-claude-code-has-a-mobile-app-personally-i-write-a-lot-of-my-code | First post of that thread on Threads, dated 03/29/26 |

### 8.6 GitHub issues (anthropics/claude-code)

| Key | URL | What it is |
|---|---|---|
| gh-14059 | https://github.com/anthropics/claude-code/issues/14059 | Opened in full: gh CLI in iOS/cloud sessions; closed 2026-08-17 |
| gh-28508 | https://github.com/anthropics/claude-code/issues/28508 | Opened in full: AskUserQuestion answers from mobile not received |
| gh-29214 | https://github.com/anthropics/claude-code/issues/29214 | Opened in full: prompts despite bypass; mode drift |
| gh-29319 | https://github.com/anthropics/claude-code/issues/29319 | Opened in full: permission-mode dropdown; closed 2026-08-17 |
| gh-29438 | https://github.com/anthropics/claude-code/issues/29438 | Opened in full: push for approvals; closed 2026-08-17 |
| gh-30592 | https://github.com/anthropics/claude-code/issues/30592 | Opened in full: iOS Claude Code notifications broken |
| gh-34255 | https://github.com/anthropics/claude-code/issues/34255 | Opened in full: Remote Control automatic reconnection fails |
| gh-35637 | https://github.com/anthropics/claude-code/issues/35637 | Opened in full: prompts not rendering on mobile |
| gh-37235 | https://github.com/anthropics/claude-code/issues/37235 | Opened in full: expand permission prompts on iOS |
| gh-47127 | https://github.com/anthropics/claude-code/issues/47127 | Opened in full: Stop control; closed 2026-08-17 |
| gh-51267 | https://github.com/anthropics/claude-code/issues/51267 | Opened in full: silent mid-execution hangs |
| gh-55500 | https://github.com/anthropics/claude-code/issues/55500 | Opened in full: branch selector missing on iOS |
| gh-57904 | https://github.com/anthropics/claude-code/issues/57904 | Opened in full: start sessions on a paired Mac from iOS |
| gh-61930 | https://github.com/anthropics/claude-code/issues/61930 | Opened in full: keyboard covers Send after dictation |
| gh-70144 | https://github.com/anthropics/claude-code/issues/70144 | Opened in full: iPadOS crash opening Code sessions |
| gh-71616 | https://github.com/anthropics/claude-code/issues/71616 | Opened in full: new Code sessions auto-archive on iOS |
| gh-73610 | https://github.com/anthropics/claude-code/issues/73610 | Opened in full: queued or unsent prompt discarded on navigation |
| gh-78792 | https://github.com/anthropics/claude-code/issues/78792 | Opened in full: published Code artifacts missing from the mobile app |
| gh-95617 | https://github.com/anthropics/claude-code/issues/95617 | Opened in full: no allow-all-domains for WebFetch/WebSearch on mobile |
| gh-97418 | https://github.com/anthropics/claude-code/issues/97418 | Opened in full: mobile Remote Control summarizes assistant text |
| gh-99489 | https://github.com/anthropics/claude-code/issues/99489 | Opened in full: iOS effort picker reverts Ultracode |
| gh-101173 | https://github.com/anthropics/claude-code/issues/101173 | Opened in full: Dynamic Island 'thinking' element ignores Live Activities setting |
| gh-28330 | https://github.com/anthropics/claude-code/issues/28330 | Title and counts only: cannot accept plan mode on mobile |
| gh-28571 | https://github.com/anthropics/claude-code/issues/28571 | Title and counts only: session fails to resync after connection drop |
| gh-28758 | https://github.com/anthropics/claude-code/issues/28758 | Title and counts only: session not connecting from mobile app |
| gh-33625 | https://github.com/anthropics/claude-code/issues/33625 | Title and counts only: AskUserQuestion shows awaiting input with no UI |
| gh-33967 | https://github.com/anthropics/claude-code/issues/33967 | Title and counts only: iPhone app hangs when a plan is pending approval on desktop (title and search excerpt) |
| gh-44805 | https://github.com/anthropics/claude-code/issues/44805 | Title and counts only: GitHub repository access check failed |
| gh-50496 | https://github.com/anthropics/claude-code/issues/50496 | Title and counts only: delete or clear old Remote Control sessions on mobile |
| gh-53709 | https://github.com/anthropics/claude-code/issues/53709 | Title and counts only: push has no sound or vibration on iOS |
| gh-63975 | https://github.com/anthropics/claude-code/issues/63975 | Title and counts only: unsent prompt lost when swiping out of the session |
| gh-65926 | https://github.com/anthropics/claude-code/issues/65926 | Title and counts only: iOS crash when the environment button is tapped |
| gh-68038 | https://github.com/anthropics/claude-code/issues/68038 | Title and counts only: slash commands broken by injected system-reminder prefix |
| gh-70108 | https://github.com/anthropics/claude-code/issues/70108 | Title and counts only: app crashes when connecting to Claude Code |
| gh-70182 | https://github.com/anthropics/claude-code/issues/70182 | Title and counts only: app silently crashes when tapping a Remote Control session |
| gh-70262 | https://github.com/anthropics/claude-code/issues/70262 | Title and counts only: crash tapping a Remote Control session on iOS 27 beta 2 |
| gh-70382 | https://github.com/anthropics/claude-code/issues/70382 | Title and counts only: crash opening a Remote Control session on iOS 26.5 |
| gh-87003 | https://github.com/anthropics/claude-code/issues/87003 | Title and counts only: mobile push requested but Android never receives it |
| gh-96126 | https://github.com/anthropics/claude-code/issues/96126 | Opened in full on 2026-10-15: push for prompts a hook already auto-approved; the push is mirrored to the Apple Watch |
| gh-96284 | https://github.com/anthropics/claude-code/issues/96284 | Title and counts only: Cowork tasks missing from the iOS project view |
| gh-97410 | https://github.com/anthropics/claude-code/issues/97410 | Title and counts only: prompt suggestions not displayed on mobile Remote Control |
| gh-99217 | https://github.com/anthropics/claude-code/issues/99217 | Title and counts only: mod UI not drawn in desktop and iOS Remote Control views |
| gh-100502 | https://github.com/anthropics/claude-code/issues/100502 | Title and counts only: merged Claude app context size versus help center |
| gh-101123 | https://github.com/anthropics/claude-code/issues/101123 | Title and counts only: Claude Code on CarPlay feature request |
| gh-search | https://api.github.com/search/issues?q=repo:anthropics/claude-code+is:issue+iOS+in:title&sort=reactions&order=desc | GitHub search used for reaction and comment counts; also queried with the terms 'remote control' mobile, label platform:ios, and 'diff' with iOS or mobile |
| gh-18189 | https://github.com/anthropics/claude-code/issues/18189 | Opened in full on 2026-10-15: mobile companion app request; July 2026 comment on routines in the app; closed by an Anthropic collaborator as covered by Remote Control |
| gh-54228 | https://github.com/anthropics/claude-code/issues/54228 | Opened in full on 2026-10-15: iPhone "Diff +X -Y" badge counts every edit instead of the git state (closed as a duplicate) |
| gh-86704 | https://github.com/anthropics/claude-code/issues/86704 | Opened in full on 2026-10-15: iOS approval prompts truncate the command and the diff (filed 2026-08-14, closed "not planned" 2026-09-12) |
| gh-88495 | https://github.com/anthropics/claude-code/issues/88495 | Opened in full on 2026-10-15: read-aloud and a screen-reader audit for the mobile Remote Control view (closed "not planned") |
| gh-95391 | https://github.com/anthropics/claude-code/issues/95391 | Opened in full on 2026-10-15: answer AskUserQuestion from the iOS push; says the push carries no question or options (open) |
| gh-97734 | https://github.com/anthropics/claude-code/issues/97734 | Opened in full on 2026-10-15: iPad local and cloud sessions look alike; a comment confirms the Code tab list shows cloud, local and offline icons |
| gh-97737 | https://github.com/anthropics/claude-code/issues/97737 | Opened in full on 2026-10-15: iPad sidebar Recents shows the same icon for every Code session |

### 8.7 Posts on X (added 2026-10-15)

Read through https://api.fxtwitter.com/, which returns the post text and date without a login.

| Key | URL | What it is |
|---|---|---|
| x-claudeai-teament | https://x.com/claudeai/status/1988737589130747906 | @claudeai, 2025-11-12: Claude Code on the web research preview expanded to Team and Enterprise, from the browser and the iOS app |
| x-claudedevs-0424 | https://x.com/ClaudeDevs/status/2047773531820491054 | @ClaudeDevs, 2026-04-24: start a session on the web or mobile, then run `claude --teleport` |
| x-claudedevs-0821 | https://x.com/ClaudeDevs/status/2090933161115205700 | @ClaudeDevs, 2026-08-21 Remote Control thread: `/diff` from the phone opens the native diff sheet |
| x-claudedevs-ga | https://x.com/ClaudeDevs/status/2102871550974427462 | @ClaudeDevs, 2026-09-23 thread: cloud sessions out of research preview; one-time credit of $100 (Pro) or $250 (Max); replies 2102871554069774451 and 2102871555244257518 give the terms |

### 8.8 Other vendors' docs (added 2026-10-15)

| Key | URL | What it is |
|---|---|---|
| codex-remote | https://learn.chatgpt.com/docs/remote-connections | OpenAI Codex docs, Remote connections: from the phone you can start new chats in projects on a connected host |

<!-- Link reference definitions so that [key] renders as a link in Markdown viewers -->

[rc-docs]: https://code.claude.com/docs/en/remote-control
[web-docs]: https://code.claude.com/docs/en/claude-code-on-the-web
[web-qs]: https://code.claude.com/docs/en/web-quickstart
[mobile-docs]: https://code.claude.com/docs/en/mobile
[projects-docs]: https://code.claude.com/docs/en/claude-projects
[cloudenv-docs]: https://code.claude.com/docs/en/cloud-environments
[perm-docs]: https://code.claude.com/docs/en/permission-modes
[desktop-docs]: https://code.claude.com/docs/en/desktop
[avail-docs]: https://code.claude.com/docs/en/feature-availability
[channels-docs]: https://code.claude.com/docs/en/channels
[routines-docs]: https://code.claude.com/docs/en/routines
[artifacts-docs]: https://code.claude.com/docs/en/artifacts
[agentview-docs]: https://code.claude.com/docs/en/agent-view
[voicecli-docs]: https://code.claude.com/docs/en/voice-dictation
[ultraplan-docs]: https://code.claude.com/docs/en/ultraplan
[model-docs]: https://code.claude.com/docs/en/model-config
[whatsnew]: https://code.claude.com/docs/en/whats-new/index
[wn-w15]: https://code.claude.com/docs/en/whats-new/2026-w15
[wn-w16]: https://code.claude.com/docs/en/whats-new/2026-w16
[wn-w17]: https://code.claude.com/docs/en/whats-new/2026-w17
[wn-w34]: https://code.claude.com/docs/en/whats-new/2026-w34
[changelog]: https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md
[npm]: https://registry.npmjs.org/@anthropic-ai/claude-code
[blog-web]: https://claude.com/blog/claude-code-on-the-web
[blog-projects]: https://claude.com/blog/projects-redesigned
[blog-cowork-mobile]: https://claude.com/blog/cowork-web-mobile
[blog-artifacts]: https://claude.com/resources/articles/build-artifacts
[blog-websearch]: https://claude.com/blog/web-search
[blog-research]: https://claude.com/blog/research
[pricing]: https://claude.com/pricing
[cc-product]: https://claude.com/product/claude-code
[download]: https://claude.com/download
[connectors-docs]: https://claude.com/docs/connectors/overview
[cowork-changelog]: https://claude.com/docs/cowork/changelog
[hc-release-notes]: https://support.claude.com/en/articles/12138966-release-notes
[hc-intents]: https://support.claude.com/en/articles/10263469-using-claude-app-intents-shortcuts-and-widgets-on-ios
[hc-lockscreen]: https://support.claude.com/en/articles/10302511-accessing-claude-app-on-ios-lock-screen-control-center-and-action-button
[hc-ios-apps]: https://support.claude.com/en/articles/11869619-use-claude-with-ios-apps
[hc-install-ios]: https://support.claude.com/en/articles/9266462-install-claude-for-ios
[hc-voice]: https://support.claude.com/en/articles/11101966-use-voice-mode
[hc-effort]: https://support.claude.com/en/articles/8664678-change-the-model-effort-and-extended-thinking-settings
[hc-memory]: https://support.claude.com/en/articles/11817273-use-claude-s-chat-search-and-memory-to-build-on-previous-context
[hc-styles]: https://support.claude.com/en/articles/10181068-configuring-and-using-styles
[hc-artifacts]: https://support.claude.com/en/articles/9487310-what-are-artifacts-and-how-do-i-use-them
[hc-upload]: https://support.claude.com/en/articles/8241126-upload-files-to-claude
[hc-research]: https://support.claude.com/en/articles/11088861-use-research-on-claude
[hc-websearch]: https://support.claude.com/en/articles/10684626-enable-and-use-web-search
[hc-share]: https://support.claude.com/en/articles/10593882-share-and-unshare-chats
[hc-share-people]: https://support.claude.com/en/articles/16762496-share-a-chat-with-specific-people
[hc-share-public]: https://support.claude.com/en/articles/16762437-public-links-for-shared-chats
[hc-projects]: https://support.claude.com/en/articles/9517075-what-are-projects
[hc-cowork-mobile]: https://support.claude.com/en/articles/15520349-use-claude-cowork-on-web-desktop-and-mobile
[hc-dispatch]: https://support.claude.com/en/articles/13947068
[hc-one-claude]: https://support.claude.com/en/articles/16761823-claude-cowork-and-chat-are-one-claude
[appstore]: https://apps.apple.com/us/app/claude-by-anthropic/id6473753684
[itunes-api]: https://itunes.apple.com/lookup?id=6473753684&country=us
[9to5mac]: https://9to5mac.com/2025/10/20/claude-code-preview-ios-iphone/
[decoder-rc]: https://the-decoder.com/claude-code-sessions-now-accessible-from-any-device/
[helpnet-rc]: https://www.helpnetsecurity.com/?p=358918
[macstories-dispatch]: https://www.macstories.net/?p=196500
[mactrast-health]: https://www.mactrast.com/2026/01/claude-ai-iphone-app-gains-apple-health-integration-in-the-us/
[ppc-voice]: https://ppc.land/claude-adds-voice-mode-to-mobile-apps/
[alt-research-mobile]: https://alternativeto.net/news/2025/5/claude-s-research-is-now-available-on-mobile
[alt-connectors-mobile]: https://alternativeto.net/news/2025/7/claude-adds-mobile-access-to-connected-tools-for-paid-users
[alt-drafting-mobile]: https://alternativeto.net/news/2025/7/claude-app-adds-email-messaging-and-calendar-invite-drafting-on-mobile
[onlinemarketing-widget]: https://onlinemarketing.de/technologie/claude-direkt-auf-home-screen-ios-widget
[aicoder-ga]: https://aicoder.com/news/news-20260923-claude-code-cloud-sessions-ga
[boris-thread]: https://threadreaderapp.com/thread/2038454336355999749.html
[boris-threads]: https://www.threads.com/@boris_cherny/post/DWfjoFYlFM_/did-you-know-claude-code-has-a-mobile-app-personally-i-write-a-lot-of-my-code
[gh-14059]: https://github.com/anthropics/claude-code/issues/14059
[gh-28508]: https://github.com/anthropics/claude-code/issues/28508
[gh-29214]: https://github.com/anthropics/claude-code/issues/29214
[gh-29319]: https://github.com/anthropics/claude-code/issues/29319
[gh-29438]: https://github.com/anthropics/claude-code/issues/29438
[gh-30592]: https://github.com/anthropics/claude-code/issues/30592
[gh-34255]: https://github.com/anthropics/claude-code/issues/34255
[gh-35637]: https://github.com/anthropics/claude-code/issues/35637
[gh-37235]: https://github.com/anthropics/claude-code/issues/37235
[gh-47127]: https://github.com/anthropics/claude-code/issues/47127
[gh-51267]: https://github.com/anthropics/claude-code/issues/51267
[gh-55500]: https://github.com/anthropics/claude-code/issues/55500
[gh-57904]: https://github.com/anthropics/claude-code/issues/57904
[gh-61930]: https://github.com/anthropics/claude-code/issues/61930
[gh-70144]: https://github.com/anthropics/claude-code/issues/70144
[gh-71616]: https://github.com/anthropics/claude-code/issues/71616
[gh-73610]: https://github.com/anthropics/claude-code/issues/73610
[gh-78792]: https://github.com/anthropics/claude-code/issues/78792
[gh-95617]: https://github.com/anthropics/claude-code/issues/95617
[gh-97418]: https://github.com/anthropics/claude-code/issues/97418
[gh-99489]: https://github.com/anthropics/claude-code/issues/99489
[gh-101173]: https://github.com/anthropics/claude-code/issues/101173
[gh-28330]: https://github.com/anthropics/claude-code/issues/28330
[gh-28571]: https://github.com/anthropics/claude-code/issues/28571
[gh-28758]: https://github.com/anthropics/claude-code/issues/28758
[gh-33625]: https://github.com/anthropics/claude-code/issues/33625
[gh-33967]: https://github.com/anthropics/claude-code/issues/33967
[gh-44805]: https://github.com/anthropics/claude-code/issues/44805
[gh-50496]: https://github.com/anthropics/claude-code/issues/50496
[gh-53709]: https://github.com/anthropics/claude-code/issues/53709
[gh-63975]: https://github.com/anthropics/claude-code/issues/63975
[gh-65926]: https://github.com/anthropics/claude-code/issues/65926
[gh-68038]: https://github.com/anthropics/claude-code/issues/68038
[gh-70108]: https://github.com/anthropics/claude-code/issues/70108
[gh-70182]: https://github.com/anthropics/claude-code/issues/70182
[gh-70262]: https://github.com/anthropics/claude-code/issues/70262
[gh-70382]: https://github.com/anthropics/claude-code/issues/70382
[gh-87003]: https://github.com/anthropics/claude-code/issues/87003
[gh-96126]: https://github.com/anthropics/claude-code/issues/96126
[gh-96284]: https://github.com/anthropics/claude-code/issues/96284
[gh-97410]: https://github.com/anthropics/claude-code/issues/97410
[gh-99217]: https://github.com/anthropics/claude-code/issues/99217
[gh-100502]: https://github.com/anthropics/claude-code/issues/100502
[gh-101123]: https://github.com/anthropics/claude-code/issues/101123
[gh-search]: https://api.github.com/search/issues?q=repo:anthropics/claude-code+is:issue+iOS+in:title&sort=reactions&order=desc
[a11y-docs]: https://code.claude.com/docs/en/accessibility
[anthropic-projects]: https://www.anthropic.com/news/projects
[anthropic-styles-wb]: https://web.archive.org/web/20241126180354/https://www.anthropic.com/news/styles
[hc-connectors]: https://support.claude.com/en/articles/11176164-use-connectors-to-extend-claude-s-capabilities
[hc-create-projects]: https://support.claude.com/en/articles/9519177-how-can-i-create-and-manage-projects
[hc-beta]: https://support.claude.com/en/articles/14503520-available-beta-and-research-preview-features
[hc-a11y-artifacts]: https://support.claude.com/en/articles/17457950-use-artifacts-with-a-keyboard-or-screen-reader
[hc-ios-collection]: https://support.claude.com/en/collections/9879000-claude-for-ios
[hc-sitemap]: https://support.claude.com/sitemap.xml
[hc-voice-2025]: https://web.archive.org/web/20250527211233/https://support.anthropic.com/en/articles/11101966-using-voice-mode-on-claude-mobile-apps
[hc-styles-wb]: https://web.archive.org/web/20260710101210/https://support.claude.com/en/articles/10181068-styles-are-moving-to-skills
[hc-intents-wb]: https://web.archive.org/web/20241218020658/https://support.anthropic.com/en/articles/10263469-using-claude-app-intents-and-shortcuts-on-ios
[hc-lockscreen-wb]: https://web.archive.org/web/20250313020235/https://support.anthropic.com/en/articles/10302511-accessing-claude-app-on-ios-lock-screen-control-center-and-action-button
[appstore-3p]: https://itunes.apple.com/lookup?id=6757966311,6760984418,6761373528&country=us
[gh-18189]: https://github.com/anthropics/claude-code/issues/18189
[gh-54228]: https://github.com/anthropics/claude-code/issues/54228
[gh-86704]: https://github.com/anthropics/claude-code/issues/86704
[gh-88495]: https://github.com/anthropics/claude-code/issues/88495
[gh-95391]: https://github.com/anthropics/claude-code/issues/95391
[gh-97734]: https://github.com/anthropics/claude-code/issues/97734
[gh-97737]: https://github.com/anthropics/claude-code/issues/97737
[x-claudeai-teament]: https://x.com/claudeai/status/1988737589130747906
[x-claudedevs-0424]: https://x.com/ClaudeDevs/status/2047773531820491054
[x-claudedevs-0821]: https://x.com/ClaudeDevs/status/2090933161115205700
[x-claudedevs-ga]: https://x.com/ClaudeDevs/status/2102871550974427462
[codex-remote]: https://learn.chatgpt.com/docs/remote-connections


---

## Verification pass (2026-10-15)

This pass resolved all 41 tags that the first draft marked "unverified": 37 claims and 4 legend or meta lines. Result for the 37 claims: 23 verified, 11 corrected, 1 removed, 2 unconfirmed. No claim needed a browser. Evidence came from free primary sources: the Apple lookup and search APIs, `gh api` on `anthropics/claude-code`, the Claude Code docs as Markdown (`curl https://code.claude.com/docs/en/<page>.md`), Help Center pages and sitemap fetched with `curl`, the Claude Code changelog and npm registry, web-archive copies (`https://web.archive.org/cdx/search/cdx?url=...`), and posts on X read through `https://api.fxtwitter.com/`. No web search was used.

### Tagged claims

| # | Claim (short) | Outcome | Evidence (URL or command) |
|---|---|---|---|
| 1 | Legend: claims I could not confirm are tagged | Legend updated (not a claim) | n/a |
| 2 | Legend: what the tag means | Legend updated (not a claim) | n/a |
| 3 | Ultraplan: no removal date found | CORRECTED: removed in CLI 2.1.222, published 2026-08-04 | `curl -s https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md \| grep -n -i ultraplan`; `time["2.1.222"]` in https://registry.npmjs.org/@anthropic-ai/claude-code |
| 4 | Meta: some Team/Enterprise rollout dates stay open | Meta note updated (the date was found, see #12) | n/a |
| 5 | In-app price gap is likely Apple's commission | REMOVED (speculative and unimportant; the prices themselves re-checked) | In-App Purchases list on https://apps.apple.com/us/app/claude-by-anthropic/id6473753684 |
| 6 | Where Web search and Research sit on the phone | CORRECTED: the steps name no surface, Research lists Claude Mobile, and the new experience uses `/deep-research` or "+" then "Research" | https://support.claude.com/en/articles/10684626-enable-and-use-web-search ; https://support.claude.com/en/articles/11088861-use-research-on-claude ; https://support.claude.com/en/articles/16761823-claude-cowork-and-chat-are-one-claude |
| 7 | No multi-pane iPad layout in the marketing images | VERIFIED | `ipadScreenshotUrls` in https://itunes.apple.com/lookup?id=6473753684&country=us (five of nine viewed, including Code_Review); https://github.com/anthropics/claude-code/issues/97737 |
| 8 | How the diff looks on an iPhone | CORRECTED: `/diff` opens a native diff sheet; iPhone shows a "Diff +X -Y" badge; layout undocumented | https://api.fxtwitter.com/status/2090933161115205700 ; `gh api repos/anthropics/claude-code/issues/54228` |
| 9 | Base-branch selector on the iPhone today | UNCONFIRMED | `gh api repos/anthropics/claude-code/issues/55500/comments`; `curl https://code.claude.com/docs/en/mobile.md`; changelog grep for "branch" |
| 10 | No teleport action in the phone app | CORRECTED: no button, but `/teleport` typed in a cloud session returns the command; Anthropic's flow is start on the phone, then `claude --teleport` | `curl https://code.claude.com/docs/en/claude-code-on-the-web.md` (section "Continue a cloud session in your terminal"); https://api.fxtwitter.com/status/2047773531820491054 |
| 11 | $100 (Pro) and $250 (Max) try credits at GA | VERIFIED (announced by @ClaudeDevs, not on an Anthropic web page) | https://api.fxtwitter.com/ClaudeDevs/status/2102871550974427462 ; profile check https://api.fxtwitter.com/ClaudeDevs |
| 12 | Team and Enterprise launch dates for cloud sessions | CORRECTED: research preview reached Team and Enterprise on 2025-11-12 | https://api.fxtwitter.com/status/1988737589130747906 |
| 13 | Project notifications on phones | VERIFIED: the docs call them desktop-only | `curl https://code.claude.com/docs/en/claude-projects.md \| grep -n desktop-only` |
| 14 | No Approve/Deny buttons on lock-screen notifications | VERIFIED (user report) | `gh api repos/anthropics/claude-code/issues/95391`; Dispatch screenshot in https://itunes.apple.com/lookup?id=6473753684&country=us |
| 15 | Third-party Live Activity apps: ClaudeLive and Agentfy | CORRECTED: Agentfy, Codync and Lody advertise Live Activities; no app named ClaudeLive found | https://itunes.apple.com/search?term=Claude%20Code&entity=software&country=us&limit=50 ; https://itunes.apple.com/lookup?id=6757966311,6760984418,6761373528&country=us |
| 16 | One reporter sees pushes on phone and watch | VERIFIED | `gh api repos/anthropics/claude-code/issues/96126 --jq .body` ("mirrored to Apple Watch") |
| 17 | Phone diff layout (section 3.8) | CORRECTED: same evidence as #8 | https://api.fxtwitter.com/status/2090933161115205700 ; `gh api repos/anthropics/claude-code/issues/54228` |
| 18 | Inline line comments on the phone diff | UNCONFIRMED | `curl https://code.claude.com/docs/en/claude-code-on-the-web.md` and `web-quickstart.md`; `gh api -X GET search/issues -f q='repo:anthropics/claude-code is:issue diff mobile in:title'` (and `diff iOS in:title`); @ClaudeDevs timeline via https://api.fxtwitter.com/2/profile/ClaudeDevs/statuses |
| 19 | Agent view is not on the phone | VERIFIED | `curl https://code.claude.com/docs/en/agent-view.md`; `remote-control.md` and `mobile.md` have no mention |
| 20 | Routine creation from the phone is not documented | VERIFIED (plus a user comment) | `curl https://code.claude.com/docs/en/routines.md` ("from the web..., from the Desktop app, or from the CLI"); `gh api repos/anthropics/claude-code/issues/18189/comments` |
| 21 | Copy, regenerate, branch, read-aloud on iOS not documented | CORRECTED: branching is documented as unavailable in the new experience; the rest is undocumented | https://support.claude.com/en/articles/16761823-claude-cowork-and-chat-are-one-claude ; https://support.claude.com/sitemap.xml ; `gh api repos/anthropics/claude-code/issues/88495` |
| 22 | Effort: no separate mobile steps | VERIFIED | https://support.claude.com/en/articles/8664678-change-the-model-effort-and-extended-thinking-settings |
| 23 | Creating a chat project from the phone not documented | VERIFIED | https://support.claude.com/en/articles/9519177-how-can-i-create-and-manage-projects |
| 24 | Original Projects release date | CORRECTED: 2024-06-25, Pro and Team | https://www.anthropic.com/news/projects |
| 25 | Artifact connectors and storage on mobile not stated | VERIFIED: availability lines name only web and Desktop | https://support.claude.com/en/articles/9487310-what-are-artifacts-and-how-do-i-use-them |
| 26 | Mobile upload limits and pickers not documented | VERIFIED | https://support.claude.com/en/articles/8241126-upload-files-to-claude |
| 27 | Free users got about 20 to 30 voice messages at launch | VERIFIED (Anthropic's own launch article) | https://web.archive.org/web/20250527211233/https://support.anthropic.com/en/articles/11101966-using-voice-mode-on-claude-mobile-apps |
| 28 | Web search: no mobile steps | VERIFIED | https://support.claude.com/en/articles/10684626-enable-and-use-web-search |
| 29 | Connecting a new service from the phone not documented | CORRECTED: documented as possible on iOS and Android, in beta | https://support.claude.com/en/articles/11176164-use-connectors-to-extend-claude-s-capabilities |
| 30 | Phone UI for searching chat history not documented | VERIFIED | https://support.claude.com/en/articles/11817273-use-claude-s-chat-search-and-memory-to-build-on-previous-context ; https://support.claude.com/en/articles/16761823-claude-cowork-and-chat-are-one-claude |
| 31 | Styles are moving to skills | VERIFIED | https://web.archive.org/web/20260710101210/https://support.claude.com/en/articles/10181068-styles-are-moving-to-skills (found with https://web.archive.org/cdx/search/cdx?url=support.claude.com/en/articles/10181068*) |
| 32 | Styles launch date and mobile availability | CORRECTED: launched 2024-11-26; mobile availability still unconfirmed | https://web.archive.org/web/20241126180354/https://www.anthropic.com/news/styles ; https://web.archive.org/web/20250708195543/https://support.anthropic.com/en/articles/10181068-configuring-and-using-styles |
| 33 | App Intents launch not stated | VERIFIED (article existed by 2024-12-18) | https://support.claude.com/en/articles/10263469-using-claude-app-intents-shortcuts-and-widgets-on-ios ; https://web.archive.org/web/20241218020658/https://support.anthropic.com/en/articles/10263469-using-claude-app-intents-and-shortcuts-on-ios |
| 34 | Lock Screen controls launch not stated | VERIFIED (article existed by 2025-03-13) | https://support.claude.com/en/articles/10302511-accessing-claude-app-on-ios-lock-screen-control-center-and-action-button ; https://web.archive.org/web/20250313020235/https://support.anthropic.com/en/articles/10302511-accessing-claude-app-on-ios-lock-screen-control-center-and-action-button |
| 35 | No Anthropic Watch features; pushes mirror to the watch | VERIFIED | `supportedDevices` in https://itunes.apple.com/lookup?id=6473753684&country=us (no Watch entry); Compatibility on the App Store page; `gh api repos/anthropics/claude-code/issues/96126` |
| 36 | iPad: Stage Manager, Split View, keyboard, Pencil not documented | VERIFIED | https://support.claude.com/en/collections/9879000-claude-for-ios ; `curl https://code.claude.com/docs/en/mobile.md`; `gh api -X GET search/issues -f q='repo:anthropics/claude-code is:issue "stage manager"'` (and `"split view" iPad`, `iPad keyboard shortcut`) |
| 37 | No Anthropic accessibility statement for the iOS app | VERIFIED | Accessibility section of https://apps.apple.com/us/app/claude-by-anthropic/id6473753684 ; https://code.claude.com/docs/en/accessibility ; https://support.claude.com/en/articles/17457950-use-artifacts-with-a-keyboard-or-screen-reader ; `gh api repos/anthropics/claude-code/issues/88495` |
| 38 | No Anthropic statement on offline behavior | VERIFIED | https://support.claude.com/sitemap.xml (no offline article); `gh api repos/anthropics/claude-code/issues/101173/comments` |
| 39 | Lock-screen push has no Approve/Deny (section 5) | VERIFIED (user report) | `gh api repos/anthropics/claude-code/issues/95391` |
| 40 | Codex's phone app can start sessions on configured machines | VERIFIED | https://learn.chatgpt.com/docs/remote-connections ("Start new chats in projects on the host"); `gh api repos/anthropics/claude-code/issues/57904/comments` |
| 41 | Appendix header: all open questions unverified | Header updated and items annotated (not a claim) | n/a |

### Untagged claims fixed or extended

| # | Claim (short) | Outcome | Evidence (URL or command) |
|---|---|---|---|
| U1 | Current iOS version is 1.261013.20 (2026-10-14) | CORRECTED: 1.261014.20 was released 2026-10-15 21:12 UTC; the app table, the version-history row and the timeline are updated | https://itunes.apple.com/lookup?id=6473753684&country=us ; Version History on https://apps.apple.com/us/app/claude-by-anthropic/id6473753684 |
| U2 | iPhone approval prompts "showed" about 100 characters (past tense, sections 3.8, 5.2 and 6.1) | CORRECTED: still truncated as of the App Store build of 2026-08-14; both reports closed "not planned" with no fix | `gh api repos/anthropics/claude-code/issues/86704`; `gh api repos/anthropics/claude-code/issues/37235` |
| U3 | Additions, not corrections: the Aug 2026 docs screenshot shows an "All" dropdown instead of chips; the Help Center beta table still lists "Claude Code web (CCR)" as a research preview; reporters see Live Activities switches for Claude in iOS Settings; timeline rows for 2025-11-12 and 2026-08-04 | Added | https://code.claude.com/docs/en/whats-new/2026-w34 ; https://support.claude.com/en/articles/14503520-available-beta-and-research-preview-features ; `gh api repos/anthropics/claude-code/issues/101173/comments` |

### Claims the product spec took from this report

| # | Spec claim | Verdict | Evidence (URL or command) |
|---|---|---|---|
| S1 | Cloud sessions (formerly "Claude Code on the web") became generally available on 2026-09-23 | VERIFIED. Caveat: the Help Center beta table still lists the web product as a research preview, which looks stale | Update note dated September 23, 2026 on https://claude.com/blog/claude-code-on-the-web ; https://api.fxtwitter.com/ClaudeDevs/status/2102871550974427462 |
| S2 | Remote Control lets the iOS app control a local CLI session; left preview in August 2026; pairs by QR or URL over an outbound-only relay | VERIFIED. Since Aug 2026 a device card can also start a session | `curl https://code.claude.com/docs/en/remote-control.md` ("outbound HTTPS requests only and never opens inbound ports", QR code, session URL); https://code.claude.com/docs/en/whats-new/2026-w34 ("Remote Control is also out of research preview") |
| S3 | The Code tab is a triage list with filter chips (All, Blocked, In progress, Done) and inline Approve | VERIFIED for the App Store marketing images (iPhone and iPad). Caveat: Anthropic's Aug 2026 docs screenshot shows an "All" dropdown instead of chips | Code_Review screenshot in https://itunes.apple.com/lookup?id=6473753684&country=us ; https://code.claude.com/docs/en/whats-new/2026-w34 |
| S4 | Approvals show the full command; the phone supports queue, steer and Stop | CORRECTED: approvals show only about 100 characters of a command and truncate diffs, with no expand. Queue, steer and Stop are verified | `gh api repos/anthropics/claude-code/issues/86704`; `gh api repos/anthropics/claude-code/issues/47127/comments` (Anthropic: Stop control in the mobile app); https://code.claude.com/docs/en/mobile ; https://code.claude.com/docs/en/claude-code-on-the-web |
| S5 | Push is presence-aware (skipped when the user is at the terminal), with two toggles | VERIFIED as documented. Caveat: a September 2026 regression report says pushes for hook-approved prompts fire while the user is active at the Mac | `curl https://code.claude.com/docs/en/remote-control.md` (section "Mobile push notifications"); `gh api repos/anthropics/claude-code/issues/96126` |
| S6 | Top GitHub complaints: Remote Control reconnect failures (#34255, about 109 reactions) and approval prompts that do not render | VERIFIED: #34255 is open with 109 reactions and 72 comments and no Anthropic reply; #35637 (prompts not rendering) is open with 30. Anthropic shipped reconnect fixes on 2026-08-21 and 2026-08-28, but users kept commenting on #34255 until 2026-09-20 | `gh api repos/anthropics/claude-code/issues/34255`; `gh api repos/anthropics/claude-code/issues/35637`; https://api.fxtwitter.com/status/2093480635591794903 |
| S7 | No Live Activity for Claude Code sessions, and no Apple Watch app | VERIFIED, with a caveat: the Live Activity half rests on user reports and on silence in Anthropic's docs. The app does show a Dynamic Island element for chat replies and exposes Live Activities switches in iOS Settings | `supportedDevices` in https://itunes.apple.com/lookup?id=6473753684&country=us ; `gh api repos/anthropics/claude-code/issues/101173/comments`; changelog grep for "live activit" returns nothing |
