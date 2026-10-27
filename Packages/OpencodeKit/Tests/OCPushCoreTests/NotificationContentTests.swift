import CryptoKit
import Foundation
import Testing
import OCFoundation
import OCShared
@testable import OCPushCore

@Test(arguments: Vectors.cases("envelope.json", "valid") + Vectors.cases("envelope.json", "rejections"))
func notificationBuilderUsesSharedVectors(item: JSONValue) throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PushSnapshotStore(directory: root)
    let envelope = try #require(item["envelope"])
    let kid = envelope["kid"]?.stringValue ?? "missing"
    let entry = try Vectors.json("envelope.json")["keyring"]?.arrayValue?.first { $0["kid"]?.stringValue == kid }
    let key: PushRecipientKey?
    if let entry, let secret = entry["recipientPrivateKey"]?.stringValue.flatMap(Base64URL.decode),
       let sender = entry["senderPublicKey"]?.stringValue.flatMap(Base64URL.decode) { key = .init(privateKey: secret, senderPublicKey: sender) }
    else { key = nil }
    let now = Date(timeIntervalSince1970: Double(try #require(item["now"]?.integerValue)))
    let opened = try? PushSealing.open(envelope, now: now) { _ in key }
    let server = opened?.payload.server ?? "unknown"
    if (try? PushEnvelope(json: envelope)) != nil { try store.register(keyID: kid, server: server) }
    let generic = NotificationPresentation(title: "Opencode", body: "Generic alert")
    let result = NotificationContentBuilder.build(envelope: envelope, key: key, server: server, now: now, generic: generic, store: store)
    if item["error"] != nil {
        #expect(result == generic)
        #expect(result.category == "OPEN_ONLY")
    } else {
        #expect(result.shownID != nil)
        #expect(result.badge == opened?.payload.pending)
        #expect(try store.shown(try #require(result.shownID))?.summary == result.body)
        #expect(try store.shown(try #require(result.shownID))?.digest == opened?.payload.digest)
    }
}

@Test func allNotificationActionsFailClosedAndOpenFirst() {
    for kind in PushContract.shared.kinds.keys {
        for risk in [PermissionRisk.low, .elevated, .high] {
            for freeText in [false, true] {
                let category = NotificationCategories.category(kind: kind, risk: risk, freeText: freeText, approvals: true)
                let actions = NotificationCategories.actions(for: category)
                #expect(actions.first?.id == .open)
                #expect(actions.first?.foreground == true)
                if kind == "permission" {
                    #expect(actions.map(\.id) == (risk == .high ? [.open, .reject] : [.open, .allow, .reject, .rejectWithNote]))
                }
                if kind == "question" { #expect(actions.map(\.id) == (freeText ? [.open, .answer] : [.open])) }
                if ["finished", "failed"].contains(kind) { #expect(actions.map(\.id) == [.open, .reply]) }
                for action in actions {
                    if action.id == .allow || action.id == .reply { #expect(action.authenticationRequired) }
                    if action.id == .reject { #expect(action.destructive) }
                    if [.rejectWithNote, .answer, .reply].contains(action.id) { #expect(action.textInput) }
                }
            }
        }
    }
    #expect(NotificationCategories.category(kind: "permission", risk: .low, freeText: false, approvals: false) == "OPEN_ONLY")
    #expect(NotificationCategories.category(kind: "question", risk: .low, freeText: true, approvals: false) == "OPEN_ONLY")
}

@Test func completionReceiptsDistinguishRunsWithinOneSecond() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PushSnapshotStore(directory: root)
    let recipient = Curve25519.KeyAgreement.PrivateKey(), sender = Curve25519.KeyAgreement.PrivateKey()
    let kid = "completion_key_123456", server = UUID().uuidString
    try store.register(keyID: kid, server: server)
    let input: JSONValue = .object(["v": .integer(1), "kind": .string("finished"), "exp": .integer(1_800_000_600),
        "server": .string(server), "sessionID": .string("ses_completion"), "pending": .integer(0)])
    let plaintext = try JSONEncoder().encode(input)
    func seal() throws -> JSONValue {
        try PushSealing.seal(plaintext, kind: "finished", expiry: 1_800_000_600, keyID: kid,
            recipientPublicKey: recipient.publicKey.rawRepresentation, senderPrivateKey: sender.rawRepresentation).json
    }
    func build(_ envelope: JSONValue) -> NotificationPresentation {
        NotificationContentBuilder.build(envelope: envelope,
            key: .init(privateKey: recipient.rawRepresentation, senderPublicKey: sender.publicKey.rawRepresentation),
            server: server, now: Date(timeIntervalSince1970: 1_800_000_000), generic: .init(body: "Generic"), store: store)
    }
    let first = try seal(), second = try seal()
    let firstID = try #require(build(first).shownID)
    #expect(build(first).shownID == firstID)
    #expect(try #require(build(second).shownID) != firstID)
}

#if canImport(UserNotifications)
import UserNotifications
/// iOS withdraws every delivered notification of the app when one arrives carrying badge 0. A resolved or
/// finished push that brings the pending count to zero must therefore leave the badge off its content, and
/// the caller clears the icon with `setBadgeCount(0)` instead, which leaves delivered notifications alone.
@Test func zeroPendingNeverPutsBadgeZeroOnContent() {
    for (badge, expected, clears) in [(Int?.none, Int?.none, false), (0, nil, true), (3, 3, false)] {
        var presentation = NotificationPresentation(title: "Request resolved", body: "Answered on another device")
        presentation.badge = badge
        let content = UNMutableNotificationContent()
        content.badge = 7 // a payload's own badge never survives a zero count
        presentation.apply(to: content)
        #expect(content.badge?.intValue == expected)
        #expect(presentation.clearsBadge == clears)
    }
}
#endif
