#if os(iOS)
import SwiftUI
import OCSync
import OCDesign

struct SavedPromptReview: View {
    let store: ReadStore
    let sessionID: String
    @State private var editing: SavedPrompt?
    @State private var text = ""
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: OCSpacing.sm) {
            ForEach(store.savedPrompts.filter { $0.sessionID == sessionID && $0.state != "pending" }) { prompt in
                OCPromptDock {
                    VStack(alignment: .leading, spacing: OCSpacing.sm) {
                        Text(prompt.state == "needsConfirmation" ? (prompt.operation == "create" ? localized("Create this saved session?") : localized("Send this saved prompt?")) : localized("This prompt was not sent.")).font(OCType.button)
                        Text(prompt.text).font(OCType.small).lineLimit(3)
                        if prompt.state == "needsConfirmation" {
                            Text(localized("Saved more than 10 minutes ago. It will only be sent if you choose Send.")).font(OCType.small).foregroundStyle(OCColor.textMuted)
                            Button(prompt.operation == "create" ? localized("Create saved session") : localized("Send saved prompt")) { run { try await store.confirmOutbox(prompt.id) } }.buttonStyle(OCButtonStyle(.contrast))
                        } else if prompt.operation == "prompt" {
                            Button(localized("Edit and resend")) { text = prompt.text; editing = prompt }.buttonStyle(OCButtonStyle(.contrast))
                        }
                        Button(prompt.operation == "create" ? localized("Discard session and saved prompts") : localized("Discard", comment: "Button that discards an unsent saved prompt")) { run { try await store.discardOutbox(prompt.id) } }.buttonStyle(OCButtonStyle(.ghost))
                    }
                }
            }
            if let error { Text(error).font(OCType.small).foregroundStyle(OCColor.danger) }
        }.sheet(item: $editing) { prompt in
            OCForm {
                Text(localized("Edit and resend")).font(OCType.heading)
                TextField(localized("Prompt", comment: "Placeholder for the prompt text field"), text: $text, axis: .vertical).textFieldStyle(OCTextFieldStyle())
                Button(localized("Resend")) { run { try await store.editSavedPrompt(prompt.id, text: text); editing = nil } }.buttonStyle(OCButtonStyle(.contrast))
                if let error { Text(error).font(OCType.small).foregroundStyle(OCColor.danger) }
            }.ocSheet()
        }.onDisappear { task?.cancel() }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard task == nil else { return }
        task = Task {
            defer { task = nil }
            do { try await operation(); error = nil }
            catch WriteStoreError.stagedRevertNeedsConfirmation { self.error = localized("The staged undo changed. Review and confirm it before resending.") }
            catch { self.error = localized("Could not update the saved prompt. Try again.") }
        }
    }
}
#endif
