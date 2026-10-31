#if os(iOS)
import SwiftUI
import OCModels
import OCSync
import OCDesign

public struct PendingInputPanel: View {
    let store: ReadStore
    let session: SessionModel
    @State private var acting = false
    @State private var error: String?
    @State private var contentHeight: CGFloat = OCLayout.touchTarget
    @Environment(\.dynamicTypeSize) private var typeSize
    public init(store: ReadStore, session: SessionModel) { self.store = store; self.session = session }
    private var rows: [InboxItem] {
        let saved = Set(store.savedPrompts.map(\.id))
        return session.pending.filter { $0.type == "user" && $0.delivery == .queue && !saved.contains($0.id) }
    }
    private var saved: [SavedPrompt] { store.savedPrompts.filter { $0.sessionID == session.id } }
    public var body: some View {
        if !rows.isEmpty || !saved.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if rows.count > 3 { Text(localized("\(rows.count) queued", comment: "%lld is the number of queued prompts")).font(OCType.micro).foregroundStyle(OCColor.textMuted).padding(OCSpacing.sm) }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(rows, id: \.id) { item in queueRow(item) }
                        ForEach(saved) { item in outboxRow(item) }
                    }.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }.scrollDismissesKeyboard(.interactively)
                    .frame(maxHeight: min(contentHeight, typeSize.isAccessibilitySize ? 350 : OCLayout.touchTarget * 4))
                if let error { Text(error).font(OCType.small).foregroundStyle(OCColor.danger).padding(OCSpacing.sm) }
            }.background(OCColor.background, in: RoundedRectangle(cornerRadius: OCRadius.dock))
                .overlay(RoundedRectangle(cornerRadius: OCRadius.dock).strokeBorder(OCColor.border, lineWidth: OCBorder.hairline).allowsHitTesting(false))
                .accessibilityElement(children: .contain).accessibilityIdentifier("pendingInputPanel").disabled(acting)
        }
    }
    private func queueRow(_ item: InboxItem) -> some View {
        row {
            Text(item.fields.payload.text.isEmpty ? localized("Attachments") : item.fields.payload.text).font(OCType.small).lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
        } controls: {
            Button(session.status.isRunning ? localized("Steer", comment: "Send a follow-up that redirects the running agent") : localized("Send", comment: "Sends the prompt")) { run { try await store.changeDelivery(session.id, itemID: item.id, delivery: .steer) } }
                .buttonStyle(OCButtonStyle(.ghost))
            OCIconButton(localized("Undo", comment: "Returns the queued prompt to the composer"), icon: "outline-undo") { run { try await store.cancelPending(session.id, itemID: item.id) } }
            OCIconButton(localized("Remove", comment: "Removes the queued prompt"), icon: "outline-xmark") { run { try await store.cancelPending(session.id, itemID: item.id, restore: false) } }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("queue-" + item.id)
    }
    private func outboxRow(_ item: SavedPrompt) -> some View {
        row {
            Text(item.text.isEmpty ? localized("New session") : item.text).font(OCType.small).lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
        } controls: {
            if item.state == "pending" { Text(store.offline ? localized("Waiting for connection") : localized("Sending", comment: "Status of a prompt being sent")).font(OCType.micro).foregroundStyle(OCColor.textMuted) }
            else if item.state == "failed" {
                Button(localized("Edit and resend")) { run { try await store.restoreFailedPrompt(item.id) } }.buttonStyle(OCButtonStyle(.ghost))
            } else {
                Text(localized("Waiting for confirmation")).font(OCType.micro)
                Button(localized("Send", comment: "Sends the prompt")) { run { try await store.confirmOutbox(item.id) } }.buttonStyle(OCButtonStyle(.ghost))
            }
            if item.state != "pending" { OCIconButton(localized("Discard", comment: "Discards the unsent prompt"), icon: "outline-xmark") { run { try await store.discardOutbox(item.id) } } }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("outbox-" + item.id)
    }
    private func row<Title: View, Controls: View>(@ViewBuilder title: () -> Title, @ViewBuilder controls: () -> Controls) -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: OCSpacing.sm) {
                    title()
                    HStack(spacing: OCSpacing.xs) { controls() }
                }.padding(.vertical, OCSpacing.sm)
            } else {
                HStack(spacing: OCSpacing.xs) { title(); Spacer(minLength: 0); controls() }
            }
        }.padding(.horizontal, OCSpacing.sm).frame(maxWidth: .infinity, minHeight: OCLayout.touchTarget, alignment: .leading)
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !acting else { return }
        acting = true
        store.performWrite(operation) { result in
            acting = false
            switch result {
            case .success: error = nil
            case .failure(let failure): if !WriteErrorMessage.isCancellation(failure) { error = WriteErrorMessage.message(failure) }
            }
        }
    }
}
#endif
