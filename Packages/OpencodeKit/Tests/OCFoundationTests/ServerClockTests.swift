import Foundation
import Testing
@testable import OCFoundation

struct ServerClockTests {
    private let serverTime: TimeInterval = 1_445_412_480

    @Test(arguments: [
        "Wed, 21 Oct 2015 07:28:00 GMT",
        "Wednesday, 21-Oct-15 07:28:00 GMT",
        "Wed Oct 21 07:28:00 2015",
    ])
    func estimatesFromRoundTripMidpoint(header: String) {
        let local = Date(timeIntervalSince1970: serverTime - 9)
        let clock = ServerClock(now: { local })
        #expect(clock.now() == local)
        #expect(clock.observe(httpDate: header, requestSentAt: local.addingTimeInterval(-2), responseReceivedAt: local))
        #expect(abs(clock.offset - 10) < 0.0001)
        #expect(clock.now() == local.addingTimeInterval(10))
    }

    @Test func acceptsNegativeOffsetAndPrefersLowerLatency() {
        let clock = ServerClock()
        let sent = Date(timeIntervalSince1970: serverTime + 9)
        #expect(clock.observe(httpDate: "Wed, 21 Oct 2015 07:28:00 GMT", requestSentAt: sent, responseReceivedAt: sent.addingTimeInterval(2)))
        #expect(clock.offset == -10)
        #expect(!clock.observe(httpDate: "Wed, 21 Oct 2015 07:28:00 GMT", requestSentAt: sent, responseReceivedAt: sent.addingTimeInterval(20)))
        #expect(clock.offset == -10)
        #expect(clock.observe(httpDate: "Wed, 21 Oct 2015 07:28:00 GMT", requestSentAt: sent, responseReceivedAt: sent))
        #expect(clock.offset == -9)
    }

    @Test func eventTimestampsRefineForwardWithoutTrustingDelayedEvents() {
        let clock = ServerClock()
        let received = Date(timeIntervalSince1970: serverTime)
        #expect(clock.refine(eventTimestamp: received.addingTimeInterval(5.25), receivedAt: received))
        #expect(clock.offset == 5.25)
        #expect(!clock.refine(eventTimestamp: received.addingTimeInterval(-100), receivedAt: received))
        #expect(clock.offset == 5.25)
        #expect(!clock.refine(eventTimestamp: Date(timeIntervalSince1970: .nan), receivedAt: received))
    }

    @Test func ignoresInvalidSamples() {
        let clock = ServerClock()
        let date = Date(timeIntervalSince1970: serverTime)
        #expect(!clock.observe(httpDate: "not a date", requestSentAt: date, responseReceivedAt: date))
        #expect(!clock.observe(httpDate: "Wed, 21 Oct 2015 07:28:00 GMT", requestSentAt: date, responseReceivedAt: date.addingTimeInterval(-1)))
        #expect(clock.offset == 0)
    }
}
