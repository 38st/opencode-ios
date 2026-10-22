import Foundation
import Synchronization
import Testing
@testable import OCFoundation

struct OpencodeIDTests {
    private struct Vectors: Decodable {
        struct Vector: Decodable {
            let timestamp: UInt64
            let descending: Bool
            let counter: Int
            let encodedTime: String
            let suffix: String
        }
        let randomBytes: [UInt8]
        let vectors: [Vector]
    }

    @Test func matchesSourceDerivedVectorsAndRecoversTimestamp() throws {
        let fixtures = try JSONDecoder().decode(Vectors.self, from: Fixture.data("identifier-vectors"))
        var sequence = IdentifierSequence()
        for vector in fixtures.vectors {
            let kind: OpencodeID.Kind = vector.descending ? .session : .message
            let time = sequence.next(descending: vector.descending, timestamp: vector.timestamp)
            let id = OpencodeID.encode(kind: kind, time: time, bytes: fixtures.randomBytes)
            #expect(id == kind.rawValue + "_" + vector.encodedTime + vector.suffix)
            let parsed = try #require(OpencodeID.components(of: id))
            #expect(parsed.counter == vector.counter)
            #expect(parsed.truncatedMilliseconds == vector.timestamp % (1 << 36))
            let expected = Date(timeIntervalSince1970: Double(vector.timestamp) / 1_000)
            #expect(abs(parsed.timestamp(nearest: expected.addingTimeInterval(60)).timeIntervalSince(expected)) < 0.0001)
        }
    }

    @Test func counterCarriesLikeSourceAfter4095() {
        var sequence = IdentifierSequence()
        for _ in 0..<4095 { _ = sequence.next(descending: false, timestamp: 100) }
        #expect(sequence.next(descending: false, timestamp: 100) == 101 * 4096)
        // The source resets its counter even if that repeats the packed time.
        #expect(sequence.next(descending: false, timestamp: 101) == 101 * 4096 + 1)
    }

    @Test func schemaPrefixesAndDirections() async throws {
        let expectedPrefixes: [OpencodeID.Kind: String] = [
            .session: "ses", .message: "msg", .permission: "per", .savedPermission: "psv",
            .form: "frm", .event: "evt", .workspace: "wrk", .pty: "pty", .integration: "con",
            .credential: "cred", .shell: "sh", .toolOutput: "tool",
        ]
        let clock = ServerClock(now: { Date(timeIntervalSince1970: 100) })
        let minter = IDMinter(clock: clock)
        for kind in OpencodeID.Kind.allCases { #expect(kind.rawValue == expectedPrefixes[kind]) }
        for kind in OpencodeID.Kind.allCases where kind != .message {
            let first = try await minter.mint(kind)
            let second = try await minter.mint(kind)
            #expect(first.hasPrefix(kind.rawValue + "_"))
            #expect(first.utf8.count == kind.rawValue.utf8.count + 27)
            #expect(OpencodeID.components(of: first)?.random.utf8.count == 14)
            if kind.isDescending { #expect(second < first) } else { #expect(first < second) }
        }
    }

    @Test func correctedTimeAndSessionFloorSurviveRollbackAndStaleSnapshots() async throws {
        let now = Mutex(Date(timeIntervalSince1970: 1_445_412_470))
        let clock = ServerClock(now: { now.withLock { $0 } })
        #expect(clock.observe(
            httpDate: "Wed, 21 Oct 2015 07:28:00 GMT",
            requestSentAt: Date(timeIntervalSince1970: 1_445_412_469),
            responseReceivedAt: Date(timeIntervalSince1970: 1_445_412_471)
        ))
        let minter = IDMinter(clock: clock, randomBytes: { Array(repeating: 0, count: 14) })
        let first = try await minter.mintMessage(sessionID: "session-a")
        let firstParts = try #require(OpencodeID.components(of: first))
        #expect(firstParts.timestamp(nearest: clock.now()) == clock.now())
        let future = OpencodeID.encode(kind: .message, time: firstParts.encodedTime + 100_000, bytes: Array(repeating: 61, count: 14))
        now.withLock { $0 = $0.addingTimeInterval(-60) }
        let second = try await minter.mintMessage(sessionID: "session-a", newestKnownMessageID: future)
        let third = try await minter.mintMessage(sessionID: "session-a", newestKnownMessageID: first)
        #expect(first < future && future < second && second < third)
        let otherSession = try await minter.mintMessage(sessionID: "session-b")
        #expect(otherSession < first)
    }

    @Test func floorSurvivesCounterOverflowAndRestart() async throws {
        let now = Mutex(Date(timeIntervalSince1970: 1))
        let clock = ServerClock(now: { now.withLock { $0 } })
        let minter = IDMinter(clock: clock, randomBytes: { Array(repeating: 0, count: 14) })
        var newest = ""
        for _ in 0..<4100 {
            let next = try await minter.mintMessage(sessionID: "a")
            #expect(next > newest)
            newest = next
        }
        now.withLock { $0 = Date(timeIntervalSince1970: 1.001) }
        let next = try await minter.mintMessage(sessionID: "a")
        #expect(next > newest)
        let restarted = IDMinter(clock: clock)
        let restored = try await restarted.mintMessage(sessionID: "a", newestKnownMessageID: next)
        #expect(restored > next)
    }

    @Test func concurrentCallsAreUnique() async throws {
        let minter = IDMinter(clock: ServerClock(now: { Date(timeIntervalSince1970: 100) }))
        let ids = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<100 { group.addTask { try await minter.mintMessage(sessionID: "a") } }
            var values: [String] = []
            for try await id in group { values.append(id) }
            return values
        }
        #expect(Set(ids).count == 100)
        let times = ids.compactMap { OpencodeID.components(of: $0)?.encodedTime }.sorted()
        #expect(times.count == 100)
        #expect(zip(times, times.dropFirst()).allSatisfy { $1 == $0 + 1 })
    }

    @Test func rejectsInvalidInputAndDoesNotWrapOrderingFloor() async throws {
        let minter = IDMinter(clock: ServerClock())
        await #expect(throws: IDMinter.MintError.invalidMessageID) {
            try await minter.mintMessage(sessionID: "a", newestKnownMessageID: "msg_broken")
        }
        await #expect(throws: IDMinter.MintError.invalidMessageID) { try await minter.mint(.message) }
        await #expect(throws: IDMinter.MintError.orderedSpaceExhausted) {
            try await minter.mintMessage(sessionID: "a", newestKnownMessageID: "msg_ffffffffffffzzzzzzzzzzzzzz")
        }
        let invalidTime = IDMinter(clock: ServerClock(now: { Date(timeIntervalSince1970: .nan) }))
        await #expect(throws: IDMinter.MintError.invalidTimestamp) { try await invalidTime.mintSession() }
        let invalidBytes = IDMinter(clock: ServerClock(), randomBytes: { [] })
        await #expect(throws: IDMinter.MintError.invalidRandomBytes) { try await invalidBytes.mintSession() }
    }

    @Test(arguments: ["", "msg_000000000001short", "msg_Z000000000010123456789ABCD", "msg_000000000001!!!!!!!!!!!!!!", "ses_0000000000010123456789ABCD_extra"])
    func invalidIDIsNotParsed(id: String) { #expect(OpencodeID.components(of: id) == nil) }
}
