import SwiftUI

public struct OCConfirmationSheet: View {
    let title: String
    let message: String
    let confirmTitle: String
    let cancel: () -> Void
    let confirm: () -> Void
    var detail: String?
    var destructive = true
    @State private var contentHeight: CGFloat = OCLayout.touchTarget
    public init(_ title: String, message: String, confirmTitle: String, cancel: @escaping () -> Void, confirm: @escaping () -> Void) {
        self.title = title; self.message = message; self.confirmTitle = confirmTitle; self.cancel = cancel; self.confirm = confirm
    }
    /// - Parameters:
    ///   - detail: exact text the action sends, shown verbatim.
    ///   - destructive: false for an action that changes nothing irreversibly by itself.
    public init(_ title: String, message: String, detail: String?, confirmTitle: String, destructive: Bool, cancel: @escaping () -> Void, confirm: @escaping () -> Void) {
        self.init(title, message: message, confirmTitle: confirmTitle, cancel: cancel, confirm: confirm)
        self.detail = detail; self.destructive = destructive
    }
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OCSpacing.lg) {
                Text(title).font(OCType.heading).accessibilityAddTraits(.isHeader)
                Text(message).font(OCType.body)
                if let detail {
                    Text(detail).font(OCType.code).textSelection(.enabled).padding(OCSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OCColor.layer2, in: RoundedRectangle(cornerRadius: OCRadius.md))
                        .accessibilityIdentifier("confirmationDetail")
                }
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
        Button(localized("Cancel"), action: cancel).buttonStyle(OCButtonStyle(.ghost))
        if destructive { Button(confirmTitle, role: .destructive, action: confirm).buttonStyle(OCButtonStyle(.danger)) }
        else { Button(confirmTitle, action: confirm).buttonStyle(OCButtonStyle()) }
    }
}
