#if os(iOS)
import SwiftUI
import Foundation
import OCModels
import OCSync
import OCDesign

struct ModelPicker: View {
    let model: ComposerModel
    let history: [String]
    let select: (ModelInfo) -> Void
    @State private var query = ""
    @State private var showAll = false
    @Environment(\.dismiss) private var dismiss
    private var groups: [ModelGroup] {
        ComposerPickers.groups(model.catalog.models.value ?? [], providers: model.catalog.providers.value ?? [], query: query, showAll: showAll, recent: history)
    }
    var body: some View {
        NavigationStack {
            List {
                Toggle(localized("Show all models"), isOn: $showAll).font(OCType.small).listRowBackground(OCColor.background)
                if groups.isEmpty { Text(localized("No model results")).font(OCType.small).foregroundStyle(OCColor.textMuted).listRowBackground(OCColor.background) }
                ForEach(groups) { group in
                    Section(group.name) {
                        ForEach(group.models) { value in
                            Button { select(value) } label: {
                                VStack(alignment: .leading, spacing: OCSpacing.sm) {
                                    HStack {
                                        Text(value.name.replacingOccurrences(of: "(latest)", with: "").trimmingCharacters(in: .whitespaces)).font(OCType.body)
                                        Spacer(minLength: OCSpacing.sm)
                                        if selected(value) { OCIcon("check").accessibilityHidden(true) }
                                    }
                                    Text(value.id).font(OCType.micro).foregroundStyle(OCColor.textMuted)
                                    ViewThatFits(in: .horizontal) {
                                        HStack { badges(value) }
                                        VStack(alignment: .leading) { badges(value) }
                                    }
                                    if let cost = value.cost.first {
                                        Text(localized("\(price(cost.input)) input · \(price(cost.output)) output / 1M tokens", comment: "Model prices per million tokens; both placeholders are prices"))
                                            .font(OCType.micro).foregroundStyle(OCColor.textMuted)
                                    }
                                }.frame(maxWidth: .infinity, minHeight: OCLayout.touchTarget, alignment: .leading)
                            }.buttonStyle(.plain).listRowBackground(OCColor.background).accessibilityIdentifier("model-" + ComposerPickers.key(value))
                                .accessibilityAddTraits(selected(value) ? .isSelected : [])
                        }
                    }
                }
            }.listStyle(.plain).scrollContentBackground(.hidden).background(OCColor.background)
                .searchable(text: $query, prompt: localized("Search models")).navigationTitle(localized("Choose model")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(localized("Done")) { dismiss() } } }
        }.ocTheme().frame(minWidth: 300, idealWidth: 440, idealHeight: 540)
    }
    @ViewBuilder private func badges(_ value: ModelInfo) -> some View {
        ForEach(ComposerPickers.badges(value, defaultModel: model.catalog.defaultModel.value.flatMap { $0 }), id: \.self) { OCBadge($0) }
    }
    private func price(_ value: Double) -> String { value.formatted(.currency(code: "USD").precision(.fractionLength(0...4))) }
    private func selected(_ value: ModelInfo) -> Bool {
        model.effectiveModel.map { ComposerPickers.key($0) == ComposerPickers.key(value) } ?? false
    }
}
#endif
