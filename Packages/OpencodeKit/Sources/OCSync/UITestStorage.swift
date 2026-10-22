#if DEBUG
import Foundation

/// A test can reset only its own namespace, never the user's records or Keychain service.
@MainActor struct UITestStorage {
    let id: String
    let resetsOnLaunch: Bool
    var service: String { "app.opencode.uitests.\(id)" }
    var explanationKey: String { "UITests.\(id).localNetworkExplained" }

    init?(environment: [String: String], arguments: [String]) {
        guard let id = environment["OPENCODE_UI_TEST_ID"], id.hasPrefix("ui-"),
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        self.id = id
        resetsOnLaunch = arguments.contains("--ui-testing-reset")
    }

    func recordsURL(in directory: URL) -> URL { directory.appending(path: "UITests/\(id).json") }

    func reset(in directory: URL, defaults: UserDefaults, resetKeychain: () async throws -> Void) async throws {
        guard resetsOnLaunch else { return }
        try await resetKeychain()
        let records = recordsURL(in: directory)
        if FileManager.default.fileExists(atPath: records.path) { try FileManager.default.removeItem(at: records) }
        defaults.removePersistentDomain(forName: service)
    }
}
#endif
