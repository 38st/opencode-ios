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
    /// What VoiceOver says when the sheet opens: the question and the choices of its first field.
    public static func announcement(_ form: FormInfo, answers: [String: JSONValue]) -> String {
        let field = FormValidation.visibleFields(form, answers: answers).first
        var options = field?.fields.options.map(\.label) ?? []
        if field?.fields.custom == true { options.append(localized("Other", comment: "Option for typing a custom answer")) }
        let question = form.title.isEmpty ? field?.fields.title ?? "" : form.title
        return options.isEmpty ? localized("Question: \(question)", comment: "%@ is the question's title")
            : localized("Question: \(question). Options: \(options.formatted(.list(type: .or))).", comment: "VoiceOver announcement; the first %@ is the question, the second its choices")
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: OCSpacing.lg) {
            OCLabel(localized("Question", comment: "Heading of an agent question card"), icon: "bubble-5").font(OCType.heading)
            Text(form.title).font(OCType.title)
            switch state {
            case .dismiss:
                Text(localized("Dismissing without a reason ends the turn.")).font(OCType.small).foregroundStyle(OCColor.textMuted)
                TextField(localized("Reason (optional)"), text: $reason, axis: .vertical).textFieldStyle(OCTextFieldStyle()).accessibilityIdentifier("dismissReason")
                Button(localized("Dismiss question"), action: dismiss).buttonStyle(OCButtonStyle(.danger)).accessibilityIdentifier("confirmDismissQuestion")
                Button(localized("Back")) { state = .editing }.buttonStyle(OCButtonStyle(.ghost))
            case .review:
                Text(localized("Review your answers")).font(OCType.heading)
                ForEach(Array(FormValidation.visibleFields(form, answers: answers).enumerated()), id: \.offset) { _, field in
                    VStack(alignment: .leading, spacing: OCSpacing.xs) {
                        Text(field.fields.title ?? field.fields.key).font(OCType.small).foregroundStyle(OCColor.textMuted)
                        Text(answerText(field)).font(OCType.body).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button(localized("Submit answers"), action: submit).buttonStyle(OCButtonStyle(.submit)).accessibilityIdentifier("submitAnswers")
                Button(localized("Edit answers")) { state = .editing }.buttonStyle(OCButtonStyle(.neutral))
            case .sending: OCLabel(localized("Sending answers…"), icon: "status").font(OCType.small)
            case .settled: OCBadge(localized("Already handled"), tone: .success)
            default:
                if state == .failed { Text(localized("Answers could not be sent. Review and try again.")).font(OCType.small).foregroundStyle(OCColor.danger) }
                FormRenderer(form: form, answers: $answers, showErrors: state == .invalid || state == .failed)
                Button(localized("Review answers")) {
                    state = FormValidation.errors(form, answers: answers).isEmpty ? .review : .invalid
                }.buttonStyle(OCButtonStyle(.submit)).accessibilityIdentifier("reviewAnswers")
                Button(localized("Dismiss", comment: "Button that dismisses an agent question")) { state = .dismiss }.buttonStyle(OCButtonStyle(.ghost)).accessibilityIdentifier("dismissQuestion")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func answerText(_ field: FormField) -> String {
        guard let value = FormValidation.activeAnswers(form, answers: answers)[field.fields.key] else { return localized("(not answered)") }
        return FormValidation.displayText(field, value: value)
    }
}

public struct QuestionSheet: View {
    let store: ReadStore
    let form: FormInfo
    let directory: String?
    @State private var state = FormSheetState.editing
    @State private var answers: [String: JSONValue]
    @State private var reason = ""
    @State private var replied = false
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
            }.ocNavigationTitle(localized("Question", comment: "Heading of an agent question card"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { OCIconButton(localized("Close", comment: "Closes the sheet"), icon: "close") { dismiss() } } }
        }
            // A reply that failed after an earlier dismissal reopens in its failed state.
            .onAppear {
                if store.approvalErrors[form.id] != nil { state = .failed }
                OCAnnouncer.post(QuestionContent.announcement(form, answers: answers))
            }
            .onChange(of: answers) { _, value in store.formDrafts[form.id] = value }
            .onChange(of: store.forms.values.flatMap { $0.map(\.id) }) { _, ids in
                guard !ids.contains(form.id) else { return }
                // Our own answer removes the form too; only another client's answer is news.
                if !replied && state != .settled { OCAnnouncer.post(localized("Already handled")) }
                state = .settled
            }
    }
    private func send(answer: [String: JSONValue]?) {
        replied = true
        store.formDrafts[form.id] = answers
        store.respondToForm(form, answer: answer, reason: reason, directory: directory)
        dismiss()
    }
}
#endif
