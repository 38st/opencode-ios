# opencode features and official clients: inventory for a native iOS/iPadOS client

Research date: 2026-10-15.

## How to read this document

- **Sources.** The main source is a shallow clone of the opencode default branch at commit `d0732ea` (2026-10-15). That branch is **opencode V2, version 2.0.29** in its package files, but its code is the v2.0.30 release plus one docs commit: the `release: v2.0.30` commit has the same parent and only bumps versions, per `gh api repos/anomalyco/opencode/commits/f16ef9a` (corrected 2026-10-15). Code citations look like `packages/app/src/servers/connect/pairing.ts:26` and are relative to the repository root. Documentation citations point to the V2 docs (`services/www/src/docs/content/...`, published at opencode.ai/v2/docs) or the V1 docs (`packages/web/src/content/docs/...`, published at opencode.ai/docs). Web sources are cited by URL.
- **Two product lines.** The opencode release installed on this Mac is **v1.18.23** (V1 line). The repository default branch is V2. Both lines use the `opencode` command, but they have **different server APIs, plugin APIs and terminal-client config files** (`services/www/src/docs/content/migrate-v1.mdx:5-15`). Every feature below is marked V1, V2 or both.
- **Markers.** A verification pass on 2026-10-15 resolved every claim that the first pass had tagged as unverified; its log is the last section of this document. "(corrected 2026-10-15)" marks a claim rewritten in that pass. "[unconfirmed: ...]" means real effort found no public evidence and says what was tried. "[not re-checked]" marks a web-research finding that was not fetched again. Nothing here is invented: if a feature is not found it is listed as absent.
- **API names.** V2 endpoints are named by their OpenAPI `operationId` from `packages/protocol/openapi.json` (for example `session.prompt` is `POST /api/session/{sessionID}/prompt`). V1 endpoints are named by method and path from `packages/web/src/content/docs/server.mdx` and `sdk.mdx`. Another researcher documents the wire protocol and the state-sync algorithm in depth; this document only names the operation or event that backs each feature.

## Key takeaways for the iOS team

1. **Target the V2 API first, decide on V1 deliberately.** All new client-facing work in 2026 (pairing, OpenTunnel remote access, PWA install, iOS voice messages) is V2-only. V2 was tagged v2.0.0 on 2026-09-11 and V1 v1.19.0 (2026-10-11) added `opencode upgrade --major` to move users to V2. But V1 is still maintained (v1.19.1 shipped today) and is what this Mac runs, so supporting V1 means a second protocol adapter (section 1).
2. **opencode already has an official iOS app in TestFlight.** The "OpenCode iOS app" is voice-first: a voice agent delegates spoken requests into sessions as `Voice delegation.` prompts, which desktop/web render as **Voice** messages (section D). Parity means at least rendering those messages; a stronger product would match or beat the voice flow.
3. **Pairing is the connection model to implement.** Scan the `opencode pair` QR code (JSON `{"code","urls"}`) or paste an `/auth/connect/<code>` link. Redeem the one-time code for a 30-day token and send it as the Basic-auth password. Use OpenTunnel URLs for access from anywhere. Tokens cannot be revoked per device; changing the server password signs out everything (D.2).
4. **There is no hosted backend to lean on.** No cloud agents, no hosted sandboxes, no push notifications, no share links (discontinued 2026-10-15). The phone always talks to a user-run server, and the V2 event stream is "volatile" (missed while disconnected), so the app must resync on every foreground (C.1, D.1).
5. **Core parity checklist (V2):**
   - Sessions: list/search, create, rename, delete, fork, child sessions, move, interrupt, unread state.
   - Composer: steer vs queue, `@file`/`@agent`/`@skill`/reference attachments, images, `!` shell, slash commands including server commands (`/init`, `/review`, MCP prompts, custom commands).
   - Agents and models: agent switching and model + variant pickers.
   - Approvals: the permission sheet (once / always / reject with feedback) and question/elicitation forms.
   - Recovery: staged undo/redo/revert and compaction.
   - Inspection: per-turn diffs and VCS review, file tree and viewer, PTY terminals.
   - Setup and status: MCP management, provider connect (device-code/paste-code flows), worktrees, and the token/cost/context chip.
6. **Skip or de-prioritize:**
   - Share links (gone).
   - LSP diagnostics and the todo list (V1-only).
   - Desktop-only extensions: browser control, SSH hosts, WSL, Office previews, updater.
   - ACP and IDE integrations.
7. **Mind OAuth on the server's loopback.** Some provider OAuth flows, and every MCP OAuth flow, redirect to the server's loopback address, so a phone cannot finish them alone. Prefer device-code or paste-code methods where a provider offers them (MCP sign-in has none) and say clearly when the user must finish on the computer (A.16, A.17).
8. **Where the official clients are weak (room to beat them):**
   - Desktop/web notify only on "Response ready" and "Session error"; no trigger for permission requests was found, and nothing works when the app is closed (B.9).
   - Open mobile-web issues: keyboard covering the composer, no terminal key bar, remote approval of permissions, stuck sessions after network switches (D.4).
   - No reconnect banner for HTTP servers in the GUI (B.3).
   - The SSE timings, timeline grouping presets and phone layout choices in section B are good defaults to copy.

## 1. V1 and V2 at a glance

| Topic | V1 (1.x, installed v1.18.23) | V2 (2.0.x, repo default branch) | Why it matters for iOS |
| --- | --- | --- | --- |
| Install | npm `opencode-ai` (dist-tag `latest` = 1.19.1), Homebrew `anomalyco/tap/opencode` (this Mac: `/opt/homebrew/Cellar/opencode/1.18.23`), `curl -fsSL https://opencode.ai/install` (installs the latest GitHub release, which is V1, per web research) | npm `@opencode/cli` (`latest` = 2.0.30; 2.0.0 published 2026-09-11; checked against registry.npmjs.org), `curl -fsSL https://opencode.ai/v2/install`, `brew install anomalyco/tap/opencode-v2`, AUR `opencode-beta`, mise, WinGet `Anomaly.OpenCode` (`services/www/src/docs/content/index.mdx:14-22`; v2.0.28 changelog). A pre-release `@opencode-ai/cli` beta ran from 2026-06-04 to 2026-09-07 (npm registry). | A user's Mac can run either line. The app must detect which API it is talking to (for example by probing V2 `GET /api/info`). |
| Server model | Every TUI launch starts its own server on a random port; `opencode serve` for headless, default port 4096 (`packages/web/src/content/docs/server.mdx`) | One shared **background service** per user account owns sessions, config, integrations and tool execution; default port 49374 on macOS/Linux, 45278 on Windows (`services/www/src/docs/content/cli/index.mdx`, `services/www/src/docs/content/cli/web.mdx:35-49`) | V2 gives the phone one stable endpoint per computer. |
| HTTP API | Unprefixed routes (`/session`, `/event`, `/tui/*`), OpenAPI at `/doc` (`packages/web/src/content/docs/server.mdx`) | Rewritten API under `/api/*` with 139 operations, client package `@opencode/client` (`V2_HTTP_API_AUDIT.md:4`, `migrate-v1.mdx:564`) | Two different protocol adapters, or a V2-only app. |
| Auth | Optional HTTP Basic via `OPENCODE_SERVER_PASSWORD`, user `opencode` (`server.mdx`) | Password protected by default; Basic auth with the password **or** a 30-day session token from pairing; `?auth_token=` for WebSockets; same-origin cookie for the web app (`packages/server/src/auth.ts:16-55`, `packages/server/src/middleware/authorization.ts:12-71`) | Pairing tokens are the natural credential for a phone. |
| Remote access | `--hostname 0.0.0.0`, `--mdns` (advertises `opencode.local`), `--cors` flags; password via `OPENCODE_SERVER_PASSWORD` (`opencode --help` on v1.18.23; `packages/web/src/content/docs/web.mdx`). V2 has no mDNS code (no `mdns`/Bonjour match in `packages/`). | `opencode pair` (QR code and one-time link), `opencode pair --remote` through **OpenTunnel** (`services/www/src/docs/content/cli/web.mdx:9-75`) | V2 has a first-party phone pairing flow. |
| Terminal client config | Layered `tui.json(c)` | One global `~/.config/opencode/cli.json` (`migrate-v1.mdx:515-526`) | Not relevant to the phone, but explains different keybind/theme config. |
| Permissions config | `permission` map per tool (`bash`, `edit`, ...) | Ordered `permissions` rule array, actions renamed (`bash`→`shell`, `task`→`subagent`) (`migrate-v1.mdx` "Permissions and tools") | Rule editor UI differs. |
| LSP | Built-in LSP servers feed diagnostics to the agent (`packages/web/src/content/docs/lsp.mdx`) | Not run at all: "does not run language servers, expose LSP tools, or produce LSP diagnostics" (`migrate-v1.mdx:413-414`) | No diagnostics panel needed for V2. |
| Todo list | `todowrite` tool and todo display | `todowrite` removed (`packages/core/src/database/v1-migration.bun.ts:901`) | Todo UI is V1-only. |
| Share links | Had `/share`, `/unshare`, `session.share` / `session.unshare` (`packages/web/src/content/docs/sdk.mdx:308-309`), but **discontinued in v1.19.1 on 2026-10-15** (release notes) | No share endpoint in the V2 API (no share route in `packages/protocol/openapi.json`); the `share` config key is still accepted (`packages/schema/src/config.ts:42-43`) | Do not build sharing. |
| `CLAUDE.md` fallback | Yes (`packages/web/src/content/docs/rules.mdx:77-103`) | No, `AGENTS.md` only (`services/www/src/docs/content/instructions.mdx:41-43`) | Affects `/init` messaging only. |
| Plugins | V1 plugin API | New plugin API; "V1 plugin implementations do not run in V2" (`migrate-v1.mdx:553`) | Plugin-provided UI differs between lines. |

