#if os(iOS)
import Foundation
import SwiftUI
import UIKit
import Testing
import SnapshotTesting
import OCFoundation
import OCModels
import OCDesign
import OCSecurity
import FeatureApprovals

@MainActor @Suite(.serialized) struct ApprovalSnapshots {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    @Test func permissionStates() async throws {
        let request = try JSONDecoder().decode(PermissionRequest.self, from: Data(contentsOf: Self.root.appending(path: "Fixtures/source/m3a/permission.json")))
        for state in PermissionSheetState.allCases {
            await capture(PermissionContent(request: request, directory: "/workspace/web-app", otherRequests: 2, state: .constant(state),
                                      note: .constant(state == .reject ? "Keep the existing timeout and add a regression test." : ""), reply: { _, _ in }), name: "permission-" + state.rawValue)
        }
        for count in [0, 1] {
            await capture(PermissionContent(request: request, directory: "/workspace/web-app", otherRequests: count, state: .constant(.reject),
                                            note: .constant(""), reply: { _, _ in }), name: "permission-reject-\(count)-others")
        }
        await capture(PermissionContent(request: request, directory: "/workspace/web-app", authentication: .touchID, state: .constant(.authenticating),
                                        note: .constant(""), reply: { _, _ in }), name: "permission-authenticating-touch-id")
        await capture(PermissionContent(request: request, directory: "/workspace/web-app", authentication: .unavailable, state: .constant(.review),
                                        note: .constant(""), reply: { _, _ in }), name: "permission-no-passcode")
        var high = request; high["action"] = .string("shell"); high["resources"] = .array([.string("git reset --hard HEAD~1")]); high["metadata"] = nil
        await capture(PermissionContent(request: high, directory: "/workspace/web-app", state: .constant(.review), note: .constant(""), reply: { _, _ in }), name: "permission-high-risk")
    }
    @Test func questionStatesAndEveryFieldType() async throws {
        let form = try JSONDecoder().decode(FormInfo.self, from: Data(contentsOf: Self.root.appending(path: "Fixtures/source/m3a/form.json")))
        let answers: [String: JSONValue] = ["theme": .string("Sepia"), "checks": .array([.string("unit")]), "scale": .double(1.5), "count": .integer(2), "publish": .bool(true), "label": .string("Review build"), "external": .bool(true)]
        for state in FormSheetState.allCases {
            await capture(QuestionContent(form: form, state: .constant(state), answers: .constant(state == .invalid ? [:] : answers), reason: .constant("Use the existing preview."), submit: {}, dismiss: {}), name: "question-" + state.rawValue)
        }
        var unknown = form; unknown["fields"] = .array([.object(["type": .string("future"), "key": .string("unknown")])])
        await capture(FormRenderer(form: unknown, answers: .constant([:]), showErrors: true), name: "question-unsupported")
        await capture(FormRenderer(form: form, answers: .constant(["publish": .bool(false)])), name: "question-conditional-hidden")
    }
    @Test func latestPill() async {
        await capture(VStack(spacing: OCSpacing.lg) { OCJumpToLatest(count: 0) {}; OCJumpToLatest(count: 3) {} }, name: "jump-to-latest")
    }
    private func capture(_ view: some View, name: String) async {
        if let filter = ProcessInfo.processInfo.environment["OC_SNAPSHOT_FILTER"],
           !filter.split(separator: ",").contains(where: { name.hasPrefix($0) }) { return }
        for dark in [false, true] {
            for width: CGFloat in [393, 820] {
                let content = view.padding(OCSpacing.lg).environment(\.dynamicTypeSize, .accessibility5)
                    .environment(\.colorScheme, dark ? .dark : .light).transaction { $0.animation = nil }.ocTheme()
                    .fixedSize(horizontal: false, vertical: true)
                let sizing = UIHostingController(rootView: content)
                sizing.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
                sizing.traitOverrides.horizontalSizeClass = width > 600 ? .regular : .compact
                let height = max(200, ceil(sizing.sizeThatFits(in: CGSize(width: width, height: 20_000)).height))
                let controller = UIHostingController(rootView: content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(OCColor.background))
                controller.overrideUserInterfaceStyle = dark ? .dark : .light
                // Async diff preparation starts only after the view appears.
                var window: UIWindow?
                if name.hasPrefix("permission-") && name != "permission-high-risk" {
                    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
                        Issue.record("Snapshots need a connected window scene"); return
                    }
                    let host = UIWindow(windowScene: scene)
                    host.frame = CGRect(x: 0, y: 0, width: width, height: height)
                    controller.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
                    controller.traitOverrides.horizontalSizeClass = width > 600 ? .regular : .compact
                    host.rootViewController = controller; host.makeKeyAndVisible()
                    controller.view.layoutIfNeeded(); window = host
                    try? await Task.sleep(for: .milliseconds(350))
                }
                defer { window?.isHidden = true }
                assertSnapshot(of: controller, as: .wait(for: 0.2, on: .image(size: CGSize(width: width, height: height), traits: UITraitCollection { traits in
                    traits.userInterfaceStyle = dark ? .dark : .light
                    traits.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
                    traits.horizontalSizeClass = width > 600 ? .regular : .compact
                })), named: name + "-" + (dark ? "dark" : "light") + "-\(Int(width))", record: ProcessInfo.processInfo.environment["OC_RECORD_SNAPSHOTS"] == "1")
            }
        }
    }
}
#endif
