// Sources: packages/ui/src/components/{card,text-field,dock-surface}.css,
// overlays/dialog; packages/app/src/settings and shell/mobile-panel-drawer.css.
import SwiftUI

public struct OCCard<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        content.padding(OCSpacing.lg).frame(maxWidth: .infinity, alignment: .leading)
            .background(OCColor.background, in: RoundedRectangle(cornerRadius: OCRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: OCRadius.lg).strokeBorder(OCColor.border, lineWidth: OCBorder.hairline))
    }
}
public struct OCSection<Content: View>: View {
    let title: String?
    let content: Content
    public init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content()
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: OCSpacing.md) {
            if let title { OCSidebarHeader(title) }
            OCCard { VStack(alignment: .leading, spacing: OCSpacing.md) { content } }
        }
    }
}
public struct OCForm<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OCSpacing.xl) { content }
                .padding(OCSpacing.xl).frame(maxWidth: OCLayout.readable)
                .frame(maxWidth: .infinity, alignment: .top)
        }.background(OCColor.backgroundDeep).textFieldStyle(OCTextFieldStyle())
    }
}
public struct OCPromptDock<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        content.padding(OCSpacing.md).frame(maxWidth: .infinity, alignment: .leading)
            .background(OCColor.background, in: RoundedRectangle(cornerRadius: OCRadius.dock))
            .overlay(RoundedRectangle(cornerRadius: OCRadius.dock).strokeBorder(OCColor.border, lineWidth: OCBorder.hairline))
            .ocElevation(.raised)
    }
}
private struct ThemeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.font(OCType.body).foregroundStyle(OCColor.text).tint(OCColor.text)
            .textFieldStyle(OCTextFieldStyle())
            .background(OCColor.background)
    }
}
public extension View {
    func ocTheme() -> some View { modifier(ThemeModifier()) }
    func ocSheet() -> some View {
        self.presentationBackground(OCColor.backgroundDeep)
            .presentationCornerRadius(OCRadius.sheet).presentationDragIndicator(.visible).ocTheme()
    }
}
#Preview("Surfaces") {
    OCForm {
        OCSection("Server") { TextField("Name", text: .constant("Studio Mac")) }
        OCPromptDock { Text("Ask anything…").foregroundStyle(OCColor.textFaint) }
    }.ocTheme()
}

#if os(iOS)
private struct NavigationTitleModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let title: String
    func body(content: Content) -> some View {
        content.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(scheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title).font(OCType.heading).foregroundStyle(OCColor.text)
                }
            }
    }
}
public extension View {
    func ocNavigationTitle(_ title: String) -> some View { modifier(NavigationTitleModifier(title: title)) }
}
#endif
