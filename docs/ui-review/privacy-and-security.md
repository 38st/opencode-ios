# UI review: Privacy and security

Part of the [UI review](README.md). 1 bug and 3 improvements, bugs first, then by severity. Paths under `Packages/OpencodeKit/Sources` are written without that prefix.

| ID | Severity | Finding |
| --- | --- | --- |
| [F39-08](#f39-08) | P3 bug | 'Unencrypted' is marked with a closed padlock, and Tailscale HTTP endpoints are called unencrypted |
| [F39-02](#f39-02) | P2 improvement | No app lock and no app-switcher privacy cover: code, diffs and pending approvals stay visible when the app is backgrounded |
| [F39-11](#f39-11) | P3 improvement | Server-supplied approval text is shown without a source label or handling of control characters |
| [F39-12](#f39-12) | P3 improvement | Markdown links open immediately without revealing their destination |

<a id="f39-08"></a>

## F39-08: 'Unencrypted' is marked with a closed padlock, and Tailscale HTTP endpoints are called unencrypted

*P3 bug · visual · effort S · found by privacy-security-ui*

- Where: `FeatureServers/ServerRow.swift:27`, `FeatureServers/ServerDetailView.swift:54`, `FeatureServers/AddServerView.swift:71`, `OCNetworking/EndpointPolicy.swift:22`
- Evidence: `crops/privacy-security-ui/list-unencrypted.png and detail-unencrypted.png: a closed padlock next to 'Unencrypted'`; `ServerRow.swift:27: OCLabel("Unencrypted", icon: "lock"). ServerRow.swift:32 and ServerDetailView.swift:45 use the same lock for 'Pairing expires soon'`; `EndpointPolicy.swift:22-23 allows plain HTTP for 100.64/10 tailnet IPs, which WireGuard encrypts, and ServerRow.isUnencrypted (39-42) flags any http scheme`
- What happens: Settings shows 'Connected · LAN' and then a closed padlock with 'Unencrypted'. A server reached at http://100.101.102.103:4096 over Tailscale shows the same badge, and while adding it the text 'anyone on this network may be able to read your credential'.
- Why it matters: A closed padlock is the universal 'secure' sign, so a glance reads the opposite. False alarms for Tailscale teach users to ignore the badge.
- Fix: Use a warning glyph for Unencrypted (warning or circle-exclamation exist in Icons.xcassets, or add an open lock) and keep 'lock' for HTTPS. Give token expiry its own icon. For tailnet endpoints, show 'Tailscale (encrypted)' and skip the warning.
- Also reported as: F38-09 by sweep-approval-server-snapshots

<a id="f39-02"></a>

## F39-02: No app lock and no app-switcher privacy cover: code, diffs and pending approvals stay visible when the app is backgrounded

*P2 improvement · privacy · effort M · found by privacy-security-ui*

- Where: `App/OpencodeApp.swift:10`, `FeatureServers/ServerRootView.swift:126`, `FeatureServers/ServerSettingsView.swift:26`
- Evidence: `ServerRootView.swift:126-129: scenePhase only drives registry.setScenePhase (connections and draft flush). There is no cover or lock, and grep finds no privacySensitive, blur or lock UI in Sources or App`; `SPEC.md:85 and SPEC.md:102 list 'app lock' for v1.0 and Settings. ARCHITECTURE.md:740-742 specifies an optional lock on launch and after N minutes in the background. research/08-feature-matrix.md:280 rates it P1. No milestone in ARCHITECTURE §7 or docs/roadmap.md schedules it`; `iphone/permission-sheet.png: the full command and /Users/<name>/… working directory would be captured as-is` (+1 more)
- What happens: Open the permission sheet, the diff viewer or a file in Review, then swipe up to the app switcher or press the side button. The switcher card, and the snapshot iOS stores, show the source code or the pending command. Anyone holding the unlocked phone can open the app and tap 'Allow once' on any elevated request (shell, edit, webfetch) with no authentication, or send a prompt to an agent that controls the computer. Settings has no lock option.
- Why it matters: Code, secrets printed by tools and approval details leak through the app switcher and over the shoulder. The app's highest-impact actions are protected only by the device lock.
- Fix: Add a privacy cover in a separate UIWindow above sheets (an .overlay on the SwiftUI root does not cover presented sheets). Show it when the scene leaves .active, at least on .background before the snapshot, and remove it on return. Then add the planned optional app lock (Settings → App lock: immediately, after 1, 5 or 15 minutes) using LAContext(.deviceOwnerAuthentication), and extend NSFaceIDUsageDescription to cover unlocking the app.

<a id="f39-11"></a>

## F39-11: Server-supplied approval text is shown without a source label or handling of control characters

*P3 improvement · privacy · effort S · plausible, needs a running app to confirm · found by privacy-security-ui*

- Where: `FeatureApprovals/PermissionSheet.swift:37`, `FeatureApprovals/PermissionSheet.swift:79`, `FeatureApprovals/ApprovalDock.swift:45`
- Evidence: `PermissionSheet.swift:37: if let message = request.message { Text(message).font(OCType.body) }. The message is unlabeled and styled like app copy between Action and Resources`; `No code in Sources neutralizes bidi controls (U+202A–U+202E, U+2066–U+2069) or zero-width characters; grep for bidi, 202E and 200B finds nothing`; `Good: Text(String) is verbatim, so Markdown and links in titles, messages and resources are never rendered`
- What happens: A plugin or MCP tool asks for permission with the message 'Read-only check — safe to allow.', and the sheet renders it as if the app said so. A prompt-injected command containing a right-to-left override or zero-width characters renders reordered or partly hidden in the dock card, which has no risk badge to contradict it, and in the sheet.
- Why it matters: The approval screen is the security boundary, so text the agent controls should be visibly attributed and rendered unambiguously.
- Fix: Label the message ('Message from the tool') in a muted style after the resources. Render bidi controls and invisible characters in the action and resources as visible escapes such as ⟨U+202E⟩, and show a warning badge when any are present.

<a id="f39-12"></a>

## F39-12: Markdown links open immediately without revealing their destination

*P3 improvement · interaction · effort S · found by privacy-security-ui*

- Where: `OCDesign/MarkdownBlockView.swift:28`, `Packages/OpencodeKit/.build/checkouts/textual/Sources/Textual/Internal/TextInteraction/UIKit/UITextInteractionView.swift:110`
- Evidence: `MarkdownBlockView.swift:29: if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") { return .systemAction }`; `Textual's handleTap opens the URL on a single tap, and a long press starts text selection, so there is no link preview`; `By contrast, ToolRowView.swift:64 and FormRenderer.swift:84 show the full URL or host before opening`
- What happens: After reading a prompt-injected web page, the agent writes '[Open the PR](https://evil.example/login)'. The transcript shows 'Open the PR' in the accent colour. A tap goes straight to Safari, or to an app that claims the universal link, with no way to see the URL first.
- Why it matters: Link text can disguise phishing destinations. ARCHITECTURE.md:783 only guarantees that opening needs a tap.
- Fix: Open http(s) links in SFSafariViewController, which shows the domain. When the link text is not the URL itself, show a confirmation with the full URL. Add a context menu with Copy link and Open.
