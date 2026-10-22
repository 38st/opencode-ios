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
                        Text(prompt.state == "needsConfirmation" ? (prompt.operation == "create" ? "Create this saved session?" : "Send this saved prompt?") : "This prompt was not sent.").font(OCType.button)
                        Text(prompt.text).font(OCType.small).lineLimit(3)
                        if prompt.state == "needsConfirmation" {
                            Text("Saved more than 10 minutes ago. It will only be sent if you choose Send.").font(OCType.small).foregroundStyle(OCColor.textMuted)
                            Button(prompt.operation == "create" ? "Create saved session" : "Send saved prompt") { run { try await store.confirmOutbox(prompt.id) } }.buttonStyle(OCButtonStyle(.contrast))
                        } else if prompt.operation == "prompt" {
                            Button("Edit and resend") { text = prompt.text; editing = prompt }.buttonStyle(OCButtonStyle(.contrast))
                        }
                        Button(prompt.operation == "create" ? "Discard session and saved prompts" : "Discard") { run { try await store.discardOutbox(prompt.id) } }.buttonStyle(OCButtonStyle(.ghost))
                    }
                }
            }
            if let error { Text(error).font(OCType.small).foregroundStyle(OCColor.danger) }
        }.sheet(item: $editing) { prompt in
            OCForm {
                Text("Edit and resend").font(OCType.heading)
                TextField("Prompt", text: $text, axis: .vertical).textFieldStyle(OCTextFieldStyle())
                Button("Resend") { run { try await store.editSavedPrompt(prompt.id, text: text); editing = nil } }.buttonStyle(OCButtonStyle(.contrast))
                if let error { Text(error).font(OCType.small).foregroundStyle(OCColor.danger) }
            }.ocSheet()
        }.onDisappear { task?.cancel() }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard task == nil else { return }
        task = Task {
            defer { task = nil }
            do { try await operation(); error = nil }
            catch WriteStoreError.stagedRevertNeedsConfirmation { self.error = "The staged undo changed. Review and confirm it before resending." }
            catch { self.error = "Could not update the saved prompt. Try again." }
        }
    }
}
#endif
