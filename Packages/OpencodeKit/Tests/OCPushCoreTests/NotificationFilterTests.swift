import CryptoKit
import Foundation
import Testing
import OCFoundation
import OCShared
@testable import OCPushCore

private let utc: Calendar = { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!; return calendar }()
/// 2026-10-29 23:30 UTC, inside 22:00–07:00 quiet hours; 12:00 UTC is outside them.
private let night = Date(timeIntervalSince1970: 1_793_316_600), noon = Date(timeIntervalSince1970: 1_793_275_200)

private func decide(_ kind: String, _ preferences: PushPreferences, at date: Date = noon, session: String? = "ses_1", root: String? = nil) -> NotificationFilter.Decision {
    NotificationFilter.decide(kind: kind, server: "srv", sessionID: session, rootSessionID: root, preferences: preferences, now: date, calendar: utc)
}

@Test func categoriesSilenceOnlyTheirOwnKind() {
    var preferences = PushPreferences()
    #expect(decide("permission", preferences) == .deliver(.timeSensitive))
    #expect(decide("question", preferences) == .deliver(.timeSensitive))
    #expect(decide("finished", preferences) == .deliver(.active))
    #expect(decide("failed", preferences) == .deliver(.active))
    preferences.silencedKinds = ["finished", "question"]
    #expect(decide("finished", preferences) == .silence && decide("question", preferences) == .silence)
    #expect(decide("failed", preferences) == .deliver(.active) && decide("permission", preferences) == .deliver(.timeSensitive))
    #expect(decide("resolved", preferences) == .deliver(.passive) && decide("test", preferences) == .deliver(.active), "Other kinds keep the server's level")
}

@Test func mutedSessionsAndTheirSubagentsAreSilencedButApprovalsAreNot() {
    var preferences = PushPreferences()
    preferences.mutedSessions = [PushPreferences.muteKey(server: "srv", session: "ses_root")]
    #expect(decide("finished", preferences, session: "ses_root") == .silence)
    #expect(decide("failed", preferences, session: "ses_child", root: "ses_root") == .silence, "A muted root mutes its subagents")
    #expect(decide("question", preferences, session: "ses_root") == .silence)
    #expect(decide("permission", preferences, session: "ses_root") == .deliver(.timeSensitive), "Approvals keep alerting in a muted session")
    #expect(decide("finished", preferences, session: "ses_other") == .deliver(.active))
    #expect(NotificationFilter.decide(kind: "finished", server: "other", sessionID: "ses_root", rootSessionID: nil, preferences: preferences, now: noon, calendar: utc) == .deliver(.active),
            "Mutes are per server")
}

@Test func quietHoursOnlyLowerTheLevelAndNeverTouchApprovals() {
    var preferences = PushPreferences()
    preferences.quietHours = QuietHours(start: 22 * 60, end: 7 * 60)
    #expect(decide("permission", preferences, at: night) == .deliver(.timeSensitive))
    #expect(decide("question", preferences, at: night) == .deliver(.active))
    #expect(decide("finished", preferences, at: night) == .deliver(.passive))
    #expect(decide("finished", preferences, at: noon) == .deliver(.active))
    preferences.silencedKinds = ["permission"]
    #expect(decide("permission", preferences, at: night) == .silence, "Only the user's own switch silences approvals")
}

@Test func quietHoursSpanMidnight() {
    let quiet = QuietHours(start: 22 * 60, end: 7 * 60)
    #expect(quiet.contains(night, calendar: utc) && !quiet.contains(noon, calendar: utc))
    #expect(QuietHours(start: 9 * 60, end: 17 * 60).contains(noon, calendar: utc))
    #expect(!QuietHours(start: 60, end: 60).contains(noon, calendar: utc), "An empty window is never quiet")
}

@Test func olderPreferenceFilesStillLoad() throws {
    let old = try JSONDecoder().decode(PushPreferences.self, from: Data(#"{"lockScreenApprovals":false,"liveActivities":true}"#.utf8))
    #expect(!old.lockScreenApprovals && old.silencedKinds.isEmpty && old.mutedSessions.isEmpty && old.quietHours == nil)
    var next = PushPreferences(); next.silencedKinds = ["failed"]; next.quietHours = .init(start: 1, end: 2); next.mutedSessions = ["a/b"]
    #expect(try JSONDecoder().decode(PushPreferences.self, from: JSONEncoder().encode(next)) == next)
    #expect(try JSONDecoder().decode(PushPreferences.self, from: Data(#"{"quietHours":"bad","future":1}"#.utf8)) == PushPreferences())
}

@Test func theBuilderAppliesTheSettingsToAVerifiedPush() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PushSnapshotStore(directory: root)
    let recipient = Curve25519.KeyAgreement.PrivateKey(), sender = Curve25519.KeyAgreement.PrivateKey()
    let kid = "filter_key_1234567890", server = UUID().uuidString
    try store.register(keyID: kid, server: server)
    func build(_ kind: String) throws -> NotificationPresentation {
        let input: JSONValue = .object(["v": .integer(1), "kind": .string(kind), "exp": .integer(1_800_000_600), "server": .string(server),
            "sessionID": .string("ses_muted"), "pending": .integer(1), "requestID": .string("req_" + kind)])
        let envelope = try PushSealing.seal(try JSONEncoder().encode(input), kind: kind, expiry: 1_800_000_600, keyID: kid,
            recipientPublicKey: recipient.publicKey.rawRepresentation, senderPrivateKey: sender.rawRepresentation).json
        return NotificationContentBuilder.build(envelope: envelope, key: .init(privateKey: recipient.rawRepresentation, senderPublicKey: sender.publicKey.rawRepresentation),
            server: server, now: Date(timeIntervalSince1970: 1_800_000_000), generic: .init(body: "Generic"), store: store)
    }
    #expect(try build("finished").silenced == false && (try build("finished").interruption) == nil)
    var preferences = try store.preferences()
    preferences.mutedSessions = [PushPreferences.muteKey(server: server, session: "ses_muted")]
    try store.save(preferences: preferences)
    let muted = try build("finished")
    #expect(muted.silenced && muted.interruption == .passive && muted.relevance == 0)
    #expect(muted.shownID != nil, "A silenced push is still recorded and routed")
    let approval = try build("permission")
    #expect(!approval.silenced && approval.interruption == nil)
}
