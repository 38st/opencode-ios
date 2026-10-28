import AppIntents
import OCIntents
import OCShared
import SwiftUI
import WidgetKit

/// Control Center, Lock Screen and Action button: a new session's composer in the last used project.
struct NewPromptControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.newPrompt.rawValue, provider: LastProject()) { project in
            ControlWidgetButton(action: NewPromptIntent()) {
                Label {
                    Text("New prompt")
                    // A project's name is redacted while locked, as in the widgets.
                    if let project { Text(project).privacySensitive() }
                } icon: { Image(systemName: "square.and.pencil") }
            }
        }
        .displayName("New prompt")
        .description("Open a new session's composer in the project you used last.")
    }
    struct LastProject: ControlValueProvider {
        var previewValue: String? { nil }
        func currentValue() async throws -> String? { ControlContent.newPromptProject(SessionsProvider.read()) }
    }
}

/// Opens the next waiting permission or question in the app, showing how many wait. It never answers one.
struct ReviewApprovalControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.reviewApproval.rawValue, provider: WaitingRequests()) { count in
            ControlWidgetButton(action: ReviewNextApprovalIntent()) {
                Label {
                    Text("Review approval")
                    Text(ControlContent.waitingText(count))
                } icon: { Image(systemName: count > 0 ? "checkmark.shield.fill" : "checkmark.shield") }
            }
        }
        .displayName("Review approval")
        .description("Open the next request that waits for your approval or answer.")
    }
    struct WaitingRequests: ControlValueProvider {
        var previewValue: Int { 0 }
        func currentValue() async throws -> Int { ControlContent.waitingRequests(SessionsProvider.pending()) }
    }
}
