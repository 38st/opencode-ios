# opencode iOS/iPadOS client: consolidated feature parity matrix

Research date: 2026-10-15. This report consolidates the sibling reports in this folder:

- `01-opencode-server-api.md`: the V2 server API (operations, events, sync rules).
- `02-opencode-features.md`: opencode V2 features, the official TUI, desktop and web clients, and the official OpenCode iOS TestFlight app.
- `03-mobile-clients-landscape.md`: third-party clients, connectivity and push.
- `04-cursor-mobile.md`, `05-claude-mobile.md`, `06-chatgpt-mobile.md`: Cursor for iOS, the Claude app (Claude Code in the Code tab) and the ChatGPT app (Codex Remote and cloud tasks).
- A few platform constraints come from `07-ios-stack.md` (deployment target, Live Activity and background limits).

No new research went into this file. Every cell restates one of those reports, and anything they do not settle is marked "?". Reports 02 to 07 went through a verification pass on 2026-10-15, and this file was then brought in line with them; the changes are listed in "Verification updates (2026-10-15)" at the end.

## How to read this document

**Columns**

- **Feature**: what the user can do. Row IDs (A1, B2, …) are used for cross-references in sections 3 and 4.
- **opencode V2 (TUI/desktop/web)**: the first-party clients on the V2 line (02). ✓ means at least one of them has it; the note says which when it matters.
- **Official OpenCode iOS (TestFlight)**: a closed-source beta (build 0.1.0, announced 2026-10-08, capped at 1,000 testers), probably written in native Swift (an inference in 03 §1.3). The reports know its pairing and voice features, that it connects to several servers, and that its push notifications need a server plugin that is not published and that testers could not install from the private repository (#54483; 02 D.1, 03 §1.1, §1.3). Most other cells are "?".
- **Cursor iOS**, **Claude iOS**, **ChatGPT iOS**: from 04, 05 and 06. For Claude and ChatGPT the coding surfaces (Claude Code, Codex) are what counts. Cursor's docs dropped the app's beta label in September 2026 without a general-availability announcement; only its Remote Control is still called beta (04 §3.1.1).
- **Best reference**: the implementation to copy or beat, with the reason in a few words.
- **V2 API support**: operationIds from 01 Appendix A, with HTTP paths where they help, and events from 01 Appendix B. "client-side" means no server support is needed. "missing: needs plugin", "needs relay" or "needs upstream" means V2 cannot do it today.
- **Priority**: see below.

**Cell values in the product columns**

| Value | Meaning |
|---|---|
| ✓ | Supported, according to the report. |
| partial | Supported with a documented limit, given in parentheses. |
| ✗ | Documented as absent, or absent by documented design (for example a vendor-relay-only product has no direct LAN path), or the report searched for it and found nothing (such as Cursor's "looked for and did not find" list in 04 §8). |
| ? | Not covered by the reports, unverified, or the sources conflict. |

**Priorities**

| Value | Meaning |
|---|---|
| P0 | Needed for the MVP daily driver: from a phone, a developer can pair with their own opencode V2 server, follow and steer sessions, get told when the agent needs them, answer approvals and questions, and check what changed. |
| P1 | Needed for v1.0 parity with opencode's own clients and with what Cursor, Claude and ChatGPT ship on iOS. |
| P2 | Later, or a differentiator that no competitor requires today. |
| N/A | Does not apply to an opencode client; the reason is given in the row. |

**Conventions and caveats**

- **Event names** follow 01's list of the 94 public V2 events. 02 also names `session.diff`, `file.edited`, `mcp.tools.changed`, `worktree.ready`, `worktree.failed`, `command.executed` and `session.error`; 01 found none of them in the V2 public event union, so this matrix does not rely on them. `session.status` and `session.idle` are declared but never emitted at HEAD (01 §7.3): busy and idle state comes from `session.execution.*` plus `session.active`.
- **Server floor**: V2 2.0.10 or later, and 2.0.25 or later for pairing and credential management (01 §12.4). V1 servers are detected and told to upgrade (A10); V1 support is not in this matrix.
- **OS reach is not a differentiator.** 07 recommends iOS/iPadOS 26.4 as the deployment target, the same generation that Cursor requires (iOS 26), while Claude and ChatGPT run on iOS 18. 07 now calls 26.4 defensible but thinly justified: it leaves out about 4–5% of users who have not updated (07 §1.3).
- **The official iOS app is a moving target.** It ships from a private repository. It connects to several servers and has push through an unpublished server plugin (#54483); its Live Activities, iPad layout, App Store timing and pricing are unknown (03 §1.3).

## Summary

The master matrix has **141 features: 46 P0, 59 P1, 34 P2 and 2 N/A.**

| Area | Rows | P0 | P1 | P2 | N/A |
|---|---|---|---|---|---|
| A. Connection and pairing | 13 | 7 | 3 | 3 | 0 |
| B. Inbox and session management | 17 | 5 | 7 | 3 | 2 |
| C. Transcript and rendering | 15 | 7 | 8 | 0 | 0 |
| D. Composer and input | 11 | 5 | 4 | 2 | 0 |
| E. Agent control | 11 | 6 | 3 | 2 | 0 |
| F. Approvals and questions | 9 | 4 | 5 | 0 | 0 |
| G. Review (diffs, files, git and PRs) | 10 | 2 | 6 | 2 | 0 |
| H. Terminal | 4 | 0 | 2 | 2 | 0 |
| I. Notifications and Live Activities | 9 | 2 | 5 | 2 | 0 |
| J. Voice | 4 | 0 | 2 | 2 | 0 |
| K. System integration | 8 | 1 | 2 | 5 | 0 |
| L. iPad and Mac | 4 | 0 | 2 | 2 | 0 |
| M. Settings and server administration | 9 | 0 | 3 | 6 | 0 |
| N. Security and privacy | 7 | 4 | 2 | 1 | 0 |
| O. Offline and performance | 6 | 3 | 2 | 1 | 0 |
| X. Accessibility | 4 | 0 | 3 | 1 | 0 |
| **Total** | **141** | **46** | **59** | **34** | **2** |

Main findings:

1. **The stable V2 API covers almost all of the MVP.** Of the 46 P0 rows, only three need anything beyond V2: push for "needs you" (I1), push for "finished or failed" (I2), and sealed push payloads (N5). All three need our own opencode plugin plus a push relay (section 4.1).
2. **The official OpenCode iOS app is known for pairing (QR code, pasted link, OpenTunnel), voice delegation, several servers, and push through an unpublished server plugin (#54483).** It is probably native Swift (an inference in 03). Most other cells in its column are "?".
3. **Each competitor leads somewhere.** Claude's Code tab is the best triage inbox (its filter chips appear in App Store images; Anthropic's own docs screenshot shows a dropdown); ChatGPT (Codex) is the best reference for the composer, steer and queue, review filters and reconnect UI; Cursor leads on Live Activities, iPad layout and the PR cockpit. All three depend on their own clouds and accounts and route desktop hosts through their own relays; only ChatGPT can also reach an SSH host directly from the phone.
4. **The strongest differentiators** (section 3): private, actionable approval notifications; reconnects that recover; no vendor in the loop; prompts that are never lost; phone-first review; a real terminal; a complete inbox across several servers.
5. **Upstream asks** (section 4.3): a shared push-target contract, session archiving, transcript content search, stable event replay, phone-friendly OAuth, and per-device tokens.

## 1. Master matrix

### A. Connection and pairing

| Feature | opencode V2 (TUI/desktop/web) | Official OpenCode iOS (TestFlight) | Cursor iOS | Claude iOS | ChatGPT iOS | Best reference | V2 API support | Priority |
|---|---|---|---|---|---|---|---|---|
| **A1** Pair by scanning the `opencode pair` QR code (JSON `{code, urls}`) | ✓ (`opencode pair`, desktop Settings → Pairing; the web app's scanner is web-only) | ✓ | ✗ (account sign-in; pairing approved on the desktop) | ✓ (QR from `claude remote-control`) | ✓ (QR per phone and host) | opencode web parser: tries every URL, prefers the first that answers within 1 s | `server.pair` (`POST /api/pair`, single-use, 5 min); `server.connect` (`GET /auth/connect/{code}` → 30-day token used as the Basic-auth password) | P0 |
| **A2** Paste a one-time `/auth/connect/<code>` link | ✓ (legacy `/connect#…` links are rejected with a message) | ✓ (paste into the server address field) | ✗ | ✓ (open the session URL) | ✓ (manual pairing code) | ChatGPT (code field accepts pasted, formatted codes) | `server.connect` | P0 |
| **A3** Manual server URL plus password (LAN, Tailscale, reverse proxy) | ✓ ("No pairing link? Use password") | ? | ✗ (relay only) | ✗ (relay only) | partial (SSH hosts only: the iOS app's "Add SSH Host" form takes host, port, user and a password or key; desktop hosts go through the relay) | opencode connect dialog (validates with `/api/info`) | `server.info` with `Authorization: Basic opencode:<password>`; LAN is plain HTTP (ATS `NSAllowsLocalNetworking`) | P0 |
| **A4** Reach the computer from anywhere | ✓ (OpenTunnel via `pair --remote` or desktop "Pair device") | ✓ (`pair --remote`; early connect bug #54627, closed) | ✓ (Cursor relay; outbound-only worker) | ✓ (Anthropic relay; host makes outbound HTTPS only) | ✓ (OpenAI relay) | OpenTunnel: TLS ends on the user's machine, no account needed | OpenTunnel HTTPS URL, listed in `server.info.urls`; nothing extra for the app | P0 |
| **A5** Several servers or computers in one app, each with live status | ✓ (desktop/web: many servers, health dots) | ✓ (several servers, per Dax Raad) | ✓ (computers grouped in the inbox) | ✓ (Devices section, status dot per computer) | ✓ (switch hosts; offline hosts shown) | ChatGPT (offline hosts stay visible; tasks keep their computer while it reconnects) | `server.info` per server (desktop polls every 10 s); one `event.subscribe` stream per server | P1 |
| **A6** One server record with many endpoints (LAN, Tailscale, OpenTunnel, custom), raced on every connect | partial (QR carries every address; raced only at pairing) | ? | ✗ (relay only) | ✗ (relay only) | ✗ (relay for desktop hosts; one address per SSH host) | 03 §4.3 layers 0–1; OpenChamber shows LAN versus relay | refresh `server.info.urls` on each connect (the tunnel URL appears there) | P1 |
| **A7** Custom request headers per server (Cloudflare Access service tokens, ngrok) | ? | ? | ✗ (relay only) | ✗ (relay only) | ✗ (relay or SSH connections only) | 03 §4.2 E (Access headers on every request) | client-side | P2 |
| **A8** SSH tunnel inside the app | partial (desktop SSH-server extension using `ssh -L`) | ? | ✗ (relay only) | ✗ (relay only) | partial (SSH hosts through a desktop host, or added in the iOS app, which connects to them directly; users say only PEM-format Ed25519 or ECDSA keys work) | grapeot client (Citadel); 07 picks Citadel 0.12.1 | client-side `direct-tcpip` to `127.0.0.1:49374`; the PTY WebSocket must use the tunnel too | P2 |
| **A9** Bonjour/mDNS discovery on the LAN | ✗ (no mDNS in V2; V1 `--mdns` only) | ? | ✗ (relay only) | ✗ (relay only) | ✗ (hosts are paired by QR code or added by address) | OpenLens (Bonjour for V1 servers) | missing: needs plugin (advertise a service such as `_opencode._tcp`) or upstream | P2 |
| **A10** Detect the server line and version; explain incompatible servers | ✓ (desktop "incompatible server" panel for V1) | ? (testers told to upgrade to v2.0.26 first) | ? | ? | ? | opencode desktop incompatible-server panel | `server.info` (`version`, `capabilities`); V1 answers `GET /global/health`; gate features at 2.0.10 and 2.0.25 | P0 |
| **A11** Honest connection state and fast, reliable reconnect with full resync | partial (watchdog and resync, but no reconnect banner for HTTP servers; Safari stuck after a network switch, #55673) | ? | ✓ (stream reconnects after network changes and catches up; clear "disabled" state) | partial (Send disabled while the host is unreachable; reconnect failures are the top complaint, #34255) | partial (reconnect progress shown; an offline host's Reconnect button does nothing, #22898, 40 reactions; 10+ s resumes reported, #37997) | opencode `connection.ts` timings plus ChatGPT's reconnect UI | `event.subscribe` (`server.connected` first, `: heartbeat` every 15 s, no replay) → `session.active` and refetch of visible scopes | P0 |
| **A12** Re-authenticate on 401 (30-day token, no refresh endpoint) | ✓ ("Authenticate" on signed-out servers) | ? | ? | partial (Trusted Devices asks for biometrics after 18 h) | partial (pairings unused since 2026-06-08 had to be redone) | opencode desktop "Authenticate" row | 401 `UnauthorizedError` → new code through `server.connect` | P0 |
| **A13** Keep the host reachable: keep-awake setting and an honest "computer asleep" state | partial (desktop Pairing page "Keep screen active") | ? | ✓ ("Keep this computer awake", plugged in, lid open) | ✓ ("Keep this computer awake for Remote Control") | partial (host must stay awake; "Keep this Mac awake" still slept, #23294) | Cursor and Claude (keep-awake with honest caveats) | missing: needs upstream (no API to read or set host sleep); the app can only show "unreachable since …" | P1 |

### B. Inbox and session management

| Feature | opencode V2 (TUI/desktop/web) | Official OpenCode iOS (TestFlight) | Cursor iOS | Claude iOS | ChatGPT iOS | Best reference | V2 API support | Priority |
|---|---|---|---|---|---|---|---|---|
| **B1** Session inbox across projects: newest first, running and unread state, last-message preview | ✓ (Home grouped Today/Yesterday/Older; unread dots on tabs) | ? | ✓ (agent inbox, cache-first) | ✓ (Code tab rows: state glyph, unread dot, location line, preview) | ✓ (one list across hosts and cloud) | Claude Code tab | `session.list` (cursor paging; `parentID=null` for roots), `session.active`, `Session.Info.time.idle/viewed` and `outcome`; events `session.created`, `session.renamed`, `session.deleted`, `session.execution.*` | P0 |
| **B2** "Needs you" group and triage filters with counts | partial (TUI `!` and `?` markers; tabs show attention) | ? | ✓ ("Needs Attention" state) | ✓ (All, Blocked, In progress, Done chips with counts in App Store images; Anthropic's Aug 2026 docs screenshot shows an "All" dropdown instead) | ✓ (priority view: running, unread, awaiting you) | Claude (chips with counts, as its App Store images show them) | `permission.request.list` and `form.list` per location; events `permission.asked`, `form.created` | P0 |
| **B3** Approve straight from the list row | ✗ (approvals live in the session's permission dock) | ? | ? | ✓ (inline Approve on blocked rows) | ? | Claude | `session.permission.reply` | P1 |
| **B4** Start a session in a chosen project, directory or worktree | ✓ (project picker; location: local, existing or new worktree) | ? | ✓ (repo and branch picker with Recents; Cloud, Team Pool or My Machines) | ✓ (repo selector for cloud; device card, then a directory) | ✓ (computer and project, directory picker, branch, worktree) | ChatGPT (directory picker, worktree defaults per project) | `project.list`, `location.get`, `fs.list`, `session.create {id, location, agent, model}` (always send `location`); `worktree.create` | P0 |
| **B5** Search sessions | ✓ (title search, session-ID lookup; TUI server-side search) | ? | ? (the web app has inline search) | ? (no phone UI for searching history documented) | ✓ (titles and content, across hosts) | ChatGPT | `session.list?search=` matches titles only; content search missing: needs upstream | P1 |
| **B6** Rename, or regenerate the title | ✓ | ? | ✓ | ✓ (rename syncs to the host) | ? | opencode (empty title asks the server for a new one) | `session.update {title}` (`""` regenerates); `session.renamed` | P1 |
| **B7** Delete a session | ✓ | ? | ? | partial (cloud sessions can be deleted; "no way to delete old sessions" for Remote Control, #50496) | ? | opencode (confirm; children are deleted too) | `session.remove`; `session.deleted` | P1 |
| **B8** Archive and unarchive | ✗ (the Archive button fails: V2 has no archive call) | ? | ? (the web app archives; iOS not documented) | ✓ (Archived tab) | ✓ (archived threads browsable) | ChatGPT | missing: needs upstream (no archive operation; `Session.Info.time.archived` comes only from migrated V1 data); archive locally meanwhile | P1 |
| **B9** Pin sessions | ✓ (TUI switcher "Pinned" group) | ? | ✓ (Pinned section; pins sync, up to 75 on the web) | ? | ✓ (pins sync with desktop) | Cursor | client-side; syncing across devices missing: needs upstream or plugin (`session.update {metadata}` replaces the whole metadata object) | P1 |
| **B10** Unread and viewed state shared by every client | ✓ (stored on the server; marked only while focused) | ? | ? | ✓ (unread dot) | ✓ (unread in priority view) | opencode (desk and phone agree because the server holds it) | `session.view {idle}`; `session.viewed`; unread = `time.idle > time.viewed` | P0 |
| **B11** Subagent (child session) cards with drill-in and family cost | ✓ (subagent card, ancestor trail, family cost) | ? | ✓ (subagent cards open the child transcript) | ✓ (subagent progress, stoppable from the phone) | ? | Cursor card plus opencode family cost | tool `metadata.sessionID`; `session.list?parentID=` (limit 200); child events arrive on the same stream; children cannot be prompted | P0 |
| **B12** Fork from a message | ✓ (TUI timeline actions: Jump, Revert, Copy, Fork) | ? | ? | ✓ (fork a Remote Control session from the app) | ✓ (fork tasks) | opencode TUI message actions | `session.fork {before}` (creates a top-level session; only `session.forked` is emitted) | P1 |
| **B13** Move a session to another directory or a new worktree | ✓ (Details → "Move to worktree") | ? | ? | ? | partial (handoff between hosts, started from the desktop app) | opencode Details menu | `worktree.create` + `session.move {directory, delivery}`; `session.moved` | P2 |
| **B14** Export a transcript through the share sheet | ✓ (Markdown or JSON, optional thinking and tool output, sanitize; desktop import) | ? | ? (the web app shares read-only agent URLs) | partial (cloud-session links on the web; sharing a chat with people is not available on mobile) | partial (shared chat links; Codex snapshots only from the macOS app) | opencode `/export` options | `experimental.session.export?sanitize=`, `experimental.session.import`; share links were discontinued on 2026-10-15 | P2 |
| **B15** Cloud-hosted runs that continue with the laptop closed | ✗ (no first-party hosted execution) | ✗ (pairs with a user-run server) | ✓ (cloud VM or Team Pool) | ✓ (cloud sessions, generally available 2026-09-23) | ✓ (Codex Cloud tasks) | — | missing: needs upstream (provider-backed workspaces are not in the V2 HTTP contract) | N/A (opencode has no hosted execution; users run the server on their machine, a VPS or a third-party host) |
| **B16** Scheduled or event-triggered runs (automations, routines) | ✗ | ? | partial (Automations run on mobile but are configured on the web) | partial (Routines exist; creating them on the phone is undocumented) | partial (scheduled tasks on mobile; Codex tasks started from GitHub, Slack or Linear) | Cursor Automations | missing: needs plugin (V2 has no scheduler) | P2 |
| **B17** Coordinator "Projects" (one agent plans and runs worker agents) | ✗ (a primary agent with subagents instead) | ? | ✓ (Projects on iOS since 1.10.0) | ✓ (Claude Code Projects, beta) | ? | — | closest: parent session plus `subagent` tool children (B11) | N/A (vendor-cloud coordinator products; opencode's equivalent is a primary agent with background subagents) |

### C. Transcript and rendering

| Feature | opencode V2 (TUI/desktop/web) | Official OpenCode iOS (TestFlight) | Cursor iOS | Claude iOS | ChatGPT iOS | Best reference | V2 API support | Priority |
|---|---|---|---|---|---|---|---|---|
| **C1** Live streaming of answer text and reasoning | ✓ (paced streaming in 24 ms steps) | ? | ✓ ("Working" and "Thinking" labels) | ✓ | ✓ (answers start while reasoning; faster long threads) | opencode paced streaming | `session.step.started/ended`, `session.text.started/delta/ended`, `session.reasoning.*` (deltas batched every 100 ms and ephemeral; `*.ended` is authoritative) | P0 |
| **C2** Markdown with highlighted code, tables and copy buttons | ✓ (worker-based highlighting, code-block copy) | ? | partial (no copy button for final answers; table text hard to select) | ? | ✓ (inline tables; writing blocks with copy) | opencode web Markdown renderer | client-side (07: block pipeline, tree-sitter) | P0 |
| **C3** Tool rows by type, grouped and collapsible (read, grep, edit, shell, webfetch, websearch, subagent, `execute`, MCP, migrated V1 names) | ✓ (per-tool renderers; "Used N …" groups) | ? | ✓ (collapsed "Worked" sections) | ✓ (tool calls collapse into groups with a one-line label) | ✓ (terminal output, test results and screenshots streamed) | opencode `tool-renderer.tsx` | `session.tool.input.started/ended`, `session.tool.called/progress/success/failed`; `execute` lists nested calls in `metadata.toolCalls` | P0 |
| **C4** Timeline detail presets (Everything … Messages only) | ✓ (5-step slider, Compact by default) | ? | ? (desktop has Compact, Balanced, Detailed) | ✗ (mobile Remote Control replaces assistant text with summaries, no toggle, #97418) | ? | opencode Timeline detail setting | client-side | P1 |
| **C5** Live output of the agent's shell commands | ✓ (64 KiB tail, polled every second) | ? | ? | ? | ✓ (terminal output from the host) | opencode web shell row | `shell.output` (byte cursor) with the tool's `metadata.shellID`; shell output is not in tool events | P0 |
| **C6** Inline diff cards for edit, write and patch | ✓ (per-file diff cards) | ? | ✓ ("Changes" card) | partial (`/diff` opens a native diff sheet; iPhone shows a "Diff +X -Y" badge; layout undocumented) | ✓ | opencode per-file cards | tool `metadata.files` (`FileDiff[]`); `write` has no diff, so render `input.content` | P0 |
| **C7** Status, retry and error cards; automatic-continuation notices | ✓ (retry countdown, execution-failure cards) | ? | ? (users report runs stuck on "Thinking" or "Queued") | partial (calm "Service is busy" state in Projects) | ? | opencode retry and error cards plus Claude's "Service is busy" | `session.retry.scheduled`, `session.step.failed`, `session.execution.failed`; assistant `retry` and `error` fields | P0 |
| **C8** Compaction divider and progress | ✓ | ? | ? | ✓ (compaction progress shown) | ? | opencode | `session.compaction.started/delta/ended/failed` | P1 |
| **C9** Long transcripts: older pages on scroll, jump to latest, scrubber, find in session | ✓ (load older, "Jump to latest", `mod+f`, message navigation) | ? | ✓ (auto-load earlier messages, drag-to-scrub) | partial (fixes for streaming in very long sessions) | ✓ (faster long threads; selection stays stable while loading) | Cursor scrubber plus opencode cursor paging | `session.message.list` (newest first, at most 200 per page, `cursor`) | P0 |
| **C10** Mermaid diagrams and LaTeX | ✓ (Mermaid and KaTeX math in desktop/web; LaTeX and Mermaid plugins in the TUI) | ? | ? | ? | ? | opencode desktop/web Markdown worker (KaTeX; prices such as `$5` stay text) | client-side (07: native LaTeX in v1, Mermaid rendered on tap) | P1 |
| **C11** Images and files in the transcript (inline images, zoom, save, copy) | ✓ (inline images from `read`; pinch zoom) | ? | ✓ (preview cards, screenshots, logs) | ✓ (files Claude makes open in the app; HEIC and AVIF previews) | ✓ (save or copy rendered images) | ChatGPT | `Tool.Content {type:"file", uri, mime}`; `fs.read` | P1 |
| **C12** Links that open in the app: other sessions, files, universal links | ✓ (clickable transcript links; links to sessions; file links open the Files panel) | ? | ✓ (agent links open in the app) | partial (`claude.ai/code/new` opens the app; Code artifacts open in a browser, #78792) | ✓ (Codex task links open directly) | Cursor | client-side; files through `fs.read` | P1 |
| **C13** Select and copy text; copy a whole message | ✓ (`/copy`, copy last answer) | partial (copying a Voice message offers the full prompt) | partial (Copy for oversized files; no copy button for final answers) | ? | ✓ (copy actions; stable selection) | ChatGPT | client-side | P1 |
| **C14** Show voice delegations as "Voice" messages | ✓ (v2.0.30) | ✓ | partial (messages from a voice call carry a waveform label) | ? | ? | opencode `voice-delegation.ts` (mirrors the iOS app's parser) | user message whose text starts with `Voice delegation.` followed by JSON (`instruction`, `voice`, `transcript_delta`) | P1 |
| **C15** Live working timer and one-line status | ✓ (TUI footer: duration, tokens per second; "Working" row) | ? | ✓ (live status line in Project chats) | ? | ✓ (live working time, thinking timer) | ChatGPT | `session.execution.started`, `session.step.*`; timer is client-side | P1 |

### D. Composer and input

| Feature | opencode V2 (TUI/desktop/web) | Official OpenCode iOS (TestFlight) | Cursor iOS | Claude iOS | ChatGPT iOS | Best reference | V2 API support | Priority |
|---|---|---|---|---|---|---|---|---|
| **D1** Composer that stays above the keyboard; newline versus send handled for touch and hardware keyboards | partial (mobile web: keyboard covers the composer, #48748; Enter always sends, #55549) | ? | partial (iPad chat kept readable with the keyboard up, fixed in 1.10.0) | partial (keyboard can cover Send after dictation, #61930) | ✓ (controls stay above the keyboard; keep-keyboard-open option) | ChatGPT | client-side | P0 |
| **D2** Per-session drafts that survive navigation, backgrounding and relaunch | ✓ (desktop drafts in SQLite; TUI drafts per tab) | ? | partial (Drafts section; a draft-loss bug at launch) | ✗ (unsent prompts lost on navigation, #73610, #63975) | ✓ (unsent drafts restored across tasks and hosts) | ChatGPT | client-side | P0 |
| **D3** Attach photos, camera shots and files | ✓ (attach, paste, drag; PNG, JPEG, GIF and WebP images and PDFs reach models that declare image or PDF input; audio and video are dropped) | ? | ✓ (any file type except video) | ✓ (photos go to the model; other files land on the host as `@` references) | ✓ (photos, camera, files; long-press + for recent photos) | ChatGPT picker plus Claude's handling of non-image files | `session.prompt` `files[{uri:"data:…"}]` (20 MiB cap, canonical base64, no http(s) URLs; a model without image or PDF input gets an error note in place of the file); `experimental.fs.write` for uploads to the server | P0 |
| **D4** Screenshot markup with pinned comments and Apple Pencil | ✗ (none found; the desktop's embedded browser can comment on page elements) | ? | ✓ (markup, tap-to-place on iPad, Pencil drawing) | ? | ? | Cursor | client-side; the annotated image is sent as a `data:` attachment | P2 |
| **D5** `@file` fuzzy search, with line ranges | ✓ (TUI ranks by frecency; `@src/a.ts#20-45`) | ? | ? | ✓ (`@` path autocomplete from the host project) | ? | opencode TUI autocomplete | `fs.find`; prompt `files[{uri:"file:///abs/path?start=&end="}]` (a path on the server) | P0 |
| **D6** `@agent`, `@skill` and `@reference` mentions | ✓ | ? | ? | ? | partial (`@` other tasks; installed skills suggested) | opencode TUI | `agent.list`, `skill.list`, `reference.list`; prompt `agents[]`, `skills[]` with mention ranges | P1 |
| **D7** Slash commands: `/init`, `/review`, MCP prompts and custom commands, with descriptions and arguments | ✓ | ? | ✓ (slash commands and skills behave as on desktop) | partial (only text-output and argument forms; pickers replaced by arguments) | partial (`/goal`, `/side`; plugin skills suggested) | opencode command list (descriptions, nested names) | `command.list`; `session.command {name, text, files, delivery}`; `command.updated` | P0 |
| **D8** `!` shell mode | ✓ (TUI and desktop/web) | ? | ✗ (no terminal) | ✗ (`!` is sent to Claude as text) | ✗ (no manual shell, per OpenAI's docs) | opencode TUI | `session.shell {id, command}`; `session.shell.started/ended` (shell prompts cannot be queued) | P1 |
| **D9** Paste handling: images from the pasteboard; long pastes collapsed or turned into attachments | ✓ (TUI `[Image N]`, `[Pasted ~N lines]`) | ? | ? | ? | ✓ (pastes over 10,000 characters become attachments) | opencode TUI plus ChatGPT | client-side; `files[]` as `data:` URIs | P1 |
| **D10** Prompt history; edit and resend the last prompt | ✓ (TUI history and stash; `/undo` puts the prompt back) | ? | ? | partial (edit and retry exist, but not for flagged prompts on mobile) | ✓ (edit the latest sent prompt) | ChatGPT plus opencode undo | `session.revert.stage` (returns the prompt) then `session.prompt`; history is client-side | P1 |
| **D11** Side question that does not enter the transcript (`/btw`, `/side`) | ✓ (`/btw`) | ? | ? (desktop has `/side` and `/btw`) | ? | ✓ (`/side` side chats) | opencode `/btw` | `session.generate {prompt}` | P2 |

### E. Agent control (models, agents, variants, steer and queue, stop)

| Feature | opencode V2 (TUI/desktop/web) | Official OpenCode iOS (TestFlight) | Cursor iOS | Claude iOS | ChatGPT iOS | Best reference | V2 API support | Priority |
|---|---|---|---|---|---|---|---|---|
| **E1** Model picker grouped by provider, with favorites and recents | ✓ (Favorites, Recent; a drawer on phones) | ? | ✓ (any cloud-agent model, plus Auto) | ✓ (model control per session) | ✓ (model per task) | opencode TUI model dialog | `model.list`, `model.default`, `provider.list`; `session.switchModel` before the prompt (prompts carry no model); `session.model.selected`, `model.updated` | P0 |
| **E2** Reasoning-effort (variant) picker that shows the value the server actually uses | ✓ (variants; `ctrl+t`, `shift+mod+d`) | ? | ? (only Router modes documented) | partial (effort control; picker reverts Ultracode, #99489) | ✓ (effort per task; Fast mode saved per task) | ChatGPT (task-scoped) plus Claude's lesson: read the effective value back | `Model.Info.variants[]` → `session.switchModel {model:{providerID, id, variant}}` | P0 |
| **E3** Agent picker (Build, Plan, custom agents with colors; hidden agents excluded) | ✓ (Shift+Tab in the TUI; on desktop the picker and `mod+.` need the "Show agent" setting, which is off by default, unless a custom primary agent is configured) | ? | partial (Plan and Agent modes only; no Ask mode) | partial (Plan through the permission-mode menu) | ? | opencode | `agent.list` (show `mode` other than `subagent`, not `hidden`); `session.switchAgent`; `session.agent.selected` | P0 |
| **E4** Steer a running agent (the message lands at the next step) | ✓ (Enter steers; follow-up default is Steer) | ? | partial (mid-run messages queue; "Send now" interrupts the current step; the desktop's non-interrupting steer is not on iOS) | partial (mid-turn messages queue as grey text and are lost if you leave, #73610) | ✓ (steer or queue, with a configurable default) | ChatGPT | `session.prompt {delivery:"steer"}` | P0 |
| **E5** Queue for the next turn, with a visible queue: steer now, edit, cancel | ✓ (queue panel; TUI dock) | ? | partial (a "Queued" pill above the composer; "Send now" interrupts the current step; editing or cancelling is not documented) | partial (on the web an "x" takes a queued message back; on mobile, pending text is reportedly lost if you leave) | ✓ (compact preview; cancelling restores text and attachments; sends in the background) | ChatGPT | `session.prompt {delivery:"queue"}`; `session.inbox.list/update/cancel`; `session.inbox.enqueued/delivered/cancelled/delivery.changed` | P0 |
| **E6** Stop (interrupt), optionally resuming pending steers | ✓ (Esc twice; a blank submit interrupts; running menu) | ? | ✓ (Stop sends the first queued message) | ✓ (Stop replaces Send while a turn runs) | ? | Claude | `session.interrupt?resume=`; `session.execution.interrupted` | P0 |
| **E7** Send a long blocking tool to the background | ✓ (`ctrl+b`) | ? | ? | ? | ? | opencode | `session.background`; the result arrives later as `session.synthetic` | P2 |
| **E8** Undo, redo and revert to a message, with files restored | ✓ (staged revert; the prompt returns to the composer) | ? | ? | ? | ? | opencode staged revert | `session.revert.stage/clear/commit`; `session.revert.staged/cleared/committed` (409 while running) | P1 |
| **E9** Compact now | ✓ (`/compact`) | ? | ? | ✓ (`/compact` works from the phone) | ? | opencode | `session.compact {id}` (idempotent; merges with a pending request) | P1 |
| **E10** Context, token and cost chip with a details sheet | ✓ (desktop context tokens and family cost; TUI "12,345 (45%) · $0.12") | ? | ? (users ask for usage visibility) | ✓ (context-usage figure; `/usage`, `/context`) | partial (plan usage and credits in the task menu and widgets) | opencode TUI chip | `session.usage.updated`; `Session.Info.cost` and `tokens`; last assistant step against `Model.Info.limit.context`; `session.context` | P1 |
| **E11** Usage and cost history | ✓ (`opencode stats`, `/stats`) | ? | ? | partial (`/usage` as text) | ✓ (usage stats in the profile; usage widgets) | ChatGPT | `experimental.session.stats` | P2 |

### F. Approvals and questions

| Feature | opencode V2 (TUI/desktop/web) | Official OpenCode iOS (TestFlight) | Cursor iOS | Claude iOS | ChatGPT iOS | Best reference | V2 API support | Priority |
|---|---|---|---|---|---|---|---|---|
| **F1** Permission sheet with the full command, path or diff; Allow once, Allow always (pattern shown), Reject with feedback | ✓ (permission dock; TUI shows the diff, full screen on demand) | ? | partial (approval sheets such as agent-initiated merges; local-agent approvals reported landing on the laptop) | partial (commands cut at about 100 characters and diffs truncated, with no way to expand; #37235 and #86704 closed "not planned") | ✓ (Approve, Always approve, "Tell Codex what to do", Deny) | ChatGPT card plus opencode diff preview | `session.permission.list/get/reply {decision, message}`; `permission.asked/replied`; `reject` also rejects every other pending request in the session | P0 |
| **F2** One list of everything waiting on you, including requests from subagents | ✓ (descendant requests surface in the parent) | ? | ✓ ("Needs Attention") | ✓ ("Blocked" filter) | ✓ ("Needs input" status) | opencode request tree plus Claude's "Blocked" filter | `permission.request.list`, `form.list` (per location); map children through `parentID` | P0 |
| **F3** Question sheet: single choice, multiple choice, free text, review step | ✓ (question dock; TUI field tabs and review step) | ? | ✓ (questions in chat and by push) | partial (answers not reaching the CLI, #28508) | ✓ (interactive forms; answer without losing the draft) | opencode form UI plus ChatGPT's draft keeping | `session.form.list/get/reply/cancel`; `form.created/replied/cancelled` (cancelling without a message ends the turn) | P0 |
| **F4** Generic form renderer: MCP elicitation, external-URL steps, provider forms, web-search provider choice, conditional fields | ✓ | ? | partial (MCP sign-in shows "Needs Attention" with Skip or Authenticate) | partial (no MCP connector re-authorization from the phone) | ? | opencode forms (`packages/schema/src/form.ts`) | the same form operations; `sessionID="global"` for MCP elicitations; the web-search choice is a form with `metadata.kind:"websearch.provider"` | P1 |
| **F5** Requests survive reconnects, never time out into "yes", and show "already handled" | ✓ (pending lists rehydrate; a 404 on reply counts as settled) | ? | ? | partial (prompts stay open until answered, but some never render, #35637) | partial (approvals recover after reconnect; "approval waiting" badge with no card, #39346) | 03 §5.3 rules plus ChatGPT's recovery | rehydrate with `session.permission.list` and `form.list` on every `server.connected`; pending requests live in server memory and die on restart or `location.reload` | P0 |
| **F6** Saved "always" rules: list and remove | ? (the API exists; no first-party screen found) | ? | ? | partial (connector tools: Always allow, Needs approval, Blocked) | partial (MCP approvals scoped to this chat or all chats) | Claude connector permissions | `permission.saved.list?projectID=`, `permission.saved.remove` | P1 |
| **F7** Auto-accept or permission mode per project or session, never "bypass everything" from the phone | ✓ (per-project auto-accept, answered by the client; `mod+shift+a`) | ? | ? | ✓ (mode menu mirrors the host; Bypass cannot be chosen from the app) | ? | Claude | client-side auto-reply `once`; `project.update` stores the override; `session.update {permissions}` | P1 |
| **F8** Risk-tiered approvals: Face ID for high-risk actions | ✗ | ? | ? | partial (Trusted Devices: biometric refresh after 18 h) | partial (an optional Face ID or passcode lock for Codex only; not per action) | Remote for OpenCode (risk tiers with Face ID) | client-side, from `Permission.Request.action` and `resources` | P1 |
| **F9** Answer from the notification: Allow once (after unlock), Reject, Reject with a note, text answer | ✗ (no push) | ? | ? | ✗ (no Approve or Deny on lock-screen pushes; the "input needed" push carries no question or options, user report #95391) | ? | Moshi (allow or deny from the banner or the Watch); 03 §5.3 design | the reply uses `session.permission.reply` or `session.form.reply` over the direct path; the notification itself is missing: needs plugin + relay | P1 |

### G. Review (diffs, files, git and PRs)

| Feature | opencode V2 (TUI/desktop/web) | Official OpenCode iOS (TestFlight) | Cursor iOS | Claude iOS | ChatGPT iOS | Best reference | V2 API support | Priority |
|---|---|---|---|---|---|---|---|---|
| **G1** Per-turn "Changes" card, then a file list with +/- counts, then the diff | ✓ ("Changed files" per turn in v2.0.30; review "last turn" mode) | ? | partial (whole-run diff; scoping to the latest step was promised, status unknown) | partial (a "Diff +X -Y" badge; `/diff` opens a native diff sheet; layout undocumented) | ✓ (last-turn filter) | ChatGPT filters plus opencode's per-turn summary | `session.diff {from, to, context}`; `session.step.ended` carries `files`; staged reverts carry `files` | P0 |
| **G2** Working-tree and branch diff (uncommitted, against the inferred base) | ✓ (review modes: working tree, branch, last turn) | ? | partial (run and PR diffs) | partial (branch diff including uncommitted edits) | ✓ (staged, unstaged and branch filters) | ChatGPT | `vcs.get`, `vcs.status`, `vcs.base`, `vcs.diff {mode: working, branch or committed; base}`; `vcs.branch.updated`, `filesystem.changed` | P0 |
| **G3** Diff viewer built for touch: unified on iPhone, split on iPad, wrap, expand and collapse, hunk navigation, large-diff fallback, "mark reviewed" | ✓ (split or unified, collapse, wrap; TUI hunk keys and "mark reviewed") | ? | partial (full-width diffs on iPad; "File too large to preview" fallback) | ? | ✓ (wrap, expand and collapse, large diffs, nested repos) | ChatGPT plus the opencode TUI diff viewer | client-side over `FileDiff.patch`; the `context` parameter limits size | P1 |
| **G4** Line comments on a diff that are sent to the agent | ✓ (review line comments flow into the prompt) | ? | ✗ (not supported; feedback goes in a follow-up message) | partial (on the web comments ride along with the next message; phone undocumented) | ✓ (inline review comments) | Claude web (comments bundled with the next message) | client-side → `session.prompt` (text with file and line, or `files[]` with `?start=&end=`) | P1 |
| **G5** File tree and file viewer (code, images, Markdown, PDF) | ✓ (Files panel with many viewers) | ? | ✗ (no file browser) | ? | ✓ (file browser, recent files, remembered reading positions) | ChatGPT plus opencode's viewers | `fs.list`, `fs.read` (ETag, Range), `fs.find`; `filesystem.changed` | P1 |
| **G6** Small file edits from the phone | partial (`experimental.fs.write` is used for uploads; no editor) | ? | ✗ | ? | ✗ (no file editing, per OpenAI's docs; the file browser only previews files and links paths) | — (06 names a read-write editor as an opening) | `experimental.fs.write?path=` (experimental; not confined to the location) | P2 |
| **G7** Branch and worktree choice when starting work; worktree setup progress | ✓ (location: local, existing or new worktree; "Creating worktree" screen) | ? | ✓ (repo and branch) | partial (no base-branch selector on iPhone in May 2026, #55500) | ✓ (branch, worktree, setup script, starting branch; Live Activity for setup) | ChatGPT | `vcs.branch.list`, `worktree.list/create/remove/refresh`; `worktree.updated`; startup script in `project.update {commands}` | P1 |
| **G8** Agent code review (`/review` of uncommitted changes, a commit, a branch or a PR) | ✓ (`/review` built in) | ? | ? | ? | partial (`/review` appears to run from the phone, inferred from the 1.2026.244 notes; PR review is desktop and web only) | opencode `/review` | `session.command {name:"review", text}` | P1 |
| **G9** One-tap "commit and push" and "open a PR" | ? (no such buttons found; the agent can be asked) | ? | ✓ (agents open PRs, as drafts by default; "View PR Draft") | ✓ (Create PR: full, draft, or GitHub's compose page) | ✓ (commit or open a PR after cloud tasks; from Remote tasks unconfirmed) | Claude Create PR | client-side quick actions → `session.prompt` or `session.command` (the agent runs git and `gh` under normal permissions) | P1 |
| **G10** PR cockpit: checks, reviewers, comments, merge, auto-merge | ✗ (no GitHub integration in V2 clients; PR links can only be read) | ? | ✓ (full PR screen: squash merge, auto-merge, mark ready) | partial (CI auto-fix; "Merge it" sends an instruction) | ✗ (the PR inbox and review submission are desktop and web only) | Cursor PR screen | missing: needs plugin (or a GitHub API integration in the app); opencode itself has no PR API | P2 |

### H. Terminal

| Feature | opencode V2 (TUI/desktop/web) | Official OpenCode iOS (TestFlight) | Cursor iOS | Claude iOS | ChatGPT iOS | Best reference | V2 API support | Priority |
|---|---|---|---|---|---|---|---|---|
| **H1** Interactive terminal (PTY) with resize and resume | ✓ (desktop/web terminal tabs; TUI panes) | ? | ✗ (no terminal) | ✗ (no terminal) | ✗ (terminal output only) | opencode desktop terminal | `pty.create/list/get/update/remove`; `pty.connect` WebSocket (Basic auth or a `pty.connect.token` ticket; cursor in UTF-16 units; resize through `PUT`); `pty.created/updated/exited/deleted` | P1 |
| **H2** Terminal key bar (Esc, Ctrl, Tab, arrows) | ✗ (requested in #50635) | ? | ✗ | ✗ | ✗ | — (open opencode request #50635) | client-side | P1 |
| **H3** "Run a command" sheet with paged output, outside any session | ✓ (shell service; the running menu can stop it) | ? | ✗ | ✗ | ✗ | opencode | `shell.create/list/get/output/remove`; `shell.created/exited/deleted` | P2 |
| **H4** Session terminals that survive server restarts | partial (TUI, experimental) | ? | ✗ | ✗ | ✗ | opencode TUI terminals tab | `server.experimental.persistentPty.*`, `persistentPty.connect` (capability `persistentPty` in `server.info`) | P2 |

### I. Notifications and Live Activities

| Feature | opencode V2 (TUI/desktop/web) | Official OpenCode iOS (TestFlight) | Cursor iOS | Claude iOS | ChatGPT iOS | Best reference | V2 API support | Priority |
|---|---|---|---|---|---|---|---|---|
| **I1** Push when the agent needs you (permission or question) while the app is closed | ✗ (no push in the TUI, desktop or web clients; desktop has no trigger for permission requests, #51507) | ? (push exists through an unpublished notify plugin that testers could not install, #54483; which events it sends is not public) | ✓ (question and approval pushes) | ✓ ("Push when actions required") | partial (Remote pushes missing until a thread was opened once, #32908) | Claude's two push tiers; OpenChamber's sealed payloads | `permission.asked` and `form.created` exist but are ephemeral → missing: needs plugin + relay | P0 |
| **I2** Push when a run finishes or fails | partial (desktop/web "Response ready" and "Session error" only while open and unfocused; TUI opt-in) | ? (push exists, as in I1; its events are not public) | partial (turn-finished pushes removed for Cloud Agents in the week of 2026-08-31) | ✓ ("Push when Claude decides"; "notify me when the tests finish") | ✓ (task completion) | Claude (agent-chosen pushes) | `session.execution.succeeded/failed` → missing: needs plugin + relay; relay-free fallback for "finished" only: background `experimental.session.wait` | P0 |
| **I3** Presence-aware delivery (no ping for the session on screen, or while you are at the desk) | partial (only when no window is focused; TUI only while the terminal is blurred) | ? | ? | ✓ (skipped while typing or focused in the terminal; presence file; a September regression report says hook-approved prompts still push while the user is at the Mac, #96126) | ✓ (fewer duplicate notifications while ChatGPT is open) | Claude | plugin watches `session.viewed`; the app suppresses banners for the visible session | P1 |
| **I4** Notification settings: per category, per-session mute, quiet hours, sounds | ✓ (desktop Agent, Permissions and Errors toggles, 45 sounds; TUI `attention` config) | ? | ? (no per-category notification controls documented) | partial (two host-side toggles in `/config`) | ? (category settings documented for the web) | opencode desktop Notifications page | preferences stored per device by the plugin (through `rpc.call`) → missing: needs plugin | P1 |
| **I5** Push health: test push, last delivery time, "notifications degraded" warning | ✗ | ? | ? | ? | ? | 03 §5.3 (Happy's push outage went unnoticed for two months) | missing: needs plugin (`test` and `listDevices` RPC) + relay delivery results | P1 |
| **I6** Live Activity for running sessions (Lock Screen, Dynamic Island) | ✗ | ? | ✓ (up to eight agents, "+N more") | partial (a "Thinking" island for chat replies; never for Code sessions, #101173) | partial (cloud tasks in 2025 and worktree setup in 2026; none for running Remote tasks, request #34912 open) | Cursor | start locally when the phone sends a prompt; remote updates missing: needs plugin + relay (ActivityKit push tokens) | P1 |
| **I7** Live Activity for runs started at the desk (push-to-start) | ✗ | ? | ? | ✗ | ✗ (no Live Activity for running Remote tasks, #34912) | GitHub Mobile Live Activities for Copilot CLI (03 §3.1) | missing: needs plugin + relay (push-to-start tokens) | P2 |
| **I8** Live Activity buttons (Open, Stop; Approve only with cached request details) | ✗ | ? | ? | partial (stop button on the chat island) | ? | 03 §5.3 (buttons are inactive until the phone is unlocked) | `session.interrupt` and `session.permission.reply` from a Live Activity intent | P2 |
| **I9** App icon badge = number of unresolved requests | ✗ (no dock or app badge) | ? | ? | ? | ? | OpenChamber (badge = distinct pending items) | badge set in each push by the plugin; recomputed in the app from `permission.request.list` and `form.list` | P1 |

### J. Voice

| Feature | opencode V2 (TUI/desktop/web) | Official OpenCode iOS (TestFlight) | Cursor iOS | Claude iOS | ChatGPT iOS | Best reference | V2 API support | Priority |
|---|---|---|---|---|---|---|---|---|
| **J1** Dictation in the composer with a live, editable transcript | ✗ (no voice input found) | ? | ✓ (live caption; words still being recognized shown in grey) | ✓ (dictation in the Code composer) | ✓ | Cursor live caption | client-side (07: `SpeechAnalyzer`); text sent with `session.prompt` | P1 |
| **J2** Code-aware recognition (file names, symbols and branch as hints) | ✗ | ? | ? | partial (the terminal `/voice` uses project and branch hints; not on mobile) | ? | Claude Code CLI dictation | client-side `contextualStrings` fed from `fs.find`, `vcs.get`, `agent.list` | P2 |
| **J3** Hands-free voice conversation that hands tasks to sessions | partial (renders Voice messages only) | ✓ (the app's headline feature; voice launched around 2026-09-17) | partial (voice-call label; staff said in July that spoken replies were not available) | partial (voice mode in chat; the Code tab gets dictation only) | ✓ (GPT-Live starts, checks and steers Codex tasks) | ChatGPT Codex voice plus the official app's voice delegation | the hand-off is a `session.prompt`; the conversational voice model is not part of opencode → missing: needs a voice backend (the official app's backend is unknown) or on-device speech | P1 |
| **J4** Spoken replies (read the answer aloud, skip code blocks) | ✗ | ? | ? (sources conflict) | partial (voice mode in chat; a request to read Remote Control replies aloud was closed "not planned", #88495) | ✓ (GPT-Live) | ChatGPT | client-side text-to-speech of `session.text.ended`, or a short summary from `session.generate` | P2 |

### K. System integration (widgets, App Intents, Shortcuts, Spotlight, Handoff, Control Center, Lock Screen, Watch)

| Feature | opencode V2 (TUI/desktop/web) | Official OpenCode iOS (TestFlight) | Cursor iOS | Claude iOS | ChatGPT iOS | Best reference | V2 API support | Priority |
|---|---|---|---|---|---|---|---|---|
| **K1** Deep links and universal links to a session or a pending request (also used by notification taps) | partial (the web app has session URLs; the desktop's `opencode://` links do not navigate: they only bring the app forward or focus the window after a Console sign-in) | ? | ✓ (agent links open in the app) | partial (`claude.ai/code/new` opens a new session in the app) | ✓ (task links and notifications open the task) | ChatGPT | client-side URL scheme (07: `opencode-ios://server/{id}/session/{id}`) | P0 |
| **K2** Home Screen widgets: sessions needing you, running sessions, recent sessions | ✗ | ? | ✗ (not found) | partial (launcher widget: Chat, Microphone, Camera) | ✓ (recent tasks per computer; remaining usage; configurable launcher) | ChatGPT | App Group cache; push-updated widgets missing: needs plugin + relay (`widgets` push type) | P1 |
| **K3** App Intents for Shortcuts and Siri: send a prompt to a project, session status, open a session, review the pending approval | ✗ | ? | ✗ (not found) | ✓ ("Ask Claude" intent runs without opening the app) | partial (Spotlight and Shortcuts entry points; widget launchers not exposed as actions) | Claude's intent plus 07's intent list | `session.create`, `session.prompt`, `session.list`, `permission.request.list` | P1 |
| **K4** Lock Screen, Control Center and Action button controls (new prompt, voice prompt, review approval) | ✗ | ? | ✗ (not found) | ✓ ("Open Claude", "Analyze Photo with Claude") | ✓ (Remote voice control; usage on the Lock Screen) | Claude's control set plus ChatGPT's Remote voice control | client-side App Intents | P2 |
| **K5** Spotlight search of sessions | ✗ | ? | ✗ (not found) | partial ("Ask Claude" from Spotlight) | partial (Spotlight entry point for Codex) | — | client-side Core Spotlight over cached `Session.Info` | P2 |
| **K6** Share extension: send text, a URL or a screenshot to a session | ✗ | ? | ✗ (not found) | ✓ (Share menu → "Ask Claude") | ? | Claude's Share sheet plus Cursor's screenshot-to-agent flow | `session.prompt` with `data:` attachments | P2 |
| **K7** Handoff between iPhone, iPad and Mac | ✗ | ? | ? | ? | ? | — (07 design: one `NSUserActivity` per session) | client-side | P2 |
| **K8** Apple Watch: notifications with safe actions | ✗ | ? | ✗ (not found) | ✗ (no Watch app; notifications mirror) | ✗ (no Watch app) | Moshi (allow or deny from the Watch) | as I1 plus `session.permission.reply`; Double Tap must land on "Open", never on an approval | P2 |

### L. iPad and Mac

| Feature | opencode V2 (TUI/desktop/web) | Official OpenCode iOS (TestFlight) | Cursor iOS | Claude iOS | ChatGPT iOS | Best reference | V2 API support | Priority |
|---|---|---|---|---|---|---|---|---|
| **L1** iPad multi-column layout (servers and projects → sessions → transcript) with a diff and file inspector | ✓ (desktop side panel beside the chat; phone layout below 768 px) | ? | ✓ (sidebar, review beside the chat, full-width diffs) | partial (one centered column) | ✓ (task list beside the open task in landscape) | Cursor iPad | client-side | P1 |
| **L2** Several windows and Stage Manager; sessions side by side | ✓ (desktop tabs and windows; reopen up to 25 closed tabs) | ? | partial (pinned sidebar chats to watch several agents) | ? | ? | opencode desktop tabs (unread dot, pulse when a prompt is queued) | client-side | P2 |
| **L3** Hardware-keyboard shortcuts, iPadOS menu bar and command palette | ✓ (full keybind set; `mod+k` palette) | ? | ? | ? | ? | opencode desktop keybinds | client-side | P1 |
| **L4** Runs on Apple silicon Macs and on Vision Pro | ✓ (native desktop app) | ? | partial (visionOS listed; no Mac- or visionOS-specific client found) | ✗ (no Mac or Vision entries in the listing) | partial (visionOS through the iPad app; Mac not listed) | ChatGPT | client-side ("Designed for iPad"; no ActivityKit or `BGContinuedProcessingTask` on macOS or visionOS) | P2 |

### M. Settings and server administration (providers, MCP, config)

| Feature | opencode V2 (TUI/desktop/web) | Official OpenCode iOS (TestFlight) | Cursor iOS | Claude iOS | ChatGPT iOS | Best reference | V2 API support | Priority |
|---|---|---|---|---|---|---|---|---|
| **M1** Connect model providers: API key, OAuth with code paste or device code, "finish on your computer" for loopback flows | ✓ (`/connect`; Settings → Providers) | ? | ✗ (models come with the Cursor plan) | ✗ (claude.ai account) | ✗ (ChatGPT account) | opencode `/connect` dialog | `integration.list/get`, `integration.connect.key/external`, `integration.oauth.connect/status/complete/cancel` (mode `auto` or `code`), `integration.command.*`; `integration.updated`. OAuth flows that redirect to the server's loopback cannot finish on the phone | P1 |
| **M2** Several accounts per provider: switch, rename, remove | ✓ (v2.0.29) | ? | ✗ (no provider accounts; team switching only) | ✗ (no provider accounts) | partial (several accounts for plugins) | opencode Settings → Providers | `credential.list/create/update/remove/activate` (`credential.list` returns raw secrets: never cache it); `credential.updated/switched` | P2 |
| **M3** MCP servers: status, connect and disconnect, sign in | ✓ (`/mcps`; settings toggles) | ? | partial (chosen per run; managed on the web) | partial (`/mcp` text summary with reconnect, enable, disable; no re-authorization from the phone; adding claude.ai connectors from the phone is in beta) | ✗ (MCP servers come from the host's configuration, per OpenAI's docs) | opencode `/mcps` dialog | `mcp.list`, `experimental.mcp.connect/disconnect/add/remove` (runtime only, not saved), `mcp.resource.catalog`; MCP OAuth through `integration.oauth.*` always calls back to a listener on the server's 127.0.0.1, so the phone shows the URL, the user finishes in a browser on the server computer, and the app polls `integration.oauth.status`; `mcp.status.changed` | P1 |
| **M4** Browse agents, commands, skills, plugins and references | ✓ | ? | ✗ (no access to skills, rules, plugins or MCPs; users ask for it) | ? | partial (installed plugins usable; browsing and installing on web or desktop) | opencode | `agent.list`, `command.list`, `skill.list`, `plugin.list/check/update`, `reference.list`; matching `*.updated` events | P2 |
| **M5** Project settings: name, icon, color, worktree startup script, auto-accept override | ✓ (desktop Projects page) | ? | ✗ (environments on the web) | ✗ (environments on web or desktop) | partial (worktree defaults per project; environments on web or desktop) | opencode desktop | `project.update {name, icon, commands}`; `project.updated` | P2 |
| **M6** View configuration; change the terminal shell | ✓ (settings dialog; per-server "Terminal shell") | ? | ✗ | partial (`/config key=value`) | ✗ (no `config.toml` changes, per OpenAI's docs) | opencode | `config.get` (raw documents; merge on the client), `config.shells`, `experimental.config.update {shell}` (the only config change V2 exposes) | P2 |
| **M7** Server administration: reload config, restart, update notice, debug info | ✓ (TUI `/reload`, `/restart`, `/update`, `/debug`) | ? | ✗ (admin and billing stay on the web) | partial (`/reload-plugins` from the phone) | ? | opencode TUI | `location.reload`; `installation.update-available`, `installation.updated`; restart and update over HTTP missing: needs upstream | P2 |
| **M8** Worktree management: list, remove after a dirty-tree check, refresh | ✓ (Settings → Worktrees, with preflight and bulk actions) | ? | ? (no source says the phone manages worktrees) | partial (`--spawn worktree` per session) | partial (creates worktrees; removal not documented) | opencode desktop Worktrees page | `worktree.list/remove/refresh` with a `vcs.status` and `vcs.diff` preflight | P2 |
| **M9** App settings: appearance, notifications, follow-up default (steer or queue), timeline detail | ✓ (searchable settings) | ? | partial (help calls the profile sheet "the app's settings"; what the "Customize" sheet controls is undocumented; users miss skills, rules, MCP and appearance controls) | ? | ✓ (default Queue or Steer; open straight into Codex on launch) | opencode settings catalog | client-side | P1 |

### N. Security and privacy

| Feature | opencode V2 (TUI/desktop/web) | Official OpenCode iOS (TestFlight) | Cursor iOS | Claude iOS | ChatGPT iOS | Best reference | V2 API support | Priority |
|---|---|---|---|---|---|---|---|---|
| **N1** Credentials only in the Keychain (shared with extensions); provider secrets never cached | ✓ (desktop injects auth in the main process; the renderer never sees the password) | ? | ? | ? (short-lived, single-purpose credentials; storage on the phone undocumented) | ? | opencode desktop | Basic `opencode:<token>`; avoid `credential.list` (raw secrets) | P0 |
| **N2** Encrypted transport: HTTPS through OpenTunnel or `tailscale serve`; a clear warning for plain-HTTP LAN | partial (LAN is plain HTTP; the web app warns about mixed content) | ✓ (OpenTunnel HTTPS) | ✓ (TLS to the vendor) | ✓ (TLS; the host only dials out) | ✓ (relay with no public exposure; SSH for hosts added on the phone) | OpenTunnel (TLS ends on the user's machine) | the server has no TLS: OpenTunnel or a reverse proxy; ATS exceptions only for the LAN | P0 |
| **N3** Code and transcripts stay on the user's machine (no vendor storage) | ✓ (user-run server; the OpenTunnel relay cannot read traffic, though it sees IP addresses, SNI and timing) | ? | ✗ (cloud data storage required; one-way Privacy Mode switch) | ✗ (transcript stored on Anthropic's servers while connected) | partial (files stay on the host; updates go through OpenAI's relay, except for SSH hosts the phone reaches directly) | opencode plus OpenTunnel | inherent | P0 |
| **N4** App lock with Face ID or passcode | ✗ | ? | ? | partial (Trusted Devices biometric refresh) | ✓ (optional Face ID or passcode lock, scoped to Codex) | ChatGPT | client-side | P1 |
| **N5** Push content hidden from the relay (sealed payload opened on the phone) | ✗ (no push) | ? (how its notify plugin reaches APNs is not public) | ? | ✗ (Anthropic sees everything) | ? | OpenChamber (sealed APNs payloads) | missing: needs plugin (HPKE sealing) + relay; a Notification Service Extension decrypts | P0 |
| **N6** Sign out one device without signing out the others | ✗ (changing the password revokes every token) | ✗ (same server limitation) | ? | ✓ (Trusted Devices, revocable per device) | partial (a revoked device stays listed and cannot be removed or re-paired, #22700, the second most-upvoted iOS issue) | Claude Trusted Devices; OpenChamber per-device tokens | missing: needs upstream (one password-derived HMAC key signs every token) | P2 |
| **N7** Consent before exposing the server, and a visible connection path (LAN, tunnel) | ✓ (the first `pair --remote` asks for consent) | ? | ✓ (pairing request approved on the desktop) | ✓ ("Enable Remote Control?" prompt) | ✓ (connection approved on the host; MFA or SSO if required) | OpenChamber (shows LAN versus relay) | label the active endpoint from `server.info.urls` | P1 |

### O. Offline and performance

| Feature | opencode V2 (TUI/desktop/web) | Official OpenCode iOS (TestFlight) | Cursor iOS | Claude iOS | ChatGPT iOS | Best reference | V2 API support | Priority |
|---|---|---|---|---|---|---|---|---|
| **O1** Cache-first launch: cached sessions and transcripts appear first, then sync | partial (web startup caching; the PWA precaches assets only) | ? | ✓ (cache-first inbox and chats) | ? | partial (cached titles kept on refresh) | Cursor | local store; resync as in 01 §7.8 | P1 |
| **O2** Read-only offline history (cached transcripts and diffs while the server is unreachable) | ✗ | ? | partial (the 2025 PWA showed past runs offline; the iOS app is cache-first) | ? | ✗ (no offline mode) | Cursor | local store | P1 |
| **O3** Outbox: idempotent sends with client IDs that survive suspension and network loss | ✓ (optimistic prompts with client `msg_` IDs) | ? | partial (false error after backgrounding, fixed in 1.12.0) | partial (text kept and Send disabled while the host is unreachable) | ✓ (queued prompts sync to the host and send in the background) | ChatGPT plus opencode's idempotent IDs | `session.prompt {id}` (same ID returns the first admission; different content → 409) | P0 |
| **O4** Fast resume after switching apps | partial (resync when visible again after 20 s of silence) | ? | ✓ (pauses in the background, then catches up) | partial (cloud sessions show missed activity at once) | partial (full reconnect of 10+ s reported, #37997) | Cursor | close the stream in the background; on return reconnect `event.subscribe` and refetch only what is visible | P0 |
| **O5** Smooth long transcripts: virtualized list, incremental Markdown, batched updates | ✓ (virtualized timeline; events flushed every 10–16 ms) | ? | ✓ (chats with large edits stay responsive) | partial (streaming fixes for very long sessions) | partial (faster long threads; scroll jumps reported) | opencode client batching | batched event handling; paged `session.message.list` | P0 |
| **O6** Keep following a phone-started run in the background for a while | ✗ | ? | ? | partial (chat replies continue in a Dynamic Island task; Code sessions do not) | partial (voice continues in the background) | — (07: prototype `BGContinuedProcessingTask` only) | `event.subscribe` while the task runs; finished-only fallback `experimental.session.wait` | P2 |

### X. Accessibility

| Feature | opencode V2 (TUI/desktop/web) | Official OpenCode iOS (TestFlight) | Cursor iOS | Claude iOS | ChatGPT iOS | Best reference | V2 API support | Priority |
|---|---|---|---|---|---|---|---|---|
| **X1** VoiceOver for the transcript, tool rows and approval sheets | ? | ? | ? | ? (no accessibility features declared in the listing) | partial (VoiceOver regressions reported, latest July 2026) | — (no product documents good support) | client-side | P1 |
| **X2** Dynamic Type and large text | partial (desktop zoom; 16 px inputs on touch screens) | ? | ? | ? | ? (one hint: Codex composer controls stay visible "for larger text sizes", 1.2026.188) | — | client-side | P1 |
| **X3** Reduce Motion and haptics settings respected | ? | ? | ✓ (animations fall back to a fade under Reduce Motion) | partial (vibration after every reply despite haptics off, reported) | partial (haptics turn off automatically in Low Power Mode or below 20% battery; where the toggle now sits is undocumented) | Cursor | client-side | P1 |
| **X4** Localization, including right-to-left languages | ✓ (63 locales with RTL) | ? | ✗ (English only) | ✓ (English plus 33 languages) | ✓ (60 languages) | opencode | client-side | P2 |

## 2. Chat-app features outside the matrix

The Claude and ChatGPT apps are general assistants, and Cursor sells hosted agents. Many of their features have no place in a client for a user-run coding agent. Some of the rest are things opencode already does on the server, so the client only has to render them.

### 2.1 Features that do not apply

| Feature (where) | Why it does not apply to an opencode client |
|---|---|
| Image generation and editing, stickers, the Sketch tool (ChatGPT Images 2.5, 06 B.7) | The client has no image pipeline of its own; what a session produces is decided by the model and the agent's tools. See 2.2 for the MCP route. |
| Consumer verticals: shopping and virtual try-on, Finances, the Health tab, flashcards (ChatGPT, 06 B.23); Health, Maps, Reminders, Calendar, Location, Mail and Messages drafting (Claude, 05 §4.10) | Personal-data features. The opencode agent runs on the user's computer and works on code, not on the phone's data. |
| Group chats (ChatGPT; creating or joining new ones ended on 2026-07-09) | Not needed: several opencode clients (TUI, desktop, web, phone) already share one server session. |
| Public share links for chats (all three) | opencode discontinued sharing on 2026-10-15 (02 A.7). Export through the share sheet replaces it (B14). |
| Incognito or temporary chats (Claude, 05 §4.11) | Sessions live on the user's own server; deleting a session or exporting with `sanitize` covers the need. |
| Account memory, chat-history search for the model, styles and personalization (Claude, ChatGPT) | Vendor-account features. opencode keeps context in the project instead (see 2.2). |
| Artifacts gallery, Canvas, Pages and Space, Docs/Slides/Design templates (Claude 05 §4.4, ChatGPT 06 B.10) | Hosted documents tied to a vendor account. An opencode agent writes files into the project, which the file viewer shows (G5). |
| Intelligent UI, interactive apps and inline charts inside answers (ChatGPT 06 B.4, Claude 05 §4.1) | They depend on a vendor-defined UI protocol. opencode has only forms (F4); server-driven UI blocks are listed as an upstream idea in section 4. |
| Custom GPTs, the plugin directory, the Apps SDK (ChatGPT 06 B.12) | Vendor marketplaces. opencode plugins, skills and agents are installed on the server and only browsed from the phone (M4). |
| Video and screen sharing in voice conversations (ChatGPT Advanced Voice, 06 B.5) | opencode sessions take text, images and PDFs, and V2 drops video; the user attaches screenshots instead (D3). |
| ChatGPT as an Apple Intelligence or Siri extension (06 B.16) | A system-level partnership with Apple. Our equivalent entry points are App Intents and Shortcuts (K3). |
| In-app subscriptions, usage credits, ads and free tiers (all three) | opencode is bring-your-own-provider: provider accounts are connected on the server (M1), and OpenCode Console or Go billing stays on the web. The client sells nothing. |
| Vendor-cloud agents: Cursor cloud VMs, Team Pools and Projects; Claude cloud sessions, Cowork, Dispatch and Code Projects; ChatGPT Codex Cloud, Work, the cloud browser, Dots and Pulse | They need vendor-hosted execution, which opencode does not offer (B15, B17). Running `opencode serve` on a VPS or a third-party host gives "laptop closed" work. |
| Audio uploads (ChatGPT, 06 B.6) | V2 drops audio and video from the model request (02 A.2). |

### 2.2 Chat-app features that opencode delivers itself

| Chat-app feature | How opencode delivers it | What the client has to do |
|---|---|---|
| Web search and research (Claude Research, ChatGPT search and deep research) | Built-in `websearch` tool (Exa, Firecrawl, Parallel, Tavily, TinyFish; the first search asks the user to pick a provider) and `webfetch`; hosted search through the OpenCode Console (02 A.26, C.5) | Render search and fetch tool rows (C3) and the provider-choice form (F4). |
| Connectors to Gmail, Calendar, Slack, Notion, Figma and similar | MCP servers configured on the server, with OAuth through integrations; the official Figma plugin (02 A.16, A.24) | Show MCP status and sign-in (M3); render MCP and `execute` tool rows (C3). |
| Image generation | An MCP or plugin tool can return images; tool results carry images as `data:` file content (01 §9.3) | Render image results inline (C11). |
| Memory, custom instructions, project knowledge | `AGENTS.md` discovery, the `instructions` config, references, skills, per-session instruction entries (`experimental.session.instructions.entry.*`) (02 A.8, A.25) | Offer `/init` (D7), `@reference` and `@skill` (D6), and a skills browser (M4). |
| Custom GPTs and styles | Custom agents (`.opencode/agents/*.md` with their own system prompt, model and permissions) and custom commands (02 A.3, A.2) | Agent picker (E3) and command list (D7). |
| File creation and data analysis | The agent's own shell, read and write tools on the real machine | Diff cards and the file viewer (C6, G5). |
| Multi-page scanning to PDF (ChatGPT, 06 B.6) | V2 passes PDFs to models that declare PDF input; for other models an error note replaces the file (02 A.2) | Offer page scanning in the attachment picker (D3), and convert the pages to images when the chosen model lacks PDF input. |
| Side questions (ChatGPT `/side`, Cursor `/btw`) | `session.generate`, answered from the session context without changing history | `/btw` sheet (D11). |
| Chat search | Title search through `session.list?search=`; content search needs upstream work | Session search (B5). |
| Scheduled tasks | Not in V2; a plugin would be needed | Later (B16). |
| Spoken conversation | Not on the server; voice delegations arrive as ordinary prompts | On-device speech and text-to-speech in the client (J1–J4). |

## 3. Differentiators: where our client can beat all of them

Each item names the pain point in the reports, what we would do, and the matrix rows involved. Issue numbers refer to the trackers cited in 02 to 06.

1. **Approvals that reach you, show everything, and stay private.**
   - *Pain.* opencode's own desktop and web apps notify only "Response ready" and "Session error", have no trigger for permission requests (open issue #51507; two fixes were closed unmerged), and send nothing while closed (02 B.9); remote approval from a phone is an open opencode request (#39628). The official iOS beta has push, but through a server plugin that is not published and that testers could not install (#54483). Claude added approval pushes in August 2026, but prompts that never render (#35637, 30 reactions) remain, and its approval prompts show only about 100 characters of a command and truncate diffs, with no way to expand (#37235, #86704, both closed "not planned"). ChatGPT can show "approval waiting" with no card (#39346, 13 reactions) and skips Remote pushes until a thread was opened once (#32908, 18). A Cursor reviewer says approvals go to the laptop. Among relay-based third-party designs, only OpenChamber seals push content: Happy, Happier, Paseo, Remodex, Sesori, Moshi and WhatCode send plaintext previews, while Remote for OpenCode and omnicus send no content at all (03 §3.2).
   - *What we do.* A server plugin plus a content-blind relay, with payloads sealed per device and opened on the phone; "Allow once" behind device unlock and "Reject with a note" from the notification; a full-fidelity sheet; one notification per request, replaced when it is answered elsewhere; silence never counts as consent; a push-health screen.
   - *Rows.* I1, I2, F1, F5, F9, N5, I5.
2. **Reconnects you can trust.**
   - *Pain.* Claude's top issue is Remote Control that never reconnects (#34255, 109 reactions; users kept reporting it into late September, after fixes shipped in late August). ChatGPT's most-upvoted connection complaints are an offline host whose Reconnect button does nothing (#22898, 40 reactions) and a revoked device that cannot be removed or re-paired (#22700, 36); users also report 10 to 30 second resumes (#37997) and silent disconnects (#32242). opencode's web client gets stuck after a network switch (#55673) and on half-open streams (#51857). Cursor users report runs stuck on "Thinking" or "Queued".
   - *What we do.* A byte-level watchdog on the event stream, reconnect on every network-path change, endpoint racing that prefers the LAN, a full resync on every `server.connected`, a visible state ("reconnecting, attempt 3", "offline since 14:02"), an outbox with idempotent message IDs, and a re-pair action on any server whose token is rejected.
   - *Rows.* A6, A11, A12, O3, O4.
3. **No vendor in the loop, on any machine.**
   - *Pain.* Cursor needs a plan with Cloud Agents and a one-way switch to the newer Privacy Mode; its cloud VMs run Ubuntu, which a Mac developer called useless for his work. Claude stores Remote Control transcripts on Anthropic's servers and is unavailable to Zero Data Retention and HIPAA organizations. ChatGPT Remote officially needs its desktop app on a Mac or Windows PC; the ChatGPT desktop app for Linux (in preview) is not a listed host, and a first-class headless Linux host is the most-upvoted iOS issue (#23200, 66 reactions). The phone can add SSH hosts directly, but users report that only PEM-format keys work.
   - *What we do.* Talk straight to the user's server over LAN, Tailscale, OpenTunnel (TLS ends on the user's machine) or SSH, on any machine that runs `opencode serve`, headless Linux included, with no account of ours.
   - *Rows.* A3, A4, A8, N2, N3.
4. **Never lose a prompt, and choose steer or queue every time.**
   - *Pain.* Claude discards unsent prompts on navigation (#73610, #63975), can wipe a long dictation (#61930), and loses mid-turn messages when you leave the screen. Cursor lost a draft at launch and showed a false error after backgrounding (fixed in 1.12.0). Cursor's iOS composer only queues mid-run messages: "Send now" interrupts the current step, and the desktop's steer that waits for the next tool call is not on iOS.
   - *What we do.* Persist drafts per session, keep an outbox, and expose opencode's own inbox: steer or queue per message, a visible queue with "steer now", and cancelling that puts the text back.
   - *Rows.* D2, E4, E5, O3.
5. **Review built for the phone.**
   - *Pain.* Cursor has no line comments that the agent acts on and shows whole-run diffs. Claude's phone diff opens in a "native diff sheet" whose layout is undocumented, and its approval prompts truncate diffs with no way to expand (#86704).
   - *What we do.* A per-turn "Changes" card leading to a file list and a unified diff, working-tree and branch diffs, line comments that go back to the agent, "mark reviewed", and split diffs on iPad.
   - *Rows.* G1, G2, G3, G4, L1.
6. **A real terminal on the phone.**
   - *Pain.* None of the three has one: Cursor has no editor, terminal or file browser; Claude sends `!` lines as text; ChatGPT offers no manual shell. opencode's mobile web terminal has no key bar (#50635).
   - *What we do.* PTY terminals over WebSocket with a key bar, plus `!` shell mode in the composer.
   - *Rows.* H1, H2, D8.
7. **A complete inbox across every server, straight from the source.**
   - *Pain.* ChatGPT lists only projects with recent chats (#36040, about 85 comments), CLI-started chats may not open (#28340), and SSH projects go missing (#23527). Cursor shows a computer's workspaces only while they are open with Remote Control on. Claude users cannot delete old Remote Control sessions (#50496).
   - *What we do.* Treat the opencode server as the source of truth: every session from the TUI, desktop, web or phone, across several servers, with a "needs you" group at the top. The official beta also connects to several servers; how it lists their sessions is unknown (03 §1.3).
   - *Rows.* A5, B1, B2, B7, B10.
8. **System integration nobody has put together.**
   - *Pain.* Claude has no Live Activity for Code sessions (#101173) and no Watch app. Cursor's report found no widgets, Siri or Shortcuts actions, share extension or Watch app. ChatGPT has no Live Activity for running Remote tasks (request #34912), no Watch app, no large widgets, and its widget launchers are not exposed as Shortcuts actions.
   - *What we do.* Live Activities for running sessions, widgets with real status, App Intents for every launcher, a share extension, and Watch notifications whose default action is "Open".
   - *Rows.* I6, K2, K3, K6, K8.
9. **iPad as a first-class layout.**
   - *Pain.* Claude shows one centered column on iPad; weak iPad layouts are a recurring complaint about third-party clients (03 §2.6). Cursor and ChatGPT set the bar with split views.
   - *What we do.* Three columns with a diff and file inspector, several windows, keyboard shortcuts and a menu bar.
   - *Rows.* L1, L2, L3.
10. **Controls that tell the truth, and costs you can see.**
    - *Pain.* Claude users report mode drift (#29214, 85 reactions) and an effort picker that snaps back (#99489). A Cursor reviewer saw a premium model stay selected after switching back to Auto. Cursor and ChatGPT users ask for usage visibility (#25240).
    - *What we do.* Read the active model, variant and agent back from session events, and show a context and cost chip that includes subagents.
    - *Rows.* E1, E2, E3, E10.
11. **A real settings screen and a visible server catalog.**
    - *Pain.* Cursor's help calls the profile sheet "the app's settings", and users say the app lacks notification, appearance and accessibility controls and any view of skills, rules, plugins or MCP servers.
    - *What we do.* Notification categories, appearance, follow-up default and timeline detail, plus read-only browsers for agents, commands, skills and MCP status.
    - *Rows.* I4, M3, M4, M9.
12. **Voice that knows your code.**
    - *Pain.* A Cursor reviewer found voice-to-text unusable for long prompts, and Hacker News users say dictation leaves filler words. Voice is the headline feature of the official OpenCode iOS app, so it is also a parity requirement.
    - *What we do.* On-device recognition with file, symbol and branch hints, an editable transcript before sending, and voice delegations shown as Voice messages.
    - *Rows.* J1, J2, J3, C14.
13. **Accessibility from the start.**
    - *Pain.* Claude's listing declares no accessibility features, ChatGPT has a history of VoiceOver regressions, and Cursor documents only Reduce Motion.
    - *What we do.* VoiceOver, Dynamic Type and Reduce Motion support in every screen, approval sheets included.
    - *Rows.* X1, X2, X3.

**Not differentiators.** OS reach (07's iOS 26.4 target matches Cursor's iOS 26 requirement); hosted runs with the laptop closed (all three competitors have them and opencode does not, B15); a PR cockpit (Cursor leads, G10); conversational voice quality (ChatGPT's GPT-Live leads, J3); speaking opencode's pairing protocol and connecting to several servers (the official beta does both, and OpenLens, OpenCody and alvarolorentedev's Opencode Mobile also accept opencode pair links, 03 §1.3, §2.6).

## 4. Server-side gaps: plugin, push relay or upstream opencode

The V2 API covers almost everything a foreground client needs. The gaps fall into three groups:

- **Our opencode plugin**, running inside the user's server. V2 events such as `permission.asked` and `form.created` are ephemeral and never replayed, so anything that must react while the phone is asleep has to live in the server process. Plugins can subscribe to the event stream (`ctx.event.subscribe()`), read and answer pending permissions (`ctx.permission.*`), and expose RPC methods that any authenticated client calls through `rpc.call` (`POST /api/rpc/{rpcID}/{method}`) (03 §1.4, §5.3).
- **Our push relay**, a small open-source service that holds the APNs key, because APNs only accepts the app developer's credentials (03 §5.1). It sees device tokens, timing and coarse kind, never content. Replies never go through it.
- **Upstream opencode changes**, which we should propose rather than fork.

### 4.1 Needs our plugin and our push relay

| Gap | Rows | What V2 offers today | What to build | Priority |
|---|---|---|---|---|
| Push when input is needed, and when a run finishes or fails | I1, I2 | Ephemeral events `permission.asked`, `form.created`, `session.execution.succeeded/failed` | Plugin listens, waits 5–10 s and cancels if answered, seals a small payload per device (HPKE), posts it to the relay; relay sends a generic alert with the ciphertext; a Notification Service Extension decrypts it | P0 |
| Content-blind push | N5 | — | As above: the relay never sees prompts, commands, paths or titles; padded ciphertext | P0 |
| Retract or replace a notification once it is answered anywhere | F5, F9 | `permission.replied`, `form.replied`, `form.cancelled` (ephemeral) | Plugin sends a replacement with the same collapse ID ("Approved on desktop") | P1 |
| Device registration, notification preferences, presence suppression | I3, I4 | `rpc.call`; `session.viewed` | Plugin RPCs `registerDevice`, `unregisterDevice`, `listDevices`, `test`; skip "finished" pushes for sessions viewed in the last minute or so | P1 |
| Push health | I5 | — | Relay reports per-device delivery results; plugin exposes "last delivered"; the app warns when delivery fails | P1 |
| App icon badge | I9 | `permission.request.list`, `form.list` | Plugin includes the unresolved count in each push | P1 |
| Live Activity updates and widget refresh while the app is asleep | I6, K2 | — | Plugin sends coarse state (phase, step count, needs-input flag) through the relay's Live Activity and widget push endpoints | P1 |
| Live Activities for runs started at the desk | I7 | — | Push-to-start tokens through the relay | P2 |
| Approve while the phone cannot reach the server | F9 | — | Phase 2 in 03 §5.3: the phone signs the decision with a Secure Enclave key and drops it at the relay; the plugin pulls and verifies it | P2 |

### 4.2 Needs a plugin only (no relay)

| Gap | Rows | What V2 offers today | What to build | Priority |
|---|---|---|---|---|
| LAN discovery for V2 servers | A9 | No mDNS in V2 | Plugin advertises a Bonjour service such as `_opencode._tcp` (or upstream adds it) | P2 |
| Scheduled and event-triggered runs | B16 | No scheduler | Plugin that starts prompts on a timer or an event | P2 |
| PR and CI data: checks, reviewers, merge | G10 | Nothing; opencode has no code-host API | Plugin (or a GitHub integration in the app itself) | P2 |
| Pins and other per-user session flags synced across devices | B9 | `session.update {metadata}` replaces the whole metadata object, so clients can overwrite each other | Plugin-owned store, or an upstream field (4.3) | P1 |

### 4.3 Needs upstream opencode changes

| Gap | Rows | What V2 offers today | Proposal | Priority |
|---|---|---|---|---|
| A vendor-neutral push-target contract, so several mobile clients (including the official app) can share one server | I1 | No published push design: the official beta's notifications use a server plugin from a private repository (#54483); Web Push PR #47374 was closed unmerged | Small upstream plugin contract (03 §5.3 "Strategic note") | P1 |
| Archive and unarchive sessions | B8 | No archive operation; the official desktop button fails | Archive operation and event | P1 |
| Transcript content search | B5 | `session.list?search=` matches titles only | Server-side content search | P1 |
| Gap-free catch-up after a reconnect | A11, O4 | `/api/event` has no replay and no `Last-Event-ID`; `session.log?after=&follow=` exists but is experimental | Stabilize per-session durable replay (the full resync works meanwhile) | P1 |
| OAuth flows that redirect to the server's loopback cannot finish on a phone: some provider logins (ChatGPT, DigitalOcean, Poe, Snowflake) and every MCP sign-in | M1, M3 | Provider methods with `mode: "code"` or a device code work; MCP attempts are always `mode: "auto"` with a callback listener on the server's 127.0.0.1, so they have no code to paste | Code-paste or device-code methods for every integration, MCP included; meanwhile, "finish on your computer" | P1 |
| Host sleep and keep-awake state | A13 | Nothing over the API; the desktop has its own "Keep screen active" switch | Report and control keep-awake through the service | P1 |
| Per-device tokens and revocation; token refresh | N6, A12 | One password-derived HMAC key signs every 30-day token; no refresh; changing the password signs out everyone | Per-device tokens with revocation and refresh (OpenChamber shows the model) | P2 |
| Relay-free "finished" alerts | I2 | `experimental.session.wait` (experimental; misses mid-turn permission requests; OpenTunnel resets connections idle for 15 minutes) | Stabilize `wait` | P2 |
| Config changes from a client | M6 | Only `experimental.config.update {shell}` | General config editing (V1's `PATCH /config` has no V2 equivalent) | P2 |
| Restart the service and install updates over HTTP | M7 | Only the TUI's local `/restart` and `/update` | Admin operations behind the existing auth | P2 |
| Audio and video input | D3 | Dropped from the model request; PDFs do reach models that declare PDF input (the V2 docs still say they do not) | Pass audio and video to models that accept them | P2 |
| Session terminals that survive server restarts | H4 | `persistentPty` routes are experimental | Stabilize | P2 |
| Server-driven UI blocks (like Claude Code "mods" or ChatGPT's inline UI) | §2.1 | Forms only; plugin `rpc.*` events are free-form | A small, versioned set of renderable blocks | P2 |
| Hosted execution with the laptop closed | B15 | Workspace drivers exist only in the SDK, outside the HTTP contract | Out of scope for the client | N/A |

**Not gaps, but worth knowing** (01 §7.3, §10): `session.status` and `session.idle` are declared but never emitted, so derive status from `session.execution.*` and `session.active`; `session.tool.input.delta` is never emitted; the OpenAPI document omits the event union and marks every object `additionalProperties: false`, so models should be hand-written and decoded tolerantly. The conversational voice agent (J3) is not a server feature at all: the official app's voice backend is unknown, and our options are on-device speech or a hosted voice service.

## 5. Conflicts and open questions

- **Event names.** 02 lists `session.diff`, `file.edited`, `mcp.tools.changed`, `worktree.ready`, `worktree.failed`, `command.executed` and `session.error`; 01's catalog of the 94 public V2 events does not contain them. This matrix follows 01.
- **Live Activity approval buttons.** 03 §5.3 limits Live Activity buttons to "Open" and "Stop" unless the decrypted request is cached on the device; 07 §5.2 suggests Approve and Deny buttons. Row I8 follows 03 until we decide.
- **Push priority.** I1 and I2 are P0 even though they need the plugin and the relay, because 02 calls approvals "the most important mobile interaction". The official beta also has push (through an unpublished server plugin, #54483), so push is a parity item too. If the relay slips, the fallback is foreground streaming plus the experimental `wait` call for "finished" alerts.
- **Cursor.** Its iOS docs still promise turn-finished pushes that the newer release notes removed for Cloud Agents, so the docs lag the product. The steer-versus-queue question is settled: iOS queues, and "Send now" interrupts (04 §3.1.3, F3). Still unconfirmed: whether voice calls speak back, whether the latest-step diff fix shipped, and whether tool approvals for local agents reach the phone (04 §8, §9.1).
- **Claude.** Partly settled: `/diff` opens a native diff sheet whose layout is undocumented, and a user report says notifications carry no Approve or Deny actions (#95391). Still unconfirmed: whether the iPhone shows a base-branch selector, whether line comments work in the phone diff, and whether the Code tab ships filter chips or the dropdown in Anthropic's docs screenshot (05 §3.2, §7).
- **ChatGPT.** Settled by 06's verification pass: Remote is available on all plans, including Free and Go; the PR inbox and PR review are desktop and web only; running Remote tasks get no Live Activity (#34912). Still open: whether the phone can open a PR from a Remote task, Dynamic Type support, and the current Action button and Lock Screen voice entry points (06 Part E).
- **Official OpenCode iOS app.** It connects to several servers and has push through an unpublished server plugin (#54483). How that plugin delivers pushes, its Live Activities, iPad layout, App Store timing and pricing are unknown, and native Swift is only an inference (03 §1.3, §6). Re-check its TestFlight notes and the opencode changelog before each milestone; any cell marked "?" in that column can change quickly.

## Verification updates (2026-10-15)

Reports 02 to 07 went through a verification pass on 2026-10-15; each now ends with a "Verification pass (2026-10-15)" section, and their corrected passages are edited in place. This file was written before that pass. The table lists every change made to bring it in line, in document order.

- **Priorities.** No priority changed, so the Summary counts (141 rows: 46 P0, 59 P1, 34 P2, 2 N/A) and the per-area table still hold. A script confirmed the counts and the column count of every table after editing.
- **Cell values.** Eight cells changed value: A3 (ChatGPT), A5 (official app), C10 (opencode), E4 and E5 (Cursor), F9 (Claude), G10 and I7 (ChatGPT). Every other change rewrites or adds a note, a sentence or a table row.

| # | Row or section | Old → new | Source report |
|---|---|---|---|
| 1 | Opening paragraph | (no mention of the verification pass) → added a sentence that points to this section | 02 to 07, verification sections |
| 2 | How to read: Official OpenCode iOS column | "The reports know only its pairing and voice features (02 D.1, 03 §1.3), so most cells are "?"." → probably written in native Swift (an inference); the reports know its pairing and voice features, that it connects to several servers, and that its push notifications need an unpublished server plugin that testers could not install (#54483) | 03 §1.1, §1.3 |
| 3 | How to read: Cursor, Claude and ChatGPT columns | (nothing on Cursor's status) → Cursor's docs dropped the app's beta label in September 2026 without a general-availability announcement; only its Remote Control is still called beta | 04 §3.1.1 |
| 4 | Conventions: OS reach | (no cost given for the 26.4 target) → 07 now calls 26.4 defensible but thinly justified: it leaves out about 4–5% of users | 07 §1.3 |
| 5 | Conventions: official app | "its push, Live Activity, iPad and multi-server support are all unknown" → it connects to several servers and has push through an unpublished server plugin (#54483); its Live Activities, iPad layout, App Store timing and pricing are unknown | 03 §1.3 |
| 6 | Summary, finding 2 | "known only for pairing (QR code, pasted link, OpenTunnel) and voice delegation. Nearly every other cell in its column is "?"." → known for pairing, voice delegation, several servers, and push through an unpublished server plugin (#54483); probably native Swift (an inference); most other cells are "?" | 03 §1.1, §1.3 |
| 7 | Summary, finding 3 | "Claude's Code tab is the best triage inbox" and "All three depend on their own clouds and relays." → the inbox claim notes that the filter chips appear in App Store images while Anthropic's docs screenshot shows a dropdown; all three depend on their own clouds and accounts and route desktop hosts through their own relays, and only ChatGPT can also reach an SSH host directly from the phone | 05 §3.2; 06 A.4 |
| 8 | A3, ChatGPT iOS | ✗ (relay only) → partial (SSH hosts only: the iOS app's "Add SSH Host" form takes host, port, user and a password or key; desktop hosts go through the relay) | 06 A.4 |
| 9 | A5, Official OpenCode iOS | ? → ✓ (several servers, per Dax Raad) | 03 §1.3 |
| 10 | A6, ChatGPT iOS | ✗ (relay only) → ✗ (relay for desktop hosts; one address per SSH host) | 06 A.4 |
| 11 | A7, ChatGPT iOS | ✗ (relay only) → ✗ (relay or SSH connections only) | 06 A.4 |
| 12 | A8, ChatGPT iOS | partial (SSH hosts added through the desktop app; direct topology unverified) → partial (SSH hosts through a desktop host, or added in the iOS app, which connects to them directly; users say only PEM-format Ed25519 or ECDSA keys work) | 06 A.4 |
| 13 | A9, ChatGPT iOS | ✗ (relay only) → ✗ (hosts are paired by QR code or added by address) | 06 A.4 |
| 14 | A11, ChatGPT iOS | partial (reconnect progress shown; 10+ s resumes reported, #37997) → adds "an offline host's Reconnect button does nothing, #22898, 40 reactions", the most-upvoted connection complaint | 06 Part D (D1) |
| 15 | B2, Claude iOS | ✓ (All, Blocked, In progress, Done chips) → ✓ (All, Blocked, In progress, Done chips with counts in App Store images; Anthropic's Aug 2026 docs screenshot shows an "All" dropdown instead) | 05 §3.2 |
| 16 | B2, Best reference | Claude (chips with counts) → Claude (chips with counts, as its App Store images show them) | 05 §3.2 |
| 17 | C6, Claude iOS | partial (diff pane; phone layout undocumented) → partial (`/diff` opens a native diff sheet; iPhone shows a "Diff +X -Y" badge; layout undocumented) | 05 §3.2, §3.8 |
| 18 | C10, opencode V2 | partial (Mermaid in desktop/web and TUI; LaTeX in the TUI, GUI unverified) → ✓ (Mermaid and KaTeX math in desktop/web; LaTeX and Mermaid plugins in the TUI) | 02 B.7 |
| 19 | C10, Best reference | opencode TUI plugins → opencode desktop/web Markdown worker (KaTeX; prices such as `$5` stay text) | 02 B.7 |
| 20 | D3, opencode V2 | ✓ (…; PNG, JPEG, GIF and WebP reach the model; PDF, audio and video do not in V2) → ✓ (…; PNG, JPEG, GIF and WebP images and PDFs reach models that declare image or PDF input; audio and video are dropped) | 02 A.2 |
| 21 | D3, V2 API support | (no note on unsupported input) → adds "a model without image or PDF input gets an error note in place of the file" | 02 A.2 |
| 22 | D8, ChatGPT iOS | ✗ (no manual shell, third-party claim) → ✗ (no manual shell, per OpenAI's docs) | 06 A.4 |
| 23 | E3, opencode V2 | ✓ (Shift+Tab in the TUI, `mod+.` on desktop) → ✓ (Shift+Tab in the TUI; on desktop the picker and `mod+.` need the "Show agent" setting, which is off by default, unless a custom primary agent is configured) | 02 B.8 |
| 24 | E3, Cursor iOS | partial (Plan mode at launch) → partial (Plan and Agent modes only; no Ask mode) | 04 §3.1.3 (F2) |
| 25 | E4, Cursor iOS | ✓ (follow-ups wait for the next tool call) → partial (mid-run messages queue; "Send now" interrupts the current step; the desktop's non-interrupting steer is not on iOS) | 04 §3.1.3 (F3), §7.3 |
| 26 | E5, Cursor iOS | ? (the web queue has "Send now"; iOS unverified) → partial (a "Queued" pill above the composer; "Send now" interrupts the current step; editing or cancelling is not documented) | 04 §3.1.3 (F3) |
| 27 | E6, Cursor iOS | ✓ → ✓ (Stop sends the first queued message) | 04 §3.1.3 (F3) |
| 28 | F1, Claude iOS | partial (commands and diffs cut at about 100 characters, #37235) → partial (commands cut at about 100 characters and diffs truncated, with no way to expand; #37235 and #86704 closed "not planned") | 05 §3.8 |
| 29 | F2, Best reference | opencode request tree plus Claude's chips → opencode request tree plus Claude's "Blocked" filter | 05 §3.2 |
| 30 | F8, ChatGPT iOS | partial (app-wide Face ID lock) → partial (an optional Face ID or passcode lock for Codex only; not per action) | 06 A.4, B.16 |
| 31 | F9, Claude iOS | ? (no evidence of lock-screen actions) → ✗ (no Approve or Deny on lock-screen pushes; the "input needed" push carries no question or options, user report #95391) | 05 §3.7 |
| 32 | G1, Claude iOS | partial (diff pane; phone layout undocumented) → partial (a "Diff +X -Y" badge; `/diff` opens a native diff sheet; layout undocumented) | 05 §3.8 |
| 33 | G6, ChatGPT iOS | ✗ (no direct file editing, third-party claim) → ✗ (no file editing, per OpenAI's docs; the file browser only previews files and links paths) | 06 A.4 |
| 34 | G8, ChatGPT iOS | partial (reviews run from mobile, inferred from the 1.2026.244 notes) → partial (`/review` appears to run from the phone, inferred from the 1.2026.244 notes; PR review is desktop and web only) | 06 A.7 |
| 35 | G9, Cursor iOS | ✓ (agents open PRs; "View PR Draft") → ✓ (agents open PRs, as drafts by default; "View PR Draft") | 04 §3.1.3 (F4), §7.5 |
| 36 | G9, ChatGPT iOS | ✓ (commit or open a PR after cloud tasks) → adds "from Remote tasks unconfirmed" | 06 A.7 |
| 37 | G10, ChatGPT iOS | partial (PR inbox on the phone unverified) → ✗ (the PR inbox and review submission are desktop and web only) | 06 A.7 |
| 38 | I1, opencode V2 | ✗ (no push in any first-party client; desktop has no trigger for permission requests) → ✗ (no push in the TUI, desktop or web clients; desktop has no trigger for permission requests, #51507) | 02 B.9; 03 §1.1 |
| 39 | I1, Official OpenCode iOS | ? → ? (push exists through an unpublished notify plugin that testers could not install, #54483; which events it sends is not public) | 03 §1.1 |
| 40 | I2, Official OpenCode iOS | ? → ? (push exists, as in I1; its events are not public) | 03 §1.1 |
| 41 | I3, Claude iOS | ✓ (skipped while typing or focused in the terminal; presence file) → adds "a September regression report says hook-approved prompts still push while the user is at the Mac, #96126" | 05 §5.6 and verification S5 |
| 42 | I4, Cursor iOS | ? (users report no settings menu) → ? (no per-category notification controls documented) | 04 §3.1.3 (F7) |
| 43 | I6, ChatGPT iOS | partial (cloud tasks in 2025; worktree setup in 2026) → partial (cloud tasks in 2025 and worktree setup in 2026; none for running Remote tasks, request #34912 open) | 06 A.8 |
| 44 | I7, ChatGPT iOS | ? → ✗ (no Live Activity for running Remote tasks, #34912) | 06 A.8 |
| 45 | J4, Claude iOS | partial (voice mode in chat) → adds "a request to read Remote Control replies aloud was closed "not planned", #88495" | 05 §4.1 |
| 46 | K1, opencode V2 | partial (desktop registers `opencode://`; its consumer is unverified) → partial (the web app has session URLs; the desktop's `opencode://` links do not navigate: they only bring the app forward or focus the window after a Console sign-in) | 02 B.12; 07 §5.5 |
| 47 | L4, V2 API support | "no ActivityKit on macOS or visionOS" → "no ActivityKit or `BGContinuedProcessingTask` on macOS or visionOS" | 07 §5.8 |
| 48 | M3, Claude iOS | partial (`/mcp` text summary with reconnect, enable, disable; no re-authorization from the phone) → adds "adding claude.ai connectors from the phone is in beta" | 05 §4.9 |
| 49 | M3, ChatGPT iOS | ✗ (configured on web or desktop, third-party claim) → ✗ (MCP servers come from the host's configuration, per OpenAI's docs) | 06 A.4 |
| 50 | M3, V2 API support | "MCP OAuth through `integration.oauth.*`" → MCP OAuth through `integration.oauth.*` always calls back to a listener on the server's 127.0.0.1, so the phone shows the URL, the user finishes in a browser on the server computer, and the app polls `integration.oauth.status` | 02 A.16 |
| 51 | M6, ChatGPT iOS | ✗ (no `config.toml` changes, third-party claim) → ✗ (no `config.toml` changes, per OpenAI's docs) | 06 A.4 |
| 52 | M9, Cursor iOS | partial (profile and "Customize" sheets; users report no settings menu) → partial (help calls the profile sheet "the app's settings"; what the "Customize" sheet controls is undocumented; users miss skills, rules, MCP and appearance controls) | 04 §3.1.3 (F1), §10.5 |
| 53 | N2, ChatGPT iOS | ✓ (relay; no public exposure) → ✓ (relay with no public exposure; SSH for hosts added on the phone) | 06 A.4 |
| 54 | N3, opencode V2 | ✓ (user-run server; the OpenTunnel relay cannot read traffic) → adds "though it sees IP addresses, SNI and timing" | 03 §1.4 |
| 55 | N3, ChatGPT iOS | partial (files stay on the host; updates go through the relay) → partial (files stay on the host; updates go through OpenAI's relay, except for SSH hosts the phone reaches directly) | 06 A.4 |
| 56 | N4, ChatGPT iOS | ✓ (optional lock) → ✓ (optional Face ID or passcode lock, scoped to Codex) | 06 A.4, B.16 |
| 57 | N5, Official OpenCode iOS | ? → ? (how its notify plugin reaches APNs is not public) | 03 §1.1, §6 |
| 58 | N6, ChatGPT iOS | partial (a revoked device stays listed, #22700) → partial (a revoked device stays listed and cannot be removed or re-paired, #22700, the second most-upvoted iOS issue) | 06 Part D (D2) |
| 59 | X2, ChatGPT iOS | ? (Dynamic Type unverified) → ? (one hint: Codex composer controls stay visible "for larger text sizes", 1.2026.188) | 06 B.18 |
| 60 | X3, ChatGPT iOS | partial (haptics toggle; current behavior unverified) → partial (haptics turn off automatically in Low Power Mode or below 20% battery; where the toggle now sits is undocumented) | 06 B.21 |
| 61 | 2.1, Group chats | "new ones reportedly ended on 2026-07-09, unverified" → "creating or joining new ones ended on 2026-07-09" | 06 B.14 |
| 62 | 2.1, Video and screen sharing | "opencode sessions take text and images" → "opencode sessions take text, images and PDFs, and V2 drops video" | 02 A.2 |
| 63 | 2.1, Multi-page scanning and audio uploads | "V2 does not pass PDF, audio or video to the model (02 A.2). 02 suggests converting PDFs to images on the phone before sending." → the row now covers audio uploads only: "V2 drops audio and video from the model request (02 A.2)." | 02 A.2 |
| 64 | 2.2, new row | (none) → "Multi-page scanning to PDF": V2 passes PDFs to models that declare PDF input; the client offers page scanning and converts pages to images for models without PDF input | 02 A.2; 06 B.6 |
| 65 | 3, differentiator 1, Pain | "have no trigger for permission requests", "commands cut at about 100 characters (#37235) remain" and "Every relay-based third-party push design except OpenChamber sends plaintext previews" → adds the open issue #51507; adds that the official beta's push depends on an unpublished plugin testers could not install (#54483); Claude's prompts truncate commands and diffs with no way to expand (#37235, #86704, both closed "not planned"); reaction counts for #39346 (13) and #32908 (18); only OpenChamber seals push content, WhatCode joins the plaintext list, and Remote for OpenCode and omnicus send no content | 02 B.9; 03 §1.1, §3.2; 05 §3.8; 06 Part D |
| 66 | 3, differentiator 2, Pain, What we do and Rows | "ChatGPT users report 10 to 30 second resumes (#37997) and silent disconnects (#32242, #23948)." → ChatGPT's most-upvoted connection complaints are an offline host whose Reconnect button does nothing (#22898, 40 reactions) and a revoked device that cannot be removed or re-paired (#22700, 36); #37997 and #32242 stay; #23948 is dropped (its reporter closed it as a likely duplicate of #23294). Claude's #34255 now notes that reports continued after the late-August fixes. What we do adds a re-pair action; Rows add A12 | 05 verification S6; 06 Part D (D1, D2) |
| 67 | 3, differentiator 3, Pain | "ChatGPT Remote needs the desktop app, and headless Linux is its most-reacted iOS request (#23200)." → ChatGPT Remote officially needs its desktop app on a Mac or Windows PC; the Linux desktop app (preview) is not a listed host; a first-class headless Linux host is the most-upvoted iOS issue (#23200, 66 reactions); the phone can add SSH hosts directly, but users report that only PEM-format keys work | 06 A.4, Part D (D3) |
| 68 | 3, differentiator 4, Pain | "Whether Cursor's iOS composer offers steer versus queue is unverified." → "Cursor's iOS composer only queues mid-run messages: "Send now" interrupts the current step, and the desktop's steer that waits for the next tool call is not on iOS." | 04 §3.1.3 (F3) |
| 69 | 3, differentiator 5, Pain | "Claude's phone diff layout is undocumented and its approval diffs are truncated." → "Claude's phone diff opens in a "native diff sheet" whose layout is undocumented, and its approval prompts truncate diffs with no way to expand (#86704)." | 05 §3.8 |
| 70 | 3, differentiator 7, What we do | (no mention of the official app) → adds "The official beta also connects to several servers; how it lists their sessions is unknown (03 §1.3)." | 03 §1.3 |
| 71 | 3, differentiator 8, Pain | "ChatGPT has no Watch app, …" → "ChatGPT has no Live Activity for running Remote tasks (request #34912), no Watch app, …" | 06 A.8 |
| 72 | 3, differentiator 11, Pain | "Cursor users say the app has no settings menu and no access to skills, rules, plugins or MCP servers." → "Cursor's help calls the profile sheet "the app's settings", and users say the app lacks notification, appearance and accessibility controls and any view of skills, rules, plugins or MCP servers." | 04 §3.1.3 (F1), §9.1, §10.5 |
| 73 | 3, Not differentiators | four items → a fifth item: speaking opencode's pairing protocol and connecting to several servers (the official beta does both, and OpenLens, OpenCody and alvarolorentedev's Opencode Mobile also accept opencode pair links) | 03 §1.3, §2.6 |
| 74 | 4.3, push-target contract | "No published push design; Web Push PR #47374 was closed unmerged" → "No published push design: the official beta's notifications use a server plugin from a private repository (#54483); Web Push PR #47374 was closed unmerged" | 03 §1.1, §5.3 |
| 75 | 4.3, loopback OAuth | gap "OAuth flows that redirect to the server's loopback (ChatGPT, DigitalOcean, Poe, Snowflake) cannot finish on a phone", today "`mode: "code"` and device-code methods work" → gap now covers "some provider logins (ChatGPT, DigitalOcean, Poe, Snowflake) and every MCP sign-in"; today: provider methods with `mode: "code"` or a device code work, but MCP attempts are always `mode: "auto"` with a callback listener on the server's 127.0.0.1, so they have no code to paste; the proposal adds "MCP included" (priority unchanged, P1) | 02 A.16, A.17 |
| 76 | 4.3, media input | "PDF and audio input / Not passed to the model in V2 / Pass them through (the client converts PDFs to images meanwhile)" → "Audio and video input / Dropped from the model request; PDFs do reach models that declare PDF input (the V2 docs still say they do not) / Pass audio and video to models that accept them" (priority unchanged, P2) | 02 A.2 |
| 77 | 5, Push priority | (justification cites only 02) → adds "The official beta also has push (through an unpublished server plugin, #54483), so push is a parity item too." (I1 and I2 stay P0) | 03 §1.1 |
| 78 | 5, Cursor | "Its docs still promise turn-finished pushes that its release notes removed for Cloud Agents; whether its iOS composer offers steer versus queue and whether voice calls speak back are unverified (04 §8)." → the docs lag the newer release notes; steer versus queue is settled (iOS queues, and "Send now" interrupts); still unconfirmed: spoken replies in voice calls, the latest-step diff fix, and tool approvals for local agents on the phone | 04 §3.1.3 (F3), §8, §9.1 |
| 79 | 5, Claude | "Whether the iPhone shows a base-branch selector, how the phone diff looks, and whether notifications carry Approve or Deny actions are unverified (05 §7)." → partly settled (native diff sheet with an undocumented layout; no Approve or Deny on notifications, user report #95391); still unconfirmed: the base-branch selector, line comments in the phone diff, and chips versus dropdown on the Code tab | 05 §3.2, §7 |
| 80 | 5, ChatGPT | "Remote's plan availability, whether the phone can open the PR inbox, and whether ordinary Remote tasks get Live Activities are unverified (06 Part E)." → settled: Remote is on all plans, including Free and Go; the PR inbox and PR review are desktop and web only; running Remote tasks get no Live Activity (#34912); still open: opening a PR from a Remote task, Dynamic Type, and the Action button and Lock Screen voice entry points | 06 A.7, A.8, A.10, Part E |
| 81 | 5, Official OpenCode iOS app | "Push, Live Activities, multiple servers, iPad layout and App Store timing are all unknown (03 §1.3)." → it connects to several servers and has push through an unpublished server plugin (#54483); how that plugin delivers pushes, its Live Activities, iPad layout, App Store timing and pricing are unknown, and native Swift is only an inference | 03 §1.3, §6 |
