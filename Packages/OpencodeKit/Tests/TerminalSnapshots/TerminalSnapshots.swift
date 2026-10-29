#if os(iOS)
import Foundation
import Synchronization
import SwiftUI
import UIKit
import Testing
import SnapshotTesting
import OCFoundation
import OCModels
import OCDesign
import OCNetworking
import OCPersistence
import OCSync
@testable import FeatureTerminal

/// Terminals in light and dark at the iPhone width and an iPad panel's width, and at the largest text size, which
/// leaves the terminal's own font unchanged.
@MainActor @Suite(.serialized) struct TerminalSnapshots {
    @Test func terminalList() async throws {
        // Models hold their store weakly, as the app's server holds it; the test keeps each store alive.
        let full = store(terminals: [pty("pty_1", "Terminal 1"), pty("pty_2", "Build", command: "/bin/zsh", status: "exited", exit: 1),
                                     pty("pty_3", "Terminal 3", status: "exited", exit: 0)])
        let list = full.terminals(directory: "/Users/Shared/opencode-ios")
        await capture(TerminalListView(list: list, open: { _ in }, runCommand: {}), name: "list") { !list.terminals.isEmpty }
        let none = store(terminals: [])
        let empty = none.terminals(directory: "/Users/Shared/opencode-ios")
        await capture(TerminalListView(list: empty, open: { _ in }, runCommand: {}), name: "list-empty") { empty.loaded }
        withExtendedLifetime((full, none)) {}
    }
    @Test func terminals() async throws {
        let sockets = SnapshotSockets(script: [.opened, .frame(.output("\u{1B}[1;32mopencode\u{1B}[0m:~/project $ ")), .frame(.control(cursor: 32))])
        let live = store(terminals: [pty("pty_1", "Terminal 1")], sockets: sockets)
        let list = live.terminals(directory: "/w"); list.refresh()
        await wait { !list.terminals.isEmpty }
        await capture(screen(list, "pty_1"), name: "terminal-empty") { list.session("pty_1").link.phase == .live }
        let writer = try PersistenceWriter()
        let screen = "\u{1B}[0m$ make test\r\n\u{1B}[0;31mFAIL\u{1B}[0m PairingTests.swift:42\r\nmake: *** [test] Error 1\r\n$ exit 1"
        try await writer.saveTerminal(TerminalResume(serverID: "s", ptyID: "pty_2", directory: "/w", cursor: 120, cols: 40, rows: 20, screen: screen, updated: Date()))
        let ended = store(terminals: [pty("pty_2", "Build", status: "exited", exit: 1)], cache: CacheStore(writer: writer))
        let exited = ended.terminals(directory: "/w"); exited.refresh()
        await wait { !exited.terminals.isEmpty }
        await capture(self.screen(exited, "pty_2"), name: "terminal-exited") { exited.session("pty_2").gap != nil }
        withExtendedLifetime((live, ended)) {}
    }
    @Test func keyBar() async throws {
        let owner = store(terminals: [])
        let session = owner.terminals(directory: "/w").session("pty_1")
        await capture(KeyBarView(session: session).frame(maxHeight: .infinity, alignment: .bottom), name: "key-bar", height: 120)
        session.toggle(.control)
        await capture(KeyBarView(session: session).frame(maxHeight: .infinity, alignment: .bottom), name: "key-bar-ctrl", height: 120)
        withExtendedLifetime(owner) {}
    }
    @Test func runACommand() async throws {
        let fixture = ShellFixture()
        let owner = store(terminals: [], shell: fixture)
        let model = owner.shellRuns(directory: "/Users/Shared/opencode-ios")
        await capture(RunCommandSheet(model: model), name: "run-empty")
        model.run("swift test")
        await wait { model.isRunning }
        await capture(RunCommandSheet(model: model), name: "run-running") { !model.running.isEmpty }
        fixture.exited.withLock { $0 = true }
        model.handle(type: "shell.exited", payload: .object(["id": .string("sh_1"), "status": .string("exited"), "exit": .integer(0)]))
        await capture(RunCommandSheet(model: model), name: "run-finished")
        withExtendedLifetime(owner) {}
    }

