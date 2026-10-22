#if os(iOS)
import SwiftUI
import OCDesign

struct WorkspacePlaceholder: View {
    let title: String
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: OCSpacing.sm) {
                OCIcon("bubble-5").foregroundStyle(OCColor.iconMuted)
                Text(title).font(OCType.button).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }.padding(OCSpacing.lg)
            ScrollView {
                VStack(spacing: OCSpacing.md) {
                    OCIcon("bubble-5", size: 32).foregroundStyle(OCColor.iconMuted)
                    Text("Your conversation appears here").font(OCType.heading)
                    Text("Choose a conversation from Home to follow its progress.")
                        .font(OCType.small).foregroundStyle(OCColor.textMuted)
                }.multilineTextAlignment(.center).padding(OCSpacing.xl).frame(maxWidth: .infinity)
                    .padding(.top, OCSpacing.section)
            }.frame(maxHeight: .infinity)
            OCDisabledPromptDock().padding(OCSpacing.md)
        }.background(OCColor.background).clipShape(RoundedRectangle(cornerRadius: OCRadius.xl))
    }
}
#endif
