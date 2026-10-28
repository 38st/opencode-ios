// SwiftUI's Menu reports no presentation state on iOS. Chrome that switches layout, such as a session's compact
// header while the keyboard comes and goes, has to stay put while its menu is open or the menu closes as it opens.
#if os(iOS)
import SwiftUI
import UIKit

public struct OCMenuItem {
    public var title: String
    /// Nil makes the row information only: shown, but not something to choose.
    public var action: (@MainActor () -> Void)?
    public init(_ title: String, action: (@MainActor () -> Void)? = nil) { self.title = title; self.action = action }
}
/// A menu button whose open state is observable. SwiftUI draws the label; a clear UIKit button over it owns the
/// menu, its accessibility and the open state.
public struct OCMenuButton<Label: View>: View {
    let title: String
    let identifier: String
    let items: [OCMenuItem]
    @Binding var isOpen: Bool
    let label: Label
    public init(_ title: String, identifier: String, items: [OCMenuItem], isOpen: Binding<Bool>, @ViewBuilder label: () -> Label) {
        self.title = title; self.identifier = identifier; self.items = items; _isOpen = isOpen; self.label = label()
    }
    public var body: some View {
        label.accessibilityHidden(true)
            .overlay { MenuButtonHost(title: title, identifier: identifier, items: items, isOpen: $isOpen) }
    }
}

private struct MenuButtonHost: UIViewRepresentable {
    let title: String
    let identifier: String
    let items: [OCMenuItem]
    @Binding var isOpen: Bool
    func makeUIView(context: Context) -> MenuButton {
        let button = MenuButton(frame: .zero)
        button.showsMenuAsPrimaryAction = true
        button.isPointerInteractionEnabled = true
        return button
    }
    func updateUIView(_ button: MenuButton, context: Context) {
        button.accessibilityLabel = title
        button.accessibilityIdentifier = identifier
        button.opened = { [binding = $isOpen] open in if binding.wrappedValue != open { binding.wrappedValue = open } }
        button.actions = items.map(\.action)
        let rows = items.map { MenuButton.Row(title: $0.title, chooses: $0.action != nil) }
        guard button.rows != rows || button.menu == nil else { return }
        button.rows = rows
        button.menu = UIMenu(children: rows.indices.map { index in
            UIAction(title: rows[index].title, attributes: rows[index].chooses ? [] : .disabled) { [weak button] _ in
                guard let button, button.actions.indices.contains(index) else { return }
                button.actions[index]?()
            }
        })
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MenuButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 44, height: proposal.height ?? 44)
    }
}

final class MenuButton: UIButton {
    struct Row: Equatable { let title: String; let chooses: Bool }
    var opened: (Bool) -> Void = { _ in }
    var rows: [Row] = []
    var actions: [(@MainActor () -> Void)?] = []
    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willDisplayMenuFor configuration: UIContextMenuConfiguration,
                                         animator: (any UIContextMenuInteractionAnimating)?) {
        super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
        opened(true)
    }
    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willEndFor configuration: UIContextMenuConfiguration,
                                         animator: (any UIContextMenuInteractionAnimating)?) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        opened(false)
    }
}
#endif
