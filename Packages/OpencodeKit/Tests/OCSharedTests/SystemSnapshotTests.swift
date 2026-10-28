import Foundation
import Testing
import OCShared

private let studio = "00000000-0000-0000-0000-0000000000A1", laptop = "00000000-0000-0000-0000-0000000000A2"
private let base = Date(timeIntervalSince1970: 1_800_000_000)
private func at(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }
private func session(_ id: String, server: String = studio, status: SystemSnapshot.Status = .idle, minutes: Double = 0, requests: Int = 0,
                     request: SystemSnapshot.Request? = nil) -> SystemSnapshot.Session {
    .init(server: server, session: id, title: "Title " + id, project: "opencode-ios", projectID: "prj", status: status, activity: at(minutes),
          runningSince: status.isRunning ? at(minutes - 5) : nil, requests: requests, request: request)
}
private func servers(_ reachability: SystemSnapshot.Reachability = .online, synced: Date? = nil) -> [SystemSnapshot.Server] {
    [.init(id: studio, name: "Studio Mac", reachability: reachability, syncedAt: synced), .init(id: laptop, name: "Laptop", reachability: reachability, syncedAt: synced)]
}
private func directory() -> URL { FileManager.default.temporaryDirectory.appending(path: UUID().uuidString) }

@Test func snapshotRoundTripsAtomicallyAndReadsTolerantly() throws {
    let root = directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = SystemSnapshotStore(directory: root)
    #expect(store.read() == .missing)
    let snapshot = SystemSnapshot(writtenAt: base, servers: servers(), sessions: [session("ses_1", status: .needsYou, requests: 2, request: .init(id: "per_1", kind: .permission, session: "ses_child"))],
                                  projects: [.init(server: studio, project: "prj", name: "opencode-ios", activity: base)],
                                  lastProject: .init(server: studio, project: "prj", name: "opencode-ios"))
    try store.write(snapshot)
    #expect(store.read() == .snapshot(snapshot))
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { !$0.hasPrefix(".") } == ["snapshot.json"], "No temporary file is left")
    // Unknown keys and values, and one malformed row, never hide the rest.
    let raw = """
    {"version":1,"writtenAt":1800000000,"future":true,"servers":[{"id":"\(studio)","name":"Studio Mac","reachability":"teleporting"}],
     "sessions":[{"server":"\(studio)","session":"ses_ok","title":"Kept","project":"p","projectID":"p","status":"pondering","unread":false,
       "activity":1800000000,"requests":0},{"broken":1},7],"projects":"nope"}
    """
    try Data(raw.utf8).write(to: root.appending(path: "snapshot.json"))
    let tolerant = try #require(store.read().snapshot)
    #expect(tolerant.servers.first?.reachability == .offline && tolerant.sessions.map(\.session) == ["ses_ok"])
    #expect(tolerant.sessions.first?.status == .idle && tolerant.projects.isEmpty)
    try Data(#"{"version":2,"writtenAt":1}"#.utf8).write(to: root.appending(path: "snapshot.json"))
    #expect(store.read() == .newer(2), "A newer app's snapshot asks for the app")
    try Data("not json".utf8).write(to: root.appending(path: "snapshot.json"))
    #expect(store.read() == .unreadable)
}

@Test func theSnapshotHoldsNoSecretsOrPaths() throws {
    let snapshot = SystemSnapshot(writtenAt: base, servers: servers(), sessions: [session("ses_1", status: .needsYou, requests: 1, request: .init(id: "per_1", kind: .permission))],
                                  projects: [.init(server: studio, project: "prj", name: "opencode-ios", activity: base)],
                                  lastProject: .init(server: studio, project: "prj", name: "opencode-ios"))
    let root = directory()
    defer { try? FileManager.default.removeItem(at: root) }
    try SystemSnapshotStore(directory: root).write(snapshot)
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appending(path: "snapshot.json")))
    var keys: Set<String> = []
    func walk(_ value: Any) {
        if let object = value as? [String: Any] { for (key, item) in object { keys.insert(key); walk(item) } }
        if let array = value as? [Any] { array.forEach(walk) }
    }
    walk(json)
    let allowed: Set<String> = ["version", "writtenAt", "servers", "sessions", "projects", "lastProject", "id", "name", "reachability", "syncedAt", "server",
                                "session", "title", "project", "projectID", "status", "unread", "activity", "runningSince", "requests", "request", "kind", "suggestsSessions"]
    #expect(keys.isSubset(of: allowed) && keys.contains("title"),
            "Only names, titles, states, times and identifiers: no credential, address, path or text field exists")
}

