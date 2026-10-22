# ChatGPT for iOS and Codex on mobile: feature inventory

Research date: 2026-10-15. Scope: OpenAI's ChatGPT iPhone and iPad app, with extra depth on Codex (coding) on mobile. Written for the opencode native iOS client project.

## 0. How to read this report

Every factual claim carries a link, or is covered by the source named in its section or table row. A verification pass on 2026-10-15 (see the last section) resolved every claim the first draft had marked unverified. Confirmed claims now carry their source, changed claims end with "(corrected 2026-10-15)", and claims that could not be settled are marked **[unconfirmed: ...]** (reason and what was tried) or **[needs browser: URL]** (only a page the fetch tools cannot load would settle it). Where help.openai.com or openai.com refused direct fetches, the pass read archived copies on the Internet Archive's Wayback Machine (web.archive.org), linked inline.

Source labels used in the text:

- **OpenAI docs**: pages on learn.chatgpt.com. This site replaced developers.openai.com/codex (the old URLs now redirect there with HTTP 308). It is the best primary source I could read.
- **press**: 9to5Mac, MacRumors, MacStories, TechCrunch, Engadget, Search Engine Journal and similar.
- **secondary**: blogs, vendor blogs, aggregators such as Releasebot.
- **user report**: GitHub issues, forum posts, Hacker News comments. These are anecdotes, not confirmed bugs.

Limits of this research that you should know about:

1. My fetch tool was blocked (HTTP 403, 402 or refused) on help.openai.com, help-lb.openai.com, openai.com, chatgpt.com, x.com and web.archive.org. So I could not read OpenAI's official ChatGPT release notes or blog posts directly. Items that depend on them are sourced from Releasebot (which mirrors the notes), from press, or from search-result summaries, and are labeled.
2. The shared web-search budget (200 calls) ran out near the end. Checks I did not get to: App Store review text, Reddit sentiment, a second confirmation of the group-chat retirement, and deep research, canvas and memory behavior on mobile.
3. The fetch tool summarizes pages with a small model and truncates very long pages. The Codex changelog is about 217,000 characters. The iOS release table for versions before 1.2026.244 comes from a single pass, so exact wording may differ slightly from the source.
4. The web changed a lot in 2026 (new model families, a new docs site, Work, Dots, plugins). Older articles and older training knowledge are often wrong now. I used only dated 2026 sources for current state.

## 1. Executive summary

