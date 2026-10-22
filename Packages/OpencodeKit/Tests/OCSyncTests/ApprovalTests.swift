import Foundation
import Testing
import OCFoundation
import OCModels
import OCNetworking
import OCSecurity
@testable import OCSync

private actor TestBiometricGate: BiometricAuthenticating {
    let succeeds: Bool
    var calls = 0
    init(succeeds: Bool) { self.succeeds = succeeds }
    func authenticate(reason: String) throws {
        calls += 1
        if !succeeds { throw CancellationError() }
    }
}
private func permission(_ id: String, session: String = "s") -> PermissionRequest {
    .init(raw: .object(["id": .string(id), "sessionID": .string(session), "action": .string("read"), "resources": .array([.string("/p/file")]), "save": .array([.string("/p/*")]), "source": .object(["type": .string("tool"), "id": .string("tool")])]))
}

@Test @MainActor func globalFormUsesItsResolvedWorkspaceLocation() async throws {
    let store = ReadStore(serverID: "server")
    let form = FormInfo(raw: .object(["id": .string("global-form"), "sessionID": .string("global"), "fields": .array([])]))
    let owner = FormOwner.global(location: Location(directory: "/workspace/project", workspaceID: "workspace").key)
    store.forms[owner] = [form]
    store.client = { readAPI { request in
        let url = try #require(request.url)
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(.init(name: "location[directory]", value: "/workspace/project")) == true)
        return .object([:])
    } }
    try await store.replyForm(form, answer: [:])
    #expect(store.forms[owner]?.isEmpty == true)
    await store.stop()
}
@Test @MainActor func alwaysRequiresAuthenticationAndRejectRemovesSessionSiblings() async throws {
    let store = ReadStore(serverID: "server"), first = permission("p1"), sibling = permission("p2"), child = permission("child", session: "child")
    store.seed(info: readInfo(), permissions: [first, sibling]); store.seed(info: readInfo("child", parent: "s"), permissions: [child])
    let gate = TestBiometricGate(succeeds: false); store.biometricGate = gate
    store.client = { readAPI { _ in .object([:]) } }
    await #expect(throws: CancellationError.self) { try await store.replyPermission(first, decision: .always) }
    #expect(await gate.calls == 1); #expect(store.permissions["s"]?.count == 2)
    #expect(store.familyPermissions("s").count == 3)
    #expect(store.permissionForTool("tool", sessionID: "s") != nil)
    #expect(store.permissionForTool("tool", sessionID: "unrelated") == nil)
    #expect(store.permissionForTool("tool", sessionID: "child")?.id == "child")
    store.client = { readAPI { request in
        await MainActor.run { #expect(store.permissions["s"]?.isEmpty == true); #expect(store.permissions["child"]?.count == 1) }
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        #expect(body["decision"] == .string("reject")); #expect(body["message"] == .string("Use the fixture instead."))
        return .object([:])
    } }
    try await store.replyPermission(first, decision: .reject, message: "Use the fixture instead.")
    #expect(store.permissions["s"]?.isEmpty == true)
    await store.stop()
}
@Test @MainActor func failedApprovalRestoresUnsettledRequestsButNotServerResolvedOnes() async throws {
    let store = ReadStore(serverID: "server"), first = permission("p1"), sibling = permission("p2")
    store.seed(info: readInfo(), permissions: [first, sibling])
    store.client = { readAPI { _ in
        let event = try readEvent("permission.replied", data: ["requestID": .string("p2")])
        await MainActor.run { store.apply(event) }
        throw URLError(.timedOut)
    } }
    do { try await store.replyPermission(first, decision: .reject) } catch APIError.transport {}
    #expect(store.permissions["s"]?.map(\.id) == ["p1"])
    await store.stop()
}
@Test @MainActor func optimisticRepliesStayHiddenFromRacingSnapshots() async throws {
    let store = ReadStore(serverID: "server"), request = permission("p")
    let form = FormInfo(raw: .object(["id": .string("f"), "sessionID": .string("s"), "fields": .array([.object(["type": .string("boolean"), "key": .string("answer"), "required": .bool(true)])])]))
    store.seed(info: readInfo(), permissions: [request], forms: [form])
    store.client = { readAPI { _ in .object([:]) } }
    try await store.replyPermission(request, decision: .once)
    try await store.replyForm(form, answer: ["answer": .bool(false)])
    store.applyRequests([request], forms: [form], owner: "s", overlay: FetchOverlay())
    #expect(store.permissions["s"]?.isEmpty == true && store.forms[.session("s")]?.isEmpty == true)
    await store.stop()
}