@Test func sessionsLinkToTheirRequestInTheOwningSession() throws {
    let child = session("ses_root", status: .needsYou, requests: 1, request: .init(id: "per_1", kind: .permission, session: "ses_child"))
    #expect(child.url?.absoluteString == "opencodeios://server/\(studio)/session/ses_child/request/per_1")
    let failed = session("ses_fail", status: .failed, request: .init(id: "error", kind: .failure))
    #expect(failed.url?.absoluteString == "opencodeios://server/\(studio)/session/ses_fail/request/error")
    #expect(session("ses_idle", request: .init(id: "per_x", kind: .permission)).url?.absoluteString == "opencodeios://server/\(studio)/session/ses_idle",
            "A row that no longer waits opens the session")
}

@Test func onlyTheWidgetsAndControlsWhoseContentChangedReload() {
    let old = SystemSnapshot(writtenAt: base, servers: servers(), sessions: [session("a", status: .running, minutes: -1), session("b", minutes: -10)])
    let all = Set(WidgetKind.allCases.map(SystemReload.widget) + ControlKind.allCases.map(SystemReload.control))
    #expect(SystemSnapshot.reloads(from: nil, to: old) == all, "The first snapshot reloads everything")
    var renamed = old; renamed.servers[0].name = "Studio"
    #expect(SystemSnapshot.reloads(from: old, to: renamed) == all)
    var asking = old; asking.sessions[1] = session("b", status: .needsYou, minutes: -10, requests: 1, request: .init(id: "per", kind: .permission))
    #expect(SystemSnapshot.reloads(from: old, to: asking) == [.widget(.needsYou), .control(.reviewApproval), .widget(.recent)])
    var finished = old; finished.sessions[0].status = .idle; finished.sessions[0].runningSince = nil
    #expect(SystemSnapshot.reloads(from: old, to: finished) == [.widget(.running), .widget(.recent)])
    var project = old; project.lastProject = .init(server: studio, project: "prj", name: "opencode-ios")
    #expect(SystemSnapshot.reloads(from: old, to: project) == [.control(.newPrompt)])
    var rewritten = old; rewritten.writtenAt = at(30)
    #expect(SystemSnapshot.reloads(from: old, to: rewritten).isEmpty && rewritten.hasSameContent(as: old))
}

@Test func widgetContentCoversEveryState() {
    var rows: [SystemSnapshot.Session] = []
    for index in 0..<9 {
        let asks = index < 4
        let request: SystemSnapshot.Request? = asks ? .init(id: "per_\(index)", kind: .permission) : nil
        rows.append(session("ses_\(index)", server: index % 2 == 0 ? studio : laptop, status: asks ? .needsYou : .idle,
                            minutes: Double(-index), requests: asks ? 1 : 0, request: request))
    }
    let all = SystemSnapshot(writtenAt: base, servers: servers(), sessions: rows)
    #expect(WidgetContent.make(.missing, pending: [:], kind: .needsYou, server: nil, size: .medium, now: base).state == .noData)
    #expect(WidgetContent.make(.newer(2), pending: [:], kind: .needsYou, server: nil, size: .medium, now: base).state == .needsApp)
    #expect(WidgetContent.make(.snapshot(.init(writtenAt: base)), pending: [:], kind: .recent, server: nil, size: .small, now: base).state == .noServer)
    #expect(WidgetContent.make(.snapshot(all), pending: [:], kind: .needsYou, server: "gone", size: .medium, now: base).state == .serverRemoved)
    let empty = WidgetContent.make(.snapshot(.init(writtenAt: base, servers: servers())), pending: [:], kind: .running, server: nil, size: .large, now: base)
    #expect(empty.state == .empty && empty.rows.isEmpty && empty.count == 0)
    // Many: the rows that fit, newest first, the rest counted; the count is the push store's pending total. A medium widget keeps
    // room for that footer.
    let many = WidgetContent.make(.snapshot(all), pending: [studio: 3, laptop: 4], kind: .needsYou, server: nil, size: .medium, now: base)
    #expect(many.state == .rows && many.rows.map(\.id) == ["\(studio):ses_0", "\(laptop):ses_1"] && many.overflow == 2)
    let three = WidgetContent.make(.snapshot(all), pending: [:], kind: .needsYou, server: studio, size: .medium, now: base)
    #expect(three.rows.count == 2 && three.overflow == 0, "Exactly what fits needs no footer")
    #expect(WidgetContent.make(.snapshot(all), pending: [:], kind: .needsYou, server: nil, size: .large, now: base).rows.count == 4)
    #expect(many.count == 7 && many.rows.first?.detail == "opencode-ios · Studio Mac" && many.url == many.rows.first?.url && !many.stale)
    // A server missing from the push store counts its rows' requests instead.
    #expect(WidgetContent.make(.snapshot(all), pending: [studio: 3], kind: .needsYou, server: nil, size: .medium, now: base).count == 5)
    // Per server: only its rows, without the server in the detail, and its name in the header.
    let one = WidgetContent.make(.snapshot(all), pending: [studio: 3, laptop: 4], kind: .recent, server: laptop, size: .large, now: base)
    #expect(one.rows.allSatisfy { $0.id.hasPrefix(laptop) } && one.rows.first?.detail == "opencode-ios" && one.serverName == "Laptop")
    let circle = WidgetContent.make(.snapshot(all), pending: [:], kind: .needsYou, server: nil, size: .circular, now: base)
    #expect(circle.rows.isEmpty, "The circle shows the count only")
    #expect(WidgetContent.placeholder(kind: .running, size: .large).rows.count == 6)
    #expect(ControlContent.waitingRequests([studio: 3, laptop: 4]) == 7 && ControlContent.waitingText(0) == "None waiting" && ControlContent.waitingText(2) == "2 waiting")
    #expect(ControlContent.newPromptProject(.snapshot(.init(writtenAt: base, lastProject: .init(server: studio, project: "p", name: "docs")))) == "docs")
}

