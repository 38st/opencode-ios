import Foundation
import XCTest
import UIKit

/// Launch timing on the simulator: XCTest's launch metric, and the time from a cold launch until Home lists the
/// sessions it cached, with the server cut off so only the cache can supply them. Report-only here; the 300 ms budget for the cached inbox is an iPhone 13 trace.
nonisolated final class PerformanceSmokeTests: SmokeTestCase {
    @MainActor func testColdLaunchToCachedInbox() async throws {
        continueAfterFailure = false
        executionTimeAllowance = 300
        try launchFreshApp(suffix: "-launch")
        app.buttons["addFirstServer"].tap()
        // Through the fault proxy, so the measured launches can be cut off from the server and show only the cache.
        let env = ProcessInfo.processInfo.environment
        try await pairSandbox(name: "Launch sandbox", url: try XCTUnwrap(env["OPENCODE_UI_PROXY_URL"]))
        app.buttons["closeSettings"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "homeSession-"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 20), "Home lists the server's sessions before they are cached")
        // Give the cache writer its moment, then measure cold launches that read it.
        try await Task.sleep(for: .seconds(2))
        app.terminate()
        try await fault(["blocked": true])
        addTeardownBlock { @MainActor [self] in _ = try? await fault(["blocked": false]) }
        var inbox: [Double] = []
        let options = XCTMeasureOptions(); options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            let start = Date()
            app.launch()
            XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "Home shows the cached sessions after a cold launch")
            inbox.append(Date().timeIntervalSince(start) * 1_000)
            app.terminate()
        }
        let sorted = inbox.sorted()
        let values = ["cold_launch_to_cached_inbox_median_ms": sorted.isEmpty ? 0 : sorted[sorted.count / 2], "cold_launch_to_cached_inbox_max_ms": sorted.last ?? 0]
        let attachment = XCTAttachment(data: try JSONEncoder().encode(values), uniformTypeIdentifier: "public.json")
        attachment.name = "finding-launch.json"; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func fault(_ body: [String: Any]) async throws {
        let env = ProcessInfo.processInfo.environment
        var request = URLRequest(url: try XCTUnwrap(URL(string: try XCTUnwrap(env["OPENCODE_UI_PROXY_URL"]) + "/__fault")))
        request.httpMethod = "POST"; request.setValue(try XCTUnwrap(env["OPENCODE_UI_PROXY_TOKEN"]), forHTTPHeaderField: "x-fault-token")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }
}
