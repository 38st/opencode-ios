import Testing
import OCActivity
import OCFoundation
import OCModels
@testable import OCSync

@Test @MainActor func activityProgressIgnoresReplayAndChildCompletion() throws {
    let store = ReadStore(serverID: "server")
    var child = readInfo("child")
    child["parentID"] = .string("root")
    store.seed(info: readInfo("root"), messages: [])
    store.seed(info: child, messages: [])
    store.apply(try readEvent("session.execution.started", session: "root"))
    let step = try readEvent("session.step.started", session: "child", data: ["assistantMessageID": .string("message")])
    store.apply(step); store.apply(step)
    #expect(store.activityProgress.states["root"]?.step == 1)
    store.apply(try readEvent("session.execution.started", session: "child"))
    store.apply(try readEvent("session.execution.succeeded", session: "child"))
    #expect(store.activityProgress.states["root"]?.phase == "running")
    #expect(store.activityProgress.states["root"]?.step == 1)
    store.apply(try readEvent("session.execution.failed", session: "root"))
    #expect(store.activityProgress.states["root"]?.phase == "failed")
}
