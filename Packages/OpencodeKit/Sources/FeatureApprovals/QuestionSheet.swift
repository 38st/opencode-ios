#if os(iOS)
import Foundation
import SwiftUI
import OCFoundation
import OCModels
import OCDesign
import OCSync

public struct QuestionContent: View {
    let form: FormInfo
    @Binding var state: FormSheetState
    @Binding var answers: [String: JSONValue]
    @Binding var reason: String
    let submit: () -> Void
    let dismiss: () -> Void
    public init(form: FormInfo, state: Binding<FormSheetState>, answers: Binding<[String: JSONValue]>, reason: Binding<String>,
                submit: @escaping () -> Void, dismiss: @escaping () -> Void) {
        self.form = form; _state = state; _answers = answers; _reason = reason; self.submit = submit; self.dismiss = dismiss
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: OCSpacing.lg) {
            OCLabel("Question", icon: "bubble-5").font(OCType.heading)
            Text(form.title).font(OCType.title)
            switch state {
            case .dismiss:
                Text("Dismissing without a reason ends the turn.").font(OCType.small).foregroundStyle(OCColor.textMuted)
                TextField("Reason (optional)", text: $reason, axis: .vertical).textFieldStyle(OCTextFieldStyle()).accessibilityIdentifier("dismissReason")
                Button("Dismiss question", action: dismiss).buttonStyle(OCButtonStyle(.danger)).accessibilityIdentifier("confirmDismissQuestion")
                Button("Back") { state = .editing }.buttonStyle(OCButtonStyle(.ghost))
            case .review:
                Text("Review your answers").font(OCType.heading)
                ForEach(Array(FormValidation.visibleFields(form, answers: answers).enumerated()), id: \.offset) { _, field in
                    VStack(alignment: .leading, spacing: OCSpacing.xs) {
                        Text(field.fields.title ?? field.fields.key).font(OCType.small).foregroundStyle(OCColor.textMuted)
                        Text(answerText(field.fields.key)).font(OCType.body).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button("Submit answers", action: submit).buttonStyle(OCButtonStyle(.submit)).accessibilityIdentifier("submitAnswers")
                Button("Edit answers") { state = .editing }.buttonStyle(OCButtonStyle(.neutral))
            case .sending: OCLabel("Sending answers…", icon: "status").font(OCType.small)
            case .settled: OCBadge("Already handled", tone: .success)
            default:
                if state == .failed { Text("Answers could not be sent. Review and try again.").font(OCType.small).foregroundStyle(OCColor.danger) }
                FormRenderer(form: form, answers: $answers, showErrors: state == .invalid || state == .failed)
                Button("Review answers") {
                    state = FormValidation.errors(form, answers: answers).isEmpty ? .review : .invalid
                }.buttonStyle(OCButtonStyle(.submit)).accessibilityIdentifier("reviewAnswers")
                Button("Dismiss") { state = .dismiss }.buttonStyle(OCButtonStyle(.ghost)).accessibilityIdentifier("dismissQuestion")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func answerText(_ key: String) -> String {
        guard let value = FormValidation.activeAnswers(form, answers: answers)[key] else { return "(not answered)" }
        if let values = value.arrayValue { return values.compactMap(\.stringValue).joined(separator: ", ") }
        if let text = value.stringValue { return text }
        if let flag = value.boolValue { return flag ? "Yes" : "No" }
        return value.doubleValue?.formatted() ?? "(not answered)"
    }
}

public struct QuestionSheet: View {
    let store: ReadStore
    let form: FormInfo
    let directory: String?
    @State private var state = FormSheetState.editing
    @State private var answers: [String: JSONValue]
    @State private var reason = ""
    @Environment(\.dismiss) private var dismiss
    public init(store: ReadStore, form: FormInfo, directory: String? = nil) {
        self.store = store; self.form = form; self.directory = directory
        _answers = State(initialValue: store.formDrafts[form.id] ?? FormValidation.activeAnswers(form, answers: [:]))
    }
    public var body: some View {
        NavigationStack {
            OCForm {
                QuestionContent(form: form, state: $state, answers: $answers, reason: $reason,
                                submit: { send(answer: answers) }, dismiss: { send(answer: nil) })
            }.ocNavigationTitle("Question")
                .toolbar { ToolbarItem(placement: .cancellationAction) { OCIconButton("Close", icon: "close") { dismiss() } } }
        }
            .onChange(of: answers) { _, value in store.formDrafts[form.id] = value }
            .onChange(of: store.forms.values.flatMap { $0.map(\.id) }) { _, ids in
                if !ids.contains(form.id) { state = .settled }
            }
    }
    private func send(answer: [String: JSONValue]?) {
        store.formDrafts[form.id] = answers
        store.respondToForm(form, answer: answer, reason: reason, directory: directory)
        dismiss()
    }
}
#endif
