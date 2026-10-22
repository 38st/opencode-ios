# opencode for iOS: product spec

*Draft 2, 2026-10-15, updated after the verification pass (§10). Working name "opencode-ios"; the final name is an open decision (§9).*

A native iPhone and iPad client for opencode V2 servers, built to be the most reliable way to run and supervise opencode away from the desk. This file is the entry point. The detail lives in:

| Document | Contents |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Modules, sync engine, persistence, push and Live Activities, security model, testing strategy, milestones, risks |
| [research/08-feature-matrix.md](research/08-feature-matrix.md) | 141 features compared across opencode, the official OpenCode iOS beta, Cursor, Claude and ChatGPT, each mapped to the V2 API and given a priority |
| [research/01-opencode-server-api.md](research/01-opencode-server-api.md) | V2 protocol reference: every route, event and tool; auth, pairing, terminals, gotchas |
| [research/02-opencode-features.md](research/02-opencode-features.md) | Everything opencode does today, and how the official clients present it |
| [research/03-mobile-clients-landscape.md](research/03-mobile-clients-landscape.md) | Official and third-party mobile clients; connectivity and push options |
| [research/04-cursor-mobile.md](research/04-cursor-mobile.md), [05-claude-mobile.md](research/05-claude-mobile.md), [06-chatgpt-mobile.md](research/06-chatgpt-mobile.md) | Feature inventories of the three reference apps, with patterns to copy and user pain points |
| [research/07-ios-stack.md](research/07-ios-stack.md) | iOS platform and library choices |
| [research/opencode-openapi.json](research/opencode-openapi.json) | The V2 OpenAPI spec at commit `d0732ea` (identical to releases 2.0.29 and 2.0.30) |

## 1. Goal

Everything you can do at the desk with opencode, from the phone, without losing a prompt or missing an approval:

- See every session on every server you own, sorted by what needs you.
- Watch runs stream live, then steer, queue or stop them.
- Approve permissions and answer questions in the app, from a notification, or from the lock screen.
- Review changes as diffs, comment on lines, browse files, and use a real terminal.
- Start sessions in any project or worktree with any model, agent and reasoning variant.
- Manage providers, MCP servers and saved permissions.

iPhone comes first. iPad is a full workspace (three columns, an inspector, keyboard shortcuts, several windows), and the same build runs on Apple silicon Macs.

The app never runs agents itself and never stores code on a vendor server. The user's own opencode server does the work and stays the source of truth.

## 2. Facts that shape the design

These come from the opencode source at commit `d0732ea` (release 2.0.30 plus one docs commit, 2026-10-15). The key ones were checked by hand.

