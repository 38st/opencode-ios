#if os(iOS)
import Foundation
import SwiftUI
import UIKit
import Testing
import SnapshotTesting
import OCModels
import OCDesign
import FeatureServers

@MainActor @Suite(.serialized) struct ServerRowTests {
    @Test func allStatesAtLargestDynamicType() throws {
        let endpoint = EndpointRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                      url: URL(string: "http://192.168.1.10:4096")!, kind: .lan)
        let now = ContinuousClock.now
        let states: [(String, ConnectionState)] = [
            ("connected", .connected(endpoint.id, since: now)), ("idle", .idle), ("resolving", .resolving),
            ("connecting", .connecting(attempt: 1)),
            ("retrying", .waiting(attempt: 3, retryAt: now.advanced(by: .seconds(12)), failure: .dnsFailure)),
            ("repair", .unauthorized), ("update", .incompatible(.v1("1.19.3"))),
            ("old-v2", .incompatible(.unsupportedV2(.init(version: "2.0.9")))),
            ("not-opencode", .incompatible(.notOpencode)), ("starting", .serviceStarting(.seconds(5))),
            ("paused", .suspended),
        ]
        for (name, state) in states {
            for dark in [false, true] {
                for width in [402, 768] {
                    let view = ServerRow(name: "Studio Mac", state: state, endpoints: [endpoint], expiresSoon: name == "repair", now: now)
                        .padding(20).frame(width: CGFloat(width), alignment: .leading)
                        .environment(\.dynamicTypeSize, .accessibility5)
                        .environment(\.colorScheme, dark ? .dark : .light)
                        .background(OCColor.background)
                    let controller = UIHostingController(rootView: view)
                    let height = controller.sizeThatFits(in: CGSize(width: CGFloat(width), height: 3000)).height
                    assertSnapshot(of: controller, as: .image(size: CGSize(width: CGFloat(width), height: height),
                        traits: UITraitCollection(userInterfaceStyle: dark ? .dark : .light)),
                        named: "\(name)-\(dark ? "dark" : "light")-\(width)",
                        record: ProcessInfo.processInfo.environment["OC_RECORD_SNAPSHOTS"] == "1")
                }
            }
        }
    }
}
#endif