The V2 docs site is the canonical description of current behavior ("OpenCode v2 is now available" banner on the V1 docs: `packages/web/src/components/V2Banner.astro:1-5`). The opencode.ai homepage, download page and docs now show only V2 install commands, while GitHub's "Latest" release badge still points at V1 because V2 versions are git tags without GitHub Release objects (web research, https://opencode.ai/download, https://github.com/anomalyco/opencode/releases). Anomaly's announcement note says "In 2.0 this server now automatically runs as a single background process on your machine" and "We have native apps in the works that take advantage of this flow" (https://anoma.ly/notes/opencode-2-0, fetched 2026-10-15). The release history is in A.28.

---

## A. Feature inventory checklist

Each table row gives the feature, how it works for the user, the API operation or event behind it, and notes for a mobile client. "V2 API" names come from `packages/protocol/openapi.json`; event names come from the V2 schema package (`packages/schema/src/*.ts`, `type: "..."` literals). The complete slash-command and keybind catalog is in Appendix 1.

### A.1 Sessions

| Feature | How it works | API / events | Mobile notes |
| --- | --- | --- | --- |
| Create | New session in a project directory ("Location"). Titles are generated by the hidden `title` agent (`services/www/src/docs/content/agents.mdx:156`). | V2 `session.create`; event `session.created`. V1 `POST /session` with `{ parentID?, title? }`. | Creating a session needs a directory on the server, so the app needs a project picker first. |
| List and search | Ordered, paginated list; filter by project, directory, subpath or parent; text search. | V2 `session.list` with `limit`, `order`, `search`, `parentID`, `directory`, `project`, `subpath`, `cursor`. `session.active` lists sessions currently running in this server process. V1 `GET /session`, `GET /session/status`. | Use cursor pagination; show running badges from `session.active` plus live status events. |
| Rename | Edit the title. The agent can also rename with the Code Mode utility `session_rename` (`services/www/src/docs/content/tools.mdx:222-236`). | V2 `session.update` `{ title, metadata, permissions }`; event `session.renamed`. V1 `PATCH /session/:id`. | Inline rename in list and header. |
| Delete | Removes the session and its data. CLI: `opencode session delete`. | V2 `session.remove`; event `session.deleted`. V1 `DELETE /session/:id`. | Confirm before delete. |
| Archive | The V2 app shows an **Archive** button, but archiving currently fails with "Session archiving is unavailable" because the V2 API has no archive call (`packages/app/src/home/sessions/controller.tsx:361-370`). Session info still carries `archived` from migrated V1 data (`packages/core/src/session/info.ts:61`). | None in V2. V1 has it: sessions carry `time_archived` (`packages/core/src/database/v1-migration.bun.ts:165`), and V1 release notes mention archived sessions in the desktop app ("Register the archive session command in both desktop layouts", v1.18.21; "Archived sessions disappear from the Home list immediately", v1.18.24; `gh release view` on `anomalyco/opencode`). | Hide or disable archive for V2 servers. Projects (not sessions) are auto-archived when their directories disappear (v2.0.27, `CHANGELOG.md`). |
| Fork | Copy history before a chosen message into a new child session. CLI `--fork` with `--continue`/`--session` on V1 (`opencode --help`). | V2 `session.fork` `{ before }`; event `session.forked`. V1 `POST /session/:id/fork` `{ messageID? }`. | Long-press a message → "Fork from here". |
| Child sessions (subagents) | The `subagent` tool starts a child session; foreground calls wait, `background: true` returns immediately and notifies the parent; the returned `sessionID` continues that child (`tools.mdx:189-203`). Commands with `subagent: true` also run in background children (`services/www/src/docs/content/commands.mdx:210-234`). V1 TUI navigates children with `session_child_first` (Leader+Down), `session_child_cycle` (Right/Left) and `session_parent` (Up) (`packages/web/src/content/docs/agents.mdx:131-138`). | V2 `session.list?parentID=`; usage totals across the "session family" (v2.0.29, `CHANGELOG.md`, PR #53785). V1 `GET /session/:id/children`. | Render a subagent card in the parent timeline that drills into the child; include child cost in totals. |
| Move session | Move a session to another directory (for example into a new worktree) at a safe boundary. | V2 `session.move` `{ directory, delivery }`; event `session.moved`; Code Mode `session_move` (`tools.mdx:229-230`). | Useful after creating a worktree from the phone. |
| Interrupt | Stop the running turn; optionally resume steered input. | V2 `session.interrupt` `{ resume }`; events `session.execution.interrupted`. V1 `POST /session/:id/abort`. | Big stop button while running. |
| Background a blocking tool | Move a long-running foreground tool (for example a shell command) into the background so the turn can continue. | V2 `session.background`. | Offer "Send to background" on long shell cards. |
| Unread/viewed state | Sessions finishing while you are away are unread; viewing marks them read. Desktop moved unread dots into session tabs (v2.0.29, PR #53570). | V2 `session.view` `{ idle }`; event `session.viewed`; `session.idle`. | Drives badges and push-style notifications. |
| Status and errors | Running/idle/retrying status; execution failures before or between model steps now appear in the timeline (v2.0.27, PR #53826); automatic continuation when a response hits the output-token limit (v2.0.29, PR #53876). | V2 events `session.status`, `session.execution.started/succeeded/failed/interrupted`, `session.retry.scheduled`, `session.error`, `session.step.*`. | Show retry countdowns and failure cards. |
| Export / import | V2 TUI `/export` offers Markdown or JSON with options to include thinking and tool output and to sanitize, then copies or writes a temp file (`packages/tui/src/routes/session/index.tsx:1207-1250`); `/copy` copies the transcript. V2 CLI `opencode session export [--sanitize]\|import`; V1 `opencode export [sessionID]`, `opencode import <file or URL>` (`opencode --help`); import from share URLs no longer works (v1.19.1). | V2 `experimental.session.export`, `experimental.session.import` (experimental). | Export via the iOS share sheet; import from Files. |
| Statistics | `opencode stats` shows token usage and cost statistics. | V2 `experimental.session.stats`. | Optional usage screen. |
| Durable log | Per-session durable event log with follow mode. | V2 `session.log` (experimental) `{ after, follow }`. | Useful for reconnect/catch-up (see the protocol report). |

### A.2 Prompt composer

| Feature | How it works | API / events | Mobile notes |
| --- | --- | --- | --- |
| Send a prompt | Text plus attachments, agent mentions and skill mentions. A prompt sent while the agent is busy is either **steered** into the current turn or **queued** for the next one. | V2 `session.prompt` `{ id, text, files, agents, skills, metadata, delivery: "steer" \| "queue", resume }`. Pending items: `session.inbox.list`, `session.inbox.update` (change delivery; "Steering wakes session execution"), `session.inbox.cancel`; events `session.inbox.enqueued/delivered/cancelled/delivery.changed`. V1 `POST /session/:id/prompt_async` or `/message`. | The phone needs a visible queue of pending prompts with "steer now" and "cancel". In the TUI, Enter steers while the agent works and Ctrl+X then Enter queues (`services/www/src/docs/content/cli/tui.mdx:17`); queued prompts sit in a dock (Appendix 1, A1.4). The desktop/web app has a "Follow-up behavior" setting (Steer by default, or Queue), an alternate-delivery submit, and a queue panel; a blank submit while the agent works interrupts it (B.5, B.8). The desktop shows steered messages as pending immediately (v2.0.29, PR #55251). |
| `@file` mentions | Fuzzy file search inserts a file attachment. Attachments are `file://` URIs; text files accept `?start=&end=` line ranges (`services/www/src/docs/content/attachments.mdx:23-42`). | V2 `fs.find` for search; attachment goes in `files[]`. V1 `GET /find/file?query=`. | Typeahead sheet after typing `@`. |
| `@agent` mentions | Mention a subagent to delegate (`@general ...`) (`README.md` Agents section; V1 `agents.mdx:124-129`). | V2 `agents[]` (`Prompt.AgentAttachment`); agent list from `agent.list`. | Same `@` typeahead, separate section for agents. |
| `@skill` mentions | "To load a skill yourself, mention it in your prompt as `@skill-id`" (`services/www/src/docs/content/skills.mdx:198`). | V2 `skills[]` in `session.prompt`; also `experimental.session.skill`; event `session.skill.activated`; list from `skill.list`. | Add skills to the typeahead. |
| `@reference` attachments | Named outside directories or Git repos from config; "Clients attach a reference by its root alias" (`services/www/src/docs/content/references.mdx:232-241`). | V2 `reference.list`; event `reference.updated`. | Offer references in the typeahead; hidden ones are excluded (`references.mdx:229`). |
| Images, files, PDFs | Desktop/web: **Attach file**, paste, or drag (`attachments.mdx:5-21`). V2 sends UTF-8 text, directories (non-recursive listing), PNG/JPEG/GIF/WebP images **and PDFs** to the model; SVG is text; **AVIF, BMP, audio, video and other binaries are dropped from the model request** (`packages/core/src/session/runner/to-llm-message.ts:17,75-84`; test "uses materialized image and PDF data as provider media", `packages/core/test/session-runner-message.test.ts:502-530`; PDF forwarding since PR #43799, 2026-08-21). The media type is detected from the bytes (`packages/core/src/session/prompt.ts:113`, `packages/core/src/mime.ts:3-16`). When the model does not declare PDF or image input, an error note telling the model to inform the user replaces the file (`packages/core/src/session/model-request.ts:122-147,297`). The V2 docs still say PDFs are not included (`attachments.mdx:66-68`, last changed 2026-09-11); the code disagrees (corrected 2026-10-15). Per-item limit 20 MiB; desktop picker total 20 MiB (`attachments.mdx:149-158`). Images are resized to 2000×2000 and ~5 MiB base64 by default (`attachments.mdx:76-117`). | `files[]` entries with `data:` URIs for inline content (`attachments.mdx:44-51`); HTTP(S) URLs are not accepted. Desktop now renders inline attachments before the server echo arrives (v2.0.29, PR #54650). | Camera, Photos and Files pickers map to `data:` URIs. Warn when the model lacks image input (`attachments.mdx:17-21`). Send PDFs as they are to models with PDF input and convert them to images only for other models; audio and video cannot reach the model (corrected 2026-10-15). |
| Paste | TUI: ctrl+v pastes images as `[Image N]` attachments; pastes of 3+ lines or 150+ characters collapse to `[Pasted ~N lines]` (Appendix 1, A1.4). Desktop/web: paste or drag files into the prompt (`attachments.mdx:7-8`). | Client-side; content goes into `text` or `files[]`. | Support images from the iOS pasteboard and collapse long pastes. |
| `!` shell | Run a shell command in the session's directory; output is attached to the conversation. | V2 `session.shell` `{ id, command }` emits `session.shell.started` / `session.shell.ended`. V1 `POST /session/:id/shell`. | A "Run command" mode toggle in the composer. |
| Slash commands | Built-in client commands plus server commands. Server-side built-ins in V2 are `/init` ("guided AGENTS.md setup") and `/review` ("review changes [commit\|branch\|pr], defaults to uncommitted") (`packages/core/src/plugin/command.ts:28-55`). MCP prompts become commands named `server:prompt` (`packages/core/src/plugin/command.ts:107-109`). | V2 `command.list`, `session.command`; events `command.executed`, `command.updated`. V1 `GET /command`, `POST /session/:id/command`. | Client-only commands (theme, sidebar, etc.) must be reimplemented as native UI. See Appendix 1 for every built-in. |
| Custom commands | Markdown in `.opencode/commands/` or `~/.config/opencode/commands/`, or JSON under `commands`; fields `template`, `description`, `agent`, `model` (`provider/model#variant`), `subagent` (`commands.mdx:5-93`). Nested paths become `/team/review`. Reloaded automatically on save (`commands.mdx:243-260`). | Listed by `command.list`; run with `session.command`. | Show `description` in the picker. |
| Command arguments | `$ARGUMENTS` = whole string; `$1`, `$2`… positional with quote grouping, last placeholder swallows the rest; if no placeholder, arguments are appended after a blank line (`commands.mdx:97-139`). Shell blocks ``!`cmd` `` run at expansion time, outside permission checks (`commands.mdx:141-165`). Templates do not expand `@path`; composer attachments are preserved (`commands.mdx:167-176`). | Expansion happens on the server. | The phone only sends the command name, argument string and attachments. |
| Prompt history and drafts | Per-client features (TUI history and stash; desktop drafts stored in its own database, `packages/desktop/src/main/storage/migration/20260906234153_drafts`). | Client-side. | Keep drafts per session locally. |

### A.3 Agents

| Feature | How it works | API / events | Mobile notes |
| --- | --- | --- | --- |
| Built-in primary agents | V2: **Build** (default, tools allowed; `.env` reads and outside-workspace access ask) and **Plan** (no edits to normal project files except plan files; shell permission-controlled) (`services/www/src/docs/content/agents.mdx:131-141`, `permissions.mdx:213-223`). V1: build and plan (plan asks for edits and bash) (`packages/web/src/content/docs/agents.mdx:43-69`). | V2 `agent.list`, `agent.get`; event `agent.updated`. | Agent chip in the composer. |
| Built-in subagents | V2: **General** (broad tools, cannot launch subagents) and **Explore** (read/search/web only); "V2 has no built-in `scout` agent" (`agents.mdx:139-156`). V1: general, explore, scout (`packages/web/src/content/docs/agents.mdx:71-93`). | Same. | Show which subagent ran in the subagent card. |
| Hidden agents | `compaction`, `title`, `summary` (both lines). | — | Never show in pickers. |
| Switching | The V2 TUI cycles primary agents with **Shift+Tab** (`packages/tui/src/config/keybind.ts:174`); V1 uses **Tab** (`packages/web/src/content/docs/agents.mdx:24-27`). `/agents` opens a picker; commands can switch agent (`commands.mdx:178-191`). Selecting an agent does not change the session's model (`agents.mdx:221-222`). | V2 `session.switchAgent` `{ agent }`; event `session.agent.selected`. | Segmented control or menu; respect `hidden` and `color` (`agents.mdx:290-306`). |
| Custom agents | Markdown in `.opencode/agents/<name>.md` (nested path → `team/reviewer`) or JSON `agents`; fields `description`, `mode` (`primary`/`subagent`/`all`), `model` with `#variant`, `system`, `permissions`, `steps`, `hidden`, `color`, `disabled`, `request` (`agents.mdx:5-342`). V1 adds `opencode agent` CLI to create agents (`opencode --help`). | `agent.list`. | Read-only list on the phone is enough; editing config remotely is possible via `experimental.config.update` (global config only). |

### A.4 Models, providers and reasoning variants

| Feature | How it works | API / events | Mobile notes |
| --- | --- | --- | --- |
| Model picker | `/models` lists models from models.dev, provider integrations and config; only enabled models with available providers (`services/www/src/docs/content/models.mdx:5-28`). Selection applies to the session, not the config. | V2 `model.list`, `model.default`, `provider.list`, `provider.get`; `session.switchModel`; events `session.model.selected`, `model.updated`, `provider.updated`. V1 `GET /config/providers`, `GET /provider`. | Group by provider; show free models. |
| Variants (reasoning effort) | `provider/model#variant` (for example `#high`); variant names come from the model catalog; config can add or replace variants with their own `settings`, `headers`, `body` (`models.mdx:60-106`). | `session.switchModel` takes `{ model: Model.Ref }` where `Model.Ref` is `{ id, providerID, variant? }` (`packages/protocol/openapi.json`). The TUI cycles variants with ctrl+t and `/variants` (Appendix 1). | A second picker or a stepper for effort. The desktop clarifies timeline notices that apply only to a variant (v2.0.29, PR #54880). |
| Defaults | `model` in config; `default_agent`; agent- and command-level models win (`models.mdx:40-58`, `commands.mdx:193-198`). | `config.get`. | — |
| Free and hosted models | OpenCode's own provider lists free models for limited periods, e.g. "Step 5 Preview Free" (v2.0.26, `CHANGELOG.md`). Zen and Go are covered in section C. | `model.list`. | Badge "free". |

### A.5 Undo, redo and revert (snapshots)

| Feature | How it works | API / events | Mobile notes |
| --- | --- | --- | --- |
| Undo | `/undo` (Leader+u) **stages** a rollback of the last exchange, restores the affected files and puts the removed prompt back into the composer; submitting commits it (`services/www/src/docs/content/snapshots.mdx:8-34`). | V2 `session.revert.stage` `{ messageID, files }`; event `session.revert.staged`. V1 `POST /session/:id/revert` `{ messageID, partID? }`. | "Undo last turn" restores the prompt text into the composer. |
| Redo | `/redo` (Leader+r) cancels the staged rollback before you submit. | V2 `session.revert.clear`; event `session.revert.cleared`. V1 `POST /session/:id/unrevert`. | — |
| Revert to a message | Select an earlier message and choose **Revert** (`snapshots.mdx:34`). | `session.revert.stage` then `session.revert.commit`; event `session.revert.committed`. | Message context menu. |
| Scope and safety | Snapshots need Git; they cover tracked and non-ignored untracked files up to 2 MiB in the active directory; shell side effects are not reversed; rollback is rejected while the session runs (`snapshots.mdx:50-127`). | — | Show the restore summary; disable while running. |

### A.6 Compaction

| Feature | How it works | API / events | Mobile notes |
| --- | --- | --- | --- |
| Automatic | Near the context limit, older history is replaced by a structured summary while ~15,000 recent tokens are kept; `compaction.auto`, `keep.tokens`, `buffer` (`services/www/src/docs/content/compaction.mdx:8-87`). | Events `session.compaction.started`, `session.compaction.delta`, `session.compaction.ended`, `session.compaction.failed`, `session.compacted`. | Render a compaction divider in the timeline. |
| Manual | `/compact` in the TUI (Appendix 1); API request is idempotent with an `id` and merges with a pending one (`compaction.mdx:40-64`). | V2 `session.compact`. V1 `POST /session/:id/summarize`. | Menu action "Compact conversation". |
| Provider-native compaction | OpenAI Responses models can use encrypted native checkpoints (`compaction.mdx:89-127`). | — | No UI difference. |

### A.7 Share links

| Feature | How it works | API / events | Mobile notes |
| --- | --- | --- | --- |
| Share / unshare (V1, until 2026-10-15) | `/share` created a public link and `/unshare` removed it; config `share: manual \| auto \| disabled`. Details of the old share service are in section C. | V1 SDK `session.share`, `session.unshare` (`packages/web/src/content/docs/sdk.mdx:308-309`). | — |
| **Discontinued** | V1 v1.19.1 (published 2026-10-15): "Session sharing has been discontinued. Existing share links and session-sharing commands are no longer available, and importing sessions from share URLs is unsupported" (`gh release view v1.19.1 -R anomalyco/opencode`). V2 v2.0.30 (2026-10-15) "Remove[d] the retired session-sharing backend and unavailable `/share` command" (PR #55716, `CHANGELOG.md` on the `dev` branch). In the analyzed commit there is no share operation in the V2 API, the TUI keeps only deprecated `session.share` / `session.unshare` keybind names marked "session sharing was removed" (`packages/tui/src/config/keybind.ts:125-127`), and the config schema still accepts `share` (`packages/schema/src/config.ts:42-43`) and legacy `autoshare` is normalized (`packages/core/src/config/normalize.ts:79-99`). | — | Do not build share links. Use "Export" (A.1) through the iOS share sheet instead. Users on v1.18.x and older still have the command, but the service behind it is gone. Old clients fail softly: the `opncd.ai` stub answers `POST /api/share` with a placeholder link and accepts sync and delete calls without storing anything, so `/share` appears to succeed but the link opens the HTTP 410 page, and `opencode import <share URL>` stops with "Failed to fetch share data" (`packages/function/src/share.ts:161-171`, PR #55716; V1 client at tag v1.18.23: `packages/opencode/src/share/share-next.ts:206-221`, `packages/opencode/src/cli/cmd/import.ts:144-149`). V1 clients signed in to a Console organization post to that Console's `/api/shares` instead, which is not in this repo. |

### A.8 `/init`, `AGENTS.md`, instructions and references

| Feature | How it works | API / events | Mobile notes |
| --- | --- | --- | --- |
| `/init` | V1: scans the repo, may ask targeted questions, creates or improves `AGENTS.md` (`packages/web/src/content/docs/rules.mdx:8-27`). V2: built-in server command "guided AGENTS.md setup" (`packages/core/src/plugin/command.ts:28-38`). | `session.command` with `init`. V1 also `POST /session/:id/init`. | One-tap "Set up AGENTS.md" for new projects. |
| `/review` (V2) | Built-in command reviewing uncommitted changes, a commit, a branch or a PR (`packages/core/src/plugin/command.ts:40-52`). | `session.command` with `review`. | Good quick action on mobile. |
| `AGENTS.md` discovery | Global file plus every `AGENTS.md` from the workspace up to home (or project root); nested files load as the agent reads those areas; edits are picked up before the next request (`services/www/src/docs/content/instructions.mdx:17-99`). V1 also falls back to `CLAUDE.md` (`rules.mdx:77-103`). | Event `session.instructions.updated`; experimental per-session instruction entries `experimental.session.instructions.entry.list/put/remove`. | "Clients can see which sources changed, but not their contents" (`instructions.mdx:99`). |
| Extra instructions | `instructions` array of files, globs or URLs (`instructions.mdx:101-128`). | `config.get`. | — |
| References | Named local directories or Git repos cached under the data dir and refreshed every 24 h (`references.mdx`). | `reference.list`. | Attach via typeahead. |

### A.9 Permissions UX

| Feature | How it works | API / events | Mobile notes |
| --- | --- | --- | --- |
| Rules | V2: ordered `{ action, resource, effect }` rules, last match wins, default `ask` when nothing matches; actions `read`, `edit`, `glob`, `grep`, `shell`, `subagent`, `skill`, `question`, `webfetch`, `websearch`, `external_directory`, `<server>_<tool>` for MCP, MCP resource actions, `execute` (`services/www/src/docs/content/permissions.mdx:31-138`). Built-in base policy allows everything except outside-workspace access and `.env` reads, which ask (`permissions.mdx:199-228`). V1: per-tool map such as `"bash": { "git push *": "ask" }` (`migrate-v1.mdx`). | `config.get`; per-session overrides via `session.update { permissions }`; event `session.permissions`. | Mostly read-only on the phone. |
| Approval prompt | Replies: **Allow once** (`once`), **Allow always** (`always`, saves the tool's proposed pattern for the project, e.g. `shell: git status *`), **Reject** (`reject`, also rejects all other pending requests in that session, optional feedback text) (`permissions.mdx:258-281`). | V2 `session.permission.list`, `session.permission.get`, `session.permission.reply`; global pending list `permission.request.list`; events `permission.asked`, `permission.replied`. V1 `POST /session/:id/permissions/:permissionID` `{ response, remember? }`. | This is the most important mobile interaction: an actionable notification plus a sheet showing tool, command/path and diff preview, with three buttons and a feedback field. |
| Saved approvals | Durable, project-scoped allow rules that never override a configured `deny` (`permissions.mdx:275-278`). | `permission.saved.list` (filter by project), `permission.saved.remove`. | A "Saved approvals" settings screen with swipe-to-delete. |
| Auto-accept | Desktop: per-project **Settings → Projects → Auto-accept permissions**, toggled in a session with `mod+shift+a` (v2.0.28, PR #54839). TUI: `--auto` or `session.permissions: "autoaccept"` in `cli.json`. V1 CLI: `--auto` auto-approves anything not explicitly denied (`opencode --help`). | **Client-side in both official clients:** the client answers each request with `once` (TUI: `packages/tui/src/context/permission.tsx:13-15`, `routes/session/index.tsx:261-277`; desktop/web: `packages/app/src/session/requests/auto-approve.ts:15-169`). The per-project override is stored with `project.update`. | A per-project "auto-accept" switch with a clear warning. |
| Policies | Admin hard-deny rules evaluated after permissions; never grant (`permissions.mdx:283-295`; `services/www/src/docs/content/policies.mdx`). | — | Show "blocked by policy" errors clearly. |

### A.10 Question tool and forms

| Feature | How it works | API / events | Mobile notes |
| --- | --- | --- | --- |
| Question tool | The agent pauses and asks one or more questions; each has a short header, prompt and choices; `multiple` allows several choices; a free-form answer is always available; dismissing cancels (`services/www/src/docs/content/tools.mdx:159-172`). V1 also lets the user navigate between several questions before submitting (`packages/web/src/content/docs/tools.mdx:270-292`). The desktop "question composer" was refreshed in v2.0.29 (PR #54822). | V2 forms: `session.form.list`, `session.form.get`, `session.form.reply`, `session.form.cancel`, global `form.list`; events `form.created`, `form.replied`, `form.cancelled`. Forms are generic: field types string, number, integer, boolean, multiselect and external URL, with conditional `when` rules (`packages/schema/src/form.ts:21-120`); the question tool maps each question to a string or multiselect field with a custom answer (`packages/core/src/tool/plugin/question.ts:12-133`). | Render as a native sheet (radio/checkbox lists, "type your own answer", review step); build a generic form renderer because the same form system also serves MCP elicitation and provider sign-in forms. Must be answerable from a notification. |
| MCP elicitation | MCP servers can request input mid-call; shown as a form or as a link to open (`services/www/src/docs/content/mcp-servers.mdx:443-451`). | Same form operations. | Same sheet; open URLs in Safari. |

### A.11 Todo display

| Feature | How it works | API / events | Mobile notes |
| --- | --- | --- | --- |
| Todo list | V1 has the `todowrite` tool; the TUI shows the list (Appendix 1) and the V1 desktop/web app shows a collapsible **todo dock** above the composer ("Remember whether the todo dock is collapsed", v1.14.49; "Keep todo docks in place when switching between sessions", v1.17.11; todo tools were briefly omitted and then restored for OpenAI models in v1.1.26/v1.1.30; release notes via `gh release view`). V2 removed the tool: migrated sessions are told "The `todowrite` tool is no longer available and must not be called" (`packages/core/test/v1-migration.test.ts:508`, `packages/core/src/database/v1-migration.bun.ts:901`); v2.0.28 removed a stale `todowrite` label from TUI output (`CHANGELOG.md`). | V1 only: `GET /session/:sessionID/todo` (operation `session.todo`, "Get session todos"; tag v1.19.1, `packages/opencode/src/server/routes/instance/httpapi/groups/session.ts:83,156-165`). | Build todo UI only if V1 support is a goal; render old `todowrite` tool parts in history gracefully. |

### A.12 Diffs and review

| Feature | How it works | API / events | Mobile notes |
| --- | --- | --- | --- |
| Per-turn diffs | Structured per-file diffs of what a turn changed, computed from snapshots; `to` extends the range; a running step compares against the working copy. | V2 `session.diff` `{ from, to, context }`; event `session.diff`. V1 `GET /session/:id/diff?messageID=`. | A "Changes" tab per turn with unified diff view. |
| Working tree review | Git status, branches, diff against an inferred review base (`vcs.base` infers the base from branch history). | V2 `vcs.get`, `vcs.status`, `vcs.branch.list`, `vcs.base`, `vcs.diff`, `vcs.init`; events `vcs.branch.updated`, `file.edited`, `filesystem.changed`. V1 `GET /vcs`, `GET /file/status`. | The desktop review panel (section B) supports line comments sent back to the agent. |

### A.13 Files

| Feature | How it works | API / events | Mobile notes |
| --- | --- | --- | --- |
| File tree | Directory listing. | V2 `fs.list`. V1 `GET /file?path=`. | Lazy tree with search. |
| File viewer | Read text and media files. | V2 `fs.read` (`GET /api/fs/read/*`). V1 `GET /file/content?path=`. | Syntax-highlighted viewer; image/SVG zoom (desktop added pinch zoom in v2.0.29, PR #54590). |
| Find | Fuzzy file name search and content search. | V2 `fs.find`. V1 `GET /find/file`, `GET /find`, `GET /find/symbol`. | — |
| Write | Write a file (experimental). | V2 `experimental.fs.write`. | Optional quick edits. |

### A.14 Terminal tabs and shell

| Feature | How it works | API / events | Mobile notes |
| --- | --- | --- | --- |
| Interactive terminals (PTY) | Desktop/web terminal tabs backed by server PTYs, connected over WebSocket with a short-lived connect token. | V2 `pty.list`, `pty.create` `{ command, args, cwd, title, env }`, `pty.get`, `pty.update` ("Update the title or viewport size"), `pty.remove`, `pty.connect.token`, `pty.connect`; events `pty.created`, `pty.updated`, `pty.exited`, `pty.deleted`. | Needs a terminal emulator view (e.g. SwiftTerm) and a keyboard accessory bar. |
| Persistent terminals | Experimental session-scoped terminals hosted by a separate PTY daemon with server handoff (`packages/core/src/persistent-pty/index.ts`, `daemon.ts`), plus snapshot and a "Read the session's most recently controlled terminal" call. | V2 `server.experimental.persistentPty.*`, `persistentPty.connect`. | Experimental; follow later. |
| One-shot shell commands | Non-interactive command with captured, pageable output. | V2 `shell.create`, `shell.list`, `shell.get`, `shell.output`, `shell.remove`; events `shell.created`, `shell.exited`, `shell.deleted`. | Simple "run command" sheet without a full terminal. |
| Session environment | Replace the environment variables used by a session's local shell commands. | V2 `session.environment` `{ variables }`. | Advanced settings. |

### A.15 LSP diagnostics

| Feature | How it works | API / events | Mobile notes |
| --- | --- | --- | --- |
| V1 LSP | ~30 built-in language servers (TypeScript, gopls, pyright, rust, clangd, ...) auto-detected or auto-installed; diagnostics are fed back to the agent; an experimental `lsp` tool offers go-to-definition, references, hover, symbols and call hierarchy (`packages/web/src/content/docs/lsp.mdx`, `packages/web/src/content/docs/tools.mdx:154-175`). | V1 `GET /lsp`, `GET /find/symbol`; event `lsp.updated` (legacy event in `packages/schema/src/lsp-event.ts`). | Show LSP status only for V1. |
| V2 | Not supported (`migrate-v1.mdx:413-414`); `lsp` is not a V2 permission action (`permissions.mdx:138`). | — | Skip. |

### A.16 MCP management

| Feature | How it works | API / events | Mobile notes |
| --- | --- | --- | --- |
| Add / list / remove | `opencode mcp add <name> --url ...` (project or `--global`), `opencode mcp list`; remove by editing config (`services/www/src/docs/content/mcp-servers.mdx:7-27`, `mcp-servers.mdx:477-523`). | V2 `mcp.list`, `experimental.mcp.add`, `experimental.mcp.remove`; events `mcp.status.changed`, `mcp.tools.changed`, `mcp.resources.changed`. V1 `GET /mcp`, `POST /mcp`. | A servers list with status dots. |
| Connect / disconnect | `/mcps` dialog in the TUI views, connects, disconnects and authenticates servers; disconnecting does not change config (`mcp-servers.mdx:485-509`). | V2 `experimental.mcp.connect`, `experimental.mcp.disconnect`. | Toggle per server. |
| OAuth | Remote servers default to OAuth with PKCE; client identity via pre-registered client, CIMD (`https://opencode.ai/oauth/opencode/client.json`) or dynamic client registration; loopback redirect `http://127.0.0.1/callback` (`mcp-servers.mdx:189-283`). MCP credentials are modeled as integrations (`packages/core/src/mcp/oauth.ts:274-279`). | V2 `integration.oauth.connect` / `integration.oauth.status` / `integration.oauth.complete`. CLI `opencode mcp auth`, `opencode mcp logout`. | The redirect lands on the **server's** loopback address, so a phone cannot complete it by itself. MCP sign-in has no paste-code fallback: every MCP attempt is `mode: "auto"` and its callback listener binds `127.0.0.1` on the server (`packages/core/src/mcp/oauth.ts:388,448,520-521`), so show the authorization URL, ask the user to open it in a browser on the server computer, and wait for the attempt to finish (`integration.oauth.status`) (corrected 2026-10-15). |
| Resources and prompts | Built-in `list_mcp_resources` / `read_mcp_resource` tools; MCP prompts appear as `server:prompt` commands (`mcp-servers.mdx:404-425`). | V2 `mcp.resource.catalog`. | Optional resource browser. |
| Code Mode | By default agents reach MCP tools through the `execute` Code Mode tool; `codemode: false` lists tools directly (`tools.mdx:277-283`). | — | Render `execute` calls with their nested tool calls. |

### A.17 Provider login (API keys and OAuth subscriptions)

| Feature | How it works | API / events | Mobile notes |
| --- | --- | --- | --- |
| Connect flow | `/connect` lists integrations; pick a provider, then a method (API key, OAuth, provider command, or environment variable); providers can add forms (Azure resource name, GitHub Enterprise domain, ...) (`services/www/src/docs/content/cli/providers.mdx:13-66`). OAuth shows a URL or device code; TUI keys `o` open and `c` copy (`cli/providers.mdx:18-19`). | V2 `integration.list`, `integration.get`, `integration.connect.key`, `integration.connect.external`, `integration.oauth.connect` (returns `{ attemptID, url, instructions, mode: "auto" \| "code", time.expires }`), `integration.oauth.status`, `integration.oauth.complete`, `integration.oauth.cancel`, `integration.command.connect/status/cancel`; event `integration.updated`. V1 `GET /provider/auth`, `POST /provider/{id}/oauth/authorize`, `POST /provider/{id}/oauth/callback`, `PUT /auth/:id`. | `mode: "code"` flows (paste a code) and device-code flows work from a phone; browser-redirect flows that call back to a server loopback port (for example ChatGPT sign-in listens on the server's `/auth/callback`, `packages/core/src/plugin/provider/chatgpt.ts:93-121`) need the computer or a code-paste fallback. |
| Multiple accounts | Each successful login is a saved account; the newest is active; switch, rename or delete from `/connect` or `opencode auth switch\|logout` (`cli/providers.mdx:110-126`). Desktop: **Settings → Providers** and the connect dialog manage accounts (v2.0.29, PR #54101). | V2 `credential.list`, `credential.create`, `credential.update`, `credential.remove`, `credential.activate`; events `credential.updated`, `credential.switched`. | Account switcher per provider. |
| Subscription logins in V2 | Method labels in code: "Sign in with ChatGPT" (`packages/core/src/plugin/provider/chatgpt.ts:99`), "Codex browser (legacy)" and "Codex device code (legacy)" (`openai.ts:59,178`), "Login with GitHub Copilot" with GitHub.com or Enterprise (`github-copilot.ts:53-62`), "Login with GitLab (OAuth)" (`gitlab.ts:131`), "SuperGrok Subscription" (`xai.ts:46`), "Login with Poe (browser)" (`poe.ts:31`), "Login with DigitalOcean" (`digitalocean.ts:45`), "Login with Snowflake (External Browser)" (`snowflake-cortex.ts:97`), "OpenCode Console account" device login (`opencode.ts:111`), "Microsoft Entra ID (Azure CLI)" (`azure.ts:152`), "Google Cloud credentials (gcloud auth or environment)" for Vertex (`google-vertex.ts:128`), "AWS profile (SSO or named profile)" for Bedrock (`amazon-bedrock.ts:65`). | As above. | Claude Pro/Max is **not** offered: "Anthropic explicitly prohibits this" and the bundled plugins were removed in V1 1.3.0 (`packages/web/src/content/docs/providers.mdx:355-366`). |
| Storage | Keys and tokens live in the server's SQLite database (`cli/providers.mdx:128-140`). | — | The phone never needs to hold provider secrets; it only relays keys the user types. |

### A.18 Notifications and sounds

- **TUI:** opt-in OS notifications and sounds (`cli.json` → `attention`) for four events: input needed (form), permission needed, session done, session failed; notifications only fire while the terminal is not focused and never for subagents; sound slots for default, question, permission, error, done and subagent_done (Appendix 1, A1.8). The v2.0.29 changelog also lists terminal program-status notifications for working sessions and sessions awaiting permission or input (PR #55172), but that change was reverted before v2.0.29 was tagged (PR #55300; details in A1.8), so no released build has it (corrected 2026-10-15).
- **Desktop and web:** OS notifications and sounds fire only on `session.execution.succeeded` ("Response ready") and `session.execution.failed` ("Session error"), only for root sessions with an open tab, and only when no app window is focused; a permission-notification setting exists but no trigger was found (B.9).
- **Server signals to watch:** `session.idle`, `session.status`, `permission.asked`, `form.created`, `session.execution.failed`.
- **Push:** no opencode server sends push notifications. No APNs, Web Push or push-subscription code exists in `packages/` (only the in-page `Notification` API in `packages/app/src/runtime/platform/web.ts:29`); a Web Push PR (#47374) was closed unmerged (section D). A native app must solve push itself (for example with a companion relay), or rely on foreground/background refresh.

### A.19 Status information (tokens, cost, context)

| Feature | How it works | API / events | Mobile notes |
| --- | --- | --- | --- |
| Tokens, cost, context % | Desktop session view shows context tokens and the accumulated cost of the whole session family (v2.0.29, PR #53785; the client helper is `lastAssistantWithUsage`). Subagent costs are included (v2.0.28, PR #55052). The TUI sidebar shows "N tokens", "N% used" and "$X spent", where tokens are the last assistant turn's input + output + reasoning + cache measured against the model's context limit; the prompt footer shows "12,345 (45%) · $0.12"; the assistant footer can show tokens per second (Appendix 1, A1.5-A1.6). | V2 events `session.usage.recorded`, `session.usage.updated`; `session.context` returns the active context messages after the last compaction. | Compact header chip "42% · $0.37"; tap for details. |

### A.20 Themes and keybinds

Covered in Appendix 1 (TUI, `cli.json`) and section B (desktop/web appearance and keybind settings). V2 terminal themes are documented in `services/www/src/docs/content/cli/theme.mdx` and `services/www/src/docs/content/themes.mdx`.

### A.21 Worktrees, workspaces and sandboxes

| Feature | How it works | API / events | Mobile notes |
| --- | --- | --- | --- |
| Git worktrees | Create, list, refresh and remove worktrees for a project; default parent directory under the server data dir or `worktree.directory` in config; plugins can add other strategies (`services/www/src/docs/content/config.mdx:477-509`). The agent can do it too with Code Mode `worktree_create`, `worktree_list`, `worktree_remove` (removal needs edit approval; `force` discards changes) (v2.0.27, `tools.mdx:238-255`). | V2 `worktree.list`, `worktree.create`, `worktree.remove`, `worktree.refresh`; events `worktree.ready`, `worktree.failed`, `worktree.resolved`, `worktree.updated`. | "New task in worktree" flow, then `session.move`. Desktop UI in section B. |
| Provider-backed workspaces (cloud sandboxes) | Core and the embedded SDK have an internal `Workspace` abstraction with pluggable drivers (provision, connect, destroy, idle tracking) (`packages/core/src/workspace.ts:1-80`), but "Provider-backed workspaces are not part of the V2 HTTP contract and can be introduced later" (`V2_HTTP_API_AUDIT.md`, resolved item for `POST /api/workspace`). | None over HTTP; events `workspace.ready`, `workspace.failed`, `workspace.status` exist in the schema. | Not drivable from a phone today. See section C. |

### A.22 GitHub and GitLab integration

- GitHub Action: comment `/opencode` or `/oc` on an issue or PR to explain an issue, fix it in a new branch and PR, or implement review requests (`github/README.md`). V1 CLI: `opencode github` (install and run the agent) and `opencode pr <number>` (check out a PR branch and start opencode) (`opencode --help` on v1.18.23). The V2 CLI has no `github` or `pr` command (`packages/cli/src/commands/handlers/` contains no such handler).
- GitLab: V1 docs `packages/web/src/content/docs/gitlab.mdx`; "Login with GitLab (OAuth)" and GitLab Duo as a provider (`packages/core/src/plugin/provider/gitlab.ts:131`).
- Mobile notes: nothing to drive from the phone except reading PR links in transcripts. More detail in section C.

### A.23 IDE extensions and ACP

- **VS Code extension** (`sdks/vscode/package.json`, publisher `sst-dev`, version 2.0.29): commands "Open opencode" and "Open opencode in new tab"; V1 docs list `Cmd+Esc` quick launch, `Cmd+Shift+Esc` new session, automatic sharing of the current selection/tab, and `Cmd+Option+K` to insert `@File#L37-42` references (`packages/web/src/content/docs/ide.mdx:9-16`). The extension auto-installs when `opencode` runs in the integrated terminal of VS Code, Cursor, Windsurf or VSCodium (`ide.mdx:20-27`). v2.0.28 fixed the extension launching V2 with a removed `--port` flag (PR #49084).
- **ACP** (Agent Client Protocol): `opencode acp` runs opencode as an ACP agent over stdio for Zed and other ACP clients, with sessions, cancellation, extra directories, config options, MCP servers, permissions, questions, compaction, usage, child sessions and retry status in the protocol mapping (`services/www/src/docs/content/cli/acp.mdx:1-382`; V1 `packages/web/src/content/docs/acp.mdx`).
- Mobile notes: ACP is stdio-only and not a network protocol, so it is not a path for a phone.

### A.24 Plugins, Code Mode and the browser

| Feature | How it works | Mobile notes |
| --- | --- | --- |
| Server plugins | npm packages, versioned packages or local files in `plugins` config or `.opencode/plugins/`; enable/disable with `-id` and wildcards; `opencode plugin add\|list\|check\|update\|remove` (`services/www/src/docs/content/plugins.mdx`). The V2 plugin API offers transforms (agents, providers, models, commands, integrations, MCP, references, skills, tools, VCS, worktrees, websearch) and hooks (prompt admission, model requests, permissions, shell, tools) (`services/www/src/docs/content/build/plugins/index.mdx`). v2.0.29 added `ctx.permission.assert` so plugins can use the native approval prompt (PR #54930). API: `plugin.list`, `plugin.check`, `plugin.update`, `rpc.call` (plugin RPC); event `plugin.updated`. | A phone can list plugins and call plugin RPCs; plugin-provided UI will not render. |
| CLI (TUI) plugins | Plugins that expose TUI components load automatically; CLI-only plugins go in `cli.json` (`services/www/src/docs/content/cli/plugins.mdx`). | Not applicable. |
| GUI extensions | Desktop/web extension surfaces (`packages/gui-extensions`); `BridgeLayout` gained viewport size and border info in v2.0.27. Details in section B. | Not applicable unless the iOS app hosts web views. |
| Official plugins | Optional **Figma** plugin with its MCP connection and six bundled skills (v2.0.28, PRs #55049/#55061; `packages/plugins/figma`). | Works through the server. |
| Code Mode (`execute`) | The agent runs JavaScript that calls and combines catalog tools (parallel calls, result processing); no filesystem, imports or timers, only `fetch`; denying `execute` removes Code Mode and tools reached only through it (`tools.mdx:205-220`). Namespaces: `opencode` (session and worktree utilities), MCP servers, `browser`. | Render `execute` cards with nested tool calls. |
| Browser control | The `browser` Code Mode namespace drives the browser attached by the **desktop app**: tabs, navigation, snapshots, clicks, forms, screenshots, file transfer (5 MiB), console/network, performance traces, heap, Lighthouse (`tools.mdx:257-275`; `packages/plugin-browser`). | Desktop-only capability; the phone can show screenshots returned by these tools. |
| V1 custom tools | V1 custom tools defined in config and executed as code (`packages/web/src/content/docs/custom-tools.mdx`). | — |

### A.25 Skills

`SKILL.md` folders (or flat `.md` files) in `.opencode/skills`, `~/.config/opencode/skills`, and the compatibility paths `.claude/skills` and `.agents/skills`, plus HTTP catalogs listed in the `skills` config array (`services/www/src/docs/content/skills.mdx:5-118`). The model sees ID, name and description each step and loads a skill with the `skill` tool; `metadata.opencode/autoinvoke: false` or `disable-model-invocation: true` hides a skill from the model; permissions use the `skill` action (`skills.mdx:120-235`). Built-in skills: "OpenCode" (a docs index) and "Report" (file a GitHub issue) (`packages/core/src/plugin/skill.ts:31-41`). API: `skill.list`, `experimental.session.skill`; events `skill.updated`, `session.skill.activated`. Mobile: a skills browser plus `@skill` typeahead.

### A.26 Web search, warming and other server features

- **Web search** (V2): five providers (Exa, Firecrawl, Parallel, Tavily, TinyFish); the first search asks for permission and a provider and remembers the choice; `websearch.provider` can be fixed or `random`, with 429 cooldown failover (`services/www/src/docs/content/websearch.mdx:11-65`). API `websearch.providers`, `websearch.query`; event `websearch.updated`. V1: websearch only with the OpenCode/Go providers or `OPENCODE_ENABLE_EXA` / `OPENCODE_ENABLE_PARALLEL` (`packages/web/src/content/docs/tools.mdx:234-262`). Console-side web search is in section C.
- **Warming**: optional keep-alive requests every 4 minutes for 30 minutes to keep provider prompt caches warm (`services/www/src/docs/content/warming.mdx:5-40`).
- **Formatters**: run after edits/writes (`services/www/src/docs/content/formatters.mdx`).
- **Text generation from context**: `session.generate` "Generate transient text from the current session context without mutating session history" and `experimental.generate.text`.
- **Synthetic messages**: `session.synthetic` admits non-user input (used by integrations).
- **Config editing**: `config.get`, `config.shells`, `experimental.config.update` (global configuration), `location.reload`.

### A.27 Settings and configuration

- Config files: system (`/Library/Application Support/opencode`), macOS managed preferences (`ai.opencode.managed`), global `~/.config/opencode/opencode.json(c)`, project `opencode.json(c)` and `.opencode/opencode.json(c)`; managed settings win (`services/www/src/docs/content/config.mdx:28-110`). Keys include `model`, `default_agent`, `shell`, `update` (`disable`/`notify`/`auto`), `permissions`, `policies`, `agents`, `snapshots`, `watcher`, `formatter`, `media`, `tool_output`, `websearch`, `mcp`, `compaction`, `warming`, `skills`, `commands`, `instructions`, `references`, `worktree`, `plugins`, `providers` (`config.mdx` headings 128-532).
- Terminal client settings: `~/.config/opencode/cli.json` (V2) or `tui.json` (V1); see Appendix 1.
- Desktop and web app settings: see section B.
- Mobile notes: the phone should treat config as server-owned. `experimental.config.update` only edits global configuration.

### A.28 What shipped during 2026

Sources: GitHub release notes for the V1 line (`gh release view <tag> -R anomalyco/opencode`; the repo's releases page lists only V1 tags), git tag dates for V2 (`refs/tags/v2.0.*`), and the V2 `CHANGELOG.md` (local copy for v2.0.26 to v2.0.29; the `dev` branch copy adds v2.0.30). The V2 changelog starts at v2.0.26, so V2 changes between 2.0.0 and 2.0.25 are reconstructed from merged PRs.

**V2 path to release.** Beta builds were published to npm as `@opencode-ai/cli` from 2026-06-04 to 2026-09-07 (npm registry). The public beta was announced in July on Threads (https://www.threads.com/@thdxr/post/DanwMEyILo6/ [not re-checked]; its post ID encodes 2026-07-10 under Instagram's media-ID scheme) and promoted at v2.opencode.ai, which now redirects to https://opencode.ai/v2. The @opencode X post "try v2 beta today" (https://x.com/opencode/status/2090794386413986201, checked through api.fxtwitter.com) is dated 2026-08-21, not July (corrected 2026-10-15). v2.0.0 was published as `@opencode/cli` on 2026-09-11 (npm publish time 2026-09-11T23:44Z; the lightweight tag `v2.0.0` points at commit `63f7cee`, dated 2026-09-11T23:46Z), and Anomaly published the "OpenCode 2.0" note around 2026-10-12 (https://anoma.ly/notes/opencode-2-0; The New Stack coverage https://thenewstack.io/opencode-2-shared-service/ [not re-checked]). Notable V2 PRs between 2.0.0 and 2.0.26 (verified with `gh pr view`): QR pairing in the app (#47799, 09-08), desktop local device pairing (#49291, 09-22), one-time pairing links (#50970, 09-24), MCP Code Mode defaults (#51029, 09-24), provider account switching (#51266, 09-25), `auth export`/`auth import` (#52139, 09-29), commenting on page elements in the in-app browser (#52217, 09-30) and Go Plus docs (#51834, 09-28). An autonomous `/goal` command (#45379) was merged into the `v2` branch on 09-18 and reverted about two hours later (#49866, "revert(core): remove autonomous goal command"), so no release shipped it; session goal and todo state is back in review as open PRs #54799 (durable contracts, opened 10-12) and #55744 (HTTP endpoints, opened 10-15), all checked with `gh pr view` (corrected 2026-10-15).

**Distribution.** V1: npm `opencode-ai`, `brew install anomalyco/tap/opencode`, `curl https://opencode.ai/install`. V2: npm `@opencode/cli`, `brew install anomalyco/tap/opencode-v2`, `curl https://opencode.ai/v2/install`, WinGet, AUR `opencode-beta`, Docker `ghcr.io/anomalyco/opencode:2.x` (section 1).

**Release lines.** V1 went from v1.0.222 (2026-01-01) through 1.1, 1.2 (2026-02-14), 1.3 (2026-03-22), 1.4 (2026-04-08), a jump to 1.14 (2026-04-19), 1.15 (2026-05-15), 1.16 (2026-06-05), 1.17 (2026-06-10), 1.18 (2026-07-14) and 1.19 (2026-10-11); the latest is v1.19.1 (2026-10-15). V2 was tagged v2.0.0 on 2026-09-11 and reached v2.0.30 on 2026-10-15 (tag dates). V1 v1.19.0 added `opencode upgrade --major` "to upgrade to OpenCode 2" and a TUI `/update` command, and stopped installing updates automatically. Earlier V1 builds lack the option (it is absent at tag v1.18.35 and in the installed 1.18.23). The command swaps the installation: npm, pnpm, Bun and Yarn replace `opencode-ai` with `@opencode/cli`; Homebrew uninstalls the V1 formula and runs `brew install anomalyco/tap/opencode-v2`; curl installs run the V2 installer, which replaces `~/.opencode/bin/opencode`. Package-manager swaps reinstall V1 if the V2 install fails, and Chocolatey or Scoop users are pointed to https://opencode.ai/v2/docs (tag v1.19.1: `packages/opencode/src/cli/cmd/upgrade.ts:22-25,51-66`, `packages/opencode/src/installation/index.ts:85-108,195-226`). Homebrew tap users on 1.18.x get 1.19.x first with `opencode upgrade`, which pulls the tap before running `brew upgrade` (tag v1.18.23: `packages/opencode/src/installation/index.ts:280-301`): the published `anomalyco/tap/opencode` formula is 1.19.1 (updated 2026-10-15), while a tap checkout last pulled before 10-11 still shows 1.18.x (this Mac's, pulled 2026-10-05, shows 1.18.34). The homebrew-core `opencode` formula has shipped V2 since 2.0.15 (2026-09-28), so `brew upgrade opencode` from core already moves to V2 (`gh api` commit history of `anomalyco/homebrew-tap` and `Homebrew/homebrew-core`). Neither docs site mentions `--major`: the V2 guide says to remove a package-managed V1 installation, then install V2 with `brew install anomalyco/tap/opencode-v2`, `npm install -g @opencode/cli` or `curl -fsSL https://opencode.ai/v2/install | bash` (`services/www/src/docs/content/migrate-v1.mdx:5-6`, `index.mdx:14-16`).

| Month (2026) | Notable user-facing changes (version) |
| --- | --- |
| January | Git worktree "sandbox" support for working in several directories per project (v1.1.1); interactive question tool (v1.1.7); Codex/ChatGPT authentication (v1.1.11); server password authentication via `OPENCODE_SERVER_PASSWORD` (v1.1.15); Ask Question tool in the desktop app and a plan mode with enter/exit tools (v1.1.19); official GitHub Copilot plugin (v1.1.21); fork sessions in the desktop app (v1.1.13); image previews for attachments (v1.1.14); new sound effects (v1.1.29); ACP session list and fork (v1.1.30); headless ChatGPT/Codex sign-in (v1.1.37); skills invokable as TUI slash commands (v1.1.48); settings made responsive for mobile and small windows (v1.1.41). |
| February | `.agents/skills` discovery (v1.1.50) and skill discovery from URLs (v1.1.54); option to turn off sound effects (v1.1.64); notifications navigate to the session (v1.1.65); storage moved to SQLite and incremental `message.part.delta` events (v1.2.0); `attach --continue/--fork` (v1.2.6); experimental `workspace-serve` (v1.2.11); OpenCode Go ($10/month) launched at the turn of February and March: its docs page was first committed on 02-27 and updated by PR #15415 on 02-28, the opencode.ai/go landing page was added on 03-03 (commit `3c8ce4a`, "feat(console): add /go landing page"), and a 03-07 news report says Go launched "last week" (https://letsdatascience.com/news/opencode-launches-10-monthly-open-source-agent-f29289b1). No first-party launch post was found (corrected 2026-10-15). |
| March | Electron desktop build added (PR #15663, merged 2026-03-04); basic remote workspace support (v1.2.16); a Ghostty-based web terminal (v1.2.18); workspaces in the TUI (v1.2.24); **v1.3.0**: Anthropic OAuth plugin removed, GitLab Agent Platform, git-backed session review (uncommitted and branch diffs), multistep authentication (Copilot Enterprise), interactive update flow, Node.js runtime support, project navigation shortcuts. |
| April | Review comments with file mentions and keyboard navigation in the question dock (v1.3.14); **v1.4.0**: OTLP export, full HTTP proxy support, "Switch model variant" keybind, PDF drag and drop, `opencode run --dangerously-skip-permissions`, better subagent sessions, auto-accept moved into Settings; OpenCode Go subscribe prompt when free limits are hit (v1.4.1); plugins can register workspace adaptors (v1.4.4); full-session fork option (v1.14.17). |
| May | Warp a session into another workspace, carrying uncommitted changes (v1.14.37, v1.14.41); built-in `customize-opencode` skill (v1.14.46); experimental background subagents (v1.14.51); Effect-based core event system (v1.15.0); TUI diff viewer (v1.15.6); workspace management dialog (v1.15.12). |
| June | Managed workspace cloning, moving sessions between workspaces, skill discovery and file-based agents, `run --replay`; desktop color themes, thinking-level selector, Settings → Servers tab, update button (v1.16.0); running subagents can be sent to the background (v1.16.2); faster `fff` file search (v1.17.0); `--mini` CLI mode, **mobile bottom navigation, improved iOS PWA shell, mobile session and home layouts** (v1.17.10); session snapshots and revert controls in the redesigned desktop layout (v1.17.11); "yolo mode" to auto-approve permissions (v1.17.12); V2 beta builds start on npm (`@opencode-ai/cli`, 2026-06-04). |
| July | Minimizable question prompts (v1.17.13); Code Mode MCP adapter (v1.17.14); unread state on tabs with pending questions (v1.17.15); review panel file-browser tabs (v1.17.16); **Desktop v2 layout migration completed with first-launch onboarding** (v1.18.0); nested subagents off by default with `subagent_depth` (v1.18.2); review panel and embedded terminal theme improvements (v1.18.4); opt-in V2 desktop sidecar backed by the bundled CLI service (v1.18.9); V2 public beta. |
| August | Toasts with mobile layout (v1.18.10); external links open in the system browser (v1.18.11); xAI single device-code login for headless/remote use (v1.18.14); web search with the Go provider (v1.18.19); archive session command in both desktop layouts (v1.18.21); mobile web startup caching (PR #44205, 08-22) and refined mobile shell (PR #46388, 08-31); hosted beta web app at beta.opencode.ai (PR #46086, 08-29). |
| September | Public-API browser plugin (PR #46531, 09-07); **V2 v2.0.0 (2026-09-11)**; the V2 PRs listed above (pairing, Code Mode for MCP, account switching, auth export/import, browser element comments); Go Plus ($40/month) documented (PR #51834); the iOS app's voice calls launched around 09-17 (stated in PR #54426); V1 maintenance releases. Mobile-relevant V2 work in this period (pairing QR, one-time pairing links, iOS voice) is listed in section D. |
| October | V2 v2.0.26 (10-08): Vertex Application Default Credentials, faster/safer snapshots, clickable transcript links, `opencode service` remote URLs on a persistent random subdomain, "Step 5 Preview Free". v2.0.27 (10-12): built-in worktree tools, consent prompt for `opencode pair --remote`, **installable web app (PWA)**, visible execution failures, automatic project archiving. v2.0.28 (10-13): per-project auto-accept, TUI release highlights (`/highlights`), native Windows ARM64, Gemini continuation, WinGet packages, official Figma plugin. v2.0.29 (10-14): **Settings → Pairing → Pair device** with QR code via OpenTunnel, provider account management, automatic continuation at the output-token limit, trackpad zoom for images, context tokens and family cost in the session view. v2.0.30 (10-15): "Changed files" per turn in the timeline, docked TUI `/diff`, Option+↑/↓ tab navigation, **iOS app voice delegations shown as Voice messages**, session-sharing backend removed. V1: v1.19.0 (10-11) `upgrade --major`; v1.19.1 (10-15) session sharing discontinued. |

---

## B. Official app (packages/app + packages/desktop)

Citation prefixes in this section: `app/` = `packages/app/src/`, `gx/` = `packages/gui-extensions/src/`, `sui/` = `packages/session-ui/src/`, `ui/` = `packages/ui/src/`, `desk/` = `packages/desktop/src/`, `client/` = `packages/client/src/`.

### B.1 Architecture

- **One app, two shells.** A single SolidJS app (`packages/app`) is both the web app (served by every V2 server, also hosted statically at `app.opencode.ai` and `beta.opencode.ai`, section C) and the renderer of the Electron desktop app (`packages/desktop`) (`app/app.tsx:48-85`).
- **Core plus extensions.** "Every feature of the desktop and web app that is not the core shell is an extension" (`packages/gui-extensions/README.md:3`). Built-ins: context, btw, debug, terminal, file, review, details, browser, pairing, updater, ssh, wsl, microsoft-office (`gx/renderer.ts:38-52`). Extensions contribute commands, menu items, panels, settings pages, servers, link handlers, titlebar items, slots and styles (`README.md:216-227`). Each panel declares a desktop region and a **mobile kind (tab, menu or drawer)** (`gx/sdk/registries.ts:210,239`). Main-process IPC is inactive on the web, so IPC-backed extensions are desktop-only (`README.md:281`).
- **Data layer.** One controller per server holds the client, the SSE stream `GET /api/event`, notification state and the permission auto-approver (`app/runtime/server/runtime.tsx:53-79`). SSE timings: server keepalive every 15 s, connect timeout 2 s, reconnect delay 1 s, idle timeout 45 s, "foreground" threshold 20 s; the stream must begin with `server.connected`; `pagehide` stops it, `pageshow` restarts it, and visibility or `online` events trigger a resync (`client/solid/connection.ts:21-38,106-107,219-240`). These are good starting values for an iOS client.
- **Persistence.** Web: localStorage keys `opencode.global.dat:<key>` and per-window `opencode.window.<id>.dat`; settings under `settings.v3`; desktop drafts in SQLite (`app/runtime/persistence/storage.ts:43-45`, `app/settings/model.tsx:310`, `desk/main/storage/schema.ts:1-49`).
- **Platform contract** (what a host shell must provide; a useful checklist for a native app): open external URL, open browser, open/reveal path, notify, attachment picker, save file, storage and draft store, zoom and pinch zoom, menu actions, clipboard image, export debug logs, extension bridge, window ID, directory picker (`app/runtime/platform/platform.tsx:34-130`).

### B.2 Screens, layout and navigation

| Route | Screen | Notes |
| --- | --- | --- |
| `/` | Home | Servers, projects and sessions (`app/shell/routes/routes.tsx:43-68`) |
| `/settings` | Settings | `?tab=&server=&project=&subtab=` (`app/settings/route.ts:1-182`) |
| `/server/:serverKey/session/:id` | Session | `serverKey` is the base64 of a URL, `"sidecar"` or an extension key, so tabs from different servers coexist (`app/shell/routes/session.ts:5-7`; `app/runtime/server/registry.tsx:185-194`) |
| `/new-session` | Draft composer | `DraftRoute` (`routes.tsx:43-68`) |
| (gate) | "Connect to a server" | Shown when no server exists or the only HTTP server is unauthorized (`routes.tsx:86-110`) |

Other full-screen states: "Creating worktree" (`app/session/route.tsx:54-95`), an incompatible-server panel (`app/session/incompatible-server-panel.tsx:17-27`), route errors and a global error page (`app/shell/errors/error.tsx:319-424`).

- **Titlebar and tabs.** Browser-like session tabs, horizontal by default; an optional vertical tab sidebar (desktop only, 140–520 px); back/forward (`mod+[`, `mod+]`); a Home button (`mod+b`); extension titlebar items; a release-channel badge (`app/shell/shell.tsx:26,50-69`; `app/shell/titlebar/titlebar.tsx:129-144,398-460,681-828`). Tabs show a project avatar with an unread dot and a pulse when a prompt is queued in a background tab; middle-click closes, double-click renames, drag reorders; a hover card (project, title, path, server) appears after 750 ms on desktop; 25 recently closed tabs can be reopened; inactive tabs keep syncing (`app/shell/tabs/*`, `app/shell/titlebar/tab-nav.tsx:102-420`, `app/shell/titlebar/tab-popover.tsx`, `app/shell/titlebar/tab-strip.tsx:155-409`).
- **Home.** Desktop: servers and their projects on the left (health dot, "Authenticate" for signed-out servers, drag-to-reorder projects, recently closed projects), sessions on the right; phone: a project dropdown (`app/home/route.tsx:14-47`; `app/home/projects/view.tsx:90-642`). Project menu: New session, Import session (desktop), Edit project, Reveal…, Clear notifications, Close (`view.tsx:748-796`). Sessions are grouped Today / Yesterday / Older and exclude child and archived sessions; row menu Rename / Export… / Delete…; long-press 500 ms on touch; open in a background tab; `mod+f` search including direct session-ID lookup (`app/home/sessions/*`).
- **Layout defaults.** Sidebar 344 px, file tree 200 px, session panel 600 px, bottom dock 280 px; side-panel tabs persist per session (`app/shell/state/layout.tsx:19-25,526-613`).

### B.3 Server connection management

- **Server types:** `http` (any URL), `sidecar` (the desktop's local service) and `extension` (SSH, WSL); many can be connected at once (`app/runtime/server/registry.tsx:148-183`).
- **Health:** `server.info` (`GET /api/info`) polled every 10 s, 30 s timeout, 2 retries; HTTP 401 marks the server unauthorized and disposes its controller until it recovers; rows show a lock, spinner, warning or green/red/grey dot and are sorted by health (`app/runtime/server/health.ts:23-140`; `runtime.tsx:81-95`; `app/servers/registry/row.tsx:107-157`). No dedicated reconnecting banner for HTTP servers was found.
- **Connect screen and dialog:** default method is a pairing link; a switch offers "No pairing link? Use password" (URL, name, password); "Scan QR code" is **web-only** and uses the `qr-scanner` library with the rear camera (10 scans/s, inverted codes accepted); the footer points to `opencode pair`; an https page explains it cannot reach an http server (mixed content); errors: expired, mixed content, unreachable, legacy link (`app/servers/connect/screen.tsx:36-251`, `method.tsx:7-27`, `dialog.tsx:97-236`, `scanner.tsx:1-96`, `camera.ts:4-33`, `redeem.ts:17-52`). Pairing protocol details are in D.2.
- **Server menu:** Edit / Show in project list / Hide from project list / Remove (Remove also closes that server's tabs); an "Add server" menu with extension items such as "Add SSH server" (`app/servers/registry/row-menu.tsx:36-100`, `controller.ts:39-61`, `add-menu.tsx:10-61`).
- **Per-server settings:** connection status, name, URL, Authenticate, and "Terminal shell" chosen from `config.shells` and saved with `experimental.config.update` (`app/settings/servers/servers.tsx:18-116`; `app/settings/general/controllers.ts:27-74`).
- **Web specifics:** the default server is the page's own origin (none when hosted with `VITE_OPENCODE_SERVER_MODE=none`); an `?auth_token=` parameter is read and stripped from the URL (`app/runtime/platform/web.ts:48-61`; `app/entry.tsx:44-50,81-82`).
- **Desktop specifics:** the built-in "Local Server" is the CLI background service (`serve --service`), found or started through `@opencode/client/service`; the main process injects Basic auth for it so the renderer never sees the password (`desk/main/service/background-service.ts:32-92`, `sidecar-credentials.ts:7-31`). SSH servers are set up automatically on Linux/macOS x64/arm64 with a host-trust step; WSL is Windows-only (`gx/ssh/*`, `gx/wsl/index.ts:8-16`). The **Pairing** page (desktop) has "Remote access" (OpenTunnel via `opencode service set remote`) and "Keep screen active" switches, a QR code of `{code, urls}` with an "Expires in" countdown, "New code" and "Copy link", and waits up to 180 s for the tunnel (`gx/pairing/main.ts:26-70`, `page.tsx:225-313`, `i18n/en.ts:1-28`).

### B.4 Projects, worktrees and workspaces

- Projects are directories on a server, added by directory picker or path; per-project settings: name, icon (128×128), color, worktree startup script and an auto-accept override, saved with `project.update` (`app/home/projects/add.ts:3-21`; `app/settings/workspaces/project.tsx:37-238`).
- **Worktrees** settings page lists worktrees, runs a `vcs.status` / `vcs.diff` preflight before deleting, then `worktree.remove`, with bulk actions (`app/settings/workspaces/workspaces.tsx:97-670`).
- **New session:** `mod+shift+o` picks the project, `mod+alt+l` cycles the location (local, existing worktree, new worktree); "Default environment" defaults to last used; a new worktree shows "Creating worktree" (`app/new-session/commands.tsx:36-51`; `app/settings/model.tsx:277-300`).
- **Move a session:** the Details extension's workspace menu creates a worktree and moves the session (`worktree.create` + `session.move`) (`gx/details/workspace-menu.tsx:26-145`). A missing directory shows a notice above the composer (`app/session/composer/location-missing.tsx:22-121`).
- No GUI for environment drivers or sandboxes (`session.environment`) was found.

### B.5 Session view

- **Layout.** Desktop: sticky header, virtualized timeline and composer in the center; side panel with extension tabs on the right; optional bottom dock (100 px to 60% of height); chat minimum 450 px, review panel 480 px or 800 px for split diffs (`app/session/screen.tsx:115-117,425-590`; `session-panel-width.ts:5-15`). **Phone (<768 px):** no header; chat and panels become tabbed views (`screen.tsx:187-304`).
- **Header.** Project menu; ancestor trail for child sessions; a **running menu** listing running work with Stop (`session.interrupt` or `shell.remove`); working indicator; title with inline rename; More options (Rename, Export…, Delete…); find in session (`mod+f`); review toggle (`app/session/timeline/message-timeline.tsx:463-612`; `app/session/session-identity-header.tsx:48-287`; `app/session/header/session-running-menu.tsx:29-312`).
- **Timeline.** Loads older messages on scroll up; "Jump to latest"; a "Working" row while busy; message navigation `mod+alt+[` / `mod+alt+]`; the session is marked viewed only while the window is focused (`app/session/timeline/interaction.ts:217-263`; `virtualizer.tsx:848-870`; `app/session/route.tsx:191-209`).
- **Docks above the composer (bottom-up):** web search dock → question dock → permission dock → composer (`app/session/composer/region.tsx:58-341`).
  - **Permission dock:** **Deny / Allow always / Allow once**; requests from descendant subagent sessions appear in the parent; auto-accept answers `once` on the client and is toggled with `mod+shift+a` (`app/session/requests/session-permission-dock.tsx:8-75`, `session-request-tree.ts:3-72`, `auto-approve.ts:15-169`).
  - **Question dock** answers the `question` tool (`app/session/requests/session-question-dock.tsx:81-723`).
  - **Web search dock:** "Third-party web search: Select the search provider agents use to search the web", options Any / a provider / "Don’t use search" (`app/session/requests/session-websearch-dock.tsx:10-93`).
  - **Queue panel:** queued or steered follow-ups via `session.inbox.list/update/cancel` (`app/session/composer/queue-panel.tsx:18-213`).
  - Child sessions are read-only ("cannot be prompted"); `Esc` returns to the parent (`region.tsx:151-156`).
- **Composer.** `!` shell mode, `@` context mentions, `/` slash commands (`app/composer/suggestions/machine.ts:101-270`); "+" add menu, paste, drop or pick attachments, 20 MiB inline limit, uploads written to the server with `experimental.fs.write` (`app/composer/editor/editor.tsx:579-813`; `app/composer/attachments/attachments.ts:64-275`, `destination.ts:19-62`); Submit/Stop button with an alternate delivery (queue vs steer); a blank submit while the agent works interrupts it; shell prompts cannot be queued; the input blurs after send on phones (`app/composer/submit.ts:64-546`). Shortcuts: model picker `mod+'`, variant cycle `shift+mod+d`, agent cycle `mod+.` / `shift+mod+.`; the model picker is a drawer on phones (`app/composer/commands.tsx:42-82`; `app/providers/models/select-dialog.tsx:267-444`). Undo/redo use `session.revert.stage/clear/commit` (`app/session/revert.ts:48-118`); fork and export dialogs; usage-exceeded dialogs.

### B.6 Side panel ("Review and files")

The side region has a tab strip with an "Add tab" menu and an inner file-tree column (240–480 px); on phones panels render as tabs, menus or drawers (`app/runtime/extension/side-region.tsx:35-384`; `app/runtime/extension/mobile.tsx:26-206`).

| Extension | What it shows | Details |
| --- | --- | --- |
| Review (`gx/review`) | Diffs | "Review" / "Files Changed N"; modes: git working tree (`vcs.diff`), branch (`vcs.diff`), last turn (`session.diff`); initialize Git (`vcs.init`); split/unified, collapse and wrap; **line comments flow into the prompt**; refresh when the session goes idle; image/media diffs; `mod+shift+r` (`gx/review/renderer.tsx:118-130`, `model.ts:99-564`; `sui/components/line-comment.tsx:150-441`). |
| Files (`gx/file`) | File tabs and tree | `mod+p` open file; "Open in" external apps; file links in messages open here; line comments; a file watcher refreshes; viewers for image, SVG, audio, video, PDF, HTML, Markdown, Mermaid, tables, fonts, documents, spreadsheets, presentations and text (`gx/file/renderer.tsx:259-628`; `packages/util/src/artifact.ts:2-16`). |
| Microsoft Office (`gx/microsoft-office`) | docx, xlsx, pptx | WebAssembly engines load lazily (`gx/microsoft-office/renderer.tsx:15-50`). |
| Terminal (`gx/terminal`) | PTY terminals | ``ctrl+` `` toggle, `ctrl+alt+t` new, `mod+w` close; side or bottom ("Terminal placement"); PTY over WebSocket; scrollback serialized locally (`gx/terminal/renderer.tsx:50-104`, `terminal.tsx:156-698`; `client/solid/pty.ts:21-66`). |
| Browser (`gx/browser`) | Embedded browser | `mod+shift+b` open, F5 reload, `mod+l` address; the agent drives it through `plugin-browser` (desktop only) (`gx/browser/renderer.tsx:25-101`; `packages/plugin-browser/README.md:3-24`). |
| Context (`gx/context`) | Usage ("Usage" on phones) | Provider, model, context limit, input/output/reasoning/cache tokens, message counts, total cost, created and last activity; system prompt, raw messages, export (`gx/context/i18n/en.ts:1-32`; `indicator.tsx:31-160`). |
| btw (`gx/btw`) | Side question | `/btw` answered by `session.generate`, not added to the transcript (`gx/btw/model.ts:7-88`). |
| Details (`gx/details`) | Session and server details | Popover `mod+shift+y`, panel, workspace menu ("Move to worktree") (`gx/details/popover.tsx:72-127`, `panel.tsx:31-172`). |

### B.7 Message parts and tool rendering

- **Message types** rendered by `sui/timeline/session-timeline-row.tsx:764-1020`: user; assistant (content parts: text, reasoning, tool); shell; idle; compaction; synthetic; system; agent-switched; model-switched; location-switched; skill.
- **Timeline detail model.** Categories shell, edit, thinking, subagents, notices and tools, each placed separate, grouped or hidden (shell/edit/thinking also expanded or collapsed); text is always shown; unfinished compactions, synthetic errors and failed shell results are forced visible (`sui/timeline/detail.ts:4-121`). Presets (Settings → Timeline detail slider, `detail.ts:21-77`):

| Preset | shell | edit | thinking | subagents | notices | tools |
| --- | --- | --- | --- | --- | --- | --- |
| Everything | separate, expanded | separate, expanded | separate, expanded | separate | separate | separate |
| Detailed | separate, expanded | separate, expanded | grouped, collapsed | separate | grouped | grouped |
| **Compact (default)** | grouped, collapsed | grouped, collapsed | grouped, collapsed | grouped | grouped | grouped |
| Quiet | hidden | grouped, collapsed | hidden | grouped | hidden | hidden |
| Messages only | hidden | hidden | hidden | hidden | hidden | hidden |

- **Rows:** user message (attachments, review comments, Voice badge for iOS voice delegations), assistant text with **paced streaming** (24 ms steps, snapping at whitespace or punctuation), reasoning, tool rows and tool groups ("Used N …" context groups and per-file edit groups), notices (agent/model/location switches, compaction queued/divider, synthetic messages, errors), user `!` shell rows, and the per-turn "changed files" summary (up to 5 files) (`sui/timeline/session-timeline-row.tsx:47,405-762`; `sui/message/message-content.tsx:110-836`).
- **Tool states:** streaming, running, completed, error (`sui/message/current-tool-state.ts:8-115`).

| Tool | Renderer (`sui/tools/tool-renderer.tsx`) | Notes |
| --- | --- | --- |
| read | `:1473-1567` | Grouped into a read group (`:843-936`); images rendered inline |
| list, glob, grep | `:1569-1669` | Part of "context" groups (`:459-841`) |
| webfetch | `:1671-1709` | Shows the requested URL while running (v2.0.30) |
| websearch | `:1711-1734` | Result links (up to 10 Exa results, `:397-452`) |
| subagent (`task`) | `:1736-1871` | Child-session work with drill-in |
| execute (Code Mode) | `:1914-1951` | Console-style output (`:1873-1912`) |
| shell (`bash`) | `:1953-2038` | Output tail of 64 KiB, polls `shell.output` every second (`sui/tools/shell-output.ts:4,25-88`) |
| edit / write / patch (`apply_patch`) | `:2086-2347` | Per-file diff cards with a diagnostics block (`:169-197`) |
| question | `:2349-2401` | Hidden while running because the dock collects answers; "Questions dismissed" |
| skill | `:2403-2434` | |
| todowrite | `:1347` | Renders nothing: no todo UI in V2 |
| MCP and unknown tools | `sui/components/basic-tool.tsx:398-418` | Generic "Called `tool`" row with an MCP icon |

- **Shared rendering:** retry, session error and tool error cards (`sui/components/session-retry.tsx`, `session-error.tsx`, `tool-error-card.tsx`); Markdown with worker-based syntax highlighting, code-block copy buttons, Mermaid diagrams, links to other sessions and inline-code linking (`sui/components/markdown*.ts(x)`); LaTeX math rendered with KaTeX (inline `$…$` and `\(…\)`, display `$$…$$`; Pandoc-style rules keep prices such as `$5` as text) by the Markdown worker (`ui/context/marked-parser.tsx:1-26`, `sui/components/markdown.worker.ts:4,42`). The TUI has its own LaTeX plugin. UI strings: `packages/ui/src/i18n/en.ts:1-285`.

### B.8 Settings catalog

Settings open with `mod+comma`, are searchable (`mod+f`), and group client tabs, server-scoped pages (per server and project), extension pages, Experimental and About (`app/settings/shell.tsx:286-579`; `app/settings/search-catalog.ts:18-208`). Tab labels: Preferences, Shortcuts, Notifications, Projects, Worktrees, Servers, Extensions, Experimental, About, plus Providers and Models (`app/runtime/i18n/en.ts:603-685,929-998`).

| Section | Setting | Options / default |
| --- | --- | --- |
| General | Language | 63 locales |
| General | Tabs | Horizontal (default) / vertical |
| General | Default environment | Last used |
| General | Auto-accept permissions | Off |
| General | Show agent | Off. Shows the composer's agent picker and enables the agent-cycle shortcuts; while off, both are hidden and new prompts default to Build, unless a custom primary agent is configured, which shows the picker anyway (`app/runtime/i18n/en.ts:839-841`, `app/providers/models/selection.tsx:101,206-211`, `app/providers/models/agent.ts:1-3`, `app/composer/commands.tsx:71,79`) |
| General | Terminal placement | Side (default) / Bottom |
| General | **Follow-up behavior** | **Steer (default) / Queue** |
| General | Pinch to zoom | Desktop only |
| General | Wrap lines | From the review extension |
| General | Updates | Desktop updater section |
| General | **Bottom navigation** | Phone only: title bar at the bottom; default top |
| Timeline | Timeline detail | 5-step slider plus advanced per-category controls (B.7) |
| Timeline | Changed files | Off |
| Appearance | Color scheme, theme, UI / code / terminal fonts | 36 themes |
| Notifications | Agent / Permissions / Errors | On / On / Off |
| Notifications | Sound per category | 45 sounds |
| Keybinds | Every command | Record, clear, conflict detection, reset |
| Server pages | Connection, Terminal shell, Providers (API key, OAuth, accounts), Models, Extensions (MCP toggles, plugins, skills), Worktrees, Projects (name, icon, color, startup script, auto-accept override) | |

Sources: `app/settings/model.tsx:277-300`, `app/settings/general/general.tsx:220-338`, `app/settings/appearance/appearance.tsx:66-136`, `app/settings/notifications/notifications.tsx:57-128`, `app/settings/keybinds/keybinds.tsx:96-398`, `app/settings/providers/*`, `app/settings/workspaces/project.tsx:37-238`, `app/runtime/i18n/en.ts:823-846`.

### B.9 Notifications, sounds and unread state

- **Triggers:** only `session.execution.succeeded` ("Response ready", body = session title, Agent sound) and `session.execution.failed` ("Session error", error sound; error notifications off by default) (`app/shell/notifications/notification.tsx:219-275`). Only root sessions that have an open tab notify; clicking opens or focuses the tab. **No trigger for permission requests was found**, even though Permissions notification and sound settings exist (`notification.tsx:235,259` are the only `platform.notify` calls; the settings are read only by the settings UI, `app/settings/model.tsx:295,477,495-502`). Open issue #51507 (2026-09-26) reports that the "needs permission" notification never fires, two fixes were closed unmerged (#51524 "fix(app): notify when permission is required", #48808 "fix(app): play permission alerts in the new layout"), and `app/shell/notifications/` has not changed on `dev` since 2026-10-13 (`gh issue view`, `gh pr view`, `gh api` commit history, checked 2026-10-15).
- **Cross-window:** OS notifications only when no app window is focused; sound and notification are deduplicated across windows with Web Locks (`app/shell/notifications/coordinator.ts:5-104`). Web uses the Notification API (asked lazily); desktop notifications are silent because the app plays its own sound (`app/runtime/platform/web.ts:17-39`; `desk/renderer/platform/notifications.ts:4-22`).
- **Unread:** stored on the server as `time.idle` vs `time.viewed`; the client calls `session.view` only while focused and other clients resync on `session.viewed`; pending permissions or questions also count as unread on project avatars (`notification.tsx:28-33,177-205`; `client/solid/data.ts:1108-1112`; `app/shell/layout/project-avatar-state.ts:34-75`).
- **Not found:** tray icon, dock/app badge, global shortcuts, dynamic document title.

### B.10 Keybinds and command palette

The palette opens with `mod+k` or `mod+shift+p`; `mod` is Cmd on macOS and Ctrl elsewhere; extension commands can add slash names and keybinds (`app/shell/commands/command.tsx:18,213-216`; `app/runtime/extension/commands.tsx:8-41`). App slash commands: `/new`, `/undo`, `/redo`, `/compact`, `/fork`, `/export`, `/open`, `/terminal`, `/model`, `/connect`, `/agent`, `/mcp`, `/btw`, plus server commands from `command.list` (`app/composer/submit.ts:64-88`; `app/composer/model.ts:225-255`).

| Action | Default |
| --- | --- |
| Find (home, settings, session) | mod+f |
| Settings | mod+comma |
| New tab / close / reopen closed | mod+t or mod+n / mod+w / mod+shift+t |
| Back / forward; Home | mod+[ / mod+]; mod+b |
| Previous / next session tab; unread tabs | alt+↑ / alt+↓; shift+alt+↑ / ↓ |
| Tab 1–9; previous / next tab | mod+1..9; mod+option+← / →, ctrl+(shift+)tab |
| Model picker / cycle variant | mod+' / shift+mod+d |
| Cycle agent / reverse | mod+. / shift+mod+. |
| Attach file / shell mode / normal mode | mod+u / mod+shift+x / mod+shift+e |
| New session (in session) | mod+shift+s |
| Background session | ctrl+b |
| Open file / toggle review / toggle file tree | mod+p / mod+shift+r / mod+backslash |
| Add selection to context | mod+shift+l |
| Previous / next message | mod+alt+[ / mod+alt+] |
| Toggle MCP / auto-accept | mod+; / mod+shift+a |
| Terminal toggle / new / close | ctrl+backtick / ctrl+alt+t / mod+w |
| Details popover; browser | mod+shift+y; mod+shift+b |

Sources: `app/shell/titlebar/titlebar.tsx:134-488`, `app/shell/titlebar/tab-strip.tsx:288-505`, `app/composer/commands.tsx:47-78`, `app/composer/model.ts:443-460`, `app/session/commands/use-session-commands.tsx:328-512`, `gx/terminal/renderer.tsx:50-104`, `gx/details/popover.tsx:84`, `gx/browser/renderer.tsx:25-101`.

### B.11 Responsive and phone behavior

Phone layout below 768 px: no vertical tabs; title bar at the top or bottom ("Bottom navigation"); tabs in a drawer; safe-area insets; no session header and tabbed views; extension panels as tabs, menus or drawers; project dropdown on Home; long-press 500 ms and 250 ms drag delay; no hover popovers; composer blurs after send; model picker as a drawer; 16 px inputs on coarse pointers to avoid iOS zoom; virtual-keyboard inset handling (`app/shell/shell.tsx:19-46`; `app/shell/mobile-drawer.tsx:6-53`; `packages/ui/src/styles/base.css:407-419`; `app/runtime/platform/keyboard.ts:3-41`). PWA details are in D.3.

### B.12 Desktop-only features

| Feature | Evidence |
| --- | --- |
| Local sidecar service with credentials injected by the main process | `desk/main/service/background-service.ts:32-92`, `sidecar-credentials.ts:7-31` |
| First-launch onboarding | `desk/main/lifecycle/onboarding.ts:9-65`, `desk/renderer/onboarding/index.tsx:22-63` |
| `opencode://` deep links (registered). Any link brings the app forward; `opencode://console/authorized?window=<id>` focuses the window that started a Console sign-in. The renderer re-broadcasts links as an `opencode:deep-link` event, but nothing in the repo listens for it, so links do not navigate inside the app. | `desk/main/lifecycle/environment.ts:41`, `desk/main/lifecycle/index.ts:47-62,79-94`, `desk/main/lifecycle/deep-link.ts:1-14`, `desk/renderer/startup/deep-links.ts:1-15`; no other reader of `opencode:deep-link` or `__OPENCODE__.deepLinks` under `packages/` |
| Updater ("Check now", "Install and restart", Beta→Stable migration) | `gx/updater/renderer.tsx:7-112`, `gx/updater/i18n/en.ts` |
| Native menu and "Install CLI" | `desk/main/native/menu.ts:52-60`, `install-cli.ts:6-28` |
| Pairing page, SSH servers, WSL | `gx/pairing`, `gx/ssh`, `gx/wsl` |
| Embedded browser and agent browser tools | `packages/plugin-browser/README.md` |
| Import session, reveal in file manager, "Open in" apps, directory picker | `app/home/projects/controller.tsx:113-145`, `gx/file/renderer.tsx:403-436` |
| Export debug logs; zoom and pinch zoom; SQLite drafts | `app/shell/commands/desktop.tsx:5-25`, `app/runtime/platform/platform.tsx:34-130`, `desk/main/storage/*` |

### B.13 Languages

63 locales with RTL support, a language cookie and lazy loading (`app/runtime/i18n/desktop-native.ts:1-219`; `app/runtime/i18n/language.tsx:33-315`). Review, terminal, browser and file extensions ship every locale; pairing, btw, details and debug are English only.

### B.14 Server operations the GUI calls

`server.info/pair/connect`, `event.subscribe`; `session.list/get/update/remove/prompt/command/shell/switchAgent/switchModel/move/background/interrupt/view/diff/generate`, `session.inbox.list/update/cancel`, `session.revert.stage/clear/commit`; `worktree.create/remove`; `vcs.init/status/diff`; file reads and `experimental.fs.write`; `shell.output/remove`; `pty.*`; `config.get/shells`, `experimental.config.update`; `project.update`; `command.list`; `integration.*`; MCP toggles (GUI sub-report, cross-checked against `packages/protocol/openapi.json`).

---

## C. Cloud and hosted offerings

### C.1 Bottom line

- **There is no first-party hosted agent execution.** No cloud agents, hosted workspaces or sandboxes comparable to Cursor background agents or Codex cloud tasks were found in code, docs, the changelog or the live site. Every opencode agent runs on a machine the user controls (their computer, a VPS, a CI runner, or an embedder's infrastructure).
- **What is hosted:** model inference and billing (OpenCode Console models, formerly marketed as "Zen"), the OpenCode Go subscription, a bring-your-own-key provider gateway, hosted web search, organization policies, and the **OpenTunnel** relay that forwards encrypted traffic to the user's own machine.
- **Sharing is gone.** The share host now returns HTTP 410 (C.6).
- **Mobile implication:** a phone app must pair with a user-run server (section D). The Console offers an account device-login and config API (C.5), but no session, device-registry or remote-execution API.

### C.2 What the cloud-related packages are

| Package / service | What it is | Evidence |
| --- | --- | --- |
| `packages/console` | The opencode.ai **marketing site and edge router** (SolidStart on Cloudflare), not the Console dashboard. `/auth` and `/workspace` redirect to the separate "new Console" at `https://opencode.ai/console/login`. Zen/Go API routes are thin proxies to a separate `opencode-inference-<stage>` worker that "owns authentication, model availability, free-tier access, and billing". Other routes: `/zen`, `/go`, `/black`, `/enterprise`, `/download`, `/data` (stats), `/docs` proxy, `/s/:id` (old share page), `/openapi.json`, and `/oauth/opencode/client.json` (MCP OAuth client metadata). `console/function` ships Zen/Go request logs to Honeycomb. | `infra/console.ts:5-83`, `packages/console/app/src/middleware.ts:20-25`, `packages/console/app/src/lib/inference-proxy.ts:3-17`, `packages/console/function/src/log-processor.ts` (cloud sub-report) |
| Console dashboard | A separate single-page app at https://opencode.ai/console whose source is **not in this repo**: the marketing site redirects the legacy dashboard routes `/auth` and `/workspace` to this "new Console", a separate deployment that preview stages do not have. | `packages/console/app/src/middleware.ts:20-25`, `infra/console.ts:5-11` |
| `packages/containers` | CI build images (`base`, `bun-node`, `rust`, `tauri-linux`, `publish`) "to speed up GitHub Actions jobs", published to `ghcr.io/anomalyco/build/*`. Not agent sandboxes. | `packages/containers/README.md:1-30` |
| `packages/identity` | Brand assets only (logo marks as SVG/PNG); no code, not an auth service. | directory listing |
| `packages/function` | Two Cloudflare Workers: `api.opencode.ai` (first-generation share backend, GitHub App token exchange for the V1 GitHub Action, a support bridge) and the `opncd.ai` share host, now a "Session sharing has been discontinued" stub. | `packages/function/src/api.ts:16-387`, `packages/function/src/share.ts:148-171`, `infra/share.ts:17-20` |
| `packages/posts` | A blog at `opencode.ai/posts` (Astro); currently placeholder posts only. | `packages/posts/astro.config.ts:6-7`, `packages/posts/src/content/posts/` |
| `packages/stats` | "OpenCode Data", public model-usage rankings at `opencode.ai/data`, built hourly from inference logs; read-only, no user API. | `packages/stats/README.md:3`, `infra/stats.ts:70-126` |
| `services/www`, `services/update`, `services/files`, `services/changelog` | V2 site and docs (`opencode.ai/v2`), release metadata and update feeds (`opencode.ai/update/api/...`), public files, and the changelog page. | `services/README.md:6-11` |
| `beta.opencode.ai` / `app.opencode.ai` | The official web app (`packages/app`) deployed as a **static site with no bundled server** (`VITE_OPENCODE_SERVER_MODE: "none"`); it connects to a user's server by pairing. Stages: `production` → `app.opencode.ai`, `beta` → `beta.opencode.ai`. The server's default CORS allows `https://*.opencode.ai`. | `sst.config.ts:34-37`, `packages/app/README.md:79-80`, `packages/server/test/cors.test.ts:10` |

### C.3 OpenCode Console models (marketed as "Zen")

- **What it is:** "a list of models tested and verified by the OpenCode team"; sign in, add credits, get an API key, and use it from OpenCode or any other agent (`services/www/src/docs/content/console/models.mdx:1-16`). The V2 docs and code say "OpenCode Console", while the marketing site still says "Zen ... not for profit ... zero markups" (https://opencode.ai/zen; `packages/console/app/src/i18n/en.ts:159-219`). `/docs/zen` redirects to the V2 Console models page (cloud sub-report).
- **Catalog:** about 90 models across OpenAI, Anthropic, Google, xAI and open-weight labs (`console/models.mdx:35-124`); the public list `GET https://opencode.ai/inference/v1/models` returned 87 models on 2026-10-15 (cloud sub-report, WebFetch).
- **Pricing:** pay-as-you-go per million tokens from prepaid workspace credits; auto-reload ($20 when below $5 by default); card, Link, Alipay, UPI, WeChat Pay; HTTP 402 when credits run out; invoiced billing for credit agreements (`console/models.mdx:198-343`, `console/billing.mdx:6-84`). The docs disagree on the processing fee (4.6% + $0.31 in `billing.mdx:34-35` vs 4.4% + $0.30 in `models.mdx:317-319`).
- **Free tier:** "Free models include Big Pickle plus promotional models available at the time, with a quota of 200 requests/day" (`packages/console/app/src/i18n/en.ts:317`). Without a key, V2 enables the `opencode` provider with the placeholder key `public` and disables every paid model (`packages/core/src/plugin/provider/opencode.ts:336-361`); the app calls this "OpenCode Free" (`packages/app/src/runtime/i18n/en.ts:135`).
- **How clients connect:** provider ID `opencode`, model IDs `opencode/<model>`; protocol-specific endpoints under `https://opencode.ai/inference/...` (OpenAI chat/responses, Anthropic messages, Google generateContent) with `Authorization: Bearer <key>` (`console/api/inference.mdx:21-35`). In V2, `/connect` → "OpenCode Console account" runs a device-code login (or accepts a service-account key) and then reads `/api/v2/config` for the provider base URL and org header (`packages/core/src/plugin/provider/opencode.ts:109-146`; `console/api/index.mdx:114-141`).

### C.4 OpenCode Go (and Black)

- **Go:** a subscription for open coding models: **Go $10/month** and **Go Plus $40/month** (`services/www/src/docs/content/console/go.mdx:6-11`). Each model has a monthly dollar allowance enforced over rolling 5-hour (20%), weekly (50%) and monthly (100%) windows; an "extra usage" setting can fall back to credits (`go.mdx:115-221,351-355`). Go is limited to single-member workspaces (`go.mdx:32-35`). Provider ID `opencode-go`, endpoints under `https://opencode.ai/inference/go/...` (`go.mdx:367-426`); clients should send a User-Agent and a stable `x-opencode-session` header (`go.mdx:80-86`).
- **Black:** a premium-model subscription ("Black 20/100/200") whose enrollment is paused ("Black plan enrollment is temporarily paused", https://opencode.ai/black, per the cloud sub-report; `packages/console/app/src/routes/black/common.tsx:4-8`).

### C.5 Accounts and the Console

- **Workspaces and roles:** each account gets a "Personal" workspace; roles Member, Admin, Owner; email invitations expire after 7 days (`console/workspaces.mdx:12-60`, `console/members.mdx:9-17`).
- **SSO and SCIM:** OIDC (Google Workspace, Entra, Okta, Auth0, Ping) or SAML 2.0 included with every workspace; domain verification by TXT record; enforcement for the Console and `/connect`; SCIM 2.0 at `https://opencode.ai/console/scim/v2` (`console/sso.mdx:9-67`, `console/scim.mdx:9-80`).
- **Budgets:** workspace, per-user and per-service-account monthly budgets, reset on the 1st (UTC), HTTP 429 when exceeded (`console/budgets.mdx:9-74`).
- **Keys and providers:** service accounts own `oc_sk_…` keys with "Inference only" or "All" permission; bring-your-own-key provider connections with custom endpoints and pricing at `https://opencode.ai/inference/custom/<connection_id>` (`console/api/index.mdx:24-57`, `console/api/providers.mdx:20-26`). Policies reach V2 clients within about a minute (`console/index.mdx:30-35`). Hosted web search costs $0.01 per search (`console/websearch.mdx:6-8`). No seat fees (`billing.mdx:6`).
- **APIs a phone could call directly:** OAuth device flow (`POST https://opencode.ai/console/auth/device/code`, then poll `/auth/device/token`; refresh tokens are single-use) and `GET /api/v2/config` (providers, models, web search, the Console MCP server and policies); a Budgets API for admins (`console/api/index.mdx:59-152`, `console/api/budgets.mdx`). Useful for a "your Console account" screen, but **not needed** to drive sessions: provider sign-in normally happens on the server through `/connect` (A.17).

### C.6 Share service (history and status)

- **How it worked (V1):** `/share` created a public link (originally `https://opencode.ai/s/<last 8 chars of the session ID>`, later `opncd.ai`), the client pushed session, message and part updates to `api.opencode.ai` (Durable Object + R2) and the share page streamed them live over WebSocket; `/unshare` deleted it; config `share: "manual" | "auto" | "disabled"` (`packages/function/src/api.ts:16-204`; `packages/web/src/pages/s/[id].astro`; `packages/web/src/components/Share.tsx:98-168`, which rendered text, markdown, diffs, bash, code, errors and tool parts plus models, cost and token counts).
- **Status:** discontinued. `opncd.ai` answers every page with HTTP 410 "Session sharing has been discontinued ... This link and its content are no longer available", and accepts V1 share API calls without storing anything "so existing clients keep working" (`packages/function/src/share.ts:148-171`). V1 v1.19.1 and V2 v2.0.30 removed the commands (A.7). The homepage still advertises "Share a link to any session" (`packages/console/app/src/i18n/en.ts:92-93`).
- **Replacement:** none hosted; use `opencode session export [--sanitize]` / `import` (`packages/cli/src/commands/commands.ts:444-469`).

### C.7 Remote access relay (OpenTunnel)

OpenTunnel (https://github.com/anomalyco/opentunnel) is the only hosted piece in the connection path. `opencode service set remote true` (or `opencode pair --remote`, or Desktop **Settings → Pairing**) creates a tunnel; the service attaches a random 16-hex-character route and becomes reachable at `https://<route>.<tunnel host>` (`*.opentunnel.xyz`); the relay routes on SNI while TLS terminates on the user's machine, so "Traffic is end-to-end encrypted, and access requires your server password" (`packages/cli/src/services/remote-tunnel.ts:7-63`, `packages/cli/src/services/service-config.ts:164-212`, `packages/cli/src/commands/handlers/pair.ts:72-76`; cloud sub-report). The route persists; turning remote access off forgets it and devices must re-pair (`service-config.ts:192-197`). The tunnel exists only in service mode, not with `opencode serve` (`packages/cli/src/server-process.ts:182`). Details of the pairing protocol are in D.2.

### C.8 Hosted workspaces and cloud agents

| Capability | Status | Evidence |
| --- | --- | --- |
| First-party cloud agents / hosted sandboxes | **Not found** | No code, docs, changelog or site entry (cloud sub-report). |
| Provider-backed workspaces (`WorkspaceDriver`, `EnvironmentDriver`) | **SDK-only, no drivers ship**; removed from the V2 HTTP contract | `packages/core/src/workspace.ts`, `packages/core/src/workspace/driver.ts:26-88`; `V2_HTTP_API_AUDIT.md` ("Provider-backed workspaces are not part of the V2 HTTP contract") |
| `@opencode/sdk/workerd` (opencode core inside a Cloudflare Durable Object) | SDK-only; filesystem, search and PTY fail "until a remote sandbox backs them" | `services/www/src/docs/content/build/sdk/cloudflare.mdx`; `packages/server/src/workerd.ts:19-36` (cloud sub-report) |
| Hosted execution experiments | Not shipped | PR #40784 "feat(core): hosted workspace execution with modal driver" was closed unmerged on 2026-09-06; PR #44526 "feat(core): decouple workspace identity from provisioning" merged 2026-08-23 (`gh pr view`). A Modal environment driver was merged into the `v2` branch (#41118, 2026-08-07; #41177 "run modal sandboxes on the vm runtime", 2026-08-08) but is gone from the analyzed commit (no `packages/server/src/workspace/`; `modal` survives only as a model provider, `packages/core/src/plugin/provider/modal.ts`). No hosted-execution product is announced in the docs, changelog or site code. |
| Railway "cloud agents" running opencode 2 servers | Third-party | https://docs.railway.com/cloud-agents/opencode (web research, not re-checked) |
| Cloudflare Agents SDK "OpenCodeHarness" | Third-party (Cloudflare), experimental, 2026-10-12 | https://developers.cloudflare.com/changelog/post/2026-10-12-opencode-harness/ (cloud sub-report) |
| Cloudflare Sandbox recipe, Daytona plugin, other community hosts | Third-party | https://developers.cloudflare.com/sandbox/coding-agents/opencode/; `packages/web/src/content/docs/ecosystem.mdx` |
| V1 1.x "remote workspaces" / workspace adaptors | Shipped in V1 as plugin-provided adaptors (no first-party hosted adaptor) | "Plugins can now register custom workspace adaptors" (v1.4.4), "Basic implementation of remote workspace support" (v1.2.16), "Added workspace sync so adapter-backed workspaces can be discovered" (v1.14.42) (release notes) |
| GitHub Action on GitHub runners | Shipped, V1 only (C.9) | `github/README.md` |

### C.9 GitHub, GitLab and Enterprise

- **GitHub (V1):** `opencode github install` installs the `opencode-agent` GitHub App and writes a workflow; `/opencode` or `/oc` in issue and PR comments runs the agent on the user's runners and can open PRs (`github/README.md`; `packages/web/src/content/docs/github.mdx`). The action exchanges a GitHub OIDC token at `api.opencode.ai` for an installation token (`packages/function/src/api.ts:262-308`). V2's CLI has no `github` command; the V2 docs show `opencode run --standalone` in an ordinary Actions job (`services/www/src/docs/content/cli/commands.mdx:16-31`). For a phone user, commenting `/oc` from the GitHub app is the only "cloud agent"-like path today.
- **GitLab (V1):** a community CI component and GitLab Duo (`packages/web/src/content/docs/gitlab.mdx`).
- **Enterprise:** V1 docs describe per-seat enterprise with central config and SSO (`packages/web/src/content/docs/enterprise.mdx`); in V2 these team features are delivered through the Console (SSO, SCIM, policies, budgets) "free for any team size" (`console/billing.mdx:6`); https://opencode.ai/enterprise is a contact form.

---

## D. Mobile signals

### D.1 Bottom line

- **An official iOS app exists in public TestFlight beta.** The TestFlight page is for the "OpenCode iOS app" and tells testers to "run /pair on the latest version of opencode v2" (https://testflight.apple.com/join/EnFsKYQ1, fetched 2026-10-15). Dax Raad (@thdxr) announced the TestFlight on 2026-10-08, limited to 1,000 testers, and asked users to upgrade to v2.0.26 before pairing (https://x.com/thdxr/status/2108284341923049578, found independently by two researchers; not re-fetched). A tester reported "iOS app version: 0.1.0 (278)" with opencode 2.0.26 (issue #54627). The app is not on the App Store and is closed source: its repository `anomalyco/opencode-ios` is referenced in PR #53588 ("The iOS app is updated in anomalyco/opencode-ios#26") but is not public, and the monorepo has no mobile package. The monorepo's code refers to "The OpenCode iOS app" and mirrors that app's `VoiceHandoff.parse` (`packages/app/src/session/timeline/voice-delegation.ts:3-5`). Anomaly's 2.0 note says "We have native apps in the works that take advantage of this flow" (https://anoma.ly/notes/opencode-2-0). The desktop pairing page tells users to "Scan the code with the OpenCode app on another device" (`packages/gui-extensions/src/pairing/i18n/en.ts`).
- **Its headline feature is voice.** The iOS app runs voice calls with a voice agent that delegates work into opencode sessions as prompts starting with `Voice delegation.` followed by JSON (`instruction`, optional `voice` framing, `transcript_delta`) (`voice-delegation.ts:1-35`; sample header text in `packages/session-ui/src/storybook/current-session-fixtures.ts:1121-1142`). Desktop and web render these as **Voice** messages since v2.0.30 ("Display delegations from the iOS app as Voice messages", PR #54426, `CHANGELOG.md` on `dev`; `packages/session-ui/src/timeline/session-timeline-row.tsx:59`). "Like the iOS app, a Voice message's copy also offers the full prompt the session received" (`packages/session-ui/src/message/message-content.tsx:467`).
- **The official connection path is pairing.** `opencode pair` prints one-time links (`/auth/connect/<code>`, valid 5 minutes) and a QR code whose payload is JSON `{"code","urls"}` with only non-loopback addresses; `--remote` pairs through OpenTunnel and `--url` pairs through any external URL such as a Tailscale address (`packages/cli/src/commands/handlers/pair.ts:14-60,119-151`). Redeeming a code returns a 30-day session token used as the Basic-auth password (`packages/server/src/auth.ts:16-55`, `packages/app/src/servers/connect/pairing.ts:84-132`). The web app can scan the QR with the phone camera using the `qr-scanner` library (web-only; `packages/app/src/servers/connect/scanner.tsx:1-96`, `screen.tsx:226-240`), and notes that pages served over plain HTTP cannot open the camera (`camera.ts:30`).
- **The official mobile web path is the responsive web app installed as a PWA.** See D.3.
- **No push notifications.** No APNs, Web Push or push-subscription code exists in `packages/` (searches for `apns`, `PushManager`, `pushManager`, `web-push` find nothing; the PWA service worker only precaches assets, `packages/app/vite.pwa.ts:17-55`). The web app uses the in-page `Notification` API only while it is open (`packages/app/src/runtime/platform/web.ts:29`).
- **No Android app** and no official statement of one was found in the code; web findings are in D.4.

### D.2 Remote access building blocks (what an iOS client must speak)

| Building block | Facts | Source |
| --- | --- | --- |
| Background service | One shared server per user; localhost only by default; port 49374 (macOS/Linux/WSL) or 45278 (Windows); `opencode service set hostname\|port\|password\|cors\|env`; `opencode service status` prints the address. | `services/www/src/docs/content/cli/web.mdx:26-102`, `cli/index.mdx` |
| Standalone server | `opencode serve --hostname 0.0.0.0 --port 4096` prints the URL and password; clients connect with `opencode --server <url>`. | `cli/web.mdx:104-128` |
| Pairing | `server.pair` (`POST /api/pair`) issues a single-use code (16 random bytes, base64url, 5-minute TTL); `server.connect` (`GET /auth/connect/{code}`) gives browsers a cookie and API clients a token. | `packages/server/src/pairing.ts:7-33`; `packages/protocol/openapi.json` |
| Tokens | `<expiry>.<HMAC>` signed with a key derived from the server password; 30-day TTL; changing the password revokes all tokens. | `packages/server/src/auth.ts:16-55` |
| Auth transport | HTTP Basic (`opencode:<password or token>`), or `?auth_token=<base64(user:pass)>` (used for WebSockets), or the same-origin cookie `opencode_session_<port>`. Note: the client docs show an `authorization: Bearer ...` header example (`services/www/src/docs/content/build/client/index.mdx:37-56`), but the built-in middleware only parses Basic, `auth_token` and the cookie (`packages/server/src/middleware/authorization.ts:32-39,58-71`). | as cited |
| Remote tunnel | `opencode pair --remote` enables OpenTunnel (https://github.com/anomalyco/opentunnel), asks for consent the first time ("This will expose your OpenCode server to the internet. Traffic is end-to-end encrypted, and access requires your server password."), `--yes` for scripts; remote URLs use a persistent random subdomain (v2.0.26). | `cli/web.mdx:53-75`; `packages/cli/src/commands/handlers/pair.ts:72-110`; `CHANGELOG.md` v2.0.26 |
| Desktop pairing UI | **Settings → Pairing → Pair device** shows a QR code and copyable link via OpenTunnel (v2.0.29, PR #55306). | `CHANGELOG.md` |
| Legacy links | Servers before one-time links used `/connect#<credentials>` or `/connect?data=<credentials>`; the app rejects them with a "legacy link" message. | `packages/app/src/servers/connect/pairing.ts:68-75`, `redeem.ts:25` |
| V1 servers | No pairing; use `--hostname`, `--mdns` (Bonjour name `opencode.local`), `--cors` and `OPENCODE_SERVER_PASSWORD`; `opencode attach <url>` lets a TUI share a web server's sessions. | `packages/web/src/content/docs/web.mdx`; `opencode --help` (v1.18.23) |

### D.3 Mobile and PWA support in the official web app

- **Installable PWA.** `packages/app/manifest.json` declares `display: "standalone"`, maskable icons and a dark theme color; `index.html` sets `viewport-fit=cover`, `interactive-widget=resizes-content`, `apple-mobile-web-app-capable` and a `black-translucent` status bar (`packages/app/index.html:6-16`). A Workbox service worker precaches the build but never intercepts `/api` or `/auth` so pairing links reach the server (`packages/app/vite.pwa.ts:17-35`). Chrome/Edge "Install" works even behind an authenticating proxy (v2.0.27, PR #53905).
- **Phone layout.** The app switches to a phone layout below 768 px (`createMediaQuery("(max-width: 767px)")`) and has a setting for the phone titlebar position, `top` (default) or `bottom` (`packages/app/src/shell/titlebar/titlebar.tsx:65-66`, `packages/app/src/settings/model.tsx:120,283`). Comments show deliberate iOS Home Screen tuning ("iOS blurs page content just below the status bar in Home Screen web apps ... as ChatGPT's phone header does", `titlebar.tsx:53-54`), keyboard inset handling ("iOS retains the home-indicator inset above its keyboard", `packages/app/src/runtime/platform/keyboard.ts:3-38`) and iOS momentum-scroll handling in the timeline virtualizer (`packages/app/src/session/timeline/virtualizer.tsx:375`).
- **Tested on phones.** End-to-end tests run the timeline on "Pixel 7" and "iPhone 13" profiles at 390×844 with touch (`packages/app/e2e/regression/mobile-timeline-scroll.spec.ts:20-28`).
- **V1 history.** Mobile bottom navigation, an improved iOS PWA shell and mobile session/home layouts shipped in v1.17.10 (2026-06-24); responsive settings in v1.1.41; mobile toast layout in v1.18.10 (release notes).

### D.4 Issues, PRs, roadmap and third parties

All items below were checked with `gh pr view` / `gh issue view` against `anomalyco/opencode` on 2026-10-15 (state, dates and titles as shown there).

| Item | State and dates | What it says |
| --- | --- | --- |
| Issue #6536 "[FEATURE]: Mobile App" | Closed as not planned on 2026-07-24; opened 2025-12-31 | Maintainer `rekram1-node`: "We will have a react native mobile app its on the roadmap" (2025-12-31). The shipped app's technology is not public [unconfirmed: its repository `anomalyco/opencode-ios` is not public (`gh api repos/anomalyco/opencode-ios` returns 404), the TestFlight post (https://x.com/thdxr/status/2108284341923049578, read through api.fxtwitter.com) does not say, and a web search found nothing; PR #53088 names iOS `AVPlayer` as a client need, which fits a native app but does not prove one]. |
| Issue #10288 "Feature Request: Mobile version of OpenCode (Android/iOS/Web UI)" | Open; 2026-01-23 | Long-running community request. |
| Issue #49316 "[FEATURE]:apk availability" | Open; 2026-09-16 | Android request; no Android app found. |
| Issue #35943 "V2: Add service QR pairing and connection-details endpoint" | Closed; 2026-07-08 | Team issue that led to V2 QR pairing. |
| PR #49291 "feat(desktop): add local device pairing" | Merged 2026-09-22 | Desktop pairing QR (local network). |
| PR #49971 "feat(cli): pair with direct server links" | Merged 2026-09-22 | CLI pairing links (the later "legacy" `/connect#...` format). |
| PR #50970 "feat(server): pair with one-time connect links" | Merged 2026-09-24 | `POST /api/pair` + `GET /auth/connect/:code`. |
| PR #53588 "feat(cli): include every pairing address in QR codes" | Merged 2026-10-06 | QR carries all reachable URLs. |
| PR #53837 "feat(cli): pair remotely through OpenTunnel" | Merged 2026-10-08 | `opencode pair --remote`. |
| PR #53905 "fix(app): make the web app installable as a PWA" | Merged 2026-10-08 | PWA install. |
| PR #55306 "feat(desktop): pair devices through remote access" | Merged 2026-10-14 | Settings → Pairing → Pair device. |
| PR #54426 "feat(app): show voice delegations from the iOS app as Voice messages" | Merged 2026-10-15 | Voice messages in desktop/web (v2.0.30). A related PR #55122 "render voice call delegations as Voice messages" is still open. |
| PR #47374 "feat(app): add opt-in PWA push notifications" | Closed unmerged; 2026-09-04 | Web Push for the PWA was proposed and not merged. |
| PRs #1593 (2025-08-04), #3060 (2025-10-09, "Web desktop fixes, early iOS build"), #10624 (2026-01-26, "feat(mobile): add React Native mobile app") | All closed unmerged | Community mobile apps were not accepted into the monorepo. |
| Issues #54596, #54627 ("mobile: iOS app cannot connect through pair --remote"), #54624, #54871 ("pair QR encodes custom JSON payload instead of plain connect URL"), #55027 ("beta.opencode.ai QR code scanner rejects opencode pair QR code") | Opened 2026-10-11 to 10-13; #54596 and #54627 closed, the others open | Early beta friction with OpenTunnel and the JSON QR payload. A native client should accept both the JSON payload and plain `/auth/connect/<code>` links, as the official parser does (`pairing.ts:28-51`). |

**Open mobile-web gaps** (all verified open with `gh issue view` unless noted): #39628 "Remote approval of permission requests from mobile / second device" (07-30); #48748 "On-screen keyboard covers composer input on mobile web (portrait)" (09-13); #50635 "Web terminal on-screen key bar for mobile (Esc/Ctrl/Tab/arrows)" (09-22); #49961 "notifications fail in Android PWA" (09-19); #51075 "local service on Tailscale receives unauthenticated requests" (09-24); #55673 "session view stuck ... after network switch on remote Safari/Firefox client" (10-15). Closed: #10721 "iOS Safari/Firefox: session history rolls back after backgrounding" (01-26). Also open: #48556 (community showcase of an unofficial native Android client) and #52575 ("Implement /share and /unshare for v2 sessions"), which was overtaken by the share shutdown. These map directly to features a native app can do better: actionable approval notifications, keyboard-safe composer, a terminal key bar, reliable reconnection after network changes.

**How people reach opencode from phones today** (web research): the V1 web UI over the network (`opencode web --hostname 0.0.0.0` or `--mdns`, often behind Tailscale or a reverse proxy), SSH from a phone terminal app, V2 pairing (LAN, `--url`, or `--remote`), the official TestFlight app, and third-party apps.

**Third-party mobile clients (all unofficial; details from the web research, not re-verified):**

| Client | Platforms | Notes |
| --- | --- | --- |
| Paseo (https://paseo.sh/opencode, https://github.com/getpaseo/paseo) | iOS, Android, desktop, web | Local daemon plus optional end-to-end-encrypted relay or Tailscale; multi-agent. |
| OpenChamber (https://github.com/openchamber/openchamber) | Desktop, web/PWA, VS Code, iOS, Android | One-time QR pairing through its own encrypted relay. |
| CodeNomad (https://github.com/NeuralNomadsAI/CodeNomad) | Desktop, browser | Requires opencode V2 ≥ 2.0.7; "Remote Control" pairs a phone; listed in the opencode ecosystem docs. |
| Sesori (https://www.sesori.com/) | iOS, Android | Desktop bridge plus relay, end-to-end encrypted. |
| OpenCode Mobile (https://getopencode.app/) | Android, iOS TestFlight | Tailscale guide, voice mode. |
| opencode_ios_client (https://github.com/grapeot/opencode_ios_client) | iOS, iPadOS, visionOS | Open source native client; LAN or HTTPS server. |
| OpenLens (https://apps.apple.com/us/app/-/id6759910797) | iOS | Bonjour/mDNS discovery and QR pairing. |
| OpenClient for OpenCode (https://apps.apple.com/us/app/openclient-for-opencode/id6763641767) | iPhone, iPad | Works with V1 or V2 servers; voice dictation; Pro in-app purchase. |
| WhisperCode, OpenCodeM, KKCode, Portal, others | iOS / web | WhisperKit speech input; Live Activities and widgets; Expo/LAN/Tailscale clients (App Store and GitHub links in the web research). |

The opencode README asks such projects to state they are not affiliated, citing "opencode-mobile" as an example name (`README.md`, "Building on OpenCode"). A deeper ecosystem comparison is in the sibling research file `03-mobile-clients-landscape.md`.

---

## Appendix 1. Terminal client: commands, keybinds and presentation

Paths are in `packages/tui/src/` unless stated otherwise. V1 facts come from the V1 docs (`packages/web/src/content/docs/tui.mdx`, `keybinds.mdx`) and from strings in the installed 1.18.23 binary; the V1 docs are stale in places (for example there is no `/details` command in the binary). Note that `packages/tui/src/config/v1/*` in the V2 repo is a migration schema for old `tui.json` files, not the V1 release.

### A1.1 V2 slash commands (client-side)

| Command | Aliases | What it does | Default key | Source |
| --- | --- | --- | --- | --- |
| `/sessions` | `/resume`, `/continue` | Session switcher | `<leader>l` | `app.tsx:729-738` |
| `/new` | | New session (keeps agent and model) | `<leader>n` | `app.tsx:739-765` |
| `/clear` | | Close the current tab, then start a new session | | `app.tsx:766-792` |
| `/open` | `/projects`, `/project` | Recent sessions and projects; → shows worktrees; ctrl+n creates a worktree | `ctrl+o` | `app.tsx:793-805`, `component/dialog-open.tsx` |
| `/models` | | Model picker (Favorites, Recent, by provider; ctrl+f favorite; ctrl+a connect) | `<leader>m` | `app.tsx:868-877`, `component/dialog-model.tsx` |
| `/agents` | | Agent picker | `<leader>a` | `app.tsx:914-922` |
| `/mcps` | | MCP servers dialog (space toggles/connects/signs in) | | `app.tsx:923-931`, `component/dialog-mcp.tsx` |
| `/variants` | `/thinking`, `/effort` | Pick a model variant (reasoning effort) | `ctrl+t` cycles | `app.tsx:949-965` |
| `/connect` | | Connect a provider or integration, manage accounts | | `app.tsx:975-988`, `component/dialog-integration.tsx` |
| `/highlights` | | Release highlights | | `app.tsx:989-999` |
| `/settings` | | Settings dialog | | `app.tsx:1000-1009`, `component/dialog-config.tsx` |
| `/status` | | Status dialog (MCP servers) | `<leader>s` | `app.tsx:1010-1018` |
| `/update` | | Install an update (when an updater exists) | | `app.tsx:1019-1029` |
| `/pair` | `/web` | Pairing links and QR code ("Pair device") | | `app.tsx:1030-1038`, `component/dialog-pair.tsx` |
| `/restart` | | Restart the background service | | `app.tsx:1039-1059` |
| `/reload` | | Reload server configuration | | `app.tsx:1060-1075` |
| `/debug` | | Debug info for bug reports | | `app.tsx:1076-1084` |
| `/themes` | | Theme picker with live preview | | `app.tsx:1085-1093` |
| `/help` | | Help (points to ctrl+p) | | `app.tsx:1116-1124` |
| `/exit` | `/quit`, `/q` | Exit | ctrl+c / ctrl+d on empty prompt, `<leader>q` | `app.tsx:1134-1140` |
| `/cd <dir>` | | Set the directory before a session exists, or move the session | | `component/prompt/index.tsx:262-312` |
| `/editor` | | Edit the prompt in `$VISUAL`/`$EDITOR` | `<leader>e` | `component/prompt/index.tsx:548-578` |
| `/skills` | | Skill picker (inserts `@skill`) | | `component/prompt/index.tsx:579-616` |
| `/worktrees` | | Move session between workspaces/worktrees; create, delete, refresh | | `component/prompt/index.tsx:617-626` |
| `/rename [title]` | | Set the title, or regenerate it when empty | `ctrl+r` | `routes/session/index.tsx:904-918` |
| `/timeline` | | List of user messages → Message Actions (Jump, Revert, Copy, Fork) | `<leader>g` | `routes/session/index.tsx:919-933`, `routes/session/dialog-message.tsx` |
| `/fork` | | Fork the whole session or from a user message | | `routes/session/index.tsx:934-950` |
| `/compact` | | Compact now | `<leader>c` | `routes/session/index.tsx:951-974` |
| `/undo` | | Interrupt, stage revert of the last user message, restore its text | `<leader>u` | `routes/session/index.tsx:975-1006` |
| `/redo` | | Clear the staged revert | `<leader>r` | `routes/session/index.tsx:1007-1023` |
| `/copy` | | Copy the transcript | | `routes/session/index.tsx:1186-1206` |
| `/export` | | Export as Markdown or JSON (options: thinking, tools, sanitize) to a temp file or clipboard | `<leader>x` | `routes/session/index.tsx:1207-1250` |
| `/terminal` | | New embedded PTY terminal pane | | `component/session-frame.tsx:245-255` |
| `/btw <question>` | | Side question answered from context, not added to the transcript (uses `session.generate`) | | `feature-plugins/prompt/btw.tsx:50-114` |
| `/stats` | | Usage statistics page | | `feature-plugins/system/stats.tsx:196-210` |
| `/plugins` | | Plugin manager | | `feature-plugins/system/plugins.tsx:331-340` |
| `/diff` | | Diff viewer (docked beside the session; `f` toggles full screen, v2.0.30) | | `feature-plugins/system/diff-viewer.tsx:1310-1351` |

**Server-side commands** appear in the same autocomplete and run through `session.command`: `/init`, `/review`, MCP prompts as `/<server>:<prompt>`, and custom commands (`component/prompt/index.tsx:1147-1150,1310-1327`; `packages/core/src/plugin/command.ts`). Slash autocomplete triggers only at the start of the prompt (v2.0.28). Argument-taking client commands and shell-mode prompts cannot be queued; server commands can.

### A1.2 V1 slash commands (1.18.23)

- Documented: `/connect`, `/compact` (`/summarize`), `/details`, `/editor`, `/exit` (`/quit`, `/q`), `/export` (opens Markdown in `$EDITOR`), `/help`, `/init`, `/models`, `/new` (`/clear`), `/redo`, `/sessions` (`/resume`, `/continue`), `/themes`, `/thinking` (show/hide thinking), `/undo` (`packages/web/src/content/docs/tui.mdx:78-262`).
- Present in the binary: also `/agents`, `/mcps`, `/variants`, `/org` (`/orgs`, `/switch-org`), `/status`, `/debug`, `/diff`, `/skills`, `/move`, `/warp` and `/workspaces` (experimental flag), `/share`, `/unshare`, `/rename`, `/timeline`, `/fork`, `/timestamps`, `/copy`, `/review`; `/details` is only a palette toggle ("Show/Hide tool details").
- Only in V2: `/open`, `/settings`, `/pair`, `/restart`, `/reload`, `/update` (V1 got `/update` in v1.19.0), `/highlights`, `/stats`, `/plugins`, `/btw`, `/cd`, `/worktrees`, `/terminal`. Only in V1: `/share`, `/unshare`, `/timestamps`, `/org`, `/move`, `/warp`, `/workspaces`. `/thinking` toggles thinking display in V1 but is an alias of `/variants` (effort) in V2.

### A1.3 Default keybinds

- **V2** lives in the global `~/.config/opencode/cli.json` (hot-reloaded; schema `https://opencode.ai/v2/cli.json`; `OPENCODE_CLI_CONFIG_CONTENT` overrides); leader `ctrl+x` with a 2 s timeout; values are strings, arrays or `{key, event, preventDefault, fallthrough}`; `"none"`/`false` disables (`config/keybind.ts:28-352`; `services/www/src/docs/content/cli/keybinds.mdx`, `cli/config.mdx`).
- **V1** lives in `tui.json` (`$schema https://opencode.ai/tui.json`, `OPENCODE_TUI_CONFIG`), with snake_case IDs (`packages/web/src/content/docs/keybinds.mdx:8-233`); the mapping to V2 IDs is in `config/v1/keybind.ts:251-414`.

| Area | V2 defaults (selection) |
| --- | --- |
| App | exit ctrl+c / ctrl+d / `<leader>q`; command palette ctrl+p; editor `<leader>e`; sidebar `<leader>b`; status `<leader>s`; suspend ctrl+z |
| Sessions | new `<leader>n`; list `<leader>l`; open menu ctrl+o; export `<leader>x`; timeline `<leader>g`; rename ctrl+r; interrupt esc (press twice within 5 s); background blocking tools ctrl+b; compact `<leader>c`; queued prompts `<leader>q`; undo/redo `<leader>u` / `<leader>r`; copy last answer `<leader>y` |
| Subagents | first child ↓ (opens the subagent picker), next/previous child →/←, parent ↑ |
| Tabs | next/previous ctrl+tab / ctrl+shift+tab and alt+↓/↑; next/previous unread alt+shift+↓/↑; close `<leader>w`; reopen ctrl+shift+t; select `<leader>1-0` / ctrl+1-0 |
| Models / agents | model list `<leader>m`; cycle recent models f2 / shift+f2; agent list `<leader>a`; **agent cycle shift+tab** (V1: Tab); variant cycle ctrl+t |
| Prompt | submit enter (**steers** while busy); **queue `<leader>return`**; newline shift/ctrl/alt+enter or ctrl+j; paste ctrl+v; view images `<leader>i`; history ↑/↓ at buffer edges; Emacs-style editing keys |
| Terminal panes | toggle `<leader>t`; select `<leader>↓`; close `<leader>↑`; focus panes `<leader>←/→` |
| Permission prompt | ←/→ or h/l choose, enter confirm, esc reject, ctrl+f full screen |
| Diff viewer | j/k, `]`/`[` hunks, n/p files, b tree, v split/unified, f full screen, m mark reviewed, `?` help |

Many commands have no default key and are reached via the palette (ctrl+p): settings, pair, restart, reload, fork, move, cd, thinking toggle, verbosity cycle, MCP list, connect, variant list, stash commands and others (`config/keybind.ts:46-300`).

### A1.4 Composer details (V2 TUI)

- `@` at a word start searches files (server `fs.find`, 20 results), plus skills, references (`@alias` or `@alias/path`) and non-primary, non-hidden agents; ranking uses frecency stored in `state/frecency.jsonl`; `@src/a.ts#20-45` attaches a line range (`component/prompt/autocomplete.tsx:244-575`).
- ctrl+v pastes images as inline `data:` attachments labelled `[Image N]` (PDFs as `[PDF N]`); pasting file paths attaches images/PDFs up to 32 paths and 20 MiB; SVG is inserted as text (`component/prompt/index.tsx:468-491`, `component/prompt/local-attachment.ts`). Pastes of 3+ lines or over 150 characters collapse to `[Pasted ~N lines]` unless `prompt.paste: "full"` (`component/prompt/index.tsx:1437-1466`).
- `!` on an empty prompt enters shell mode ("Run a command…") and sends `session.shell` (`component/prompt/index.tsx:958-1014,1305-1309`).
- History (50 entries, `state/prompt-history.jsonl`), stash (50 entries; "Stash prompt", "Stash pop", "Stash list"), per-tab drafts, external editor, and IDE context: the active editor file or selection (VS Code over WebSocket, or Zed) is added as hidden context with a footer label (`component/prompt/index.tsx:160-253,709-923`).
- Metadata row under the composer: agent (in its color), "auto" tag when auto-accept is on, model, provider and variant (`component/prompt/metadata.tsx:8-87`).
- While busy, Enter **steers** and `<leader>return` **queues**; a dock lists queued prompts (enter steers, ctrl+d deletes, ctrl+u returns it to the composer); a pending steer can be moved to the queue or deleted (`routes/session/index.tsx:646-694,2257-2270`; `services/www/src/docs/content/cli/tui.mdx:17`).

### A1.5 Session view details (V2 TUI)

- **Switcher**: server-side search (150 ms debounce, 50 results, top-level sessions), groups "Pinned", "Today" and dates, gutter markers `!` (permission), `?` (question), spinner (running); ctrl+a toggles current directory vs all projects; pin ctrl+f, delete ctrl+d twice, rename ctrl+r (`component/dialog-session-list.tsx:27-292`).
- **Tabs** (default on): per-tab unread, attention (permission/question), busy state (`context/session-tabs.tsx:152-177`).
- **Children**: a child session swaps the composer for a subagent picker; permissions and questions from descendants bubble up to the parent; the footer shows "N subagents · N shells" (`routes/session/index.tsx:198-215,1466-1482`; `feature-plugins/prompt/footer.tsx:22-90`).
- **Display settings** (`cli.json` `session.*`): thinking shown/hidden (default hidden), markdown rendered/source, grouping, verbosity low/medium/high, scrollbar, image preview, tokens per second (`component/dialog-config.tsx:47-131`). Tool and shell output collapse and expand on click. There is no "tool details" toggle in V2.
- **Assistant footer**: "Agent · model · duration · N tok/s · interrupted", errors, and "⚠ Retrying in Ns · attempt N" (`routes/session/index.tsx:1881-1931,2394`).
- **Exit epilogue** prints the session title and `opencode -s <id>` to continue (`util/presentation.ts:26-35`).

### A1.6 Sidebar and status

- **V2 sidebar** (auto when wider than 120 columns, `<leader>b`): session title (shimmer while generating), **Context** ("N tokens", "N% used", "$X spent"; tokens from the last assistant turn against the model limit), MCP status dots, a "Connect provider" getting-started card, and `dir:branch` with worktree actions. No LSP, todo or modified-files sections (`routes/session/sidebar.tsx`; `feature-plugins/sidebar/context.tsx:20-41`; `util/session.ts:46-66`).
- **V2 prompt footer**: spinner and "esc interrupt" while running; `~/dir:branch` or worktree progress; "N subagents · N shells"; "12,345 (45%) · $0.12"; hints such as "shift+tab agents" and "ctrl+p commands" (`feature-plugins/prompt/footer.tsx`).
- **V1 sidebar**: Context (tokens, % used, spent), MCP, LSP ("LSPs will activate as files are read"), Todo and Modified Files, in that order, with a "Getting started" / "Connect provider" card in the footer (sidebar plugins at tag v1.18.23: `packages/tui/src/feature-plugins/sidebar/context.tsx`, `mcp.tsx`, `lsp.tsx`, `todo.tsx`, `files.tsx` with `order` 100-500, and `footer.tsx`).

### A1.7 Permission and question prompts (TUI)

- **Permission**: replaces the composer with "△ Permission required" and the tool title; edits show a diff (split view above 120 columns); options **Allow once**, **Always allow** (only when the request proposes save patterns; it explains "This will always allow … for this project"), **Reject**; rejecting a child-session request can include a reason; auto-accept (`--auto` or `session.permissions: "autoaccept"`) replies `once` automatically on the client (`routes/session/permission.tsx:22-611`; `context/permission.tsx:13-15`). V1: once / always ("for the rest of the current OpenCode session") / reject, plus palette "Enable/Disable auto-approve permissions" (`packages/web/src/content/docs/permissions.mdx:197-203`).
- **Questions are generic forms in V2**: field types string, number, integer, boolean, multiselect and external URL, with conditional `when` rules (`packages/schema/src/form.ts:21-120`); the `question` tool maps each question to a string or multiselect field with a custom answer (`packages/core/src/tool/plugin/question.ts:12-133`). The TUI shows field tabs, "Field N of M", a review step, number keys 1-9 to pick, space to toggle, and an always-present "Type your own answer" row (`routes/session/form.tsx:642-765`). MCP elicitation forms can also appear on the home screen (`routes/home.tsx:36-120`).

### A1.8 Notifications, sounds and terminal title

- V2 `cli.json` → `attention`: `notifications` (default false), `sound` (default false), `volume` 0.4, per-event `sounds` for default, question, permission, error, done and subagent_done (`config/index.tsx:99-111,306-311`; `services/www/src/docs/content/cli/config.mdx:214-244`).
- Events: form created → "Input needs response"; permission asked → "Permission needs input"; session done → "Session done"; session failed → error text and a toast. Notifications fire only while the terminal is blurred and never for subagents; sounds always play (`feature-plugins/system/notifications.ts:16`, `attention.ts:35-181`).
- Terminal title "OC | <session title>"; OSC 8 hyperlinks (`FORCE_HYPERLINK=1`). The program-status reporting of working and waiting sessions listed in the v2.0.29 changelog (PR #55172, OSC 7501 in `packages/tui/src/context/program-status.ts`) was reverted with the OpenTUI 0.6 upgrade before that release was tagged (PR #55300, merged 2026-10-14 04:27 UTC; `release: v2.0.29` commit at 09:03 UTC contains the revert), so no released V2 build has it and the analyzed commit has no such file (corrected 2026-10-15).
- V1 `tui.json` → `attention.enabled` (default false) with notifications and sound (`packages/web/src/content/docs/tui.mdx:388-397`).

### A1.9 Themes

Built-in themes (both lines): aura, ayu, carbonfox, catppuccin (+ frappe, macchiato), cobalt2, cursor, dracula, everforest, flexoki, github, gruvbox, kanagawa, lucent-orng, material, matrix, mercury, monokai, nightowl, nord, one-dark, **opencode** (default), orng, osaka-jade, palenight, rosepine, solarized, synthwave84, tokyonight, vercel, vesper, zenburn, and **system** (derived from the terminal palette) (`theme/v1.ts:37-70`, `theme/index.ts:26-37`). V2 uses a new token format with nine-step hues, semantic groups and interaction states, in `~/.config/opencode/themes/*.json` or `.opencode/themes/*.json`; V1 theme JSON is migrated automatically (`services/www/src/docs/content/cli/theme.mdx`; `theme/index.ts:53-61`).

### A1.10 CLI subcommands, V1 vs V2

| Command | V1 1.18.23 | V2 2.0.x |
| --- | --- | --- |
| default (TUI) | ✓ with `--port`, `--hostname`, `--mdns`, `--cors`, `-m`, `--agent`, `--fork`, `--auto`, `--mini` | ✓ talks to the shared service; `--standalone`, `--server <url>`, `--auto`, `-c`, `-s`, `--prompt` (`packages/cli/src/commands/commands.ts:6-58`) |
| `mini` | `--mini` flag | `opencode mini` (`commands.ts:340-375`) |
| `run` | ✓ (`--command`, `--share`, `--attach`, `--variant`, ...) | ✓ (`-m provider/model#variant`, `--agent`, `--format json`, `--auto`; permissions are auto-rejected unless `--auto`) (`commands.ts:376-417`; `packages/cli/src/run/noninteractive.ts`) |
| `attach <url>` | ✓ | ✗ (use `--server`) |
| `serve` | ✓ | ✓ |
| `web` | ✓ | ✗ (web UI is served by the service; use `pair`) |
| `service start\|restart\|status\|stop\|get\|set\|unset` | ✗ | ✓ |
| `pair [--url] [--remote] [-y]` | ✗ | ✓ |
| `reload`, `api` | ✗ | ✓ |
| `acp` | ✓ | ✓ |
| `auth` / `providers` | `providers` (alias `auth`) | `auth list\|login\|logout\|switch\|export\|import` |
| `mcp` | add, list, auth, logout, debug | list, add, auth, logout |
| `plugin` | `plugin <module>` | list, add, check, update, remove |
| `session` | list, delete | list, delete, export `--sanitize`, import |
| `export` / `import` | top level | under `session` |
| `stats`, `models`, `upgrade`, `uninstall` | ✓ | ✓ |
| `agent`, `db`, `github`, `pr`, `completion` | ✓ | ✗ |

### A1.11 Dialogs, toasts and TUI-directed server events

- Dialog inventory a native client should have equivalents for: command palette, session list and rename, open/projects, workspaces and worktree naming, model, variant, agent, MCP, integration (key, OAuth, code, command sub-views), settings, status, debug, theme list, help, highlights, update, pair, skills, stash, image preview, shell output, timeline, message actions, fork, queued prompts, export options and result, `/btw` answer, plugins, diff base, plus the in-place permission prompt, question/form prompt, reconnecting overlay, migration overlay and toasts (`app.tsx`, `component/*`, `ui/*`).
- Toast variants info, success, warning, error with an optional action button (`ui/toast.tsx:11-18,160`).
- Server events aimed at TUIs: `tui.toast.show`, `tui.command.execute`, `tui.session.select`, `tui.prompt.append` (`app.tsx:1294-1315`). The transcript also renders LaTeX and Mermaid through built-in plugins (`plugin/builtins.ts:12-26`).

---

## Appendix 2. V2 event names by feature area

Event `type` literals defined in `packages/schema/src/*.ts` (delivered on `GET /api/event`, which is "Volatile by contract: a slow consumer overflows and fails the stream, and events during disconnection are missed", `packages/protocol/src/groups/event.ts:44-52`). The protocol report covers payloads and ordering; this list only maps events to the features above. The `message.*` names come from V1-shaped schemas kept for compatibility (`packages/schema/src/v1/session.ts`, re-exported via `packages/schema/src/legacy-event.ts`), and `lsp.updated` from `packages/schema/src/lsp-event.ts`; `permission.asked` is a V2 ephemeral event (`packages/schema/src/permission.ts:45`).

| Area | Events |
| --- | --- |
| Session lifecycle | `session.created`, `session.updated`, `session.deleted`, `session.renamed`, `session.forked`, `session.moved`, `session.metadata.updated`, `session.viewed`, `session.idle`, `session.status` |
| Execution and streaming | `session.execution.started/succeeded/failed/interrupted`, `session.step.started/streamed/ended/failed`, `session.text.started/delta/ended`, `session.reasoning.started/delta/ended`, `session.retry.scheduled`, `session.error` |
| Tools | `session.tool.input.started/delta/ended`, `session.tool.called`, `session.tool.progress`, `session.tool.success`, `session.tool.failed` |
| Inputs | `session.inbox.enqueued/delivered/cancelled/delivery.changed`, `session.synthetic`, `session.shell.started/ended`, `session.skill.activated`, `session.message.content.updated` |
| Agent and model | `session.agent.selected`, `session.model.selected`, `agent.updated`, `model.updated`, `provider.updated` |
| Usage | `session.usage.recorded`, `session.usage.updated` |
| Revert and compaction | `session.revert.staged/cleared/committed`, `session.compaction.started/delta/ended/failed`, `session.compacted` |
| Approvals and forms | `permission.asked`, `permission.replied`, `session.permissions`, `form.created`, `form.replied`, `form.cancelled` |
| Instructions and diffs | `session.instructions.updated`, `session.diff`, `file.edited`, `filesystem.changed`, `vcs.branch.updated` |
| Terminals and shells | `pty.created/updated/exited/deleted`, `shell.created/exited/deleted` |
| Integrations and catalog | `integration.updated`, `credential.updated`, `credential.switched`, `mcp.status.changed`, `mcp.tools.changed`, `mcp.resources.changed`, `command.updated`, `command.executed`, `skill.updated`, `reference.updated`, `plugin.updated`, `websearch.updated`, `config.updated`, `project.updated` |
| Worktrees and workspaces | `worktree.ready/failed/resolved/updated`, `workspace.ready/failed/status` |
| Server | `server.connected`, `installation.updated`, `location.shutdown`, `global.disposed` |
| TUI control | `tui.toast.show`, `tui.command.execute`, `tui.session.select`, `tui.prompt.append` |
| Legacy (V1-shaped) | `message.updated`, `message.removed`, `message.part.updated`, `message.part.delta`, `message.part.removed`, `lsp.updated` |

---

## Verification pass (2026-10-15)

This pass resolved the 12 lines that carried the first pass's "unverified" marker (the marker legend plus 11 tagged claims), checked five claims that the product spec takes from this report, and fixed the wrong or unverified claims it found along the way. Sources: the clone at `d0732ea` (`d0732ea` and the `release: v2.0.30` commit share the parent `775d1d0`, and the release commit only bumps package versions, so the analyzed code is v2.0.30 plus one docs commit), the GitHub API (`gh` against `anomalyco/opencode`, its `v1` branch and V1 tags, `anomalyco/homebrew-tap` and `Homebrew/homebrew-core`), the npm registry, api.fxtwitter.com, two web searches and one page fetch. This pass changed text only within existing lines, so the line numbers in the "Claim" column are valid before and after it.

| # | Claim (short) | Outcome | Evidence (URL or command) |
| --- | --- | --- | --- |
| 1 | Marker legend (line 9) | Legend updated (not a claim) | — |
| 2 | A.7 (line 141): v1.18.x keeps `/share`; do old clients fail gracefully? | VERIFIED: they fail softly (placeholder link that opens the 410 page; `import` stops with "Failed to fetch share data") | `packages/function/src/share.ts:161-171`; `gh pr view 55716 -R anomalyco/opencode`; `gh api "repos/anomalyco/opencode/contents/packages/opencode/src/share/share-next.ts?ref=v1.18.23"` and `.../cli/cmd/import.ts?ref=v1.18.23` |
| 3 | A.16 (line 214): phone finishes MCP OAuth via the attempt's `mode` or a pasted code | CORRECTED: MCP attempts are always `mode: "auto"` with a listener on the server's `127.0.0.1`, so there is no code to paste; takeaway 7 tightened to match | `packages/core/src/mcp/oauth.ts:388,448,520-521`; `packages/core/src/integration.ts:60-73`; `packages/core/src/mcp/index.ts:204-210` |
| 4 | A.28 (line 299): status of the autonomous goal command #45379 | CORRECTED: reverted about two hours after merging (#49866); goal and todo state is back in review (#54799, #55744, open) | `gh pr view 45379`, `gh pr view 49866`, `gh pr list -R anomalyco/opencode --state all --search "goal in:title"` |
| 5 | A.28 (line 308): OpenCode Go launched "around late February" | CORRECTED: turn of February and March (docs 02-27/28, `/go` landing page 03-03, news report on 03-07 says "last week") | `gh api "repos/anomalyco/opencode/commits?path=packages/console/app/src/routes/go&sha=dev"`; `gh pr view 15415`; https://letsdatascience.com/news/opencode-launches-10-monthly-open-source-agent-f29289b1 |
| 6 | B.7 (line 425): LaTeX in the GUI | VERIFIED: KaTeX math in the Markdown worker | `packages/ui/src/context/marked-parser.tsx:1-26`; `packages/session-ui/src/components/markdown.worker.ts:4,42` |
| 7 | B.8 (line 437): effect of "Show agent" | VERIFIED: default Off; controls the composer agent picker and agent-cycle shortcuts | `packages/app/src/runtime/i18n/en.ts:839-841`; `packages/app/src/settings/model.tsx:281`; `packages/app/src/providers/models/selection.tsx:101,206-211`; `packages/app/src/composer/commands.tsx:71,79` |
| 8 | B.12 (line 497): renderer consumer of `opencode://` links | VERIFIED: none; the main process only uses `opencode://console/authorized?window=<id>` to pick the window to focus | `packages/desktop/src/main/lifecycle/deep-link.ts:1-14`; `packages/desktop/src/main/lifecycle/index.ts:47-62`; `grep -rn -e opencode:deep-link -e deepLinks packages` |
| 9 | C.2 (line 529): Console dashboard source lives in `anomalyco/platform` | REMOVED: speculative; the only reference is the Pulumi stack `anomalyco/platform/production`, and GitHub has no public repository of that name | `services/update/README.md:104-106`; `gh api repos/anomalyco/platform` (404) |
| 10 | C.8 (line 576): product status of hosted execution | VERIFIED: not shipped and not announced; a Modal environment driver was merged into `v2` in August and later removed | `gh pr view 41118`, `gh pr view 41177`, `gh pr view 40784`; no `packages/server/src/workspace/` in `d0732ea`; no hosted-execution mention in `CHANGELOG.md` or `services/www/src/docs/content` |
| 11 | D.4 (line 629): technology of the official iOS app | UNCONFIRMED: no public statement found | `gh api repos/anomalyco/opencode-ios` (404); https://api.fxtwitter.com/thdxr/status/2108284341923049578; one web search; `gh pr view 53088` (mentions iOS `AVPlayer`) |
| 12 | A1.8 (line 773): where program-status reporting (PR #55172) is implemented | CORRECTED: it was reverted by PR #55300 before v2.0.29 was tagged, so no release has it | `gh pr view 55300`; `gh api "repos/anomalyco/opencode/contents/packages/tui/src/context/program-status.ts?ref=v2.0.29"` (404); `gh api repos/anomalyco/opencode/compare/def5d948e...042d0832f` (v2.0.29 is 6 ahead, 0 behind the revert) |
| S1 | Spec: V2.0.0 was tagged on 2026-09-11 | VERIFIED: lightweight tag on commit `63f7cee` dated 2026-09-11T23:46Z; npm `@opencode/cli` 2.0.0 published 2026-09-11T23:44Z | `gh api repos/anomalyco/opencode/git/refs/tags/v2.0.0`; https://registry.npmjs.org/@opencode/cli (`time["2.0.0"]`) |
| S2 | Spec: share links discontinued on 2026-10-15; `opncd.ai` answers HTTP 410 | VERIFIED: PR #55716 merged 2026-10-15T17:42Z (domain handover #55784 at 18:09Z); V1 v1.19.1 release notes published 19:19Z; `opncd.ai` returned 410 "Session sharing has been discontinued" when checked | `gh pr view 55716`; `gh release view v1.19.1 -R anomalyco/opencode`; `curl -s -o /dev/null -w '%{http_code}' https://opncd.ai/` (410) |
| S3 | Spec: neither desktop nor web notifies on permission requests | VERIFIED; B.9 now cites the open issue and the unmerged fixes | `packages/app/src/shell/notifications/notification.tsx:219-275`; `gh issue view 51507`; `gh pr view 51524`, `gh pr view 48808` |
| S4 | Spec: V1 still maintained (1.19.1) and offers `opencode upgrade --major` | VERIFIED: added in v1.19.0 (absent in 1.18.35 and in the installed 1.18.23). The published tap formula is 1.19.1; the 1.18.34 seen on this Mac comes from a tap checkout last pulled 2026-10-05. A.28 now describes the upgrade paths, including Homebrew | `gh release view v1.19.0 -R anomalyco/opencode`; https://registry.npmjs.org/opencode-ai (`latest` 1.19.1, 2026-10-15T19:20Z); `gh api "repos/anomalyco/opencode/contents/packages/opencode/src/cli/cmd/upgrade.ts?ref=v1.18.35"`; `gh api repos/anomalyco/homebrew-tap/contents/opencode.rb`; `git -C "$(brew --repo anomalyco/tap)" log -1` |
| S5 | Spec: V2 does not pass PDF, audio or video attachments to the model | CORRECTED: PDFs are passed (to models that declare PDF input; otherwise an error note replaces them); audio and video are dropped. The V2 docs are out of date | `packages/core/src/session/runner/to-llm-message.ts:75-84`; `packages/core/src/session/model-request.ts:122-147,297`; `packages/core/test/session-runner-message.test.ts:502-530`; `gh pr view 43799` |
| X1 | A.2 (line 92): "PDF ... not included in the model request" and "convert PDFs to images" | CORRECTED (see S5) | as S5 |
| X2 | A.18 (line 229): the TUI reports program status (v2.0.29) | CORRECTED (see 12) | as 12 |
| X3 | A.28 (line 299): X post cited for the July beta announcement | CORRECTED: the post is dated 2026-08-21; the Threads post ID encodes 2026-07-10 | https://api.fxtwitter.com/opencode/status/2090794386413986201 |
| X4 | A.11 (line 174): "[V1 endpoint unverified]" for todos | VERIFIED: `GET /session/:sessionID/todo` | `gh api "repos/anomalyco/opencode/contents/packages/opencode/src/server/routes/instance/httpapi/groups/session.ts?ref=v1.19.1"` |
| X5 | A1.6 (line 762): "[layout details unverified]" for the V1 sidebar | VERIFIED: section order and footer card from the V1 sources | `gh api "repos/anomalyco/opencode/contents/packages/tui/src/feature-plugins/sidebar/context.tsx?ref=v1.18.23"` (and `mcp.tsx`, `lsp.tsx`, `todo.tsx`, `files.tsx`, `footer.tsx`) |
| X6 | Line 7: the analyzed branch is "version 2.0.29" | CORRECTED: 2.0.29 is only the package version; the code equals the v2.0.30 release plus one docs commit | `gh api repos/anomalyco/opencode/commits/f16ef9a` (parent `775d1d0`, version bumps only); `git -C <clone> log -1` (`d0732ea`, parent `775d1d0`) |

Outcome counts for the 11 tagged claims: 5 VERIFIED, 4 CORRECTED, 1 REMOVED, 1 UNCONFIRMED. Spec claims: 4 VERIFIED, 1 CORRECTED. Other fixes: 4 CORRECTED (X1, X2, X3, X6) and 2 VERIFIED (X4, X5). No claim needs a browser.
