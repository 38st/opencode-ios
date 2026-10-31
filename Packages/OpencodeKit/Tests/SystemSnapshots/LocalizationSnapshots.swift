#if os(iOS)
import Foundation
import SwiftUI
import UIKit
import Testing
import SnapshotTesting
import OCDesign
import OCFoundation
import OCModels
import FeatureApprovals
import FeatureSettings

/// Layout checks a translation would otherwise find late: every looked-up string at double length, and a right-to-left
/// layout in which code, paths and diffs stay left-to-right. Also the Acknowledgements screen in light, dark and the
/// largest text size.
@MainActor @Suite(.serialized) struct LocalizationSnapshots {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func acknowledgements() {
        for variant in [Variant.light, .dark, .largestText] { capture(NavigationStack { AcknowledgementsView() }, name: "acknowledgements", variant: variant) }
    }

    @Test func doubleLengthStrings() throws {
        for (name, screen) in try screens() { capture(screen, name: name, variant: .doubleLength) }
    }

    @Test func rightToLeft() throws {
        for (name, screen) in try screens() { capture(screen, name: name, variant: .rightToLeft) }
    }

    private func screens() throws -> [(String, AnyView)] {
        var request = try JSONDecoder().decode(PermissionRequest.self, from: Data(contentsOf: Self.root.appending(path: "Fixtures/source/approvals/permission.json")))
        request["action"] = .string("shell"); request["resources"] = .array([.string("git reset --hard HEAD~1")]); request["metadata"] = nil
        let form = try JSONDecoder().decode(FormInfo.self, from: Data(contentsOf: Self.root.appending(path: "Fixtures/source/approvals/form.json")))
        return [
            ("acknowledgements", AnyView(NavigationStack { AcknowledgementsView() })),
            ("permission", AnyView(ScrollView { PermissionContent(request: request, directory: "/workspace/web-app", otherRequests: 2, state: .constant(.review), note: .constant(""), reply: { _, _ in }).padding(OCSpacing.lg) })),
            ("question", AnyView(ScrollView { QuestionContent(form: form, state: .constant(.editing), answers: .constant(["theme": .string("Sepia")]), reason: .constant(""), submit: {}, dismiss: {}).padding(OCSpacing.lg) })),
        ]
    }

    enum Variant: String { case light, dark, largestText = "accessibility5", doubleLength = "double-length", rightToLeft = "right-to-left" }

    /// Renders synchronously: the double-length mode is process-wide, so no other test may render while it is on.
    private func capture(_ view: some View, name: String, variant: Variant) {
        let size = CGSize(width: 393, height: 852)
        let dark = variant == .dark
        let rightToLeft = variant == .rightToLeft
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            Issue.record("Snapshots need a connected window scene"); return
        }
        if variant == .doubleLength { OCLocalization.mode = .doubleLength }
        defer { OCLocalization.mode = .standard }
        let controller = UIHostingController(rootView: view
            .environment(\.dynamicTypeSize, variant == .largestText ? .accessibility5 : .large)
            .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight)
            .environment(\.colorScheme, dark ? .dark : .light).transaction { $0.animation = nil }.ocTheme()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(OCColor.backgroundDeep))
        controller.overrideUserInterfaceStyle = dark ? .dark : .light
        controller.traitOverrides.preferredContentSizeCategory = variant == .largestText ? .accessibilityExtraExtraExtraLarge : .large
        controller.traitOverrides.layoutDirection = rightToLeft ? .rightToLeft : .leftToRight
        controller.view.semanticContentAttribute = rightToLeft ? .forceRightToLeft : .unspecified
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        window.frame = CGRect(origin: .zero, size: size); window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded(); controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let label = "\(name)-\(variant.rawValue)"
        if ProcessInfo.processInfo.environment["OC_RECORD_SNAPSHOTS"] == "1" {
            if let result = verifySnapshot(of: image, as: .image, named: label, record: true, testName: "localization"),
               !result.contains("Record mode is on") { Issue.record(Comment(rawValue: result)) }
        } else {
            assertSnapshot(of: image, as: .image, named: label, testName: "localization")
        }
    }
}
#endif
