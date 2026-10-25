import Foundation
import Testing
import OCModels
import OCFoundation
@testable import OCRender

@Test func runEndAnnouncementReportsOnlyTheLatestTurnsFailure() {
    #expect(TimelineAnnouncement.runEnded(rows: []) == "Run finished")
    let failed = [TimelineRow(id: "u1", kind: .userPrompt), TimelineRow(id: "e1", kind: .error, text: "Provider error")]
    #expect(TimelineAnnouncement.runEnded(rows: failed) == "Run failed")
    let recovered = failed + [TimelineRow(id: "u2", kind: .userPrompt), TimelineRow(id: "a2", kind: .assistantText), TimelineRow(id: "t2", kind: .turnEnd)]
    #expect(TimelineAnnouncement.runEnded(rows: recovered) == "Run finished")
}

@Test func pendingInputAnnouncementNamesOnlyNewRequests() {
    let shell = PermissionRequest(raw: .object(["id": .string("p1"), "sessionID": .string("s"), "action": .string("bash")]))
    let edit = PermissionRequest(raw: .object(["id": .string("p2"), "sessionID": .string("s"), "action": .string("edit")]))
    let form = FormInfo(raw: .object(["id": .string("f1"), "sessionID": .string("s"), "title": .string("Pick a branch")]))
    #expect(TimelineAnnouncement.pendingInput(previous: [], permissions: [shell], forms: []) == "Permission needed: Bash")
    #expect(TimelineAnnouncement.pendingInput(previous: ["p1"], permissions: [shell, edit], forms: [form]) == "Permission needed: Edit. Question: Pick a branch")
    #expect(TimelineAnnouncement.pendingInput(previous: ["p1", "p2", "f1"], permissions: [shell, edit], forms: [form]) == nil)
    #expect(TimelineAnnouncement.pendingInput(previous: ["p1"], permissions: [], forms: []) == nil)
}
