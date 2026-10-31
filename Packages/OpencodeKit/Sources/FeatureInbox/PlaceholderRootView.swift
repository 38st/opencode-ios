import SwiftUI

public struct PlaceholderRootView: View {
    private let version: String

    public init(version: String) {
        self.version = version
    }

    public var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text(verbatim: "Opencode")
                    .font(.largeTitle.bold())
                Text(localized("Version \(version)", comment: "%@ is the app version number"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ContentUnavailableView(localized("No servers yet"), systemImage: "server.rack")
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
