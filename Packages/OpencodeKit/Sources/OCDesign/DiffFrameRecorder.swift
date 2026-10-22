#if DEBUG && os(iOS)
import Foundation
import UIKit
import Darwin

/// Available only in the existing UI-test namespace; no production telemetry is collected.
final class DiffFrameRecorder {
    private final class Target: NSObject {
        weak var owner: DiffFrameRecorder?
        @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
    }
    private let target = Target()
    private var link: CADisplayLink?
    private var start = CACurrentMediaTime()
    private var key = ""
    private var firstRows: Double?
    private var previous: Double?
    private var histogram: [Int: Int] = [:]
    private var frameCount = 0
    private var frameTime: Double = 0
    private var hitchTime: Double = 0
    /// The budgets cover frames while the list moves under a finger or decelerates.
    /// Idle frames between XCUITest gestures include the runner's own accessibility queries.
    private var longestFrame: Double = 0, longestIdleFrame: Double = 0
    private var peakFootprint: UInt64 = 0
    private var lastPublished: Double = 0
    weak var view: UICollectionView?
    var scrolling = false
    var rows = 0, highlightedLines = 0, wordDiffLines = 0
    var split = false, wrap = true
    init?(view: UICollectionView) {
        guard ProcessInfo.processInfo.environment["OPENCODE_UI_TEST_ID"]?.hasPrefix("ui-") == true else { return nil }
        self.view = view; target.owner = self
        let link = CADisplayLink(target: target, selector: #selector(Target.tick(_:)))
        self.link = link; link.add(to: .main, forMode: .common)
    }
    func stop() { link?.invalidate(); link = nil }
    func begin(_ key: String) {
        guard self.key != key else { return }; self.key = key
        start = CACurrentMediaTime(); firstRows = nil; previous = nil; histogram = [:]
        frameCount = 0; frameTime = 0; hitchTime = 0; longestFrame = 0; longestIdleFrame = 0; peakFootprint = 0
    }
    func rowsReady() { if firstRows == nil { firstRows = (CACurrentMediaTime() - start) * 1000; previous = nil } }
    private func tick(_ link: CADisplayLink) {
        defer { previous = link.timestamp }
        if firstRows != nil, let previous {
            let elapsed = (link.timestamp - previous) * 1000
            if !scrolling { longestIdleFrame = max(longestIdleFrame, elapsed) }
            if scrolling {
                longestFrame = max(longestFrame, elapsed)
                frameCount += 1; frameTime += elapsed
                histogram[Int((elapsed * 100).rounded()), default: 0] += 1
                let interval = link.duration * 1000
                if elapsed > interval * 1.5 { hitchTime += max(0, elapsed - interval) }
            }
        }
        guard link.timestamp - lastPublished > 0.25 else { return }; lastPublished = link.timestamp
        // A 0.01 ms histogram keeps instrumentation cost bounded during long traversals.
        var cumulative = 0, p95: Double = 0
        for bucket in histogram.keys.sorted() {
            cumulative += histogram[bucket, default: 0]
            if cumulative >= Int(ceil(Double(frameCount) * 0.95)) { p95 = Double(bucket) / 100; break }
        }
        peakFootprint = max(peakFootprint, footprint())
        let values: [String: Double] = ["firstRowsMilliseconds": firstRows ?? -1, "p95FrameMilliseconds": p95, "longestFrameMilliseconds": longestFrame, "longestIdleFrameMilliseconds": longestIdleFrame, "hitchMillisecondsPerSecond": frameTime > 0 ? hitchTime / frameTime * 1000 : 0, "physicalFootprintMiB": Double(peakFootprint) / 1_048_576, "frames": Double(frameCount), "offset": Double(view?.contentOffset.y ?? 0), "contentHeight": Double(view?.contentSize.height ?? 0), "viewportHeight": Double(view?.bounds.height ?? 0), "rows": Double(rows), "highlightedLines": Double(highlightedLines), "wordDiffLines": Double(wordDiffLines), "split": split ? 1 : 0, "wrapping": wrap ? 1 : 0]
        if let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]), let value = String(data: data, encoding: .utf8) { view?.accessibilityValue = value }
    }
    private func footprint() -> UInt64 {
        var info = task_vm_info_data_t(), count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return status == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
#endif
