#if os(iOS)
import Foundation
import SwiftUI
import UIKit
import Testing
import OCFoundation
import OCModels
import OCRender
@testable import OCSync
@testable import FeatureTranscript

extension ReadPerformanceTests {
    @Test func jumpCountExcludesPrependedHistory() {
        func row(_ id: String) -> TimelineRow { .init(id: id, kind: .notice) }
        let previous = [row("a"), row("b")]
        #expect(SessionTimeline.appendedRowCount(previous: previous, next: [row("older")] + previous) == 0)
        #expect(SessionTimeline.appendedRowCount(previous: previous, next: [row("older")] + previous + [row("new")]) == 1)
        #expect(SessionTimeline.appendedRowCount(previous: [], next: previous) == 0)
    }
    @Test func renderedFiveThousandRowsAndPrependAnchor() async throws {
        let before = physicalFootprint()
        let sampleMessages = messages(5_000)
        let transcript = TranscriptModel(messages: sampleMessages)
        let session = SessionModel(info: .init(raw: .object(["id": .string("performance")])))
        let rows = await TimelineRowBuilder().build(sampleMessages, detail: .everything)
        let store = ReadStore(serverID: "performance"), control = TimelineScrollControl()
        func content(_ rows: [TimelineRow]) -> TimelineCollection {
            TimelineCollection(rows: rows, store: store, session: session, transcript: transcript, detail: .everything,
                working: false, control: control, openChild: { _ in }, openRoot: { _ in }, atBottom: { _ in }, reachedTop: {})
        }
        // Hostless tests exercise the same collection and hosting configurations as the screen.
        let initial = content(rows), coordinator = initial.makeCoordinator()
        let view = initial.makeCollection(coordinator: coordinator)
        view.frame = CGRect(x: 0, y: 0, width: 393, height: 700)
        coordinator.update(initial)
        defer { control.cancel() }
        try await collectionSettled { control.coordinator?.ids.count == 5_000 && control.coordinator?.applying == false }
        view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        #expect(view.visibleCells.count > 0 && view.visibleCells.count < 100)
        let footprint = physicalFootprint()
        #expect(footprint < 250 * 1_024 * 1_024, "Rendered collection must stay within the 250 MiB session budget")
        try record(["rendered_5000_footprint_mb": Double(footprint) / 1_024 / 1_024,
                    "rendered_5000_incremental_mb": Double(footprint > before ? footprint - before : 0) / 1_024 / 1_024,
                    "visible_cells": Double(view.visibleCells.count)], name: "collection")
        control.following = false
        view.setContentOffset(CGPoint(x: 0, y: 500), animated: false); view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        let oldPath = try #require(view.indexPathsForVisibleItems.sorted().first)
        let id = try #require(coordinator.source?.itemIdentifier(for: oldPath))
        let oldFrame = try #require(view.layoutAttributesForItem(at: oldPath)?.frame)
        let oldOffset = oldFrame.minY - view.contentOffset.y
        let older = (0..<20).map { TimelineRow(id: "older-\($0)", kind: .notice, text: "Earlier message \($0)") }
        // A malformed duplicate row must not crash the diffable data source.
        coordinator.update(content(older + older.prefix(1) + rows))
        try await collectionSettled { coordinator.ids.count == 5_020 && !coordinator.applying }
        try await Task.sleep(for: .milliseconds(200))
        let newIndex = try #require(coordinator.ids.firstIndex(of: id))
        let newFrame = try #require(view.layoutAttributesForItem(at: IndexPath(item: newIndex, section: 0))?.frame)
        #expect(abs(newFrame.minY - view.contentOffset.y - oldOffset) < 1)
        control.show("older-5")
        try await Task.sleep(for: .milliseconds(100))
        #expect(view.indexPathsForVisibleItems.contains { coordinator.source?.itemIdentifier(for: $0) == .row("older-5") })
        await store.stop()
    }
    private func collectionSettled(_ ready: () -> Bool) async throws {
        for _ in 0..<200 {
            if ready() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The collection did not finish applying its rows")
    }
}
#endif
