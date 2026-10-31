import Foundation

/// The third-party components the app ships, read from `Resources/Licenses/acknowledgements.json`. The same file
/// generates the table in THIRD_PARTY_NOTICES.md (`Tools/notices/generate.mjs`), so the two cannot drift.
nonisolated public struct Acknowledgements: Decodable, Sendable {
    public struct Section: Decodable, Sendable, Identifiable {
        public let id: String
        public let items: [Item]
    }

    public struct Item: Decodable, Sendable, Identifiable, Hashable {
        public let name: String
        public let version: String
        public let license: String
        public let copyright: String
        public let url: URL
        public let licenseFile: String
        public var id: String { name }
    }

    public let sections: [Section]

    public static func bundled() -> Acknowledgements {
        guard let url = Bundle.module.url(forResource: "acknowledgements", withExtension: "json", subdirectory: "Licenses")
                ?? Bundle.module.url(forResource: "acknowledgements", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(Acknowledgements.self, from: data) else { return Acknowledgements(sections: []) }
        return value
    }

    public static func licenseText(for item: Item) -> String? {
        let name = (item.licenseFile as NSString).deletingPathExtension
        let ext = (item.licenseFile as NSString).pathExtension
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Licenses")
                ?? Bundle.module.url(forResource: name, withExtension: ext) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    init(sections: [Section]) { self.sections = sections }
}
