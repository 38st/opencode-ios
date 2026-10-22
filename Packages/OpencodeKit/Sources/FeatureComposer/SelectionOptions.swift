#if os(iOS)
import SwiftUI
import OCModels
import OCDesign

struct AgentOptions: View {
    let agents: [AgentInfo]
    let select: (String) -> Void
    var body: some View {
        ForEach(ComposerPickers.agents(agents)) { agent in
            Button { select(ComposerPickers.agentID(agent)) } label: {
                Text(agent.name).foregroundStyle(OCMentionStyle.agentAccent(agent.color))
            }
        }
    }
}
struct VariantOptions: View {
    let variants: [ModelVariant]
    let select: (String?) -> Void
    var body: some View {
        Button("Default") { select(nil) }
        ForEach(variants.filter { $0.id != "default" }) { variant in Button(variant.id) { select(variant.id) } }
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