1. **opencode V2 is a new API.** V2.0.0 was tagged on 2026-09-11, and the latest release is 2.0.30 (npm package `@opencode/cli`). V2 replaced V1's HTTP API with `/api/*` routes, so V1 servers (npm `opencode-ai`, 1.19.1) are incompatible. V1 1.19.0 (2026-10-11) added `opencode upgrade --major` to move to V2. **Decision: support V2 only**, version 2.0.10 or later (pairing needs 2.0.25). A V1 server gets a clear upgrade screen.
2. **Pairing is official.** `opencode pair` prints a QR code that holds `{code, urls}`. The phone redeems the one-time code at `GET /auth/connect/{code}` and receives a 30-day token, which it sends as the HTTP Basic password with the fixed username `opencode`. There is no refresh endpoint. `opencode pair --remote` adds an OpenTunnel URL: Anomaly's HTTPS relay, which ends TLS on the developer's machine, so the relay cannot read the traffic.
3. **One event stream, with no replay.** `GET /api/event` is a single global SSE stream with a heartbeat every 15 s. It never replays missed events, and it closes a client that falls 4,096 frames behind. Durable events carry `{aggregateID, seq, version}`. Text deltas arrive in 100 ms batches, and each `*.ended` event carries the authoritative final value. The client must therefore resync over REST after every reconnect.
4. **Prompts are asynchronous.** A prompt goes into a durable inbox with `steer` or `queue` delivery. Model and agent are changed with separate calls. Busy or idle state comes from `session.execution.*` events plus `GET /api/session/active`.
5. **Terminals** use REST to create, resize and delete them, plus a WebSocket at `/api/pty/{id}/connect` that resumes from a cursor.
6. **The OpenAPI spec cannot feed a code generator directly.** It is OpenAPI 3.1 with 118 paths, 142 operations and 285 schemas. Unions are `anyOf` without discriminators, and almost every object sets `additionalProperties: false`, so a generated Swift client would fail on any new server field. **Decision: hand-written, tolerant models.**
7. **opencode itself has no push.** The desktop and web apps notify only when a response is ready or a session fails, never on a permission request (issue #51507 is open). The official iOS beta gets notifications through a notify plugin whose source is not public (testers hit a 404 installing it, issue #54483). **Decision: our own opencode plugin plus a small relay** (§6).
8. **V2 moves fast:** about six releases a week (23 in the 28 days to 2026-10-15), no API version, and no mDNS. Hence tolerant decoding, capability detection, nightly contract tests against the newest release, and QR or link pairing instead of LAN discovery.

## 3. Landscape and positioning

| Product | State (October 2026) | Strengths to match | Weak spots we can beat |
|---|---|---|---|
| Official OpenCode iOS app | Public TestFlight since 2026-10-08, capped at 1,000 testers; build 0.1.0 (278); closed source; not in the App Store | Official pairing and OpenTunnel; several servers; voice "delegations" into sessions; push notifications through an unpublished notify plugin | Very early (testers report connection failures, for example issue #54627); the push plugin is not published, so its design and privacy cannot be checked |
| 27+ third-party opencode clients (22 live App Store listings plus open-source repos: OpenLens, OpenClient, Paseo, OpenChamber, CodeNomad and others) | Mixed quality; V2 broke several (grapeot/opencode_ios_client, WhisperCode) | OpenChamber's sealed-push relay design; OpenClient's multi-column iPad layout (as advertised) | Fragile reconnects; no background push without extra infrastructure, or plaintext previews through Expo, FCM or the apps' own APNs relays; weak iPad layouts; laggy transcripts; abandoned projects |
| Cursor for iOS | Launched as a beta on 2026-06-29 (the docs dropped the beta label in September); iPad since 2026-07-29; needs iOS 26 | Inbox built around "needs attention"; Live Activities for up to 8 agents; full PR screen; voice dictation; screenshot markup | No editor, terminal or file browser; no line comments on diffs; no non-interrupting steer (follow-ups queue, and "Send now" interrupts); Remote Control is hard to find and flaky |
| Claude iOS (Code tab) | Cloud sessions GA on 2026-09-23; Remote Control of a local CLI session (out of preview since August) | Triage list with status filters; QR pairing over an outbound-only relay; queue, steer and stop; presence-aware push | Reconnect failures (issue #34255, 109 reactions); approval prompts that cut commands to about 100 characters with no way to expand (#37235, #86704); no Live Activity for Code sessions (per user reports) |
| ChatGPT iOS (Codex tab) | Cloud tasks, plus Remote (GA 2026-06-25) to a Mac or Windows host through OpenAI's relay, or to SSH hosts | Approval card (Approve, Always approve, Tell Codex what to do, Deny); Queue versus Steer; diffs with inline comments; widgets; Face ID lock for Codex | No first-class headless Linux host (#23200, the most-upvoted Remote issue); revoked hosts that cannot be removed (#22700); missing or non-actionable approval notifications (#32908, #39346); no Live Activity for Remote tasks; PR review only on desktop and web |

**Where we win** (justified in [section 3 of the matrix](research/08-feature-matrix.md)):

1. Approvals that show the full command or diff (Claude cuts commands to about 100 characters), and approval notifications that are private (sealed end to end, with a published plugin and relay) and actionable (Allow once after unlocking), where silence never counts as consent.
2. Reconnects that recover, with an honest connection state instead of a stream that only looks alive.
3. No vendor in the loop: LAN, Tailscale, OpenTunnel, custom HTTPS and later SSH; headless Linux servers included (ChatGPT's most-upvoted Remote request); no account needed.
4. Prompts are never lost (a persistent outbox and drafts), and every follow-up can be sent as steer or queue.
5. Review built for the phone, with line comments that go back to the agent.
6. A real terminal with a key bar, which none of the three reference apps has.
7. One inbox across several servers.
8. The full Apple surface: Live Activities, widgets, App Intents and Shortcuts, a real iPad layout, and accessibility.

## 4. Scope

The matrix lists 141 features: **46 P0** (MVP daily driver), **59 P1** (v1.0 parity), **34 P2** (later or differentiators) and 2 N/A.

### 4.1 MVP (P0)

- **Connection:** pair by QR code or link; manual URL and password; reach the computer from anywhere (OpenTunnel, Tailscale, HTTPS); detect V1 and outdated servers; honest connection state, fast reconnect and full resync; re-pair on 401.
- **Inbox:** one inbox across projects with a "Needs you" group and filters; start a session in a chosen project, directory or worktree; unread state shared with other clients; subagent cards with drill-in and family cost.
- **Transcript:** live streaming text and reasoning; Markdown with highlighted code, tables and copy buttons; tool rows by type, grouped and collapsible; live shell output; inline diff cards; status, retry and error cards; paging for long sessions.
- **Composer:** stays above the keyboard; drafts that survive navigation, backgrounding and relaunch; photos, camera and files; `@file` fuzzy search; slash commands (`/init`, `/review`, MCP prompts, custom commands).
- **Agent control:** model, reasoning-variant and agent pickers; steer, queue (with a visible queue) and stop.
- **Approvals:** permission sheet with the full command, path or diff (Allow once, Allow always, Reject with a note); one list of everything waiting, child sessions included; question forms; requests that survive reconnects and never time out into "yes".
- **Review:** per-turn Changes card, then a file list, then the diff; working-tree and branch diffs.
- **Push:** when the agent needs you, and when a run finishes or fails.
- **Platform:** deep and universal links; credentials only in the Keychain; encrypted transport options; sealed push payloads; an outbox with idempotent sends; fast resume; smooth long transcripts.

### 4.2 v1.0 parity (P1)

Several servers, each with several endpoints; session search, rename, delete, pin, fork and archive; undo, redo and revert with files restored; compaction; context, token and cost details; `@agent`, `@skill` and `@reference` mentions; `!` shell mode; prompt history; Mermaid and LaTeX; images in the transcript; voice delegations shown as Voice messages; a touch diff viewer (unified on iPhone, split on iPad) with line comments; file tree and viewer; agent code review; commit-and-push and open-a-PR; interactive terminal with a key bar; Live Activities; app badge; notification settings, presence-aware delivery and push health; approving from notifications; risk-tiered approvals with Face ID; saved "always" rules; dictation and hands-free voice; widgets; App Intents and Shortcuts; iPad multi-column layout, menu bar and shortcuts; provider sign-in (API key, or OAuth by code paste or device code); MCP management; app lock; cache-first launch and offline history; VoiceOver, Dynamic Type and Reduce Motion.

### 4.3 Later (P2)

SSH tunnel inside the app; Bonjour discovery (needs a plugin, because V2 has no mDNS); custom headers per server (Cloudflare Access); moving sessions between worktrees; export; scheduled runs; screenshot markup with Apple Pencil; `/btw` side questions; a PR cockpit; small file edits; persistent terminals; push-to-start Live Activities; Lock Screen, Control Center and Action button controls; Spotlight; a share extension; Handoff; Apple Watch; several windows and Stage Manager; Mac and Vision Pro; several accounts per provider; server administration; localization.

### 4.4 Deliberately out of scope

Chat-app features that do not fit a client for a user-run coding agent: image generation, consumer verticals (shopping, health, mail drafting), group chats, public share links (opencode discontinued sharing on 2026-10-15; export replaces it), incognito chats, account memory and styles, artifacts and canvas, vendor UI widgets, custom GPTs and app stores, video in voice mode, in-app subscriptions, and vendor-hosted cloud agents. opencode has no hosted execution; running `opencode serve` on a VPS covers the "laptop closed" case.

Several chat-app features arrive through opencode itself and only need good rendering: the web search and fetch tools, MCP connectors, `AGENTS.md` and skills as memory, and custom agents in place of custom GPTs.

## 5. App structure

**iPhone** follows the desktop UI's own mobile layout, with our triage added (layout updated 2026-10-17 to match the desktop app):

- **Home:** a project picker ("All projects" or one project), session search, and sessions grouped by day, as in the desktop sidebar. "Needs you" and "Running" sections across all servers sit on top. Blocked rows have a Review button; swipe to mark read or pin. New session, directory browser and a worktree option start from here.
- **Settings:** servers and endpoints, notifications, providers, MCP, saved permissions, app lock, diagnostics.

The **session screen** follows the desktop session page: the streaming timeline with the prompt dock at the bottom, a header with title, model, agent, context % and cost, and an approval dock above the prompt. The review panel (changes, files, terminal, context) opens from the toolbar.

**Visual design.** The app looks like the opencode desktop app (user decision, 2026-10-16). It uses the desktop app's colour tokens, the Inter and JetBrains Mono fonts, its icons and components, its session-timeline styling, and its three-pane layout on iPad. It adapts these to iOS for touch, safe areas, Dynamic Type and accessibility. Tokens and assets are ported from opencode's MIT-licensed `packages/ui` and listed in `THIRD_PARTY_NOTICES.md`. The app's name and icon stay distinct, so it is not mistaken for an official opencode app.

**iPad** mirrors the desktop layout: project tabs along the top, the session timeline with the prompt dock as the main column, a review panel on the right (changes with diffs, files, terminal, context), and the Home sidebar as a collapsible pane. It also has menu bar commands and keyboard shortcuts (⌘N, ⌘↩, ⌘., ⌘K and others). Several windows come later.

## 6. Architecture summary

The full design is in [ARCHITECTURE.md](ARCHITECTURE.md).

- **Project:** XcodeGen; an app target plus a Notification Service Extension and a Widgets extension; a local SPM package `OpencodeKit` (OCFoundation, OCModels, OCNetworking, OCSecurity, OCPersistence, OCShared, OCPushCore, OCSync, OCRender, OCDesign, OCActivity and the Feature targets). Swift 6 language mode; minimum iOS and iPadOS 26.4; built with Xcode 27.
- **Connection:** one `actor ServerConnection` per server owns the SSE stream, with a 45 s byte watchdog, jittered backoff, and endpoint racing across LAN, tailnet, HTTPS and tunnel addresses. Streams close in the background and reopen in the foreground.
- **Sync:** MainActor `@Observable` stores ported from the official client's `data.ts`; a full resync on every `server.connected`; duplicate removal by `seq`; gap splicing for open transcripts; optimistic writes with client-minted IDs; an outbox that survives restarts.
- **Decoding:** every union has an `.unknown` case and arrays decode lossily, so an unknown event or part can never crash the app or end the stream.
- **Persistence:** GRDB/SQLite storing raw server JSON plus a few indexed columns, so server schema changes need no migrations. Drafts and the outbox live there too.
- **Rendering:** a swift-markdown block pipeline drawn with Textual, where finished blocks are frozen and only the tail is re-parsed; tree-sitter highlighting; a Runestone file viewer; a custom diff renderer; SwiftTerm for the terminal; a `LazyVStack` transcript with a `UICollectionView` fallback.
- **Push:** a TypeScript opencode plugin seals per-device payloads with HPKE and sends them to our relay (a Cloudflare Worker with D1 that holds the APNs key). A Notification Service Extension decrypts them on the phone. Approval actions go straight from the phone to the server and are checked against a digest of what the user saw. The relay is never on the reply path and cannot read content.

## 7. Milestones

| Milestone | Outcome |
|---|---|
| M0 Foundations | Project skeleton, CI on Xcode 27, fixture recorder, mock LLM and contract harness. Spikes: SSE through OpenTunnel and `tailscale serve`; Worker-to-APNs over HTTP/2; a 2,000-row streaming list; mention editing |
| M1 Connection | Pairing (QR, link, manual), Keychain, version probe and V1 screen, endpoint racing, a robust stream, diagnostics. Passes an 8-hour soak and network switches |
| D1 Design system | Port the desktop app's look into OCDesign (tokens, fonts, icons, components, iPad three-pane shell) and restyle the existing screens; side-by-side comparisons against captures of the official UI |
| M2 Read path | Models, events, stores, resync and gap splicing, inbox, transcript with every tool renderer, subagents, paging, cache. Replaying each recorded fixture yields the same transcript as the server |
| M3 Write path | Composer, steer, queue and stop, outbox, drafts, pickers, new session and worktree, session actions, in-app approval and question sheets. No prompt lost across kill or relaunch |
| M4 Review and files | Changes card, diff viewer, VCS review, line comments, file browser (can run alongside M3) |
| M5 Push and Live Activities | Plugin, relay, sealed payloads, NSE, actionable notifications with digest checks, presence, delivery health, Live Activity |
| **MVP = M0 to M5** | Daily driver on iPhone and iPad |
| M6 iPad and system | Inspector, menu bar, shortcuts, multiple windows, App Intents, Spotlight, widgets, controls |
| M7 Terminal | SwiftTerm terminal, key bar, resume |
| M8 Parity | Providers, MCP, saved permissions, config, worktrees, voice, stats, export, side questions |
| M9 Launch | Accessibility, performance, App Attest, a hosted demo server for App Review, privacy policy, external TestFlight |

ARCHITECTURE.md estimates 17 to 20 calendar weeks to the MVP for two iOS engineers and a part-time TypeScript engineer. Re-estimate after M0 for the way this project is actually staffed.

## 8. Prerequisites

1. **opencode V2 on the development Mac.** This Mac runs V1 1.18.23 from Homebrew. Its local tap checkout is stale, so `brew info` shows 1.18.34, while the tap now ships 1.19.1. The documented path is `opencode upgrade` (to 1.19.1), then `opencode upgrade --major`, which on Homebrew uninstalls V1 and installs `anomalyco/tap/opencode-v2` ([v1.19.0 notes](https://github.com/anomalyco/opencode/releases/tag/v1.19.0), report 02). That replaces V1; running V2 side by side from npm (`@opencode/cli`, 2.0.30) is the alternative. Decide before M0.
2. **Apple Developer Program membership** for push, Live Activities, App Groups and TestFlight. On-device testing needs it from M1; M5 requires it.
3. **A Cloudflare account** for the relay, by M5.
4. **A GitHub repository** for the code.

## 9. Open decisions, with recommended defaults

| # | Decision | Recommended default |
|---|---|---|
| 1 | Protocol support | V2 only; V1 servers get an upgrade screen |
| 2 | Minimum OS | iOS and iPadOS 26.4, with iOS 27 features behind `#available`. This excludes about 4–5% of devices; at the end of September iOS 26 ran on about 75% and iOS 27 on about 16% (TelemetryDeck, report 07) |
| 3 | Open source | Decided 2026-10-21: the app is open source under GPL-3.0-only, and the plugin and relay will be MIT-licensed, so the privacy claims can be checked |
| 4 | Push content | Sealed summaries, decrypted on the device; an ID-only mode later |
| 5 | Approving from the lock screen | On, with risk tiers: Allow once needs an unlocked device, high-risk requests offer only Open and Reject, and "Allow always" exists only inside the app |
| 6 | Transcript cache on the device | On (last 200 sessions or 300 MB), with a metadata-only option |
| 7 | Telemetry | None by default; opt-in crash reports |
| 8 | MVP scope | Terminal (M7) and voice (M8) after the MVP; pull them in if they matter more than push |
| 9 | Name and branding | A distinct name that does not imply an official opencode app |
| 10 | Android later | Keep the plugin and relay platform-neutral either way |

## 10. Research quality

- The protocol facts come from the opencode source and were spot-checked by hand: the pairing route, `/api/event`, the npm versions and release dates, and the V1 `--major` upgrade.
- The first research pass left 158 claims tagged [unverified] because several agents ran out of web-search quota. A verification pass on 2026-10-15 resolved all of them from primary sources: GitHub, the App Store API, official docs and changelogs, SEC filings, archived pages, and a real browser for two pages that block fetch tools. Each claim is now verified with a source, corrected (marked "corrected 2026-10-15"), removed, or marked [unconfirmed] with the reason and what was tried. Each report ends with its verification table.
- 38 statements remain [unconfirmed]. Most are undocumented UI details of the competitor apps; a few are iOS behaviors (URLSession buffering of SSE, ATS for WebSockets, `TextEditor` input methods) that the M0 spikes will settle.
- Corrections that changed this spec: the official beta already has push; Claude truncates commands in approvals; ChatGPT's most-upvoted Remote complaints; Cursor's queue-only steering; the V1-to-V2 upgrade path; V2 sends PDFs to models that accept them.
- opencode V2 changes almost daily. Re-check the API reference against the newest release when M0 starts.
