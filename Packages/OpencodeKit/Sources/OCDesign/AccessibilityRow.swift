import SwiftUI

/// A custom action VoiceOver offers on a grouped row (copy, open, expand and the like).
public struct OCAccessibilityAction: Identifiable {
    public let name: String
    public let perform: () -> Void
    public var id: String { name }
    public init(_ name: String, perform: @escaping () -> Void) { self.name = name; self.perform = perform }
}

public extension View {
    /// With VoiceOver, the row is one element: `label` when given, otherwise its children's text combined; its
    /// controls and `actions` become custom actions. Without VoiceOver (Voice Control, Switch Control, UI automation)
    /// every control stays its own element, so it can still be named and tapped directly. `grouped: false` keeps the
    /// children apart under VoiceOver too, for rows whose header is already the one element (tool rows).
    func ocAccessibilityRow(_ label: String? = nil, actions: [OCAccessibilityAction] = [], grouped: Bool = true) -> some View {
        modifier(AccessibilityRow(label: label, actions: actions, grouped: grouped))
    }
}

private struct AccessibilityRow: ViewModifier {
    let label: String?
    let actions: [OCAccessibilityAction]
    let grouped: Bool
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: voiceOver && grouped ? .combine : .contain)
            .accessibilityLabel(label ?? "", isEnabled: voiceOver && grouped && label != nil)
            .accessibilityActions {
                if voiceOver && grouped { ForEach(actions) { action in Button(action.name, action: action.perform) } }
            }
    }
}
