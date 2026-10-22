import SwiftUI
#if os(iOS)
import UIKit
#endif

private struct SelectableText: ViewModifier {
    let text: String
    @State private var selecting = false
    func body(content: Content) -> some View {
        Group {
            if #available(iOS 27, *) { content.textSelection(.enabled) }
            else {
                content.contextMenu {
                    Button("Select text") { selecting = true }
                    Button("Copy") { OCCopy.text(text) }
                }
            }
        }.sheet(isPresented: $selecting) { OCTextSelectionSheet(text: text).ocSheet() }
    }
}
public extension View {
    func ocSelectableText(_ text: String) -> some View { modifier(SelectableText(text: text)) }
}
public struct OCTextSelectionSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    public init(text: String) { self.text = text }
    public var body: some View {
        NavigationStack {
            Group {
                #if os(iOS)
                SelectionTextView(text: text)
                #else
                ScrollView { Text(text).font(OCType.body).textSelection(.enabled).padding(OCSpacing.lg) }
                #endif
            }.navigationTitle("Select text")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.buttonStyle(OCButtonStyle(.ghost)) }
                }.ocTheme()
        }
    }
}
#if os(iOS)
private struct SelectionTextView: UIViewRepresentable {
    let text: String
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false; view.isSelectable = true; view.dataDetectorTypes = []
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: OCSpacing.lg, left: OCSpacing.lg, bottom: OCSpacing.lg, right: OCSpacing.lg)
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        OCFonts.register()
        view.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont(name: "Inter-Regular", size: 14) ?? UIFont.preferredFont(forTextStyle: .body))
        view.textColor = UIColor(OCColor.text); view.backgroundColor = UIColor(OCColor.background)
        if view.text != text { view.text = text }
    }
}
#endif