1. **Shape of the app (Oct 2026).** The ChatGPT iPhone app now hosts Chat, Work (the cloud agent that reportedly replaced agent mode), Codex (remote control for coding agents, plus cloud tasks) and Dots (always-on agents, launched 2026-09-29). Codex is not a separate app. The docs say "open Codex" in the ChatGPT app, and older builds label it "Remote" ([OpenAI docs: Codex on mobile](https://learn.chatgpt.com/docs/mobile)). No standalone Codex iOS app exists as far as I can find ([AICatchup](https://aicatchup.com/news/codex-chatgpt-mobile-preview); [MacStories, April 2026](https://www.macstories.net/reviews/remodex-codex-remote-mobile-app-ios/), which said OpenAI staff were hinting at one).
2. **Two ways to run Codex from the phone.** (a) Cloud tasks in an OpenAI-managed VM, on iOS since 2025-05-19. (b) Remote: the phone controls Codex running on your own Mac or Windows PC through an OpenAI relay, or on an SSH host that is either reached through that computer or added directly in the iOS app (see A.4) (corrected 2026-10-15). Remote launched as a preview on 2026-05-14 and went generally available on 2026-06-25 ([OpenAI docs: changelog](https://learn.chatgpt.com/docs/changelog)).
3. **Remote is a thin client.** Files, credentials, tools, MCP servers, skills, browser and Computer Use stay on the host. The phone gets streamed transcripts, diffs, test results, terminal output and screenshots, and sends prompts and approvals ([OpenAI docs: Remote connections](https://learn.chatgpt.com/docs/remote-connections)).
4. **The iOS Codex client ships almost weekly** (1.2026.132 on 2026-05-18 to 1.2026.272 on 2026-10-07). Highlights: approvals with "Always approve", Queue vs Steer, goals, side chats, worktrees and branches, file browser, diffs with inline comments, Face ID lock, voice, Spotlight and Shortcuts, Live Activity for worktree setup, Home Screen and Lock Screen widgets, deep links to tasks, iPad split view (details in section A.4).
5. **Apple integration is real but uneven.** Live Activities (Codex cloud tasks in 2025, worktree setup in 2026, Live voice from 2026-08-31), widgets (recent tasks, usage and reset times, configurable launcher), a Control Center and Lock Screen control for Remote voice, Spotlight and Shortcuts entry points. Gaps: no Apple Watch app, widget launchers are not exposed as Shortcuts actions, no large iPhone widget ([MacStories](https://www.macstories.net/ios/openai-updates-chatgpt-for-ios-with-customizable-widgets-for-chatgpt-work-and-codex-remote/)).
6. **General app direction.** GPT-6 with "Intelligent UI" (interactive answers) shipped 2026-10-07. Voice is now full duplex (GPT-Live, 2026-07-08). Agent mode was removed in favor of Work in mid-July 2026: OpenAI's help article now says "ChatGPT agent is no longer available", a notice that first appears in the Wayback copy of 2026-07-20 while the 2026-07-11 copy still described agent mode ([help article, archived](https://web.archive.org/web/20261012103042/https://help.openai.com/en/articles/11752874-chatgpt-agent)) (corrected 2026-10-15). Since 2026-07-09 users cannot create or join new group chats, though existing ones keep working ([ChatGPT release notes, archived 2026-10-10](https://web.archive.org/web/20261010013210/https://help.openai.com/en/articles/6825453-chatgpt-release-notes)). Custom GPTs retire 2026-12-11 in favor of plugins. Pulse was retired in favor of scheduled tasks (announced 2026-06-17).
7. **Biggest user pain points** (all documented in section D): connection reliability and host dependence (Mac sleep or lock, silent disconnects, 10+ second resume), pairing and revocation bugs, push notifications and approvals that do not arrive or are not actionable, a project-list regression, usage limits, and no first-class headless host.
8. **Where a better client can win**: direct and relay-free connectivity, a reliable host-presence model, actionable notifications, complete session and project lists, in-app usage visibility, and full Shortcuts and App Intents exposure.

## 2. Product map: what the ChatGPT iPhone app contains

| Area | What it is | Plans and notes | Source |
|---|---|---|---|
| Chat | Conversational ChatGPT with search, images, voice, files, camera | All plans. GPT-6 Sol for paid, GPT-6 Luna for Free and Go (since 2026-10-07 and 10-08) | [9to5Mac](https://9to5mac.com/2026/10/07/openai-brings-gpt-6-to-chatgpt-and-debuts-intelligent-ui/) |
| Work | Cloud agent for multi-step tasks and finished files; reportedly replaced agent mode | Launched 2026-07-09 on web and mobile for all plans except Free and Go (see B.9) (corrected 2026-10-15) | [OpenAI docs: use ChatGPT](https://learn.chatgpt.com/docs/use-chatgpt) |
| Codex (Remote and cloud) | Start, steer and review coding tasks on a connected computer or in the cloud | See section A.10 | [OpenAI docs: mobile](https://learn.chatgpt.com/docs/mobile) |
| Dots | Always-on agents with their own cloud computer; create, name, message and call from the app | Pro 100/200/500 (adults outside EEA, UK, Switzerland), Business Premium, Enterprise by admin | [OpenAI docs: dots](https://learn.chatgpt.com/docs/dots) |
| Voice | Full-duplex voice (GPT-Live) in chat, Work and Codex | All plans, with per-plan limits (see B.5) (corrected 2026-10-15) | [TechCrunch](https://techcrunch.com/2026/07/08/openai-releases-new-voice-models-for-more-natural-live-conversations/) |
| Scheduled tasks | Replaced Pulse; recurring, monitoring and event-triggered tasks | Go, Plus, Pro, Business, Enterprise on web and mobile | [9to5Mac](https://9to5mac.com/2026/06/17/openai-launches-scheduled-tasks-in-chatgpt-details-here/) |

Docs structure note: OpenAI's docs treat Chat, Work and Codex as three modes of one product, with Codex exposing developer tools and technical detail that Work hides ([use ChatGPT](https://learn.chatgpt.com/docs/use-chatgpt)). The iOS widget exposes the same three groups: Chat, Work and Remote ([MacStories](https://www.macstories.net/ios/openai-updates-chatgpt-for-ios-with-customizable-widgets-for-chatgpt-work-and-codex-remote/)).

---

# Part A. Codex on mobile

## A.1 Timeline

| Date | Event | Source |
|---|---|---|
| 2025-05-16 | Codex launches as a cloud software-engineering agent (research preview) for Pro, Enterprise and Business; Plus and Edu "coming soon" | [OpenAI blog, via search result](https://openai.com/index/introducing-codex/) (page not fetchable; summary only) |
| 2025-05-19 | "Codex in the ChatGPT iOS app": start tasks, view diffs, push PRs from the phone | [Changelog](https://learn.chatgpt.com/docs/changelog) |
| 2025-05-20 | Press coverage adds Live Activities on the Lock Screen for monitoring tasks | [AlternativeTo](https://alternativeto.net/news/2025/5/openai-integrates-codex-into-chatgpt-ios-app); OpenAI Developers made the same point on X on 2025-05-19 ([post](https://x.com/OpenAIDevs/status/1924601527898951914), read through the fxtwitter API) |
| 2025-06-03 | Plus users get Codex; agent internet access (off by default); follow-ups update an existing PR; voice dictation for tasks; Live Activities re-enabled on iOS | [Changelog](https://learn.chatgpt.com/docs/changelog); the Plus rollout note is from the [OpenAI blog update, via search result](https://openai.com/index/introducing-codex/) |
| 2025-06-13 | Best-of-N: several simultaneous attempts per task | [Changelog](https://learn.chatgpt.com/docs/changelog), [forum post](https://community.openai.com/t/codex-generates-multiple-responses-simultaneously/1287639) |
| 2025-08-27 | IDE extension, ChatGPT sign-in, hand off tasks between local and cloud, Code Reviews | [Changelog](https://learn.chatgpt.com/docs/changelog) |
| 2025-10-06 | Codex generally available; Slack, SDK, GitHub Action; cloud tasks count toward usage from 2025-10-20 | [Changelog](https://learn.chatgpt.com/docs/changelog) |
| 2026-02-02 | Codex desktop app for macOS launches | [What's new](https://learn.chatgpt.com/docs/whats-new) |
| 2026-04-16 | SSH remote connections begin rolling out in alpha | [Changelog](https://learn.chatgpt.com/docs/changelog) |
| 2026-05-14 | Codex in the ChatGPT mobile app (Remote) announced as a preview on iOS and Android; Mac host only | [9to5Mac](https://9to5mac.com/2026/05/14/openai-brings-codex-control-to-chatgpt-for-iphone-and-android/), [MacRumors](https://www.macrumors.com/2026/05/15/openai-brings-codex-chatgpt-mobile-app/), [TechCrunch](https://techcrunch.com/2026/05/14/openai-says-codex-is-coming-to-your-phone/) |
| 2026-05-29 | Remote supports Windows hosts | [Changelog](https://learn.chatgpt.com/docs/changelog) |
| 2026-06-18 | Handoff of a chat between local and remote hosts | [Changelog](https://learn.chatgpt.com/docs/changelog) |
| 2026-06-25 | Codex Remote generally available; one-to-one QR pairing per phone and host | [Changelog](https://learn.chatgpt.com/docs/changelog) |
| 2026-07-09 | Codex merges into the ChatGPT desktop app (all plans, including Free) | [What's new](https://learn.chatgpt.com/docs/whats-new) |
| 2026-09-29 | "All new Codex Cloud": reusable environments, tasks continue when the laptop is closed, start and follow from mobile | [TechCrunch](https://techcrunch.com/2026/09/29/openai-gives-codex-reusable-cloud-environments-that-work-across-devices/), [forum announcement](https://community.openai.com/t/meet-the-all-new-codex-cloud/1402399) |
| 2026-10-07 | ChatGPT for iOS 1.2026.272 (latest at time of writing) | [Changelog](https://learn.chatgpt.com/docs/changelog) |

## A.2 Two ways to run Codex from the phone

| | Cloud tasks | Remote (connected computer) |
|---|---|---|
| Where code runs | OpenAI-managed VM built from a published environment | Your Mac or Windows PC running the ChatGPT desktop app; also SSH hosts |
| Computer must be on | No; tasks run while your computer sleeps | Yes: awake, online, signed in to the same account and workspace |
| Start from phone | Choose Cloud plus an environment, describe the task | Choose a connected computer plus a project, describe the task |
| Create the environment | Web or desktop only; mobile can only select an existing published environment | Not applicable |
| Local files, tools, credentials | None; nothing transfers automatically from your machine | All host capabilities: files, shell, MCP, skills, browser, Computer Use |
| What you review | Responses, changed files, diffs, test results; then commit or open a PR | Responses, diffs, test results, terminal output, screenshots; approve commands |
| Sources | [Cloud](https://learn.chatgpt.com/docs/cloud), [Cloud environments](https://learn.chatgpt.com/docs/environments/cloud-environments), [Modes](https://learn.chatgpt.com/docs/environments/modes) | [Mobile](https://learn.chatgpt.com/docs/mobile), [Remote connections](https://learn.chatgpt.com/docs/remote-connections) |

## A.3 Cloud tasks from the phone

**What the phone can do** ([OpenAI docs: Codex Cloud](https://learn.chatgpt.com/docs/cloud), [Cloud environments](https://learn.chatgpt.com/docs/environments/cloud-environments), [Codex on mobile](https://learn.chatgpt.com/docs/mobile)):

- Select a published environment on mobile (open Codex, pick Cloud). Creating or editing an environment needs the web or desktop app (Work in, Cloud, Create environment). Repositories are chosen when the environment is created, so on the phone you pick the environment that already bundles them; picking a repository or branch per cloud task on mobile is not documented, since the docs say only that on mobile you open Codex, select a published environment and describe the task ([Cloud environments](https://learn.chatgpt.com/docs/environments/cloud-environments#start-a-task-in-codex-cloud)).
- Describe a task and send it. Each task gets an isolated workspace built from the environment. Reopen the same task on web, mobile or desktop to continue it.
- Review changed files and test results, request follow-ups, then commit or open a pull request.
- Tasks keep running while your computer sleeps. Saved VM state is recoverable for up to seven days after the last turn or resume.

**Environment model (OpenAI docs):**

- A reusable environment bundles repositories, dependencies, tools and access settings. Codex inspects the repos, installs dependencies, tests the workflow, and you review the setup report, then Save and Publish. Publishing captures the prepared filesystem for new tasks. Existing tasks keep their own files.
- Customization is conversational. Codex can record an install script and a "start skill" (instructions to start services).
- Internet access is off by default and configured per environment: package-manager presets or custom domains or unrestricted. Network secrets are swapped in by a proxy for allowed HTTPS destinations, so the raw credential is never placed in a local process or file. A personal vault supplies per-user values for shared environments.
- Tailscale is the only supported VPN provider. OIDC for cloud resources is available by request for Enterprise.
- Default VM per task: Plus and Edu Plus 2 vCPU, 8 GiB RAM, 8 GiB disk; Pro, Business, Enterprise, Edu 4 vCPU, 16 GiB RAM, 32 GiB disk.
- Documented limitations: no computer or browser use in cloud tasks yet; GitLab and self-hosted GitHub Enterprise Server are listed as roadmap items for the new cloud (see the GitLab note below); personal local skills do not sync to cloud environments (repo-stored skills do).
- Source for all bullets above: [Cloud environments](https://learn.chatgpt.com/docs/environments/cloud-environments).

**Legacy cloud tasks.** The older "Codex Cloud (Legacy)" still backs Code Review and the Linear and GitHub integrations, with deprecation planned (no date given). Legacy details: tasks run in a `universal` container, container state is cached up to 12 hours, setup scripts get internet access but the agent phase does not by default, and the agent returns an answer plus a diff that you can turn into a PR ([Legacy environments](https://learn.chatgpt.com/docs/environments/cloud-environment)).

**Multiple attempts (best-of-N).**

- Announced 2025-06-13: Codex can generate several responses at once for a single task, rolling out to Pro, Enterprise, Team, Edu and Plus ([forum post](https://community.openai.com/t/codex-generates-multiple-responses-simultaneously/1287639), [changelog](https://learn.chatgpt.com/docs/changelog)).
- The CLI lists an `attempt_total` field per cloud task ([CLI reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli)). A third-party article says `codex cloud exec --attempts` accepts 1 to 4 and that the web dashboard shows attempts side by side with no automatic ranking ([Daniel Vaughan, secondary](https://codex.danielvaughan.com/2026/04/01/codex-cloud-exec-best-of-n-attempts/)).
- Whether best-of-N still exists in the September 2026 "all new" Codex Cloud, and whether the iPhone UI shows attempts, is open **[unconfirmed: the CLI reference still documents `codex cloud exec --attempts` (1 to 4, "best-of-N") and the `attempt_total` field, but the Codex Cloud, Cloud environments and Codex on mobile pages and the iOS entries 1.2026.132 to 1.2026.272 of the [changelog](https://learn.chatgpt.com/docs/changelog) never mention attempts]**.

**Logs and diffs on mobile.** The docs say you can inspect responses, changed files, diffs and test results on mobile ([mobile](https://learn.chatgpt.com/docs/mobile)). A dedicated "logs" view for cloud tasks on iOS is **[unconfirmed: the Codex Cloud, Cloud environments and Codex on mobile pages list responses, changed files, diffs and test results only, and no iOS entry in the [changelog](https://learn.chatgpt.com/docs/changelog) mentions logs]**. For Remote tasks the phone receives terminal output and screenshots from the host ([Remote connections](https://learn.chatgpt.com/docs/remote-connections)).

**Starting cloud work from outside the app** (all create cloud tasks you can follow on the phone):

- GitHub: comment `@codex review` on a PR for a review (GitHub reviews flag only P0 and P1 issues); any other `@codex` comment starts a legacy cloud chat with the PR as context ([GitHub integration](https://learn.chatgpt.com/docs/third-party/github)).
- Slack: mention `@ChatGPT` with a repository; the task runs in Codex Cloud and the thread gets a "Follow along" link, a Cancel control and private Allow/Deny cards for approvals ([Slack](https://learn.chatgpt.com/docs/third-party/slack)).
- Linear: assign an issue to Codex or mention `@Codex`; progress posts back to the issue ([Linear](https://learn.chatgpt.com/docs/third-party/linear)).
- GitLab: a beta from 2026-08-19 lets `@codex` start cloud tasks from GitLab issues or merge requests ([changelog](https://learn.chatgpt.com/docs/changelog)). The new cloud docs list GitLab as not yet supported, so this likely refers to the legacy cloud (inference, not stated).
- CLI: `codex cloud` opens a picker; `codex cloud exec` submits; `codex cloud list` lists chats (JSON available); `codex apply` applies the latest cloud diff locally ([CLI reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli)).

**Plan availability for cloud tasks.** Plus, Pro, Business, Healthcare, Education and Enterprise per [Nerdschalk's DevDay summary](https://nerdschalk.com/codex-cloud-code-review-security-cloud/). OpenAI's pricing page lists Codex on web, CLI, IDE and iOS for Plus and cloud integrations (code review, Slack) as Plus and above; Free and Go get the desktop app with GPT-6 Luna only ([Pricing](https://learn.chatgpt.com/docs/pricing)).

## A.4 Remote: controlling a connected computer from the iPhone

### Setup and pairing (OpenAI docs)

1. On the Mac or Windows PC, open the ChatGPT desktop app: Settings, Connections, "Control this Mac or PC", then Set up or Add. Approve remote access and complete verification (MFA, SSO or passkey if required).
2. Scan the QR code with the phone, sign in to the same account and workspace, approve the connection.
3. In the iOS app, open Codex (or Remote on older builds), pick the computer, start or continue a task.

Rules and requirements: each phone is paired with each host separately; connections used since 2026-06-08 stay paired, older inactive ones must pair again; setup cannot be started from the Codex CLI or IDE extension; Codex access is needed in the account and workspace; workspace admins may need to enable Remote Control; the host must be awake, online and signed in; signing out turns Remote Control off but keeps pairings. Sources: [Codex on mobile](https://learn.chatgpt.com/docs/mobile), [Remote connections](https://learn.chatgpt.com/docs/remote-connections).

Manual pairing codes exist (added in 1.2026.160; the entry field accepts pasted formatted codes since 1.2026.272) ([changelog](https://learn.chatgpt.com/docs/changelog)). For headless hosts, the CLI documents `codex remote-control start`, `stop` and `pair` (creates a short-lived manual pairing code) ([CLI reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli)). The Remote connections page itself does not mention that command and says setup cannot start from the CLI, so the two OpenAI pages are not fully aligned. A user report describes pairing a Linux server this way and calls it more work than Claude Code ([Hacker News, user report](https://news.ycombinator.com/item?id=48850170)).

### Host support

- Mac and Windows hosts running the ChatGPT desktop app. Mac at launch (2026-05-14); Windows from 2026-05-29 ([changelog](https://learn.chatgpt.com/docs/changelog)).
- SSH hosts: the desktop app adds hosts from `~/.ssh/config` and runs commands and file operations there ([Remote connections](https://learn.chatgpt.com/docs/remote-connections)). Users expect SSH projects of a connected Mac to appear on the phone; issue [#23527](https://github.com/openai/codex/issues/23527) (open since 2026-05-19, still receiving duplicates on 2026-10-13) reports they do not, with a late-September comment saying remote projects can be activated under Settings, Connections. The iOS release notes also mention SSH connections to Windows machines (1.2026.146) and SSH hosts that use private keys or no credentials (1.2026.181) ([changelog](https://learn.chatgpt.com/docs/changelog)). The phone reaches SSH hosts in two ways. The Remote connections page describes connecting the desktop app host to the SSH environment, after which "your phone still connects to the same host" ([Remote connections](https://learn.chatgpt.com/docs/remote-connections#choose-what-to-connect)). The iOS app also has its own "Add SSH Host" form (display name, host, port, user name; password only at launch), so the phone can connect to an SSH host directly; the key support in 1.2026.181 is for this form. Users report that the host must then be reachable from the phone's own network, and that only Ed25519 or ECDSA keys in PKCS#8 or SEC1 PEM format work, not OpenSSH-format keys ([#23543](https://github.com/openai/codex/issues/23543), [#23466](https://github.com/openai/codex/issues/23466), [#22857](https://github.com/openai/codex/issues/22857), user reports) (corrected 2026-10-15).
- Linux is not a documented phone-accessible host in the Remote page. A GitHub request for headless Linux hosts has been open since 2026-05-17 with no maintainer reply ([openai/codex #23200](https://github.com/openai/codex/issues/23200), user report). A ChatGPT desktop app for Linux has been in public preview since 2026-08-14 (Ubuntu, Debian, Fedora, and now Arch), but the Remote page still lists only macOS and Windows desktop hosts ([Linux app](https://learn.chatgpt.com/docs/linux/linux-app), [ChatGPT release notes, 2026-08-14 (archived)](https://web.archive.org/web/20261010013210/https://help.openai.com/en/articles/6825453-chatgpt-release-notes)) (added 2026-10-15).
- Multiple hosts: the phone can switch between connected hosts and shows unavailable hosts in the task list (1.2026.195).

### Security and architecture statements

- OpenAI docs: Files, credentials, permissions and local setup stay on the host; only updates go to the phone. A relay layer keeps authorized machines reachable without direct public internet exposure. Host sandboxing and approvals still apply. OpenAI recommends a VPN or mesh tool for access across networks and warns against exposing app-server transports on shared or public networks ([Remote connections](https://learn.chatgpt.com/docs/remote-connections)).
- OpenAI's launch framing, as reported: the feature goes beyond remotely controlling one task or dispatching tasks to your computer, and lets you work across all your threads ([TechCrunch](https://techcrunch.com/2026/05/14/openai-says-codex-is-coming-to-your-phone/)).
- A third-party write-up describes Ed25519 identity, X25519 key exchange, AES-256-GCM sessions and a metadata-only relay ([Daniel Vaughan](https://codex.danielvaughan.com/2026/05/15/codex-mobile-chatgpt-app-relay-architecture-remote-agent-control/)). These details describe Remodex, the third-party client, not OpenAI's relay: Remodex's open-source bridge uses Ed25519 identity keys, X25519 with HKDF-SHA256 and AES-256-GCM, and its relay README says the relay logs only connection metadata and payload sizes ([Remodex bridge source](https://github.com/Emanuele-web04/remodex/blob/main/phodex-bridge/src/secure-transport.js), [relay README](https://github.com/Emanuele-web04/remodex/blob/main/relay/README.md)). OpenAI has published no cryptographic design for its own relay beyond the "secure relay layer" sentence above (corrected 2026-10-15).
- Optional Face ID or passcode lock for Codex (1.2026.146; the release note scopes it to Codex, not the whole app) ([changelog](https://learn.chatgpt.com/docs/changelog)) (corrected 2026-10-15).

### What the phone can do (consolidated from docs and release notes)

- Start new tasks; choose Cloud plus environment, or a computer plus project; pick a directory with a directory picker; choose branch, create a worktree, run setup scripts; choose a starting branch or include local changes; the app remembers worktree mode and setup environment per project.
- Follow progress, resume tasks, see when input is needed; steer an active task or queue a follow-up (default configurable); edit the latest sent prompt; restore unsent drafts when switching tasks, hosts or workspaces.
- Approve actions with Approve, Always approve, Tell Codex what to do, or Deny ([Codex on mobile](https://learn.chatgpt.com/docs/mobile)); MCP approvals can apply to the current chat or all chats; the approval picker was redesigned in 1.2026.272.
- Review responses, changed files, diffs and test results; diff controls include line wrapping, expand and collapse, large-diff handling, nested Git repo browsing and inline review comments ([What's new digests for June and July](https://learn.chatgpt.com/docs/whats-new)), and staged, unstaged, branch and last-turn filters ([LinkLoot, secondary](https://linkloot.io/blog/chatgpt-ios-12026181-codex-mobile-task-management)).
- Browse the workspace: file browser, recent files, back navigation, remembered reading positions, create folders from the picker.
- Use `/goal` (set, edit, pause, resume), `/side` side chats (carry attachments, selected text, review comments), fork tasks, `@` mention other tasks, reference selected transcript text in the composer.
- Attach photos, camera captures and files; attachments work across all connected hosts including Windows and Linux.
- Dictate or use voice from a task composer; voice follows the selected model and effort and can continue actions in the background.
- Change model and reasoning effort; Fast mode choice is saved per task.
- Per-host personality (Friendly, Pragmatic).
- Interactive forms and inline visualizations in tasks; inline page previews in responses.
- Search tasks by title and conversation content across connected hosts; browse archived threads; pinned chats sync with desktop.
- See usage limits and credit details in the task menu, and a profile screen with usage stats.
- Sources: iOS entries in the [Codex changelog](https://learn.chatgpt.com/docs/changelog) and the weekly digests in [What's new](https://learn.chatgpt.com/docs/whats-new).

What the phone cannot do: edit files directly, run shell commands manually, configure plugins or MCP servers, change `config.toml` ([Daniel Vaughan](https://codex.danielvaughan.com/2026/05/15/codex-mobile-chatgpt-app-relay-architecture-remote-agent-control/)). OpenAI's docs match this scope: the phone sends prompts, approvals and follow-up messages, while shell commands, MCP servers and skills come from the host's configuration ([Remote connections](https://learn.chatgpt.com/docs/remote-connections#what-comes-from-the-connected-host)); the iOS file browser is for previewing files and linking paths into prompts (1.2026.160); and on mobile you use the plugins already available to your account ([Plugins](https://learn.chatgpt.com/docs/plugins)). No doc or iOS release note describes file editing, a manual shell, MCP or plugin configuration, or `config.toml` editing on the phone. The author of one guide treats the phone as a place for decision points rather than a full IDE, and notes it lacks CLI parity ([vanja.io, secondary](https://vanja.io/codex-mobile/)).

### iOS release history (ChatGPT for iOS, Codex-related entries)

Dates are the changelog dates; App Store dates differ by a day or so. Entries before 1.2026.244 come from a single summarized pass of the changelog ([source for all rows](https://learn.chatgpt.com/docs/changelog)). Rows for 1.2026.244 to 1.2026.272 were read in full.

| Version | Date | Highlights |
|---|---|---|
| 1.2026.132 | 2026-05-18 | Open completed Codex tasks from iOS notifications; better resume and reconnect |
| 1.2026.139 | 2026-05-25 | Spotlight and Shortcuts entry points for Codex Mobile; browse archived threads; save or copy rendered images |
| 1.2026.146 | 2026-06-02 | Optional Face ID or passcode lock; default follow-up behavior (Queue or Steer); SSH to Windows; `/side` |
| 1.2026.153 | 2026-06-09 | Branch choice, worktree creation, setup scripts; profile screen with usage stats; `/goal`; edit latest sent prompt |
| 1.2026.160 | 2026-06-15 | Workspace file browser and directory picker; MCP approval scopes; manual pairing codes; host selection after pairing |
| 1.2026.167 | 2026-06-22 | Per-host personality; edit goals in the composer |
| 1.2026.181 | 2026-07-06 | Create, search, open, fork and manage tasks from a conversation; SSH hosts with keys; "Needs input" status; usage and credits in the task menu |
| 1.2026.188 | 2026-07-13 | Inline visualizations; composer controls stay above the keyboard; Fast mode saved per task |
| 1.2026.195 | 2026-07-20 | Interactive forms in tasks; restore unsent prompts across tasks and hosts; sort by recent activity; unavailable hosts shown |
| 1.2026.202 | 2026-07-27 | Voice uses the chosen voice and shows usage-limit warnings; better reconnect on return or Face ID unlock |
| 1.2026.209 | 2026-08-07 | Clearer reconnect progress with tasks still usable; approvals and input requests recover after reconnect |
| 1.2026.223 | 2026-08-18 | Setting to open ChatGPT in Codex Remote on launch; voice from existing task composers, actions continue in background |
| 1.2026.230 | 2026-08-26 | Task search across titles and content; configurable Home Screen shortcuts for ChatGPT, Work, Remote; faster long threads |
| 1.2026.237 | 2026-09-01 | Attachments on all hosts; priority view (running, unread, awaiting you); queued prompts sync to host and send in background; live working time |
| 1.2026.244 | 2026-09-08 | `@` mentions of other tasks; answer live questions without losing your draft; file explorer with recents and reading positions; starting branch for worktrees; worktree setup continues in background on iOS 26 with a Live Activity; voice respects model and effort |
| 1.2026.251 | 2026-09-18 | Create folders from file picker; writing blocks with draft alternatives; per-project worktree defaults; compact preview for long queued prompts; thinking timer fix |
| 1.2026.258 | 2026-09-23 | Redesigned home screen; iPad landscape split view with task list beside the open task; nested Git repo browsing; side chats carry attachments, selection and review comments; pairing fix for wrong device clock |
| 1.2026.267 | 2026-10-02 | Home Screen widgets for recent tasks; Home and Lock Screen widgets for remaining usage and reset times; keep keyboard open after send; canceling a queued prompt restores text and attachments |
| 1.2026.272 | 2026-10-07 | Inline page previews; open Codex task links directly; redesigned approval picker; single Plugins entry in the plus menu; faster streaming in long threads; tasks keep the selected computer when it is offline; clearer manual pairing entry |

### Voice in Codex

ChatGPT Voice (GPT-Live) works in Chat, Work and Codex on the desktop app and through Remote on iOS ([Voice docs](https://learn.chatgpt.com/docs/features/voice)). In Codex it can start separate tasks, check on tasks and send follow-ups, and follows the same permissions as the tasks it directs. Desktop voice is billed at $0.05 per minute against Codex usage (1.25 credits per minute on Business, Edu and Enterprise credit billing) ([Pricing](https://learn.chatgpt.com/docs/pricing)). MacStories describes a "Remote voice" mode that runs in Codex on the Mac and can be opened from Control Center and the Lock Screen ([MacStories](https://www.macstories.net/ios/openai-updates-chatgpt-for-ios-with-customizable-widgets-for-chatgpt-work-and-codex-remote/)).

## A.5 Monitoring or connecting to local Codex sessions from the phone

| Local surface | Phone visibility | Notes | Source |
|---|---|---|---|
| ChatGPT desktop app (formerly the Codex app; Mac and Windows) | Yes, via Remote | The official path. Pair via QR in Settings, Connections | [Remote connections](https://learn.chatgpt.com/docs/remote-connections) |
| Codex CLI (headless or terminal) | Partly | `codex remote-control start/stop/pair` runs a managed app-server daemon with remote control and creates a manual pairing code. `codex agents --remote <URL>` and `codex --remote ws://...` connect a terminal client to a shared app server. `codex queue` can queue a message to an existing session. The Remote page says setup cannot start from the CLI | [CLI reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli), [app-server](https://learn.chatgpt.com/docs/app-server) |
| CLI-started chats | Unreliable per users | One thread reports chats started in the CLI would not open on iOS while chats from the macOS app did, and that remote stopped working when both CLI and desktop app were open | [openai/codex #28340](https://github.com/openai/codex/issues/28340) (user report) |
| IDE extension | Not documented | The IDE page does not mention remote or mobile; setup cannot start from the IDE | [IDE](https://learn.chatgpt.com/docs/codex/ide) |
| External notification | Yes, DIY | A `notify` config runs an external program when a turn completes; users pair this with Pushover | [Notifications](https://learn.chatgpt.com/docs/notifications), [HN](https://news.ycombinator.com/item?id=48850170) (user report) |
| Third-party iOS clients | Yes | Remodex is an indie iOS client for the Codex App Server, QR pairing, Tailscale recommended, $3.99 per month or $29.99 per year, no iPad version (as of April 2026) | [MacStories](https://www.macstories.net/reviews/remodex-codex-remote-mobile-app-ios/) |

Relevant for opencode: OpenAI's own app-server docs warn that its WebSocket transport is experimental and that non-loopback listeners accept unauthenticated connections by default during rollout, so auth must be configured first ([app-server](https://learn.chatgpt.com/docs/app-server)).

## A.6 Handoff between surfaces

| Handoff | Status | Details | Source |
|---|---|---|---|
| Local to worktree and back (desktop) | Shipped 2026-03 | Moves a chat and its work between Local and Worktree | [What's new](https://learn.chatgpt.com/docs/whats-new), [Glossary](https://learn.chatgpt.com/docs/glossary) |
| Local to remote host and back | Shipped 2026-06-18 | Open the chat in the desktop app, choose the destination in the footer, Review, Hand off. Needs a saved project for the same Git repo on both hosts. Codex creates or reuses a worktree on the destination. A running response is interrupted first. The requesting chat cannot be handed off. Cloud environments are not supported as a destination | [Remote connections](https://learn.chatgpt.com/docs/remote-connections) |
| IDE to cloud and cloud to local | Shipped 2025-08-27 | Tasks can be handed between local and cloud with the changes applied locally; the IDE keeps the chat available when you return | [Changelog](https://learn.chatgpt.com/docs/changelog), [IDE](https://learn.chatgpt.com/docs/codex/ide) |
| CLI session to desktop app | Shipped | `/app` continues the session in the desktop app | [CLI reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli) |
| Cloud task to local repo | Shipped | `codex apply` applies the latest cloud diff locally | [CLI reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli) |
| Desktop Work to mobile (Work across devices) | Announced 2026-09-29 | Start a synced Work task on desktop and continue on web or mobile; local steps need the computer online; if offline an eligible task can continue in a cloud container without local files. Needs desktop app 26.929 or later | [Cloud-local access](https://learn.chatgpt.com/docs/enterprise/cloud-local-access), [Get started with Work](https://learn.chatgpt.com/docs/get-started-with-work) |
| Pinned chats | Shipped 2026-08 | Pinned chats stay in sync between desktop and iOS | [What's new](https://learn.chatgpt.com/docs/whats-new) |
| Local conversation sync | Documented | Syncing a local conversation does not upload the local folder or make it available to another computer | [Projects](https://learn.chatgpt.com/docs/projects) |

A Hacker News commenter says `/handoff` in the app moves a local session to the cloud so you can continue from the phone, while another notes `/handoff` is not in the CLI (user reports, [HN](https://news.ycombinator.com/item?id=48850170)). The desktop app's slash-command reference lists no `/handoff`; the closest command is `/cloud`, which runs the chat in the cloud when cloud execution is available ([Slash commands](https://learn.chatgpt.com/docs/reference/slash-commands)). The Remote page says handoff to a Codex cloud environment is not supported, so the HN description does not match current docs, and whether `/cloud` carries an existing local chat's changes along is not documented (corrected 2026-10-15).

## A.7 Code review and pull requests

- **Desktop and web Code Review plugin.** PR inbox (Assigned to me, Assigned to my team, Authored by me), Summary and Changes tabs, pin PRs, mark files viewed, Stack for dependent PRs, "Review with Codex" opens a chat, Checks can be attached with Fix, Submit review (Comment, Approve, Request changes). Asking Codex in chat never posts comments, approves or merges by itself. GitHub is generally available; GitLab merge requests are in preview ([Code review](https://learn.chatgpt.com/docs/code-review)). The page does not mention mobile.
- **Automatic cloud reviews** run before you open a PR when the ChatGPT Codex connector and permissions are set. `@codex review` triggers one from a GitHub or GitLab comment ([Code review](https://learn.chatgpt.com/docs/code-review), [GitHub](https://learn.chatgpt.com/docs/third-party/github)). Nerdschalk lists code review as available on all plans and Security Cloud on Pro, Business, Enterprise and Edu ([Nerdschalk](https://nerdschalk.com/codex-cloud-code-review-security-cloud/)).
- **On the phone**, review means the diff viewer and inline review comments for the host's working tree (staged, unstaged, branch, last turn), plus code reviews that the 1.2026.244 notes say complete more reliably, which implies `/review` runs from mobile ([changelog](https://learn.chatgpt.com/docs/changelog), inference). The PR inbox and review submission are not offered on the phone: OpenAI's 2026-09-29 release note says PR review through the Code Review plugin is available "on supported desktop and web experiences" ([ChatGPT release notes (archived)](https://web.archive.org/web/20261010013210/https://help.openai.com/en/articles/6825453-chatgpt-release-notes)), and the Code Review page has only desktop app and web variants ([Code review](https://learn.chatgpt.com/docs/code-review)) (corrected 2026-10-15).
- **PR creation.** Cloud tasks end with committing or opening a pull request ([Cloud](https://learn.chatgpt.com/docs/cloud)). The 2025 iOS launch lets you push PRs from the phone ([changelog](https://learn.chatgpt.com/docs/changelog)). Creating a PR from a Remote (local) task on the phone is **[unconfirmed: no iOS entry from 1.2026.132 to 1.2026.272 in the [changelog](https://learn.chatgpt.com/docs/changelog), and neither the Codex on mobile nor the Remote connections page, mentions a commit or pull-request control for Remote tasks]**.

## A.8 Notifications for Codex

- Open completed Codex tasks directly from iOS notifications (1.2026.132); the phone gets alerts when a task completes or needs attention ([Remote connections](https://learn.chatgpt.com/docs/remote-connections)).
- Approval requests send push notifications ([Daniel Vaughan](https://codex.danielvaughan.com/2026/05/15/codex-mobile-chatgpt-app-relay-architecture-remote-agent-control/), secondary); the app also surfaces them in the task list as an "Awaiting approval" badge ([#39346](https://github.com/openai/codex/issues/39346), user report).
- Fewer unnecessary phone notifications while you are already using ChatGPT (2026-10-09 dots update) ([What's new](https://learn.chatgpt.com/docs/whats-new/october-5-9-2026)).
- Desktop adds a notification sound setting for completions, permission requests and questions (2026-09-22) and an Activity view (bell icon) listing unread, running and waiting chats ([changelog](https://learn.chatgpt.com/docs/changelog), [Notifications](https://learn.chatgpt.com/docs/notifications)).
- Web notification settings cover push, email and SMS channels by category ([Notifications](https://learn.chatgpt.com/docs/notifications)). The notifications page has no iOS-specific section.
- Live Activities: cloud-task monitoring on the Lock Screen (2025) and worktree setup progress (2026) ([AlternativeTo](https://alternativeto.net/news/2025/5/openai-integrates-codex-into-chatgpt-ios-app), [changelog](https://learn.chatgpt.com/docs/changelog)). Ordinary running Remote tasks get no Live Activity: the only Remote-side Live Activity in the iOS release notes is worktree setup (1.2026.244), and a request for one covering tasks running on a Mac has been open since 2026-07-23 ([#34912](https://github.com/openai/codex/issues/34912), user report) (corrected 2026-10-15).
- Known delivery problems are in section D.

## A.9 Is there a standalone Codex mobile app?

No evidence of one as of 2026-10-15.

- OpenAI's own docs tell you to open Codex inside the ChatGPT iOS app ([Codex on mobile](https://learn.chatgpt.com/docs/mobile)).
- AICatchup states that no separate Codex mobile app exists ([AICatchup](https://aicatchup.com/news/codex-chatgpt-mobile-preview)).
- In April 2026 MacStories reported that OpenAI staff had been hinting at a native Codex iOS app, and titled its Remodex review as the best client only until OpenAI ships an official Codex mobile app ([MacStories](https://www.macstories.net/reviews/remodex-codex-remote-mobile-app-ios/)).
- App Store check on 2026-10-15: the developer OpenAI OpCo, LLC (ID 1684349733) publishes only two apps in the US and UK stores, ChatGPT and ChatGPT for Intune, and searches for "codex" return only third-party clients ([iTunes lookup](https://itunes.apple.com/lookup?id=1684349733&entity=software&country=us), [iTunes search](https://itunes.apple.com/search?term=codex&entity=software&country=us)).

## A.10 Plans, limits and cost for Codex mobile

- **Remote availability: all plans, including Free and Go.** OpenAI's release notes say the 2026-05-14 preview rolled out on iOS and Android "across all plans, including Free and Go", and the 2026-06-25 note says Codex Remote "is now generally available on all ChatGPT plans" ([ChatGPT release notes (archived)](https://web.archive.org/web/20261010013210/https://help.openai.com/en/articles/6825453-chatgpt-release-notes)). Launch coverage agrees ([Verdent](https://www.verdent.ai/guides/codex-in-chatgpt-mobile), [TechCrunch](https://techcrunch.com/2026/05/14/openai-says-codex-is-coming-to-your-phone/)). The pricing page lists mobile remote control for Plus, Pro, Business and Enterprise and not with an API key, but its feature table has no Free or Go column, so it does not contradict the release notes ([Pricing](https://learn.chatgpt.com/docs/pricing)) (corrected 2026-10-15: the first draft called these sources conflicting).
- **Usage.** Work and Codex share limits and credits. Plus has estimated local-message ranges per five hours (for example GPT-6.1 Sol 15 to 160, GPT-6 Luna 350 to 3,000); Pro has no five-hour limit "currently"; Fast mode costs 2.5x included usage (2x on credits) and Ultrafast 8x (6x) ([Pricing](https://learn.chatgpt.com/docs/pricing), [Speed](https://learn.chatgpt.com/docs/agent-configuration/speed)). The five-hour limit for Plus was lifted for some weeks and restored on 2026-08-25 ([9to5Mac](https://9to5mac.com/2026/08/24/openai-restores-5-hour-codex-and-work-limits-for-chatgpt-plus-users/)).
- **Models.** Astra, GPT-6.1 Sol, GPT-6 Sol and Luna are the Codex models; GPT-5.5 retired on 2026-10-14 ([Models](https://learn.chatgpt.com/docs/models)).
- **Enterprise.** Admins can restrict mobile access, and Remote Control may need admin enablement ([Remote connections](https://learn.chatgpt.com/docs/remote-connections)).

---

# Part B. General ChatGPT iOS app features

For each feature: what it is and UX specifics, launch date, plans, source.

## B.1 App facts (App Store listing)

- Developer OpenAI OpCo, LLC; category Productivity; free with in-app purchases. Requires iOS and iPadOS 18.0 or later and visionOS 2.0 or later (presumably the iPad app running on Vision Pro; inference). Apple Watch and Mac are not listed. Size 271.7 MB. Rating 4.8 from 11 million ratings. Age 13+ with Age Assurance and Parental Controls. 60 languages ([App Store](https://apps.apple.com/us/app/chatgpt/id6448311069), read 2026-10-15).
- In-app purchases: ChatGPT Go $8.00, Plus $19.99, Pro 100 $100, Pro 200 $200, Pro 500 $500, credit packs $4 (100), $20 (500), $40 (1,000) ([App Store](https://apps.apple.com/us/app/chatgpt/id6448311069)).
- Cadence: builds from 1.2026.125 (May 11) to 1.2026.272 (Oct 6). The store What's New text is the same generic bug-fix line on every version, so real release detail lives in the Codex changelog (iOS entries) and the ChatGPT release notes ([App Store](https://apps.apple.com/us/app/chatgpt/id6448311069)).
- OpenAI also posts weekly "feature drops" on X (consumer product lead Adam Fry) ([9to5Mac](https://9to5mac.com/2026/08/21/chatgpts-iphone-app-gets-a-handy-shortcut-to-attach-recent-photos-more-quickly/)).

## B.2 Streaming chat UI and composer

- **Streaming with early answers (GPT-6).** From 2026-10-07 ChatGPT can start answering while it is still reasoning or using tools and add to the answer progressively. OpenAI says GPT-6 Instant starts web-search answers 44 percent sooner than GPT-5.6 Instant. Cited answers show a Sources button ([9to5Mac](https://9to5mac.com/2026/10/07/openai-brings-gpt-6-to-chatgpt-and-debuts-intelligent-ui/), [Search Engine Journal](https://www.searchenginejournal.com/chatgpt-gpt-6-intelligent-ui/592249/)).
- **Plus menu and long-press shortcuts.** The composer's + button offers photos, camera and files. Long-pressing + shows your four most recent photos (2026-08-21) ([9to5Mac](https://9to5mac.com/2026/08/21/chatgpts-iphone-app-gets-a-handy-shortcut-to-attach-recent-photos-more-quickly/), [The Next Web](https://thenextweb.com/news/chatgpt-iphone-recent-photos-shortcut-siri-eu-delay)). One outlet adds that it needs photo-library access and that users who granted only "Selected Photos" may see recent photos missing ([Digital Trends, seen in search results only](https://www.digitaltrends.com/phones/chatgpt-for-iphone-now-lets-users-grab-recent-photos-with-a-long-press/)). MacStories calls the redesigned "latest photos" picker (long-press +) part of the August update ([MacStories](https://www.macstories.net/ios/openai-updates-chatgpt-for-ios-with-customizable-widgets-for-chatgpt-work-and-codex-remote/)).
- **Long-press send for a one-off model choice.** OpenAI's release notes of 2026-06-08 say paid users on iOS can long-press the send button to choose a model for a single message without changing their default ([ChatGPT release notes (archived)](https://web.archive.org/web/20261010013210/https://help.openai.com/en/articles/6825453-chatgpt-release-notes)); Digital Today described it on 2026-06-19 as a hidden menu offering High, Medium and Instant ([Digital Today](https://www.digitaltoday.co.kr/en/view/69654/chatgpt-ios-hidden-setting-lets-users-adjust-reasoning-time-per-question)) (corrected 2026-10-15: the first draft said it was not formally announced). Later releases added a visible slider (B.3).
- **Plugins entry.** One "Plugins" entry in the composer's plus menu (1.2026.272); the composer also suggests installed plugins and their skills (1.2026.202) ([changelog](https://learn.chatgpt.com/docs/changelog), [What's new](https://learn.chatgpt.com/docs/whats-new)).
- **Keyboard behavior.** Setting to keep the keyboard open after sending (1.2026.267), composer controls above the keyboard (1.2026.188), smoother keyboard transitions (1.2026.267 and .272). These are in Codex task composers ([changelog](https://learn.chatgpt.com/docs/changelog)); whether the same setting applies to Chat is **[unconfirmed: the setting appears only in the iOS 1.2026.267 entry of the Codex changelog, and the ChatGPT release notes (archived 2026-10-10) do not mention it]**.
- **Long threads.** Faster loading of long conversations and clearer UI while waiting for a connection (2026-08-21 drop) ([9to5Mac](https://9to5mac.com/2026/08/21/chatgpts-iphone-app-gets-a-handy-shortcut-to-attach-recent-photos-more-quickly/)); faster streaming and fewer freezes in long Codex threads (1.2026.272).
- **Writing blocks** with draft alternatives and copy actions (1.2026.251) ([changelog](https://learn.chatgpt.com/docs/changelog)).
- **Pastes over 10,000 characters** become attachments on every plan (week of 2026-08-03) ([What's new](https://learn.chatgpt.com/docs/whats-new)).

## B.3 Model picker and reasoning effort

| Item | Detail | Date | Plans | Source |
|---|---|---|---|---|
| GPT-6 in Chat | Replaces "Latest" in the model menu. Sol for paid, Luna for Free and Go. GPT-5.6 Sol remains selectable. The Pro thinking level runs on Astra | 2026-10-07 (Free and Go 10-08) | Plus, Pro, Business, Enterprise (admin-gated), then Free and Go | [Search Engine Journal](https://www.searchenginejournal.com/chatgpt-gpt-6-intelligent-ui/592249/), [9to5Mac](https://9to5mac.com/2026/10/07/openai-brings-gpt-6-to-chatgpt-and-debuts-intelligent-ui/) |
| Thinking-level slider | Instant and Thinking merged for Plus and Pro on GPT-5.6 Sol; a slider sets reasoning effort per response on web, mobile and desktop | 2026-08-06 | Plus, Pro | [9to5Mac](https://9to5mac.com/2026/08/06/openai-updating-chatgpt-with-a-smarter-gpt-5-6-sol-and-unlimited-free-chats/) |
| Slider labels | Instant, Medium, High, Extra High. They replaced Thinking Standard, Extended and Heavy in the model picker on 2026-06-10 (Thinking Light was dropped), when Extra High, Pro Standard and Pro Extended were Pro-only; GPT-6 Intelligent UI works "from Instant through Extra High" (2026-10-07) (corrected 2026-10-15) | 2026-06-10 | Plus and Pro (Extra High Pro-only at launch) | [ChatGPT release notes (archived)](https://web.archive.org/web/20261010013210/https://help.openai.com/en/articles/6825453-chatgpt-release-notes) |
| Think button | Free users can give GPT-5.6 Luna more time; unlimited text chats on Luna | 2026-08-06 | Free | [9to5Mac](https://9to5mac.com/2026/08/06/openai-updating-chatgpt-with-a-smarter-gpt-5-6-sol-and-unlimited-free-chats/) |
| Automatic Instant to Thinking switching retired | Manual selection stays | 2026-09-14 | Plus, Pro | [Releasebot](https://releasebot.io/updates/openai/chatgpt) (mirror of release notes) |
| Work and Codex picker | GPT-6 Astra, GPT-6.1 Sol, GPT-6 Sol, GPT-6 Luna; effort Light (Low in CLI), Medium, High, Extra High; Max adds reasoning time; Ultra uses subagents; Standard, Fast, Ultrafast speeds | 2026-07 to 2026-10 | varies, GPT-6.1 Sol not in Free and Go; Ultrafast only Pro $500 and eligible Enterprise and Edu | [Models](https://learn.chatgpt.com/docs/models), [Speed](https://learn.chatgpt.com/docs/agent-configuration/speed) |
| Dots | You do not choose a model, effort or speed | 2026-09-29 | Pro, Business Premium | [MacStories](https://www.macstories.net/stories/openais-dots-a-first-look/) |

On mobile specifically: Codex tasks keep task-scoped model and reasoning settings, Fast mode is saved per task, and voice follows the selected model and effort ([changelog](https://learn.chatgpt.com/docs/changelog)).

## B.4 Interactive answers, visualizations and inline UI

- **Intelligent UI (GPT-6).** Answers can mix text with tappable buttons, forms, charts and small tools such as calculators or bill splitters; the model picks the layout per question and plain text remains possible. Rolling out to Plus, Pro, Business and Enterprise on 2026-10-07 and to Free and Go on 2026-10-08; needs updated apps (older macOS and Windows apps do not support it); not available at the Pro thinking level; a "Layout and visuals" setting can reduce it on web ([Search Engine Journal](https://www.searchenginejournal.com/chatgpt-gpt-6-intelligent-ui/592249/), [9to5Mac](https://9to5mac.com/2026/10/07/openai-brings-gpt-6-to-chatgpt-and-debuts-intelligent-ui/)).
- **Visualize plugin.** Charts, maps, diagrams, calculators and simulations you can adjust in chat; invoke with `@Visualize`; mobile apps are rolling out to eligible accounts; not rendered in the CLI or IDE ([Visualizations](https://learn.chatgpt.com/docs/visualizations)).
- **Flashcards.** Interactive, savable, shuffleable decks on mobile and web for all plans (2026-09-22) ([Releasebot](https://releasebot.io/updates/openai/chatgpt)).
- **In Codex tasks.** Inline visualizations (1.2026.188), interactive forms (1.2026.195), inline page previews (1.2026.272), inline tables and visual themes (1.2026.202) ([changelog](https://learn.chatgpt.com/docs/changelog), [What's new](https://learn.chatgpt.com/docs/whats-new)).
- **Plugin Extensions.** Developers can add sidebar apps, conversation panels, file viewers and forms; composer mentions are desktop-only; Free and Go web extensions "coming soon" ([DevDay 2026](https://learn.chatgpt.com/docs/whats-new/devday-2026)).

## B.5 Voice (standard, GPT-Live, video, screen share)

| Feature | Detail | Date | Plans | Source |
|---|---|---|---|---|
| Voice inside the chat | Voice runs in the main chat window with live transcript, and images and maps show during the conversation; "Separate mode" stays in Settings, Voice | 2025-11-25 | All, per coverage | [Gulf News](https://gulfnews.com/technology/openai-integrates-chatgpt-voice-into-main-chat-interface-1.500360920) (secondary, seen in search results) |
| Advanced Voice with video and screen share | Camera button in a voice conversation; Share Screen from the three-dot menu; per-day and per-conversation limits | 2024-12 (iOS 1.2024.339) | Team, most Plus and Pro first; not EU and several other regions; Enterprise and Edu later | [Neowin](https://www.neowin.net/news/chatgpt-mobile-apps-now-support-video-and-screensharing-in-advanced-voice-mode/) (search result; page not fetchable) |
| GPT-Live full-duplex voice | Listens while speaking, interruptions and pauses handled, can stay silent until addressed, live translation, hands hard questions to text models and shows some visuals. Live replaced Advanced as the default ChatGPT Voice (GPT-Live-1 for paid users, GPT-Live-1 mini for Free; OpenAI's [Voice article](https://help.openai.com/en/articles/20001274-chatgpt-voice), updated 2026-10-15, now names GPT-Live-1.1 and GPT-Live-1.1 Quip); Advanced and Standard stay selectable | 2026-07-08 | Live limits per rolling 24 hours: Free limited GPT-Live-1 mini; Go 3 hours of GPT-Live-1 mini; Plus 3 hours of GPT-Live-1; Pro $100 15 hours; Pro $200 unlimited; Business Standard 3 hours and Business Premium 15 hours, then 1.25 credits a minute; Enterprise and Edu billed per minute (credits or $0.05). Not in Business, Enterprise or Edu workspaces at launch; available in eligible workspaces now (corrected 2026-10-15) | [TechCrunch](https://techcrunch.com/2026/07/08/openai-releases-new-voice-models-for-more-natural-live-conversations/), [Ubergizmo](https://www.ubergizmo.com/2026/07/finally-chatgpt-voice-will-stop-interrupting-you-mid-sentence/), [ChatGPT release notes, 2026-07-08 (archived)](https://web.archive.org/web/20261010013210/https://help.openai.com/en/articles/6825453-chatgpt-release-notes), [ChatGPT Voice help article (archived 2026-10-15)](https://web.archive.org/web/20261015092947/https://help.openai.com/en/articles/20001274-chatgpt-voice) |
| Voice modes | Live, Advanced and Standard under Settings, Voice. Live lacks video and screen share, so use Advanced for those on iOS and Android; Standard is turn-by-turn and transcribes speech before answering | 2026 | per plan, workspace, region, app version and parental controls | [ChatGPT Voice help article (archived 2026-10-15)](https://web.archive.org/web/20261015092947/https://help.openai.com/en/articles/20001274-chatgpt-voice) |
| Plugins in Voice, Voice in Work | Voice can use plugins and connected apps on web, iOS and Android; Voice in Work can create files and continue unfinished tasks in text after a call; Free and Go can use Voice in Chat with plugins their plan supports | 2026-09-23 | broad | [9to5Mac](https://9to5mac.com/2026/09/23/openai-just-upgraded-chatgpt-voice-in-three-ways/), [Releasebot](https://releasebot.io/updates/openai/chatgpt) |
| Voice with files and Projects | Ask about an uploaded document aloud or continue a project by voice | week of 2026-08-03 | not stated | [What's new](https://learn.chatgpt.com/docs/whats-new) |
| Background Conversations | Setting under Settings, Voice keeps a voice chat going outside the app; Codex voice follows it (1.2026.209) | 2024; 2026-08-07 | not stated | [changelog](https://learn.chatgpt.com/docs/changelog), [MacRumors how-to](https://www.macrumors.com/how-to/use-chatgpt-mobile-app-background-chat/) |
| Live voice on Lock Screen and Dynamic Island | Content from a Live voice conversation shows as a Live Activity on the Lock Screen and, on iPhones that have one, in the Dynamic Island; Background conversations (Settings, Voice) keeps the call going outside the app. One secondary source adds that ending the session happens in the app | 2026-08-31 | not stated | [ChatGPT release notes, 2026-08-31 (archived)](https://web.archive.org/web/20261010013210/https://help.openai.com/en/articles/6825453-chatgpt-release-notes), [Pondero](https://pondero.ai/news/2026-09-02-chatgpt-lock-screen/) (secondary) |
| Voice in Codex | Start, check and steer tasks by voice; usage warnings; voice reliability fixes on connection drops | 2026-07 to 09 | Plus, Pro, Business, Edu, Enterprise (desktop and Remote) | [Voice docs](https://learn.chatgpt.com/docs/features/voice), [changelog](https://learn.chatgpt.com/docs/changelog) |
| Usage | More than 150 million people use Voice and Dictation (OpenAI figure, as reported) | 2026-07 | n/a | [TechCrunch](https://techcrunch.com/2026/07/08/openai-releases-new-voice-models-for-more-natural-live-conversations/) |

System entry points for voice: Action Button shortcut "Start voice conversation" (iPhone 15 Pro and later, iOS 18) and a Lock Screen widget with a headphones icon ([blog guide, Jan 2025](https://blog.kowatek.com/2025/01/03/how-to-link-chatgpt-advanced-voice-mode-to-iphone-action-button/), [CO/AI, Sept 2024](https://getcoai.com/news/how-to-use-the-chatgpt-voice-widget-on-iphone-lock-screens/)). These are older secondary sources, and current behavior is **[unconfirmed: in a browser on 2026-10-15, OpenAI's Siri and Shortcuts article (https://help.openai.com/en/articles/7993358-chatgpt-ios-app-siri-and-shortcuts) returns "That page doesn't exist", a help-center search for "lock screen widget shortcuts" finds no matching article, and the current ChatGPT Voice article (https://help.openai.com/en/articles/20001274-chatgpt-voice, updated 2026-10-15) covers CarPlay, a "Start with Voice" setting and background conversations but not the Action Button or a Lock Screen widget]**.

## B.6 Camera, photos, files, scanning, audio

- Attach from camera, photo library or files via the + menu; recent-photos long-press (see B.2).
- **Multi-page scanning.** The camera's three-dot menu has Scan, which combines several captured pages into one PDF. Rolling out on iOS, 2026-10-01 ([ChatGPT release notes (archived)](https://web.archive.org/web/20261010013210/https://help.openai.com/en/articles/6825453-chatgpt-release-notes), [Releasebot](https://releasebot.io/updates/openai/chatgpt)).
- **Audio uploads.** Upload recordings for transcripts, summaries and structured notes; paid plans and workspaces; 2026-10-06 ([ChatGPT release notes (archived)](https://web.archive.org/web/20261010013210/https://help.openai.com/en/articles/6825453-chatgpt-release-notes), [Releasebot](https://releasebot.io/updates/openai/chatgpt)). Platform coverage not stated.
- **Multi-photo note capture for study materials** is available on iOS, Android in progress (2026-10-07) ([Releasebot](https://releasebot.io/updates/openai)).
- **Library and files.** Reuse Library files without re-uploading (web); search also matches folders and conversation titles on web, iOS and Android (week of 2026-08-03). Box, Dropbox and SharePoint join Google Drive in Library on web, mobile "to follow" (2026-09-10). Pages and Space replace Library for accounts with access (2026-09-29) ([What's new](https://learn.chatgpt.com/docs/whats-new), [Releasebot](https://releasebot.io/updates/openai/chatgpt)).
- **Attachments in Codex** include photos, camera, files, with previews before sending (1.2026.181) ([LinkLoot](https://linkloot.io/blog/chatgpt-ios-12026181-codex-mobile-task-management), secondary).
- Accessibility concern: a VoiceOver user reported the camera toggle is not reliably accessible (July 2026) ([AppleVis](https://mail.applevis.com/comment/211605), user report).

## B.7 Image generation and editing

- **ChatGPT Images 2.5** (2026-09-08): sharper details, up to 50 percent lower latency than Images 2, more reliable multi-turn editing, a Sketch tool to draw reference images in ChatGPT, templates, and shareable prompts. Rolling out to ChatGPT, Work and Codex across all tiers on desktop, mobile and web. The article describes no select-region editor ([9to5Mac](https://9to5mac.com/2026/09/08/openai-releases-chatgpt-images-2-5-with-sharper-details-and-more-precise-editing/)). OpenAI's Codex docs say image edits can target a selected area, built-in generation uses `gpt-image-2`, and the desktop app has an expanded viewer with Focused and Canvas views ([Image generation](https://learn.chatgpt.com/docs/image-generation)). Mobile is not covered on that page.
- **Stickers** (2026-08-24): Images, Stickers; upload photos, describe style, transparent backgrounds, "Add to chat apps" exports to iMessage, WhatsApp (needs at least three) or Photos. Plans not stated ([9to5Mac](https://9to5mac.com/2026/08/24/chatgpt-now-lets-users-create-custom-imessage-and-whatsapp-stickers/)).
- **Usage cost.** In Work and Codex, image turns use included limits about 3 to 5 times faster, and the page says image generation is not available on Free in that context ([Pricing](https://learn.chatgpt.com/docs/pricing)). That limit covers Work and Codex only. In Chat, Images 2.0 "is available on all ChatGPT plans" (2026-04-21) and Images 2.5 left existing image limits unchanged (2026-09-08), so Free users can generate images in Chat ([ChatGPT release notes (archived)](https://web.archive.org/web/20261010013210/https://help.openai.com/en/articles/6825453-chatgpt-release-notes)) (corrected 2026-10-15).
- Save or copy rendered images in Codex tasks (1.2026.139).

## B.8 Search and deep research

- **Web search** works in Chat, Work and Codex; search activity appears in the transcript; workspace settings can disable it ([Web search](https://learn.chatgpt.com/docs/web-search)). Cited answers show a Sources button ([Search Engine Journal](https://www.searchenginejournal.com/chatgpt-gpt-6-intelligent-ui/592249/)).
- **Deep research** works in Chat and, where available, in Work and Codex. Start it by typing @Deepresearch, or in Chat by picking Deep research from the + menu; Chat first shows a research plan you can edit, and in Work it draws on your Work and Codex allowance ([Deep research help article, archived 2026-09-14](https://web.archive.org/web/20260914073610/https://help.openai.com/en/articles/10500283-deep-research)). In Work it is also a Deep research plugin in the desktop app and a + menu option on web, producing a sourced report you can follow up on ([Web search](https://learn.chatgpt.com/docs/web-search)) (corrected 2026-10-15: the first draft said it is now part of Work only). Neither page lists platform limits. OpenAI's February 2025 launch post said mobile and desktop apps would get it "within the month" ([launch post, archived](https://web.archive.org/web/20261011125149/https://openai.com/index/introducing-deep-research/)) **[unconfirmed: no dated iOS rollout appears in that post's later updates or in the archived ChatGPT release notes]**.
- **Shopping and finance verticals**: virtual try-on (2026-10-01), Finances (Free and Go in the U.S. from 2026-10-02) ([Releasebot](https://releasebot.io/updates/openai/chatgpt)). Not relevant to a coding client.

## B.9 Work, agent mode (removed), cloud browser, scheduled tasks, Pulse

- **ChatGPT Work** launched on 2026-07-09 per OpenAI's release notes: multi-step tasks over files, plugins and approved tools producing reviewable documents, decks and spreadsheets; you can follow progress, answer questions, redirect and approve important actions; it can run for hours while you follow along ([What's new](https://learn.chatgpt.com/docs/whats-new), [Get started with Work](https://learn.chatgpt.com/docs/get-started-with-work)). Plan availability: OpenAI's 2026-07-09 release note says Work on web and mobile rolled out to every plan except Free and Go: Pro, Pro Lite, Enterprise and Edu first, Plus and Business within days, with a two-week, off-by-default preview for Enterprise and Edu workspaces ([ChatGPT release notes (archived)](https://web.archive.org/web/20261010013210/https://help.openai.com/en/articles/6825453-chatgpt-release-notes)). That matches the chatgpt.com download-page snippet (Plus, Pro, Business, Enterprise). One vendor blog says Free and Go get Work on desktop only (secondary).
- **Mobile Work.** Cloud Work conversations sync across web, mobile and desktop; local Work stays on the computer (2026-07-13). From 2026-09-29, "Local computer access with Work Cloud" lets you start on desktop and continue on web or mobile ([What's new](https://learn.chatgpt.com/docs/whats-new), [Cloud-local access](https://learn.chatgpt.com/docs/enterprise/cloud-local-access)).
- **Agent mode removed.** OpenAI's help article now opens with "ChatGPT agent is no longer available" and points to Work and the cloud browser. The notice first appears in the Wayback copy of 2026-07-20 (article updated about two days earlier), while the 2026-07-11 copy still described agent mode, so the removal came in mid-July 2026, not early August ([archived 2026-07-20](https://web.archive.org/web/20260720213323/https://help.openai.com/en/articles/11752874-chatgpt-agent), [archived 2026-07-11](https://web.archive.org/web/20260711195731/https://help.openai.com/en/articles/11752874-chatgpt-agent)). Vendor blogs report the same notice ([Carly](https://www.usecarly.com/blog/chatgpt-agent-mode/), [izzedo](https://www.izzedo.chat/blog/ai-agent-mode)) (corrected 2026-10-15).
- **Cloud browser sign-in** (2026-08-25): Work has its own browser on a cloud computer. It pauses on login screens and shows a secure sign-in form; the model never sees credentials; a review model checks for phishing; supported iOS password managers can fill credentials; you can take over the cloud computer on mobile or desktop; site access modes are Always ask (default), Auto approve, Always allow, plus per-site rules; sessions persist. Plus and Pro on web and mobile; not Enterprise or Edu ([Browser docs](https://learn.chatgpt.com/docs/browser), [What's new](https://learn.chatgpt.com/docs/whats-new)). MacStories found it worked better on iPhone than on Mac, but CAPTCHA takeover took several attempts ([MacStories](https://www.macstories.net/?p=198275)).
- **Scheduled tasks** (redesign 2026-06-17): a Scheduled page to pause, resume, edit and delete; times or windows such as morning; monitoring tasks check the web and connected apps and notify only on findings; at most once per hour; unattended tasks may pause after inactivity. Go, Plus, Pro, Business, Enterprise on web and mobile ([9to5Mac](https://9to5mac.com/2026/06/17/openai-launches-scheduled-tasks-in-chatgpt-details-here/)). Event triggers from Gmail, Slack and GitHub arrived 2026-08-25 on web and mobile for eligible plans; one task can use several triggers but cannot combine events with a time schedule; the Scheduled view acts as an inbox with an unread indicator ([Automations](https://learn.chatgpt.com/docs/automations)). Free users can have up to three active scheduled tasks that run once or at most daily, and Free and Go cannot create webhook-triggered tasks (2026-08-25) ([ChatGPT release notes (archived)](https://web.archive.org/web/20261010013210/https://help.openai.com/en/articles/6825453-chatgpt-release-notes)).
- **Pulse** was retired: OpenAI said on 2026-06-17 that Pulse would be sunset within 14 days, with scheduled tasks as the replacement ([9to5Mac](https://9to5mac.com/2026/06/17/openai-launches-scheduled-tasks-in-chatgpt-details-here/)). Pulse had launched on 2025-09-25 as an early preview for Pro users on iOS and Android ([ChatGPT release notes (archived)](https://web.archive.org/web/20261010013210/https://help.openai.com/en/articles/6825453-chatgpt-release-notes)) (added 2026-10-15).

## B.10 Canvas, Pages and Space

- **ChatGPT Space** (2026-09-29): a workspace of Pages (documents you and ChatGPT edit together), files, spreadsheets, presentations and Sites. Block-based editor with a selection toolbar, a `/` menu, `@` mentions of people, agents, files and chats, real-time co-editing, comments, and attribution. Space replaces Library for accounts with access ([Space](https://learn.chatgpt.com/docs/space), [Pages](https://learn.chatgpt.com/docs/space/pages), [Releasebot](https://releasebot.io/updates/openai/chatgpt)). OpenAI's 2026-09-29 release note limits Space to eligible Pro, Business and Enterprise users in the desktop app and on the web, so it is not on mobile at launch ([ChatGPT release notes (archived)](https://web.archive.org/web/20261010013210/https://help.openai.com/en/articles/6825453-chatgpt-release-notes)) (corrected 2026-10-15: the first draft said plans and mobile behavior were undocumented). MacStories found Spaces "buggy" at launch ([MacStories](https://www.macstories.net/stories/openais-dots-a-first-look/)).
- **Canvas** is being retired. Since 2026-05-28 it is no longer available in GPT-5.5 Instant or Thinking, writing blocks and code blocks in chat replace it, and paid users keep canvas only through legacy models until those are sunset ([ChatGPT release notes, 2026-05-28 (archived)](https://web.archive.org/web/20261010013210/https://help.openai.com/en/articles/6825453-chatgpt-release-notes)) (corrected 2026-10-15).
- **Files from Work.** Documents, decks, spreadsheets and PDFs preview beside the chat on desktop and download on web; mobile is not covered ([Work with files](https://learn.chatgpt.com/docs/artifacts-viewer)).

## B.11 Projects, Library, memory and personalization

- **Projects** group chats, files, sources and instructions; the desktop app merges web projects and local folder projects; mobile project features are not described ([Projects](https://learn.chatgpt.com/docs/projects)). Voice supports Projects.
- **Memory.** Chat memory carries context across chats; Codex memories are local, off by default, and per machine. Memories rolled out to the EEA, UK and Switzerland in June 2026, off by default there ([Memories](https://learn.chatgpt.com/docs/customization/memories), [What's new](https://learn.chatgpt.com/docs/whats-new)). A Privacy Center gathers privacy, memory, personalization and security settings, rolling out 2026-09-21 (Settings, Privacy Center on iOS) ([Releasebot](https://releasebot.io/updates/openai/chatgpt)). Security history (sign-ins, MFA and passkey changes) shows in account settings (2026-09-25) ([Releasebot](https://releasebot.io/updates/openai)).
- **Personalization.** Base style and tone; custom instructions; writing style learned from connected apps (Work, web). In Codex the equivalent is `AGENTS.md`; per-host personality on iOS is Friendly or Pragmatic ([Personalize](https://learn.chatgpt.com/docs/personalize), [changelog](https://learn.chatgpt.com/docs/changelog)).
- **Multiple accounts for plugins** (2026-09-17) across web, mobile and desktop ([Releasebot](https://releasebot.io/updates/openai/chatgpt)).

## B.12 Custom GPTs, apps and plugins

- **Apps in ChatGPT / Apps SDK.** OpenAI opened submissions and an App Directory on 2025-12-17, built on MCP; apps appear as inline cards or carousels, fullscreen views or picture-in-picture, invoked with `@` or the tools menu ([VentureBeat](https://venturebeat.com/technology/openai-now-accepting-chatgpt-app-submissions-from-third-party-devs-launches)). On 2026-07-09 OpenAI replaced the App Directory with the Plugin Directory; existing app connections were unaffected, and plugins can package skills, apps and app templates ([ChatGPT release notes (archived)](https://web.archive.org/web/20261010013210/https://help.openai.com/en/articles/6825453-chatgpt-release-notes)). ChatGPT and Codex share one plugin directory ([Plugins](https://learn.chatgpt.com/docs/plugins)).
- **Plugins** bundle skills, MCP servers (with optional custom UI), browser extensions and hooks. On mobile you can use plugins already available to your account in Chat or Work, but browsing and installing is described only for web and desktop ([Plugins](https://learn.chatgpt.com/docs/plugins)).
- **Custom GPTs retire.** Announced 2026-09-11. Enterprise workspaces stop creating GPTs on 2026-10-26, GPTs stop running 2026-12-11, and approved Enterprise deferrals extend to 2027-02-11. Migration turns instructions into a skill and copies knowledge files; custom actions, conversations, selected model and sharing settings do not migrate ([Virtualization Review](https://virtualizationreview.com/articles/2026/09/28/openai-to-retire-custom-gpts-replace-them-with-plugins.aspx), [Migrate GPTs](https://learn.chatgpt.com/docs/migrate-custom-gpts)). Mobile is not mentioned.
- **Sign in with ChatGPT** and MCP Events are developer features announced at DevDay ([DevDay 2026](https://learn.chatgpt.com/docs/whats-new/devday-2026)).

## B.13 Dots

- **What.** Always-on agents on GPT-6 Astra with their own cloud computer and browser, memory, background agents, and the ability to delegate to Work or Codex. They work between conversations and return results or ask for decisions ([Dots](https://learn.chatgpt.com/docs/dots)).
- **Mobile UX.** Create and name a dot, customize its appearance, connect plugins, choose whether ChatGPT opens to the dot's conversation (2026-10-09); message it or tap the phone button in its conversation to call, and type while talking; ending a call does not stop assigned work; connecting your computer is desktop-only; mobile web unsupported ([Getting started](https://learn.chatgpt.com/docs/dots/getting-started), [Channels](https://learn.chatgpt.com/docs/dots/channels), [October 5 to 9 digest](https://learn.chatgpt.com/docs/whats-new/october-5-9-2026)). The dot can start and follow up on Codex tasks, search ChatGPT conversations and edit Work automations.
- **Controls.** Four rule handlings (act without asking, act when told, ask first, hand off), automatic action review, Pause, Resume, Delete; activity review is described for desktop ([Controls](https://learn.chatgpt.com/docs/dots/controls)). The docs say the automatic review can require you to complete a step yourself, such as changing a password; The Next Web likewise says sensitive tasks such as changing a password always stay with the user ([The Next Web](https://thenextweb.com/news/openai-dots-always-on-ai-agents-cloud-computers-devday)).
- **Plans.** Pro 100, 200 and 500 (adults outside EEA, UK, Switzerland), Business Premium worldwide, Enterprise off by default; dot conversations do not count against usage but Work and Codex tasks do ([Dots](https://learn.chatgpt.com/docs/dots)).
- **Hands-on.** MacStories says reaching the dot from iPhone is easier than Codex Remote; limits are one dot, no search inside its thread, one connected Mac ([MacStories](https://www.macstories.net/stories/openais-dots-a-first-look/)).

## B.14 Group chats and sharing

- **Group chats** launched globally 2025-11-20 for Free, Go, Plus and Pro, up to 20 participants, invite links, reactions, content not stored in memory ([Engadget](https://www.engadget.com/ai/chatgpt-group-chats-roll-out-to-everyone-202038918.html)). OpenAI's release notes say that from 2026-07-09 users on web, iOS and Android can no longer create new group chats, turn conversations into group chats or join one by invite link, while existing ones keep working for now ([ChatGPT release notes, 2026-07-09 (archived)](https://web.archive.org/web/20261010013210/https://help.openai.com/en/articles/6825453-chatgpt-release-notes)).
- **Sharing.** Chats have a Share action ([Visualizations](https://learn.chatgpt.com/docs/visualizations)); shared links can be viewed or revoked under data controls, Shared links. Codex thread snapshots can be shared read-only from the macOS desktop app, with workspace links limited to members or invited people ([Use ChatGPT](https://learn.chatgpt.com/docs/use-chatgpt)). A shared visualization is a snapshot, not a live dashboard. Profile sharing and showcasing Sites arrived 2026-09-29 ([Releasebot](https://releasebot.io/updates/openai/chatgpt)).
- **Space pages** share with view, comment or edit access ([Space](https://learn.chatgpt.com/docs/space)).

## B.15 Chat search, history and organization

- Search across folders and conversation titles on web, iOS and Android (week of 2026-08-03) ([What's new](https://learn.chatgpt.com/docs/whats-new)). Pinned chats sync between desktop and iOS (2026-08-20). Archived chats can be restored from Settings; Codex archived threads are browsable on iOS (1.2026.139) ([Projects](https://learn.chatgpt.com/docs/projects), [changelog](https://learn.chatgpt.com/docs/changelog)).
- Codex task search covers titles and conversation content across connected hosts (1.2026.230), and the list has filters, Pinned and Today sections ([Codex on mobile](https://learn.chatgpt.com/docs/mobile)).

## B.16 Apple platform integration

| Integration | Detail | Date | Source |
|---|---|---|---|
| Home Screen widget: ChatGPT shortcuts | Small and medium only. Long-press, Edit Widget, choose buttons and whether labels show. Buttons per group: Chat (new chat, camera, photos, dictation, voice), Work (same, prefixed), Remote (new remote chat, camera, photos, dictation, voice). The older widget cannot be customized | 2026-08-26/27 | [MacStories](https://www.macstories.net/ios/openai-updates-chatgpt-for-ios-with-customizable-widgets-for-chatgpt-work-and-codex-remote/) |
| Home Screen widget: recent Codex tasks | Shows recent tasks from selected computers | 2026-10-02 | [changelog](https://learn.chatgpt.com/docs/changelog) |
| Home and Lock Screen widgets: usage | Remaining usage and reset times | 2026-10-02 | [changelog](https://learn.chatgpt.com/docs/changelog) |
| Lock Screen widgets (voice) | Two widgets, one with a headphones icon that starts ChatGPT Voice | 2024-09 | [CO/AI](https://getcoai.com/news/how-to-use-the-chatgpt-voice-widget-on-iphone-lock-screens/) (older, secondary) |
| Control Center and Lock Screen control | A dedicated control opens Remote voice (Codex on the Mac); it shares an icon with regular ChatGPT Voice | 2026-08 | [MacStories](https://www.macstories.net/ios/openai-updates-chatgpt-for-ios-with-customizable-widgets-for-chatgpt-work-and-codex-remote/) |
| Action Button | Shortcut "Start voice conversation" (iPhone 15 Pro and later, iOS 18) | 2025-01 guide | [blog guide](https://blog.kowatek.com/2025/01/03/how-to-link-chatgpt-advanced-voice-mode-to-iphone-action-button/) (secondary) |
| Live Activities | Codex cloud task monitoring (2025), worktree setup progress on iOS 26 (2026-09-08), Live voice on the Lock Screen and in the Dynamic Island (2026-08-31) | see rows | [AlternativeTo](https://alternativeto.net/news/2025/5/openai-integrates-codex-into-chatgpt-ios-app), [changelog](https://learn.chatgpt.com/docs/changelog), [ChatGPT release notes (archived)](https://web.archive.org/web/20261010013210/https://help.openai.com/en/articles/6825453-chatgpt-release-notes) |
| Spotlight and Shortcuts | Entry points for opening Codex Mobile | 2026-05-25 | [changelog](https://learn.chatgpt.com/docs/changelog) |
| Shortcuts and Siri (original) | Saved shortcuts around a custom ChatGPT prompt, run by Siri; drag and drop of responses | 2023-06-08 | [GSMArena](https://m.gsmarena.com/chatgpts_app_for_ios_gains_siri_and_shortcuts_integration-amp-58813.php) |
| Home Screen shortcuts | Configurable shortcuts for ChatGPT, Work, Codex Remote; setting to open ChatGPT directly in Codex Remote on launch | 2026-08 | [changelog](https://learn.chatgpt.com/docs/changelog) |
| Notifications | Open tasks from notifications; push | 2026-05-18 | [changelog](https://learn.chatgpt.com/docs/changelog) |
| Face ID or passcode lock for Codex | Optional; the release note scopes it to Codex, not the whole app (corrected 2026-10-15) | 2026-06-02 | [changelog](https://learn.chatgpt.com/docs/changelog) |
| Password manager autofill | In cloud-browser sign-in on iOS, and email verification codes autofill in dot setup | 2026-08, 2026-10 | [Browser docs](https://learn.chatgpt.com/docs/browser), [October 5 to 9 digest](https://learn.chatgpt.com/docs/whats-new/october-5-9-2026) |
| Apple Intelligence | ChatGPT is an optional extension: Settings, Apple Intelligence and Siri, Extensions, ChatGPT (iOS 26). In iOS 27 it is Settings, Siri, ChatGPT, Use Extension. Used by Siri for complex requests, Writing Tools Compose, Image Playground styles, Visual Intelligence; works without an account but account use gives more; data sent includes the request, attachments and approximate location | Launched 2024-12-11 per a secondary source (iOS 18.2 per search results) | [apfelpatient](https://www.apfelpatient.com/tips-tricks/chatgpt-with-apple-intelligence-easy-setup-on-the-iphone), [iDownloadBlog](https://www.idownloadblog.com/2026/08/20/use-chatgpt-in-siri-app/), [Progressive Robot](https://www.progressiverobot.com/2026/09/25/chatgpt-in-siri-apple-intelligence-minimal-usage/) |
| Siri in iOS 27 | A new Siri app built on Gemini; ChatGPT is reached through Ask, then ChatGPT, and does not persist; chats there do not appear in your ChatGPT history. Reports that Apple would add Claude and Gemini "Extensions" were not confirmed at WWDC | 2026-06 to 09 | [iDownloadBlog](https://www.idownloadblog.com/2026/08/20/use-chatgpt-in-siri-app/), [The Next Web](https://thenextweb.com/news/apple-siri-extensions-third-party-ai-missing-wwdc) |
| App Intents | OpenAI publishes a Codex use case on adding App Intents to iOS apps (Shortcuts, Siri, Spotlight, widgets, controls, Live Activities). It does not say what the ChatGPT app itself exposes | 2026 | [Use case](https://learn.chatgpt.com/use-cases/ios-app-intents) |

Siri usage context: in a 2026-09-22 court brief OpenAI described ChatGPT in Siri as badly underperforming and said usage was minimal, citing the opt-in friction (secondary source summarizing a filing, [Progressive Robot](https://www.progressiverobot.com/2026/09/25/chatgpt-in-siri-apple-intelligence-minimal-usage/)).

## B.17 iPad, Vision Pro and Apple Watch

- **iPad.** The app was optimized for iPad and ran full-screen in 2023 ([GSMArena](https://m.gsmarena.com/chatgpts_app_for_ios_gains_siri_and_shortcuts_integration-amp-58813.php)). In 2026: redesigned home screen and a landscape split view that keeps the task list beside the open task (1.2026.258); aligned project, environment and Git controls on iPad (1.2026.251). MacStories notes there is no XL iPad widget ([changelog](https://learn.chatgpt.com/docs/changelog), [MacStories](https://www.macstories.net/ios/openai-updates-chatgpt-for-ios-with-customizable-widgets-for-chatgpt-work-and-codex-remote/)). Remodex had no iPad app in April 2026 ([MacStories](https://www.macstories.net/reviews/remodex-codex-remote-mobile-app-ios/)).
- **Vision Pro.** Listed as supported (visionOS 2.0 or later) via the iPad app ([App Store](https://apps.apple.com/us/app/chatgpt/id6448311069)).
- **Apple Watch.** No official ChatGPT watch app. A feature request (2026-08-24) got an OpenAI Support reply on 2026-09-07 with no timeline ([OpenAI forum](https://community.openai.com/t/feature-request-native-chatgpt-companion-for-apple-watch-watchos/1392290)). A vendor page confirms only third-party apps and API-based Shortcuts exist ([AskWatch, vendor](https://askwatch.app/en/chatgpt-on-apple-watch)). The App Store listing does not list Apple Watch ([App Store](https://apps.apple.com/us/app/chatgpt/id6448311069)).

## B.18 Accessibility

- No OpenAI accessibility statement found. History is regressions after updates: VoiceOver announcing only "close menu" (Dec 2023, v1.2023.334) ([OpenAI forum](https://community.openai.com/t/chatgpt-ios-app-no-longer-accessible-for-blind-users-with-latest-update/554146)); Send button and voice mode not activatable by VoiceOver (v1.2024.233) ([OpenAI forum](https://community.openai.com/t/ios-chatgpt-accessibility-issue-cant-activate-send-button-to-send-a-message/924355)); July 2026 AppleVis thread on regressions with VoiceOver and NVDA, including an inaccessible camera toggle on iOS ([AppleVis](https://mail.applevis.com/comment/211605)). All are user reports.
- Dynamic Type support: the only hint is the 1.2026.188 note that Codex composer controls stay visible above the keyboard "for long prompts and larger text sizes" ([changelog](https://learn.chatgpt.com/docs/changelog)) **[unconfirmed: no OpenAI help article, release note or accessibility statement on Dynamic Type found; checked the archived ChatGPT release notes and the Wayback index of help.openai.com articles]**.
- OpenAI's visualization docs say accessibility is not guaranteed and suggest asking for text summaries and data tables ([Visualizations](https://learn.chatgpt.com/docs/visualizations)).

## B.19 Notifications (general)

- Scheduled tasks and monitoring tasks notify on findings; the Scheduled page is the inbox with an unread indicator ([Automations](https://learn.chatgpt.com/docs/automations)).
- Web settings list push, email and SMS channels by category ([Notifications](https://learn.chatgpt.com/docs/notifications)).
- Dots can message you proactively and you choose where updates go (for example routine progress in ChatGPT and decisions in Slack) ([Channels](https://learn.chatgpt.com/docs/dots/channels)). Text, SMS and iMessage for dots are "coming soon".
- Fewer duplicate phone notifications while ChatGPT is open (2026-10-09).

## B.20 Offline and connectivity behavior

- No documented offline mode. Everything depends on the network. The app shows clearer UI while waiting for a connection (2026-08-21) ([9to5Mac](https://9to5mac.com/2026/08/21/chatgpts-iphone-app-gets-a-handy-shortcut-to-attach-recent-photos-more-quickly/)).
- Codex is built to tolerate phone disconnects: work continues on the host or cloud, queued prompts sync to the host and send while the app is in the background, tasks stay usable during reconnect checks, pairing survives temporary outages, approvals recover after reconnect, and new tasks keep the selected computer while it reconnects ([changelog](https://learn.chatgpt.com/docs/changelog)).
- Voice calls got reliability fixes for brief connection drops (1.2026.251).

## B.21 Notable UX details: haptics, animations, scroll

- **Haptics.** iOS has a Haptic Feedback toggle under the three-dot menu, Settings; in 2023 coverage the phone vibrated throughout response generation ([Wccftech, 2023-05-29](https://wccftech.com/how-to/disable-annoying-haptic-feedback-vibrations-in-chatgpt-for-iphone-tutorial/amp/)). OpenAI's iOS help article, last updated in mid-2026, says the app still uses haptic feedback and switches it off automatically in Low Power Mode or below 20 percent battery; it does not say where the toggle now sits ([help article, archived 2026-08-25](https://web.archive.org/web/20260825095239/https://help.openai.com/en/articles/7925783-why-did-haptic-feedback-stop-working)) (corrected 2026-10-15). OpenAI documents an Android toggle under Personalization ([help article, archived 2026-08-13](https://web.archive.org/web/20260813202829/https://help.openai.com/en/articles/8144762-haptic-feedback-in-the-chatgpt-android-app)).
- **Animations.** Smoother animations when adding photos from camera or library (1.2026.258); smoother home screen, send and keyboard transitions (1.2026.267); keyboard transitions when starting tasks and swiping back (1.2026.272) ([changelog](https://learn.chatgpt.com/docs/changelog)).
- **Scroll during streaming.** The app auto-scrolls to the newest text during generation with no documented setting to turn it off; users have asked for a stationary option since 2024 and some report a stuck or jumping scroll. Tapping the screen stops the scroll per one commenter ([OpenAI forum](https://community.openai.com/t/screen-auto-scrolls-as-the-response-being-generated/782378), [OpenAI forum](https://community.openai.com/t/chatgpt-wont-let-me-scroll-down-while-its-writing/1130778.md)). Platform specifics in those threads vary (web, mobile, desktop).
- **Transcript stability.** Fixes for selecting text while older messages load (1.2026.267), a thinking timer that no longer resets when a new task starts (1.2026.251), and a live working-time display for long tasks (1.2026.237).
- **Status vocabulary.** iOS "Needs input" status; desktop pets show Running, Needs input, Ready, Blocked ([changelog](https://learn.chatgpt.com/docs/changelog), [Notifications](https://learn.chatgpt.com/docs/notifications)).

## B.22 Plans and pricing snapshot

| Plan | Price | Notes for mobile and Codex | Source |
|---|---|---|---|
| Free | $0 | Unlimited text chats on GPT-5.6 Luna with a Think button (2026-08-06), GPT-6 Luna from 2026-10-08; Codex desktop app with Luna. The App Store lists "Advertising" as frequent content, and The Next Web reports ads expanding to 31 European countries | [Pricing](https://learn.chatgpt.com/docs/pricing), [9to5Mac](https://9to5mac.com/2026/08/06/openai-updating-chatgpt-with-a-smarter-gpt-5-6-sol-and-unlimited-free-chats/), [App Store](https://apps.apple.com/us/app/chatgpt/id6448311069), [The Next Web](https://thenextweb.com/news/chatgpt-iphone-recent-photos-shortcut-siri-eu-delay) |
| Go | $8 per month | Same Codex scope as Free; included in the 2026-06-17 scheduled-tasks rollout on web and mobile | [Pricing](https://learn.chatgpt.com/docs/pricing), [9to5Mac](https://9to5mac.com/2026/06/17/openai-launches-scheduled-tasks-in-chatgpt-details-here/) |
| Plus | $20 per month | Codex on web, CLI, IDE, iOS; cloud integrations; GPT-6.1 Sol and Luna; five-hour limit restored 2026-08-25; VM 2 vCPU | [Pricing](https://learn.chatgpt.com/docs/pricing) |
| Pro | $100, $200, $500 per month | No five-hour limit currently; Ultrafast on $500; dots | [Pricing](https://learn.chatgpt.com/docs/pricing) |
| Business | $20 per user per month annual ($25 monthly) | ChatGPT and Codex on desktop and mobile; larger VMs | [Pricing](https://learn.chatgpt.com/docs/pricing) |
| Enterprise, Edu | Contact sales | Admin gates for Remote, GPT models, dots, Ultrafast | [Pricing](https://learn.chatgpt.com/docs/pricing) |
| API key | Pay per use | Codex CLI, SDK, IDE only; no cloud features; no mobile remote | [Pricing](https://learn.chatgpt.com/docs/pricing) |

## B.23 Other consumer features seen in release notes (low relevance to a coding client)

Health tab explanations (2026-09-28), Finances and credit score (2026-09-21 and 10-02), virtual try-on and Favorites (2026-10-01), ChatGPT for Word (2026-09-17), teen protections (2026-08-18 per 9to5Mac headline), Messages integration on Mac, multiple Gmail and Calendar accounts (2026-08-28) ([Releasebot](https://releasebot.io/updates/openai/chatgpt), [9to5Mac tag page](https://9to5mac.com/tag/chatgpt/)).

---

# Part C. Patterns worth copying in a native iOS client for a coding agent

Each pattern cites the evidence from this report. "Priority" is my judgment for an opencode client, not a sourced claim.

1. **Treat the phone as a thin client over a durable host, and design reconnect as a first-class state.** Keep tasks usable while reconnecting, preserve the selected host, keep cached titles on refresh, recover approvals after reconnect, preserve pairing through short outages (1.2026.209, .244, .267, .272). Show an explicit "stale or resyncing" state rather than a silent spinner (see D1, D6). Priority: high.
2. **Pair once per device and host, with a QR code plus a pasteable manual code**, store the host identity in the Keychain, and give the user an in-app way to list and delete stale hosts (1.2026.160, .272; fails in #22700). Priority: high.
3. **One task list across hosts and cloud** with filter chips (All, Cloud, each host), Pinned and Today sections, sort by recent activity, unavailable hosts shown greyed, a priority view for running, unread and needs-input tasks, search over titles and content, and an archive browser ([mobile](https://learn.chatgpt.com/docs/mobile), 1.2026.195, .230, .237). Desktop rows also carry pull-request status badges (draft, open, merged, closed), a cheap and useful cue for a coding list ([changelog, 2026-02-27](https://learn.chatgpt.com/docs/changelog)). Priority: high.
4. **A tiny, consistent status vocabulary** (Running, Needs input, Ready, Blocked) reused in rows, notifications, widgets and Live Activities ([Notifications](https://learn.chatgpt.com/docs/notifications), 1.2026.181). Priority: high.
5. **An approval card that always shows what is being approved**, with Approve, Always approve, Tell the agent what to do, and Deny; scoped "always" choices (this chat or all chats); and never a banner without an actionable card (the failure in #39346). Add an "approve for me" review mode only as an opt-in, with a circuit breaker: OpenAI's auto-review interrupts a turn after 3 consecutive denials or 10 denials in the last 50 reviews ([mobile](https://learn.chatgpt.com/docs/mobile), [Auto-review](https://learn.chatgpt.com/docs/sandboxing/auto-review), 1.2026.160 and .272). Priority: high.
6. **Queue and Steer with a default setting.** Queued prompts show a compact expandable preview, sync to the host, send in the background, and canceling one restores text and attachments to the composer (1.2026.146, .237, .251, .267). Priority: high.
7. **Answer the agent's live questions without losing your draft** and render structured questions as forms (1.2026.195, .244). Priority: medium.
8. **Branch, worktree and setup choices at task creation**, remembered per project, with a starting-branch picker and "include local changes" (1.2026.153, .244, .251). Priority: high for a coding agent.
9. **Small-screen diff review:** file list to diff, line wrap toggle, expand or collapse all, filters (staged, unstaged, branch, last turn), inline comments that become a follow-up message, syntax highlighting, graceful large diffs, nested repo support (1.2026.181, .202, .258, [Verdent](https://www.verdent.ai/guides/codex-in-chatgpt-mobile), [LinkLoot](https://linkloot.io/blog/chatgpt-ios-12026181-codex-mobile-task-management)). Priority: high.
10. **Workspace file browser** with recent files, back navigation, remembered reading positions, folder creation and a directory picker for new tasks (1.2026.160, .244, .251). Priority: medium.
11. **Side chats, forks, goals and task mentions** keep the composer powerful: `/side`, fork, `/goal` with pause and resume, `@` another task, select transcript text to reference (1.2026.146, .153, .181, .244, .258). Priority: medium.
12. **Live Activities for long operations** (setup progress, running task, approval needed) with status and elapsed time; OpenAI shipped this for cloud tasks in 2025 and for worktree setup in 2026 ([AlternativeTo](https://alternativeto.net/news/2025/5/openai-integrates-codex-into-chatgpt-ios-app), 1.2026.244). Priority: high.
13. **Widgets with real utility:** recent tasks per host, remaining usage with reset time (Home and Lock Screen), and a configurable launcher (new task, camera, photos, dictation, voice) (1.2026.267, [MacStories](https://www.macstories.net/ios/openai-updates-chatgpt-for-ios-with-customizable-widgets-for-chatgpt-work-and-codex-remote/)). Beat ChatGPT by exposing each launcher as an App Intent and Shortcuts action, adding large iPhone and XL iPad sizes, and giving voice a distinct icon (all complaints from the same article). Priority: medium.
14. **System entry points:** Control Center and Lock Screen controls, Action Button, Spotlight, Shortcuts, Siri (1.2026.139, MacStories). OpenAI's own App Intents guidance lists Shortcuts, Siri, Spotlight, widgets, controls and Live Activities as the target surfaces ([use case](https://learn.chatgpt.com/use-cases/ios-app-intents)). Priority: medium.
15. **Deep links and notification taps that open the exact task**, including links shared from desktop or Slack (1.2026.132, .272). A stable thread reference with a distinct "needs human" event is a user request worth honoring ([#32908](https://github.com/openai/codex/issues/32908)). Priority: high.
16. **Voice as a first-class input in the task composer**, following the selected model and effort, continuing in the background, with usage warnings (1.2026.202, .209, .223, .244). Priority: medium.
17. **Optional Face ID or passcode lock** for an app that can approve shell commands (1.2026.146). Priority: high.
18. **Show usage and limits where the user decides to start work:** task menu, profile screen, widgets, warnings before big jobs (1.2026.153, .181, .267; request in [#25240](https://github.com/openai/codex/issues/25240)). Priority: medium for opencode (depends on provider billing).
19. **Composer ergonomics:** model and effort controls above the keyboard, keep-keyboard-open option, drafts restored across tasks, edit the last prompt, long-press shortcuts (+ for recent photos, send for effort) (1.2026.153, .188, .195, .267, [9to5Mac](https://9to5mac.com/2026/08/21/chatgpts-iphone-app-gets-a-handy-shortcut-to-attach-recent-photos-more-quickly/)). Priority: high.
20. **Rich inline output:** forms, charts, tables, page previews, image save and copy (1.2026.139, .188, .195, .272). Priority: medium.
21. **Host breadth:** Mac, Windows, SSH hosts with key auth, and a CLI-generated short-lived pairing code for headless servers (1.2026.146, .181; [CLI reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli)). Make headless Linux first-class, which is the most requested missing item ([#23200](https://github.com/openai/codex/issues/23200)). Priority: high.
22. **iPad as a real layout:** task list beside the open task in landscape, aligned project and Git controls (1.2026.251, .258). Priority: medium.
23. **Handoff with Git state** between local, worktree and remote host, with a destination picker and a warning that a running turn will be interrupted ([Remote connections](https://learn.chatgpt.com/docs/remote-connections)). Priority: medium.
24. **Cloud and host choice at task start**, with the environment prepared elsewhere (desktop) and only selected on the phone ([Cloud](https://learn.chatgpt.com/docs/cloud)). Priority: depends on opencode's hosted story.
25. **Security posture to match or exceed:** per-device per-host pairing, relay with no public exposure, approvals still enforced on the host, admin kill switch, VPN or mesh recommendation ([Remote connections](https://learn.chatgpt.com/docs/remote-connections)). For a direct-connect client, TLS, token auth and Tailscale-style reachability avoid a vendor relay entirely (inference).
26. **Fast, stable streaming in long threads**: incremental loading, stable text selection while older messages load, a live working-time display and thinking timer (1.2026.237, .251, .267, .272). Priority: high.
27. **A full start-from-the-phone flow** (new task, pick host or cloud, project, branch, model) is what reviewers single out. Federico Viticci wrote that other companies' remote-control features (he names Claude and Cursor) require starting from a Mac, while Codex Remote offers a complete start-from-iOS flow, near desktop parity and a voice mode (paraphrased from his [post of 2026-08-17](https://x.com/viticci/status/2089420425193202065), read through the fxtwitter API). Priority: high.
28. **Look native.** MacStories praised a third-party Codex client for an iOS 26 Liquid Glass design that does not look like a command-line tool ([MacStories](https://www.macstories.net/reviews/remodex-codex-remote-mobile-app-ios/)). Priority: medium.
29. **Dictation everywhere in the launcher and composer** (widget buttons for dictation and voice in each group) because typing on a phone lowers prompt quality ([MacStories](https://www.macstories.net/ios/openai-updates-chatgpt-for-ios-with-customizable-widgets-for-chatgpt-work-and-codex-remote/), [HN](https://news.ycombinator.com/item?id=48140529)). Priority: medium.

---

# Part D. Known user pain points

Evidence is mostly GitHub issues in openai/codex (303 issues carry the iOS label at the time of reading, [issue list](https://github.com/openai/codex/issues?q=is%3Aissue+label%3AiOS+sort%3Areactions-%2B1-desc)), a large Hacker News thread, and press hands-on. All are user reports unless noted. I saw no substantive maintainer replies on the issues I opened, only label changes, bot comments and one duplicate marking.

Ranked by thumbs-up reactions on 2026-10-15, the top iOS-labeled issues are: headless Linux hosts ([#23200](https://github.com/openai/codex/issues/23200), 66), a revoked device that cannot be removed or re-paired ([#22700](https://github.com/openai/codex/issues/22700), 36), pairing stuck on "Waiting for desktop" ([#22715](https://github.com/openai/codex/issues/22715), 29, closed as completed on 2026-08-15), no worktree or branch choice ([#22925](https://github.com/openai/codex/issues/22925), 25), SSH projects missing on the phone ([#23527](https://github.com/openai/codex/issues/23527), 23), Remote push notifications not delivered ([#32908](https://github.com/openai/codex/issues/32908), 18), running tasks that fail to open ([#28340](https://github.com/openai/codex/issues/28340), 14) and the missing approval card ([#39346](https://github.com/openai/codex/issues/39346), 13). An offline-host issue without the iOS label has 40 ([#22898](https://github.com/openai/codex/issues/22898)). The 10-second resume issue has only 2 ([#37997](https://github.com/openai/codex/issues/37997)), and the Mac-sleep issue has 10 ([#23294](https://github.com/openai/codex/issues/23294)). Command: `gh api -X GET search/issues -f q='repo:openai/codex is:issue label:iOS' -f sort=reactions-+1 -f order=desc` (added 2026-10-15).

**D1. Connection reliability and host presence**

- Mac sleep or lock drops the host: a MacBook with "Keep this Mac awake" still slept and vanished from the phone ([#23294](https://github.com/openai/codex/issues/23294)); after lock or display-off the mobile app can no longer use the connection and shows no error ([#23948](https://github.com/openai/codex/issues/23948), closed by its reporter the same day after a bot flagged it as a likely duplicate of #23294) (corrected 2026-10-15). OpenAI's own docs confirm access stops if the host sleeps, loses network or closes the app, and laptops need power and an external display with the lid closed ([Remote connections](https://learn.chatgpt.com/docs/remote-connections)).
- Silent disconnect after about two hours with no diagnostic ([#32242](https://github.com/openai/codex/issues/32242)).
- Resume is slow: switching apps and back forces a full reconnect taking 10+ seconds, 15 to 30 seconds for some users; reports run from 2026-08-11 to 2026-10-04 ([#37997](https://github.com/openai/codex/issues/37997)).
- "Reconnect" does nothing visible ([#22898](https://github.com/openai/codex/issues/22898)); host shows offline while online ([#22773](https://github.com/openai/codex/issues/22773)); pairing stuck on "Waiting for desktop" when the remote-control daemon cannot use a proxy ([#22851](https://github.com/openai/codex/issues/22851), title as seen in search results).
- Users on Hacker News report connection reliability problems, for example iOS showing the desktop but unable to connect ([HN thread, 486 points](https://news.ycombinator.com/item?id=48140529)).

**D2. Pairing and revocation**

- A revoked device stays listed in the iOS app with no way to delete it, and re-pairing fails ([#22700](https://github.com/openai/codex/issues/22700)).
- Per-device, per-host QR pairing is required, and connections not used since 2026-06-08 had to be re-paired ([Remote connections](https://learn.chatgpt.com/docs/remote-connections)). Pairing failed on devices with a wrong clock until 1.2026.258.

**D3. Dependence on the desktop app, and no headless host**

- The host must be awake and signed in, and Linux is not a documented host. The headless Linux request is the most-reacted iOS-labeled issue and has been open since 2026-05-17 ([#23200](https://github.com/openai/codex/issues/23200)). A workable path exists (`codex remote-control start` then `pair`). In August, commenters on that issue said it was documented only in a developer README, is Unix-only, has no systemd unit and does not support API-key auth; the CLI reference I read in October does now list the commands ([CLI reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli)).
- Windows Computer Use needs the desktop unlocked and dedicated ([Remote connections](https://learn.chatgpt.com/docs/remote-connections)).

**D4. Notifications and approvals**

- Completion and approval pushes are not delivered for Remote tasks until the thread has been opened once on the phone; desktop-started turns may not push while phone-started ones do; scheduled-task pushes work, so general push is fine ([#32908](https://github.com/openai/codex/issues/32908), open since 2026-07-14, comment as recent as 2026-10-15). An earlier report of very late or missing notifications was closed as not planned by its reporter ([#22773](https://github.com/openai/codex/issues/22773)).
- The task list can show "approval waiting" while the thread has no approval card or buttons, leaving the desktop task blocked for hours ([#39346](https://github.com/openai/codex/issues/39346)).

**D5. Project and thread visibility**

- iOS Remote lists only projects with recent chats; renamed projects show folder names; ghost entries remain ([#36040](https://github.com/openai/codex/issues/36040), open since 2026-07-29, still active on 2026-10-15; about 85 comments and timeline items per the issue list).
- Chats started in the CLI may not open on iOS, and running tasks sometimes fail to open with a connection-invalidated error ([#28340](https://github.com/openai/codex/issues/28340)).
- SSH remote projects from a connected Mac did not show on mobile; rescanning the QR code and reinstalling did not help. Open since 2026-05-19, with another issue marked as its duplicate on 2026-10-13 ([#23527](https://github.com/openai/codex/issues/23527)).
- Worktree and branch choice from the phone was missing at launch (new tasks could silently run in the primary checkout, issue [#22925](https://github.com/openai/codex/issues/22925)). The picker shipped in 1.2026.153 and .244, but the issue is still open, and an August comment reports the client rejecting a freshly generated worktree path.
- Usage visibility was requested ([#25240](https://github.com/openai/codex/issues/25240)); usage and reset widgets arrived in 1.2026.267, though that issue is still open.

**D6. State sync and hydration**

- 403 "Error loading messages", stale "Implement this plan?" prompts that block steering, dropped events on the desktop side, and lag behind the host ([#22773](https://github.com/openai/codex/issues/22773)). Users propose sequence numbers, replay buffers and an explicit stale or resync indicator.

**D7. Limits and cost**

- Plus users lost and regained the five-hour limit (restored 2026-08-25), and OpenAI said many Plus users accidentally burn their weekly allowance ([9to5Mac](https://9to5mac.com/2026/08/24/openai-restores-5-hour-codex-and-work-limits-for-chatgpt-plus-users/)).
- HN commenters say Free users hit limits quickly ([HN](https://news.ycombinator.com/item?id=48140529)).
- Voice costs usage ($0.05 per minute in desktop Codex) ([Pricing](https://learn.chatgpt.com/docs/pricing)).

**D8. Mobile ergonomics and capability gaps**

- Typing and terminal ergonomics are poor, so people write terser prompts and get worse results; voice dictation leaves filler words ([HN](https://news.ycombinator.com/item?id=48140529)).
- No direct file editing, manual shell, plugin or MCP configuration on the phone ([Daniel Vaughan](https://codex.danielvaughan.com/2026/05/15/codex-mobile-chatgpt-app-relay-architecture-remote-agent-control/); consistent with OpenAI's [Remote connections](https://learn.chatgpt.com/docs/remote-connections#what-comes-from-the-connected-host) and [Plugins](https://learn.chatgpt.com/docs/plugins) pages, see A.4). One commenter wants cloud agents that do not depend on an online desktop ([HN](https://news.ycombinator.com/item?id=48140529)); the September 2026 Codex Cloud relaunch (agents keep working after you close the laptop) addresses that for cloud tasks ([forum announcement](https://community.openai.com/t/meet-the-all-new-codex-cloud/1402399)).
- Cloud environments cannot be created on mobile ([Cloud](https://learn.chatgpt.com/docs/cloud)).
- Users asked for cloud-task model and effort selection (HN; I did not verify whether this shipped).

**D9. Apple integration gaps**

- Widget launchers are not exposed as Shortcuts actions; no large iPhone or XL iPad widget; Voice and Remote voice share one icon ([MacStories](https://www.macstories.net/ios/openai-updates-chatgpt-for-ios-with-customizable-widgets-for-chatgpt-work-and-codex-remote/)).
- No official Apple Watch app ([OpenAI forum](https://community.openai.com/t/feature-request-native-chatgpt-companion-for-apple-watch-watchos/1392290)).
- Siri integration underperformed by OpenAI's own account ([Progressive Robot](https://www.progressiverobot.com/2026/09/25/chatgpt-in-siri-apple-intelligence-minimal-usage/), secondary).

**D10. Accessibility** regressions after updates (VoiceOver and NVDA), most recently reported July 2026 ([AppleVis](https://mail.applevis.com/comment/211605)).

**D11. Product churn and naming drift**

- Agent mode removed (mid-July 2026), group chat creation ended (2026-07-09), Pulse retired (announced 2026-06-17), custom GPTs retiring on 2026-12-11, App Directory replaced by the Plugin Directory (2026-07-09), Codex app merged into the ChatGPT desktop app (2026-07-09), "Remote" renamed "Codex", docs moved from developers.openai.com to learn.chatgpt.com (old URLs answer with HTTP 308), "Codex Cloud (Legacy)" versus the new Codex Cloud. Third-party guides already warn that older walkthroughs are outdated ([AICatchup](https://aicatchup.com/news/codex-chatgpt-mobile-preview)). The 2026-10-15 verification pass checked each item against OpenAI pages or archived copies of them (see the table at the end).

**D12. Cloud-browser and Work friction.** MacStories found cloud-browser sign-in frustrating: frozen UI on Mac, CAPTCHA takeovers needing several attempts, better on iPhone ([MacStories](https://www.macstories.net/?p=198275)). Dots: one dot only, no search in the thread, buggy Spaces ([MacStories](https://www.macstories.net/stories/openais-dots-a-first-look/)).

**D13. Streaming scroll.** Auto-scroll with no setting to stop it, and reports of a stuck scroll position while code streams ([OpenAI forum](https://community.openai.com/t/screen-auto-scrolls-as-the-response-being-generated/782378), [OpenAI forum](https://community.openai.com/t/chatgpt-wont-let-me-scroll-down-while-its-writing/1130778.md); both older than 2026).

**Where an opencode client can differentiate** (inference from D1 to D8): direct LAN or Tailscale connection with no vendor relay; a visible host-presence and last-synced indicator; first-class headless servers; complete project and session lists straight from the server; actionable notifications with distinct needs-input, approval and done events; in-app host management; native App Intents for every launcher; and a read-write file editor for small fixes.

---

# Part E. Open questions after the 2026-10-15 verification pass

Resolved by the pass (details in the table at the end): no standalone Codex iOS app exists; how the phone reaches SSH hosts; Remote plan availability; the PR inbox on the phone; group chats; agent mode; the Plugin Directory; Work's plans; voice modes and limits; the live-voice Live Activity; multi-page scanning and audio uploads (both in OpenAI's release notes of 2026-10-01 and 2026-10-06); the effort labels; canvas; iOS haptics; the 2025 Pulse launch date.

Still open:

- Whether best-of-N attempts survive in the new Codex Cloud and appear on iPhone; whether the phone shows cloud task logs.
- Whether the phone can create a PR from a Remote task.
- Whether the keep-keyboard-open setting applies to Chat.
- Current Action Button and Lock Screen voice entry points (needs a browser check of OpenAI's Siri and Shortcuts article for iOS).
- Dynamic Type support; when deep research first reached iOS.
- A Control Center control for regular ChatGPT Voice on iOS 18: only the Remote voice control is confirmed.

---

# Appendix: primary and key sources

- OpenAI docs (learn.chatgpt.com): [Codex on mobile](https://learn.chatgpt.com/docs/mobile), [Remote connections](https://learn.chatgpt.com/docs/remote-connections), [Codex Cloud](https://learn.chatgpt.com/docs/cloud), [Cloud environments](https://learn.chatgpt.com/docs/environments/cloud-environments), [Changelog](https://learn.chatgpt.com/docs/changelog), [What's new](https://learn.chatgpt.com/docs/whats-new), [Pricing](https://learn.chatgpt.com/docs/pricing), [Models](https://learn.chatgpt.com/docs/models), [Voice](https://learn.chatgpt.com/docs/features/voice), [Dots](https://learn.chatgpt.com/docs/dots), [CLI reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli), [Index of all pages](https://learn.chatgpt.com/llms.txt).
- Press: [9to5Mac](https://9to5mac.com/2026/05/14/openai-brings-codex-control-to-chatgpt-for-iphone-and-android/), [MacRumors](https://www.macrumors.com/2026/05/15/openai-brings-codex-chatgpt-mobile-app/), [TechCrunch](https://techcrunch.com/2026/05/14/openai-says-codex-is-coming-to-your-phone/), [MacStories widgets](https://www.macstories.net/ios/openai-updates-chatgpt-for-ios-with-customizable-widgets-for-chatgpt-work-and-codex-remote/), [MacStories Remodex](https://www.macstories.net/reviews/remodex-codex-remote-mobile-app-ios/), [MacStories cloud browser](https://www.macstories.net/?p=198275), [MacStories dots](https://www.macstories.net/stories/openais-dots-a-first-look/).
- Community: [HN thread](https://news.ycombinator.com/item?id=48140529), [openai/codex iOS-labeled issues](https://github.com/openai/codex/issues?q=is%3Aissue+label%3AiOS+sort%3Areactions-%2B1-desc).
- App Store: [ChatGPT listing](https://apps.apple.com/us/app/chatgpt/id6448311069).
- Read through Wayback Machine copies in the 2026-10-15 pass: [ChatGPT release notes (2026-10-10)](https://web.archive.org/web/20261010013210/https://help.openai.com/en/articles/6825453-chatgpt-release-notes), [ChatGPT agent](https://web.archive.org/web/20261012103042/https://help.openai.com/en/articles/11752874-chatgpt-agent), [ChatGPT Voice](https://web.archive.org/web/20261015092947/https://help.openai.com/en/articles/20001274-chatgpt-voice), [Deep research](https://web.archive.org/web/20260914073610/https://help.openai.com/en/articles/10500283-deep-research).
- Still not readable by the tools (cited only through search results or mirrors): [Introducing Codex](https://openai.com/index/introducing-codex/), [Work with Codex from anywhere](https://openai.com/index/work-with-codex-from-anywhere/).

---

## Verification pass (2026-10-15)

Scope: the 35 claims the first draft tagged unverified, plus untagged claims found wrong or out of date along the way, plus five claims the product spec took from this report. Line numbers (L) refer to the first draft. Archived copies were read on the Internet Archive's Wayback Machine because help.openai.com, openai.com and chatgpt.com return HTTP 403 to the fetch tools. "RN" below means the [ChatGPT release notes, archived 2026-10-10](https://web.archive.org/web/20261010013210/https://help.openai.com/en/articles/6825453-chatgpt-release-notes); "changelog" means [learn.chatgpt.com/docs/changelog](https://learn.chatgpt.com/docs/changelog).

Outcome counts for the 35 tags: VERIFIED 14, CORRECTED 13 (one is the legend in section 0), REMOVED 1, UNCONFIRMED 7, NEEDS BROWSER 0 (the one browser check, done on 2026-10-15, stayed unconfirmed).

| # | Claim (short) | Outcome | Evidence (URL or command) |
|---|---|---|---|
| 1 | L7 legend describing the "unverified" marker | CORRECTED (legend rewritten for the new markers) | This section |
| 2 | L30 agent mode removed "about August 2026" | CORRECTED: mid-July 2026 | [help article, archived 2026-07-20](https://web.archive.org/web/20260720213323/https://help.openai.com/en/articles/11752874-chatgpt-agent) has the notice; [2026-07-11 copy](https://web.archive.org/web/20260711195731/https://help.openai.com/en/articles/11752874-chatgpt-agent) does not |
| 3 | L30 group chat creation ended 2026-07-09 | VERIFIED | RN, 2026-07-09 "Retiring group chats in ChatGPT" |
| 4 | L88 picking repo or branch per cloud task on mobile is undocumented | VERIFIED | [Cloud environments](https://learn.chatgpt.com/docs/environments/cloud-environments), [Codex Cloud](https://learn.chatgpt.com/docs/cloud) |
| 5 | L109 best-of-N in the new cloud and on iPhone | UNCONFIRMED | [CLI reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli) (`--attempts` 1 to 4, `attempt_total`); no mention in cloud, mobile pages or iOS changelog entries |
| 6 | L111 logs view for cloud tasks on iOS | UNCONFIRMED | Cloud, Cloud environments and [mobile](https://learn.chatgpt.com/docs/mobile) pages; changelog iOS entries |
| 7 | L138 phone talks to SSH hosts directly or via desktop | CORRECTED: both paths exist | [Remote connections](https://learn.chatgpt.com/docs/remote-connections); [#23543](https://github.com/openai/codex/issues/23543), [#23466](https://github.com/openai/codex/issues/23466), [#22857](https://github.com/openai/codex/issues/22857); changelog 1.2026.146 and .181 |
| 8 | L146 Ed25519, X25519, AES-256-GCM, metadata-only relay | CORRECTED: describes Remodex, not OpenAI | [Remodex secure-transport.js](https://github.com/Emanuele-web04/remodex/blob/main/phodex-bridge/src/secure-transport.js), [relay README](https://github.com/Emanuele-web04/remodex/blob/main/relay/README.md) |
| 9 | L166 phone cannot edit files, run a shell, configure plugins, MCP or config.toml | VERIFIED (documented scope) | [Remote connections](https://learn.chatgpt.com/docs/remote-connections), [Plugins](https://learn.chatgpt.com/docs/plugins), changelog 1.2026.160 |
| 10 | L224 HN: `/handoff` moves a local session to the cloud | CORRECTED: no `/handoff` in the docs; `/cloud` exists | [Slash commands](https://learn.chatgpt.com/docs/reference/slash-commands), [Remote connections](https://learn.chatgpt.com/docs/remote-connections) |
| 11 | L230 PR inbox or PR review from the phone | CORRECTED: desktop and web only | RN, 2026-09-29 "Review pull requests with Codex"; [Code review](https://learn.chatgpt.com/docs/code-review) |
| 12 | L231 PR creation from a Remote task on the phone | UNCONFIRMED | changelog iOS entries 1.2026.132 to .272; mobile and Remote pages |
| 13 | L240 Live Activity for running Remote tasks | CORRECTED: none shipped; request open | `gh api repos/openai/codex/issues/34912`; changelog 1.2026.244 |
| 14 | L250 no standalone Codex iOS app | VERIFIED | `curl 'https://itunes.apple.com/lookup?id=1684349733&entity=software&country=us'` (ChatGPT and ChatGPT for Intune only); `curl 'https://itunes.apple.com/search?term=codex&entity=software&country=us'` |
| 15 | L254 GA note says "all plans" | VERIFIED (and the "conflicting sources" framing fixed) | RN, 2026-06-25 and 2026-05-14 entries; [Pricing](https://learn.chatgpt.com/docs/pricing) has no Free or Go column |
| 16 | L278 keep-keyboard-open setting applies to Chat | UNCONFIRMED | changelog 1.2026.267; not in RN |
| 17 | L289 slider labels Instant, Medium, High, Extra High | CORRECTED: dated 2026-06-10, Extra High Pro-only then | RN, 2026-06-10 "Simplified controls in the model picker" and 2026-10-07 |
| 18 | L311 GPT-Live tier mapping and Business, Enterprise, Edu coverage | CORRECTED: per-plan limits added | RN, 2026-07-08; [ChatGPT Voice, archived 2026-10-15](https://web.archive.org/web/20261015092947/https://help.openai.com/en/articles/20001274-chatgpt-voice) |
| 19 | L312 voice modes Live, Advanced, Standard; Live lacks video | VERIFIED (URL fixed: the article slug is chatgpt-voice) | [ChatGPT Voice, archived 2026-10-15](https://web.archive.org/web/20261015092947/https://help.openai.com/en/articles/20001274-chatgpt-voice) |
| 20 | L316 Live voice on Lock Screen and Dynamic Island | VERIFIED (date 2026-08-31) | RN, 2026-08-31 "See Live voice content on your Lock Screen" |
| 21 | L320 Action Button and Lock Screen voice widget still current | UNCONFIRMED (after browser check, 2026-10-15) | Siri and Shortcuts article now returns "That page doesn't exist"; help-center search finds nothing; the current Voice article (https://help.openai.com/en/articles/20001274-chatgpt-voice) omits both |
| 22 | L336 which image limit applies to Free in Chat | CORRECTED: Free can generate images in Chat | RN, 2026-04-21 (Images 2.0 on all plans) and 2026-09-08 (limits unchanged); [Pricing](https://learn.chatgpt.com/docs/pricing) covers Work and Codex |
| 23 | L342 deep research on iOS in 2025 | UNCONFIRMED (launch post promised mobile "within the month") | [launch post, archived](https://web.archive.org/web/20261011125149/https://openai.com/index/introducing-deep-research/); [help article, archived 2026-09-14](https://web.archive.org/web/20260914073610/https://help.openai.com/en/articles/10500283-deep-research) |
| 24 | L347 Work: Pro, Pro Lite, Enterprise, Edu first, then Plus and Business | VERIFIED | RN, 2026-07-09 "Introducing ChatGPT Work" |
| 25 | L347 Work: Plus, Pro, Business, Enterprise | VERIFIED (all plans except Free and Go) | RN, 2026-07-09 |
| 26 | L349 agent mode removal notice, "early August" | CORRECTED: notice verified, date mid-July | Same as #2 |
| 27 | L351 Free users get up to three scheduled tasks | VERIFIED | RN, 2026-08-25 "Scheduled tasks for Free users" |
| 28 | L357 no 2026 documentation of Canvas on mobile | CORRECTED: canvas is being retired | RN, 2026-05-28 "GPT-5.5 Instant Update" |
| 29 | L369 App Directory replaced by Plugin Directory 2026-07-09 | VERIFIED | RN, 2026-07-09; [Plugins](https://learn.chatgpt.com/docs/plugins) |
| 30 | L378 press: dots always leave money movement to the human | REMOVED: the cited article mentions only password changes | [The Next Web](https://thenextweb.com/news/openai-dots-always-on-ai-agents-cloud-computers-devday) (fetched in full); [Dots controls](https://learn.chatgpt.com/docs/dots/controls) |
| 31 | L384 group chat creation and invite joins ended 2026-07-09 | VERIFIED | RN, 2026-07-09 |
| 32 | L425 Dynamic Type support | UNCONFIRMED (one hint in 1.2026.188) | changelog 1.2026.188; RN; Wayback index of help.openai.com |
| 33 | L443 current iOS haptics | CORRECTED: haptics present, auto-off in Low Power Mode or under 20 percent battery | [iOS help article, archived 2026-08-25](https://web.archive.org/web/20260825095239/https://help.openai.com/en/articles/7925783-why-did-haptic-feedback-stop-working) |
| 34 | L551 no file editing, shell, plugin or MCP config on the phone | VERIFIED | Same as #9 |
| 35 | L565 churn items unverified against OpenAI pages | VERIFIED | RN (2026-06-17, 2026-07-09, 2026-09-11); agent help article; [mobile](https://learn.chatgpt.com/docs/mobile); `curl -sI https://developers.openai.com/codex` returns 308 to learn.chatgpt.com |

Untagged claims fixed or upgraded during the pass:

| # | Claim (short) | Outcome | Evidence (URL or command) |
|---|---|---|---|
| U1 | L26 Remote reaches "Mac, Windows PC or SSH host, through an OpenAI relay" | CORRECTED: SSH hosts sit behind a desktop host or are added in the iOS app | Same as #7 |
| U2 | L147 and B.16 Face ID or passcode lock "in the app" | CORRECTED: the lock is for Codex | changelog 1.2026.146 |
| U3 | L254 Remote plan sources "conflicting" | CORRECTED: no conflict | Same as #15 |
| U4 | L276 long-press send "not formally announced" | CORRECTED: announced 2026-06-08 (choose a model for one message) | RN, 2026-06-08 |
| U5 | L342 deep research "now part of Work" | CORRECTED: also in Chat (and Codex) | [help article, archived 2026-09-14](https://web.archive.org/web/20260914073610/https://help.openai.com/en/articles/10500283-deep-research) |
| U6 | L356 Space plans and mobile "not documented" | CORRECTED: Pro, Business, Enterprise on desktop and web | RN, 2026-09-29 |
| U7 | L509 #23948 cited as an open lock-screen bug | CORRECTED: closed by its reporter the same day as a likely duplicate of #23294 | `gh api repos/openai/codex/issues/23948` |
| U8 | A.4 Linux hosts | ADDED: Linux desktop app in preview since 2026-08-14, not a listed Remote host | RN, 2026-08-14; [Linux app](https://learn.chatgpt.com/docs/linux/linux-app) |
| U9 | B.9 Pulse launch date "not verified" | ADDED: 2025-09-25, Pro, iOS and Android | RN, 2025-09-25 |
| U10 | Part D ranking of pain points | ADDED: reaction counts | `gh api -X GET search/issues -f q='repo:openai/codex is:issue label:iOS' -f sort=reactions-+1 -f order=desc` |
| U11 | Citations upgraded to primary sources | VERIFIED | Work launch date, scanning, audio uploads (RN); Android haptics article (archived); OpenAIDevs and Viticci posts via `curl https://api.fxtwitter.com/OpenAIDevs/status/1924601527898951914` and `curl https://api.fxtwitter.com/viticci/status/2089420425193202065` |
| U12 | L39 and L42 product map: Work plans "described inconsistently", voice plans "unclear" | CORRECTED to match #24, #25 and #18 | RN, 2026-07-09 and 2026-07-08; Voice help article (archived) |

Claims the product spec took from this report:

| # | Spec claim (short) | Outcome | Evidence (URL or command) |
|---|---|---|---|
| S1 | Codex in the iOS app has cloud tasks plus Remote, a thin client to a Mac, Windows or SSH host through an OpenAI relay (preview 2026-05-14, GA 2026-06-25), paired per phone per host by QR or code; `codex remote-control pair` serves headless hosts | CORRECTED: dates, relay, per-device QR pairing and manual codes hold for Mac and Windows desktop hosts. SSH hosts are reached through a desktop host or added directly in the iOS app, which then connects over SSH itself, not through the relay. `codex remote-control start` and `pair` are in the CLI reference and users run them on headless Linux, but the Remote page says setup cannot start from the CLI, the daemon is Unix-only and API-key auth is unsupported | RN, 2026-05-14 and 2026-06-25; [Remote connections](https://learn.chatgpt.com/docs/remote-connections); [CLI reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli); changelog 1.2026.160; [#23200](https://github.com/openai/codex/issues/23200), [#22857](https://github.com/openai/codex/issues/22857), [#23466](https://github.com/openai/codex/issues/23466) |
| S2 | Approval card offers Approve, Always approve, Tell Codex what to do, Deny | VERIFIED (labels from OpenAI's mobile page; 1.2026.272 redesigned the picker, so wording may since have shifted) | `curl -sL https://learn.chatgpt.com/docs/mobile` and search the HTML for "Always approve"; changelog 1.2026.272 |
| S3 | Queue vs Steer, diffs with inline comments, widgets, Face ID lock | VERIFIED (the lock is scoped to Codex) | changelog 1.2026.146, .153, .230, .267 |
| S4 | Top pain points: Mac sleep or lock disconnects, 10+ s reconnects on resume, missing or non-actionable approval notifications (#32908, #39346; also #22700, #36040, #23200) | CORRECTED: all five issues exist and are open, but by reactions the top items are headless Linux (#23200, 66), revoked-device pairing (#22700, 36; #22715, 29, closed), offline host with a dead Reconnect (#22898, 40), worktree choice (#22925, 25) and SSH projects (#23527, 23); #32908 (18) and #39346 (13) rank next. The 10 s resume issue (#37997) has 2 reactions and the Mac-sleep issue (#23294) 10 | `gh api -X GET search/issues -f q='repo:openai/codex is:issue label:iOS' -f sort=reactions-+1 -f order=desc`; `gh api repos/openai/codex/issues/<n>` |
| S5 | No standalone Codex iOS app and no Apple Watch app | VERIFIED | Same as #14; ChatGPT's `supportedDevices` in `curl 'https://itunes.apple.com/lookup?id=6448311069&country=us'` has no Watch entries, while apps with Watch apps list `Watch4-Watch4`; open request [#33528](https://github.com/openai/codex/issues/33528) |
