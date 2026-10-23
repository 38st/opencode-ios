# UI review: Servers and settings

Part of the [UI review](README.md). 19 bugs and 4 improvements, bugs first, then by severity. Paths under `Packages/OpencodeKit/Sources` are written without that prefix.

| ID | Severity | Finding |
| --- | --- | --- |
| [F02-02](#f02-02) | P2 bug | Adding or pairing a server that is already saved creates a second record, so every session and request appears twice |
| [F02-04](#f02-04) | P2 bug | Removing an endpoint the server advertises does not stick: it is re-added as 'discovered' within a second |
| [F02-06](#f02-06) | P2 bug | Problem-state status pills fail contrast in light mode, look alike, and expose internal state names to VoiceOver |
| [F02-07](#f02-07) | P2 bug | Remove server keeps the server's cached transcripts, drafts and unsent prompts on the device, and the confirmation does not say so |
| [F02-08](#f02-08) | P2 bug | App preferences are hard to understand: the Follow-up behavior picker has no visible label and the toggles have no explanations |
| [F02-14](#f02-14) | P2 bug | A save failure leaves an undismissable error toast over the bottom of every screen until relaunch |
| [F26-02](#f26-02) | P2 bug | iPad: returning to a session reopens its review panel because presentRequest is never consumed |
| [F40-01](#f40-01) | P2 bug | iPad New session (+, ⌘N, /new) ignores the server chosen in Home and starts on the open session's server |
| [F40-06](#f40-06) | P2 bug | iPad 'Back to parent' rebuilds the parent transcript at the newest message, unlike iPhone |
| [F40-10](#f40-10) | P2 bug | Deep links route underneath open sheets and fail silently or misleadingly |
| [G01-M2](#g01-m2) | P2 bug | A denied Local Network permission is never detected on the connection path, so LAN servers only show 'Retrying … could not be reached' and the 'Allow Local Network access' link never appears |
| [G16-M1](#g16-m1) | P2 bug | A failed resync is swallowed: no retry and no UI, so the app reads Connected over pre-gap state |
| [F02-03](#f02-03) | P3 bug | 'Check again' swaps the update screen for the server-details form while it re-probes, then swaps back with no result |
| [F02-05](#f02-05) | P3 bug | Pressing Return in the server name field saves an empty name |
| [F02-11](#f02-11) | P3 bug | Server detail shows 'Version: Checking…' forever, 'Pairing: Needs 2.0.25' when the version is unknown, and 'expires soon' for an expired token |
| [F02-12](#f02-12) | P3 bug | Diagnostics are hard to read: 'attempt 0', 'Last 1 transitions', no times, oldest first, and an export without the app version |
| [F29-13](#f29-13) | P3 bug | Internal terms leak into user-facing copy: endpoints, transitions, resyncs, outbox, server record, V1 and “attempt 0” |
| [G14-M3](#g14-m3) | P3 bug | After one failed session creation on iPad, later returns to New session repeat 'Failed to create session. Your prompt has been restored.' |
| [G14-M2](#g14-m2) | P3 bug | Tapping Review for a request in the session already open rebuilds the screen, and tapping it again does nothing |
| [F33-11](#f33-11) | P2 improvement | First-run pairing points only to LAN pairing and ends in Settings instead of Home |
| [G18-M1](#g18-m1) | P2 improvement | The iPad top strip shows every project as a filter tab, but the reference strip holds tabs for open sessions, with attention dots |
| [F02-13](#f02-13) | P3 improvement | Server detail puts the Reconnect and endpoint actions far from the status and doesn't show which endpoint is in use |
| [F40-09](#f40-09) | P3 improvement | No navigation state survives the app being killed: open session, Home filters, Files tabs |

<a id="f02-02"></a>

## F02-02: Adding or pairing a server that is already saved creates a second record, so every session and request appears twice

*P2 bug · functional · effort M · found by servers-management*

- Where: `OCSync/ServerRegistry.swift:144-148`, `OCSync/ServerSetup.swift:20-24`, `OCSync/ServerSetup.swift:36-40`, `OCNetworking/PairingService.swift:131`, `FeatureInbox/HomeView.swift:32-40` (+2 more)
- Evidence: `'guard !servers.contains(where: { $0.id == record.id }) else { throw ServerSetupError.duplicateServer }': record IDs are always fresh UUIDs, so this check never fires for a real duplicate`; `'public var id: String { server.id.rawValue.uuidString + ":" + session.id }': a duplicate server produces separate rows`; `The UI smoke test adds the sandbox by password, then pairs the same URL and waits for 2 connected servers`
- What happens: The user added 'Studio Mac' with a password. Later they run `opencode pair` to switch to a token, or retry a setup that looked stuck, and paste the link. The app saves a second server named '192.168.1.20' with the same endpoint. Home now lists every session twice, Needs you shows every permission and question twice, and both records keep their own event stream. The two cards in Settings give no hint which one to remove.
- Why it matters: A duplicated triage list and duplicated approvals, double network and battery use, and confusion about which copy to act on. M5b push registration would also be doubled.
- Fix:
  - Before saving in addManually or pair, normalise the endpoint URLs and look for a saved server whose endpoints overlap the new ones.
  - If one is found, offer 'Update credentials for Studio Mac' and take the ServerStore.repair path, merging the new endpoints, instead of adding a server.
  - Also reject such a duplicate in ServerRegistry.add as a backstop.

<a id="f02-04"></a>

## F02-04: Removing an endpoint the server advertises does not stick: it is re-added as 'discovered' within a second

*P2 bug · state · effort M · found by servers-management*

- Where: `FeatureServers/ServerDetailView.swift:56`, `OCSync/ServerStore.swift:117`, `OCSync/ServerStore.swift:172`, `OCSync/ServerStore.swift:198`, `OCNetworking/EndpointResolver.swift:56` (+2 more)
- Evidence: `'discover(resolution.discovered.map(\.url))', and apply(info) calls 'discover(info.urls)': both append any non-loopback URL that is not already saved`; `research/01-opencode-server-api.md:292: /api/info 'urls' lists one URL per non-internal interface, plus tunnel URLs`; `'let enabled = endpoints.filter(\.isEnabled)': the resolver honours isEnabled, but no UI sets it`
- What happens: The Mac also has a VPN or VM bridge interface, so /api/info lists http://10.8.0.2:49374. The app adds it as an endpoint that always shows 'The server did not respond in time'. The user taps Remove endpoint. replaceEndpoints restarts the connection straight away, the next successful probe reports the same URL, and within about a second the row is back and saved again. A manually added URL that the server also advertises behaves the same way.
- Why it matters: Remove endpoint looks broken. Unreachable addresses keep adding up to a 2 s LAN timeout to every endpoint race and fill the list with failure messages.
- Fix:
  - For URLs the server advertises, offer Disable instead of Remove: set isEnabled = false, save it, and show the row greyed out with an Enable action.
  - Alternatively, keep a per-server list of dismissed URLs that discover() skips.
  - Label each endpoint's source: Paired, Added or Discovered.

<a id="f02-06"></a>

## F02-06: Problem-state status pills fail contrast in light mode, look alike, and expose internal state names to VoiceOver

*P2 bug · accessibility · effort M · found by servers-management*

- Where: `FeatureServers/ServerRow.swift:22`, `FeatureServers/ServerRow.swift:61`, `OCDesign/Rows.swift:19`, `OCDesign/Rows.swift:37`, `OCDesign/Colors.swift:66` (+5 more)
- Evidence: `Packages/OpencodeKit/Tests/FeatureServersTests/__Snapshots__/ServerRowTests/allStatesAtLargestDynamicType.update-light-402.png`; `Packages/OpencodeKit/Tests/FeatureServersTests/__Snapshots__/ServerRowTests/allStatesAtLargestDynamicType.retrying-light-402.png`; `Packages/OpencodeKit/Tests/FeatureServersTests/__Snapshots__/ServerRowTests/allStatesAtLargestDynamicType.repair-light-402.png` (+4 more)
- What happens: In light mode, at any text size, 'Retrying in 12s', 'Needs re-pairing', 'Update opencode' and 'Not an opencode server' are pale gold on cream, below WCAG AA even for large text. All four share the same 6 pt yellow dot, which stays 6 pt at accessibility5, so they can be told apart only by reading them. 'Unencrypted' and 'Pairing expires soon' use a closed padlock, which reads as 'secure'.

  With VoiceOver on the server detail screen, the pill speaks its internal state name as its value: 'Starting, serviceStarting', 'Connecting, idle', 'Paused, suspended', 'Needs re-pairing, unauthorized'. On a Settings row the retry reason is exposed twice: once in the pill's label and again as the separate detail text.
- Why it matters: The states that need action are the hardest to read, so low-vision users can miss them. VoiceOver output is noisy and uses internal jargon.
- Fix:
  - In light mode, use a darker warning colour for text (at least 4.5:1, around #8A6500 on #FEFAEC), or draw the pill text in OCColor.text with a coloured icon. The gold comes from the OC-2 token, so this revisits docs/design.md's token fidelity.
  - Draw a distinct icon per state by mapping ServerStatus.symbol to the OC icon set (warning, refresh, arrow-up and so on), scaled with Dynamic Type.
  - Use a warning icon instead of the closed padlock for 'Unencrypted'.
  - Set the stable state value only in UI-test runs, or put it on a hidden automation element. This revisits the decision recorded in docs/m3a-audit.md:97.
  - Hide the duplicate detail text from accessibility.
- Verifier's note: From F01-09: the same light-mode warning foreground also affects the re-pair OCBanner (AddServerView.swift:45) and the token-expiry line (:47-48). 'No pairing link?' uses textFaint #808080 at 3.95:1 (:143). Fix the warning foreground once, in the light-mode colour asset or with an OCTone text override, and give OCBanner a warning glyph instead of 'info'.
- Also reported as: F01-09 by servers-onboarding

<a id="f02-07"></a>

## F02-07: Remove server keeps the server's cached transcripts, drafts and unsent prompts on the device, and the confirmation does not say so

*P2 bug · privacy · effort M · found by servers-management*

- Where: `OCSync/ServerRegistry.swift:167`, `OCPersistence/LocalStores.swift:134`, `OCPersistence/PersistenceWriter.swift:110`, `FeatureServers/ServerDetailView.swift:97`, `FeatureServers/ServerRootView.swift:138`
- Evidence: `remove() only deletes the Keychain credential, disposes the store and calls FileCache.shared.removeServer`; `OCPersistence has no DELETE … WHERE server_id=? for the project, catalog, draft or outbox tables. Session and message rows are deleted only per session, by user delete or the global LRU.`; `Confirmation title: "Remove this server and its saved credential?"`
- What happens: The user removes an old work server.
  - Its sessions and full transcripts (code, command output) stay in cache.sqlite until the global LRU happens to evict them.
  - Its projects, catalogs, drafts and outbox entries are never deleted. Re-adding the machine creates a new ServerID, so these rows stay orphaned.
  - Unsent prompts in that server's outbox are dropped without warning.
  - If one of its sessions is open in the iPad main column, the column changes to the bare text 'This server is no longer saved.'
- Why it matters: Data the user believes is gone stays on the device, which is a privacy and storage problem, and unsent work is lost without warning.
- Fix:
  - Delete every row for the server's ID in one transaction: session, message, transcript_window, local_meta, project, catalog, draft and draft files, outbox and review marks.
  - Name the server in the dialog ('Remove Studio Mac?') and list what will be deleted, including '2 unsent prompts will be discarded'.
  - Clear any session path or server selection that points at the removed server.
- Also reported as: F39-03 by privacy-security-ui

<a id="f02-08"></a>

## F02-08: App preferences are hard to understand: the Follow-up behavior picker has no visible label and the toggles have no explanations

*P2 bug · copy · effort S · found by servers-management*

- Where: `FeatureServers/ServerSettingsView.swift:27`, `FeatureServers/ServerSettingsView.swift:31`, `OCDesign/Surfaces.swift:50`, `OCDesign/Controls.swift:54`
- Evidence: `iphone/server-list.png`; `crops/servers-management/app-section.png ('Steer' starts at 37 pt, the toggle rows at 25 pt)`; `crops/servers-management/dark-toggles.png (switch on-track #FAFAFA in dark mode)` (+1 more)
- What happens: In Settings on iPhone:
  - The first App control is a bare 'Steer ⌃⌄' menu button. A menu-style Picker outside a Form does not draw its 'Follow-up behavior' label, and the button sits about 12 pt to the right of the rows below.
  - Nothing explains Steer versus Queue, what Wrap lines affects (diffs and the file viewer), or what Show agent does.
  - 'List the files each turn changed when it finishes' sits 24 pt below Changed files and 24 pt above Show agent, so it could belong to either.
  - In dark mode the switches use the text colour as their tint, so a switch that is on has a #FAFAFA track under a white thumb.
- Why it matters: Users cannot tell what these settings do. Follow-up behavior decides whether a prompt sent during a run goes into that run (Steer) or waits until it finishes (Queue).
- Fix:
  - Use OCToggleRow(title, detail:) for the three toggles. It already provides the title plus muted description and the accent-coloured switch, and the review and form screens use it.
  - Make Follow-up behavior a labelled row: a title, the description 'While the agent is working, Steer adds your message to the current run; Queue sends it after the run finishes', and a trailing Menu.
  - Add descriptions for Wrap lines ('Wrap long lines in diffs and files') and Show agent (the reference copy).
- Also reported as: F02-10 by servers-management, F20-08 by design-system, F29-03 by ux-writing, F30-04 by visual-polish-iphone, F32-06 by design-parity, F33-12 by ux-flows-ia, F38-07 by sweep-approval-server-snapshots

<a id="f02-14"></a>

## F02-14: A save failure leaves an undismissable error toast over the bottom of every screen until relaunch

*P2 bug · state · effort S · found by servers-management*

- Where: `FeatureServers/ServerRootView.swift:110-120`, `OCSync/ServerRegistry.swift:103`, `OCSync/ServerRegistry.swift:217-218`, `OCSync/ServerRegistry.swift:232`
- Evidence: `'if let error = registry.error { OCToast { Text(error)... if !registry.isLoaded { Button("Try again") ... } } }'`; `registry.error is set when draft or server saves fail during a scene-phase change, and is reset to nil only inside load(), which never runs again once the app has loaded`
- What happens: The device is nearly full, so moving the app to the background fails to flush a draft and registry.error becomes 'Could not save drafts before pausing.' When the user returns, a floating card with that text sits at the bottom of Home, and on iPhone over the session composer. It has no close or retry button and stays until the app is relaunched, even after later saves succeed.
- Why it matters: A stale error stays on screen indefinitely and covers the prompt dock and the bottom of lists. The trigger is rare.
- Fix:
  - Clear registry.error when a later flush or save succeeds.
  - Auto-dismiss the toast after a few seconds, or give it a close button.
  - Offer Retry, which re-runs the flush, when the app is already loaded.
- Raised from P3 to P2, the severity of F26-06, which describes the same problem.
- Also reported as: F26-06 by swiftui-state, F28-12 by states-coverage

<a id="f26-02"></a>

## F26-02: iPad: returning to a session reopens its review panel because presentRequest is never consumed

*P2 bug · state · effort S · found by swiftui-state*

- Where: `FeatureServers/ServerRootView.swift:163`, `OCDesign/WorkspaceShell.swift:57`, `OCSync/ReviewModel.swift:76`, `OCSync/FilesModel.swift:178`
- Evidence: `ServerRootView.swift:163-167 'panelRequest' returns the selected session's 'review.presentRequest' or 'files.presentRequest' and is passed as 'reviewRequest'`; `WorkspaceShell.swift:57 '.onChange(of: reviewRequest) { _, request in if request != nil { if beside { reviewOpen = true } else { reviewSheet = true } } }'`; `ReviewModel.swift:76 and FilesModel.swift:161/178 set 'presentRequest = UUID()'; grep finds nothing that sets it back to nil`
- What happens: On iPad, in session A, tap a file link in the transcript or a file in a turn's changes card, and the review panel opens. Close it with the toggle, pick session B in Home, then pick A again. `panelRequest` changes from nil to A's old UUID, so OCWorkspaceShell opens the side panel again; in windows narrower than 768 pt (Split View, Stage Manager) it presents the review sheet instead. The same happens when moving between any two sessions that ever had a request, and when coming back from New session.
- Why it matters: The review panel opens on its own during ordinary navigation, squeezing the transcript or covering it with a sheet, and closing it does not stick.
- Fix: Make the request one-shot: clear it once the shell or SessionScreen has acted on it, for example with a `consumePresentRequest()` on ReviewModel and FilesModel. Alternatively, remember the last handled UUID per session and react only when the request changes while the same session stays selected.
- Also reported as: F40-02 by navigation-state-restoration, G10-M1 by verifier G10

<a id="f40-01"></a>

## F40-01: iPad New session (+, ⌘N, /new) ignores the server chosen in Home and starts on the open session's server

*P2 bug · ux-flow · effort M · found by navigation-state-restoration*

- Where: `FeatureServers/ServerRootView.swift:151-155`, `FeatureServers/ServerRootView.swift:156-161`, `FeatureServers/ServerRootView.swift:147`, `FeatureInbox/HomeView.swift:100-112`, `FeatureComposer/NewSessionView.swift:33-53`
- Evidence: `ServerRootView.swift:153 beginSession: 'if let ref = sessionPath.last { selectedServer = ref.serverID }'`; `ServerRootView.swift:147 routeLink: 'selectedServer = id; selectedProject = nil'`; `ipad/ipad-composer-new.png: New session shows only the project and worktree, never a server; the sidebar switcher reads 'Co…'` (+1 more)
- What happens: iPad with two saved servers and a session on server B open in the main column. In the Home sidebar, pick server A in the switcher, then tap + (or press ⌘N, or type /new). beginSession overwrites selectedServer with B, so the switcher flips back to B and the New session composer lists B's projects. NewSessionView never names its server, and the sidebar truncates the switcher label to a few characters, so the user can send the first prompt to the wrong computer. Projects with the same name, such as one repo cloned on both machines, look identical. Following any deep link also silently rewrites the Home filter to that server and clears the project filter, so Back to Home shows a filtered list the user never chose.
- Why it matters: For multi-server users (a headline SPEC feature), prompts can run on the wrong machine, and Home filters change behind the user's back.
- Fix: Separate the Home filter from the new-session target. Pass an explicit target server into NewSessionView: the server chosen in Home if any, otherwise the open session's server, otherwise the first. Show and allow changing that server next to the project selector. Remove the selectedServer and selectedProject writes from beginSession and routeLink. Make the sidebar switcher legible, for example icon-only in the header with the full server name in a row below.
- Also reported as: F33-06 by ux-flows-ia, G06-M2 by verifier G06

<a id="f40-06"></a>

## F40-06: iPad 'Back to parent' rebuilds the parent transcript at the newest message, unlike iPhone

*P2 bug · navigation · effort M · found by navigation-state-restoration*

- Where: `FeatureServers/ServerRootView.swift:52-58`, `FeatureServers/ServerRootView.swift:137`, `FeatureTranscript/TimelineCollection.swift:111`, `FeatureTranscript/TimelineCollection.swift:154`, `FeatureTranscript/SessionTimeline.swift:20-24`
- Evidence: `The main column renders only 'sessionPath.last' through 'sessionView(ref)', which applies '.id(ref.id)', so the parent view is destroyed when a child is pushed`; `A new TimelineScrollControl starts with 'following = true', and its first snapshot calls 'followLatest()'`; `ipad/ipad-subagent.png and ipad-split.png: 'Back to parent' is centred ghost text above the session card, with no chevron and no parent title`
- What happens: iPad: scroll up in a long parent transcript to a subagent card halfway down, tap Open agent, then tap Back to parent. A new parent SessionScreen is built and jumps to the newest message, and expanded tool rows collapse. The same happens on every session switch from Home. On iPhone the parent stays mounted in the NavigationStack and keeps its position, so the two layouts behave differently.
- Why it matters: Reviewing several subagents of one run on iPad means scrolling back through the parent after each one.
- Fix: Store a per-session timeline anchor (first visible row ID and offset, like ReviewModel.scrollOffsets) in ReadStore when SessionScreen disappears. Restore it when the screen is recreated, unless a requestID targets a row. Alternatively, keep the parent mounted under the child. Restyle the control as a leading chevron button showing the parent's title inside the session header, and add ⌘[ with M6's shortcuts.

<a id="f40-10"></a>

## F40-10: Deep links route underneath open sheets and fail silently or misleadingly

*P2 bug · navigation · effort S · found by navigation-state-restoration*

- Where: `FeatureServers/ServerRootView.swift:75-80`, `FeatureServers/ServerRootView.swift:90-98`, `FeatureServers/ServerRootView.swift:140-149`, `FeatureTranscript/SessionScreen.swift:39-41`, `OCShared/DeepLink.swift:9-20` (+1 more)
- Evidence: `routeLink only sets selectedServer, selectedProject and sessionPath; the 'creatingSession' and 'settingsDestination' sheets are left presented`; `ServerRootView.swift:78 'guard let link = DeepLink(url: url) else { return }': no message for an invalid link`; `'Copy session link' embeds 'server.id', a random per-device UUID ('ServerID(rawValue: UUID = UUID())')` (+1 more)
- What happens: iPhone with the New session sheet (or Settings) open: open an opencodeios:// session link, or after M5b tap an approval notification. The stack changes underneath, but the sheet stays on top, so nothing seems to happen until the user cancels the sheet. A truncated or malformed link does nothing at all. A link made with 'Copy session link' and opened on the user's iPad says 'This server is not saved. Add it in Settings first.' even when the same opencode server is saved there, because server IDs are random on each device.
- Why it matters: Shared links and soon notification taps will look broken.
- Fix: In routeLink, clear transient presentations before routing: set creatingSession to false, clear settingsDestination unless a repair is in progress, and close the iPad Home sheet. Show an alert for unparseable links. For an unknown server ID, explain that the link came from another device or a removed server, and offer to open it on a saved server. Label the menu item 'Copy link for this device', or put a portable server identity in the link.
- Verifier's note: On narrow iPads, onChange(of: selectionID) already closes the Home sheet when a session is routed, so that part of the fix is unnecessary. Also present the 'Could not open link' alert after dismissing transient sheets: it is attached to the root, which may already be presenting one.
- Also reported as: F26-07 by swiftui-state

<a id="g01-m2"></a>

## G01-M2: A denied Local Network permission is never detected on the connection path, so LAN servers only show 'Retrying … could not be reached' and the 'Allow Local Network access' link never appears

*P2 bug · state · effort M · found by verifier G01*

- Where: `OCNetworking/NetworkPathMonitor.swift:26`, `OCSync/ServerRegistry.swift:50`, `OCNetworking/ServerConnection.swift:131`, `OCNetworking/EndpointResolver.swift:70`, `OCNetworking/EndpointPolicy.swift:78` (+1 more)
- Evidence: `NetworkPathMonitor.swift:26-29 uses a general 'NWPathMonitor()' and reports denial only when 'path.status == .unsatisfied && path.unsatisfiedReason == .localNetworkDenied'.`; `ServerRegistry.swift:50-51 creates every ServerConnection with 'pathMonitor: nil'. The only path a connection sees is the registry's general one, passed in with setNetworkPath (ServerRegistry.swift:161, 227, 242, 255).`; `ServerConnection.swift:131 passes 'networkPath?.localNetworkDenied ?? false' to the resolver. EndpointResolver.swift:70 maps a LAN transport or timeout failure to .localNetworkDenied only when that flag is true; otherwise diagnose() returns .transport or .timeout (EndpointPolicy.swift:78).` (+1 more)
- What happens: iPhone on home Wi-Fi with internet access. After the app's explanation, the user taps Don't Allow on the iOS Local Network prompt. The general path stays satisfied, so the flag stays false, and every LAN probe fails as a transport error or a 2 s timeout. Settings shows 'Retrying in Ns · Attempt N · The server could not be reached. Check the address and network.' indefinitely, Home rows show 'Syncing', and the server detail never shows the Settings link built for this case. Not verified on a device: this assumes a general NWPathMonitor does not report per-app Local Network denial while internet is reachable; Apple's guidance is to inspect a connection's path to the local endpoint instead.
- Why it matters: A common first-run failure, declining a permission prompt, is reported as a network or address problem, and the app's own recovery link is never shown.
- Fix: Detect denial per endpoint. After a LAN probe fails, open an NWConnection to that host and port and check `currentPath?.unsatisfiedReason == .localNetworkDenied`, or read the NWPath attached to the URLError. Then record .localNetworkDenied, so the row and the detail show 'Allow Local Network access' with an Open Settings button. Feed the same result to the pairing diagnosis (F01-02).

<a id="g16-m1"></a>

## G16-M1: A failed resync is swallowed: no retry and no UI, so the app reads Connected over pre-gap state

*P2 bug · state · effort M · found by verifier G16*

- Where: `OCSync/ResyncCoordinator.swift:56-69`, `OCSync/ReadResync.swift:8-72`, `OCSync/ServerStore.swift:183-184`, `OCNetworking/ServerConnection.swift:233`, `OCNetworking/Endpoint.swift:96` (+2 more)
- Evidence: `ResyncCoordinator.enqueue: 'do { try await self.refresh(reason); ...; try await self.extensionWork?.resync(reason: reason); succeeded = true } catch {}'. A failure only appends a ResyncRecord; nothing re-enqueues it.`; `Resyncs are enqueued only on server.connected, an oversized event or backlog overflow (ServerConnection.swift:223, 233, 239 via ServerStore.swift:183-184).`; `No view reads ResyncCoordinator.isRunning or ResyncRecord.succeeded (grep). DiagnosticsView shows only '\(records.count) recorded' (ServerDetailView.swift:186), and diagnosticsExport omits resyncs.` (+3 more)
- What happens: The phone switches networks or the tunnel blips. The event stream reconnects and server.connected enqueues a resync. One request in it fails: for example /api/info or /api/session/active answers 503 while the server finishes starting, or a GET times out three times on a weak link. The coordinator records the failure and stops. Settings reads 'Connected · Tailscale' and Home rows show the connected check. A session that finished during the gap stays under Running, with 'Working…' and Stop on its session screen. A permission asked during the gap is missing from Needs you until that session is opened or the next reconnect. If this happens on the first connection after launch, every idle row keeps the grey syncing glyph. Diagnostics shows 'Resyncs · 1 recorded' with no sign of the failure.
- Why it matters: This is the 'stream that only looks alive' that SPEC §3 promises to beat. A hidden permission request stalls the agent without the user ever being asked.
- Fix: Retry failed resyncs with backoff while the stream stays connected, or force a reconnect after repeated failures. Surface ResyncCoordinator.isRunning and the last failure in the connection banner proposed in F28-01 ('Refreshing…', 'Couldn't refresh · Retry'). List each resync's outcome, reason and time in Diagnostics and include them in the export.

<a id="f02-03"></a>

## F02-03: 'Check again' swaps the update screen for the server-details form while it re-probes, then swaps back with no result

*P3 bug · state · effort M · found by servers-management*

- Where: `FeatureServers/ServerDetailView.swift:22-24`, `FeatureServers/ServerDetailView.swift:87-92`, `FeatureServers/ServerDetailView.swift:128-158`, `OCNetworking/ServerConnection.swift:76-79`, `OCNetworking/ServerConnection.swift:126` (+3 more)
- Evidence: `iphone/update.png`; `'if case .incompatible(let outcome) = server.state, !showingConnectionDetails { UpdateServerView(...) } else { OCForm { ... } }'`; `After forceReconnect, run() emits '.resolving', then '.incompatible(outcome)' again` (+1 more)
- What happens: On iPhone with 'Legacy server' (opencode 1.19.3), the user runs the commands and taps Check again before restarting the server.
  - The state goes to .resolving, so the screen flips to the full server form (name field, endpoints, capabilities, Reconnect), and the '…' Server details menu item disappears.
  - When the probe reports V1 again, the update screen comes back scrolled to the top, and the 'Copied …' note is gone.
  - The flip lasts as long as the probe, which can take up to 6 s on a non-LAN endpoint.
  - The button never shows progress, and nothing says the result is unchanged.

  The screen also never shows which address it probed or the detected version. 'Not an opencode server' uses the same up-arrow icon while its copy says 'Check the URL'. Nothing tells the user to restart `opencode serve` after upgrading.
- Why it matters: The main recovery flow for outdated servers flickers and looks broken. Users cannot tell whether the check ran or why the server still fails it.
- Fix:
  - Keep UpdateServerView on screen while a re-check is in flight: remember the last incompatible outcome, or add a `checking` flag that the body honours.
  - Show a spinner on Check again and disable it while checking.
  - If the result is unchanged, say so, for example 'Still opencode 1.19.3 at http://…. Restart opencode serve after upgrading.'
  - Show the probed URL with an Edit address action.
  - Use a warning icon for a non-opencode server.
  - For opencode 1.19.0 or later, show only `opencode upgrade --major`.

<a id="f02-05"></a>

## F02-05: Pressing Return in the server name field saves an empty name

*P3 bug · functional · effort S · found by servers-management*

- Where: `FeatureServers/ServerDetailView.swift:27-30`, `FeatureServers/ServerDetailView.swift:86`, `OCSync/ServerStore.swift:113-116`, `OCSync/ServerRegistry.swift:166`, `FeatureInbox/HomeView.swift:102` (+1 more)
- Evidence: `'TextField("Name", text: $name).onSubmit { perform { try await registry.rename(server, to: name) } }' has no guard`; `Save name is disabled for a blank or unchanged name: '.disabled(name == server.record.name || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)'`; `ServerStore.rename: 'record.name = name.trimmingCharacters(in: .whitespacesAndNewlines)', with no validation`
- What happens: The user clears the name to retype it and presses Return, and an empty name is saved. The navigation title goes blank, the Settings card shows only the status pill, the Home server switcher gets an empty menu item, and every session row reads ' · /Users/\<name>'.

  Two smaller problems in the same field:
  - A name with trailing spaces is saved trimmed, but the field keeps the spaces, so Save name stays enabled.
  - Leaving the screen without tapping Save silently drops the edit.
- Why it matters: The server can no longer be identified anywhere in the app until the user renames it again.
- Fix:
  - Reject a blank name in ServerStore.rename, or fall back to the endpoint host.
  - Apply the same check in onSubmit.
  - After a successful save, set `name = server.record.name`.
  - Commit a valid edit on submit or when leaving the screen, instead of needing a separate Save name button.

<a id="f02-11"></a>

## F02-11: Server detail shows 'Version: Checking…' forever, 'Pairing: Needs 2.0.25' when the version is unknown, and 'expires soon' for an expired token

*P3 bug · copy · effort S · found by servers-management*

- Where: `FeatureServers/ServerDetailView.swift:31`, `FeatureServers/ServerDetailView.swift:35`, `FeatureServers/ServerDetailView.swift:43-48`, `FeatureServers/ServerDetailView.swift:72-73`, `OCSync/ResyncCoordinator.swift:9-12` (+2 more)
- Evidence: `Packages/OpencodeKit/Tests/FeatureServersTests/__Snapshots__/ServerRowTests/allStatesAtLargestDynamicType.repair-light-402.png ('Needs re-pairing' and 'Pairing expires soon' together)`; `'LabeledContent("Version", value: server.version ?? "Checking…")'`; `'pairing = info?.supportsPairing ?? false'` (+1 more)
- What happens: A server added with a wrong password, or never reached, shows Version 'Checking…' although nothing is checking. Its Capabilities say 'Pairing: Needs 2.0.25 – Pairing needs opencode 2.0.25 or later' although its version is unknown.

  After a pairing token expires, the server is unauthorized. The detail screen then shows Pair again in the Server section and a second card, 'Your pairing token expires within 5 days.', with another Pair again button. The Settings row shows both 'Needs re-pairing' and 'Pairing expires soon'.
- Why it matters: Users may upgrade a server that is fine, or read an expired credential as a future warning.
- Fix:
  - Show 'Unknown – not connected yet' for the version, and hide the capability verdicts until the server's info is known.
  - Tell an expired token ('Pairing expired on Oct 20') apart from an expiring one ('expires Oct 25').
  - Show a single Pair again button, and drop 'expires soon' once the server needs re-pairing.

<a id="f02-12"></a>

## F02-12: Diagnostics are hard to read: 'attempt 0', 'Last 1 transitions', no times, oldest first, and an export without the app version

*P3 bug · copy · effort S · found by servers-management*

- Where: `FeatureServers/ServerDetailView.swift:171-188`, `OCNetworking/ServerConnection.swift:122`, `OCNetworking/ServerConnection.swift:155`, `OCNetworking/ServerConnection.swift:172`, `OCSync/ServerStore.swift:187-191` (+1 more)
- Evidence: `iphone/diagnostics.png ('Connecting (attempt 0)')`; `Packages/OpencodeKit/Tests/FeatureServersTests/__Snapshots__/DesignScreenTests/screens.diagnostics-light-393x852.png ('Last 1 transitions')`; `'["Opencode connection diagnostics", "Version: \(version)"]'`
- What happens: The Diagnostics screen lists 'Resolving endpoints / Connecting (attempt 0) / Connected · LAN' with no times.
  - The first try is labelled 'attempt 0', while the following 'Retrying … Attempt 1' refers to that same try.
  - A single entry is headed 'Last 1 transitions'.
  - Up to 50 entries are listed oldest first. Each background and foreground cycle adds four, so the current state soon ends up at the bottom.
  - 'Resyncs: 1 recorded' gives no reason, time or result, although ResyncRecord stores all three.
  - In the export, 'Version:' is the server's version, and the app version, build and iOS version are missing. Its 'Ns ago' ages are worked out when the screen last redrew, not when it is shared.
- Why it matters: Diagnostics are the main support tool for connection bugs. Without times or versions, reports are hard to act on.
- Fix:
  - Number attempts from 1.
  - Fix the plural ('Last transition' or 'Last 3 transitions').
  - Show relative times, newest first, and absolute times in the export.
  - List recent resyncs with their reason, time and result.
  - Label 'Server version' and add the app version, build and iOS version.
  - Build the export text when the user shares it.
- Also reported as: F38-10 by sweep-approval-server-snapshots

<a id="f29-13"></a>

## F29-13: Internal terms leak into user-facing copy: endpoints, transitions, resyncs, outbox, server record, V1 and “attempt 0”

*P3 bug · copy · effort M · found by ux-writing*

- Where: `OCSync/ServerStore.swift:241`, `OCSync/ServerStore.swift:242`, `OCSync/ServerStore.swift:257`, `OCNetworking/ServerConnection.swift:122`, `FeatureServers/ServerDetailView.swift:49` (+8 more)
- Evidence: `iphone/diagnostics.png: “Last 3 transitions”, “Resolving endpoints”, “Connecting (attempt 0)”, “Resyncs: 1 recorded”`; `iphone/server-detail.png: “Endpoints”, “New endpoint URL”, “Add endpoint”`; `iphone/update.png: “…Run the first command to update V1 before using it.”` (+2 more)
- What happens: The server detail lists “Endpoints”. For a paired server with several addresses, rows read “Tailscale · Another endpoint won the race”. Diagnostics shows “Last 3 transitions” (or “Last 1 transitions”), “Resolving endpoints”, “Connecting (attempt 0)” and “Resyncs: 1 recorded”. Errors read “This server record is already saved.”, “Could not read the saved outbox.” (in red above the composer) and “Keep at least one endpoint for this server.”. The update screen says “update V1” where other copy says opencode 1. VoiceOver reads the header cost as “Family cost”. An unsupported form field says it “needs a newer client”.
- Why it matters: Users meet implementation vocabulary on exactly the screens they'd use to troubleshoot or report a problem, and the off-by-one counter looks like a bug in the diagnostics themselves.
- Fix: Use user-facing terms:
  - “Addresses” instead of “Endpoints”.
  - “Not used: another address answered first” instead of “won the race”.
  - “Finding the server” instead of “Resolving endpoints”.
  - Number attempts from 1 in both the connecting and retrying rows.
  - “Recent connection events”, with correct plurals.
  - “Full refreshes” instead of “Resyncs”.
  - “opencode 1” instead of “V1”.
  - “This server is already added.”
  - “Couldn’t read prompts waiting to send.”
  - “Total cost, including subagents” instead of “Family cost”.
  - “needs a newer version of this app”, shown once.

  Keep raw names only in the exported diagnostics if support needs them.

<a id="g14-m3"></a>

## G14-M3: After one failed session creation on iPad, later returns to New session repeat 'Failed to create session. Your prompt has been restored.'

*P3 bug · state · effort S · found by verifier G14*

- Where: `FeatureServers/ServerRootView.swift:84`, `FeatureServers/ServerRootView.swift:133`, `FeatureServers/ServerRootView.swift:148`, `FeatureServers/ServerRootView.swift:152`, `FeatureServers/ServerRootView.swift:158` (+1 more)
- Evidence: `ServerRootView.swift:84 'recoveredDirectory = directory' is cleared only in beginSession (ServerRootView.swift:152)`; `'deleted: { sessionPath = [] }' (ServerRootView.swift:133) and server-only links ('?? []', ServerRootView.swift:148) clear sessionPath without resetting it`; `ServerRootView.swift:158 'NewSessionView(server: server, directory: recoveredDirectory)'; NewSessionView.swift:57-60 sets 'error = "Failed to create session. Your prompt has been restored."' whenever initialDirectory is non-nil`
- What happens: On iPad, a session creation is rejected. The app returns to New session with the restored prompt and the message, which is correct. The user sends it successfully and keeps working. Later they delete a session from its header menu, or open a link that names only a server. The main pane shows New session again, back in the old directory, again reading 'Failed to create session. Your prompt has been restored.' above an empty composer.
- Why it matters: A stale failure message suggests a new error, and the composer points at an old directory.
- Fix: Make the recovered directory one-shot. Clear recoveredDirectory once the recovered NewSessionView has resolved it, or in the opened, deleted and routeLink paths. Alternatively, pass the failed session's ID and show the message only while that failure is unresolved.

<a id="g14-m2"></a>

## G14-M2: Tapping Review for a request in the session already open rebuilds the screen, and tapping it again does nothing

*P3 bug · navigation · effort S · found by verifier G14*

- Where: `FeatureServers/ServerRootView.swift:137`, `FeatureServers/ServerRootView.swift:181`, `OCModels/SessionRef.swift:7`, `FeatureTranscript/SessionTimeline.swift:57`, `FeatureTranscript/SessionTimeline.swift:66`
- Evidence: `ServerRootView.swift:137 'SessionScreen(...).id(ref.id)' with SessionRef.swift:7 'id = serverID + ":" + sessionID + (requestID.map { ":" + $0 } ?? "")'`; `ServerRootView.swift:181 'selectSession: { sessionPath = [$0] }'; assigning an equal path changes nothing`; `SessionTimeline.swift:57 '.onChange(of: requestID)' can never fire, because a requestID change replaces the whole view; scrollToRequest is one-shot through pendingScrollDone (SessionTimeline.swift:66-71)`
- What happens: iPad landscape. Session A is open from its Home row and has a pending permission, so Home lists A under Needs you with a Review button. Tapping Review adds the request ID to the ref, so SessionScreen is destroyed and rebuilt: open() and loadFamily() refetch, the rows rebuild from empty and expanded rows collapse, and then it scrolls to the request. The user scrolls away and taps Review again. sessionPath gets an equal value, nothing changes, and the timeline stays where it is. A second deep link for the same request, and in M5b a second notification tap, behaves the same.
- Why it matters: Home's main triage action appears to do nothing when tapped again, and the first tap reloads the conversation the user was reading.
- Fix: Key the session view by server and session only, and pass requestID as an input that SessionTimeline's existing onChange handles. Add a per-tap token (a UUID) to Review and link routing so a repeated request scrolls again.

<a id="f33-11"></a>

## F33-11: First-run pairing points only to LAN pairing and ends in Settings instead of Home

*P2 improvement · ux-flow · effort S · found by ux-flows-ia*

- Where: `FeatureServers/ServerRootView.swift:37-44`, `FeatureServers/ServerRootView.swift:96-98`, `FeatureServers/ServerSettingsView.swift:59-64`, `FeatureServers/ServerSettingsView.swift:69`, `FeatureServers/AddServerView.swift:92-101` (+2 more)
- Evidence: `iphone/onboarding.png`; `iphone/add-server.png (only 'opencode pair' is offered)`; `iphone/server-list.png (Settings shown right after pairing, same minute)` (+1 more)
- What happens: 'Add your first server' opens Settings with Add server stacked on top, and the Local Network explainer and an iOS alert follow. The copy chip offers only `opencode pair`, whose links are LAN addresses unless `--remote` is added; nothing in the app mentions `opencode pair --remote`, OpenTunnel or Tailscale. After pairing, the Add sheet closes onto Settings (follow-up, wrap lines and show agent toggles), and the user must tap Done. An empty Home then shows only 'Your sessions will appear here', with no button to start a session.
- Why it matters: The app's purpose is use away from the desk. A LAN-only pairing silently stops working once the phone leaves Wi-Fi (and finding 2 hides that), and the first run adds modal steps at its most fragile moment.
- Fix: Present Add server directly from onboarding, and on success dismiss to Home, or straight into New session for an empty server. Add a short 'Use it away from home' step that recommends `opencode pair --remote` (with a copy chip) and mentions Tailscale, as research 03 §4.3 Layer 2 advises. Give the empty Home a 'Start a session' button.

<a id="g18-m1"></a>

## G18-M1: The iPad top strip shows every project as a filter tab, but the reference strip holds tabs for open sessions, with attention dots

*P2 improvement · design-parity · effort M · found by verifier G18*

- Where: `FeatureServers/ServerRootView.swift:50`, `FeatureServers/ServerRootView.swift:174`, `OCDesign/WorkspaceShell.swift:76`, `SPEC.md:108`, `ARCHITECTURE.md:534` (+1 more)
- Evidence: `crops/verify-G18/ref-tabstrips.png (top strips from the reference timeline, permission, question, sidebar, review and composer captures: the tab titles 'Design system', 'Permission request', 'Question' and 'Composer reference' each match the session header below them; the active tab is filled with a ×; a blue dot sits on the inactive 'Permission request' tab; there is a grid Home tab and a '+')`; `crops/verify-G18/ref-tabs-sessions.png`; `.build/design-reference/sidebar-light-1180x820.png (the Projects list holds 'project'; the tab strip holds the session 'Design system')` (+2 more)
- What happens: iPad landscape with Home collapsed, or portrait where Home is a sheet, while the user supervises three sessions in two projects. The strip shows a folder tab for every project on every server, re-sorted by activity, and tapping one only changes Home's project filter. Switching from session A to session B means opening Home, finding B in the day list and tapping it, and nothing in the strip shows that B is waiting on a permission. In the reference, each opened session is a tab (project avatar plus session title). The active tab is filled and has a close ×, a dot marks any tab that needs attention, a grid tab returns to Home, and '+' starts a new session.
- Why it matters: The most prominent navigation control on iPad does nothing visible and grows with every directory opencode has seen. Meanwhile the reference's fast switching between sessions, and its per-tab attention dots (visible even with Home collapsed or in portrait), are missing. This also explains the tab confusion in F32-04, F32-05 and F33-07.
- Fix: Replace OCProjectTabs with tabs for open sessions: a leading Home tab (grid icon), then one tab per session opened in this scene, each with OCProjectAvatar, the title, a needs-you or running dot from SessionSummary or SessionModel.attention, and a × to close. Persist the tabs with @SceneStorage. Selecting a tab sets sessionPath; '+' opens New session in the active tab's project. Keep project filtering in Home's picker, and update SPEC §5, ARCHITECTURE §3.4 and docs/design.md D1.1, which all say 'project tabs'.

<a id="f02-13"></a>

## F02-13: Server detail puts the Reconnect and endpoint actions far from the status and doesn't show which endpoint is in use

*P3 improvement · ux-flow · effort M · found by servers-management*

- Where: `FeatureServers/ServerDetailView.swift:32-34`, `FeatureServers/ServerDetailView.swift:49-70`, `FeatureServers/ServerDetailView.swift:76-81`, `FeatureServers/ServerDetailView.swift:117-121`, `OCSync/ServerStore.swift:248-259`
- Evidence: `iphone/server-detail.png (Reconnect is below the first screen)`; `Packages/OpencodeKit/Tests/FeatureServersTests/__Snapshots__/DesignScreenTests/screens.server-detail-dark-393x852.png (Connection diagnostics link has no chevron)`; `.build/design-reference/settings-server-light-393x852.png (each connection row has a … menu)`
- What happens: When Studio Mac is 'Retrying in 30s':
  - The pill at the top gives no reason; the status detail exists only in its accessibility label.
  - Reconnect is the last control on the page, below Capabilities and off-screen on an iPhone 17 Pro.

  With LAN, Tailscale and tunnel endpoints, every reachable one says 'Healthy', and nothing marks the one carrying the connection; the pill says only 'Connected · LAN'.

  Endpoint management:
  - Every endpoint has a full-size Remove endpoint button that acts without confirmation.
  - With one endpoint, a disabled pink button is shown with no reason.
  - Adding a URL that is already saved silently clears the field.
  - Return in the URL field does nothing.
  - A URL cannot be edited (for a port change, for example), only added and removed.

  'Connection diagnostics' is a borderless link with no chevron, so it does not look like it opens a page.
- Why it matters: Retrying an offline server takes a scroll, setups with several endpoints are hard to reason about, and destructive actions are a single tap.
- Fix:
  - Under the pill, show the status detail and a Retry now button while the server is retrying, paused or starting.
  - Mark the endpoint in use as 'In use'.
  - Move per-endpoint actions into a trailing … menu, as in the reference: Copy URL, Edit, and Disable or Remove with confirmation.
  - Hide Remove when there is only one endpoint.
  - Add onSubmit and an 'Already added' message to the endpoint field.
  - Render Connection diagnostics as a row with a chevron.

<a id="f40-09"></a>

## F40-09: No navigation state survives the app being killed: open session, Home filters, Files tabs

*P3 improvement · state · effort M · found by navigation-state-restoration*

- Where: `FeatureServers/ServerRootView.swift:21`, `OCSync/FilesModel.swift:17`, `research/08-feature-matrix.md:292`, `ARCHITECTURE.md:540`
- Evidence: `sessionPath, selectedServer and selectedProject (ServerRootView) are plain @State, as are search and showHidden (HomeView) and homeOpen and reviewOpen (shell)`; `No @SceneStorage, NSUserActivity or scene restoration anywhere in Sources or App (grep), although SessionRef is already Codable`; `ReviewState (tab, selected file, source) is persisted; FilesModel.openFiles and selectedPath are not, and the saved tab is applied only on the first refresh after the panel appears`
- What happens: Read a session on iPhone, then switch to a terminal or browser for a while; iOS evicts the app. Relaunching lands on Home with All servers and All projects selected and the search cleared. On iPad the review panel is closed and Home is open. The draft is saved, but the user has to find the session again to see it. If they had been in the Files tab, reopening review starts on Changes, flips to Files after the first refresh, and shows an empty tree instead of the file they had open.
- Why it matters: Eviction is frequent on phones, so this breaks the 'fast resume' promise in SPEC §4.1 and makes the persisted draft hard to find.
- Fix: Encode `[SessionRef]`, selectedServer, selectedProject and panel visibility into @SceneStorage (JSON). Restore them after `registry.load()`, dropping refs whose server or session no longer exists. Persist FilesModel's open files and selected path alongside ReviewState. ARCHITECTURE §3.4 already plans @SceneStorage for M6 windows; applying it to the single window now also covers iPhone.
