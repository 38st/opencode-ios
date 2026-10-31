import Foundation
import OCModels

/// Spoken text for changes VoiceOver users would otherwise miss. Views post it through `OCAnnouncer`.
public enum TimelineAnnouncement {
    /// The run that just stopped failed when its latest turn ends in an error row.
    public static func runEnded(rows: [TimelineRow]) -> String {
        let turn = rows.lastIndex { $0.kind == .userPrompt }.map { rows[$0...] } ?? rows[...]
        return turn.contains { $0.kind == .error } ? localized("Run failed") : localized("Run finished")
    }
    /// Names only the requests that were not pending before, so a refresh does not repeat them.
    public static func pendingInput(previous: Set<String>, permissions: [PermissionRequest], forms: [FormInfo]) -> String? {
        let requests = permissions.filter { !previous.contains($0.id) }.map { $0.action.isEmpty ? localized("Permission needed: Request") : localized("Permission needed: \($0.action.capitalized)", comment: "%@ is the permission's action name") }
        let questions = forms.filter { !previous.contains($0.id) }.map { $0.title.isEmpty ? localized("Question", comment: "VoiceOver announcement for a new question") : localized("Question: \($0.title)", comment: "%@ is the question's title") }
        let parts = requests + questions
        return parts.isEmpty ? nil : parts.joined(separator: ". ")
    }
}
