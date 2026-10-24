# Roadmap to the App Store

Status as of 2026-10-22. ARCHITECTURE.md §7 has the milestone definitions and SPEC.md §9 the open decisions. Each milestone lands on `main` only after its full verification passes, including two consecutive full UI smoke runs with the iPad flow. Its audit is in `docs/<milestone>-audit.md`.

## Blocked on the owner

These need the owner's accounts, money, devices or decisions. Claude and Codex build everything up to them.

| Item | Needed for |
| --- | --- |
| Apple Developer Program membership, team ID and bundle ID prefix | Real-device testing, push, Live Activities, App Groups, TestFlight, the App Store |
| Cloudflare account | Deploying the relay, the Workers-to-APNs HTTP/2 check |
| An APNs authentication key (`.p8`) with its key ID, and a domain for the relay | Deploying the relay and sending real pushes (`server/relay/README.md`, "Deploying") |
| A physical iPhone (ideally an iPhone 13 for the performance budgets) and iPad | The real-device exit criteria below |
| Push content: sealed summaries or IDs only (default: sealed summaries) | M5 |
| Lock-screen approvals: on with risk tiers, opt-in, or off (default: on with risk tiers) | M5 |
| Who pays for the relay (licensing is decided: the app is GPL-3.0-only, the plugin and relay MIT) | Deploying the relay |
| The plugin's npm name and scope (placeholder until decided) | Publishing the plugin |
| The app's name and branding. "Opencode" risks rejection under App Review guideline 5.2.1. | Store listing, bundle ID, plugin name |
| Which of M6, M7 and M8 ship in 1.0 (default: M6 in 1.0, M7 and M8 as updates) | Launch scope |
| Telemetry (default: none, opt-in crash reports), transcript cache default, "Designed for iPad" on Mac, Android later | M9 |

Until the owner decides, builds use the SPEC §9 defaults and keep names in one place so they are easy to change. Account creation, deploys, npm publishing and App Store submission wait for the owner.

## Milestones

| Milestone | Status |
| --- | --- |
| M0 Foundations, M1 Connection, D1 Design, M2 Read path | Landed |
| M3a Write core and approvals | Landed |
| M3b Composer, pickers, session actions | Landed |
| M4 Review and files | Landed |
| M5a Push, server side: contracts, plugin, relay, Swift envelope core | Landed |
| M5b Push, app side: registration, NSE, actions, presence, delivery health, badge, Live Activity | Next |
| M6 iPad and system integration | After M5 |
| M7 Terminal | After M6 |
| M8 Parity | After M7 |
| M9 Launch readiness (the parts that run locally) | After M8 |

## Not yet verified

| Check | From |
| --- | --- |
| Workers outbound `fetch` reaches APNs over HTTP/2 (else the Fly.io fallback) | M0 spike, M5a; needs a Cloudflare account and an APNs key |
| The relay deployed with D1, its secrets and `wrangler deploy`, and its URL set in `server/contracts/constants.json` | M5a; needs a Cloudflare account and an APNs key |
| The real APNs sandbox accepts the relay's provider token and its alert and Live Activity requests (tested only against the mock APNs) | M5a; needs an APNs key and a device token |
| `opencode plugin add` from npm (tested with a Git specifier in the sandbox) | M5a; needs the npm name and publishing |
| Live updates through OpenTunnel and `tailscale serve` | M0 spike |
| Mention editing with Japanese, Chinese and Korean input on a device | M0 spike |
| Pairing over LAN and tunnel in under 10 s; Wi-Fi/cellular switches; lock and unlock; an 8-hour soak with no dead stream | M1, on a device |
| iPhone 13 Instruments trace; cached inbox within 300 ms of a cold start; offline browsing | M2, on a device |
| No prompt or draft lost across kill, relaunch and backgrounding; approve in under 1 s over real Wi-Fi | M3, on a device |
| A 5,000-line diff scrolls smoothly | M4, on a device |
| ⌘F with a hardware keyboard on a physical iPad | M4, carried to M6 |
| End-to-end push through the APNs sandbox; "Allow once" from the lock screen within 5 s | M5, on a device |
| At least 99.5% crash-free sessions in an external TestFlight beta | M9 |

## Launch readiness (M9)

- App Review demo: a hosted demo server and an in-app demo mode (guideline 2.1).
- A privacy manifest for the app (`PrivacyInfo.xcprivacy`; the app uses `UserDefaults`), the App Privacy answers, a privacy policy URL, and the export-compliance answer (TLS and HPKE).
- App Attest on relay device registration; relay operations: APNs key custody, rate limits, monitoring, alerts and a cost cap.
- Spec watch: the nightly contract run already tests the latest 2.x. Add the npm poll, `oasdiff`, the event-union diff and the automatic issue. State the minimum server version (2.0.10, or 2.0.25 for pairing) in the app and the listing.
- Accessibility (VoiceOver, Dynamic Type, Reduce Motion), String Catalogs, a performance pass, a security review and complete licence notices.
- A release pipeline that archives, signs and uploads builds to App Store Connect, with version and build numbering.
- The store listing: name, subtitle, keywords, screenshots for 6.9-inch iPhone and 13-inch iPad, support URL, age rating, category, price, and the "Pair your phone" onboarding page.
- External TestFlight, then App Review, then a phased release.

## After launch

The M6 to M8 work not in 1.0, then ARCHITECTURE §7's "Later" list: SSH tunnel, push-to-start and multi-session Live Activities, the Notification Content extension, ID-only push, Apple Watch, persistent terminals, durable-log replay, a share extension.
