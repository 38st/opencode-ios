#if os(iOS)
import SwiftUI
import OCModels
import OCFoundation
import OCSync
import OCDesign
import OCRender

struct SessionTimeline: View {
    let store: ReadStore
    let session: SessionModel
    let transcript: TranscriptModel
    let detail: TimelineDetail
    let requestID: String?
    let openChild: (String) -> Void
    let openRoot: (String) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var phase
    @State private var rows: [TimelineRow] = []
    @State private var control = TimelineScrollControl()
    @State private var nearBottom = true
    @State private var unseen = 0
    @State private var pendingScrollDone = false
    @State private var pageTask: Task<Void, Never>?
    @State private var error: String?
    private struct RunStamp: Equatable { let sessionID: String; let working: Bool }
    private var working: Bool { session.status.isRunning || store.running.contains(session.id) }
    var body: some View {
        VStack(spacing: 0) {
            if let error { Text(error).font(OCType.small).foregroundStyle(OCColor.danger).ocAnnounce(error, initial: true) }
            TimelineCollection(rows: rows, store: store, session: session, transcript: transcript, detail: detail,
                working: working, control: control,
                openChild: openChild, openRoot: openRoot, atBottom: { value in
                    nearBottom = value
                    if value { unseen = 0 }
                }, reachedTop: loadOlder, scheme: scheme, typeSize: typeSize, phase: phase,
                hasHistory: transcript.olderCursor != nil, loadingHistory: transcript.loadingOlder)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !nearBottom {
                        OCJumpToLatest(count: unseen) { control.jumpToLatest(); nearBottom = true; unseen = 0 }
                            .padding(OCSpacing.sm)
                    }
                }
                .background {
                    TimelineProjection(store: store, session: session, transcript: transcript, detail: detail, rows: $rows).equatable()
                    TimelineTailActivity(transcript: transcript) {
                        if nearBottom { control.followLatest() }
                        else if unseen == 0 { unseen = 1 }
                    }
                }
                .onChange(of: rows) { old, next in
                    if !nearBottom { unseen += Self.appendedRowCount(previous: old, next: next) }
                    scrollToRequest()
                }
                .onChange(of: requestID) { _, _ in pendingScrollDone = false; scrollToRequest() }
                .onChange(of: RunStamp(sessionID: session.id, working: working)) { old, next in
                    // The Working… row disappears silently, so say how the run ended.
                    if old.sessionID == next.sessionID && old.working && !next.working { OCAnnouncer.post(TimelineAnnouncement.runEnded(rows: rows)) }
                }
                .onDisappear { pageTask?.cancel(); control.cancel() }
        }
    }
    static func appendedRowCount(previous: [TimelineRow], next: [TimelineRow]) -> Int {
        let known = Set(previous.map(\.id))
        guard let lastKnown = next.lastIndex(where: { known.contains($0.id) }) else { return 0 }
        return next.count - lastKnown - 1
    }
    private func scrollToRequest() {
        guard let requestID, !pendingScrollDone else { return }
        let target = requestID == "error" ? rows.last(where: { $0.kind == .error })?.id : rows.first(where: { $0.id == requestID })?.id
        if let target {
            control.show(target); nearBottom = false; pendingScrollDone = true
        }
    }
    private func loadOlder() {
        guard transcript.olderCursor != nil, !transcript.loadingOlder, pageTask == nil else { return }
        pageTask = Task {
            defer { pageTask = nil }
            do { try await store.loadOlder(session.id); error = nil }
            catch is CancellationError {} catch { self.error = localized("Could not load earlier messages.") }
        }
    }
}

/// Observe live text separately so a delta does not invalidate the row container.
private struct TimelineTailActivity: View {
    let transcript: TranscriptModel
    let updated: () -> Void
    private var tailLength: Int {
        guard let id = transcript.order.last, let message = transcript.messages[id] else { return 0 }
        return message.items.last?.text.utf8.count ?? 0
    }
    var body: some View {
        Color.clear.frame(width: 0, height: 0).onChange(of: tailLength) { _, _ in updated() }
    }
}
#endif
