// swift-tools-version: 6.4
import PackageDescription

let coreSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(nil),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
]
let uiSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
]
let features = [
    "FeatureServers", "FeatureInbox", "FeatureTranscript", "FeatureComposer",
    "FeatureApprovals", "FeatureReview", "FeatureFiles", "FeatureTerminal", "FeatureSettings",
]
let modules = [
    "OCFoundation", "OCModels", "OCNetworking", "OCSecurity", "OCPersistence", "OCShared",
    "OCPushCore", "OCSync", "OCRender", "OCDesign", "OCActivity", "OCIntents", "OCAppIntents",
] + features

let grammarNames = ["swift", "typescript", "tsx", "javascript", "python", "json", "bash", "go", "rust", "markdown", "yaml", "html", "css"]
let grammarTargets: [Target] = grammarNames.map { name in
    .target(name: "Grammar_" + name, path: "Grammars/" + name,
            sources: ["parser.c"] + (["json", "go"].contains(name) ? [] : ["scanner.c"]),
            publicHeadersPath: "include", cSettings: [.headerSearchPath(".")])
}

let package = Package(
    name: "OpencodeKit",
    platforms: [.iOS("26.4"), .macOS("27.0")],
    products: modules.map { .library(name: $0, targets: [$0]) },
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown", exact: "0.7.3"),
        .package(url: "https://github.com/gonzalezreal/textual", exact: "0.5.0"),
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", exact: "0.10.0"),
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.8.0"),
        .package(url: "https://github.com/pointfreeco/swift-clocks", exact: "1.1.1"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.18.7"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.99.1"),
    ],
    targets: [
        .target(name: "OCFoundation", swiftSettings: coreSettings),
        .target(name: "OCModels", dependencies: ["OCFoundation"], swiftSettings: coreSettings),
        .target(name: "OCNetworking", dependencies: ["OCModels", "OCFoundation"], swiftSettings: coreSettings),
        .target(name: "OCSecurity", dependencies: ["OCFoundation", "OCModels"], swiftSettings: coreSettings),
        .target(name: "OCPersistence", dependencies: ["OCModels", "OCFoundation", .product(name: "GRDB", package: "GRDB.swift")], swiftSettings: coreSettings),
        .target(name: "OCShared", dependencies: ["OCFoundation"], swiftSettings: coreSettings),
        // The contract files are byte-identical copies of server/contracts (Tools/sync-push-contracts.mjs).
        .target(name: "OCPushCore", dependencies: ["OCFoundation", "OCModels", "OCSecurity", "OCShared"], resources: [.copy("Resources/Contracts")], swiftSettings: coreSettings),
        .target(
            name: "OCSync",
            dependencies: ["OCModels", "OCFoundation", "OCNetworking", "OCPersistence", "OCSecurity", "OCShared", "OCPushCore", "OCActivity", "OCIntents", "OCAppIntents"],
            swiftSettings: uiSettings
        ),
        .target(name: "OCRender", dependencies: ["OCModels", "OCFoundation", .product(name: "Markdown", package: "swift-markdown"), .product(name: "SwiftTreeSitter", package: "swift-tree-sitter")] + grammarNames.map { .byName(name: "Grammar_" + $0) }, swiftSettings: coreSettings),
        .target(name: "OCDesign", dependencies: ["OCRender", .product(name: "Textual", package: "textual")], resources: [.process("Resources")], swiftSettings: uiSettings),
        .target(name: "OCActivity", dependencies: ["OCShared"], swiftSettings: coreSettings),
        // The app process injects the intents' implementations (OCSync); the Widgets extension links this target
        // without networking or sync, so its intents there only read the App Group snapshot.
        .target(name: "OCIntents", dependencies: ["OCShared"], swiftSettings: coreSettings),
        .target(name: "OCAppIntents", dependencies: ["OCIntents", "OCShared"], swiftSettings: coreSettings),
    ] + grammarTargets + features.map {
        .target(name: $0, dependencies: ["OCModels", "OCFoundation", "OCSync", "OCDesign", "OCRender"] + ($0 == "FeatureServers" ? [.byName(name: "FeatureInbox"), .byName(name: "FeatureTranscript"), .byName(name: "FeatureComposer"), .byName(name: "FeatureReview"), .byName(name: "OCShared"), .byName(name: "FeatureSettings")] : []) + ($0 == "FeatureTranscript" ? [.byName(name: "FeatureApprovals"), .byName(name: "FeatureComposer"), .byName(name: "FeatureReview")] : []) + (["FeatureReview", "FeatureApprovals"].contains($0) ? [.byName(name: "FeatureFiles")] : []) + ($0 == "FeatureApprovals" ? [.byName(name: "OCPushCore"), .byName(name: "OCSecurity")] : []) + (["FeatureSettings", "FeatureInbox"].contains($0) ? [.byName(name: "OCShared")] : []) + (["FeatureReview", "FeatureTranscript", "FeatureServers"].contains($0) ? [.byName(name: "FeatureTerminal")] : []) + ($0 == "FeatureTerminal" ? [.product(name: "SwiftTerm", package: "SwiftTerm")] : []), swiftSettings: uiSettings)
    } + [
        .testTarget(name: "OCNetworkingTests", dependencies: ["OCNetworking", "OCSecurity", .product(name: "Clocks", package: "swift-clocks")], swiftSettings: coreSettings),
        .testTarget(name: "OCNetworkingLiveTests", dependencies: ["OCNetworking", "OCSecurity", "OCSync", "OCModels", "OCFoundation", "OCPersistence"], swiftSettings: coreSettings),
        .testTarget(name: "OCPushCoreTests", dependencies: ["OCPushCore", "OCFoundation", "OCModels", "OCShared", "OCSecurity"], swiftSettings: coreSettings),
        .testTarget(name: "OCPersistenceTests", dependencies: ["OCPersistence", "OCModels", "OCFoundation", .product(name: "Clocks", package: "swift-clocks")], swiftSettings: coreSettings),
        .testTarget(name: "OCSyncTests", dependencies: ["OCSync", "OCActivity", "OCPushCore", "OCRender", "OCShared", "OCNetworking", "OCSecurity", "OCModels", "OCIntents", .product(name: "Clocks", package: "swift-clocks")], swiftSettings: coreSettings),
        .testTarget(name: "OCIntentsTests", dependencies: ["OCIntents", "OCAppIntents", "OCShared"], swiftSettings: coreSettings),
        .testTarget(name: "FeatureServersTests", dependencies: ["OCFoundation", "FeatureServers", "OCSync", "OCModels", "OCDesign", "OCNetworking", "OCSecurity", .product(name: "SnapshotTesting", package: "swift-snapshot-testing")], exclude: ["__Snapshots__"], swiftSettings: uiSettings),
    ] + ["OCFoundation", "OCModels", "OCSecurity", "OCRender", "OCShared", "OCActivity"].map {
        .testTarget(name: "\($0)Tests", dependencies: [.byName(name: $0)], swiftSettings: coreSettings)
    }
)
