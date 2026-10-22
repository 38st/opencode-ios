/// Semantic Versioning 2.0 precedence. Build metadata is retained for display,
/// but ignored by equality, hashing and comparison.
public struct SemVer: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: [String]
    public let buildMetadata: [String]

    public init?(_ text: String) {
        let buildParts = text.split(separator: "+", omittingEmptySubsequences: false)
        guard buildParts.count <= 2 else { return nil }
        let versionParts = buildParts[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = versionParts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard core.count == 3 else { return nil }
        let numbers = core.compactMap { part -> Int? in
            guard Self.isNumeric(String(part)), part.count == 1 || part.first != "0" else { return nil }
            return Int(part)
        }
        guard numbers.count == 3 else { return nil }
        let prerelease = versionParts.count == 2 ? Self.identifiers(String(versionParts[1])) : []
        let metadata = buildParts.count == 2 ? Self.identifiers(String(buildParts[1])) : []
        guard let prerelease, let metadata,
              prerelease.allSatisfy({ !Self.isNumeric($0) || $0.count == 1 || $0.first != "0" })
        else { return nil }
        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]
        self.prerelease = prerelease
        buildMetadata = metadata
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
            + (prerelease.isEmpty ? "" : "-" + prerelease.joined(separator: "."))
            + (buildMetadata.isEmpty ? "" : "+" + buildMetadata.joined(separator: "."))
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch && lhs.prerelease == rhs.prerelease
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(major)
        hasher.combine(minor)
        hasher.combine(patch)
        hasher.combine(prerelease)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        for (a, b) in zip(lhs.prerelease, rhs.prerelease) where a != b {
            let aNumeric = isNumeric(a), bNumeric = isNumeric(b)
            if aNumeric != bNumeric { return aNumeric }
            if aNumeric, a.count != b.count { return a.count < b.count }
            return a < b
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let version = Self(try container.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid semantic version")
        }
        self = version
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    private static func isNumeric(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func identifiers(_ value: String) -> [String]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.allSatisfy({ part in
            !part.isEmpty && part.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
            }
        }) else { return nil }
        return parts
    }
}
