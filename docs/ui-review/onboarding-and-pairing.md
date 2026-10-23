# UI review: Onboarding and pairing

Part of the [UI review](README.md). 9 bugs and 6 improvements, bugs first, then by severity. Paths under `Packages/OpencodeKit/Sources` are written without that prefix.

| ID | Severity | Finding |
| --- | --- | --- |
| [F01-01](#f01-01) | P2 bug | Password setup saves the server before checking it, so a wrong password, a mistyped address or Cancel each leave a broken saved server |
| [F01-03](#f01-03) | P2 bug | Re-pair sheet ignores how the server signs in, never names the server, and closes as if it succeeded when the new password is rejected |
| [F01-05](#f01-05) | P2 bug | Returning users see the first-run 'Your servers, anywhere' screen on every cold launch while saved servers load, and keep seeing it if loading fails |
| [F01-08](#f01-08) | P2 bug | VoiceOver hears nothing about pairing progress or errors, the focused Connect button disappears mid-action, and each field is read twice |
| [F01-02](#f01-02) | P3 bug | A failed pairing is explained wrongly: a reachable server is reported as 'Authentication failed. Pair with the server again.' under the heading 'None of the server addresses could be reached.' |
| [F01-04](#f01-04) | P3 bug | Re-pairing with a link replaces every saved endpoint, silently dropping manually added addresses, and accepts a link for a different computer |
| [F01-11](#f01-11) | P3 bug | Tapping the `opencode pair` chip replaces the command with 'Copied' until the sheet closes |
| [F01-12](#f01-12) | P3 bug | An address typed without a scheme silently becomes http://, so a bare LAN IP gets no 'Unencrypted' warning and a bare domain is rejected with an HTTPS error |
| [F29-14](#f29-14) | P3 bug | Onboarding copy: “Opencode” vs “opencode”, a pair-command chip that turns into “Copied”, and QR instructions with no scanner |
| [F01-07](#f01-07) | P2 improvement | Password mode never says which password to enter; the reference form's 'run opencode service get password' hint is missing |
| [F38-08](#f38-08) | P2 improvement | Re-pair sheet never names the server it is re-pairing, yet opens on its own when Settings opens |
| [F01-06](#f01-06) | P3 improvement | 'Add your first server' opens Settings with the add form stacked on top; Cancel lands on app preferences, and success leaves the user in Settings |
| [F01-10](#f01-10) | P3 improvement | Paired servers are named after an IP or tunnel host, with no chance to rename during setup, and re-adding a saved computer creates a duplicate whose sessions appear twice |
| [F01-13](#f01-13) | P3 improvement | Input in the wrong mode is not recognised, the copy promises QR scanning where no scanner exists, and any non-opencode QR code closes the scanner |
| [F01-14](#f01-14) | P3 improvement | The connection form has no keyboard flow: Return never advances or connects, and Return in the pairing field inserts a line break |

<a id="f01-01"></a>

## F01-01: Password setup saves the server before checking it, so a wrong password, a mistyped address or Cancel each leave a broken saved server

*P2 bug · ux-flow · effort M · found by servers-onboarding*

- Where: `OCSync/ServerSetup.swift:20`, `FeatureServers/AddServerView.swift:163`, `FeatureServers/AddServerView.swift:174`, `FeatureServers/AddServerView.swift:82`, `FeatureServers/AddServerView.swift:111` (+2 more)
- Evidence: `iphone/re-pair.png: captured right after addManual(url, password: 'deliberately-wrong') (UITests/ServerSmokeTests.swift:46-47). The user who typed a password is shown 'Re-pair server / Needs re-pairing / Pairing link'.`; `AddServerView.swift:174 'case .connected, .unauthorized, .incompatible, .waiting, .serviceStarting: finished = true; working = false; completed(server)'`; `ServerSetup.swift:20-23: addManually() calls add(), which writes the Keychain item and the record, with no probe first. PairingService.manual(url:password:) at PairingService.swift:139 does probe /api/info, but nothing calls it.` (+2 more)
- What happens: iPhone, first run, tap 'Use password'. (a) Mistype the password and tap Connect. The spinner shows 'Connecting to server…', then the sheet closes. The record is already saved, and a new 'Re-pair server' sheet opens in pairing-link mode with a 'Needs re-pairing' banner. Nothing says the password was wrong, and tapping Cancel leaves a 'Needs re-pairing' server behind. (b) Mistype the IP as 192.168.1.20. The first retry state (.waiting) counts as finished, so the sheet closes and Settings shows 'Retrying in Ns · Attempt 1 · …'. Fixing the typo means deleting the server, or adding and removing endpoints in its detail screen. (c) Tap Cancel during 'Connecting to server…': the sheet dismisses, but add() has already saved the record. Whitespace pasted with the password is not trimmed either.
- Why it matters: The form gives no inline feedback for the two most common setup mistakes. Each mistake leaves a record the user has to find and delete, and first-time users are sent to a pairing screen they never asked for.
- Fix: Probe before saving: reuse PairingService.manual or ServerProbe with the entered credential, and keep the form open with field-level errors for each outcome. For .unauthorized: 'The server rejected this password (run opencode service get password)'. For .failure: its message, plus a 'Save anyway' option for a server that is offline. For .v1, .unsupportedV2 and .notOpencode: an inline message with a link to the update screen. Call registry.add only after success, so Cancel never leaves a record. Require a non-empty password and trim surrounding whitespace.
- Verifier's note: PairingService.manual cannot be reused as is: it collapses v1, unsupportedV2, notOpencode, v2Starting and transport failures into PairingError.unreachable. Return the ProbeOutcome, or a typed error, so the form can show the specific inline messages.
- Also reported as: F39-07 by privacy-security-ui

<a id="f01-03"></a>

## F01-03: Re-pair sheet ignores how the server signs in, never names the server, and closes as if it succeeded when the new password is rejected

*P2 bug · state · effort S · found by servers-onboarding*

- Where: `FeatureServers/ServerSettingsView.swift:66`, `FeatureServers/ServerSettingsView.swift:73`, `FeatureServers/AddServerView.swift:40`, `FeatureServers/AddServerView.swift:167`, `FeatureServers/AddServerView.swift:174` (+3 more)
- Evidence: `iphone/re-pair.png: a server created with a password ('Needs pairing') reopens in pairing-link mode, and neither its name nor its address appears anywhere in the sheet.`; `ServerSettingsView.swift:66 'AddServerView(registry: registry, repairing: server) { _ in repairing = nil }' passes no initialMethod, so the sheet uses method 0 (pairing link) even for password credentials or servers without pairing (capabilities.pairing false, below 2.0.25).`; `AddServerView.swift:174 treats .unauthorized as settled, which calls completed() and closes the sheet; ServerSettingsView.swift:73 '!shownRepair.contains($0.id)' stops it from reopening.` (+1 more)
- What happens: A server was added with a password, and the password was later changed on the computer, so the app gets a 401. Settings opens 'Re-pair server' on its own and asks for a pairing link and 'opencode pair'. The user taps 'Use password', mistypes it and taps 'Pair again'. The reconnection gets a 401 and the sheet dismisses as if it had worked; it is not shown again, and the only sign of failure is the 'Needs re-pairing' pill in Settings. When two servers need repair, the sheet does not say which one it is for.
- Why it matters: Restoring a credential is needed every 30 days for pairing tokens and after any password change. For password users it is confusing, and a failure is reported as a success.
- Fix: Choose the initial method from the stored credential (tokenExpiresAt == nil means a password) and from server.capabilities.pairing. Show the server name and primary address under the title. In re-pair mode, treat .unauthorized as a failure: keep the sheet open with 'The server rejected this password or link'. Use wording that fits both credential types, such as 'Sign in again' and 'Sign-in rejected: the password changed or the pairing expired'.
- Verifier's note: Judge the outcome only from states emitted after the post-repair .resolving, not the stale .unauthorized. From F02-09: keep the dismissed-repair set in ServerRegistry for the app session instead of per-presentation @State (ServerSettingsView.swift:17, :69), so Cancel is not undone on the next Settings visit. Show the cause (expired token or rejected password), and offer Remove server in the sheet.
- Also reported as: F02-09 by servers-management

<a id="f01-05"></a>

## F01-05: Returning users see the first-run 'Your servers, anywhere' screen on every cold launch while saved servers load, and keep seeing it if loading fails

*P2 bug · state · effort S · found by servers-onboarding*

- Where: `FeatureServers/ServerRootView.swift:37`, `FeatureServers/ServerRootView.swift:42`, `FeatureServers/ServerRootView.swift:121`, `OCSync/ServerRegistry.swift:101`, `OCSync/ReadStore.swift:147` (+1 more)
- Evidence: `ServerRootView.swift:37 'if registry.servers.isEmpty {' shows onboarding, and :42 '.disabled(!registry.isLoaded)' disables its button. load() only starts in the .task at :121-122.`; `ServerRegistry.swift:99-101 builds every store before 'servers = stores': two Keychain reads per server plus ReadStore.loadCache (projects, sessions, outbox and catalogs, ReadStore.swift:147-164).`; `When loading fails (ServerRegistry.swift:115), servers stays empty, so the first-run screen stays up with a disabled button and an error toast.` (+1 more)
- What happens: iPhone with two saved servers and a large cache, cold launch. The app shows 'Opening servers…', then 'Your servers, anywhere / Add your first server' with the button greyed out for the whole load, then Home. If the Keychain or cache read fails, an existing user is left on the empty first-run screen with a disabled button and a toast.
- Why it matters: Every launch flashes the wrong screen, which works against the spec's cache-first launch. When loading fails, it suggests the user's servers are gone.
- Fix: Show onboarding only when registry.isLoaded && servers.isEmpty. While loading, keep the 'Opening servers…' state or a Home skeleton; when loading fails, show an error state with Try again. Consider publishing the server records before their caches finish loading.
- Also reported as: F28-07 by states-coverage

<a id="f01-08"></a>

## F01-08: VoiceOver hears nothing about pairing progress or errors, the focused Connect button disappears mid-action, and each field is read twice

*P2 bug · accessibility · effort S · found by servers-onboarding*

- Where: `FeatureServers/AddServerView.swift:76`, `FeatureServers/AddServerView.swift:77`, `FeatureServers/AddServerView.swift:53`, `FeatureServers/AddServerView.swift:64`, `OCDesign/Feedback.swift:19`
- Evidence: `AddServerView.swift:77-83 'if working { OCSpinner(…) } else { Button … Connect }': the button VoiceOver has just activated is removed from the view.`; `AddServerView.swift:76 'if let error { OCBanner(error, tone: .danger) }' is not announced. There is no AccessibilityNotification or @AccessibilityFocusState anywhere in Packages/OpencodeKit/Sources.`; `Feedback.swift:19-30: OCBanner is plain text, and its danger tone is shown by colour only.` (+1 more)
- What happens: VoiceOver on: paste an expired link and double-tap Connect. Focus jumps when the button is replaced by 'Pairing with server…'. The red banner then appears above the restored button without being read out, so the user never hears 'This pairing link expired or was already used.' Swiping through the form reads 'Server URL' and then 'Server URL, text field'.
- Why it matters: Blind users cannot tell whether pairing worked or why it failed.
- Fix: Keep the Connect button in place, disabled, with an inline ProgressView, so focus stays put. Post AccessibilityNotification.Announcement for 'Pairing…', for success and for the error text, or move focus to the banner with @AccessibilityFocusState. Prefix the banner's label with 'Error:'. Hide the visible label Texts from accessibility, or combine each label and field into one element.

<a id="f01-02"></a>

## F01-02: A failed pairing is explained wrongly: a reachable server is reported as 'Authentication failed. Pair with the server again.' under the heading 'None of the server addresses could be reached.'

*P3 bug · functional · effort M · found by servers-onboarding*

- Where: `OCSync/ServerSetup.swift:31`, `OCSync/ServerSetup.swift:58`, `OCSync/ServerSetup.swift:64`, `OCNetworking/EndpointResolver.swift:67`, `OCNetworking/EndpointResolver.swift:34` (+2 more)
- Evidence: `ServerSetup.swift:31 'await EndpointResolver().resolve(endpoints: endpoints, credential: nil)'. research/01-opencode-server-api.md:80 says '/api/info and /openapi.json require auth', so every reachable V2 server answers 401. EndpointResolver.swift:67 turns that into .failure(.unauthorized), which Connection.swift:14 words as 'Authentication failed. Pair with the server again.'`; `ServerSetup.swift:58: the heading is always 'None of the server addresses could be reached.' At :64 the default branch, which is what a 503 'starting' server reaches, says 'Pairing is unavailable. Create a new link on the server.'`; `localNetworkDenied is never passed (EndpointResolver.swift:34 defaults to false; EndpointPolicy.swift:78), so a denied Local Network permission reads 'The server could not be reached. Check the address and network.' The add form has no Settings link; ServerDetailView does.` (+1 more)
- What happens: iPhone, pairing link for a server that is running. The /auth/connect request times out after 5 s (slow tunnel or Wi-Fi, busy server) or returns a 5xx, so redeem throws .unreachable and the app re-probes without a credential. The banner then reads 'None of the server addresses could be reached. 192.168.1.2: Authentication failed. Pair with the server again.', although the server was reached and the user is in the middle of pairing. If the user denied Local Network access, every attempt says 'could not be reached. Check the address and network.', with no way to Settings. A server answering 503 while starting shows 'Pairing is unavailable. Create a new link on the server.' Not verified on a device: on a fresh install, the first LAN redeem probably fires while iOS is showing its Local Network alert. URLSessionTransport does not set waitsForConnectivity, so that first attempt could fail and land in this path.
- Why it matters: On the main pairing flow, the error text points users at the wrong fix (a new link, re-pairing, or checking the address). A denied Local Network permission, a common first-run cause, is never named.
- Fix: Treat an unauthenticated 401 from /api/info as 'reachable' and say 'The server answered but did not accept the link. Try again or run opencode pair again.' Detect local-network denial (NWPath.unsatisfiedReason) and show 'Allow Local Network access' with an Open Settings button. Map .starting to 'The server is starting. Try again in a moment.' Choose the heading based on whether any address answered. When none answered, add 'Is this phone on the same Wi-Fi? Away from home, run opencode pair --remote.' After the Local Network explanation, wait for the user's permission decision, or retry the redeem once automatically.
- Verifier's note: Choose the heading by whether any address answered, and treat a credential-less 401 as 'reachable, link not accepted'. The connection path probably never detects Local Network denial either; see the missed finding about NetworkPathMonitor.

<a id="f01-04"></a>

## F01-04: Re-pairing with a link replaces every saved endpoint, silently dropping manually added addresses, and accepts a link for a different computer

*P3 bug · functional · effort S · found by servers-onboarding*

- Where: `OCSync/ServerSetup.swift:37`, `OCSync/ServerStore.swift:129`, `OCNetworking/PairingService.swift:130`, `FeatureServers/AddServerView.swift:159`
- Evidence: `ServerSetup.swift:37 'try await server.repair(credential: credential, endpoints: result.server.endpoints)' leads to ServerStore.swift:129 'record.endpoints = endpoints'. The new endpoints are fresh records built from link.urls (PairingService.swift:130), with new IDs and reset stats and headerNames.`; `The password re-pair path keeps the existing endpoints: AddServerView.swift:159-160 'repairing.record.endpoints.contains(...) ? repairing.record.endpoints : repairing.record.endpoints + [endpoint]'.`; `Nothing checks that the link's URLs share a host with the server being repaired.`
- What happens: Studio Mac has its paired LAN URL and a manually added https://studio.tail1234.ts.net (tailscale serve) endpoint. The token expires after 30 days, and the user re-pairs at home from a QR code that only has the LAN address. The record now holds only the LAN URL. Only the addresses the server lists in /api/info.urls come back as discovered endpoints, so the Tailscale or reverse-proxy endpoint is gone, and the server is unreachable the next time the user is away. Pasting the other Mac's link into this sheet repoints 'Studio Mac' at a different computer, keeping its name and cached sessions.
- Why it matters: A recurring flow silently deletes the user's configuration. The failure only shows up later, away from home, with no hint of the cause.
- Fix: Merge instead of replace: keep the existing endpoints and add the link's URLs, deduplicated by URL. If none of the link's hosts and ports match a saved endpoint, ask 'This link is for a different server. Add it as a new server?'

<a id="f01-11"></a>

## F01-11: Tapping the `opencode pair` chip replaces the command with 'Copied' until the sheet closes

*P3 bug · interaction · effort S · found by servers-onboarding*

- Where: `FeatureServers/AddServerView.swift:96`, `FeatureServers/AddServerView.swift:98`
- Evidence: `AddServerView.swift:96-97 'Button { UIPasteboard.general.string = 'opencode pair'; copiedPairCommand = true } label: { Text(copiedPairCommand ? 'Copied' : 'opencode pair') }': copiedPairCommand is never reset.`; `The accessibilityLabel stays 'Copy opencode pair' (line 98), so VoiceOver gets no confirmation.`; `UpdateServerView already handles this better: ServerDetailView.swift:144 keeps the command visible and adds 'Copied <command>' below it.` (+1 more)
- What happens: On first run the user taps the chip. It now reads 'Copied' in monospace, and the instruction above it ('Run this command on the server's computer…') no longer shows which command to run. Switching to password mode and back still shows 'Copied'.
- Why it matters: After one tap, the main first-run instruction disappears from the screen.
- Fix: Keep the command text visible. Show a checkmark or 'Copied' label next to it, or a toast that resets after about 2 s, and announce it.

<a id="f01-12"></a>

## F01-12: An address typed without a scheme silently becomes http://, so a bare LAN IP gets no 'Unencrypted' warning and a bare domain is rejected with an HTTPS error

*P3 bug · functional · effort S · found by servers-onboarding*

- Where: `FeatureServers/AddServerView.swift:70`, `OCNetworking/PairingService.swift:30`, `OCNetworking/EndpointPolicy.swift:23`, `OCNetworking/EndpointPolicy.swift:25`
- Evidence: `AddServerView.swift:70 'if address.lowercased().hasPrefix('http://')' shows the warning only when the user types that literal prefix, while PairingParser.serverAddress (PairingService.swift:30) prepends http:// to anything typed without a scheme.`; `EndpointPolicy.swift:23 then refuses non-local http with 'Plain HTTP is only supported for local networking. Use an HTTPS URL for this host.' (Connection.swift:10).`; `PairingService.swift:29 only accepts a lowercase 'http://' or 'https://', so a pasted 'HTTP://…' is rejected as invalid.` (+1 more)
- What happens: (a) Typing '192.168.1.2:4096', the natural form, saves the server as plain HTTP, and the Unencrypted note never appears in the form. (b) Typing 'studio.example.com' for an HTTPS reverse proxy is rejected with 'Use an HTTPS URL', although the user typed no scheme. (c) Pasting 'http://127.0.0.1:4096' from the `opencode serve` output is accepted, and the saved server keeps retrying, because on a phone that address is the phone itself.
- Why it matters: The security warning misses the most common input, and valid addresses are rejected or accepted for the wrong reasons.
- Fix: Base the warning on the scheme of the normalized URL. Default to https for non-local hosts, and to http only for LAN and tailnet addresses. Lowercase the scheme before checking it. Warn on loopback: '127.0.0.1 and localhost mean this iPhone. Use your computer's network address (opencode pair shows it).'
- Verifier's note: Warn on loopback rather than blocking it: the simulator and UI tests rely on 127.0.0.1 reaching the Mac.
- Also reported as: F39-04 by privacy-security-ui

<a id="f29-14"></a>

## F29-14: Onboarding copy: “Opencode” vs “opencode”, a pair-command chip that turns into “Copied”, and QR instructions with no scanner

*P3 bug · copy · effort S · found by ux-writing*

- Where: `FeatureServers/AddServerView.swift:41`, `FeatureServers/AddServerView.swift:84`, `FeatureServers/AddServerView.swift:96-97`, `FeatureServers/ServerRootView.swift:43`, `FeatureServers/ServerRootView.swift:194` (+7 more)
- Evidence: `iphone/onboarding.png: the title “Opencode” sits above “Connect to opencode on your computer…”`; `iphone/local-network.png: “Opencode connects directly to the server…”`; `iphone/add-server.png: “…or scan its QR code.” with no Scan QR code button on screen` (+2 more)
- What happens: First launch on iPhone. The screen title says “Opencode” while the body says “opencode”, and the Local Network sheet and all three permission prompts say “Opencode uses…”. In Add server, tapping the “opencode pair” chip replaces the command with “Copied” for as long as the sheet stays open. The command the user still has to type on their computer is gone. Where DataScannerViewController is unsupported (the Mac “Designed for iPad” build, simulators), the subtitle still says “or scan its QR code”, but no Scan button is shown.
- Why it matters: Two capitalisations of one word make the app and the server read as the same product, while SPEC §5 asks for a distinct name. The name is scattered across about eight places and must be changed in each when the owner picks one. The chip hides the very instruction it illustrates.
- Fix: Keep the command visible and confirm the copy briefly (a checkmark or “Copied” for about 2 s, or a separate Copy button). Show the scanning clause only when DataScannerViewController.isSupported. Move the app name to one constant and build setting ($(PRODUCT_NAME) or InfoPlist.strings), and use “this app” in body copy until the owner decides on a name.

<a id="f01-07"></a>

## F01-07: Password mode never says which password to enter; the reference form's 'run opencode service get password' hint is missing

*P2 improvement · design-parity · effort S · found by servers-onboarding*

- Where: `FeatureServers/AddServerView.swift:68`, `FeatureServers/AddServerView.swift:41`, `FeatureServers/AddServerView.swift:60`
- Evidence: `.build/design-compare/add-server-password-light-393x852.png: under the Password field the reference says 'To see it, run opencode service get password on the server's computer.' The native form shows nothing there.`; `iphone/add-server-password.png`; `research/01-opencode-server-api.md:49 and :101: the server password is generated, and 'opencode service get password' prints it.` (+1 more)
- What happens: A user whose server cannot pair (older than 2.0.25), or who prefers a password, taps 'Use password'. They see 'Name (optional)', 'Server URL', 'Password' and 'Enter your server address and password to get started.' Many will try their Mac login password, get a 401, and fall into the re-pair loop described in the first finding. The generated password has to be typed blind, because there is no show or hide control.
- Why it matters: Without outside documentation, the password route is close to unusable.
- Fix: Add the reference hint under the field, with a copyable `opencode service get password` chip styled like the `opencode pair` one. Add a show or hide toggle to the SecureField, trim whitespace on paste, and put Server URL before the optional Name field (the reference has no Name field).

<a id="f38-08"></a>

## F38-08: Re-pair sheet never names the server it is re-pairing, yet opens on its own when Settings opens

*P2 improvement · ux-flow · effort S · not verified · found by sweep-approval-server-snapshots*

- Where: `FeatureServers/AddServerView.swift:40`, `FeatureServers/AddServerView.swift:45`, `FeatureServers/ServerSettingsView.swift:68`
- Evidence: `Packages/OpencodeKit/Tests/FeatureServersTests/__Snapshots__/DesignScreenTests/screens.re-pair-light-393x852.png: title 'Re-pair server', banner 'Needs re-pairing', empty link field; no server name or address anywhere`; `Packages/OpencodeKit/Tests/FeatureServersTests/__Snapshots__/DesignScreenTests/screens.re-pair-light-820x1180.png: same`; `iphone/re-pair.png: same in the real app` (+1 more)
- What happens: The user has two paired computers and one revokes the token. Opening Settings slides up 'Re-pair server' with an empty pairing-link field.
- Why it matters: The user doesn't know which computer to run `opencode pair` on and may paste a link for the wrong server. The banner also doesn't say why re-pairing is needed.
- Fix: Name the server in the title or subtitle, e.g. 'Re-pair Studio Mac' with the endpoint host. Give the banner a reason, e.g. 'The server no longer accepts the saved credential'.

<a id="f01-06"></a>

## F01-06: 'Add your first server' opens Settings with the add form stacked on top; Cancel lands on app preferences, and success leaves the user in Settings

*P3 improvement · ux-flow · effort M · found by servers-onboarding*

- Where: `FeatureServers/ServerRootView.swift:40`, `FeatureServers/ServerRootView.swift:96`, `FeatureServers/ServerSettingsView.swift:69`, `FeatureServers/ServerSettingsView.swift:61`, `FeatureServers/AddServerView.swift:112` (+1 more)
- Evidence: `iphone/add-server.png: the Settings sheet is visible behind the Add server sheet (crop: crops/servers-onboarding/add-server-top.png).`; `iphone/local-network.png: a third stacked sheet, with no drag indicator and no Cancel; AddServerView.swift:112-117 does not apply .ocSheet().`; `iphone/server-list.png shows where the user lands, with the app preferences (Steer, Wrap lines, Changed files, Show agent) above the server card. UITests/ServerSmokeTests.swift:19 has to tap Done to get past it.` (+1 more)
- What happens: Fresh install: tapping 'Add your first server' opens the Settings sheet, which immediately presents Add server (ServerSettingsView .task with addOnOpen). For a LAN address, a third sheet explains Local Network access. Tapping Cancel does not return to onboarding; it reveals the Settings screen ('Servers / App / Follow-up behavior / Wrap lines…'). After a successful connection, the add sheet closes onto Settings, and the user has to find Done to reach their sessions.
- Why it matters: The first-run path is longer than it needs to be and ends somewhere unexpected, and the stacked sheets make it unclear where Cancel goes.
- Fix: Present AddServerView directly from onboarding, or make the connection form the onboarding screen as the reference does, and dismiss to Home on success. Keep OCWorkspaceShell's deferral of the Home sheet, tied to the add sheet instead. Give the Local Network explanation .ocSheet() and a 'Not now' button. This revisits docs/design.md ('every connection flow lives in Settings') and the m3a-audit rule that Settings stays presented after setup.

<a id="f01-10"></a>

## F01-10: Paired servers are named after an IP or tunnel host, with no chance to rename during setup, and re-adding a saved computer creates a duplicate whose sessions appear twice

*P3 improvement · ux-flow · effort M · found by servers-onboarding*

- Where: `OCNetworking/PairingService.swift:131`, `FeatureServers/AddServerView.swift:60`, `OCSync/ServerRegistry.swift:146`, `FeatureInbox/HomeView.swift:34`
- Evidence: `ipad/ipad-portrait.png: after pairing by link, the server switcher and every session row read '127.0.0.1' (crop: crops/servers-onboarding/ipad-home-header.png).`; `PairingService.swift:131 'ServerRecord(name: link.urls[preferred].host ?? 'opencode', …)'. The Name field only exists in password mode (AddServerView.swift:60-63).`; `ServerRegistry.swift:146 only compares the newly generated UUID (ServerRecord.swift:72), so ServerSetupError.duplicateServer can never fire. UITests/ServerSmokeTests.swift:17, 40 and 46 add the same URL three times without any warning.` (+1 more)
- What happens: Pairing by QR names the server '192.168.1.23', or a roughly 45-character '…opentunnel.xyz' host when the tunnel answers first. That name appears in the Home server switcher and in every session row. A user whose token expired may tap Add server and pair again instead of finding re-pair. They then get a second server for the same Mac, and Home lists every session twice.
- Why it matters: Server names are unreadable on the primary (pairing) path, and duplicate records double the Home list.
- Fix: Show the optional Name field in pairing mode too, or offer a quick rename after pairing, with a friendlier default (prefer the LAN host to a tunnel host). Before saving, look for a saved server that shares an endpoint URL or host and port, and offer 'Re-pair Studio Mac instead'.
- Verifier's note: Keep this finding to naming: a Name field in pairing mode, or a rename step after pairing, defaulting to the LAN host rather than a tunnel host. Track duplicate detection in F02-02.

<a id="f01-13"></a>

## F01-13: Input in the wrong mode is not recognised, the copy promises QR scanning where no scanner exists, and any non-opencode QR code closes the scanner

*P3 improvement · ux-flow · effort M · found by servers-onboarding*

- Where: `OCNetworking/PairingService.swift:37`, `OCNetworking/PairingService.swift:15`, `FeatureServers/AddServerView.swift:41`, `FeatureServers/AddServerView.swift:126`, `FeatureServers/AddServerView.swift:186` (+2 more)
- Evidence: `PairingParser.bareServerAddress (PairingService.swift:37-41) is never called. A server URL pasted into the pairing field gets 'Enter an opencode pairing link, QR payload, or server URL and password.' (line 15).`; `A pairing link pasted into the Server URL field passes PairingParser.serverAddress, which allows paths, and Endpoint.swift:136-137 appends the API paths to it, so the probes go to /auth/connect/<code>/api/info.`; `iphone/add-server.png: the subtitle says 'or scan its QR code', but no Scan button is offered (DataScannerViewController.isSupported is false). The same applies on Mac, which project.yml:44 enables.` (+1 more)
- What happens: A user copies 'http://192.168.1.2:4096' from the server's log into the Pairing link field. They get a generic error with jargon ('QR payload') and no shortcut to password mode. If they scan the Wi-Fi QR code on their router by mistake, the camera closes and the same error appears, and they have to reopen the scanner.
- Why it matters: Common mistakes in the first-run flow end at a generic error, with no step that leads to the right method.
- Fix: Recognise input meant for the other mode: offer 'Use this address with a password' (switch method and prefill the address), or 'This is a pairing link. Pair instead.' Drop 'or scan its QR code' when the scanner is unsupported. In the scanner, ignore payloads that are not pairing links, show an inline hint, and keep scanning. Use .cancellationAction for the scanner's Cancel, and add an Open Settings button when the camera is denied.

<a id="f01-14"></a>

## F01-14: The connection form has no keyboard flow: Return never advances or connects, and Return in the pairing field inserts a line break

*P3 improvement · interaction · effort S · found by servers-onboarding*

- Where: `FeatureServers/AddServerView.swift:54`, `FeatureServers/AddServerView.swift:62`, `FeatureServers/AddServerView.swift:69`, `FeatureServers/AddServerView.swift:80`
- Evidence: `AddServerView has no @FocusState, .submitLabel or .onSubmit. The only .onSubmit in FeatureServers is ServerDetailView.swift:27.`; `AddServerView.swift:54: the pairing TextField uses axis: .vertical, so Return inserts a newline. It has no .keyboardType(.URL) and no Paste button.`; `AddServerView.swift:62: the Name field keeps sentence capitalisation and autocorrection.` (+1 more)
- What happens: iPhone, password mode: Return in Name does not move to Server URL, and Return in Password only hides the keyboard, so Connect needs another tap. iPad with a Magic Keyboard: Return in the password field never connects. In the pairing field, Return adds a line break.
- Why it matters: Setup takes extra taps on a form most users fill in once, under some friction already, and keyboard users on iPad cannot submit it from the keyboard.
- Fix: Add @FocusState, with .submitLabel(.next) on Name and URL, and .submitLabel(.go) plus .onSubmit { connectTapped() } on Password. Make the pairing field submit on Return (single line, or intercept the newline) and add a PasteButton beside it. Add .keyboardShortcut(.defaultAction) to Connect, and .textInputAutocapitalization(.words) and .autocorrectionDisabled() to Name.
