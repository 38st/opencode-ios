import Foundation
import Testing
@testable import OCSync

#if DEBUG
@MainActor struct UITestStorageTests {
    @Test func resetRequiresValidNamespaceAndExplicitArgument() async throws {
        #expect(UITestStorage(environment: [:], arguments: ["--ui-testing-reset"]) == nil)
        #expect(UITestStorage(environment: ["OPENCODE_UI_TEST_ID": "ui-../../real"], arguments: ["--ui-testing-reset"]) == nil)
        let storage = try #require(UITestStorage(environment: ["OPENCODE_UI_TEST_ID": "ui-reset"], arguments: []))
        var reset = false
        try await storage.reset(in: .temporaryDirectory, defaults: .standard) { reset = true }
        #expect(!reset)
    }

    @Test func resetRemovesOnlyThisTestsDataAndCredentials() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let storage = try #require(UITestStorage(environment: ["OPENCODE_UI_TEST_ID": "ui-reset-" + UUID().uuidString], arguments: ["--ui-testing-reset"]))
        let suite = storage.service
        let defaults = try #require(UserDefaults(suiteName: suite))
        let other = try #require(UserDefaults(suiteName: suite + ".other"))
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        defer { other.removePersistentDomain(forName: suite + ".other") }
        let record = storage.recordsURL(in: directory)
        try FileManager.default.createDirectory(at: record.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("saved server".utf8).write(to: record)
        let unrelated = directory.appending(path: "UITests/ui-other.json")
        try Data("other server".utf8).write(to: unrelated)
        defaults.set(true, forKey: storage.explanationKey)
        defaults.set("everything", forKey: "timelineDetail")
        other.set(true, forKey: "localNetworkExplained")
        var resets = 0
        try await storage.reset(in: directory, defaults: defaults) { resets += 1 }
        #expect(resets == 1)
        #expect(!FileManager.default.fileExists(atPath: record.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        #expect(!defaults.bool(forKey: storage.explanationKey))
        #expect(defaults.string(forKey: "timelineDetail") == nil)
        #expect(other.bool(forKey: "localNetworkExplained"))
        // Reset is idempotent, including a relaunch with the same namespace.
        try await storage.reset(in: directory, defaults: defaults) { resets += 1 }
        #expect(resets == 2)
    }
}
#endif
