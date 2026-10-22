import Foundation

public enum OpencodeID {
    /// Prefixes declared by the V2 schemas; only sessions use descending time.
    public enum Kind: String, CaseIterable, Sendable {
        case session = "ses"
        case message = "msg"
        case permission = "per"
        case savedPermission = "psv"
        case form = "frm"
        case event = "evt"
        case workspace = "wrk"
        case pty = "pty"
        case integration = "con"
        case credential = "cred"
        case shell = "sh"
        case toolOutput = "tool"

        public var isDescending: Bool { self == .session }
    }

    public struct Components: Sendable, Hashable {
        public let kind: Kind
        /// The wire value, before undoing the descending complement.
        public let encodedTime: UInt64
        public let random: String

        public var timeAndCounter: UInt64 {
            kind.isDescending ? (~encodedTime & OpencodeID.timeMask) : encodedTime
        }
        public var counter: UInt16 { UInt16(timeAndCounter & 0xfff) }
        public var truncatedMilliseconds: UInt64 { timeAndCounter >> 12 }

        /// The wire contains only 36 timestamp bits (~795 days). Recover the era
        /// nearest a trusted server time, never pretend it contains a full epoch.
        public func timestamp(nearest reference: Date) -> Date {
            let period = Double(UInt64(1) << 36)
            let milliseconds = Double(truncatedMilliseconds)
            let referenceMS = reference.timeIntervalSince1970 * 1_000
            let era = ((referenceMS - milliseconds) / period).rounded()
            return Date(timeIntervalSince1970: (milliseconds + era * period) / 1_000)
        }
    }

    static let timeMask: UInt64 = 0xffff_ffff_ffff
    static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8)

    public static func components(of id: String) -> Components? {
        let parts = id.split(separator: "_", omittingEmptySubsequences: false)
        guard parts.count == 2, let kind = Kind(rawValue: String(parts[0])) else { return nil }
        let bytes = Array(parts[1].utf8)
        guard bytes.count == 26,
              bytes.prefix(12).allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              bytes.suffix(14).allSatisfy({ alphabet.contains($0) }),
              let time = UInt64(String(decoding: bytes.prefix(12), as: UTF8.self), radix: 16)
        else { return nil }
        return Components(kind: kind, encodedTime: time, random: String(decoding: bytes.suffix(14), as: UTF8.self))
    }

    static func encode(kind: Kind, time: UInt64, bytes: [UInt8]) -> String {
        let hex = String(time & timeMask, radix: 16)
        let suffix = String(decoding: bytes.map { alphabet[Int($0) % 62] }, as: UTF8.self)
        return kind.rawValue + "_" + String(repeating: "0", count: 12 - hex.count) + hex + suffix
    }
}

/// One minter per server. The actor owns the shared counter and session floors.
public actor IDMinter {
    public enum MintError: Error, Sendable, Equatable {
        case invalidTimestamp
        case invalidRandomBytes
        case invalidMessageID
        case orderedSpaceExhausted
    }

    private let now: @Sendable () -> Date
    private let randomBytes: @Sendable () -> [UInt8]
    private var sequence = IdentifierSequence()
    private var newestMessageTimes: [String: UInt64] = [:]

    public init(
        clock: ServerClock,
        randomBytes: @escaping @Sendable () -> [UInt8] = { (0..<14).map { _ in UInt8.random(in: .min ... .max) } }
    ) {
        now = { clock.now() }
        self.randomBytes = randomBytes
    }

    public func mintSession() throws -> String { try mint(.session) }

    /// Records observed IDs as well as locally minted ones, so a stale snapshot
    /// cannot lower the floor. Restore the newest persisted ID after relaunch.
    public func mintMessage(sessionID: String, newestKnownMessageID: String? = nil) throws -> String {
        var floor = newestMessageTimes[sessionID]
        if let id = newestKnownMessageID {
            guard let parsed = OpencodeID.components(of: id), parsed.kind == .message else {
                throw MintError.invalidMessageID
            }
            floor = max(floor ?? 0, parsed.encodedTime)
        }
        let parts = try nextParts(kind: .message)
        var time = parts.time
        if let floor, time <= floor {
            guard floor < OpencodeID.timeMask else { throw MintError.orderedSpaceExhausted }
            time = floor + 1
        }
        newestMessageTimes[sessionID] = time
        return OpencodeID.encode(kind: .message, time: time, bytes: parts.bytes)
    }

    /// Non-message identifiers use Identifier.create's ordering without adjustment.
    /// Message creation requires a session through mintMessage.
    public func mint(_ kind: OpencodeID.Kind) throws -> String {
        guard kind != .message else { throw MintError.invalidMessageID }
        let parts = try nextParts(kind: kind)
        return OpencodeID.encode(kind: kind, time: parts.time, bytes: parts.bytes)
    }

    private func nextParts(kind: OpencodeID.Kind) throws -> (time: UInt64, bytes: [UInt8]) {
        let milliseconds = (now().timeIntervalSince1970 * 1_000).rounded(.down)
        guard milliseconds.isFinite, milliseconds >= 0,
              let timestamp = UInt64(exactly: milliseconds)
        else { throw MintError.invalidTimestamp }
        let bytes = randomBytes()
        guard bytes.count == 14 else { throw MintError.invalidRandomBytes }
        return (sequence.next(descending: kind.isDescending, timestamp: timestamp), bytes)
    }
}

/// Port of packages/schema/src/identifier.ts at d0732ea. The counter is shared
/// across prefixes/directions and deliberately carries into the timestamp bits.
struct IdentifierSequence {
    private var lastTimestamp: UInt64 = 0
    private var counter: UInt64 = 0

    mutating func next(descending: Bool, timestamp: UInt64) -> UInt64 {
        if timestamp != lastTimestamp {
            lastTimestamp = timestamp
            counter = 0
        }
        counter &+= 1
        let current = timestamp &* 0x1000 &+ counter
        return (descending ? ~current : current) & OpencodeID.timeMask
    }
}
