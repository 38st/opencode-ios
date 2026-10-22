# opencode on mobile: the ecosystem, connectivity and notification architecture

Research date: 2026-10-15. Scope: official plans, third-party mobile and remote clients, analogous tools for other coding agents, and the connectivity and push-notification architecture for a native iOS/iPadOS client of `opencode serve` / `opencode service`.

Conventions: every non-obvious claim carries a source link. Claims first left unconfirmed were checked in a verification pass on 2026-10-15 (last section): rewritten claims end in "(corrected 2026-10-15)", and anything still open is marked **[unconfirmed: …]**. Star counts and dates were read on 2026-10-15 and will drift.

## Executive summary

1. **The opencode team now ships an official iOS app, as a TestFlight beta announced 2026-10-08** and capped at 1,000 testers. It pairs with `opencode pair` and reaches machines anywhere through **OpenTunnel**, Anomaly's new blind TLS relay in which the user's machine holds the certificate key. There is no official Android app and no published push design: the beta's notifications rely on a server plugin kept in a private repository (corrected 2026-10-15). The app's distinctive feature is voice calls that delegate work to sessions (Section 1).
2. **The third-party field is crowded but shallow.** There are over 25 iOS apps and repos, including OpenLens, OpenClient, BYOT, Tailscode, Remote for OpenCode, opencode companion, KKCode, grapeot's client and WhisperCode, plus multi-agent remotes (Paseo, Happier, Sesori) and wrappers (OpenChamber, CodeNomad). Their recurring gaps:
   - breakage across the opencode v2 API change;
   - no reliable background push without bolted-on infrastructure;
   - no support for opencode's own pairing links or OpenTunnel (except OpenLens, OpenCody and alvarolorentedev's Opencode Mobile for pair links) (corrected 2026-10-15);
   - weak iPad layouts;
   - laggy long transcripts;
   - abandonment (Section 2).
3. **Analogous products have converged** on outbound-only host connections, QR pairing, shared control rather than takeover, presence-aware push, Live Activities and biometric step-up for approvals. Among relay-based coding-agent tools, only OpenChamber seals push content; Happy, Happier, Paseo, Remodex, Sesori, Moshi and WhatCode send plaintext previews through Expo, FCM or their own relay. Remote for OpenCode (content-free CloudKit nudges) and the small omnicus/opencode2-mobile (allowlisted category text plus an encrypted routing envelope) avoid the problem by sending no content (Sections 3 and 5; corrected 2026-10-15).
4. **Connectivity recommendation** (Section 4):
   - A multi-endpoint server model fed by opencode's own pairing payloads.
   - OpenTunnel as the zero-config default for "anywhere".
   - LAN and Tailscale (the system app) as private fast paths.
   - Custom HTTPS with custom headers (Cloudflare Access, ngrok) and an in-app SSH tunnel as power-user paths.
   - Embedded TailscaleKit and our own end-to-end relay only later and only if needed. WebRTC is not worth it.
   - A rigorous reconnect/resync engine, because opencode's event stream is live-only.
5. **Push recommendation** (Section 5):
   - An opencode **plugin** watches events and seals a per-device payload (HPKE).
   - A small open-source **relay** we run holds the APNs key and forwards a generic alert plus ciphertext.
   - A **Notification Service Extension** decrypts it.
   - **Actions** ("Allow once" behind device unlock, "Reject", text reply) go back over the direct path, never through the relay.
   - **Live Activities** carry only coarse state.
   - An opt-in **zero-relay mode** (background wait or ntfy) serves privacy maximalists.

---

## 1. Official plans: what Anomaly / the opencode team ships

### 1.1 Bottom line

