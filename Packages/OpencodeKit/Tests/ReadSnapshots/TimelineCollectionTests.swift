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

#if os(iOS)
@MainActor @Suite(.serialized) struct TimelineInteractionTests {
    @Test func externalScrollPausesFollowingAndViewportChangesPreserveIntent() async throws {
        let store = ReadStore(serverID: "timeline-test")
        let session = SessionModel(info: .init(raw: .object(["id": .string("s")])))
        let transcript = TranscriptModel(), control = TimelineScrollControl()
        var atBottom = true, reachedTop = 0
        let rows = (0..<80).map { TimelineRow(id: "row-\($0)", kind: .notice, text: "Earlier message \($0)") }
        func content(_ rows: [TimelineRow], history: Bool = false, loading: Bool = false) -> TimelineCollection {
            TimelineCollection(rows: rows, store: store, session: session, transcript: transcript, detail: .everything,
                working: false, control: control, openChild: { _ in }, openRoot: { _ in }, atBottom: { atBottom = $0 },
                reachedTop: { reachedTop += 1 }, hasHistory: history, loadingHistory: loading)
        }
        let initial = content(rows, history: true), coordinator = initial.makeCoordinator()
        let view = initial.makeCollection(coordinator: coordinator)
        defer { control.cancel() }
        #expect(view.keyboardDismissMode == .interactive)
        view.frame = CGRect(x: 0, y: 0, width: 393, height: 600)
        coordinator.update(initial)
        try await settled(coordinator)
        #expect(coordinator.ids.first == .history)
        control.jumpToLatest(); view.layoutIfNeeded()
        #expect(control.following)
        for height: CGFloat in [300, 200, 600] {
            view.frame.size.height = height; view.layoutIfNeeded()
            #expect(abs(view.contentOffset.y - max(0, view.contentSize.height - height)) < 1)
            #expect(control.following)
        }
        // Offset changes from layout or self-sizing are not user intent and keep following.
        let bottom = view.contentOffset.y
        view.setContentOffset(CGPoint(x: 0, y: bottom - 200), animated: false)
        #expect(control.following)
        view.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
        // Hardware keyboard scrolls animate and end without touch flags; VoiceOver uses accessibilityScroll.
        view.setContentOffset(CGPoint(x: 0, y: 100), animated: false)
        coordinator.scrollViewDidEndScrollingAnimation(view)
        #expect(!view.isDragging && !view.isDecelerating && !view.isTracking)
        #expect(!control.following && !atBottom && reachedTop > 0)
        let offset = view.contentOffset.y
        view.frame.size.height = 300; view.layoutIfNeeded()
        #expect(abs(view.contentOffset.y - offset) < 1 && !control.following)
        coordinator.update(content(rows + [.init(id: "new", kind: .notice, text: "New activity")], history: true, loading: true))
        try await settled(coordinator)
        try await Task.sleep(for: .milliseconds(150))
        #expect(!control.following && !atBottom)
        #expect(abs(view.contentOffset.y - offset) < 1)
        let anchorPath = try #require(view.indexPathsForVisibleItems.sorted().first { coordinator.source?.itemIdentifier(for: $0)?.rowID != nil })
        let anchorID = try #require(coordinator.source?.itemIdentifier(for: anchorPath))
        let anchorOffset = try #require(view.layoutAttributesForItem(at: anchorPath)).frame.minY - view.contentOffset.y
        coordinator.update(content(rows))
        try await settled(coordinator)
        #expect(!coordinator.ids.contains(.history))
        let newPath = IndexPath(item: try #require(coordinator.ids.firstIndex(of: anchorID)), section: 0)
        let newOffset = try #require(view.layoutAttributesForItem(at: newPath)).frame.minY - view.contentOffset.y
        #expect(abs(newOffset - anchorOffset) < 1)
        control.jumpToLatest(); view.layoutIfNeeded()
        let cell = try #require(view.visibleCells.first)
        NotificationCenter.default.post(name: UIAccessibility.elementFocusedNotification, object: nil,
                                        userInfo: [UIAccessibility.focusedElementUserInfoKey: cell])
        #expect(control.accessibilityFocused && !control.following && !atBottom)
        control.followLatest()
        try await Task.sleep(for: .milliseconds(150))
        #expect(!control.following)
        control.jumpToLatest()
        #expect(control.following && !control.accessibilityFocused)
        await store.stop()
    }
    private func settled(_ coordinator: TimelineCollection.Coordinator) async throws {
        for _ in 0..<200 {
            if !coordinator.applying { coordinator.view?.layoutIfNeeded(); return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timeline did not finish applying rows")
    }
}
#endif