    private func screen(_ list: TerminalListModel, _ id: String) -> some View {
        TerminalScreen(list: list, session: list.session(id), showsHeader: true, autoFocus: false, back: {}, runCommand: {})
    }
    private func wait(_ predicate: () -> Bool) async {
        for _ in 0..<500 { if predicate() { return }; try? await Task.sleep(for: .milliseconds(10)) }
    }
    private func capture<V: View>(_ view: V, name: String, height: Double = 852, until ready: () -> Bool = { true }) async {
        for (dark, accessibility, width) in [(false, false, 393.0), (true, false, 393), (false, true, 393), (false, false, 768), (true, false, 768)] {
            let size = CGSize(width: width, height: height)
            let controller = UIHostingController(rootView: view
                .environment(\.dynamicTypeSize, accessibility ? .accessibility5 : .large)
                .environment(\.colorScheme, dark ? .dark : .light).transaction { $0.animation = nil }.ocTheme()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(OCColor.background))
            controller.overrideUserInterfaceStyle = dark ? .dark : .light
            controller.traitOverrides.preferredContentSizeCategory = accessibility ? .accessibilityExtraExtraExtraLarge : .large
            controller.view.frame = CGRect(origin: .zero, size: size)
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
                Issue.record("Snapshots need a connected window scene"); return
            }
            let window = UIWindow(windowScene: scene)
            window.overrideUserInterfaceStyle = dark ? .dark : .light
            window.frame = CGRect(origin: .zero, size: size); window.rootViewController = controller; window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            await wait(ready)
            // A navigation title fades in after the first layout.
            try? await Task.sleep(for: .milliseconds(800))
            // The window as it is on screen: the view-controller strategy would move the view to a window of its own,
            // laying out the navigation bar and the terminal's scroll view again.
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let label = "\(name)-\(dark ? "dark" : "light")-\(Int(width))-\(accessibility ? "accessibility5" : "default")"
            if ProcessInfo.processInfo.environment["OC_RECORD_SNAPSHOTS"] == "1" {
                if let result = verifySnapshot(of: image, as: .image, named: label, record: true, testName: "capture"),
                   !result.contains("Record mode is on") { Issue.record(Comment(rawValue: result)) }
            } else {
                // Run a command's sheet has a system glass Done button and a spinner that render a little differently
                // each time (about 0.2% of the image, all inside them).
                assertSnapshot(of: image, as: .image(precision: name.hasPrefix("run-") ? 0.995 : 1), named: label, testName: "capture")
            }
            window.isHidden = true
        }
    }
    private func store(terminals: [JSONValue], cache: CacheStore? = nil, sockets: SnapshotSockets = SnapshotSockets(script: []), shell: ShellFixture? = nil) -> ReadStore {
        let store = ReadStore(serverID: "s", cache: cache, client: {
            APIClient(baseURL: URL(string: "http://127.0.0.1:4096")!, transport: SnapshotTransport(terminals: terminals, shell: shell))
        })
        store.webSockets = sockets
        return store
    }
}

private func pty(_ id: String, _ title: String, command: String = "/bin/bash", status: String = "running", exit: Int? = nil) -> JSONValue {
    var raw: JSONValue = .object(["id": .string(id), "title": .string(title), "command": .string(command), "args": .array([.string("-l")]),
                                  "cwd": .string("/Users/Shared/opencode-ios"), "status": .string(status), "pid": .integer(4242)])
    if let exit { raw.set("exitCode", .integer(Int64(exit))) }
    return raw
}

/// The one command Run a command starts: running once posted, until the test says it exited.
private nonisolated final class ShellFixture: Sendable {
    let started = Mutex(false), exited = Mutex(false)
    var running: Bool { started.withLock { $0 } && !exited.withLock { $0 } }
}

/// Answers the routes the terminal screens read, with fixed content.
private struct SnapshotTransport: HTTPTransport {
    let terminals: [JSONValue]
    let shell: ShellFixture?
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let path = request.url?.path ?? "", url = try #require(request.url)
        let located: (JSONValue) -> JSONValue = { .object(["location": .object(["directory": .string("/w")]), "data": $0]) }
        let running: JSONValue = .object(["id": .string("sh_1"), "status": .string("running"), "command": .string("swift test"), "cwd": .string("/w"),
                                          "shell": .string("/bin/bash"), "file": .string("/f"), "metadata": .object([:]), "time": .object(["started": .integer(1)])])
        var exited = running
        exited.set("status", .string("exited")); exited.set("exit", .integer(0))
        if path == "/api/shell", request.httpMethod == "POST" { shell?.started.withLock { $0 = true } }
        let body: JSONValue = switch path {
        case "/api/pty": located(.array(terminals))
        case "/api/config/shell": .array([.object(["path": .string("/bin/bash"), "name": .string("bash"), "acceptable": .bool(true)]),
                                          .object(["path": .string("/bin/zsh"), "name": .string("zsh"), "acceptable": .bool(true)])])
        case "/api/shell" where request.httpMethod == "POST": located(running)
        case "/api/shell": located(.array(shell?.running == true ? [running] : []))
        case "/api/shell/sh_1": located(shell?.running == false ? exited : running)
        case "/api/shell/sh_1/output":
            // The output once, from the start; a later page from its end is empty.
            located(.object(["output": .string(url.query?.contains("cursor=96") == true ? "" : "Building for debugging...\n\u{1B}[32m✔\u{1B}[0m Test run with 412 tests passed after 3.2 seconds.\n"),
                             "cursor": .integer(96), "size": .integer(96), "truncated": .bool(false)]))
        default: located(terminals.first ?? .object([:]))
        }
        return .init(data: try JSONEncoder().encode(body), response: try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])))
    }
    func stream(_ request: URLRequest) -> AsyncThrowingStream<TransportChunk, any Error> { .init { $0.finish() } }
}

/// A socket that plays a fixed script and stays open.
private final class SnapshotSockets: WebSocketConnecting {
    let script: [PTYEvent]
    init(script: [PTYEvent]) { self.script = script }
    func open(_ request: URLRequest) -> any WebSocketConnection { SnapshotSocket(script: script) }
}
private final class SnapshotSocket: WebSocketConnection {
    let events: AsyncStream<PTYEvent>
    private let continuation: AsyncStream<PTYEvent>.Continuation
    init(script: [PTYEvent]) {
        (events, continuation) = AsyncStream.makeStream()
        for event in script { continuation.yield(event) }
    }
    func send(_ text: String) async throws {}
    func close() { continuation.finish() }
}
#endif