- **There is an official iOS app, in public TestFlight beta since 2026-10-08.** Dax Raad announced it: "ok testflight for OpenCode iOS app, limited to 1000 ... it definitely needs polish but it's already so useful and we all love using it ... be sure to upgrade to OpenCode v2.0.26 before pairing" ([X post](https://x.com/thdxr/status/2108284341923049578), mirrored on [Threads](https://www.threads.com/@thdxr/post/DePu1MBGd76/ok-testflight-for-open-code-i-os-app-limited-to-it-definitely-needs-polish-but/)). The public TestFlight page is titled "Join the OpenCode beta" and says to "run /pair on the latest version of opencode v2" ([TestFlight](https://testflight.apple.com/join/EnFsKYQ1)).
- **It is not on the App Store yet.** opencode.ai/download lists only the CLI, the desktop app and editor extensions; it has no iOS, Android or TestFlight entry ([download page](https://opencode.ai/download)).
- **No official Android app has been announced.** The only maintainer statement found is from 2025-12-31: "We will have a react native mobile app its on the roadmap" ([issue #6536](https://github.com/anomalyco/opencode/issues/6536)). Requests for an APK remain open with no maintainer reply ([#49316](https://github.com/anomalyco/opencode/issues/49316), [#10288](https://github.com/anomalyco/opencode/issues/10288)).
- **The official mobile-web path is the opencode web UI.** Every opencode server serves it, and it is also hosted at `app.opencode.ai` (production) and `beta.opencode.ai` (beta) ([app README](https://github.com/anomalyco/opencode/blob/dev/packages/app/README.md)). It installs as a PWA and has a long tail of open mobile bugs (Section 1.5).
- **The official answer to "reach my machine from anywhere" is `opencode pair --remote`**, which exposes the background service through Anomaly's own OpenTunnel service: a blind TLS relay in which the developer's machine holds the certificate key ([PR #53837](https://github.com/anomalyco/opencode/pull/53837), [OpenTunnel README](https://github.com/anomalyco/opentunnel)). Since v2.0.29 the desktop app's "Pair device" button *only* pairs through OpenTunnel. The LAN, VPN and custom-address options were removed ([PR #55306](https://github.com/anomalyco/opencode/pull/55306), [changelog](https://opencode.ai/changelog)).
- **No official push notification design has been published.** The opencode repository contains no APNs code (a code search for `apns` returns nothing). A PR that would have let the server send Web Push straight to PWAs was closed without merging ([PR #47374](https://github.com/anomalyco/opencode/pull/47374)). The TestFlight app does have notifications. A tester saw a "notifications" sheet right after starting a first session ([X](https://x.com/peterpme/status/2108295873822142861)). Testers report that notifications need a server plugin, `github:anomalyco/opencode-ios#main::path:packages/notify-plugin`, which would not install because that repository is not public; the GitHub API still returned 404 on 2026-10-15 ([X](https://x.com/nematollahi97/status/2108301296205775166), [#54483](https://github.com/anomalyco/opencode/issues/54483)). How that plugin reaches APNs is not public (corrected 2026-10-15).

How this was checked: I searched opencode.ai (download, docs, changelog) and the anomalyco/opencode issues and PRs for mobile, iOS, android, phone, remote, PWA, push notification and tailscale. GitHub Discussions are disabled on the repository (`has_discussions: false`), so issues and PRs are the public record. I also checked team members' public posts.

### 1.2 Timeline

| Date | Event | Source |
|---|---|---|
| 2025-08-04 | Community PR "Add React Native mobile app for opencode" closed without merging | [PR #1593](https://github.com/anomalyco/opencode/pull/1593) |
| 2025-10 | Community PR "Web desktop fixes, early iOS build" (Tauri) closed without merging | [PR #3060](https://github.com/anomalyco/opencode/pull/3060) |
| 2025-12-31 | Maintainer: "We will have a react native mobile app its on the roadmap" | [#6536](https://github.com/anomalyco/opencode/issues/6536) |
| 2026-01-26 | Community PR "feat(mobile): add React Native mobile app" closed without merging | [PR #10624](https://github.com/anomalyco/opencode/pull/10624) |
| 2026-01-31 | Dax: "finally got around to setting up an always on opencode server so i can run sessions on any device from anywhere" (date decoded from the post ID) | [X](https://x.com/thdxr/status/2017691649384620057), quoted by [waylonwalker.com](https://go.waylonwalker.com/tags/opencode/) |
| 2026-07-08 | Team-filed issue "V2: Add service QR pairing and connection-details endpoint" for "OpenCode clients such as OpenMobile", including "Send the finalized schema to the OpenMobile client owner" | [#35943](https://github.com/anomalyco/opencode/issues/35943) |
| 2026-07-08 | Ryan Vogel (GitHub bio "work @ opencode", company @anomalyco) publishes a script that generates an "OpenMobile onboarding QR" for a V2 service exposed over private **Tailscale Serve**. Payload: `{type:"opencode.mobile.server",version:1,url,username,password,name}` | [gist](https://gist.github.com/R44VC0RP/da505bcc925c91dee0160a4c7577c1a3) |
| 2026-07-10 | Dax: "we are playing with this. it's why we added `opencode pair` in v2" (quoted in a comment on #10288; date decoded from the post ID) | [X](https://x.com/thdxr/status/2075690050805739682), [#10288 comment](https://github.com/anomalyco/opencode/issues/10288) |
| 2026-09-16 to 09-22 | Desktop local-network pairing QR; CLI direct `/connect#<credentials>` links | [PR #49291](https://github.com/anomalyco/opencode/pull/49291), [PR #49971](https://github.com/anomalyco/opencode/pull/49971) |
| 2026-09-17 | Voice launches in the iOS app (date inferred from "every format iOS has sent since voice launched (Sep 17)") | [PR #54426](https://github.com/anomalyco/opencode/pull/54426) |
| 2026-09-24 | One-time pairing links (`POST /api/pair`, `GET /auth/connect/:code`) replace password-bearing links | [PR #50970](https://github.com/anomalyco/opencode/pull/50970) |
| 2026-10-06 | Pairing QR codes include every reachable address | [PR #53588](https://github.com/anomalyco/opencode/pull/53588) |
| 2026-10-08 | v2.0.26: `opencode pair --remote` via OpenTunnel. Remote URLs use "a persistent random subdomain". TestFlight announced the same day | [PR #53837](https://github.com/anomalyco/opencode/pull/53837), [changelog](https://opencode.ai/changelog), [X](https://x.com/thdxr/status/2108284341923049578) |
| 2026-10-11 | v2.0.27: the first `pair --remote` warns that it "will expose your OpenCode server to the internet" and asks for consent | [PR #54561](https://github.com/anomalyco/opencode/pull/54561) |
| 2026-10-11 to 10-14 | First beta incidents: an opentunnel.xyz regional outage (Cloudflare 525s from European colos), DNS filters (Pi-hole) blocking `*.opentunnel.xyz`, stuck pending tunnels, and a QR payload that generic scanners and an old beta.opencode.ai build cannot read | [#54596](https://github.com/anomalyco/opencode/issues/54596), [#54627](https://github.com/anomalyco/opencode/issues/54627), [#54624](https://github.com/anomalyco/opencode/issues/54624), [#54871](https://github.com/anomalyco/opencode/issues/54871), [#55027](https://github.com/anomalyco/opencode/issues/55027) |
| 2026-10-14 | v2.0.29: Desktop Settings → Pairing → "Pair device" always uses OpenTunnel | [PR #55306](https://github.com/anomalyco/opencode/pull/55306), [changelog](https://opencode.ai/changelog) |
| 2026-10-15 | v2.0.30: desktop and web "Display delegations from the iOS app as Voice messages" | [changelog](https://opencode.ai/changelog), [PR #54426](https://github.com/anomalyco/opencode/pull/54426) |

### 1.3 What is known about the official iOS app

- **Distribution:** public TestFlight link, capped at 1,000 testers ([TestFlight](https://testflight.apple.com/join/EnFsKYQ1), [X](https://x.com/thdxr/status/2108284341923049578)). A user reported build "0.1.0 (278)" on 2026-10-11 ([#54627](https://github.com/anomalyco/opencode/issues/54627)).
- **Pairing:** scan the QR code from `opencode pair` / `opencode pair --remote` or paste the printed link. The official docs describe the flow as "Scanning the QR code from the OpenCode app, or pasting the link into its server address field, connects the app the same way" ([web docs](https://github.com/anomalyco/opencode/blob/dev/services/www/src/docs/content/cli/web.mdx)). Connection failures surface as "OpenCode connection error / Phase: Pair / Couldn't reach the OpenCode server" ([#54627](https://github.com/anomalyco/opencode/issues/54627)).
- **Voice calls:** the iOS app has a voice agent. Voice calls send each request into a session as plain prompt text: a `Voice delegation.` header followed by JSON with the spoken `instruction`, the voice agent's optional `voice` framing, the transcript and an optional call-log attachment. iOS renders these as "Voice messages", and desktop and web now do the same ([PR #54426](https://github.com/anomalyco/opencode/pull/54426), [PR #55122](https://github.com/anomalyco/opencode/pull/55122)). This is the clearest signal of the app's product direction: hands-free delegation to a running agent rather than a pocket IDE.
- **Internal name:** "OpenMobile" appears in a team-filed issue and a team member's gist ([#35943](https://github.com/anomalyco/opencode/issues/35943), [gist](https://gist.github.com/R44VC0RP/da505bcc925c91dee0160a4c7577c1a3)). The earliest pairing design (July 2026) assumed Tailscale Serve with HTTPS and MagicDNS, before OpenTunnel existed.
- **Closed source:** the opencode monorepo has no mobile package (the `packages/` directory holds app, cli, desktop, server, tui, web and others). The app's notification plugin is fetched from `anomalyco/opencode-ios`, which returns 404 to the public ([#54483](https://github.com/anomalyco/opencode/issues/54483)), so the app's code is most likely in that private repository.
- **Multiple servers:** supported. Asked whether it could have "several opencode VMs connected to it", Dax replied "it can do that already" ([X](https://x.com/thdxr/status/2108290378243739659)) (corrected 2026-10-15).
- **Notifications:** yes, through a server plugin from a private repository (Section 1.1) (corrected 2026-10-15).
- **UI technology:** probably native Swift, not the React Native that the 2025 roadmap comment mentioned. This is an inference from two clues. opencode's tests quote prompts "as the OpenCode iOS app has sent them (`VoiceHandoff.format`)", and those prompts use the pretty-print style of Foundation's `JSONEncoder` (a space before each colon, keys sorted), which JavaScript's `JSON.stringify` does not produce ([voice-delegation.test.ts](https://github.com/anomalyco/opencode/blob/dev/packages/app/src/session/timeline/voice-delegation.test.ts)). A team PR also refers to the app's `OpenCodePairingLink.decode` ([PR #53946](https://github.com/anomalyco/opencode/pull/53946)) (corrected 2026-10-15).
- **Still unknown:** Live Activities, iPad-specific layouts, App Store timing and pricing **[unconfirmed: none of these is mentioned on the TestFlight page, in the 41 replies to Dax's announcement (read through api.fxtwitter.com), in the opencode.ai changelog and docs, or in anomalyco/opencode issues and PRs; the app's repository is private]**.

### 1.4 The official connectivity and auth model (what any client must interoperate with)

These are the interfaces a third-party iOS client should speak natively, because every opencode v2 user now has them.

- **Background service.** `opencode service` runs a shared server that listens only on localhost by default. The default port is 49374 on macOS, Linux and WSL and 45278 on Windows. The password is randomly generated by default, and `opencode service set hostname|port|password|cors|remote` changes the settings ([web docs](https://github.com/anomalyco/opencode/blob/dev/services/www/src/docs/content/cli/web.mdx), [PR #54561](https://github.com/anomalyco/opencode/pull/54561)). `opencode serve` still runs a standalone foreground server for systemd, Docker and remote hosts (same docs).
- **One-time pairing.** `POST /api/pair` (basic auth) returns `{ code, expires_in: 300 }`. The code is held in memory and works once. `GET /auth/connect/:code` needs no auth: it returns `{ token }` to API clients, or sets a 30-day `HttpOnly` cookie and redirects for browsers ([PR #50970](https://github.com/anomalyco/opencode/pull/50970)).
- **Session tokens** are stateless: `expiry.hmac(key)`, with the key derived from the server password. Changing the password signs out every device, and signing out a single device is not supported ([PR #50970](https://github.com/anomalyco/opencode/pull/50970)). A token can be sent as the Basic-auth password or as a Bearer header ([client docs](https://github.com/anomalyco/opencode/blob/dev/services/www/src/docs/content/build/client/index.mdx)).
- **QR payload.** The QR code holds JSON, not a URL: `{"code":"…","urls":["http://192.168.x.x:49374"]}` for LAN, or `["https://<route>.<tunnel>.opentunnel.xyz"]` for remote ([#54871](https://github.com/anomalyco/opencode/issues/54871), [#55027](https://github.com/anomalyco/opencode/issues/55027)). The reference parser in the web app races the code against every URL, prefers the first URL if it answers within a second, and stores the returned token as the server password. Its comment: "The token works on every address of the server" ([pairing.ts](https://github.com/anomalyco/opencode/blob/dev/packages/app/src/servers/connect/pairing.ts)). Pre-September servers used `/connect#<base64url({username,password})>` links ([PR #49971](https://github.com/anomalyco/opencode/pull/49971)), and the July OpenMobile prototype used `{type:"opencode.mobile.server",version:1,…}` ([gist](https://gist.github.com/R44VC0RP/da505bcc925c91dee0160a4c7577c1a3)).
- **OpenTunnel remote access.**
  - It is a "blind TLS tunnel". The hosted server reads only the TLS ClientHello (SNI) and forwards the still-encrypted stream over a bridge WebSocket to the client that claimed the route. The local client "owns the certificate private key, terminates TLS, and forwards decrypted traffic to the local application unchanged" ([OpenTunnel README](https://github.com/anomalyco/opentunnel)).
  - Certificates are wildcard certificates from ZeroSSL via ACME DNS-01; the client generates the key and sends only a CSR ([protocol.md](https://github.com/anomalyco/opentunnel/blob/master/docs/protocol.md)). The service runs on Fly.io with PlanetScale MySQL, since 2026-10-10 as one machine in each of eleven regions behind one anycast address; the README's deployment section still says `iad` only ([server.md](https://github.com/anomalyco/opentunnel/blob/master/docs/server.md#multiple-regions), [fly.toml](https://github.com/anomalyco/opentunnel/blob/master/fly.toml)) (corrected 2026-10-15). Only the tunnel hostname appears in certificate-transparency logs, so opencode's random route subdomain keeps the URL unguessable ([README](https://github.com/anomalyco/opentunnel), [remote-tunnel.ts](https://github.com/anomalyco/opencode/blob/dev/packages/cli/src/services/remote-tunnel.ts)).
  - The relay does see each visitor's real IP address, the SNI hostname, and traffic timing and volume ([trust-boundary.md](https://github.com/anomalyco/opentunnel/blob/master/docs/trust-boundary.md)).
  - opencode tells users that "Traffic is end-to-end encrypted, and access requires your server password" ([PR #54561](https://github.com/anomalyco/opencode/pull/54561)).
  - For an iOS client this is ordinary HTTPS with a publicly trusted certificate: plain `URLSession` works, with no special crypto and no ATS exceptions.
- **Event stream.** `GET /api/event` is Server-Sent Events ([OpenAPI spec](https://github.com/anomalyco/opencode/blob/dev/packages/protocol/openapi.json)). The client docs say: "Subscriptions are live-only, with no replay or automatic reconnection … A late native subscriber receives the current `server.connected` marker, not past business events" ([client docs](https://github.com/anomalyco/opencode/blob/dev/services/www/src/docs/content/build/client/index.mdx)). Keep-alives differ by version:
  - The v2 server merges an SSE *comment* line (`: heartbeat`) into the stream every 15 s, and sends `Cache-Control: no-cache, no-transform` and `X-Accel-Buffering: no` ([v2 handlers/event.ts](https://github.com/anomalyco/opencode/blob/dev/packages/server/src/handlers/event.ts)).
  - v1 sends a `server.heartbeat` data event every 10 s ([v1 event.ts](https://github.com/anomalyco/opencode/blob/v1.19.1/packages/opencode/src/server/routes/instance/httpapi/handlers/event.ts)).
  - A native watchdog must therefore count raw bytes, comments included, not just parsed events. The official web client still suffers from half-open "zombie" SSE connections and from Safari failing permanently after a Wi-Fi/cellular switch ([#51857](https://github.com/anomalyco/opencode/issues/51857), [#55673](https://github.com/anomalyco/opencode/issues/55673)). A native client must therefore implement its own heartbeat watchdog, reconnect logic and full state resync.
- **Events relevant to notifications (v2 schema):**
  - `permission.asked` and `permission.replied`, with replies `once`, `always` or `reject` ([permission.ts](https://github.com/anomalyco/opencode/blob/dev/packages/schema/src/permission.ts)).
  - `form.created`, `form.replied` and `form.cancelled`. Questions are "forms" in v2 ([form.ts](https://github.com/anomalyco/opencode/blob/dev/packages/schema/src/form.ts)).
  - `session.status` (`idle`, `busy`, `retry`) ([session-status-event.ts](https://github.com/anomalyco/opencode/blob/dev/packages/schema/src/session-status-event.ts)).
  - `session.execution.started`, `succeeded`, `failed` and `interrupted` ([session-event.ts](https://github.com/anomalyco/opencode/blob/dev/packages/schema/src/session-event.ts)).
  - These events are declared "ephemeral", so a notifier has to be listening live. A server-side plugin is the natural place for it.
  - The REST endpoints for answering are `GET /api/permission/request` and `POST /api/session/{sessionID}/permission/{requestID}/reply` ([OpenAPI spec](https://github.com/anomalyco/opencode/blob/dev/packages/protocol/openapi.json)).
- **Plugins** can `ctx.event.subscribe()` to the public event stream and `ctx.permission.list/get/reply()` pending requests ([plugin docs](https://github.com/anomalyco/opencode/blob/dev/services/www/src/docs/content/build/plugins/index.mdx)). This is the hook a push-forwarding plugin would use.
- **mDNS:**
  - v1 documented `opencode web --mdns` and a `server.mdns` config key ([v1 docs](https://github.com/anomalyco/opencode/blob/dev/packages/web/src/content/docs/web.mdx)).
  - In v1 code, this publishes a Bonjour `_http._tcp` service named `opencode-<port>` on host `opencode.local`, with TXT `path=/` ([mdns.ts at v1.19.1](https://github.com/anomalyco/opencode/blob/v1.19.1/packages/opencode/src/server/mdns.ts)).
  - The v2 source tree on `dev` has no mDNS module, and the v2 docs and desktop pairing UI no longer offer LAN discovery. Bonjour discovery therefore only finds v1 servers (or servers advertised by a companion) **[v2 absence inferred from the source tree]**.

### 1.5 Official mobile web / PWA status

- The web UI is responsive and served by every server. The hosted beta build at `beta.opencode.ai` starts with no server. You add one by address and password, by pasting an `opencode pair` link, or with **Scan QR code** ([app README](https://github.com/anomalyco/opencode/blob/dev/packages/app/README.md), [#55027](https://github.com/anomalyco/opencode/issues/55027)). Hosted origins are cross-origin to your server, and `opencode service set cors` exists for such clients ([web docs](https://github.com/anomalyco/opencode/blob/dev/services/www/src/docs/content/cli/web.mdx)).
- Open mobile-web problems at the time of writing:
  - The keyboard covers the composer ([#48748](https://github.com/anomalyco/opencode/issues/48748)).
  - Enter submits on mobile with no way to insert a newline ([#55549](https://github.com/anomalyco/opencode/issues/55549)).
  - Question options are cut off ([#51770](https://github.com/anomalyco/opencode/issues/51770)).
  - There is no on-screen key bar for the web terminal ([#50635](https://github.com/anomalyco/opencode/issues/50635)).
  - Notifications fail in the Android PWA ([#49961](https://github.com/anomalyco/opencode/issues/49961)).
  - The PWA manifest lacks an `any`-purpose icon ([#47466](https://github.com/anomalyco/opencode/issues/47466)).
  - Features break on plain-HTTP origins such as Tailscale IPs because `crypto.randomUUID` is missing outside secure contexts ([#46168](https://github.com/anomalyco/opencode/issues/46168)).
- A user asked for remote permission approval from a phone on 2026-07-30. The thread contains the best public discussion of approval UX: "silence must not read as yes", one pending action should produce one notification, and the approval screen must show the command or diff ([#39628](https://github.com/anomalyco/opencode/issues/39628)).

### 1.6 Implications for our client

1. **Compete with a free first-party app.** It pairs with one QR scan and is backed by the team that controls the protocol. Our client must win on depth and polish: iPad, multi-server, notifications, reliability, review and diff UX, offline history. It cannot win on "it connects".
2. **Speak the official pairing protocol from day one.** That means the `{code, urls}` QR payload, `/auth/connect/:code` links, OpenTunnel URLs, and legacy `/connect#…` and manual URL plus password entry. A user who already ran `opencode pair --remote` for the official app should be able to scan the same QR code with ours.
3. **Treat OpenTunnel as the default internet path, but not the only one.** It is new, run by one vendor, and already had a regional outage and DNS-blocklist failures in its first week. Tailscale, SSH and LAN fallbacks are worth having (Section 4).
4. **Push is where the official stack has nothing public yet.** The beta already has notifications, but they depend on a plugin from a private repository (Section 1.1), so there is no public contract to build on (corrected 2026-10-15). A good relay-based push design (Section 5) is a real differentiator, but should be built so it can adopt an official mechanism later.

---

## 2. Third-party clients for opencode

### 2.1 How to read this section

- App Store data (price, version, date, rating) comes from Apple's public lookup API on 2026-10-15, US storefront. Ratings are per storefront and tiny for most apps.
- GitHub stars and last-push dates come from the GitHub API on the same day.
- "v1/v2" says which opencode server API a client speaks. opencode 2.x moved the HTTP API under `/api/*` and broke most v1 clients for a while. Examples: an OpenLens review titled "Not compatible with v2 server", and the open issue [grapeot #169](https://github.com/grapeot/opencode_ios_client/issues/169).
- No third-party client was found that knowingly supports OpenTunnel URLs from `opencode pair --remote`. Any client that accepts an arbitrary HTTPS URL plus password works with them in principle.

### 2.2 Native iOS / iPadOS clients (App Store)

| App | Developer, source | Tech | Price | Store (version, date, rating) | Connection | Push / background | Notes |
|---|---|---|---|---|---|---|---|
| [OpenLens – OpenCode client](https://apps.apple.com/us/app/openlens-opencode-client/id6759910797) | Martyn Pekala, [MIT, 66★](https://github.com/martynpekala/OpenLens) | SwiftUI, iOS 26+ | Free | 2.0, 2026-10-02, 4.67 (6) | QR, Bonjour (v1 `--mdns`), manual URL, deep links. Accepts opencode pair links ([README](https://github.com/martynpekala/OpenLens#pair-with-opencode-v2)), as OpenCody also does (corrected 2026-10-15). Optional "OpenLens Remote" Mac gateway behind your own Cloudflare Tunnel/Access with an HPKE end-to-end channel | No background push while closed (README) | Inbox for permissions and questions; Review tab with diffs and per-update revert; model and variant switching; cost insights; Live Activities; Shortcuts. v1 and v2 |
| [OpenClient for OpenCode](https://apps.apple.com/us/app/openclient-for-opencode/id6763641767) | Nicolas Toporcov, [source-available, PolyForm Noncommercial, 29★](https://github.com/ntoporcov/openclient) | SwiftUI, iOS 17+ | Freemium: free tier 5 prompts a day and 1 session; Pro $4.99/mo or $29.99 lifetime ([site](https://open-client.com/)) | 1.0.24, 2026-10-12, 4.0 (6) | Direct URL with Basic auth (LAN, Tailscale, HTTPS) | "OC Notify": Web Push through a plugin, your own HTTPS endpoint and a companion PWA. No hosted relay | Most elaborate iPad layout advertised: multi-column projects, sessions and chat (judgment from listings, not tested; corrected 2026-10-15); Live Activities; widgets and Control Center controls; queue, steer and side questions on v2; per-response diffs. Complaints: lag, price changes |
| [BYOT Coding Agent](https://apps.apple.com/us/app/byot-coding-agent/id6782403920) | Bogeybot LLC, [MIT](https://github.com/steventsao/byot) | Swift, iOS 17+ | Free | 1.0.32, 2026-10-13, 5.0 (2) | HTTPS with Basic auth (usually Tailscale Serve). Own `byot://pair` QR. HTTP only for mDNS-found LAN hosts | Optional companion plus BYOT relay. Real background APNs push is still an open plan ([#73](https://github.com/steventsao/byot/issues/73)) | Protocol auto-detection for v1 and v2; queue and steer; per-prompt model; opt-in telemetry |
| [Tailscode](https://apps.apple.com/us/app/tailscode-coding-agent-remote/id6791660932) | Midgar Oy, [GPL-3.0, 14★](https://github.com/guitaripod/Tailscode) | UIKit, Swift 6, iOS 18+, Mac | Free; Pro $14.99 one-time for multiple servers | 1.77, 2026-10-14 | Tailscale only; "nothing leaves your tailnet" | No relay. The phone holds a request open on the opencode v2 server until the turn ends, and iOS wakes the app to post a local notification. Needs Background App Refresh; v2 only ([#3](https://github.com/guitaripod/Tailscode/issues/3)) | Also drives Claude Code and Oh My Pi through bridges; Live Activities; forking; cost analytics |
| [Remote for OpenCode Agents](https://apps.apple.com/us/app/remote-for-opencode-agents/id6797660779) | Tim Williams, [PolyForm Noncommercial, 13★](https://github.com/tjameswilliams/remote-for-opencode) | SwiftUI plus Mac menu-bar companion | Free | 1.5, 2026-10-04 | Keys exchanged through the user's own iCloud private database, confirmed by a six-digit code. Bonjour on LAN, hole-punched UDP elsewhere. End-to-end encrypted (Curve25519, ChaCha20-Poly1305). opencode stays on localhost | "CloudKit routes a contentless nudge through your own iCloud account", then the phone fetches details over the encrypted link ([README](https://github.com/tjameswilliams/remote-for-opencode)) | Risk-tiered approvals with Face ID; Plan mode; scheduled prompts. Mac only on the server side |
| [opencode companion](https://apps.apple.com/us/app/opencode-companion/id6813434085) | Raul Alonso Pardo, [`ocremote` on npm](https://www.npmjs.com/package/ocremote) (MIT; repo not public) | iOS 17+ | Free | 1.1, 2026-10-05 | `npx ocremote --pair` QR. The companion supervises `opencode serve` on loopback and connects to a hosted relay, end-to-end encrypted with an Ed25519 key pinned in the QR. Direct Tailscale Funnel / Cloudflare modes also offered | APNs through the relay for permissions, questions and completion; Live Activities | Closest existing analogue to a Happy-style design for opencode |
| [KKCode – OpenCode Mobile](https://apps.apple.com/us/app/kkcode-opencode-mobile/id6780920001) | 张军保 (closed source; [site](https://kkcode.app/)) | iOS 16.4+ | Free | 1.0.7, 2026-09-30, 5.0 (10) | QR "tunnel" through an outbound relay, plus Tailscale, Cloudflare, LAN | Notifications for questions and permission requests through an opencode plugin that the `@kkcode-app/agent` companion registers, delivered by KKCode's notification service ([site FAQ](https://kkcode.app), [npm](https://www.npmjs.com/package/@kkcode-app/agent)) (corrected 2026-10-15); Live Activity per reviews | iPad split view, nine languages. Reviews ask for collapsible tool calls |
| [OpenCody](https://apps.apple.com/us/app/opencody-an-opencode-client/id6760118911) | Fabian Will, [MIT](https://github.com/fwilldev/OpenCody) | Swift, iOS 26+ | Free (tip IAPs) | 1.8, 2026-10-12 | opencode's own v2 pair links: redeems pasted `/auth/connect/<code>` links and creates them with `POST /api/pair` ([PairingAPI.swift](https://github.com/fwilldev/OpenCody/blob/main/OpenCody%20-%20An%20OpenCode%20Client/Services/API/V2/PairingAPI.swift)) (corrected 2026-10-15) | Local notifications only: a best-effort `BGAppRefreshTask`, no more often than every 15 minutes, polls the session list and posts a local notification while sessions are busy ([BackgroundRefreshService.swift](https://github.com/fwilldev/OpenCody/blob/main/OpenCody%20-%20An%20OpenCode%20Client/Services/BackgroundRefreshService.swift)) (corrected 2026-10-15) | Fork from a message; MCP and provider config; v1 and v2 |
| [Saffron OpenCode](https://apps.apple.com/us/app/saffron-opencode/id6806661363) | Upcastr Pty Ltd, closed | SwiftUI, iOS 18+ | Free | 1.0.5, 2026-10-15 | LAN or VPN, LAN auto-discovery; "no relay … no telemetry" | None advertised. The listing and site mention no notifications and promise "no account, no relay" ([site](https://saffronsuite.com/oc)) (corrected 2026-10-15) | Launched 2026-10-08 |
| [OC Remote](https://apps.apple.com/us/app/oc-remote/id6761319053) (unrelated to the Android "OC Remote" in 2.5) | Didac Sabates Duran, closed ([site](https://ocremote.didac.dev)) | iOS 18+ | Free; Pro for terminals and dictation | 1.1.1, 2026-04-17 | Remote connections require HTTPS | None advertised in the listing or on the [site](https://ocremote.didac.dev) (corrected 2026-10-15) | Revert/unrevert, fork, MCP auth; stale since April |
| [OpenCoderMan](https://apps.apple.com/us/app/opencodeman/id6760598918) | Michael Frey, closed | iOS 26.2+ | $2.99 | 1.2, 2026-06-21 | Direct | None advertised in the listing or on the developer's [site](https://thecodingman.net) (corrected 2026-10-15) | Diff review, command palette, iCloud key-value sync |
| [Remodex](https://apps.apple.com/us/app/remodex-remote-ai-coding/id6760243963) | Emanuele Di Pietro, [Apache-2.0, 3.3k★](https://github.com/Emanuele-web04/remodex) | SwiftUI, iOS 18.6+ | Free download, subscription (about $4/mo, "HARD PAYWALL" per reviews) | 4.0, 2026-10-01, 3.71 (35) | Mac QR pairing, SSH terminal | APNs completion alerts from its relay's push service, which holds the `.p8` key; plaintext previews up to 160 characters ([push-service.js](https://github.com/Emanuele-web04/remodex/blob/main/relay/push-service.js)). The 4.0 notes also mention Dynamic Island (corrected 2026-10-15) | Started as a Codex remote, added opencode in 4.0. Complaints: crashes, scrolling, no iPad layout |

### 2.3 Cross-platform, wrapper and TestFlight-only clients

| App | Tech, source | Status | Connection and push | Notes |
|---|---|---|---|---|
| [grapeot/opencode_ios_client](https://github.com/grapeot/opencode_ios_client) ("OpenCode Remote", [TestFlight](https://testflight.apple.com/join/2cWrmPVq)) | SwiftUI, MIT, 266★, the most-starred native Swift client; native visionOS | Active (2026-10-14) but v1 only: "cannot connect to OpenCode V2 server" is open ([#169](https://github.com/grapeot/opencode_ios_client/issues/169)); the fork [DeputyFifeofMayberry/fife_code](https://github.com/DeputyFifeofMayberry/fife_code) ("FifeCode") has an untested V2 adapter (added 2026-10-16) | LAN or HTTPS with Basic auth, plus a built-in SSH tunnel (Citadel). No background push | File tree, model picker, voice transcription. Diffs are fetched but never shown (corrected 2026-10-16, see 09-grapeot-ios-client.md) |
| [WhisperCode](https://apps.apple.com/us/app/whispercode/id6759430954) | Fork of opencode ([MIT, 344★](https://github.com/DNGriffin/whispercode)); SolidJS UI in an Xcode shell, WhisperKit speech-to-text | Highest-rated dedicated client (4.59 from 29) but last release 2026-04-27; reviews say "Abandonware" and crashes with newer servers | Bun `push-relay` package | Shows demand for voice-first input |
| [OpenCode Mobile App](https://apps.apple.com/us/app/opencode-mobile-app/id6757406313) | React Native, [doza62, MIT, 305★](https://github.com/doza62/opencode-mobile) | Stale since 2026-02; 1.9 from 10 ratings | Cloudflare/ngrok/localtunnel tunnel with a `/mobile` QR; Expo push through an `opencode-mobile` plugin | Complaints: no password support, errors, abandonment |
| [alvarolorentedev/opencode-mobile](https://github.com/alvarolorentedev/opencode-mobile) ([getopencode.app](https://getopencode.app/), [TestFlight](https://testflight.apple.com/join/ddcE5Wzz)) | Expo/React Native, Apache-2.0, 259★ | Active; switched to native v2 on 2026-10-12 | Tunnels or VPN | Terminal, file patching, voice, multiple servers; Android on Google Play |
| [Client for OpenCode](https://apps.apple.com/us/app/client-for-opencode/id6759843671) | Flutter | $2.99, single release 2026-03-16, no ratings | Direct | SSE, approvals, diff viewer |
| [OpenCode-Mobile-Client](https://apps.apple.com/us/app/opencode-mobile-client/id6787161501) | WebView wrapper of the stock web UI with injected mobile fixes ([MIT, 66★](https://github.com/bmpenuelas/opencode-mobile-client)) | 1.2.5, 2026-09-04 | Multiple server profiles, Basic auth, health-check reconnect | Also on Android |
| [OpenCodeM](https://apps.apple.com/us/app/opencodem/id6764783164) | WKWebView of the web UI plus native SSE status, Live Activity, widget | $0.99, last update 2026-05-22, targets opencode 1.15.7 | Local notifications only | |
| [Whatcode](https://apps.apple.com/us/app/whatcode/id6760623503) | v2 only since 2.0.0 (2026-10-13) | Subscription: "All features require a WhatCode Pro subscription" | QR pairing with the WhatCode daemon (`npx @whatcode-ai/whatcode start`, MIT), which starts opencode and exposes it on the LAN or over Tailscale HTTPS. For push, the daemon posts a plaintext title and body (project name; model name plus the last reply, the permission request or the error) to WhatCode's relay, which sends it through APNs ([daemon docs](https://github.com/Pnlvfx/whatcode-ai/blob/main/apps/docs/docs/daemon.md), [apn.ts](https://github.com/Pnlvfx/whatcode-ai/blob/main/packages/sdk/src/apn/apn.ts)). The 2.0.0 notes say rebuilt notifications "work with plain OpenCode" (corrected 2026-10-15) | |
| [OpenCode Mobile — Unofficial](https://apps.apple.com/us/app/opencode-mobile-unofficial/id6799246544) | Private source ([docs](https://github.com/opencode-mobile/opencode-mobile-docs)) | Launched 2026-10-13, also Android | Tailscale URL plus `OPENCODE_SERVER_PASSWORD`; "does not create a tunnel or relay" | Approvals, diffs, terminals, dictation, tablet split view |
| [omnicus/opencode2-mobile](https://github.com/omnicus/opencode2-mobile) | Expo, MIT, 6★ | v2 only | Uses opencode's own `/pair`; "self-hosted encrypted push" through a self-hosted broker, then Expo Push, then APNs/FCM | Small, but the right pairing primitives |
| OpenChamber ([TestFlight](https://testflight.apple.com/join/5ek6GU1E), [MIT, 11.7k★](https://github.com/openchamber/openchamber)) | Capacitor wrapper around the OpenChamber web UI, which itself wraps opencode | Beta | One-time QR over its end-to-end "Private Relay" or LAN; push via Capacitor push notifications ([mobile docs](https://github.com/openchamber/openchamber/blob/main/packages/docs/content/docs/mobile.mdx)) | Requires the OpenChamber server, not plain opencode |
| [Remote Code](https://remote-code.com/opencode) (Vanna.ai) | TestFlight plus an "Uplink" desktop app | Beta | Pairs the phone with Uplink on Mac, Windows or Linux ("secure pairing"); the site describes no transport details and no push notifications (corrected 2026-10-15) | |

The long tail, all at 19★ or fewer and lightly maintained:
- [Shahfarzane/opencode-mobile](https://github.com/Shahfarzane/opencode-mobile), an Expo fork of OpenChamber, stale since January.
- [fernandogarzaaa/opencode-mobile](https://github.com/fernandogarzaaa/opencode-mobile), whose PR #12 adds Approve/Decline notification actions backed by HMAC-signed approval endpoints.
- [v1truv1us/opencode-nexus](https://github.com/v1truv1us/opencode-nexus).
- [georgi/opencode-mobile](https://github.com/georgi/opencode-mobile).
- jackwener/opencode-ios, ricoberger/OpenCode and similar.

`dzianisv/opencode-mobile` (vibebrowser.app) is Android-only. Its iOS app is still "coming soon" ([blog](https://www.vibebrowser.app/blog/2026-07-14-opencode-mobile-ios-coming-soon)).

### 2.4 Multi-agent remotes that also drive opencode

These products are agent-agnostic and treat opencode as one backend among several. Their architecture is analysed in Section 3.

| App | iOS listing | Source | Notes |
|---|---|---|---|
| Paseo | [4.91 from 102 ratings, free](https://apps.apple.com/us/app/paseo-remote-coding-agents/id6758887924), the most-rated app in this space | [getpaseo/paseo, 21.0k★](https://github.com/getpaseo/paseo) | Expo; end-to-end encrypted relay; local-first voice ([paseo.sh/opencode](https://paseo.sh/opencode)) |
| Sesori | Flutter (Dart) app on the [App Store](https://apps.apple.com/us/app/sesori-mobile-ai-coding/id6760642500) (free, 1.9.1 of 2026-10-15, 5.0 from 1 rating) and [Google Play](https://play.google.com/store/apps/details?id=com.sesori.app) | [sesori_apps_monorepo, 130★](https://github.com/sesori-ai/sesori_apps_monorepo) | End-to-end encrypted relay plus a bridge CLI; OAuth device pairing; Claude, Codex, OpenCode, Cursor, Pi and more ([#6536 comment](https://github.com/anomalyco/opencode/issues/6536)) |
| Happier | Expo, MIT; [4.29 from 14 ratings, free](https://apps.apple.com/us/app/happier-remote-claude-codex/id6758554297) | [docs](https://docs.happier.dev/providers/opencode) | Happy fork with opencode support; end-to-end relay or Tailscale |

Others list opencode among supported agents but were not examined in depth: AgentsRoom, Codync, Zedra, Port22, Lunel, Clawdex, Lody, Leash (Apple Watch), Argus, Supermux, Cockpit, Perch, Spaces, BrewPing (iPhone and Watch), Muqun and Doom Coder (alerts only). Hosted alternatives that run opencode in the vendor's cloud rather than on your machine include [Cosyra](https://cosyra.com/guides/opencode-on-iphone.html) and Vibe Pocket.

### 2.5 Android, mobile-web, terminal-bridge and chat-bot clients

These are not our platform, but they show what users of a phone client expect and where the pain is. Play listings are at `play.google.com/store/apps/details?id=<id>`. Install counts and ratings were read on 2026-10-15. The shared web-search budget ran out during this part, so Reddit, HN and X sentiment is thin and user feedback comes mostly from Play reviews and GitHub issues.

**Native Android apps**

| App | Tech, source | Store | Connection | Notes |
|---|---|---|---|---|
| OpenCode: AI Coding Agent (Play `cc.agentlabs.opencode`) | React Native/Expo, [dzianisv/opencode-mobile, MIT, 229★](https://github.com/dzianisv/opencode-mobile) | 10K+ installs, 4.6★ (112), free; also F-Droid repo and APK | URL plus password; LAN, Tailscale, Cloudflare Tunnel, ngrok | SSE, side-by-side diffs, approvals, multiple servers, biometric lock, demo mode. v1 only (V2 tracked in its repo). Top complaint: the input hides behind the keyboard |
| OpenCode Mobile Client (Play `com.logicedge.opencodemobile`; also iOS) | Capacitor wrapper around the stock web UI ([MIT, 66★](https://github.com/bmpenuelas/opencode-mobile-client)) | 10K+, 4.4★ (51) | LAN/VPN/Tailscale, profiles, Basic auth | V2 support open. Reviews: "Nothing loads… loads perfectly in browser" |
| Opencode Mobile (Play `app.getopencode`; iOS TestFlight) | Expo, ships both v1 SDK and v2 client ([Apache-2.0, 259★](https://github.com/alvarolorentedev/opencode-mobile)) | 5K+, IAPs | Manual URL, **`opencode pair` QR**, or a paid "Cloud Link" hosted relay (`api.opencodecloud.link`; price not published) | Widgets, failure and pending-action notifications (2026-10-13), terminal, voice. Issues: Tailscale connection failures, scroll jumps |
| Pocket for OpenCode (Play `dev.blazelight.p4oc`) | Native Kotlin/Compose, OkHttp SSE, Termux terminal view ([GPL-3.0, 88★](https://github.com/theblazehen/P4OC)) | $0.99, 500+, 3.9★ (33) | Direct | Auto-detects v1 and v2 (0.15.0); multi-tab and sub-agent tabs; diffs and revert. Reviews split: "forgets model and effort" |
| MobileCode (Play `io.apuyou.mobilecode`) | Expo, v1 SDK ([MIT](https://github.com/apuyou/mobilecode)) | 1K+ | LAN or Tailscale only | No approvals or diffs listed |
| OC Remote ([crim50n/oc-remote](https://github.com/crim50n/oc-remote)) | Kotlin, MIT, 167★, APKs only | 1.1K–2.4K downloads per release | Direct | Broadest Android feature set: PTY terminal over WebSocket, permission/question queue, MCP management, on-device Termux runtime, foreground service to keep SSE alive. v1 only, waiting for v2 to settle |
| [grapeot/opencode_android_client](https://github.com/grapeot/opencode_android_client) | Kotlin, MIT, 96★ | GitHub | Direct | Three-pane tablet layout, voice |

Also on GitHub:
- [hjinlabs-netizen/opencode-android](https://github.com/hjinlabs-netizen/opencode-android), the [#48556](https://github.com/anomalyco/opencode/issues/48556) showcase.
- [mittaus/opencode-mobile-client](https://github.com/mittaus/opencode-mobile-client), a KMP app plus a Go gateway doing API-key auth, SSE fan-out and one server per project.
- vchhikara/opencode-remote, which uses per-device credentials with revocation and an audit log.
- CrossCode (`npx crosscode` starts a tunnel and QR; stable tunnels $2–5/month).

**Mobile web and PWA UIs**

- **The official web UI as a PWA.** It is served by every server and hosted at app.opencode.ai and beta.opencode.ai. It is the most common "mobile client" in practice and has the open bugs listed in Section 1.5.
- **OpenChamber** ([MIT, 11.7k★](https://github.com/openchamber/openchamber)): desktop, web/PWA and VS Code UI on top of opencode, with Capacitor iOS/Android apps.
  - One-time QR pairing issues revocable per-device tokens ([connect-devices](https://github.com/openchamber/openchamber/blob/main/packages/docs/content/docs/connect-devices.mdx)).
  - An end-to-end encrypted, outbound-only "Private Relay" ([private-relay](https://github.com/openchamber/openchamber/blob/main/packages/docs/content/docs/private-relay.mdx)) that is self-hostable ([openchamber-relay](https://github.com/openchamber/openchamber-relay)).
  - Sealed APNs push through a central relay (Section 5.2).
  - This is the most complete reference design in the ecosystem.
- **CodeNomad** ([MIT, 2.6k★](https://github.com/NeuralNomadsAI/CodeNomad)): desktop app and browser server for the v2 service. Its "Remote Control" pairs a phone "through an OpenTunnel relay … TLS ends on your machine" (README), so a third-party project already uses OpenTunnel.
- **OpenCode Manager** ([MIT, 900★](https://github.com/chriswritescode-dev/opencode-manager)): Docker-based, mobile-first PWA with VAPID Web Push for permissions, questions, errors and completions ([docs](https://chriswritescode-dev.github.io/opencode-manager/features/notifications/)).
- **OpenPortal** ([hosenur/portal, MIT, 812★](https://github.com/hosenur/portal)): mobile-first web UI over Tailscale or VPN. It is listed on opencode's ecosystem page ([ecosystem.mdx](https://github.com/anomalyco/opencode/blob/dev/packages/web/src/content/docs/ecosystem.mdx)) and has been quiet since May. Not to be confused with gosuda/portal-tunnel ([#53922](https://github.com/anomalyco/opencode/issues/53922)).
- **Others:**
  - [CloudCLI/claudecodeui](https://github.com/siteboon/claudecodeui) (AGPL-3.0, 14.1k★), which added opencode in v1.33.0 per its release notes.
  - [Collie](https://github.com/AltanS/collie) (1.4k★), a PWA over tmux, zellij and Herdr panes with VAPID push.
  - [Harness Remote](https://github.com/giuliastro/harness-remote) (415★), a Capacitor APK plus PWA with one-time QR pairing.

**Terminal bridges**
- **opencode-remote (cmateos91).** It mirrored the live TUI to an xterm.js PWA over WebSocket with an automatic Cloudflare Tunnel ([#10288 comment](https://github.com/anomalyco/opencode/issues/10288)). The repository now returns 404.
- **shell.online.** `shell opencode` prints a link and QR that show the real TUI in a phone browser. Its maker concedes it is cramped and that "the link is a bearer credential" (same thread).
- **Termux and SSH clients.** Running the TUI over these on Android hits resize flicker and disconnects ([#44093](https://github.com/anomalyco/opencode/issues/44093)), broken scrolling under ConnectBot plus tmux ([#45871](https://github.com/anomalyco/opencode/issues/45871)), and garbled images ([#52492](https://github.com/anomalyco/opencode/issues/52492)).

**Chat bots and notifier plugins**

Chat bots are a popular "mobile client" because they get push for free:
- [grinev/opencode-telegram-bot](https://github.com/grinev/opencode-telegram-bot) (MIT, 1.3k★, v1 and v2): inline-button approvals, model and mode switching, Whisper voice.
- [Kimaki](https://github.com/remorses/kimaki) (MIT, 1.4k★, opencode 2 only): Discord, with one channel per project and one thread per session.

Approval and notification services:
- [Pushary](https://pushary.com): a hosted approval and notification service with native apps, $9.99 or $19.99 a month. Notification metadata (title, body, tool name) passes through its servers. A V2 port is pending ([#52778](https://github.com/anomalyco/opencode/issues/52778)).
- ntfy plugins with Allow/Deny buttons, such as lannuttia/opencode-ntfy.sh and bkoimett/opencode-ntfy-approve.
- Desktop notifiers listed in the ecosystem docs.
- Lauther (lauther.app) and CPJ (choupijiang.istarlit.com): approval relays whose makers pitched them in [#39628](https://github.com/anomalyco/opencode/issues/39628) and [#47692](https://github.com/anomalyco/opencode/issues/47692). opencode support is unverified for both.

### 2.6 Patterns and gaps across third-party clients

1. **The v2 API break sorted the field.** Clients with dual-protocol adapters (BYOT, Tailscode, OpenClient, OpenLens 2.0) recovered quickly. The most-starred Swift client (grapeot) and the most-rated wrapper (WhisperCode) still do not work with v2.
2. **Nobody delivers background push for plain `opencode serve` without extra infrastructure.** Every working approach adds something:
   - a companion process plus a hosted relay (BYOT, opencode companion, Paseo, Sesori, Happier, KKCode, WhatCode);
   - a self-hosted broker (omnicus, OpenClient's Web Push);
   - a CloudKit nudge (Remote for OpenCode, Mac only);
   - an OS-woken long request (Tailscode, v2 and Tailscale only).
   Everything else only notifies while in the foreground.
3. **Reaching the server is the main friction.** Most apps assume Tailscale or a self-managed HTTPS endpoint plus Basic auth. Only OpenLens and OpenCody on the App Store, plus alvarolorentedev's Opencode Mobile (TestFlight and Play), accept opencode's own pair links ([PairingAPI.swift](https://github.com/fwilldev/OpenCody/blob/main/OpenCody%20-%20An%20OpenCode%20Client/Services/API/V2/PairingAPI.swift), [pairing.ts](https://github.com/alvarolorentedev/opencode-mobile/blob/main/lib/opencode/pairing.ts)) (corrected 2026-10-15). Only grapeot has an in-app SSH tunnel. Bonjour discovery is rare. None advertise OpenTunnel support.
4. **Quality gaps that recur in reviews:**
   - abandonment after an opencode release;
   - lag and scroll jank in long transcripts;
   - noisy tool-call rendering;
   - weak iPad layouts;
   - paywalls on basic use;
   - servers that cannot be edited while unreachable.
5. **Rare but valued:**
   - Live Activities that update while the app is closed;
   - per-change revert and fork;
   - risk-tiered approvals with Face ID;
   - a review/diff tab;
   - native visionOS (grapeot only);
   - Mac builds (Tailscode, OpenCodeM).

---

## 3. Analogous tools: how other coding agents solved remote and mobile

### 3.1 Summary table

| Tool | Reaching the machine behind NAT | End-to-end encryption | Push | Handoff model |
|---|---|---|---|---|
| **Claude Code Remote Control** (Anthropic) | Local CLI "makes outbound HTTPS requests only and never opens inbound ports"; registers with the Anthropic API and polls for work; streaming route once a device connects ([docs](https://code.claude.com/docs/en/remote-control)) | No. TLS to Anthropic, which also runs the model | Claude iOS/Android app. Two toggles: "Push when Claude decides" and "Push when actions required". Skipped while you type in or focus the terminal; `CLAUDE_CLIENT_PRESENCE_FILE` extends presence detection (same docs) | All surfaces live at once; `/teleport` pulls cloud sessions down. Trusted Devices adds a biometric step-up after 18 h. Permission prompts never time out; other dialogs expire after 5 min |
| **OpenAI Codex Remote** (ChatGPT app) | Codex desktop app or app-server enrolls at `chatgpt.com/backend-api/wham/remote/control/server/enroll`, then holds an outbound connection with a bearer token ([protocol.rs](https://github.com/openai/codex/blob/main/codex-rs/app-server-transport/src/transport/remote_control/protocol.rs)). The CLI has `codex remote-control start/stop/pair` ([remote_control_cmd.rs](https://github.com/openai/codex/blob/main/codex-rs/cli/src/remote_control_cmd.rs)) | None claimed [inference from source] | Notifications for completed tasks; Live Activity during worktree setup; Face ID lock; approvals recover after reconnect (per the [ChatGPT changelog](https://learn.chatgpt.com/docs/changelog)) [details from one source] | Thread handoff moves chat plus Git state to a worktree on the destination host |
| **Cursor iOS app** (beta since 2026-06-29, iOS 26+) | Remote Control: the agent loop runs in Cursor's cloud and tool calls execute on your machine, which must stay online ([docs](https://cursor.com/docs/cloud-agent/web-and-mobile), [changelog](https://cursor.com/changelog/ios-mobile-app)) | No | Push "when an agent finishes, needs input, or is ready for review"; Live Activities "track up to eight agents" | Sessions can move from local to cloud |
| **GitHub Copilot CLI** | `copilot --remote` streams the session to GitHub, generally available 2026-05-18 ([changelog](https://github.blog/changelog/2026-05-18-remote-control-for-copilot-cli-sessions-now-generally-available-on-mobile-web-and-vs-code/)) | No | GitHub Mobile Live Activities (iOS 17.2+) with states In progress, Waiting for user input, Idle, Finished; tap opens logs ([changelog](https://github.blog/changelog/2026-07-08-github-mobile-live-notifications-for-copilot-cli-sessions)) | Steer, approve, answer from phone |
| **Happy** ([MIT, 24.1k★](https://github.com/slopus/happy)) | Daemon and phone both dial out to `happy-server` (Socket.IO); self-hostable Docker image | Yes: phone master secret, per-session AES-256-GCM data keys wrapped with NaCl box; server sees ids, timestamps and activity ([encryption.md](https://github.com/slopus/happy/blob/main/docs/encryption.md)) | Expo, with **plaintext** title/body; skipped when a UI client is active. A code comment admits a "total push outage stayed invisible for two months" ([pushDispatch.ts](https://github.com/slopus/happy/blob/main/packages/happy-server/sources/app/push/pushDispatch.ts)) | Original CLI: local/remote mode switch (phone message kills the TUI and resumes in SDK mode). New harness: shared control, "no remote mode" |
| **Happier** ([MIT, 2.0k★](https://github.com/happier-dev/happier)) | Happier Cloud or self-hosted relay; drives a managed `opencode serve` natively (v1 or v2) ([opencode docs](https://github.com/happier-dev/happier/blob/dev/apps/docs/content/docs/agents/opencode.mdx)) | Yes by default, with a client-side "require E2EE" pin against server downgrade ([encryption](https://github.com/happier-dev/happier/blob/dev/apps/docs/content/docs/security/encryption.mdx)) | Expo, sent by the CLI. Allow/Deny/Answer actions still open the app ([notifications](https://github.com/happier-dev/happier/blob/dev/apps/docs/content/docs/extras/notifications-setup.mdx)) | Live session can move between machines keeping its ID |
| **Paseo** ([21.0k★](https://github.com/getpaseo/paseo)) | Daemon connects out to an open-source Elixir relay ([paseo-relay](https://github.com/getpaseo/paseo-relay)); also SSH and Tailscale ([connectivity](https://github.com/getpaseo/paseo/blob/main/public-docs/connectivity.md)) | Yes: daemon Curve25519 key in the QR, NaCl box. Relay sees IPs, timing, sizes and session IDs ([security](https://github.com/getpaseo/paseo/blob/main/public-docs/security.md)) | Daemon posts **plaintext** title/body straight to Expo's push API ([push-service.ts](https://github.com/getpaseo/paseo/blob/main/packages/server/src/server/push/push-service.ts)) | Multi-agent orchestration; viewer/operator/owner grants |
| **Remodex** ([Apache-2.0, 3.3k★](https://github.com/Emanuele-web04/remodex)) | Node bridge drives `codex app-server` (and opencode) and meets the phone at a relay (hosted, self-hosted, LAN, cloudflared) | Yes: Ed25519 identities, X25519 ephemeral keys, signed transcript, HKDF, AES-GCM with counter nonces, "trusted reconnect" | Phone sends its APNs token to the bridge over E2EE. The bridge calls the relay's push service (which holds the `.p8`) with a per-session secret. **Plaintext** preview up to 160 chars ([push-service.js](https://github.com/Emanuele-web04/remodex/blob/main/relay/push-service.js)) | — |
| **Sesori** | Dart bridge plus relay; its opencode plugin uses `/global/event` (v1) or `/api/event` (v2) ([plugin README](https://github.com/sesori-ai/sesori_apps_monorepo/blob/main/bridge/sesori_plugin_opencode/README.md)) | Yes for payloads; relay manages device public keys | Bridge to Sesori backend to FCM with **plaintext** question/permission text ([content builder](https://github.com/sesori-ai/sesori_apps_monorepo/blob/main/bridge/app/lib/src/push/push_notification_content_builder.dart)) | Account-based pairing |
| **OpenChamber** (opencode-based) | Outbound "Private Relay"; direct LAN preferred when reachable | Yes: device and server agree keys directly; relay "cannot read your code, your prompts, or your passwords" ([private-relay](https://github.com/openchamber/openchamber/blob/main/packages/docs/content/docs/private-relay.mdx)) | Central Cloudflare-Worker relay holds the one `.p8`. Servers sign requests (P-256), tokens bound to a `serverId`. Clear text is generic; real text is **sealed** (AES-256-GCM) and opened in the NSE ([APNS.md](https://github.com/openchamber/openchamber/blob/main/packages/web/server/lib/notifications/APNS.md)) | Shared control |
| **Omnara** | Was a Python wrapper around Claude Code and Codex with apps; deprecated in Nov 2025 as "unfeasible to maintain with Claude Code's constant updates" ([legacy README](https://github.com/omnara-ai/omnara/blob/500a82ad85ba35d0a478810bb00e944ba93071b1/README.md)). Now a Go managed-agent platform whose daemon connects outbound | No | Push, email, SMS (old version) | — |
| **VibeTunnel** ([MIT, 4.7k★](https://github.com/amantus-ai/vibetunnel)) | Browser terminal on port 4020 via Tailscale Serve/Funnel, ngrok or Cloudflare | Transport only | Web Push (VAPID) for session start/exit, long commands, bell, Claude turns ([push doc](https://github.com/amantus-ai/vibetunnel/blob/main/docs/push-notification.md)) | iOS app "still work in progress" |
| **Moshi** (iOS terminal) | Direct SSH/Mosh/ET, Tailscale; no session relay | Transport only | `moshi-hook` (Claude, Codex, **OpenCode** and more) sends truncated summaries via Expo. Allow/deny "right from the banner" or the Watch. Live Activities. Docs warn "Anyone with the token can send notifications to your device" ([hooks](https://getmoshi.app/docs/hooks), [notifications](https://getmoshi.app/docs/notifications)) | Terminal is the session |
| **Termius / Blink + mosh + tmux + Tailscale** | DIY: SSH over Tailscale, tmux for persistence | SSH | DIY hooks to ntfy, Poke and similar ([example](https://granda.org/en/2026/01/02/claude-code-on-the-go)) | Reattach tmux |
| **Gemini CLI, Aider** | No first-party phone remote found. Gemini is reachable through ACP-based third-party apps; Aider has only an experimental browser UI | — | — | — |

### 3.2 Lessons that transfer to an opencode iOS client

1. **Everyone converged on outbound-only host connections.** Examples: Claude, Codex, Cursor, Copilot, Happy, Paseo, Remodex, OpenChamber. For opencode v2, OpenTunnel already provides this at the transport layer, with TLS ending on the user's machine. Our app does not need its own relay just to reach the server.
2. **A relay of our own is only justified for push** and, optionally, for store-and-forward of approvals while the server is unreachable. Nimbalyst's queued-prompt sync is an example ([SYNC_ARCHITECTURE.md](https://github.com/nimbalyst/nimbalyst/blob/main/design/MobileSync/SYNC_ARCHITECTURE.md)).
3. **Build on the official server API, never on a scraped TUI.** Omnara's wrapper died of this. opencode's HTTP API is the stable contract.
4. **Push privacy is a real differentiator.**
   - Every open-source relay-based push implementation inspected, except OpenChamber, sends plaintext previews through Expo, FCM or its own relay: Happy, Happier (previews can be switched off), Paseo, Remodex, Sesori, Moshi, and WhatCode ([apn.ts](https://github.com/Pnlvfx/whatcode-ai/blob/main/packages/sdk/src/apn/apn.ts)). The exceptions avoid content altogether: Remote for OpenCode's CloudKit nudges, omnicus/opencode2-mobile's allowlisted category text plus an encrypted routing envelope ([NOTIFICATIONS.md](https://github.com/omnicus/opencode2-mobile/blob/main/docs/NOTIFICATIONS.md)), and Signal-style ID-only pushes (corrected 2026-10-15).
   - Sealed payloads opened in a Notification Service Extension are cheap to build and easy to explain.
5. **Presence-aware push** is now table stakes: Claude's typing/focus and presence file, Happy's active UI, OpenChamber's iOS-side foreground suppression. So is **monitoring delivery outcomes**: Happy lost push for two months unnoticed.
6. **Shared control beats takeover.** opencode's server model already gives the TUI, desktop and phone equal access to one session. The phone should show who else is attached and offer queue versus steer for mid-turn prompts.
7. **Live Activities and Watch are expected** in this category: Cursor (eight agents), Copilot, Codex, Moshi, OpenLens, OpenClient and Tailscode all use them.
8. **Approval safety rules seen across products:**
   - permission prompts never time out into an action (Claude; "silence must not read as yes" in [#39628](https://github.com/anomalyco/opencode/issues/39628));
   - biometric step-up (Claude Trusted Devices, Remote for OpenCode Face ID, Codex app lock);
   - no "bypass all permissions" from the phone (Claude);
   - per-device scopes (Paseo grants);
   - a warning that whoever can reply can approve (Claude Channels docs).

---

## 4. Connectivity: how the phone reaches `opencode serve`

### 4.1 Constraints that shape every option

- **The server side:**
  - opencode listens on localhost with a random password by default.
  - It speaks plain HTTP plus SSE, and its event stream is live-only with no replay (Section 1.4).
  - A client must therefore (a) find a reachable address, (b) authenticate, and (c) resync state after every reconnect.
- **The phone side:**
  - iOS suspends an app shortly after it leaves the foreground. Apple's DTS has said "There's no general-purpose mechanism for: Running code continuously in the background" ([forum](https://developer.apple.com/forums/thread/685525)).
  - Background `URLSession` sessions only perform upload and download tasks, which the system runs in a separate process ([Apple](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:))). They cannot carry an SSE stream.
  - `BGAppRefreshTask` and background pushes give short, throttled windows ([Apple](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)).
  - iOS 26's `BGContinuedProcessingTask` lets a *user-initiated* task keep running with a system progress UI, but it must report progress and can be terminated under pressure ([Apple](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask)). It might be able to follow a single turn the user just started from the phone [inference; needs a prototype], but it cannot keep a general event stream alive.
  - **Design consequence:** the foreground is the only time the app streams. While suspended, the app learns about events only through push (Section 5) or OS-scheduled wakeups.
- **IPv6-only networks:** App Review requires "Apps must be fully functional on IPv6-only networks" (guideline 2.5.5, [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)). Never hard-code IPv4 literals for our own services, and test against NAT64.
- **The network:**
  - Phones move between home Wi-Fi, office Wi-Fi and cellular CGNAT, and switch mid-session.
  - The official web client fails permanently after a Wi-Fi/cellular switch ([#55673](https://github.com/anomalyco/opencode/issues/55673)) and on half-open "zombie" SSE connections ([#51857](https://github.com/anomalyco/opencode/issues/51857)). A native client must do better:
    - watch path changes with `NWPathMonitor`;
    - treat ~40 s without any bytes as a dead stream (v2 sends a `: heartbeat` comment every 15 s, v1 a `server.heartbeat` event every 10 s);
    - reconnect with backoff and jitter;
    - re-fetch sessions, messages and pending permissions/forms after every reconnect.
- **Idempotency:** `POST /api/session/{id}/prompt` accepts an optional client-generated message `id`, and "Durably admit[s] one session input" ([OpenAPI](https://github.com/anomalyco/opencode/blob/dev/packages/protocol/openapi.json)). The plugin docs add that "Retrying an ID already pending or delivered returns the original admission" ([plugin docs](https://github.com/anomalyco/opencode/blob/dev/services/www/src/docs/content/build/plugins/index.mdx)). The phone should generate the ID and retry freely on flaky networks.
- **App Transport Security (ATS):**
  - Since iOS 17, ATS blocks connections to IP addresses by default.
  - `NSAllowsLocalNetworking` re-enables unqualified names, `.local` names and IP literals ([Apple](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)).
  - Plain HTTP to a qualified name, such as a MagicDNS `*.ts.net` host or a custom domain, still needs an exception domain or `NSAllowsArbitraryLoads`.
  - Prefer HTTPS everywhere off the LAN.

### 4.2 Options compared

#### A. LAN direct, with Bonjour discovery

- **How it works.**
  - The phone calls `http://<lan-ip>:49374`. The service must listen beyond loopback (`opencode service set hostname 0.0.0.0`). When it does, `opencode pair` already includes the LAN URL in its QR code ([#54871](https://github.com/anomalyco/opencode/issues/54871)).
  - Discovery browses `_http._tcp` for `opencode-<port>` names. Only v1 servers advertise this (Section 1.4).
  - Any local-network use requires `NSLocalNetworkUsageDescription`, and browsing requires listing the service types in `NSBonjourServices` ([Apple](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription), [Apple](https://developer.apple.com/documentation/bundleresources/information-property-list/nsbonjourservices)).
  - The restricted multicast entitlement is only needed for raw multicast or for browsing *arbitrary* service types ([Apple](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast)).
  - Plain HTTP to IP literals needs `NSAllowsLocalNetworking` (Section 4.1).
- **Pros:** lowest latency; works with no internet; no third party involved.
- **Cons:**
  - Only works at home or the office.
  - Plain HTTP exposes the password or session token to anyone on the Wi-Fi.
  - Binding to `0.0.0.0` exposes the server to the whole LAN.
  - DHCP addresses change.
  - v2 no longer advertises itself.
  - Users see the Local Network permission prompt.
- **Security:** only as good as the LAN. Use it on trusted networks, or as a latency optimisation alongside an encrypted path.
- **Setup friction:** low if the user runs `opencode pair` with the service bound to all interfaces; otherwise the user must type an IP address.
- **App Store:** no issues beyond the permission strings.

#### B. OpenTunnel (`opencode pair --remote`), the official path

- **How it works.**
  - The dev machine keeps an outbound bridge WebSocket to opentunnel.xyz.
  - The phone connects to `https://<route>.<tunnel>.opentunnel.xyz`, which has a publicly trusted wildcard certificate.
  - TLS terminates inside the opencode process. The relay routes by SNI and never holds the key ([README](https://github.com/anomalyco/opentunnel), [PR #54561](https://github.com/anomalyco/opencode/pull/54561)).
- **Pros:**
  - Zero configuration and no account.
  - Works through CGNAT and on cellular.
  - Standard `URLSession` HTTPS with no ATS exceptions.
  - Official, and already used by third parties such as CodeNomad.
  - End-to-end TLS, a persistent random subdomain, and an unguessable URL.
- **Cons:**
  - The server becomes reachable from the whole internet. Access control is only the server password or a 30-day session token, and per-device revocation does not exist ([PR #50970](https://github.com/anomalyco/opencode/pull/50970)).
  - It depends on one vendor's brand-new service: there was a European outage in its first week, and Pi-hole style blocklists break it ([#54596](https://github.com/anomalyco/opencode/issues/54596)).
  - The relay sees visitor IPs, SNI and traffic timing ([trust-boundary.md](https://github.com/anomalyco/opentunnel/blob/master/docs/trust-boundary.md)).
  - Connections idle for 15 minutes are reset ([server.md](https://github.com/anomalyco/opentunnel/blob/master/docs/server.md)).
  - Latency depends on geography. The phone and the dev machine each reach the nearest of eleven Fly.io regions (iad, ord, sjc, gru, lhr, fra, cdg, jnb, sin, nrt, syd). When those regions differ, the stream is forwarded between machines over Fly's private network, and the machine's bridge also passes through Cloudflare ([server.md](https://github.com/anomalyco/opentunnel/blob/master/docs/server.md#multiple-regions)) (corrected 2026-10-15).
- **Security:** strong confidentiality. Exposure is mitigated by the random default password, but a weak custom password becomes an internet-facing weakness.
- **Setup friction:** one command or one desktop button, plus a QR scan.
- **App Store:** nothing special.

#### C. Tailscale through the official Tailscale app

- **How it works.** Both machines join a tailnet. The phone calls the server's `100.x` address or MagicDNS name. HTTPS with a real certificate comes from `tailscale serve`, which is exactly how the team's July "OpenMobile" prototype paired ([gist](https://gist.github.com/R44VC0RP/da505bcc925c91dee0160a4c7577c1a3)).
- **Pros:**
  - Private: not internet-reachable.
  - WireGuard encryption, with NAT traversal and relay fallback built in.
  - Most existing third-party clients already document it (Section 2).
- **Cons:**
  - Requires a Tailscale account and app on both ends.
  - Tailscale's own docs say "iOS and Android enforce a limit of running only one VPN at a time", so it conflicts with corporate VPNs ([Tailscale](https://tailscale.com/kb/1105/other-vpns)).
  - Plain HTTP to full MagicDNS names needs an ATS exception, so prefer `tailscale serve` HTTPS. Serve certificates put machine names into public Certificate Transparency logs ([Tailscale HTTPS](https://tailscale.com/kb/1153/enabling-https)).
  - The service must listen on the tailnet address or sit behind `tailscale serve`. The desktop app has had auth bugs on non-loopback addresses ([#51075](https://github.com/anomalyco/opencode/issues/51075)).
  - Tailscale Funnel can expose the server publicly with TLS ending on the node, so the relay "cannot decrypt data". It is limited to ports 443, 8443 and 10000 and has bandwidth limits ([Funnel](https://tailscale.com/kb/1223/funnel)).
- **Security:** very good; still keep the opencode password.
- **Setup friction:** medium; easy for people who already use Tailscale.
- **App Store:** nothing special in our binary. However, guideline 4.2.3(i) says "Your app should work on its own without requiring installation of another app to function" ([guidelines](https://developer.apple.com/app-store/review/guidelines/)), so Tailscale must be one path among several, never a hard requirement.

#### D. Tailscale embedded in our app (TailscaleKit / libtailscale)

- **How it works.**
  - libtailscale's Swift package runs a userspace tsnet node inside the app and provides a `URLSessionConfiguration` that routes through a loopback proxy ([TailscaleKit README](https://github.com/tailscale/libtailscale/tree/main/swift)).
  - That proxy relies on `URLSessionConfiguration.proxyConfigurations`, which requires iOS 17 ([Apple](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/proxyconfigurations)).
  - Nodes are authorized with an auth key or an interactive browser login, and the control URL is configurable, which allows Headscale.
  - The README says the iOS framework "is free of any simulator segments and is suitable for app-store submissions".
- **Precedents:**
  - NovaScale on the App Store: "Built-in Tailscale connects your tailnet inside NovaScale. Traditional SSH hosts and Headscale are also supported" ([App Store](https://apps.apple.com/app/id6749938291)).
  - The open-source terminal [Clauntty](https://github.com/eriklangille/clauntty).
  - Community SwiftPM packaging such as [libtailscale-spm](https://github.com/AkinoKaede/libtailscale-spm).
- **Pros:**
  - No VPN slot used and no Tailscale app needed on the phone.
  - Coexists with corporate VPNs.
  - Headscale-compatible.
- **Cons:**
  - Bundles a Go runtime, built with the Go toolchain: binary size and memory [size unverified].
  - Each install becomes a separate tailnet device ([tsnet](https://tailscale.com/kb/1244/tsnet)).
  - Tailscale login has to happen inside our app (use `ASWebAuthenticationSession`; never embed OAuth client secrets).
  - The node must come back up after each suspension.
  - The LocalAPI is "somewhat incomplete" (README).
  - Non-OS cryptography adds export-compliance paperwork.
- **Security:** same as C.
- **Setup friction:** medium (login), but contained in one app.
- **App Store:** allowed per the README and NovaScale's listing. No Network Extension is involved, so guideline 5.4 on VPN apps should not apply [judgment].

#### E. Cloudflare Tunnel, ngrok and other reverse tunnels (custom HTTPS URL)

- **How it works.** The user runs `cloudflared`, ngrok, zrok, frp or similar. The phone uses the public HTTPS URL, optionally behind Cloudflare Access.
- **Pros:**
  - Fits existing setups and custom domains.
  - Cloudflare Access adds an identity layer in front of opencode.
- **Cons:**
  - The tunnel operator terminates TLS and can see plaintext. This is unlike OpenTunnel and Tailscale Funnel, and is not end-to-end.
  - **Cloudflare Quick Tunnels are unusable for opencode.** Cloudflare's docs state "Quick Tunnels do not support Server-Sent Events (SSE)". They also cap in-flight requests at 200 and change hostname on every run ([Cloudflare](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/)).
  - **Named tunnels** need a domain in the user's Cloudflare account.
  - Cloudflare's proxy read timeout is 125 s ([Cloudflare](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-524/)). That is harmless given opencode's heartbeats (every 15 s in v2, 10 s in v1), but proxies that buffer or silently drop SSE have caused zombie streams ([#51857](https://github.com/anomalyco/opencode/issues/51857)).
  - **ngrok's free plan** is capped at 1 GB of egress and 20,000 HTTP requests a month. Its browser interstitial is skipped with an `ngrok-skip-browser-warning` header ([ngrok](https://ngrok.com/docs/pricing-limits/free-plan-limits/)).
- **Security:** depends on the provider. Cloudflare Access service tokens (`CF-Access-Client-Id` and `CF-Access-Client-Secret` headers, [Cloudflare](https://developers.cloudflare.com/cloudflare-one/identity/service-tokens/)) add a strong pre-auth layer that a native app can send on every request.
- **Setup friction:** medium to high.
- **App Store:** none. The app must support per-server **custom headers** and Basic auth.

#### F. SSH port forwarding inside the app

- **How it works.**
  - The app opens SSH to the dev host or a bastion and a `direct-tcpip` channel to `127.0.0.1:49374`. HTTP and SSE run over that channel.
  - [Citadel](https://github.com/orlandos-nl/Citadel) (MIT, 386★, 0.12.1 released 2026-04-04) wraps [swift-nio-ssh](https://github.com/apple/swift-nio-ssh) (Apache-2.0, 520★, 0.15.0 released 2026-07-28) and documents TCP-IP forwarding.
  - grapeot's client already ships this. The official docs recommend `ssh -L` for remote hosts ([web docs](https://github.com/anomalyco/opencode/blob/dev/services/www/src/docs/content/cli/web.mdx)).
- **Pros:**
  - No server changes.
  - Reuses existing SSH access to cloud dev boxes, VPSes and home servers.
  - Strong key-based authentication and encryption.
- **Cons:**
  - The SSH port still has to be reachable, so mostly cloud machines, or SSH over Tailscale.
  - swift-nio-ssh implements only modern algorithms (Ed25519, ECDSA, AES-GCM, X25519) and **no RSA**. Citadel's RSA support comes through a pinned fork of swift-nio-ssh, which is a maintenance risk (per the Citadel README and Package manifest).
  - Host-key verification UX. Use trust-on-first-use pinning in the Keychain.
  - The tunnel dies on suspension. Termius documents that iOS stops background activity "within 20 to 30 seconds" ([Termius](https://docs.termius.com/help-center/faq/how-can-i-keep-termius-sessions-alive-in-the-background-on-ios-ipados)). Do not copy the location-tracking keep-alive tricks some terminals use, because guideline 2.5.4 limits background modes to their intended purpose.
  - More code paths. Also, the PTY uses WebSockets, so the tunnel must carry them too.
- **Security:** strong.
- **Setup friction:** medium (keys).
- **App Store:** fine; Termius and Blink are precedents.

#### G. Our own end-to-end encrypted relay (Happy, Paseo, OpenChamber or ocremote style)

- **How it works.** A companion on the dev machine dials out to a relay. The phone meets it there, with keys exchanged through the QR code, and the relay forwards opaque frames. Examples: Paseo uses a NaCl box with the daemon key in the QR ([security](https://github.com/getpaseo/paseo/blob/main/public-docs/security.md)); ocremote pins an Ed25519 key in the QR and uses HKDF plus AES-256-GCM ([npm](https://www.npmjs.com/package/ocremote)).
- **Pros:**
  - Nothing is publicly addressable, and only paired devices can talk to the server.
  - Per-device revocation is natural.
  - The same relay can also carry push and store-and-forward.
- **Cons:**
  - We operate the infrastructure: uptime, cost, abuse.
  - Needs a companion install, because opencode does not speak our protocol.
  - A custom transport instead of plain `URLSession`.
  - Largely duplicates OpenTunnel for v2 users.
- **Security:** excellent if the handshake is mutually authenticated, with replay protection and per-device keys. Paseo admits its replay protection is incomplete.
- **Setup friction:** low after installing the companion.
- **App Store:** fine.

#### H. WebRTC or other peer-to-peer (hole punching, iroh)

- **How it works.** A signalling server exchanges offers. ICE and STUN punch through NAT, with TURN as a fallback.
- **Pros:** direct paths and low latency.
- **Cons:**
  - Needs a companion, because opencode does not speak WebRTC.
  - TURN is needed for symmetric NAT and CGNAT.
  - A heavy native library.
  - ICE restarts on every network change.
  - It buys nothing over Tailscale or OpenTunnel for an HTTP+SSE workload.
  - The proposal for opencode itself was closed ([#19013](https://github.com/anomalyco/opencode/issues/19013)).
  - Remote for OpenCode shows a Mac-only variant: UDP hole punching with iCloud rendezvous.
- **Verdict:** not worth it.

### 4.3 Recommended layered strategy

**Layer 0: one server, many endpoints, one credential.**
- Model a "server" as an identity plus a list of candidate endpoints (LAN, Tailscale, OpenTunnel, custom HTTPS, SSH) sharing one credential.
- Fill it from:
  - opencode's own pairing inputs: the `{code, urls}` QR payload, `/auth/connect/<code>` links, legacy `/connect#…` links;
  - manual URL plus password;
  - optional per-endpoint custom headers;
  - an optional SSH profile.
- Redeem pairing codes exactly like the reference client: race every URL, prefer the first if it answers within a second, and keep the token ([pairing.ts](https://github.com/anomalyco/opencode/blob/dev/packages/app/src/servers/connect/pairing.ts)).
- Refresh the endpoint list from `GET /api/info` (`urls`) on every connect, because the tunnel URL appears there while connected ([PR #53837](https://github.com/anomalyco/opencode/pull/53837)).
- Store secrets in the Keychain with `AfterFirstUnlockThisDeviceOnly`.
- Session tokens expire after 30 days, so build a smooth "re-pair" flow.

**Layer 1: endpoint racing and a reconnect/resync engine (this matters more than any single transport).**
- On launch, foreground and every `NWPathMonitor` change, race a cheap authenticated probe across endpoints. Prefer LAN when it answers, otherwise the fastest remote endpoint. Show the active path in the UI, as OpenChamber does with LAN versus relay.
- Run SSE only in the foreground:
  - a byte-level heartbeat watchdog (no bytes for ~40 s means the stream is dead; v2 heartbeats are SSE comments every 15 s);
  - backoff with jitter;
  - a full REST resync of sessions, messages, pending permissions and forms after every reconnect, because events are live-only.
- Make prompt submission idempotent with client-generated message IDs, plus an outbox that survives suspension.

**Layer 2: OpenTunnel as the default "anywhere" path.**
- Support it from day one: it is just HTTPS.
- In onboarding, recommend `opencode pair --remote` (or the desktop's "Pair device").
- Explain plainly that it exposes the server to the internet, protected by the server password.
- Detect the known failure modes and give specific advice: DNS blocklists on `*.opentunnel.xyz`, and the service being down.

**Layer 3: private paths for people who want no internet exposure.**
- LAN with `NSAllowsLocalNetworking` and the Local Network prompt.
- The Tailscale app (`100.x` addresses, or MagicDNS with `tailscale serve` HTTPS).
- Bonjour browsing of `_http._tcp` for v1 servers.

**Layer 4: power-user paths.**
- Custom HTTPS URLs with custom headers: Cloudflare named tunnels with Access service tokens, ngrok, Tailscale Funnel.
- An in-app SSH tunnel through Citadel or swift-nio-ssh, for cloud dev boxes and VPSes.

**Later, only if needed.**
- Embedded TailscaleKit, for corporate users with a conflicting VPN.
- Our own end-to-end relay, if OpenTunnel proves unreliable or if v1 servers matter. It can share infrastructure with the push relay.

**Not recommended.** WebRTC and other bespoke P2P.

### 4.4 App Review checklist for a self-hosted client

- **Guideline 2.1, demo access.** It requires demo account information "(and turn on your back-end service!)"; a built-in demo mode needs "prior approval by Apple" ([guidelines](https://developer.apple.com/app-store/review/guidelines/)). Run a **hosted demo opencode server** with a reviewer token, and also offer a local demo mode as OpenLens, dzianisv and ocremote do. A developer-forum thread reports a self-hosted-only client being rejected under 2.1 ([forum](https://developer.apple.com/forums/thread/815919)).
- **Guideline 4.2.3(i).** The app must work without installing another app, so Tailscale or ntfy can only be optional paths.
- **Guideline 4.2.7.** It restricts remote-desktop "mirror" apps to LAN-only connections. Present the app as a native client of an HTTP API, not a screen or terminal mirror [judgment].
- **Guideline 2.5.5.** IPv6-only networks must work.
- **Privacy.** Publish a privacy policy and keep the relay content-blind (Section 5).
- **Export compliance.** Declare it if we ship non-OS cryptography such as libsodium or the Tailscale Go runtime.

---

## 5. Push notifications when the server is self-hosted

### 5.1 The hard constraint

- APNs only accepts notifications signed with the app developer's credentials: a token-signing `.p8` key bound to the developer's Team ID, addressed to the app's bundle-ID topic. Those credentials cannot be handed to every user's `opencode serve`.
- So any App Store app that wants background alerts from a self-hosted server needs one of these:
  1. a developer-operated **relay** that holds the key;
  2. a **third-party push service** that holds it for you (Expo, Firebase, ntfy.sh upstream, CloudKit);
  3. **no APNs at all**: Web Push to a PWA, a chat bot, or OS-scheduled background wakeups.
- The Matrix spec states the rule plainly: "As APNS requires that the sender has a private key owned by the app developer, each app must have its own push gateway" ([spec](https://github.com/matrix-org/matrix-spec/blob/main/content/client-server-api/modules/push.md)).
- Apple's limits apply whichever route is chosen:
  - **Credentials and tokens:**
    - Token auth is an ES256 JWT signed with the `.p8` key, refreshed no more than once every 20 minutes and at least once an hour ([Apple](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns)).
    - Device tokens are per app and device and change on reinstall or restore, so register on every launch.
    - TestFlight and App Store builds use the production environment.
    - APNs answers `410 Unregistered` for dead tokens and `429` when one device gets too many pushes ([Apple](https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns)).
  - **Delivery:**
    - Payloads are capped at 4 KB ([Apple](https://developer.apple.com/documentation/usernotifications/generating-a-remote-notification)).
    - APNs keeps only the latest undelivered notification per app for an offline device, and delivery is best-effort. Treat every push as a hint and resync on open.
    - Background (silent) pushes are throttled: Apple advises against more than two or three an hour ([Apple](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)). Use visible alerts for anything that matters.
  - **Notification Service Extension (NSE):**
    - It gets "no more than 30 seconds" to rewrite or decrypt content, and runs only for alert pushes with `mutable-content: 1` ([Apple](https://developer.apple.com/documentation/usernotifications/unnotificationserviceextension/didreceive(_:withcontenthandler:))).
    - Suppressing a notification entirely from the NSE needs the restricted `usernotifications.filtering` entitlement ([Apple](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.usernotifications.filtering)). Plan on *replacing* stale alerts rather than hiding them.
  - **Live Activities:** update tokens, push-to-start tokens (iOS 17.2+) and broadcast channels all go through the same developer APNs credentials ([Apple](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications), [pushToStartTokenUpdates](https://developer.apple.com/documentation/activitykit/activity/pushtostarttokenupdates)). ActivityKit pushes go straight to the widget, never through an NSE, so their `content-state` is readable by whoever sends them.

### 5.2 What existing tools actually do

**Coding-agent tools**

| Tool | Who holds the APNs key | What the push path sees | Notes |
|---|---|---|---|
| OpenChamber (opencode-based) | Central Cloudflare-Worker relay holds the single `.p8`; self-builders can switch to "direct" mode with their own key | Generic title ("Agent needs permission"), device token, session id, and a sealed blob (AES-256-GCM with a 32-byte key shared at registration, at most 250 chars, opened by the NSE). The relay stores only `token → serverId` hashes | Servers sign relay requests with an auto-generated P-256 key, so a leaked device token is useless. ±5 min timestamp window; per-token sandbox/production environment; `apns-collapse-id` per event tag; badge = number of distinct tags; foreground banners suppressed on the device ([APNS.md](https://github.com/openchamber/openchamber/blob/main/packages/web/server/lib/notifications/APNS.md)). **The best existing model to copy** |
| Happy, Happier | Expo (EAS credentials) | Plaintext title and body (session summary or folder) | Server skips push when a UI client is active; Happier has Allow/Deny/Answer actions that open the app (Section 3) |
| Paseo | Expo | Plaintext "Agent finished" plus preview | Daemon calls `exp.host` directly ([push-service.ts](https://github.com/getpaseo/paseo/blob/main/packages/server/src/server/push/push-service.ts)) |
| Remodex | Its relay's push service holds the `.p8`; bridge authenticates with a per-session `notificationSecret` | Plaintext preview up to 160 chars | Self-hosters need their own APNs key ([push-service.js](https://github.com/Emanuele-web04/remodex/blob/main/relay/push-service.js)) |
| Sesori | Sesori backend, then FCM | Plaintext question or permission text | Payloads end-to-end encrypted, pushes not |
| Moshi | Expo; Live Activities over APNs | Prompt ≤200 chars, response ≤80, approval command ≤256, plus project/session/tool metadata ([hooks](https://getmoshi.app/docs/hooks)) | Has an opencode plugin (`.opencode/plugins/moshi-hooks.ts`); approval round-trips over its WebSocket |
| Claude Code Remote Control | Anthropic (first-party Claude app) | Everything (Anthropic also runs the model) | "Push when actions required" plus model-initiated pushes; presence suppression ([docs](https://code.claude.com/docs/en/remote-control)) |
| Remote for OpenCode | **Apple, via CloudKit**: the Mac companion writes to the user's own iCloud private database and "CloudKit routes a contentless nudge"; the phone then fetches details over its encrypted link ([README](https://github.com/tjameswilliams/remote-for-opencode)) | Nothing but the wake-up | No developer server at all, but needs a Mac companion signed with the same iCloud container |
| Tailscode | No push. A long request to the v2 server is held until the turn ends, and iOS wakes the app to post a local notification ([#3](https://github.com/guitaripod/Tailscode/issues/3)) | Nothing leaves the tailnet | Probably uses `POST /api/experimental/session/{id}/wait` [inference] ("Wait for a session agent loop to become idle", [OpenAPI](https://github.com/anomalyco/opencode/blob/dev/packages/protocol/openapi.json)) via a background `URLSession`. Background sessions run transfers in a separate process and wake the app on completion, but a user force-quit cancels them ([Apple](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:))). Only covers "finished", not new permission requests mid-turn |
| OpenClient ("OC Notify") | Nobody: Web Push | Browser push service | Requires the OpenClient plugin, your own HTTPS endpoint and a companion PWA on the Home Screen. "No OpenClient-hosted notification relay is used" ([App Store listing](https://apps.apple.com/us/app/openclient-for-opencode/id6763641767)) |
| opencode PR #47374 (closed) | Nobody: Web Push from the opencode server itself (VAPID) | Browser push service | Best-effort: ≤100 subscriptions, 128-event in-memory queue, no retries; iOS needs a Home Screen PWA on 16.4+ ([PR](https://github.com/anomalyco/opencode/pull/47374)) |
| BYOT (planned) | "A small self-hosted OpenCode companion and a dedicated relay" | "server credentials and transcript content remain on the user's computer" ([#73](https://github.com/steventsao/byot/issues/73)) | |
| Telegram/Discord bots | Telegram/Discord | Everything they display | Push for free; inline-button approvals ([grinev bot](https://github.com/grinev/opencode-telegram-bot)) |
| Pushary | Pushary (hosted, $9.99–19.99/mo) | Title, body, tool name; transcripts "redacted and encrypted on your machine" ([pushary.com](https://pushary.com)) | |

**Self-hosting precedents outside coding agents**

- **ntfy.** A self-hosted ntfy server cannot push to the App Store ntfy app directly. With `upstream-base-url: "https://ntfy.sh"` it forwards a poll request that "contains only the message ID (in the `X-Poll-ID` header)" and the literal text "New message". ntfy.sh relays that through Firebase to APNs. The iOS app then "fetches the actual message from your server" ([ntfy docs](https://docs.ntfy.sh/config/#ios-instant-notifications)). Without the upstream, delivery "can take hours". This is the canonical "content-free wake-up" pattern.

| Project | Who holds the APNs key | What the relay sees | Lesson |
|---|---|---|---|
| Nextcloud | push-notifications.nextcloud.com | Device identifier plus a subject encrypted to the device's RSA key and signed with the user's key ([push-v2](https://github.com/nextcloud/notifications/blob/master/docs/push-v2.md)) | Shipping the key with every server would let anyone "push to any random Nextcloud device" |
| Mattermost | Hosted push proxy (HPNS/TPNS) | In "ID-only" mode, only IDs; the app fetches content ([config](https://docs.mattermost.com/administration-guide/configure/push-notification-server-configuration-settings.html)) | Self-hosting the proxy requires your own app build ([doc](https://docs.mattermost.com/deployment-guide/mobile/host-your-own-push-proxy-service.html)) |
| Matrix / Element | Per-app Sygnal gateway ([sygnal](https://github.com/element-hq/sygnal)) | With `event_id_only`, event and room IDs and counts | Same as Mattermost |
| Signal | Signal | Only `mutable-content` and a placeholder; the NSE fetches and decrypts ([APNSender.java](https://github.com/signalapp/Signal-Server/blob/main/service/src/main/java/org/whispersystems/textsecuregcm/push/APNSender.java)) | Content-free wake-up |
| Home Assistant | Its open-source Firebase relay, which also drives Live Activities ([repo](https://github.com/home-assistant/mobile-apps-fcm-push)) | Plaintext title and body. 500 notifications per device per day ([docs](https://companion.home-assistant.io/docs/notifications/notification-details)) | Also offers "Local Push" over a WebSocket on configured Wi-Fi networks, with no relay ([docs](https://companion.home-assistant.io/docs/notifications/notification-local)). Apple's API for this kind of LAN delivery, Local Push Connectivity, needs an entitlement ([Apple](https://developer.apple.com/documentation/networkextension/local-push-connectivity)) |
| Bark | The developer, but the `.p8` private key is **embedded in the open-source bark-server** ([apns_certs.go](https://github.com/Finb/bark-server/blob/master/apns/apns_certs.go)) | Self-hosted servers push to APNs directly; optional AES payload encryption | Anti-pattern: anyone holding a device token can spam it, and it risks key revocation |
| Swiftfin (Jellyfin) | — | — | Push request closed because a self-hosted server cannot hold the key ([#672](https://github.com/jellyfin/Swiftfin/issues/672)) |

### 5.3 Recommended design

**The idea in one sentence:** a tiny relay we operate is a *doorbell that carries a sealed envelope*. The opencode server rings it, only the phone can open the envelope, and every reply travels back over the normal direct connection (OpenTunnel, Tailscale or LAN), never through the relay.

```
(1) event      opencode server + "ios-push" plugin  (user's machine)
                 │  seals {kind, session, request, summary} to the phone's public key
                 ▼
(2) doorbell   push relay  (ours: holds the APNs .p8 key, sees no content)
                 │  generic alert + mutable-content + ciphertext
                 ▼
(3) delivery   APNs ──▶ iPhone: Notification Service Extension decrypts, shows rich alert + actions
                 │
                 ▼
(4) reply      app ──▶ POST /api/session/{id}/permission/{requestID}/reply
               over the direct path (OpenTunnel / Tailscale / LAN) with normal opencode auth;
               the relay is never on the reply path
```

**Components and what each knows**

1. **opencode plugin (`ios-push`, runs inside the user's server).**
   - Subscribes to `ctx.event.subscribe()` and reacts to:
     - `permission.asked` and `form.created`: needs input, high priority;
     - `session.execution.failed`: error;
     - `session.execution.succeeded` or `session.status` → `idle`: finished;
     - `permission.replied` and `form.replied`: retract or replace the alert.
   - These are the v2 event names in [the schema](https://github.com/anomalyco/opencode/tree/dev/packages/schema/src). The events are ephemeral, which is why the notifier must live in-process rather than in the phone.
   - For v1 servers the equivalents, delivered through the v1 plugin `event` hook, are `permission.asked`/`permission.replied`, `question.asked`/`replied`/`rejected`, `session.idle` and `session.error` ([v1.19.1 SDK types](https://github.com/anomalyco/opencode/blob/v1.19.1/packages/sdk/js/src/v2/gen/types.gen.ts)).
   - Exposes plugin RPC methods: `registerDevice`, `unregisterDevice`, `listDevices` and `test`. Any authenticated client can call them through `POST /api/rpc/{rpcID}/{method}` ([client docs](https://github.com/anomalyco/opencode/blob/dev/services/www/src/docs/content/build/client/index.mdx)), so the app registers itself over its existing authenticated connection with no new pairing step.
   - Seals a small JSON payload per device. Contents: kind, server-local session id and title, request id, a summary of at most ~300 characters (the command, file path or question), option labels, an expiry, and a digest of the full request.
     - Use HPKE (`Curve25519_SHA256_ChachaPoly`), which CryptoKit provides from iOS 17 ([Apple](https://developer.apple.com/documentation/cryptokit/hpke)); any RFC 9180 library works on the server side.
     - Prefer HPKE's *authenticated* mode, with the plugin's static key pinned by the app at registration ([HPKE.Recipient](https://developer.apple.com/documentation/cryptokit/hpke/recipient)). Then neither the relay nor anyone who learns a device public key can forge an alert.
     - Pad plaintexts to fixed buckets (for example 512 bytes) so ciphertext size does not leak command length.
     - It then POSTs the sealed payload to the relay.
   - Delays "needs input" pushes by ~5–10 s and cancels them if the request is answered first. Claude Code does the same: its `permission_prompt` notification fires "only after the prompt has waited about six seconds", and `idle_prompt` fires about 60 seconds after a response if you have not typed ([hooks docs](https://code.claude.com/docs/en/hooks)).
   - Keeps device registrations (relay device id, send token, device public key, preferences) in a 0600 file in the global config directory.
   - **Knows:** everything, as it is the user's own server. **Never learns:** the APNs device token.
   - A sidecar process using `@opencode/client` and `Service.discover()` can implement the same contract for users who do not want a plugin.
2. **Push relay (we run it, open source, stateless apart from a device table).**
   - Holds the APNs token-auth `.p8` key.
   - Its API:
     - `POST /v1/devices`, called by the app with its APNs token, its environment and an App Attest assertion. App Attest certifies "a valid instance of your app" ([Apple](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity)), which keeps scripted registrations out. It returns a random `deviceId` and a 256-bit `sendToken`, and stores only the token's hash.
     - `POST /v1/push`, called by the plugin with `{deviceId, sendToken, kind, collapseId, ciphertext}`.
     - `DELETE /v1/devices/{id}`.
     - Equivalent endpoints for Live Activity tokens.
   - It builds the APNs request:
     - a **generic** visible alert, such as "opencode needs your approval" or "A session finished";
     - `mutable-content: 1`, `category` by kind, `thread-id` set to an opaque per-session hash, and `apns-collapse-id` set to the request id;
     - an interruption level:
       - `time-sensitive` for input requests. These "can break through system controls such as Notification Summary and Focus", the user can turn them off, and the app must enable the Time Sensitive capability ([Apple](https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive)).
       - `active` for finished and error.
       - `passive` for progress.
     - `relevance-score` for ranking in summaries;
     - the ciphertext in a custom key, capped at about 3 KB to stay under the 4 KB payload limit.
   - **Knows:** device tokens, timing, coarse kind, and the server's egress IP. **Never knows:** prompts, commands, paths, session titles, or which opencode server a device belongs to beyond an opaque token.
   - This mirrors OpenChamber's relay ([APNS.md](https://github.com/openchamber/openchamber/blob/main/packages/web/server/lib/notifications/APNS.md)). The difference is that a per-device send token replaces OpenChamber's server-signature binding. Either works, and the signature approach is preferable if one server pushes to many devices.
3. **iOS app plus Notification Service Extension.**
   - Per paired server, the app generates an X25519 key pair (`Curve25519.KeyAgreement`). The private key goes in a Keychain access group shared with the NSE, with `AfterFirstUnlockThisDeviceOnly` accessibility so a locked phone can still decrypt.
   - The app registers with the relay, then calls `registerDevice` on the server.
   - The NSE has ≤30 s. It decrypts the envelope, then:
     - sets the title (for example "Allow `bash`?"), the subtitle (session title) and the body (command, path or question);
     - picks a category: permission, question, finished or error;
     - groups by session.
   - On any failure, the generic text stays.

**Actionable notifications and their safety**

- **Permission category.** Order and flags matter:
  1. "Open" (foreground) comes first. On Apple Watch Series 9 and Ultra 2, Double Tap "invokes the first nondestructive action" ([Apple](https://developer.apple.com/documentation/usernotifications/declaring-your-actionable-notification-types)), so a wrist gesture must never land on an approval.
  2. "Allow once" uses `.authenticationRequired`, so "the system prompts the user to unlock the device" first ([Apple](https://developer.apple.com/documentation/usernotifications/unnotificationactionoptions/authenticationrequired)). It is also flagged `.destructive`, which keeps it out of Double Tap.
  3. "Reject" maps to `reply: "reject"`. "Reject with note…" is a `UNTextInputNotificationAction` that sends the optional `message`, which opencode turns into corrective feedback for the agent.
  - The notification copy must say that rejecting one request **rejects every other pending request in the same session**. That is what v2's `Permission.reply` does ([core/permission.ts](https://github.com/anomalyco/opencode/blob/dev/packages/core/src/permission.ts)).
  - Do **not** offer "Always allow" from a notification. In v2 it saves a rule and auto-approves other matching pending requests (same file). That belongs in the app, where the full rule and diff are visible.
  - For commands the app classes as high risk (`rm -r`, `sudo`, force-push, writes outside the project), show only "Open" and "Reject". This is the risk tiering that Remote for OpenCode uses.
- **Question category:**
  - A `UNTextInputNotificationAction` handles free-text answers.
  - Multiple-choice forms can show their real options through a Notification Content Extension, which can replace a notification's buttons at display time (`NSExtensionContext.notificationActions`, iOS 12+, [Apple](https://developer.apple.com/documentation/foundation/nsextensioncontext/notificationactions)). Otherwise they open the app.
- **Handling an action:**
  - The system launches the app in the background.
  - The app re-reads the pending request: `GET /api/permission/request`, or the session's permission list. It checks that the request still exists and that its digest matches what the notification showed, so the user approves exactly what they saw.
  - It then sends `POST /api/session/{id}/permission/{requestID}/reply` ([OpenAPI](https://github.com/anomalyco/opencode/blob/dev/packages/protocol/openapi.json)), over the fastest reachable endpoint, using the stored session token, with a timeout of 10 s or less.
  - On success it replaces the alert with "Approved". A reply to an unknown request fails with `NotFoundError` ([core/permission.ts](https://github.com/anomalyco/opencode/blob/dev/packages/core/src/permission.ts)); in that case it says "Already handled".
  - If the server is unreachable, it posts a local "Couldn't reach your server — tap to retry". It never assumes success.
  - Pending requests live in server memory and are rejected when the server instance is disposed (same file), so a restart turns old notifications into "expired".
- **Phase 2: a return path for unreachable servers.** The app signs `{requestID, digest, decision, expiry, nonce}` with a Secure Enclave P-256 key and drops it at the relay. The plugin collects it over an outbound connection and verifies the signature, nonce and expiry before replying locally. A malicious relay could delay or drop an approval, but never forge one. Moshi and Claude Remote Control use the same outbound-pull shape.
- **Silence is never consent.** Nothing auto-approves when a notification expires. This is the lesson from [#39628](https://github.com/anomalyco/opencode/issues/39628), and it matches Claude Code keeping permission prompts open indefinitely.
- **One pending request makes one notification.**
  - The collapse id is the request id. When the request is answered on another device, the plugin sends a replacement alert with the same collapse id ("Approved on desktop"), so stale prompts do not linger.
  - Badge = the number of unresolved requests, like OpenChamber's badge count of distinct tags.
- **Presence suppression, failing open:**
  - The plugin skips "finished" pushes for a session that a client viewed in the last ~60 s (`session.viewed` exists in the v2 schema). Users can also opt into Claude-style "not while I'm at my desk" behaviour.
  - Input requests are always pushed unless the user opts out.
  - The app suppresses foreground banners for the session on screen.
- **Delivery health:**
  - The relay returns per-device outcomes, and `listDevices` exposes "last delivered at…".
  - The app shows a warning when pushes are failing, so a silent outage like Happy's ("invisible for two months") cannot happen.

**Live Activities**

- **Start.** Start one locally when the user sends a prompt from the phone, or remotely through a push-to-start token (iOS 17.2+). The remote path is for sessions started at the desk and is opt-in.
- **Update.** The plugin sends updates through the relay's Live Activity endpoint.
- **Keep content-state coarse:** phase (running, waiting for input, done, failed), step count, elapsed time and a needs-input flag. Unlike alerts, content-state goes straight to the widget extension with no NSE, so anything in it is visible to the relay and to Apple. Take the session title from the App Group cache, not from the push.
- **Budget.** Priority-10 updates draw on an hourly budget and priority-5 updates do not. Use priority 5 for progress (at most one update every 30–60 s) and priority 10 with an alert only for "needs approval". `NSSupportsLiveActivitiesFrequentUpdates` raises the budget, but users can switch it off ([Apple](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)).
- **Lifetime.**
  - Apple: "A Live Activity can be active for up to eight hours", and it "remains on the Lock Screen for a maximum of 12 hours" ([Apple](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)).
  - Restart long sessions, and set a `dismissal-date` on end.
  - Set `stale-date` a few minutes ahead on each update, so a sleeping laptop shows as stale instead of "running".
- **Where it appears.** Live Activities also appear in the Apple Watch Smart Stack, the Mac menu bar and CarPlay ([Apple](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)). That makes them the right surface for "agent is working / waiting for you".
- **Buttons.**
  - Interactive buttons run a `LiveActivityIntent` in the app's process. Apple states: "On a locked device, buttons and toggles are inactive and the system doesn't perform actions unless a person authenticates and unlocks their device" ([Apple](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)).
  - An "Approve" button is therefore technically gated. Still keep it to "Open" and "Stop" unless the app has the decrypted request details cached locally, so that what is shown matches what is approved.

**Privacy-maximal and zero-relay options (opt-in)**

- **Local only.** No push. While the app is backgrounded mid-turn, a background `URLSession` request to `POST /api/experimental/session/{id}/wait` wakes the app when the session goes idle (the Tailscode technique). Limitations:
  - it is an experimental endpoint;
  - it does not fire for permission requests mid-turn, because the session never goes idle;
  - a force-quit cancels it;
  - over OpenTunnel, a connection with no bytes for 15 minutes is reset (`CONNECTION_IDLE_TIMEOUT_MS = 900000`, [server.md](https://github.com/anomalyco/opentunnel/blob/master/docs/server.md)).
- **ntfy.** The plugin can publish content-free messages to the user's own ntfy server (with the ntfy.sh upstream), whose iOS app then fetches the text from the user's server ([ntfy docs](https://docs.ntfy.sh/config/#ios-instant-notifications)). The notification's click URL deep-links into our app. Never put opencode credentials into ntfy action buttons.
- **ID-only mode.** The push carries only an opaque request id. The NSE fetches the details from the user's server within its 30 s window, the Mattermost, Matrix and Signal pattern. The relay then sees nothing but timing, at the cost of generic text whenever the server is unreachable from the phone.
- **LAN-only push without APNs.** Apple's Local Push Connectivity keeps a provider extension connected to a local server on configured Wi-Fi networks. It needs an entitlement and does not work away from home, so it is not worth it here ([Apple](https://developer.apple.com/documentation/networkextension/local-push-connectivity)).
- **Self-built app.** The relay is open source, so people who build the app themselves can run it with their own APNs key. App Store users cannot avoid our relay, which is why it must be content-blind and auditable. Never publish the key, as Bark does.

**Failure modes to design for**

- Relay down: the plugin retries briefly with a bounded queue and then drops. The app's foreground streaming still works, and the app shows "notifications degraded".
- APNs token rotation: the app re-registers its token idempotently on every launch.
- App deleted: APNs returns 410, so the relay deletes the device and answers `gone`, and the plugin removes the registration.
- Laptop asleep or opencode stopped: no events means no pushes. An opt-in relay heartbeat can alert "server offline", but it reveals uptime metadata.
- Several servers on one phone: one key pair and send token per server, and the envelope carries a key id.
- Abuse:
  - only the paired server holds a device's send token;
  - App Attest-gated registration;
  - rate limits per device and per token, for example ~30 alerts a minute in bursts and a few hundred a day (Home Assistant allows 500 a day per device);
  - backing off on APNs `429`;
  - a payload size cap;
  - tokens revoked on unpair;
  - logs of counts only, never payloads.

**Strategic note.** Anomaly ships an official iOS app and has not published its push mechanism: the beta's notifications use a server plugin from a private repository (Section 1.1) (corrected 2026-10-15). It is worth proposing a small, vendor-neutral "push target" plugin contract upstream, so that `opencode` can serve several mobile clients at once and our plugin is not a fork of whatever the official app adopts.

---

## 6. Open questions and what to watch

- **The official iOS app.**
  - Its tech stack (probably native Swift), its remaining features, how its private notification plugin delivers pushes, and when (and whether) it reaches the App Store (corrected 2026-10-15).
  - Whether it will remain free.
  - Whether Anomaly publishes a push or relay contract.
  - Watch the [changelog](https://opencode.ai/changelog), TestFlight notes, and PRs mentioning "iOS app".
- **OpenTunnel maturity.** Uptime, regional reach, rate limits and terms of use for third-party clients. Its repository does not accept pull requests ([README](https://github.com/anomalyco/opentunnel)).
- **Per-device revocation in opencode auth.** Today one password-derived key signs every session token ([PR #50970](https://github.com/anomalyco/opencode/pull/50970)). Per-device tokens would be worth proposing upstream; OpenChamber shows the model.
- **v2 discovery.** No mDNS in v2. A `_opencode._tcp` Bonjour type with version and TLS-fingerprint TXT records would be a small upstream proposal.
- **The `wait` endpoint.** `POST /api/experimental/session/{id}/wait` is experimental. If it stabilizes, it enables relay-free "finished" alerts on private networks.
- **Unverified items to test on device.**
  - TailscaleKit's binary size and resume latency.
  - The `BGContinuedProcessingTask` approach for following a phone-initiated turn.
  - SSE behaviour through Cloudflare named tunnels.
  - Live Activity update budgets under real use.

## 7. Key sources

Official opencode:
- [anomalyco/opencode](https://github.com/anomalyco/opencode)
- [changelog](https://opencode.ai/changelog)
- [download page](https://opencode.ai/download)
- [web and remote-access docs](https://github.com/anomalyco/opencode/blob/dev/services/www/src/docs/content/cli/web.mdx)
- [client docs](https://github.com/anomalyco/opencode/blob/dev/services/www/src/docs/content/build/client/index.mdx)
- [plugin docs](https://github.com/anomalyco/opencode/blob/dev/services/www/src/docs/content/build/plugins/index.mdx)
- [OpenAPI spec](https://github.com/anomalyco/opencode/blob/dev/packages/protocol/openapi.json)
- PRs [#50970](https://github.com/anomalyco/opencode/pull/50970), [#53837](https://github.com/anomalyco/opencode/pull/53837), [#54561](https://github.com/anomalyco/opencode/pull/54561), [#55306](https://github.com/anomalyco/opencode/pull/55306), [#54426](https://github.com/anomalyco/opencode/pull/54426), [#47374](https://github.com/anomalyco/opencode/pull/47374)
- Issues [#6536](https://github.com/anomalyco/opencode/issues/6536), [#10288](https://github.com/anomalyco/opencode/issues/10288), [#35943](https://github.com/anomalyco/opencode/issues/35943), [#39628](https://github.com/anomalyco/opencode/issues/39628), [#51857](https://github.com/anomalyco/opencode/issues/51857), [#54596](https://github.com/anomalyco/opencode/issues/54596), [#54627](https://github.com/anomalyco/opencode/issues/54627), [#55673](https://github.com/anomalyco/opencode/issues/55673)
- [OpenTunnel](https://github.com/anomalyco/opentunnel) and its [trust boundary](https://github.com/anomalyco/opentunnel/blob/master/docs/trust-boundary.md) and [server](https://github.com/anomalyco/opentunnel/blob/master/docs/server.md) docs
- [TestFlight](https://testflight.apple.com/join/EnFsKYQ1) and [announcement](https://x.com/thdxr/status/2108284341923049578)
- [OpenMobile QR gist](https://gist.github.com/R44VC0RP/da505bcc925c91dee0160a4c7577c1a3)

Clients and analogues:
- App Store listings linked in Section 2, read through Apple's public lookup API
- [OpenChamber APNs design](https://github.com/openchamber/openchamber/blob/main/packages/web/server/lib/notifications/APNS.md) and [Private Relay](https://github.com/openchamber/openchamber/blob/main/packages/docs/content/docs/private-relay.mdx)
- [Paseo security](https://github.com/getpaseo/paseo/blob/main/public-docs/security.md)
- [Happy encryption](https://github.com/slopus/happy/blob/main/docs/encryption.md)
- [Remote for OpenCode](https://github.com/tjameswilliams/remote-for-opencode)
- [Tailscode #3](https://github.com/guitaripod/Tailscode/issues/3)
- [ocremote](https://www.npmjs.com/package/ocremote)
- [Claude Code Remote Control](https://code.claude.com/docs/en/remote-control)
- [Codex remote-control source](https://github.com/openai/codex/blob/main/codex-rs/app-server-transport/src/transport/remote_control/protocol.rs)
- [Cursor iOS docs](https://cursor.com/docs/cloud-agent/web-and-mobile)
- [Copilot live notifications](https://github.blog/changelog/2026-07-08-github-mobile-live-notifications-for-copilot-cli-sessions)
- [Moshi hooks](https://getmoshi.app/docs/hooks)
- [ntfy iOS upstream](https://docs.ntfy.sh/config/#ios-instant-notifications)

Platform:
- Apple docs on [NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking), [local network keys](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription), [multicast entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast), [background URLSession](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:)), [NSE time limit](https://developer.apple.com/documentation/usernotifications/unnotificationserviceextension/didreceive(_:withcontenthandler:)), [payload size](https://developer.apple.com/documentation/usernotifications/generating-a-remote-notification), [authenticationRequired](https://developer.apple.com/documentation/usernotifications/unnotificationactionoptions/authenticationrequired), [ActivityKit push](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications), [CryptoKit HPKE](https://developer.apple.com/documentation/cryptokit/hpke)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [TailscaleKit](https://github.com/tailscale/libtailscale/tree/main/swift)
- [Tailscale and other VPNs](https://tailscale.com/kb/1105/other-vpns)
- [Cloudflare Quick Tunnels](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/)
- [Citadel](https://github.com/orlandos-nl/Citadel) and [swift-nio-ssh](https://github.com/apple/swift-nio-ssh)

## Verification pass (2026-10-15)

The first draft had 11 "unverified" tags: the conventions sentence plus 10 claims (rows 1–11). Rows E1–E11 are other claims found wrong or weakly sourced along the way, including the narrower "format", "mechanism" and "store details" unverified tags. Rows S1–S6 check the claims the product spec took from this report. Sources were read on 2026-10-15. The opencode source is commit `d0732ea`. "lookup" means `curl 'https://itunes.apple.com/lookup?id=<id>&country=us'`, and "thread" means `curl https://api.fxtwitter.com/2/conversation/2108284341923049578`, which returned 41 replies to Dax's announcement.

| # | Claim (short) | Outcome | Evidence (URL or command) |
|---|---|---|---|
| 1 | Conventions sentence describing the unverified tag | n/a (text updated to describe this pass) | — |
| 2 | §1.1: whether the TestFlight app has push | CORRECTED: it has notifications, which need a server plugin from the private `anomalyco/opencode-ios` repository | [#54483](https://github.com/anomalyco/opencode/issues/54483); thread replies [2108301296205775166](https://x.com/nematollahi97/status/2108301296205775166) and [2108295873822142861](https://x.com/peterpme/status/2108295873822142861); `gh api repos/anomalyco/opencode-ios` returns 404 |
| 3a | §1.3: official app and multiple servers | CORRECTED: supported | [Dax's reply](https://x.com/thdxr/status/2108290378243739659), via thread |
| 3b | §1.3: UI technology | CORRECTED: probably native Swift (inference) | [voice-delegation.test.ts](https://github.com/anomalyco/opencode/blob/dev/packages/app/src/session/timeline/voice-delegation.test.ts) (`"key" : value`, sorted keys); [PR #53946](https://github.com/anomalyco/opencode/pull/53946) (`OpenCodePairingLink.decode`) |
| 3c | §1.3: official app and push | CORRECTED (as row 2) | as row 2 |
| 3d | §1.3: Live Activities, iPad layouts, App Store timing, pricing | UNCONFIRMED | TestFlight page; thread; [changelog](https://opencode.ai/changelog); `gh search issues --repo anomalyco/opencode iOS`; one WebSearch with no hits. The app's repository is private |
| 4 | §2.2 Saffron: push and background | CORRECTED: none advertised; "no account, no relay" | lookup id 6806661363; [saffronsuite.com/oc](https://saffronsuite.com/oc) |
| 5 | §2.2 OC Remote: push and background | CORRECTED: none advertised | lookup id 6761319053; [ocremote.didac.dev](https://ocremote.didac.dev) |
| 6 | §2.2 OpenCoderMan: push and background | CORRECTED: none advertised | lookup id 6760598918; [thecodingman.net](https://thecodingman.net) |
| 7 | §2.2 Remodex: push and background | CORRECTED: APNs through its relay, plaintext previews of up to 160 characters | [push-service.js](https://github.com/Emanuele-web04/remodex/blob/main/relay/push-service.js); lookup id 6760243963 (release notes) |
| 8 | §2.3 Whatcode: connection and push | CORRECTED: daemon plus WhatCode relay to APNs, plaintext | [daemon.md](https://github.com/Pnlvfx/whatcode-ai/blob/main/apps/docs/docs/daemon.md), [apn.ts](https://github.com/Pnlvfx/whatcode-ai/blob/main/packages/sdk/src/apn/apn.ts); lookup id 6760623503 |
| 9 | §2.3 Remote Code: connection and push | CORRECTED: pairs with the Uplink desktop app; no push described | [remote-code.com/opencode](https://remote-code.com/opencode) |
| 10 | §2.4 Happier: 4.29 from 14 ratings | VERIFIED | lookup id 6758554297 |
| 11 | §4.2 B: latency to "the Fly.io deployment" varies by region | CORRECTED: eleven regions, nearest-machine routing, forwarding between regions | [server.md, "Multiple regions"](https://github.com/anomalyco/opentunnel/blob/master/docs/server.md#multiple-regions); [fly.toml](https://github.com/anomalyco/opentunnel/blob/master/fly.toml) |
| E1 | §1.4: OpenTunnel "runs on Fly.io (`iad`)" | CORRECTED: eleven regions since 2026-10-10 (the README is stale) | as row 11; `gh api "repos/anomalyco/opentunnel/commits?path=fly.toml"` (ca918ce) |
| E2 | OpenTunnel doc links pointed at `blob/main`, which returns 404 | CORRECTED: links now use `blob/master` | `gh api repos/anomalyco/opentunnel --jq .default_branch` returns `master` |
| E3 | "Only OpenLens accepts opencode pair links" (summary, §2.2, §2.6) | CORRECTED: OpenCody and alvarolorentedev's app do too | [PairingAPI.swift](https://github.com/fwilldev/OpenCody/blob/main/OpenCody%20-%20An%20OpenCode%20Client/Services/API/V2/PairingAPI.swift); [pairing.ts](https://github.com/alvarolorentedev/opencode-mobile/blob/main/lib/opencode/pairing.ts) |
| E4 | §2.2 OpenCody: pairing-link format `[format unverified]` | CORRECTED: opencode's own `/auth/connect/<code>` and `POST /api/pair` | as E3 |
| E5 | §2.2 OpenCody: notification mechanism | CORRECTED: local notifications from `BGAppRefreshTask` polling | [BackgroundRefreshService.swift](https://github.com/fwilldev/OpenCody/blob/main/OpenCody%20-%20An%20OpenCode%20Client/Services/BackgroundRefreshService.swift) |
| E6 | §2.2 KKCode: notification mechanism | CORRECTED: companion-registered plugin plus KKCode's notification service | kkcode.app FAQ (JSON-LD); `curl https://registry.npmjs.org/@kkcode-app%2Fagent` |
| E7 | §2.4 Sesori: store details | VERIFIED: App Store and Google Play | `curl 'https://itunes.apple.com/search?term=sesori&entity=software&country=us'`; [Play](https://play.google.com/store/apps/details?id=com.sesori.app) |
| E8 | Plaintext-push lists (summary 3, §2.6, §3.2) | CORRECTED: WhatCode added (plaintext); omnicus added (no content) | as row 8; [NOTIFICATIONS.md](https://github.com/omnicus/opencode2-mobile/blob/main/docs/NOTIFICATIONS.md) |
| E9 | §2.2 OpenClient: "best iPad story" | CORRECTED: the most elaborate layout advertised; untested judgment | lookup id 6763641767 ("Multi-column iPad layout for projects, sessions, and chat") |
| E10 | §1.3: official app is closed source (was an inference) | VERIFIED: its plugin repository returns 404 to the public | [#54483](https://github.com/anomalyco/opencode/issues/54483); `gh api repos/anomalyco/opencode-ios` |
| E11 | Summary 1, §1.6, §5.3 and §6 on official push | CORRECTED for consistency with row 2 | as row 2 |
| S1 | Over 25 third-party clients, including OpenLens, OpenClient, Paseo, OpenChamber, CodeNomad | VERIFIED: 20 listings live in one lookup plus Happier and Sesori, and 5 more repos | bulk lookup of the 21 ids in §2; `gh api repos/{openchamber/openchamber,NeuralNomadsAI/CodeNomad,getpaseo/paseo,grapeot/opencode_ios_client,alvarolorentedev/opencode-mobile,omnicus/opencode2-mobile}` |
| S2 | The v2 API change broke grapeot and WhisperCode | VERIFIED | [grapeot #169](https://github.com/grapeot/opencode_ios_client/issues/169) (open; "There is no build yet"); [WhisperCode #44](https://github.com/DNGriffin/whispercode/issues/44), [#46](https://github.com/DNGriffin/whispercode/issues/46); lookup id 6759430954 (last release 2026-04-27) |
| S3 | OpenChamber's sealed-push relay is worth copying; OpenClient has the best iPad layout | VERIFIED (OpenChamber); CORRECTED (OpenClient: advertised, untested) | [APNS.md](https://github.com/openchamber/openchamber/blob/main/packages/web/server/lib/notifications/APNS.md); as E9 |
| S4 | Relay-based apps push plaintext previews through Expo or FCM | CORRECTED: Expo (Happy, Happier, Paseo, Moshi), FCM (Sesori) or their own APNs relay (Remodex, WhatCode). OpenChamber seals; omnicus sends no content | [push-service.ts](https://github.com/getpaseo/paseo/blob/main/packages/server/src/server/push/push-service.ts), [pushDispatch.ts](https://github.com/slopus/happy/blob/main/packages/happy-server/sources/app/push/pushDispatch.ts), [content builder](https://github.com/sesori-ai/sesori_apps_monorepo/blob/main/bridge/app/lib/src/push/push_notification_content_builder.dart), [Happier docs](https://github.com/happier-dev/happier/blob/dev/apps/docs/content/docs/extras/notifications-setup.mdx), [Moshi hooks](https://getmoshi.app/docs/hooks), rows 7 and 8 |
| S5 | OpenTunnel ends TLS on the developer's machine, so the relay cannot read traffic | VERIFIED as designed. The relay still sees IPs, SNI and timing. Inference: the operator controls the DNS zone and ACME issuance, so a mis-issued certificate is possible in principle and would show in CT logs | `packages/cli/src/server-process.ts` lines 185–197 and `packages/cli/src/services/remote-tunnel.ts` at d0732ea (the server process embeds `@opentunnel/client` 0.4.0 and forwards decrypted traffic to its own listening address, loopback by default); [README](https://github.com/anomalyco/opentunnel); [protocol.md](https://github.com/anomalyco/opentunnel/blob/master/docs/protocol.md) (client-side key, CSR only) |
| S6 | The official app is not on the App Store and has no published push design | CORRECTED: not on the App Store (verified); push exists through an unpublished plugin | `curl 'https://itunes.apple.com/search?term=opencode&entity=software&country=us&limit=200'` (175 results, none from Anomaly); `curl 'https://itunes.apple.com/lookup?id=584743419&entity=software&country=us'` (Anomaly Innovations: only Rebase Trivia); row 2 |
