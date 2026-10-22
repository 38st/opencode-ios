import SwiftUI

public struct OCConfirmationSheet: View {
    let title: String
    let message: String
    let confirmTitle: String
    let cancel: () -> Void
    let confirm: () -> Void
    @State private var contentHeight: CGFloat = OCLayout.touchTarget
    public init(_ title: String, message: String, confirmTitle: String, cancel: @escaping () -> Void, confirm: @escaping () -> Void) {
        self.title = title; self.message = message; self.confirmTitle = confirmTitle; self.cancel = cancel; self.confirm = confirm
    }
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OCSpacing.lg) {
                Text(title).font(OCType.heading).accessibilityAddTraits(.isHeader)
                Text(message).font(OCType.body)
                ViewThatFits(in: .horizontal) {
                    HStack { actions }
                    VStack(alignment: .leading) { actions }
                }
            }.padding(OCSpacing.xl).frame(maxWidth: OCLayout.readable, alignment: .leading).frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: { contentHeight = $0 }
        }.scrollBounceBehavior(.basedOnSize)
            .frame(idealHeight: contentHeight)
            .background(OCColor.background).ocTheme()
            .presentationSizing(.fitted)
            .presentationDetents([.height(contentHeight)])
    }
    @ViewBuilder private var actions: some View {
        Button("Cancel", action: cancel).buttonStyle(OCButtonStyle(.ghost))
        Button(confirmTitle, role: .destructive, action: confirm).buttonStyle(OCButtonStyle(.danger))
    }
}
