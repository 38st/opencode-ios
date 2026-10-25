#if os(iOS)
import SwiftUI
import OCModels
import OCDesign

// Inline pickers give the menus the system checkmark and the selected trait for the current choice.
struct AgentOptions: View {
    let agents: [AgentInfo]
    let selected: String
    let select: (String) -> Void
    var body: some View {
        Picker("Agent", selection: Binding(get: { selected }, set: select)) {
            ForEach(ComposerPickers.agents(agents)) { agent in
                Text(agent.name).foregroundStyle(OCMentionStyle.agentAccent(agent.color)).tag(ComposerPickers.agentID(agent))
            }
        }.pickerStyle(.inline).labelsHidden()
    }
}
struct VariantOptions: View {
    let variants: [ModelVariant]
    /// `nil` and "default" both mean the model's default variant.
    let selected: String?
    let select: (String?) -> Void
    var body: some View {
        Picker("Variant", selection: Binding(get: { selected == "default" ? nil : selected }, set: select)) {
            Text("Default").tag(String?.none)
            ForEach(variants.filter { $0.id != "default" }) { variant in Text(variant.id).tag(Optional(variant.id)) }
        }.pickerStyle(.inline).labelsHidden()
    }
}
struct SendOptions: View {
    let alternate: String
    let sendAlternate: () -> Void
    let interrupt: () -> Void
    var body: some View {
        Button(alternate, action: sendAlternate)
        Button("Interrupt and send", action: interrupt)
    }
}
enum SessionMenuAction { case rename, fork, compact, undo, redo, delete }
struct SessionMenuOptions: View {
    let canRedo: Bool
    let select: (SessionMenuAction) -> Void
    var body: some View {
        Button("Rename") { select(.rename) }
        Button("Fork from message") { select(.fork) }
        Button("Compact session") { select(.compact) }
        Button("Undo last message") { select(.undo) }
        Button("Redo last message") { select(.redo) }.disabled(!canRedo)
        Divider()
        Button("Delete session", role: .destructive) { select(.delete) }
    }
}
#endif
