#if os(iOS)
import Foundation
import SwiftUI
import OCFoundation
import OCModels
import OCDesign

public enum FormSheetState: String, CaseIterable { case editing, invalid, review, dismiss, sending, failed, settled }

public struct FormRenderer: View {
    let form: FormInfo
    @Binding var answers: [String: JSONValue]
    let showErrors: Bool
    @State private var custom: Set<String> = []
    @State private var customText: [String: String] = [:]
    @State private var numericText: [String: String] = [:]
    public init(form: FormInfo, answers: Binding<[String: JSONValue]>, showErrors: Bool = false) {
        self.form = form; _answers = answers; self.showErrors = showErrors
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: OCSpacing.xl) {
            ForEach(Array(FormValidation.visibleFields(form, answers: answers).enumerated()), id: \.offset) { _, field in
                VStack(alignment: .leading, spacing: OCSpacing.sm) {
                    Text((field.fields.title ?? field.fields.key) + (field.fields.required ? " *" : "")).font(OCType.heading)
                        .accessibilityLabel((field.fields.title ?? field.fields.key) + (field.fields.required ? ", " + localized("required", comment: "VoiceOver: this form field must be answered") : ""))
                        .accessibilityAddTraits(.isHeader)
                    if let description = field.fields.description { Text(description).font(OCType.body).foregroundStyle(OCColor.textMuted) }
                    control(field)
                    if showErrors, let error = FormValidation.errors(form, answers: answers)[field.fields.key] {
                        Text(error).font(OCType.small).foregroundStyle(OCColor.danger).accessibilityIdentifier("formError-" + field.fields.key)
                    }
                }
            }
        }
    }
    @ViewBuilder private func control(_ field: FormField) -> some View {
        let f = field.fields
        switch field {
        case .string:
            if !f.options.isEmpty {
                Text(localized("Select one answer")).font(OCType.small).foregroundStyle(OCColor.textMuted)
                options(field, multiple: false)
            }
            if f.options.isEmpty || custom.contains(f.key) || (f.custom && isCustom(field)) {
                TextField(f.placeholder ?? localized("Type your answer…"), text: text(f.key), axis: .vertical)
                    .textFieldStyle(OCTextFieldStyle()).accessibilityIdentifier("formField-" + f.key)
            }
        case .multiselect:
            Text(localized("Select all answers that apply")).font(OCType.small).foregroundStyle(OCColor.textMuted)
            options(field, multiple: true)
            if f.custom && custom.contains(f.key) {
                TextField(localized("Type your own answer…"), text: Binding(get: { customText[f.key] ?? "" }, set: { customText[f.key] = $0 }))
                    .textFieldStyle(OCTextFieldStyle())
                Button(localized("Add answer")) {
                    let value = (customText[f.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return }
                    var values = answers[f.key]?.arrayValue ?? []
                    if !values.contains(.string(value)) { values.append(.string(value)); answers[f.key] = .array(values) }
                    customText[f.key] = ""
                }.buttonStyle(OCButtonStyle(.neutral))
            }
            ForEach((answers[f.key]?.arrayValue ?? []).compactMap(\.stringValue).filter { value in !f.options.contains { $0.value == value } }, id: \.self) { value in
                Button { toggle(value, key: f.key) } label: { OCLabel(value, icon: "check") }.buttonStyle(OCButtonStyle(.neutral))
            }
        case .number, .integer:
            TextField(field.type == "integer" ? localized("Whole number") : localized("Number", comment: "Placeholder for a numeric form field"), text: Binding(get: {
                if let text = numericText[f.key] { return text }
                if let text = answers[f.key]?.stringValue { return text }
                return answers[f.key]?.doubleValue.map { value in
                    let text = String(value)
                    return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
                } ?? ""
            }, set: { value in
                // Preserve intermediate edits such as "1." until the next digit.
                numericText[f.key] = value
                if value.isEmpty { answers.removeValue(forKey: f.key) }
                else { answers[f.key] = Double(value).map(JSONValue.number) ?? .string(value) }
            })).keyboardType(.numbersAndPunctuation).textFieldStyle(OCTextFieldStyle()).accessibilityIdentifier("formField-" + f.key)
        case .boolean:
            HStack {
                choice(localized("Yes"), selected: answers[f.key]?.boolValue == true) { answers[f.key] = .bool(true) }
                choice(localized("No"), selected: answers[f.key]?.boolValue == false) { answers[f.key] = .bool(false) }
            }
        case .external:
            if let raw = f.url, let url = URL(string: raw), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                Link(destination: url) { OCLabel(localized("Open \(url.host ?? raw)", comment: "%@ is a website host name"), icon: "square-arrow-top-right") }.buttonStyle(OCButtonStyle(.neutral))
                Text(raw).font(OCType.code).ocSelectableText(raw)
                OCToggleRow(localized("I completed this step"), isOn: Binding(get: { answers[f.key]?.boolValue == true }, set: { answers[f.key] = .bool($0) }))
            } else { Text(localized("This external URL cannot be opened.")).font(OCType.small).foregroundStyle(OCColor.danger) }
        default:
            Text(localized("This field needs a newer client. You can dismiss the request with a reason.")).font(OCType.small).foregroundStyle(OCColor.danger)
            CodeBlockView((try? field.raw.prettyPrinted()) ?? "", language: "json")
        }
    }
    private func options(_ field: FormField, multiple: Bool) -> some View {
        let f = field.fields
        return VStack(alignment: .leading, spacing: OCSpacing.sm) {
            ForEach(f.options, id: \.value) { option in
                let selected = multiple ? (answers[f.key]?.arrayValue?.contains(.string(option.value)) ?? false) : answers[f.key]?.stringValue == option.value
                choice(option.label, description: option.description, selected: selected) {
                    if multiple { toggle(option.value, key: f.key) }
                    else { custom.remove(f.key); answers[f.key] = .string(option.value) }
                }.accessibilityIdentifier("formOption-" + f.key + "-" + option.value)
            }
            if f.custom {
                choice(localized("Other", comment: "Option for typing a custom answer"), selected: custom.contains(f.key) || isCustom(field)) {
                    custom.insert(f.key)
                    if !multiple { answers[f.key] = .string("") }
                }
            }
        }
    }
    private func choice(_ title: String, description: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: OCSpacing.sm) {
                OCIcon("check", size: 16).opacity(selected ? 1 : 0).foregroundStyle(selected ? OCColor.accent : OCColor.iconMuted)
                VStack(alignment: .leading, spacing: OCSpacing.xs) {
                    Text(title).font(OCType.button)
                    if let description { Text(description).font(OCType.small).foregroundStyle(OCColor.textMuted) }
                }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            }.fixedSize(horizontal: false, vertical: true)
        }.buttonStyle(OCButtonStyle(.neutral)).fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func toggle(_ value: String, key: String) {
        var values = answers[key]?.arrayValue ?? []
        if values.contains(.string(value)) { values.removeAll { $0 == .string(value) } } else { values.append(.string(value)) }
        answers[key] = .array(values)
    }
    private func text(_ key: String) -> Binding<String> {
        Binding(get: { answers[key]?.stringValue ?? "" }, set: { answers[key] = .string($0) })
    }
    private func isCustom(_ field: FormField) -> Bool {
        guard let value = answers[field.fields.key]?.stringValue, !value.isEmpty else { return false }
        return !field.fields.options.contains { $0.value == value }
    }
}
#endif
