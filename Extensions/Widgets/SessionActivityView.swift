import AppIntents
import OCActivity
import OCIntents
import SwiftUI
import WidgetKit

struct SessionActivityView: View {
    let attributes: SessionActivityAttributes
    let state: SessionActivityAttributes.ContentState
    var stale = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if typeSize.isAccessibilitySize {
                heading
                Text(stale ? String(localized: "Open for status") : state.label).font(.subheadline)
            } else {
                HStack(alignment: .top) {
                    heading
                    Spacer(minLength: 8)
                    Text(stale ? String(localized: "Open for status") : state.label).font(.subheadline)
                }
            }
            HStack {
                Text("Step \(state.step)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let url = attributes.url { Link("Open", destination: url) }
                if !state.isFinal { Button("Stop", intent: StopSessionIntent(server: attributes.serverID, session: attributes.sessionID)) }
            }
        }.padding(16)
    }
    private var heading: some View {
        HStack(alignment: .top) {
            Image(systemName: state.symbol).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(attributes.title).font(.headline).lineLimit(2)
                Text(attributes.project).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct SessionActivityCompact: View {
    let state: SessionActivityAttributes.ContentState
    var body: some View { Text(state.label).font(.caption2).lineLimit(1) }
}
struct SessionActivityGlyph: View {
    let state: SessionActivityAttributes.ContentState
    var body: some View { Image(systemName: state.symbol) }
}
