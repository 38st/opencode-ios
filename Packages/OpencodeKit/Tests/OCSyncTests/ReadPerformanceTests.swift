import Foundation
import Darwin
import Testing
import OCFoundation
import OCModels
import OCRender
@testable import OCSync

@Suite(.serialized) @MainActor struct ReadPerformanceTests {
    @Test func streamingAtFiftyTokensPerSecond() async throws {
        let store = ReadStore(serverID: "performance")
        let info = SessionInfo(raw: .object(["id": .string("s")]))
        let row = SessionMessage(raw: .object(["id": .string("a"), "type": .string("assistant"), "content": .array([])]))
        store.seed(info: info, messages: [row])
        let item = store.sessions["s"]?.transcript?.messages["a"]?.upsert(.text(0), value: .init(raw: .object(["type": .string("text"), "text": .string("")])))
        let pipeline = StreamingMarkdown()
        var samples: [Double] = [], cpuSamples: [Double] = []
        let start = ContinuousClock.now
        for index in 0..<100 {
            let raw: JSONValue = .object(["id": .string("evt-\(index)"), "created": .integer(Int64(index)), "type": .string("session.text.delta"),
                "data": .object(["sessionID": .string("s"), "assistantMessageID": .string("a"), "ordinal": .integer(0), "delta": .string("token ")])])
            let event = ServerEvent.decode(try JSONEncoder().encode(raw))
            let before = ContinuousClock.now
            let cpuBefore = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            store.apply(event)
            cpuSamples.append(Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - cpuBefore) / 1e6)
            samples.append(seconds(before.duration(to: .now)) * 1_000)
            if index % 5 == 0 { _ = try await pipeline.update(item?.text ?? "") }
            let next = start.advanced(by: .milliseconds((index + 1) * 20))
            if next > .now { try await Task.sleep(until: next, clock: .continuous) }
        }
        samples.sort()
        let p95 = samples[Int(Double(samples.count - 1) * 0.95)], maximum = samples.last ?? 0
        #expect((cpuSamples.max() ?? 0) < 4, "ARCHITECTURE §3.1: main-thread CPU work budget is 4 ms")
        #expect(p95 < 4, "Simulator wall-time p95 excludes OS scheduling outliers")
        #expect(await pipeline.parseCount <= 25)
        try record(["main_update_p95_ms": p95, "main_update_max_ms": maximum, "main_cpu_max_ms": cpuSamples.max() ?? 0, "tokens_per_second": 50], name: "streaming")
        await store.stop()
    }
    @Test func twoThousandMessagesAndFiveThousandRows() async throws {
        let builder = TimelineRowBuilder()
        let start = ContinuousClock.now
        let rows = await builder.build(messages(2_000), detail: .everything)
        let milliseconds = seconds(start.duration(to: .now)) * 1_000
        #expect(rows.count == 2_000)
        // Off-main cold projection gets 250 ms; live updates retain the 4 ms budget.
        #expect(milliseconds < 250)
        let before = residentBytes()
        let large = messages(5_000)
        let transcript = TranscriptModel(messages: large)
        let largeRows = await builder.build(large, detail: .everything)
        let retained = max(0, residentBytes() - before)
        #expect(transcript.order.count == 5_000); #expect(largeRows.count == 5_000)
        #expect(retained < 250 * 1_024 * 1_024)
        #expect(residentBytes() > 0)
        // iOS memory pressure uses physical footprint; resident size includes shared SDK mappings.
        #expect(physicalFootprint() > 0)
        #expect(physicalFootprint() < 250 * 1_024 * 1_024)
        try record(["build_2000_ms": milliseconds, "session_5000_incremental_mb": Double(retained) / 1_024 / 1_024,
                    "process_resident_mb": Double(residentBytes()) / 1_024 / 1_024,
                    "process_footprint_mb": Double(physicalFootprint()) / 1_024 / 1_024], name: "rows")
    }
    func messages(_ count: Int) -> [SessionMessage] {
        (0..<count).map { index in
            let type = index % 3 == 0 ? "user" : index % 3 == 1 ? "assistant" : "idle"
            var raw: JSONValue = .object(["id": .string("m-\(index)"), "type": .string(type), "text": .string("Inspect the implementation and report the result.")])
            if type == "assistant" {
                raw.set("content", .array([.object(["type": .string("text"), "text": .string(String(repeating: "A cached paragraph with enough text to represent a typical answer. ", count: 8))])]))
            }
            return SessionMessage(raw: raw)
        }
    }
    func record(_ values: [String: Double], name: String) throws {
        let environment = ProcessInfo.processInfo.environment
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = environment["OC_PERFORMANCE_OUTPUT"].map { URL(fileURLWithPath: $0) } ?? root.appending(path: ".build/performance")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if targetEnvironment(simulator)
        let platform = "simulator"
        #else
        let platform = "host"
        #endif
        try JSONEncoder().encode(values).write(to: directory.appending(path: "\(platform)-\(name).json"))
        print("PERFORMANCE \(platform) \(name): \(values)")
    }
    private func seconds(_ value: Duration) -> Double { Double(value.components.seconds) + Double(value.components.attoseconds) / 1e18 }
    private func residentBytes() -> Int64 {
        var info = mach_task_basic_info(), count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return status == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
    func physicalFootprint() -> UInt64 {
        var info = task_vm_info_data_t(), count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return status == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
