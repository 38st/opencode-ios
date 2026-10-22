import os

/// Dynamic values are discarded before reaching os.Logger, even when the system
/// enables private logging. Never paste credentials into literal message text.
public struct RedactedLogMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable {
    public let text: String

    public init(stringLiteral value: String) { text = value }
    public init(stringInterpolation: StringInterpolation) { text = stringInterpolation.text }

    public struct StringInterpolation: StringInterpolationProtocol {
        fileprivate var text = ""

        public init(literalCapacity: Int, interpolationCount: Int) {
            text.reserveCapacity(literalCapacity + interpolationCount * 10)
        }

        public mutating func appendLiteral(_ literal: String) { text += literal }

        public mutating func appendInterpolation<T>(_ value: T) {
            text += "[REDACTED]"
        }
    }
}

public struct RedactingLogger: Sendable {
    private let logger: Logger

    public init(category: String) {
        logger = Logger(subsystem: "dev.opencodeios.client", category: category)
    }

    public func debug(_ message: RedactedLogMessage) { logger.debug("\(message.text, privacy: .public)") }
    public func info(_ message: RedactedLogMessage) { logger.info("\(message.text, privacy: .public)") }
    public func error(_ message: RedactedLogMessage) { logger.error("\(message.text, privacy: .public)") }
}

public enum OCLog {
    public static let networking = RedactingLogger(category: "networking")
    public static let sync = RedactingLogger(category: "sync")
    public static let persistence = RedactingLogger(category: "persistence")
    public static let security = RedactingLogger(category: "security")
    public static let rendering = RedactingLogger(category: "rendering")
    public static let app = RedactingLogger(category: "app")
}
