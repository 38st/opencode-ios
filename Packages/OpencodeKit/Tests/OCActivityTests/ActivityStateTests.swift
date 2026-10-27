import Foundation
import Testing
import OCActivity
@Test func activityTimestampsUseUnixSeconds() throws {
    let raw = Data(#"{"phase":"running","step":2,"toolGlyph":"shell","startedAt":1800000000,"updatedAt":1800000010}"#.utf8)
    let state = try JSONDecoder().decode(SessionActivityAttributes.ContentState.self, from: raw)
    #expect(state.startedAt == 1_800_000_000)
    #expect(state.label == "Running")
}
