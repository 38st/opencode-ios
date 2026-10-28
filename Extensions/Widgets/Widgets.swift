import ActivityKit
import OCActivity
import SwiftUI
import WidgetKit

@main struct OpencodeWidgets: WidgetBundle {
    var body: some Widget {
        SessionActivity()
        NeedsYouWidget()
        RunningWidget()
        RecentWidget()
        NewPromptControl()
        ReviewApprovalControl()
    }
}
struct SessionActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            SessionActivityView(attributes: context.attributes, state: context.state, stale: context.isStale)
                .widgetURL(context.attributes.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    SessionActivityView(attributes: context.attributes, state: context.state, stale: context.isStale)
                }
            } compactLeading: {
                SessionActivityGlyph(state: context.state)
            } compactTrailing: {
                SessionActivityCompact(state: context.state)
            } minimal: {
                SessionActivityGlyph(state: context.state)
            }.widgetURL(context.attributes.url)
        }
    }
}
