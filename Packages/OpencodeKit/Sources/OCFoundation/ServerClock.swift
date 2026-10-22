import Foundation
import Synchronization

/// A server-scoped wall clock; all inputs can be supplied without network access.
public final class ServerClock: Sendable {
    private struct State: Sendable {
        var offset: TimeInterval = 0
        var bestRoundTrip: TimeInterval?
    }

    private let state = Mutex(State())
    private let localNow: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        localNow = now
    }

    public var offset: TimeInterval { state.withLock { $0.offset } }

    public func now() -> Date { localNow().addingTimeInterval(offset) }

    /// Prefer the lowest-latency HTTP sample. Date headers have one-second precision.
    @discardableResult
    public func observe(
        httpDate: String, requestSentAt: Date, responseReceivedAt: Date
    ) -> Bool {
        guard let serverDate = Self.parseHTTPDate(httpDate) else { return false }
        let roundTrip = responseReceivedAt.timeIntervalSince(requestSentAt)
        let midpoint = requestSentAt.timeIntervalSince1970 + roundTrip / 2
        let offset = serverDate.timeIntervalSince1970 - midpoint
        guard roundTrip.isFinite, roundTrip >= 0, offset.isFinite else { return false }
        return state.withLock {
            if let best = $0.bestRoundTrip, roundTrip > best { return false }
            $0.offset = offset
            $0.bestRoundTrip = roundTrip
            return true
        }
    }

    /// An event's arrival gives a lower bound on the offset, not an RTT sample.
    /// Old/queued events cannot pull the clock backwards. A fresh HTTP sample can.
    @discardableResult
    public func refine(eventTimestamp: Date, receivedAt: Date) -> Bool {
        let lowerBound = eventTimestamp.timeIntervalSince(receivedAt)
        guard lowerBound.isFinite else { return false }
        return state.withLock {
            guard lowerBound > $0.offset else { return false }
            $0.offset = lowerBound
            return true
        }
    }

    private static func parseHTTPDate(_ value: String) -> Date? {
        // RFC 9110 recipients also accept the two obsolete HTTP-date formats.
        let formats = ["EEE, dd MMM yyyy HH:mm:ss 'GMT'", "EEEE, dd-MMM-yy HH:mm:ss 'GMT'", "EEE MMM d HH:mm:ss yyyy"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            formatter.isLenient = false
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}