@Test func widgetsTurnStaleWhenTheirServersStopBeingOnline() {
    let online = SystemSnapshot(writtenAt: base, servers: servers(), sessions: [session("ses_run", status: .running)])
    let fresh = WidgetTimelinePlan.make(.snapshot(online), pending: [:], kind: .running, server: nil, size: .medium, now: at(5))
    #expect(fresh.entries.map(\.date) == [at(5), at(60)], "Online: stale only an hour after the last write")
    #expect(fresh.entries.map(\.content.stale) == [false, true] && fresh.refresh == at(120))
    let paused = SystemSnapshot(writtenAt: at(-2), servers: servers(.paused, synced: at(-3)), sessions: [session("ses_run", status: .running)])
    let plan = WidgetTimelinePlan.make(.snapshot(paused), pending: [:], kind: .running, server: nil, size: .medium, now: base)
    #expect(plan.entries.map(\.date) == [base, at(12)], "Paused: stale fifteen minutes after the last sync")
    let later = WidgetContent.make(.snapshot(paused), pending: [:], kind: .running, server: nil, size: .medium, now: at(20))
    #expect(later.stale && later.updated == at(-3) && later.rows.first?.label(stale: true) == "Last seen running")
    let missing = WidgetTimelinePlan.make(.missing, pending: [:], kind: .recent, server: nil, size: .small, now: base)
    #expect(missing.entries.count == 1 && missing.entries[0].content.state == .noData)
}

@Test func composeLinksOpenTheNewSessionComposer() throws {
    let server = try #require(UUID(uuidString: studio))
    let plain = try #require(DeepLink.compose(serverID: server))
    #expect(plain.absoluteString == "opencodeios://server/\(studio)/new")
    let link = try #require(DeepLink(url: plain))
    #expect(link.compose && link.projectID == nil && link.sessionID == nil)
    let project = try #require(DeepLink.compose(serverID: server, projectID: "prj_ios"))
    #expect(DeepLink(url: project)?.projectID == "prj_ios" && DeepLink(url: project)?.compose == true)
    for bad in ["opencodeios://server/\(studio)/old", "opencodeios://server/\(studio)/project/prj", "opencodeios://server/\(studio)/project/../new",
                "opencodeios://server/\(studio)/project/p/new?x=1", "opencodeios://server/\(studio)/session/s/new"] {
        #expect(URL(string: bad).flatMap(DeepLink.init(url:)) == nil, "\(bad)")
    }
    #expect(DeepLink(url: try #require(URL(string: "opencodeios://server/\(studio)/session/ses_1/request/per_1")))?.compose == false)
}

@Test func pendingCountsAreReadPerServer() throws {
    let root = directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PushSnapshotStore(directory: root)
    try store.setPending(2, server: studio); try store.setPending(5, server: laptop)
    #expect(try store.pendingCounts() == [studio: 2, laptop: 5])
    try store.remove(server: laptop)
    #expect(try store.pendingCounts() == [studio: 2])
}

/// The widgets draw Home's status icons from copies; they must stay the app's.
@Test func widgetIconsMatchTheApp() throws {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../../..").standardizedFileURL
    let copies = repository.appending(path: "Extensions/Widgets/WidgetIcons.xcassets")
    let originals = repository.appending(path: "Packages/OpencodeKit/Sources/OCDesign/Resources/Icons.xcassets")
    let icons = try FileManager.default.contentsOfDirectory(atPath: copies.path).filter { $0.hasSuffix(".imageset") }
    #expect(Set(icons) == ["warning.imageset", "circle-x.imageset", "check.imageset", "circle-ban-sign.imageset", "server.imageset"])
    for icon in icons {
        for file in try FileManager.default.contentsOfDirectory(atPath: copies.appending(path: icon).path) {
            #expect(try Data(contentsOf: copies.appending(path: icon).appending(path: file)) == Data(contentsOf: originals.appending(path: icon).appending(path: file)), "\(icon)/\(file)")
        }
    }
}
