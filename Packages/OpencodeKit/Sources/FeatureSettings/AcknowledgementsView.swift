#if os(iOS)
import SwiftUI
import OCDesign

/// Settings → Acknowledgements: every third-party component the app ships, from the same list that generates
/// THIRD_PARTY_NOTICES.md, with each full licence text.
public struct AcknowledgementsView: View {
    private let acknowledgements = Acknowledgements.bundled()
    public init() {}
    public var body: some View {
        OCForm {
            OCSection {
                Text(localized("Opencode is free software under the GNU General Public License, version 3. It includes the components below, each under its own licence."))
                    .font(OCType.small).foregroundStyle(OCColor.textMuted)
            }
            ForEach(acknowledgements.sections) { section in
                OCSection(Self.title(section.id)) {
                    ForEach(section.items) { item in
                        NavigationLink {
                            LicenseTextView(item: item)
                        } label: {
                            VStack(alignment: .leading, spacing: OCSpacing.xs) {
                                Text(verbatim: item.name).font(OCType.body).foregroundStyle(OCColor.text)
                                Text(localized("\(item.version) · \(item.license)", comment: "A component's version, then its licence name"))
                                    .font(OCType.small).foregroundStyle(OCColor.textMuted)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityIdentifier("acknowledgement-\(item.name)")
                    }
                }
            }
        }
        .ocNavigationTitle(localized("Acknowledgements")).ocTheme()
    }

    static func title(_ section: String) -> String {
        switch section {
        case "libraries": localized("Libraries")
        case "grammars": localized("Syntax highlighting grammars")
        case "assets": localized("Fonts, icons and design")
        case "server": localized("Push plugin and relay", comment: "Components of the separately installed server plugin and push relay")
        default: section
        }
    }
}

private struct LicenseTextView: View {
    let item: Acknowledgements.Item
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OCSpacing.md) {
                Text(verbatim: item.copyright).font(OCType.body)
                Link(destination: item.url) { Text(verbatim: item.url.absoluteString).font(OCType.small) }
                Text(verbatim: Acknowledgements.licenseText(for: item) ?? item.license)
                    .font(OCType.code).textSelection(.enabled)
                    .environment(\.layoutDirection, .leftToRight)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(OCSpacing.xl).frame(maxWidth: OCLayout.readable, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .ocNavigationTitle(item.name).ocTheme()
    }
}
#endif
