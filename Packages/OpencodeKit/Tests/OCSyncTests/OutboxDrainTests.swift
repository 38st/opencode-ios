import Foundation
import Testing
import OCFoundation
import OCPersistence
@testable import OCSync

private actor PromptRequests {
    var bodies: [Data] = []
    func append(_ body: Data) { bodies.append(body) }
}

@Test func reconnectDrainsOriginalPromptBytesInOrderAndHoldsOldEntries() async throws {
    let writer = try PersistenceWriter(), store = OutboxStore(writer: writer), requests = PromptRequests()
    let drain = OutboxDrain(store: store, serverID: "server"), now = Date()
    let old = OutboxEntry(id: "old", serverID: "server", sessionID: "other-session", body: Data(#"{"id":"old"}"#.utf8), createdAt: now.addingTimeInterval(-601))
    let bodies = [Data(#"{ "id": "a", "text": "first" }"#.utf8), Data(#"{"text":"second","id":"b"}"#.utf8)]
    try await store.save(old)
    for (index, id) in ["a", "b"].enumerated() {
        try await store.save(.init(id: id, serverID: "server", sessionID: "s", body: bodies[index], createdAt: now.addingTimeInterval(Double(index))))
    }
    try await drain.prepareLaunch(now: now)
    let api = readAPI { request in
        let body = try #require(request.httpBody)
        await requests.append(body)
        let raw = try JSONDecoder().decode(JSONValue.self, from: body)
        return .object(["data": .object(["type": .string("user"), "id": raw["id"] ?? .null])])
    }
    async let first: Void = drain.drain(using: api)
    async let second: Void = drain.drain(using: api)
    _ = try await (first, second)
    #expect(await requests.bodies == bodies)
    let remaining = try await store.entries(serverID: "server")
    #expect(remaining.map(\.id) == ["old"])
    #expect(remaining.first?.state == "needsConfirmation")
    await drain.stop()
}
