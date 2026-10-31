#if os(iOS)
import SwiftUI
import OCModels
import OCFoundation
import OCSync
import OCRender

/// Observation invalidates this view for topology/metadata changes. Equatable keeps
/// scroll geometry updates out of the O(history) structural walk. Text is observed only by ContentRow.
struct TimelineProjection: View, Equatable {
    let store: ReadStore
    let session: SessionModel
    let transcript: TranscriptModel
    let detail: TimelineDetail
    @Binding var rows: [TimelineRow]
    @State private var builder = TimelineRowBuilder()
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.store === rhs.store && lhs.session === rhs.session && lhs.transcript === rhs.transcript && lhs.detail == rhs.detail
    }
    private var structure: Int {
        var hash = Hasher(); hash.combine(detail); hash.combine(transcript.order); hash.combine(session.pending.map(\.raw))
        hash.combine(session.info.revert?.messageID)
        for id in transcript.order {
            guard let message = transcript.messages[id] else { continue }
            hash.combine(message.fields.raw)
            for item in message.items { hash.combine(item.id); hash.combine(item.fields.raw) }
        }
        hash.combine(store.permissions[session.id]?.map(\.raw)); hash.combine(store.forms[.session(session.id)]?.map(\.raw))
        return hash.finalize()
    }

    var body: some View {
        Color.clear.frame(width: 0, height: 0).task(id: structure) {
            let visible = transcript.visibleOrder(revert: session.info.revert?.messageID, pending: session.pending)
            let messages = visible.compactMap { transcript.messages[$0]?.value }
            let next = await builder.build(messages, detail: detail, pending: pendingRows)
            guard !Task.isCancelled else { return }
            rows = next
        }
    }
    private var pendingRows: [TimelineRow] {
        let permissions = (store.permissions[session.id] ?? []).map {
            TimelineRow(id: $0.id, kind: .pendingInput, text: $0.action + "\n" + $0.resources.joined(separator: "\n"), badge: localized("Permission", comment: "Badge on a pending permission request in the timeline"))
        }
        let forms = (store.forms[.session(session.id)] ?? []).map { form in
            let questions = form.fields.map(\.fields).filter { !$0.hidden }.map { field in
                ([field.title, field.description].compactMap { $0 } + field.options.map(\.label)).joined(separator: "\n")
            }
            return TimelineRow(id: form.id, kind: .pendingInput, text: ([form.title] + questions).joined(separator: "\n\n"), badge: localized("Question", comment: "Badge on a pending question in the timeline"))
        }
        let queued = session.pending.filter { $0.type == "compaction" }.map {
            TimelineRow(id: "pending:" + $0.id, kind: .pendingInput, text: $0.fields.payload.text, badge: $0.type == "compaction" ? localized("Compaction queued") : localized("Queued"))
        }
        return permissions + forms + queued
    }

}
#endif
